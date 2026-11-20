class_name LagNetworkAdaptor
extends "res://addons/godot-rollback-netcode/RPCNetworkAdaptor.gd"

## Rollback network adaptor with two paths and optional network emulation:
## - direct: a P2P `transport` (UDP) while it is ready AND alive for that peer;
## - relay: Godot RPCs over the multiplayer peer (Nakama relay = TCP) otherwise.
## Every message picks its path when it leaves, so a match keeps running if P2P comes up or
## drops halfway. "Ready" only means the channels are open; the path behind them can still eat
## every packet (seen on phones when ICE settles late). So the link counts as alive only while
## both sides hear each other over it: a P2P packet arrived within `p2p_silence_ms` and it says
## its sender hears us too (every P2P packet carries that flag). Until then messages go over the
## relay and P2P carries a copy as a probe, which wins the link back once it works.
## Emulation (debug builds) delays outgoing messages by `delay ± jitter` (order kept), stalls
## them, and drops a share of input packets; pings are delayed too.
## Both peers must use this script (RPC methods are matched by node path and script).

## The direct link to `peer_id` started (true) or stopped (false) carrying the match.
signal ev_link_changed(peer_id: int, direct: bool)

enum Kind { PING, PING_BACK, REMOTE_START, REMOTE_STOP, INPUT }

var profile: LagProfile
## Direct link to the other peer; null or not ready = relay only.
var transport: PeerTransport
## Silence on the direct link (ms) after which it no longer counts as alive (`NetTuning`).
var p2p_silence_ms: int = 1000

var _sync_manager: Node
var _queue: Array[Dictionary] = []
var _last_due_ms: int = 0
var _rng := RandomNumberGenerator.new()
## Per peer: msec of the last P2P packet from it, whether it said it hears us, and whether the
## direct link carried the match the last time a message left (to report changes once).
var _heard_ms: Dictionary = {}
var _hears_me: Dictionary = {}
var _direct: Dictionary = {}


func _ready() -> void:
	_rng.randomize()


func attach_network_adaptor(sync_manager) -> void:
	_sync_manager = sync_manager


## The match stopped: anything still waiting in the emulation queue is for a finished match.
func stop_network_adaptor(_sync_manager_arg) -> void:
	_queue.clear()


## "p2p" when messages to this peer go over the direct link, else "relay".
func link_name(peer_id: int) -> String:
	return "p2p" if _is_direct(peer_id) else "relay"


## A ping answer can arrive after the match stopped and SyncManager forgot the peer
## (it would index its peer list and crash): drop it.
@rpc("any_peer", "unreliable")
func _remote_ping_back(msg: Dictionary) -> void:
	_deliver_ping_back(multiplayer.get_remote_sender_id(), msg)


func send_ping(peer_id: int, msg: Dictionary) -> void:
	_enqueue({"kind": Kind.PING, "peer": peer_id, "msg": msg}, false)


func send_ping_back(peer_id: int, msg: Dictionary) -> void:
	_enqueue({"kind": Kind.PING_BACK, "peer": peer_id, "msg": msg}, false)


func send_remote_start(peer_id: int) -> void:
	_enqueue({"kind": Kind.REMOTE_START, "peer": peer_id}, false)


func send_input_tick(peer_id: int, msg: PackedByteArray) -> void:
	_enqueue({"kind": Kind.INPUT, "peer": peer_id, "msg": msg}, true)


## Sent when the match stops — often because this very peer just left the room. Never delayed:
## the match scene goes away right after.
func send_remote_stop(peer_id: int) -> void:
	_send_now({"kind": Kind.REMOTE_STOP, "peer": peer_id})


func poll() -> void:
	_flush()
	_receive_direct()


func _process(_delta: float) -> void:
	_flush()
	_receive_direct()


func _enqueue(item: Dictionary, droppable: bool) -> void:
	if profile == null or not profile.is_active():
		_send_now(item)
		return
	if droppable and profile.drop_rate > 0.0 and _rng.randf() < profile.drop_rate:
		return
	var now := Time.get_ticks_msec()
	var due := profile.stall_release_ms(now) + profile.delay_ms
	if profile.jitter_ms > 0:
		due += _rng.randi_range(0, profile.jitter_ms)
	due = maxi(due, _last_due_ms)
	_last_due_ms = due
	item["due"] = due
	_queue.append(item)


func _flush() -> void:
	var now := Time.get_ticks_msec()
	while not _queue.is_empty() and int(_queue[0]["due"]) <= now:
		_send_now(_queue.pop_front())


func _send_now(item: Dictionary) -> void:
	var peer_id: int = item["peer"]
	var kind := int(item["kind"])
	var direct := _is_direct(peer_id)
	if direct != bool(_direct.get(peer_id, false)):
		_direct[peer_id] = direct
		ev_link_changed.emit(peer_id, direct)
	if transport != null and transport.is_ready(peer_id):
		var reliable := kind == Kind.REMOTE_START or kind == Kind.REMOTE_STOP
		# Start / stop must arrive once: over P2P only when it is proven, else over the relay only.
		# Pings and inputs may arrive twice (both are idempotent), so they also probe the link.
		if direct or not reliable:
			var packet := var_to_bytes([kind, item.get("msg"), _hears(peer_id)])
			if transport.send(peer_id, reliable, packet) and direct:
				return
	# Relay. The peer may already be gone (it left the room): an RPC to an unknown peer is an
	# engine error, so skip it.
	if not _is_connected(peer_id):
		return
	match kind:
		Kind.PING:
			super.send_ping(peer_id, item["msg"])
		Kind.PING_BACK:
			super.send_ping_back(peer_id, item["msg"])
		Kind.REMOTE_START:
			super.send_remote_start(peer_id)
		Kind.REMOTE_STOP:
			super.send_remote_stop(peer_id)
		Kind.INPUT:
			super.send_input_tick(peer_id, item["msg"])


func _receive_direct() -> void:
	if transport == null:
		return
	for packet in transport.receive():
		var decoded = bytes_to_var(packet[1])
		if not (decoded is Array and decoded.size() == 3):
			continue
		var peer_id: int = packet[0]
		_heard_ms[peer_id] = Time.get_ticks_msec()
		_hears_me[peer_id] = bool(decoded[2])
		match int(decoded[0]):
			Kind.PING:
				received_ping.emit(peer_id, decoded[1])
			Kind.PING_BACK:
				_deliver_ping_back(peer_id, decoded[1])
			Kind.REMOTE_START:
				received_remote_start.emit()
			Kind.REMOTE_STOP:
				received_remote_stop.emit()
			Kind.INPUT:
				received_input_tick.emit(peer_id, decoded[1])


## We got a P2P packet from `peer_id` recently: told to it in every P2P packet we send.
func _hears(peer_id: int) -> bool:
	return _heard_ms.has(peer_id) and Time.get_ticks_msec() - int(_heard_ms[peer_id]) <= p2p_silence_ms


## The direct link carries the match: open, and both sides hear each other over it.
func _is_direct(peer_id: int) -> bool:
	return transport != null and transport.is_ready(peer_id) and _hears(peer_id) and bool(_hears_me.get(peer_id, false))


func _deliver_ping_back(peer_id: int, msg: Dictionary) -> void:
	if _sync_manager != null and not _sync_manager.peers.has(peer_id):
		return
	received_ping_back.emit(peer_id, msg)


func _is_connected(peer_id: int) -> bool:
	return multiplayer != null and multiplayer.has_multiplayer_peer() and multiplayer.get_peers().has(peer_id)
