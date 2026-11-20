class_name OnlineAbilitiesDebugTab
extends DebugTab

## "Способности" tab of online battles: only the powers that keep the peers in lockstep.
## - Autopilot: a bot plays my slots. Its decisions go out as my input, so the opponent receives
##   them like key presses and both peers simulate the same thing.
## Everything else of the offline tab (speed, pause, ball, trampoline, restart) edits the sim on
## this peer only and would desync the match, so it is not here.
## Works by swapping the `sample` callable of my `RollbackInput` nodes (the session binds them
## once in `setup`); `detach` puts them back. The choice carries over to the next online battle.

@export var autopilot_toggle: CheckButton

var _listener := EventListener.new()
var _sim: VolleySim
var _memory: Dictionary = {}
## My input nodes, the sample each had before, and the bot that plays its slot.
var _nodes: Array[RollbackInput] = []
var _own_samples: Array[Callable] = []
var _bots: Array[AiOpponent] = []


func accepts(target: Node) -> bool:
	var session := target.get("_session") as MatchSession
	return session != null and session.is_online() and target.get("_sim") is VolleySim


func attach(target: Node, memory: Dictionary) -> void:
	_sim = target.get("_sim") as VolleySim
	_memory = memory
	var ai_profile := target.get("ai_profile") as AiProfile
	var inputs: Array = target.get("_session").get("_inputs")
	for slot in inputs.size():
		var node := inputs[slot] as RollbackInput
		if node == null or not node.sample.is_valid():
			continue # another peer's slot
		_nodes.append(node)
		_own_samples.append(node.sample)
		_bots.append(AiOpponent.new(slot, ai_profile))
		node.sample = _sample.bind(_nodes.size() - 1)
	autopilot_toggle.set_pressed_no_signal(bool(_memory.get("autopilot", false)))
	autopilot_toggle.disabled = _nodes.is_empty()
	_listener.add(autopilot_toggle.toggled, _set_autopilot)


func detach() -> void:
	_listener.deinit()
	for i in _nodes.size():
		if is_instance_valid(_nodes[i]):
			_nodes[i].sample = _own_samples[i]
	_nodes.clear()
	_own_samples.clear()
	_bots.clear()


func _sample(index: int) -> Dictionary:
	if bool(_memory.get("autopilot", false)):
		return _bots[index].decide(_sim.state, _sim.cfg["physics"], _sim.cfg["arena"])
	return _own_samples[index].call()


func _set_autopilot(on: bool) -> void:
	_memory["autopilot"] = on
	log_channel.info("autopilot", {"on": on, "online": true, "tick": _sim.state.tick})
