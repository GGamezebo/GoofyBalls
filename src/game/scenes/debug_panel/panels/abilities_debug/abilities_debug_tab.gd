class_name AbilitiesDebugTab
extends DebugTab

## "Способности" tab of offline battles: debug powers over the running match.
## - Time: speed (the engine's physics tick rate and `time_scale` scaled together: the sim steps
##   once per physics tick with a fixed DT, views and FX slow down with it), pause, one-tick steps.
## - Ball: put it above my blob, hang it in the air until someone touches it, trampoline floor
##   (a rally never ends on the floor).
## - Players: autopilot (a bot plays my slots).
## - Match: drop the ball on a team's side (that team loses the rally), restart the match.
## "Включено" off turns every power off at once (×1, no pause, no hanging ball, no trampoline or
## autopilot) and keeps the choices for when it is on again; "Сбросить" clears the choices.
## Works by wrapping the session's `_sample` / `_step` callables and editing `SimState` between
## ticks; `detach` undoes it all. Speed, trampoline and autopilot carry over to the next battle.
## Online battles get no such tab: every change would desync the match.

## "Включено" + "Сбросить".
@export var header: DebugHeader
## "Включено" when the tab first appears.
@export var enabled_by_default: bool = true
@export var speeds: Array[float] = [0.1, 0.25, 0.5, 1.0, 2.0, 3.0]
## One button per entry of `speeds`; extra buttons are hidden.
@export var speed_buttons: Array[Button] = []
@export var status_label: Label
@export var pause_button: Button
@export var step_button: Button
@export var ball_to_me_button: Button
@export var hang_toggle: CheckButton
@export var trampoline_toggle: CheckButton
@export var autopilot_toggle: CheckButton
## Holds one "drop the ball on team N" button per team.
@export var drop_box: Container
@export var drop_template: PackedScene
@export var restart_button: Button
## Height above my blob the ball is put at (m).
@export var ball_to_me_height: float = 2.6
## Trampoline floor: share of the falling speed given back, and the least upward speed (m/s).
@export_range(0.0, 2.0) var trampoline_bounce: float = 0.9
@export var trampoline_min_up: float = 7.0
## Trampoline catches the ball this many ticks of fall before the floor line.
@export var trampoline_lead_ticks: float = 2.0

var _listener := EventListener.new()
var _battle: Node
var _session: LocalSession
var _sim: VolleySim
var _view: MatchView
var _memory: Dictionary = {}
var _orig_step: Callable
var _orig_sample: Callable
## My slot → bot that plays it while the autopilot is on.
var _bots: Dictionary = {}
var _local_slots: Array[int] = []
var _paused: bool = false
var _hanging: bool = false
var _hang_pos := Vector2.ZERO
var _hang_touch: int = 0
var _hang_point: int = 0


func accepts(target: Node) -> bool:
	return target.get("_session") is LocalSession and target.get("_sim") is VolleySim


func attach(target: Node, memory: Dictionary) -> void:
	_battle = target
	_session = target.get("_session") as LocalSession
	_sim = target.get("_sim") as VolleySim
	_view = target.get("match_view") as MatchView
	_memory = memory
	if not _memory.has("base_ticks"):
		_memory["base_ticks"] = Engine.physics_ticks_per_second
	if not _memory.has("enabled"):
		_memory["enabled"] = enabled_by_default
	var inputs := target.get("_inputs") as MatchInputs
	_local_slots = inputs.local_slots() if inputs != null else []
	var ai_profile := target.get("ai_profile") as AiProfile
	for slot in _local_slots:
		_bots[slot] = AiOpponent.new(slot, ai_profile)

	_orig_step = _session._step
	_orig_sample = _session._sample
	_session._step = _debug_step
	_session._sample = _debug_sample

	for i in speed_buttons.size():
		speed_buttons[i].visible = i < speeds.size()
		if i < speeds.size():
			speed_buttons[i].text = "×%s" % str(speeds[i])
			_listener.add(speed_buttons[i].pressed, _set_speed.bind(speeds[i]))
	for team in _sim.team_count():
		var button := drop_template.instantiate() as Button
		button.text = "Уронить мяч к команде %d" % (team + 1)
		drop_box.add_child(button)
		_listener.add(button.pressed, _drop_ball.bind(team))
	trampoline_toggle.set_pressed_no_signal(bool(_memory.get("trampoline", false)))
	autopilot_toggle.set_pressed_no_signal(bool(_memory.get("autopilot", false)))
	header.set_enabled(_enabled())
	_listener.add(header.ev_enabled_toggled, _on_enabled_toggled)
	_listener.add(header.ev_reset_pressed, _on_reset)
	_listener.add(pause_button.toggled, _set_paused)
	_listener.add(step_button.pressed, _step_once)
	_listener.add(ball_to_me_button.pressed, _ball_to_me)
	_listener.add(hang_toggle.toggled, _set_hang)
	_listener.add(trampoline_toggle.toggled, _set_flag.bind("trampoline"))
	_listener.add(autopilot_toggle.toggled, _set_flag.bind("autopilot"))
	_listener.add(restart_button.pressed, _restart)
	_apply_speed()
	_refresh_controls()


func detach() -> void:
	_listener.deinit()
	if is_instance_valid(_session):
		_session._step = _orig_step
		_session._sample = _orig_sample
		if _paused:
			_session.set_physics_process(_session._running)
	_paused = false
	Engine.physics_ticks_per_second = int(_memory.get("base_ticks", Engine.physics_ticks_per_second))
	Engine.time_scale = 1.0
	_battle = null


func _process(_delta: float) -> void:
	if not is_visible_in_tree() or _sim == null:
		return
	var parts: Array[String] = ["×%s" % str(_memory.get("speed", 1.0)) if _enabled() else "выключено",
		"тик %d" % _sim.state.tick, String(VolleySim.Phase.keys()[_sim.state.phase]).to_lower()]
	if _paused:
		parts.append("ПАУЗА")
	if _hanging:
		parts.append("мяч подвешен")
	status_label.text = " · ".join(parts)


# --- on / off / reset ------------------------------------------------------------------------

func _enabled() -> bool:
	return bool(_memory.get("enabled", true))


func _on_enabled_toggled(on: bool) -> void:
	_memory["enabled"] = on
	if not on:
		_stop_live_powers()
	_apply_speed()
	_refresh_controls()
	log_channel.info("abilities", {"on": on})


func _on_reset() -> void:
	_memory["speed"] = 1.0
	_memory["trampoline"] = false
	_memory["autopilot"] = false
	trampoline_toggle.set_pressed_no_signal(false)
	autopilot_toggle.set_pressed_no_signal(false)
	_stop_live_powers()
	_apply_speed()
	_refresh_controls()
	log_channel.info("abilities_reset")


## Pause and the hanging ball belong to this battle only: they just stop.
func _stop_live_powers() -> void:
	if _paused:
		pause_button.set_pressed_no_signal(false)
		_set_paused(false)
	if _hanging:
		_set_hang(false)


func _refresh_controls() -> void:
	var on := _enabled()
	var has_me := not _local_slots.is_empty()
	for button in speed_buttons:
		button.disabled = not on
	pause_button.disabled = not on
	step_button.disabled = not on or not _paused
	ball_to_me_button.disabled = not on or not has_me
	hang_toggle.disabled = not on
	trampoline_toggle.disabled = not on
	autopilot_toggle.disabled = not on or not has_me
	for button in drop_box.get_children():
		(button as Button).disabled = not on
	restart_button.disabled = not on


# --- time -------------------------------------------------------------------------------

func _set_speed(speed: float) -> void:
	_memory["speed"] = maxf(speed, 0.01)
	_apply_speed()


## The chosen speed while on, ×1 while off.
func _apply_speed() -> void:
	var speed := float(_memory.get("speed", 1.0)) if _enabled() else 1.0
	var base := int(_memory["base_ticks"])
	Engine.physics_ticks_per_second = maxi(1, roundi(float(base) * speed))
	Engine.time_scale = speed
	log_channel.info("speed", {"speed": speed, "physics_tps": Engine.physics_ticks_per_second})


func _set_paused(on: bool) -> void:
	_paused = on
	_session.set_physics_process(not on and _session._running)
	step_button.disabled = not on or not _enabled()
	if on:
		_hold_view()
	log_channel.info("pause", {"on": on, "tick": _sim.state.tick})


func _step_once() -> void:
	if not _paused:
		return
	_session._physics_process(VolleySim.DT)
	_hold_view()


## While the sim stands still the view would keep swinging between the last two ticks:
## forget the older one so it shows the last tick as is.
func _hold_view() -> void:
	if _view == null or _view._latest < 1:
		return
	_view._ring[(_view._latest - 1 + MatchView.RING) % MatchView.RING] = null


# --- tick hooks ---------------------------------------------------------------------------

func _debug_sample(slot: int) -> Dictionary:
	if _enabled() and bool(_memory.get("autopilot", false)) and _bots.has(slot):
		return (_bots[slot] as AiOpponent).decide(_sim.state, _sim.cfg["physics"], _sim.cfg["arena"])
	return _orig_sample.call(slot)


func _debug_step(inputs: Array) -> int:
	_before_tick()
	var tick: int = _orig_step.call(inputs)
	_after_tick()
	return tick


func _before_tick() -> void:
	var state := _sim.state
	if not _enabled() or not bool(_memory.get("trampoline", false)) or state.phase != VolleySim.Phase.PLAY:
		return
	var ball := state.balls[0]
	if ball.stick > 0 or ball.vy >= 0.0:
		return
	var floor_line := float(_sim.cfg["arena"]["floor_score_y"])
	if ball.y + ball.vy * VolleySim.DT * trampoline_lead_ticks <= floor_line:
		ball.vy = maxf(-ball.vy * trampoline_bounce, trampoline_min_up)


func _after_tick() -> void:
	if not _hanging:
		return
	var state := _sim.state
	if state.touch_serial != _hang_touch or state.point_serial != _hang_point:
		_set_hang(false) # touched or the rally ended: let it go
		return
	var ball := state.balls[0]
	ball.x = _hang_pos.x
	ball.y = _hang_pos.y
	ball.vx = 0.0
	ball.vy = 0.0


# --- ball / players / match ---------------------------------------------------------------

func _set_hang(on: bool) -> void:
	_hanging = on
	hang_toggle.set_pressed_no_signal(on)
	if on:
		var state := _sim.state
		_hang_pos = Vector2(state.balls[0].x, state.balls[0].y)
		_hang_touch = state.touch_serial
		_hang_point = state.point_serial
	log_channel.info("hang_ball", {"on": on, "tick": _sim.state.tick})


func _set_flag(on: bool, flag: String) -> void:
	_memory[flag] = on
	log_channel.info(flag, {"on": on})


func _ball_to_me() -> void:
	var state := _sim.state
	if _local_slots.is_empty() or state.phase == VolleySim.Phase.POINT or state.phase == VolleySim.Phase.MATCH_END:
		return
	var player := state.players[_local_slots[0]]
	var ball := state.balls[0]
	var top := float(_sim.cfg["arena"]["ceiling"]) - _sim.param("ball_radius")
	ball.x = player.x
	ball.y = minf(player.y + ball_to_me_height, top)
	ball.vx = 0.0
	ball.vy = 0.0
	ball.stick = 0
	ball.stick_player = -1
	ball.cooldown = 0
	if _hanging:
		_hang_pos = Vector2(ball.x, ball.y)
	log_channel.info("ball_to_me", {"slot": _local_slots[0], "tick": state.tick})


## The ball lands in the middle of `team`'s zone and the sim's own rule ends the rally there.
func _drop_ball(team: int) -> void:
	var state := _sim.state
	if state.phase != VolleySim.Phase.PLAY:
		return
	if _hanging:
		_set_hang(false)
	var zone := state.zones[team]
	var ball := state.balls[0]
	ball.x = (zone.x_min + zone.x_max) * 0.5
	ball.y = _sim.param("ball_radius")
	ball.vx = 0.0
	ball.vy = 0.0
	ball.stick = 0
	ball.stick_player = -1
	var phase := _sim._fsm.get_current_state() as PlayPhase
	if phase != null:
		phase._lose_rally(team, VolleySim.Reason.FLOOR)
	log_channel.info("drop_ball", {"team": team, "tick": state.tick})


func _restart() -> void:
	var root_events := _battle.get("root_events") as RootEvents
	var match_setup := _battle.get("_setup") as MatchSetup
	if root_events == null or match_setup == null:
		return
	log_channel.info("restart_match", {"tick": _sim.state.tick})
	root_events.ev_start_game.emit({"match_setup": match_setup})
