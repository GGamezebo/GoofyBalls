class_name VolleySim
extends RefCounted

## Deterministic volleyball simulation (rollback-safe). The only gameplay truth.
## - State = typed `SimState` (players, balls, zones, nets); ticks at 60 Hz, no nodes or engine
##   physics. Save / load / hash go through its plain-Dictionary snapshot (`to_dict`).
## - Floats use only + - * / and sqrt; randomness = xorshift int stored in the state.
## - N teams × N players: the court is split into one zone per team, nets between neighbours.
## - Never emits signals or FX: views read `state` and edge-detect the `*_serial` counters.
## - Match phases = FSM (`core/lib/fsm`) of `SimPhase` states in `phases/`; `state.phase` stays
##   the truth and the FSM is re-synced from it every tick (rollback / save-load safe).
## Input per player: {"x": -100..100, "j": 0|1, "a": 0|1}.

enum Phase { SERVE, PLAY, POINT, MATCH_END }
enum Reason { NONE, FLOOR, TOUCHES }

const TICK_RATE := 60
const DT := 1.0 / 60.0

## Static per match: physics, arena, rules, team sizes (see MatchSetup.to_sim_config()).
var cfg: Dictionary = {}
var state := SimState.new()

var _fsm: FSM


static func neutral_input() -> Dictionary:
	return {"x": 0, "j": 0, "a": 0}


func reset(config: Dictionary) -> void:
	cfg = config.duplicate(true)
	var arena: Dictionary = cfg["arena"]
	var team_sizes: Array = cfg["team_sizes"]
	var teams := team_sizes.size()
	var half_width := float(arena["half_width"])
	var zone_width := 2.0 * half_width / float(teams)

	var zones: Array[SimZone] = []
	var nets: Array[SimNet] = []
	for team in teams:
		var x_min := -half_width + zone_width * float(team)
		zones.append(SimZone.create(team, x_min, x_min + zone_width))
		if team > 0:
			nets.append(SimNet.create(x_min, float(arena["net_half_width"]), float(arena["net_height"])))

	var players: Array[SimPlayer] = []
	for team in teams:
		for _k in int(team_sizes[team]):
			players.append(SimPlayer.create(team, param("blob_radius")))

	var scores: Array[int] = []
	for _team in teams:
		scores.append(0)

	var rng := int(cfg["seed"]) & 0xFFFFFFFF
	if rng == 0:
		rng = 0x9E3779B9
	state = SimState.create(rng, scores, zones, nets, players)
	state.serving_team = _next_random() % teams
	_build_phases() # enters SERVE


## Plain-Dictionary snapshot for rollback (SyncManager stores and hashes it) and save files.
func save_state() -> Dictionary:
	return state.to_dict()


func load_state(saved: Dictionary) -> void:
	state = SimState.from_dict(saved)


func state_hash() -> int:
	return state.to_dict().hash()


func team_count() -> int:
	return (cfg["team_sizes"] as Array).size()


func player_count() -> int:
	return state.players.size()


func is_match_over() -> bool:
	return state.phase == Phase.MATCH_END


## One tick. `inputs[i]` belongs to player i (MatchSetup slot order); missing = neutral.
func step(inputs: Array) -> void:
	state.tick += 1
	for i in state.players.size():
		var input: Dictionary = inputs[i] if i < inputs.size() and inputs[i] is Dictionary else {}
		_step_player(state.players[i], input)

	# The state may come from `load_state` (rollback) or be edited directly: follow it.
	if _fsm.get_current_state_id() != state.phase:
		_fsm.restore_state(state.phase)
	(_fsm.get_current_state() as SimPhase).tick()


## Physics value for `target` (a player or the ball). Iteration 1: the preset value; buffs will
## stack modifiers on top here (preset ⊕ modifiers) without touching the callers.
func param(name: String, _target: RefCounted = null) -> float:
	return float(cfg["physics"][name])


func is_on_floor(player_index: int) -> bool:
	return state.players[player_index].y <= param("blob_radius") + 0.001


## Horizontal limits [lo, hi] for a player center inside its team zone (walls and nets).
func player_limits(team: int) -> Array:
	var arena: Dictionary = cfg["arena"]
	var radius := param("blob_radius")
	var zone := state.zones[team]
	var half_width := float(arena["half_width"])
	var net_gap := float(arena["net_half_width"]) + radius + float(arena["net_clearance"])
	var lo := zone.x_min + (radius if zone.x_min <= -half_width + 0.0001 else net_gap)
	var hi := zone.x_max - (radius if zone.x_max >= half_width - 0.0001 else net_gap)
	return [lo, hi]


func zone_of(x: float) -> int:
	for zone in state.zones:
		if x < zone.x_max:
			return zone.team
	return (state.zones.back() as SimZone).team


# --- players ----------------------------------------------------------------------------
# Tar blobs (Gish feel): a little inertia on the floor, short hop when the jump is released
# early, and they stick to the outer arena walls (slow slide + wall jump). Nets never stick.

func _step_player(player: SimPlayer, input: Dictionary) -> void:
	var physics: Dictionary = cfg["physics"]
	var radius := param("blob_radius")
	var move_speed := param("move_speed")
	var axis := clampf(float(int(input.get("x", 0))) / 100.0, -1.0, 1.0)
	var jump_held := int(input.get("j", 0)) != 0
	var jump_pressed := jump_held and not player.jump_held
	player.jump_held = jump_held
	var on_floor := player.y <= radius + 0.001
	var target_vx := axis * move_speed
	var vx := player.vx
	if bool(physics["snap_move"]) and on_floor:
		player.vx = target_vx
	elif on_floor:
		# Speeding up along the stick uses `ground_accel`; stopping and turning bite harder.
		var speeding_up := absf(target_vx) > 0.01 and target_vx * vx >= 0.0
		var accel := param("ground_accel") if speeding_up else param("ground_friction")
		player.vx = move_toward(vx, target_vx, accel * DT)
	else:
		player.vx = move_toward(vx, target_vx, move_speed * param("air_control") * param("air_accel_scale") * DT)

	var cling := player.cling
	if cling != 0 and jump_pressed and not on_floor:
		# Wall jump: peel off the wall, away from it.
		player.vy = param("wall_jump_velocity")
		player.vx = -float(cling) * param("wall_jump_push")
		cling = 0
	elif jump_held and on_floor:
		player.vy = param("jump_velocity")
		on_floor = false
	if not on_floor:
		var gravity := param("gravity")
		if not jump_held and player.vy > 0.0:
			gravity *= param("jump_cut_gravity")
		player.vy = player.vy - gravity * DT

	player.x = player.x + player.vx * DT
	player.y = player.y + player.vy * DT
	if player.y <= radius:
		player.y = radius
		if player.vy < 0.0:
			player.vy = 0.0

	var limits := player_limits(player.team)
	var x := player.x
	var wall := 0
	if x <= float(limits[0]):
		player.x = float(limits[0])
		wall = -1
		if player.vx < 0.0:
			player.vx = 0.0
	elif x >= float(limits[1]):
		player.x = float(limits[1])
		wall = 1
		if player.vx > 0.0:
			player.vx = 0.0

	# Stick while airborne and pushing into an outer wall: slide down slowly.
	var half_width := float(cfg["arena"]["half_width"])
	var outer := absf(player.x + float(wall) * radius) >= half_width - 0.001
	cling = 0
	if wall != 0 and outer and axis * float(wall) > 0.3 and player.y > radius + 0.001:
		cling = wall
		player.vy = maxf(player.vy, -param("wall_slide_speed"))
	player.cling = cling


# --- phases ----------------------------------------------------------------------------
# SERVE → (serve delay) → PLAY → (floor / too many touches) → POINT → NEXT_SERVE | MATCH_END.

func _build_phases() -> void:
	if _fsm:
		_fsm.deinit()
	_fsm = FSM.new({
		"initial": {"state": Phase.SERVE},
		"transitions": [
			{"src": Phase.SERVE, "dst": Phase.PLAY, "event": SimPhaseEvents.SERVE_DONE},
			{"src": Phase.PLAY, "dst": Phase.POINT, "event": SimPhaseEvents.RALLY_LOST},
			{"src": Phase.POINT, "dst": Phase.SERVE, "event": SimPhaseEvents.NEXT_SERVE},
			{"src": Phase.POINT, "dst": Phase.MATCH_END, "event": SimPhaseEvents.MATCH_WON},
		],
		"states": [ServePhase.new(self), PlayPhase.new(self), PointPhase.new(self), MatchEndPhase.new(self)],
		"final": Phase.MATCH_END,
	})


# --- helpers ---------------------------------------------------------------------------

## xorshift32 on the int stored in the state.
func _next_random() -> int:
	var x := state.rng
	x ^= (x << 13) & 0xFFFFFFFF
	x ^= x >> 17
	x ^= (x << 5) & 0xFFFFFFFF
	x &= 0xFFFFFFFF
	state.rng = x
	return x
