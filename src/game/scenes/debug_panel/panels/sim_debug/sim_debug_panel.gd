class_name SimDebugPanel
extends DebugTab

## "Симуляция" tab, always open:
## - live readout of the running battle's sim while "Включено": tick, phase, score, touches, ball,
##   players and the state hash (read only, so it is safe online too);
## - the determinism probe runs a reference input log through its own sim and shows whether the
##   final hash matches the recorded one: the same result on PC and phone means both compute
##   identically.
## "Сбросить" clears the probe result.

## "Включено" + "Сбросить".
@export var header: DebugHeader
## "Включено" when the tab first appears.
@export var enabled_by_default: bool = true
@export var live_label: Label
@export var probe: DeterminismProbe
@export var probe_button: Button
@export var probe_label: Label
@export var ok_color: Color = Color("#7CFF4F")
@export var fail_color: Color = Color("#FF3B3B")
## Live readout refresh period (s) while the tab is on screen.
@export var refresh_sec: float = 0.25

var _listener := EventListener.new()
var _memory: Dictionary = {}
var _battle: Node
var _refresh_left: float = 0.0


func attach(_target: Node, memory: Dictionary) -> void:
	_memory = memory
	if not _memory.has("enabled"):
		_memory["enabled"] = enabled_by_default
	header.set_enabled(bool(_memory["enabled"]))
	_listener.add(header.ev_enabled_toggled, _on_enabled_toggled)
	_listener.add(header.ev_reset_pressed, _on_reset)
	_listener.add(probe_button.pressed, _run_probe)
	_refresh_live()


func detach() -> void:
	_listener.deinit()
	_battle = null


func on_target_changed(target: Node) -> void:
	_battle = target
	_refresh_live()


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_refresh_left -= delta
	if _refresh_left > 0.0:
		return
	_refresh_left = refresh_sec
	_refresh_live()


func _on_enabled_toggled(on: bool) -> void:
	_memory["enabled"] = on
	log_channel.info("sim_readout", {"on": on})
	_refresh_live()


func _on_reset() -> void:
	probe_label.text = ""
	probe_label.remove_theme_color_override("font_color")
	_refresh_live()


func _refresh_live() -> void:
	if not bool(_memory.get("enabled", true)):
		live_label.text = "Выключено."
		return
	var sim: VolleySim = null
	if is_instance_valid(_battle):
		sim = _battle.get("_sim") as VolleySim
	if sim == null:
		live_label.text = "Боя нет."
		return
	live_label.text = format_state(sim)


## Several readable lines about the sim state (numbers rounded for the eye).
static func format_state(sim: VolleySim) -> String:
	var state := sim.state
	var scores: Array[String] = []
	for score in state.scores:
		scores.append(str(score))
	var touches := "касаний нет"
	if state.touch_team >= 0:
		touches = "касания: команда %d ×%d" % [state.touch_team + 1, state.touch_count]
	var lines: Array[String] = [
		"тик %d · %s %d тик. · счёт %s" % [state.tick, String(VolleySim.Phase.keys()[state.phase]).to_lower(), state.phase_ticks, ":".join(scores)],
		"подаёт команда %d · %s" % [state.serving_team + 1, touches],
	]
	for ball in state.balls:
		lines.append("мяч (%.2f, %.2f) v(%.2f, %.2f)%s" % [ball.x, ball.y, ball.vx, ball.vy, " висит" if ball.frozen else ""])
	for i in state.players.size():
		var player := state.players[i]
		lines.append("блоб %d (к.%d) (%.2f, %.2f) v(%.2f, %.2f)" % [i, player.team + 1, player.x, player.y, player.vx, player.vy])
	lines.append("хеш состояния %d" % sim.state_hash())
	return "\n".join(lines)


func _run_probe() -> void:
	if probe == null:
		return
	var result := probe.run()
	log_channel.info("determinism_probe", result)
	var ok := bool(result.get("ok", false))
	probe_label.text = "%s хеш %d (эталон %d)" % ["✓ совпал" if ok else "✗ НЕ совпал", int(result.get("hash", 0)), int(result.get("expected", 0))]
	probe_label.add_theme_color_override("font_color", ok_color if ok else fail_color)
