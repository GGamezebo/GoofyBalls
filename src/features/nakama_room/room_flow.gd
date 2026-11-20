class_name RoomFlow
extends Node

## Friend room by code over the Nakama relay:
## sign in (device id) → RPC `room_create` / `room_join` (server returns code, match name, seed)
## → join the relayed named match through `NakamaMultiplayerBridge` (first in = host = peer 1)
## → peers say hello → the host sets up a direct WebRTC link (UDP; offer / answer / ICE go as
## room RPCs over the relay) and starts the match once it is open, or after `p2p_timeout_sec`
## on the relay → the host starts every rematch for both.
## The connection lives until `leave()`, so a rematch needs no new room. Two players max.

## Texts for these codes belong to the UI that shows them; the feature only reports what happened.
signal ev_room_created(code: String)
signal ev_status(status: RoomStatus)
## The room is gone (the connection was already dropped).
signal ev_error(error: RoomError)
signal ev_match_ready(room_match: RoomMatch)
signal ev_rematch_status(status: RematchStatus)
signal ev_opponent_left
## The direct link to the opponent appeared (or went away: null).
signal ev_transport_changed(transport: PeerTransport)

## Room lifecycle (`core/lib/fsm`): IDLE → CONNECTING → WAITING → IN_MATCH (rematches stay there),
## LEAVE from anywhere back to IDLE. Internal to the protocol: the app only sees `ev_*` signals.
enum RoomState { IDLE, CONNECTING, WAITING, IN_MATCH }

const EV_CONNECT := "connect"
const EV_JOINED := "joined"
const EV_START := "start"
const EV_LEAVE := "leave"

## Progress of opening a room.
enum RoomStatus {
	CONNECTING_SERVER,
	CREATING_ROOM,
	JOINING_FRIEND,
	## Guest is in the match, the host has not started it yet.
	WAITING_HOST,
	FRIEND_JOINED,
	## Host: the friend left before the match, the room waits for them again.
	FRIEND_LEFT,
	CONNECTING_DIRECT,
}

## Why the room could not be opened or was lost.
enum RoomError {
	NONE,
	## Sign-in or socket failed: the server at `OnlineConfig.address()` is unreachable.
	NO_SERVER,
	CREATE_FAILED,
	ROOM_NOT_FOUND,
	JOIN_FAILED,
	TOO_MANY_ATTEMPTS,
	MATCH_JOIN_FAILED,
	SERVER_LOST,
	ROOM_FULL,
}

enum RematchStatus {
	OPPONENT_GONE,
	WAITING_OPPONENT,
	OPPONENT_WANTS,
}

## Error codes of the server RPC `room_join` (server/).
const SERVER_ROOM_NOT_FOUND := "room_not_found"
const SERVER_RATE_LIMITED := "rate_limited"
const SERVER_TOO_MANY_ATTEMPTS := "too_many_attempts"

## Part of the protocol, not a tuning knob: both peers derive every round's seed with it.
const SEED_STEP := 7919

@export var nakama_node: Node

var client := OnlineClient.new()
var display_name: String = ""

var _config: OnlineConfig
var _log: LogChannel
var _fsm := FSM.new({
	"initial": {"state": RoomState.IDLE},
	"transitions": [
		{"src": RoomState.IDLE, "dst": RoomState.CONNECTING, "event": EV_CONNECT},
		{"src": RoomState.CONNECTING, "dst": RoomState.WAITING, "event": EV_JOINED},
		# A guest can get the host's start while its own join is still settling.
		{"src": [RoomState.CONNECTING, RoomState.WAITING, RoomState.IN_MATCH], "dst": RoomState.IN_MATCH, "event": EV_START},
		{"src": FSM.ALL_STATES, "dst": RoomState.IDLE, "event": EV_LEAVE},
	],
})
var _socket: NakamaSocket
var _bridge: NakamaMultiplayerBridge
var _code: String = ""
var _base_seed: int = 0
var _round: int = 0
var _opponent_peer: int = 0
var _names: Dictionary = {}
var _rematch: Dictionary = {}
var _profile: String = ""
var _transport: WebRTCTransport
## Seconds the host still waits for the direct link before starting on the relay (-1 = not waiting).
var _p2p_wait_left: float = -1.0
var _p2p_started_ms: int = 0


func _process(delta: float) -> void:
	if _transport != null:
		_transport.poll()
	if _p2p_wait_left < 0.0:
		return
	_p2p_wait_left -= delta
	var linked := _transport != null and _transport.is_ready(_opponent_peer)
	if linked or _p2p_wait_left <= 0.0:
		_p2p_wait_left = -1.0
		if not linked:
			_log.warn("p2p_timeout", {"state": _transport.connection_state() if _transport != null else "none"})
		if _is(RoomState.WAITING) and multiplayer.is_server() and _opponent_peer != 0:
			_start_round()


func setup(config: OnlineConfig, log_channel: LogChannel) -> void:
	_config = config
	_log = log_channel
	_fsm.ev_state_changed.connect(func(from: int, to: int) -> void:
		_log.info("room_state", {"from": _room_state_name(from), "to": _room_state_name(to)}))
	_profile = _cmdline_profile()
	client.setup(nakama_node, config)
	var device := OnlineClient.device_id(_profile)
	display_name = "Игрок %s" % device.right(4).to_upper()


func _is(state: RoomState) -> bool:
	return _fsm.get_current_state_id() == state


func _state_name() -> String:
	return _room_state_name(_fsm.get_current_state_id())


## RoomFlow passes no state objects (the FSM creates plain ones), so it names its enum itself.
static func _room_state_name(state: int) -> String:
	return RoomState.keys()[state].to_lower() if state >= 0 and state < RoomState.size() else str(state)


func is_idle() -> bool:
	return _is(RoomState.IDLE)


func create_room() -> void:
	if not _is(RoomState.IDLE):
		return
	_fsm.add_event(EV_CONNECT)
	_log.info("room_create_requested", {"server": _config.address()})
	if not await _connect():
		return
	ev_status.emit(RoomStatus.CREATING_ROOM)
	var result := await client.rpc_async("room_create", {})
	if not _is(RoomState.CONNECTING):
		return
	if not bool(result.get("ok", false)):
		_fail("room_create_failed", RoomError.CREATE_FAILED, {"error": client.last_error})
		return
	_code = str(result["code"])
	_base_seed = int(result.get("seed", randi()))
	_log.info("room_created", {"code": _code})
	ev_room_created.emit(_code)
	if await _join_match(str(result["match_name"])) and _is(RoomState.CONNECTING):
		_fsm.add_event(EV_JOINED)


func join_room(code: String) -> void:
	if not _is(RoomState.IDLE):
		return
	_fsm.add_event(EV_CONNECT)
	_log.info("room_join_requested", {"code": code, "server": _config.address()})
	if not await _connect():
		return
	var result := await client.rpc_async("room_join", {"code": code})
	if not _is(RoomState.CONNECTING):
		return
	if not bool(result.get("ok", false)):
		var error := str(result.get("error", client.last_error))
		_fail("room_join_failed", _join_error(error), {"code": code, "error": error})
		return
	_code = code
	_base_seed = int(result.get("seed", 0))
	ev_status.emit(RoomStatus.JOINING_FRIEND)
	if await _join_match(str(result["match_name"])) and _is(RoomState.CONNECTING):
		_fsm.add_event(EV_JOINED)


func request_rematch() -> void:
	if not _is(RoomState.IN_MATCH) or _opponent_peer == 0:
		ev_rematch_status.emit(RematchStatus.OPPONENT_GONE)
		return
	_rematch[multiplayer.get_unique_id()] = true
	_rpc_rematch.rpc_id(_opponent_peer)
	ev_rematch_status.emit(RematchStatus.WAITING_OPPONENT)
	_log.info("rematch_requested", {"round": _round})
	_check_rematch()


## Synchronous on purpose: the room scene is freed right after this (HFSM unmount), so nothing
## may wait on the server here. Closing the socket is enough — Nakama drops our presence from
## the relayed match and the other peer gets `peer_disconnected`.
func leave() -> void:
	if _is(RoomState.IDLE) and _socket == null:
		return
	_log.info("room_leave", {"code": _code, "state": _state_name()})
	_fsm.add_event(EV_LEAVE)
	_opponent_peer = 0
	_names.clear()
	_rematch.clear()
	_p2p_wait_left = -1.0
	_close_transport()
	var socket := _socket
	_bridge = null
	_socket = null
	# On app quit the node is already out of the tree: no multiplayer API, just drop the socket.
	if is_inside_tree():
		_disconnect_multiplayer_signals()
		multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	if socket != null:
		socket.close()


# --- connection -------------------------------------------------------------------------

func _connect() -> bool:
	ev_status.emit(RoomStatus.CONNECTING_SERVER)
	if not await client.sign_in_async(_profile):
		_fail("sign_in_failed", RoomError.NO_SERVER, {"error": client.last_error, "server": _config.address()})
		return false
	if not _is(RoomState.CONNECTING):
		return false
	_log.info("signed_in", {"user": client.session.user_id})
	_socket = nakama_node.create_socket_from(client.nakama)
	_socket.closed.connect(_on_socket_closed)
	var connected = await _socket.connect_async(client.session)
	if connected != null and connected.is_exception():
		_fail("socket_failed", RoomError.NO_SERVER, {"error": str(connected.get_exception().message), "server": _config.address()})
		return false
	_bridge = NakamaMultiplayerBridge.new(_socket)
	multiplayer.multiplayer_peer = _bridge.multiplayer_peer
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	_log.info("socket_connected")
	return true


func _join_match(match_name: String) -> bool:
	var outcome := {"done": false, "ok": false, "error": ""}
	var on_joined := func() -> void:
		outcome["done"] = true
		outcome["ok"] = true
	var on_error := func(exception) -> void:
		outcome["done"] = true
		outcome["error"] = str(exception.message) if exception != null else "join error"
	_bridge.match_joined.connect(on_joined, CONNECT_ONE_SHOT)
	_bridge.match_join_error.connect(on_error, CONNECT_ONE_SHOT)
	_bridge.join_named_match(match_name)
	var waited := 0.0
	while not bool(outcome["done"]) and waited < _config.join_timeout_sec:
		await get_tree().process_frame
		waited += get_process_delta_time()
		if _bridge == null:
			return false
	if not bool(outcome["ok"]):
		_fail("match_join_failed", RoomError.MATCH_JOIN_FAILED, {"error": outcome["error"] if outcome["done"] else "timeout"})
		return false
	_log.info("match_joined", {"code": _code, "peer": multiplayer.get_unique_id(), "host": multiplayer.is_server()})
	if not multiplayer.is_server():
		ev_status.emit(RoomStatus.WAITING_HOST)
	return true


func _on_peer_connected(peer_id: int) -> void:
	if multiplayer.is_server():
		if _opponent_peer != 0 and _opponent_peer != peer_id:
			_log.warn("room_full_rejected", {"peer": peer_id})
			_rpc_room_full.rpc_id(peer_id)
			return
		_opponent_peer = peer_id
	elif peer_id == 1:
		_opponent_peer = 1
	else:
		return
	_log.info("peer_connected", {"peer": peer_id})
	ev_status.emit(RoomStatus.FRIEND_JOINED)
	_rpc_hello.rpc_id(peer_id, display_name)


func _on_peer_disconnected(peer_id: int) -> void:
	if peer_id != _opponent_peer:
		return
	_log.warn("opponent_left", {"peer": peer_id, "state": _state_name()})
	_opponent_peer = 0
	_p2p_wait_left = -1.0
	_close_transport()
	ev_opponent_left.emit()
	if _is(RoomState.WAITING) and multiplayer.is_server():
		ev_status.emit(RoomStatus.FRIEND_LEFT)
	elif _is(RoomState.IN_MATCH):
		leave()


func _on_socket_closed() -> void:
	if _is(RoomState.IDLE):
		return
	_log.warn("socket_closed", {"state": _state_name()})
	var was_in_match := _is(RoomState.IN_MATCH)
	if was_in_match:
		ev_opponent_left.emit()
	leave()
	if not was_in_match:
		ev_error.emit(RoomError.SERVER_LOST)


func _disconnect_multiplayer_signals() -> void:
	if multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.disconnect(_on_peer_connected)
	if multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.disconnect(_on_peer_disconnected)


static func _join_error(server_error: String) -> RoomError:
	match server_error:
		SERVER_ROOM_NOT_FOUND:
			return RoomError.ROOM_NOT_FOUND
		SERVER_RATE_LIMITED, SERVER_TOO_MANY_ATTEMPTS:
			return RoomError.TOO_MANY_ATTEMPTS
	return RoomError.JOIN_FAILED


func _fail(event: String, error: RoomError, kv: Dictionary) -> void:
	_log.warn(event, kv)
	leave()
	ev_error.emit(error)


# --- room RPCs (same node path on both peers) ---------------------------------------------

@rpc("any_peer", "call_remote", "reliable")
func _rpc_hello(peer_name: String) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != _opponent_peer and not (sender == 1 and not multiplayer.is_server()):
		return
	_names[sender] = peer_name.left(_config.max_name_length)
	_log.info("hello", {"peer": sender})
	if multiplayer.is_server() and _is(RoomState.WAITING):
		_begin_p2p()


# --- direct link (WebRTC) ---------------------------------------------------------------

## Host: ask the guest to prepare its side, then offer. The match starts from `_process`.
func _begin_p2p() -> void:
	if not _config.p2p_enabled or not WebRTCTransport.is_supported():
		_log.info("p2p_skipped", {"enabled": _config.p2p_enabled, "supported": WebRTCTransport.is_supported()})
		_start_round()
		return
	_p2p_started_ms = Time.get_ticks_msec()
	_p2p_wait_left = _config.p2p_timeout_sec
	ev_status.emit(RoomStatus.CONNECTING_DIRECT)
	_log.info("p2p_begin", {"peer": _opponent_peer})
	_rpc_p2p_prepare.rpc_id(_opponent_peer)


@rpc("authority", "call_remote", "reliable")
func _rpc_p2p_prepare() -> void:
	_p2p_started_ms = Time.get_ticks_msec()
	if _open_transport(1):
		_rpc_p2p_prepared.rpc_id(1)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_p2p_prepared() -> void:
	if multiplayer.get_remote_sender_id() != _opponent_peer or not multiplayer.is_server():
		return
	if _open_transport(_opponent_peer):
		_transport.make_offer()


@rpc("any_peer", "call_remote", "reliable")
func _rpc_p2p_signal(message: Dictionary) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if _transport != null and sender == _transport.remote_peer_id:
		_transport.on_signal_in(message)


func _open_transport(remote_peer: int) -> bool:
	_close_transport()
	var transport := WebRTCTransport.new()
	if not WebRTCTransport.is_supported() or not transport.open(remote_peer, _config.stun_servers):
		_log.warn("p2p_unavailable", {"peer": remote_peer})
		return false
	transport.ev_signal_out.connect(_send_signal.bind(remote_peer))
	transport.ev_ready.connect(_on_transport_ready.bind(remote_peer))
	transport.ev_closed.connect(_on_transport_closed.bind(remote_peer))
	_transport = transport
	ev_transport_changed.emit(transport)
	return true


func _send_signal(message: Dictionary, remote_peer: int) -> void:
	if _opponent_peer != 0 and is_inside_tree():
		_rpc_p2p_signal.rpc_id(remote_peer, message)


func _on_transport_ready(remote_peer: int) -> void:
	_log.info("p2p_ready", {"peer": remote_peer, "ms": Time.get_ticks_msec() - _p2p_started_ms})


func _on_transport_closed(remote_peer: int) -> void:
	_log.warn("p2p_closed", {"peer": remote_peer})


func _close_transport() -> void:
	if _transport == null:
		return
	_transport.close()
	_transport = null
	ev_transport_changed.emit(null)


@rpc("authority", "call_remote", "reliable")
func _rpc_start(round_index: int, host_name: String, guest_name: String) -> void:
	_round = round_index
	_names[1] = host_name
	_names[multiplayer.get_unique_id()] = guest_name
	_emit_ready(host_name, guest_name)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_rematch() -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != _opponent_peer:
		return
	_rematch[sender] = true
	ev_rematch_status.emit(RematchStatus.OPPONENT_WANTS)
	_check_rematch()


@rpc("authority", "call_remote", "reliable")
func _rpc_room_full() -> void:
	_log.warn("room_full")
	leave()
	ev_error.emit(RoomError.ROOM_FULL)


func _check_rematch() -> void:
	if not multiplayer.is_server() or _opponent_peer == 0:
		return
	if _rematch.get(1, false) and _rematch.get(_opponent_peer, false):
		_round += 1
		_start_round()


func _start_round() -> void:
	var host_name := display_name
	var guest_name := str(_names.get(_opponent_peer, "Гость"))
	_rpc_start.rpc_id(_opponent_peer, _round, host_name, guest_name)
	_emit_ready(host_name, guest_name)


func _emit_ready(host_name: String, guest_name: String) -> void:
	_fsm.add_event(EV_START)
	_rematch.clear()
	var guest_peer := _opponent_peer if multiplayer.is_server() else multiplayer.get_unique_id()
	var room_match := RoomMatch.new()
	room_match.match_seed = (_base_seed + _round * SEED_STEP) & 0x7FFFFFFF
	room_match.round_index = _round
	room_match.peer_ids = [1, guest_peer]
	room_match.names = [host_name, guest_name]
	_log.info("match_ready", {"code": _code, "round": _round, "guest_peer": guest_peer})
	ev_match_ready.emit(room_match)


static func _cmdline_profile() -> String:
	for arg in OS.get_cmdline_user_args() + OS.get_cmdline_args():
		if arg.begins_with("--profile="):
			return arg.trim_prefix("--profile=")
	return ""
