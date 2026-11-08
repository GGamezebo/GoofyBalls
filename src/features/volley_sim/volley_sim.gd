class_name VolleySim
extends RefCounted

## Deterministic volleyball simulation (rollback-safe). The only gameplay truth.
## - State is a plain Dictionary (save / load / hash), ticks at 60 Hz, no nodes or engine physics.
## - Floats use only + - * / and sqrt; randomness = xorshift int stored in the state.
## - N teams × N players: the court is split into one zone per team, nets between neighbours.
## - Never emits signals or FX: views read `state` and edge-detect the `*_serial` counters.
## - Match phases = FSM (`core/lib/fsm`) of `SimPhase` states in `phases/`; `state["phase"]` stays
##   the truth and the FSM is re-synced from it every tick (rollback / save-load safe).
## Input per player: {"x": -100..100, "j": 0|1, "a": 0|1}.

enum Phase { SERVE, PLAY, POINT, MATCH_END }
enum Reason { NONE, FLOOR, TOUCHES }

const TICK_RATE := 60
const DT := 1.0 / 60.0

## Static per match: physics, arena, rules, team sizes (see MatchSetup.to_sim_config()).
var cfg: Dictionary = {}
var state: Dictionary = {}

var _fsm: FSM
## Indexed by `Phase`.
var _phases: Array[SimPhase] = []


static func neutral_input() -> Dictionary:
	return {"x": 0, "j": 0, "a": 0}


func reset(config: Dictionary) -> void:
	cfg = config.duplicate(true)
	var arena: Dictionary = cfg["arena"]
	var team_sizes: Array = cfg["team_sizes"]
	var teams := team_sizes.size()
	var half_width := float(arena["half_width"])
	var zone_width := 2.0 * half_width / float(teams)

	var zones: Array = []
	var nets: Array = []
	for team in teams:
		var x_min := -half_width + zone_width * float(team)
		zones.append({"team": team, "x_min": x_min, "x_max": x_min + zone_width})
		if team > 0:
			nets.append({"x": x_min, "half_w": float(arena["net_half_width"]), "top": float(arena["net_height"])})

	var players: Array = []
	for team in teams:
		for _k in int(team_sizes[team]):
			players.append({"team": team, "x": 0.0, "y": param("blob_radius"), "vx": 0.0, "vy": 0.0, "jh": 0, "cling": 0})

	var scores: Array = []
	for _team in teams:
		scores.append(0)

	var rng := int(cfg["seed"]) & 0xFFFFFFFF
	if rng == 0:
		rng = 0x9E3779B9
	state = {
		"tick": 0,
		"phase": Phase.SERVE,
		"phase_ticks": 0,
		"rng": rng,
		"scores": scores,
		"serving_team": 0,
		"winner_team": -1,
		"touch_team": -1,
		"touch_count": 0,
		"zones": zones,
		"nets": nets,
		"players": players,
		"balls": [_new_ball()],
		"touch_serial": 0,
		"touch_player": -1,
		"point_serial": 0,
		"point_team": -1,
		"point_reason": Reason.NONE,
	}
	state["serving_team"] = _next_random() % teams
	_build_phases() # enters SERVE


func save_state() -> Dictionary:
	return state.duplicate(true)


func load_state(saved: Dictionary) -> void:
	state = saved.duplicate(true)


func state_hash() -> int:
	return state.hash()


func team_count() -> int:
	return (cfg["team_sizes"] as Array).size()


func player_count() -> int:
	return (state["players"] as Array).size()


func is_match_over() -> bool:
	return int(state["phase"]) == Phase.MATCH_END


## One tick. `inputs[i]` belongs to player i (MatchSetup slot order); missing = neutral.
func step(inputs: Array) -> void:
	state["tick"] = int(state["tick"]) + 1
	var players: Array = state["players"]
	for i in players.size():
		var input: Dictionary = inputs[i] if i < inputs.size() and inputs[i] is Dictionary else {}
		_step_player(players[i], input)

	# The state may come from `load_state` (rollback) or be edited directly: follow it.
	var phase := _phases[int(state["phase"])]
	if _fsm.get_current_state_name() != phase.state_name:
		_fsm.restore_state(phase.state_name)
	phase.tick()


## Physics value for `target` (player / ball dict). Iteration 1: the preset value; buffs will
## stack modifiers on top here (preset ⊕ modifiers) without touching the callers.
func param(name: String, _target: Dictionary = {}) -> float:
	return float(cfg["physics"][name])


func is_on_floor(player_index: int) -> bool:
	var player: Dictionary = state["players"][player_index]
	return float(player["y"]) <= param("blob_radius") + 0.001


## Horizontal limits [lo, hi] for a player center inside its team zone (walls and nets).
func player_limits(team: int) -> Array:
	var arena: Dictionary = cfg["arena"]
	var radius := param("blob_radius")
	var zone: Dictionary = state["zones"][team]
	var half_width := float(arena["half_width"])
	var net_gap := float(arena["net_half_width"]) + radius + float(arena["net_clearance"])
	var lo := float(zone["x_min"]) + (radius if float(zone["x_min"]) <= -half_width + 0.0001 else net_gap)
	var hi := float(zone["x_max"]) - (radius if float(zone["x_max"]) >= half_width - 0.0001 else net_gap)
	return [lo, hi]


func zone_of(x: float) -> int:
	var zones: Array = state["zones"]
	for zone in zones:
		if x < float(zone["x_max"]):
			return int(zone["team"])
	return int(zones.back()["team"])


# --- players ----------------------------------------------------------------------------
# Tar blobs (Gish feel): a little inertia on the floor, short hop when the jump is released
# early, and they stick to the outer arena walls (slow slide + wall jump). Nets never stick.

func _step_player(player: Dictionary, input: Dictionary) -> void:
	var physics: Dictionary = cfg["physics"]
	var radius := param("blob_radius")
	var move_speed := param("move_speed")
	var axis := clampf(float(int(input.get("x", 0))) / 100.0, -1.0, 1.0)
	var jump_held := int(input.get("j", 0)) != 0
	var jump_pressed := jump_held and int(player["jh"]) == 0
	player["jh"] = 1 if jump_held else 0
	var on_floor := float(player["y"]) <= radius + 0.001
	var target_vx := axis * move_speed
	var vx := float(player["vx"])
	if bool(physics["snap_move"]) and on_floor:
		player["vx"] = target_vx
	elif on_floor:
		# Speeding up along the stick uses `ground_accel`; stopping and turning bite harder.
		var speeding_up := absf(target_vx) > 0.01 and target_vx * vx >= 0.0
		var accel := param("ground_accel") if speeding_up else param("ground_friction")
		player["vx"] = move_toward(vx, target_vx, accel * DT)
	else:
		player["vx"] = move_toward(vx, target_vx, move_speed * param("air_control") * param("air_accel_scale") * DT)

	var cling := int(player["cling"])
	if cling != 0 and jump_pressed and not on_floor:
		# Wall jump: peel off the wall, away from it.
		player["vy"] = param("wall_jump_velocity")
		player["vx"] = -float(cling) * param("wall_jump_push")
		cling = 0
	elif jump_held and on_floor:
		player["vy"] = param("jump_velocity")
		on_floor = false
	if not on_floor:
		var gravity := param("gravity")
		if not jump_held and float(player["vy"]) > 0.0:
			gravity *= param("jump_cut_gravity")
		player["vy"] = float(player["vy"]) - gravity * DT

	player["x"] = float(player["x"]) + float(player["vx"]) * DT
	player["y"] = float(player["y"]) + float(player["vy"]) * DT
	if float(player["y"]) <= radius:
		player["y"] = radius
		if float(player["vy"]) < 0.0:
			player["vy"] = 0.0

	var limits := player_limits(int(player["team"]))
	var x := float(player["x"])
	var wall := 0
	if x <= float(limits[0]):
		player["x"] = float(limits[0])
		wall = -1
		if float(player["vx"]) < 0.0:
			player["vx"] = 0.0
	elif x >= float(limits[1]):
		player["x"] = float(limits[1])
		wall = 1
		if float(player["vx"]) > 0.0:
			player["vx"] = 0.0

	# Stick while airborne and pushing into an outer wall: slide down slowly.
	var half_width := float(cfg["arena"]["half_width"])
	var outer := absf(float(player["x"]) + float(wall) * radius) >= half_width - 0.001
	cling = 0
	if wall != 0 and outer and axis * float(wall) > 0.3 and float(player["y"]) > radius + 0.001:
		cling = wall
		player["vy"] = maxf(float(player["vy"]), -param("wall_slide_speed"))
	player["cling"] = cling


# --- phases ----------------------------------------------------------------------------
# SERVE → (serve delay) → PLAY → (floor / too many touches) → POINT → NEXT_SERVE | MATCH_END.

func _build_phases() -> void:
	if _fsm:
		_fsm.deinit()
	_phases = [ServePhase.new(), PlayPhase.new(), PointPhase.new(), MatchEndPhase.new()]
	for i in _phases.size():
		assert(_phases[i].phase == i, "phase list must follow VolleySim.Phase")
		_phases[i].initialize(self)
	_fsm = FSM.new({
		"initial": {"state": ServePhase.get_state()},
		"transitions": [
			{"src": ServePhase.get_state(), "dst": PlayPhase.get_state(), "event": SimPhaseEvents.SERVE_DONE},
			{"src": PlayPhase.get_state(), "dst": PointPhase.get_state(), "event": SimPhaseEvents.RALLY_LOST},
			{"src": PointPhase.get_state(), "dst": ServePhase.get_state(), "event": SimPhaseEvents.NEXT_SERVE},
			{"src": PointPhase.get_state(), "dst": MatchEndPhase.get_state(), "event": SimPhaseEvents.MATCH_WON},
		],
		"states": _phases,
		"final": MatchEndPhase.get_state(),
	})


# --- helpers ---------------------------------------------------------------------------

static func _new_ball() -> Dictionary:
	return {
		"x": 0.0, "y": 0.0, "vx": 0.0, "vy": 0.0, "frozen": true, "last_toucher": -1, "cooldown": 0,
		"stick": 0, "stick_player": -1, "stick_dx": 0.0, "stick_dy": 0.0,
		"impact_serial": 0, "impact_nx": 0.0, "impact_ny": 0.0, "impact_power": 0.0,
	}


## xorshift32 on the int stored in the state.
func _next_random() -> int:
	var x := int(state["rng"])
	x ^= (x << 13) & 0xFFFFFFFF
	x ^= x >> 17
	x ^= (x << 5) & 0xFFFFFFFF
	x &= 0xFFFFFFFF
	state["rng"] = x
	return x
