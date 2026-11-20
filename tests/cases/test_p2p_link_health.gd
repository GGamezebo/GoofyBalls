extends TestCase

## LagNetworkAdaptor trusts the direct (P2P) link only while both sides hear each other over it.
## An open but silent link (the W2X3 abort: P2P "ready", every packet lost) must hand the match
## back to the relay and keep probing; one-shot start/stop never travel twice.

const PEER := 2


class FakeTransport extends PeerTransport:
	var ready := true
	## [reliable, decoded Array] for every packet the adaptor sent.
	var sent: Array = []
	## [peer_id, PackedByteArray] waiting for the adaptor's receive().
	var inbox: Array = []

	func is_ready(peer_id: int) -> bool:
		return ready and peer_id == PEER

	func send(_peer_id: int, reliable: bool, data: PackedByteArray) -> bool:
		sent.append([reliable, bytes_to_var(data)])
		return true

	func receive() -> Array:
		var out := inbox
		inbox = []
		return out


func _make() -> Array:
	var adaptor := LagNetworkAdaptor.new()
	var transport := FakeTransport.new()
	adaptor.transport = transport
	tree.root.add_child(adaptor) # relay = offline multiplayer: no peers, RPCs are skipped
	return [adaptor, transport]


func _from_peer(transport: FakeTransport, kind: int, hears_us: bool) -> void:
	transport.inbox.append([PEER, var_to_bytes([kind, PackedByteArray([1]), hears_us])])


func test_open_but_silent_link_is_not_trusted() -> void:
	var made := _make()
	var adaptor: LagNetworkAdaptor = made[0]
	var transport: FakeTransport = made[1]
	expect_eq(adaptor.link_name(PEER), "relay", "nothing heard yet: relay")
	adaptor.send_input_tick(PEER, PackedByteArray([7]))
	expect_eq(transport.sent.size(), 1, "input still probes the open link")
	expect(transport.sent.size() == 1 and transport.sent[0][1][2] == false, "probe says we hear nothing")
	adaptor.send_remote_start(PEER)
	expect_eq(transport.sent.size(), 1, "remote start is not sent over an unproven link")
	adaptor.queue_free()


func test_link_carries_match_once_both_sides_hear() -> void:
	var made := _make()
	var adaptor: LagNetworkAdaptor = made[0]
	var transport: FakeTransport = made[1]
	var changes: Array = []
	adaptor.ev_link_changed.connect(func(peer_id: int, direct: bool) -> void: changes.append([peer_id, direct]))
	var inputs: Array = []
	adaptor.received_input_tick.connect(func(peer_id: int, _msg) -> void: inputs.append(peer_id))

	_from_peer(transport, LagNetworkAdaptor.Kind.INPUT, false)
	adaptor.poll()
	expect_eq(inputs, [PEER], "probe input is delivered")
	expect_eq(adaptor.link_name(PEER), "relay", "peer does not hear us yet: relay")

	_from_peer(transport, LagNetworkAdaptor.Kind.INPUT, true)
	adaptor.poll()
	expect_eq(adaptor.link_name(PEER), "p2p", "both sides hear each other: p2p")
	adaptor.send_input_tick(PEER, PackedByteArray([7]))
	expect(transport.sent.size() == 1 and transport.sent[0][1][2] == true, "packet says we hear the peer")
	expect_eq(changes, [[PEER, true]], "switch to the direct link is reported once")
	adaptor.send_remote_start(PEER)
	expect(transport.sent.size() == 2 and transport.sent[1][0] == true, "remote start goes reliable over a proven link")
	adaptor.queue_free()


func test_silence_hands_match_back_to_relay() -> void:
	var made := _make()
	var adaptor: LagNetworkAdaptor = made[0]
	var transport: FakeTransport = made[1]
	adaptor.p2p_silence_ms = 50
	var changes: Array = []
	adaptor.ev_link_changed.connect(func(peer_id: int, direct: bool) -> void: changes.append([peer_id, direct]))
	_from_peer(transport, LagNetworkAdaptor.Kind.PING, true)
	adaptor.poll()
	adaptor.send_input_tick(PEER, PackedByteArray([7]))
	expect_eq(adaptor.link_name(PEER), "p2p", "fresh link: p2p")

	# Wall-clock wait: the adaptor measures silence in real msec, and a SceneTree timer follows
	# Engine.time_scale (other tests may change it).
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 120:
		await tree.process_frame
	expect_eq(adaptor.link_name(PEER), "relay", "silent for longer than p2p_silence_ms: relay")
	adaptor.send_input_tick(PEER, PackedByteArray([8]))
	expect_eq(changes, [[PEER, true], [PEER, false]], "fall back to the relay is reported")
	var last: Array = transport.sent[transport.sent.size() - 1]
	expect(last[1][2] == false, "probe tells the peer we stopped hearing it")

	_from_peer(transport, LagNetworkAdaptor.Kind.INPUT, true)
	adaptor.poll()
	expect_eq(adaptor.link_name(PEER), "p2p", "link heard again: back to p2p")
	adaptor.queue_free()


func test_closed_link_is_relay() -> void:
	var made := _make()
	var adaptor: LagNetworkAdaptor = made[0]
	var transport: FakeTransport = made[1]
	_from_peer(transport, LagNetworkAdaptor.Kind.INPUT, true)
	adaptor.poll()
	transport.ready = false
	expect_eq(adaptor.link_name(PEER), "relay", "channels closed: relay")
	adaptor.send_input_tick(PEER, PackedByteArray([7]))
	expect_eq(transport.sent.size(), 0, "nothing goes into a closed link")
	adaptor.queue_free()
