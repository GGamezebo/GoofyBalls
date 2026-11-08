extends IScene

## App/Online/Room context: one friend room by code, from create / join until it closes.
## The HFSM mounts it on `ev.open_room` and unmounts it on `ev.open_menu` / `ev.close_room`,
## so leaving the room is never another scene's job: `deinit` always drops the connection.
## Payload: {"code": ""} creates a room, {"code": "ABCD"} joins one. F6: creates a room.
## Talks out only through OnlineEvents (answers to the menu / results) and RootEvents (battle).

@export var root_events: RootEvents
@export var online_events: OnlineEvents
@export var online_config: OnlineConfig
## Template for an online 1×1: peers and names are filled per match.
@export var online_setup: MatchSetup
@export var log_settings: LogSettings
## Where the battle picks up the direct link to the opponent.
@export var net_link: NetLink
@export var room_flow: RoomFlow

var _listener := EventListener.new()
var _log: LogChannel
var _closing: bool = false


func initialize(data: Dictionary) -> void:
	_log = LogChannel.new("room", log_settings)
	room_flow.setup(online_config, _log)
	_listener.add(online_events.ev_rematch_request, room_flow.request_rematch)
	_listener.add(room_flow.ev_room_created, func(code: String) -> void: online_events.ev_room_created.emit(code))
	_listener.add(room_flow.ev_status, func(text: String) -> void: online_events.ev_room_status.emit(text))
	_listener.add(room_flow.ev_error, _on_error)
	_listener.add(room_flow.ev_rematch_status, func(text: String) -> void: online_events.ev_rematch_status.emit(text))
	_listener.add(room_flow.ev_opponent_left, _on_opponent_left)
	_listener.add(room_flow.ev_match_ready, _on_match_ready)
	_listener.add(room_flow.ev_transport_changed, _on_transport_changed)

	var code := str(data.get("code", ""))
	_log.info("room_open", {"mode": "join" if not code.is_empty() else "create", "server": online_config.address()})
	if code.is_empty():
		room_flow.create_room()
	else:
		room_flow.join_room(code)


func deinit() -> void:
	_log.info("room_close")
	_listener.deinit()
	room_flow.leave()
	net_link.transport = null
	super.deinit()


## RoomFlow already dropped the connection (no server, room full, socket lost): close the state.
func _on_error(text: String) -> void:
	online_events.ev_room_error.emit(text)
	_close()


## During a match RoomFlow leaves right after this signal; while waiting (host) the room stays
## open for the next friend. Checked deferred, once RoomFlow has decided.
func _on_opponent_left() -> void:
	online_events.ev_opponent_left.emit()
	_close_if_left.call_deferred()


func _close_if_left() -> void:
	if room_flow.is_idle():
		_close()


func _close() -> void:
	if _closing:
		return
	_closing = true
	add_event("ev.close_room")


func _on_transport_changed(transport: PeerTransport) -> void:
	net_link.transport = transport


func _on_match_ready(info: Dictionary) -> void:
	var setup := online_setup.duplicate(true) as MatchSetup
	var slots := setup.slots()
	slots[0].peer_id = int(info["host_peer"])
	slots[0].display_name = str(info["host_name"])
	slots[1].peer_id = int(info["guest_peer"])
	slots[1].display_name = str(info["guest_name"])
	setup.match_seed = int(info["seed"])
	_log.info("start_online_match", {"round": info["round"], "seed": setup.match_seed})
	root_events.ev_start_game.emit({"match_setup": setup})
