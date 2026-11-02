class_name VolleySim
extends RefCounted

## Deterministic volleyball simulation (rollback-safe). The only gameplay truth.
## - State is a plain Dictionary (save / load / hash), ticks at 60 Hz, no nodes or engine physics.
## - Floats use only + - * / and sqrt; randomness = xorshift int stored in the state.
## - N teams × N players: the court is split into one zone per team, nets between neighbours.
## - Never emits signals or FX: views read `state` and edge-detect the `*_serial` counters.
## Input per player: {"x": -100..100, "j": 0|1, "a": 0|1}.

enum Phase { SERVE, PLAY, POINT, MATCH_END }
enum Reason { NONE, FLOOR, TOUCHES }

const TICK_RATE := 60
const DT := 1.0 / 60.0

## Static per match: physics, arena, rules, team sizes (see MatchSetup.to_sim_config()).
var cfg: Dictionary = {}
var state: Dictionary = {}


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
	_begin_serve()


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

	var rules: Dictionary = cfg["rules"]
	match int(state["phase"]):
		Phase.SERVE:
			state["phase_ticks"] = int(state["phase_ticks"]) + 1
			if int(state["phase_ticks"]) >= int(rules["serve_delay_ticks"]):
				_start_play()
		Phase.PLAY:
			_step_play()
		Phase.POINT:
			state["phase_ticks"] = int(state["phase_ticks"]) + 1
			if int(state["phase_ticks"]) >= int(rules["point_pause_ticks"]):
				_after_point()
		Phase.MATCH_END:
			state["phase_ticks"] = int(state["phase_ticks"]) + 1


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
		player["vx"] = move_toward(vx, target_vx, move_speed * param("air_control") * 8.0 * DT)

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


# --- rally flow -------------------------------------------------------------------------

func _begin_serve() -> void:
	var arena: Dictionary = cfg["arena"]
	state["phase"] = Phase.SERVE
	state["phase_ticks"] = 0
	state["touch_team"] = -1
	state["touch_count"] = 0

	var radius := param("blob_radius")
	var players: Array = state["players"]
	var zones: Array = state["zones"]
	var team_sizes: Array = cfg["team_sizes"]
	var index := 0
	for team in team_sizes.size():
		var zone: Dictionary = zones[team]
		var size := int(team_sizes[team])
		for k in size:
			var player: Dictionary = players[index]
			var t := float(k + 1) / float(size + 1)
			player["x"] = float(zone["x_min"]) + (float(zone["x_max"]) - float(zone["x_min"])) * t
			player["y"] = radius
			player["vx"] = 0.0
			player["vy"] = 0.0
			player["cling"] = 0
			index += 1

	var server := _first_player_of(int(state["serving_team"]))
	var server_x := float(server["x"])
	var toward_center := 0.0
	if server_x < 0.0:
		toward_center = 1.0
	elif server_x > 0.0:
		toward_center = -1.0
	var ball: Dictionary = state["balls"][0]
	ball["x"] = server_x + toward_center * float(arena["serve_offset"])
	ball["y"] = float(arena["serve_height"])
	ball["vx"] = 0.0
	ball["vy"] = 0.0
	ball["frozen"] = true
	ball["last_toucher"] = -1
	ball["cooldown"] = 0
	ball["stick"] = 0
	ball["stick_player"] = -1


func _start_play() -> void:
	state["phase"] = Phase.PLAY
	state["phase_ticks"] = 0
	for ball in state["balls"]:
		ball["frozen"] = false


func _rally_lost(losing_team: int, reason: int) -> void:
	var scoring_team := TwoTeamPoints.rally_winner(losing_team)
	var scores: Array = state["scores"]
	scores[scoring_team] = int(scores[scoring_team]) + 1
	state["serving_team"] = scoring_team
	state["point_serial"] = int(state["point_serial"]) + 1
	state["point_team"] = scoring_team
	state["point_reason"] = reason
	state["phase"] = Phase.POINT
	state["phase_ticks"] = 0
	for ball in state["balls"]:
		ball["frozen"] = true
		ball["vx"] = 0.0
		ball["vy"] = 0.0
		ball["stick"] = 0
		ball["stick_player"] = -1


func _after_point() -> void:
	var winner := TwoTeamPoints.match_winner(state["scores"], int(cfg["rules"]["win_score"]))
	if winner >= 0:
		state["phase"] = Phase.MATCH_END
		state["phase_ticks"] = 0
		state["winner_team"] = winner
		return
	_begin_serve()


func _first_player_of(team: int) -> Dictionary:
	for player in state["players"]:
		if int(player["team"]) == team:
			return player
	return state["players"][0]


# --- ball -------------------------------------------------------------------------------
# Tar ball (Gish feel): heavy, soft bounces that grip walls and nets, and a short stick to the
# blob on a touch (it rides along, then launches). Hitbox stays a circle; squish is view-only,
# driven by `impact_serial` + `impact_nx/ny` (direction the ball was pushed) + `impact_power`.

static func _new_ball() -> Dictionary:
	return {
		"x": 0.0, "y": 0.0, "vx": 0.0, "vy": 0.0, "frozen": true, "last_toucher": -1, "cooldown": 0,
		"stick": 0, "stick_player": -1, "stick_dx": 0.0, "stick_dy": 0.0,
		"impact_serial": 0, "impact_nx": 0.0, "impact_ny": 0.0, "impact_power": 0.0,
	}


func _step_play() -> void:
	var physics: Dictionary = cfg["physics"]
	var arena: Dictionary = cfg["arena"]
	var ball: Dictionary = state["balls"][0]
	ball["cooldown"] = maxi(0, int(ball["cooldown"]) - 1)
	if int(ball["stick"]) > 0:
		_step_stuck(ball)
		return

	var vx := float(ball["vx"])
	var vy := float(ball["vy"])
	vy -= param("ball_gravity") * DT
	var damp := maxf(0.0, 1.0 - param("ball_damp") * DT)
	vx *= damp
	vy *= damp
	var max_speed := param("ball_max_speed")
	var speed := sqrt(vx * vx + vy * vy)
	if speed > max_speed:
		vx = vx / speed * max_speed
		vy = vy / speed * max_speed
	ball["vx"] = vx
	ball["vy"] = vy

	var substeps := int(physics["ball_substeps"])
	var sub_dt := DT / float(substeps)
	for _k in substeps:
		ball["x"] = float(ball["x"]) + float(ball["vx"]) * sub_dt
		ball["y"] = float(ball["y"]) + float(ball["vy"]) * sub_dt
		_collide_walls(ball)
		for net in state["nets"]:
			_collide_net(ball, net)
		if _collide_players(ball):
			return # touch fault ended the rally
		if int(ball["stick"]) > 0:
			return # glued to a blob: it carries the ball from the next tick

	var ball_radius := param("ball_radius")
	if float(ball["y"]) <= float(arena["floor_score_y"]) and (float(ball["vy"]) < -1.0 or float(ball["y"]) <= ball_radius + 0.01):
		_impact(ball, 0.0, 1.0, -float(ball["vy"]))
		_rally_lost(zone_of(float(ball["x"])), Reason.FLOOR)


## The ball rides on its blob at the contact offset; on the last stuck tick the hit launches it.
## Velocity keeps the incoming value meanwhile (the hit reflects part of it).
func _step_stuck(ball: Dictionary) -> void:
	var player: Dictionary = state["players"][int(ball["stick_player"])]
	ball["x"] = float(player["x"]) + float(ball["stick_dx"])
	ball["y"] = maxf(float(player["y"]) + float(ball["stick_dy"]), param("ball_radius"))
	ball["stick"] = int(ball["stick"]) - 1
	if int(ball["stick"]) > 0:
		return
	var dx := float(ball["stick_dx"])
	var dy := float(ball["stick_dy"])
	var dist := sqrt(dx * dx + dy * dy)
	var nx := 0.0
	var ny := 1.0
	if dist > 0.001:
		nx = dx / dist
		ny = dy / dist
	_apply_hit(player, ball, nx, ny)
	ball["stick_player"] = -1
	ball["cooldown"] = int(cfg["physics"]["touch_cooldown_ticks"])
	_impact(ball, nx, ny, sqrt(float(ball["vx"]) * float(ball["vx"]) + float(ball["vy"]) * float(ball["vy"])))
	# Launch from a legal spot: the ride may have pressed the ball into a wall or a net.
	_collide_walls(ball)
	for net in state["nets"]:
		_collide_net(ball, net)


## Visual squish event: the ball was pushed along (nx, ny) with `power` m/s of speed change.
func _impact(ball: Dictionary, nx: float, ny: float, power: float) -> void:
	if power < 1.0:
		return
	ball["impact_serial"] = int(ball["impact_serial"]) + 1
	ball["impact_nx"] = nx
	ball["impact_ny"] = ny
	ball["impact_power"] = power


func _collide_walls(ball: Dictionary) -> void:
	var arena: Dictionary = cfg["arena"]
	var radius := param("ball_radius")
	var bounce := param("ball_bounce")
	var slide := 1.0 - param("ball_grip")
	var limit := float(arena["half_width"]) - radius
	var x := float(ball["x"])
	if x > limit or x < -limit:
		var nx := -1.0 if x > limit else 1.0
		var vn := float(ball["vx"]) * nx
		ball["x"] = -limit * nx
		if vn < 0.0:
			ball["vx"] = -vn * bounce * nx
			ball["vy"] = float(ball["vy"]) * slide
			_impact(ball, nx, 0.0, -vn)
	# Ceiling: no grip, so lobs stay readable.
	var top := float(arena["ceiling"]) - radius
	if float(ball["y"]) > top:
		ball["y"] = top
		if float(ball["vy"]) > 0.0:
			_impact(ball, 0.0, -1.0, float(ball["vy"]))
			ball["vy"] = -float(ball["vy"]) * bounce


func _collide_net(ball: Dictionary, net: Dictionary) -> void:
	var radius := param("ball_radius")
	var x := float(ball["x"])
	var y := float(ball["y"])
	var net_x := float(net["x"])
	var half_w := float(net["half_w"])
	var cx := clampf(x, net_x - half_w, net_x + half_w)
	var cy := clampf(y, 0.0, float(net["top"]))
	var dx := x - cx
	var dy := y - cy
	var d2 := dx * dx + dy * dy
	if d2 >= radius * radius:
		return
	var nx: float
	var ny: float
	var dist := sqrt(d2)
	if dist < 0.0001:
		# Center inside the net box: push out sideways, away from the net center.
		nx = 1.0 if x >= net_x else -1.0
		ny = 0.0
		dist = 0.0
	else:
		nx = dx / dist
		ny = dy / dist
	var push := radius - dist
	ball["x"] = x + nx * push
	ball["y"] = y + ny * push
	var vx := float(ball["vx"])
	var vy := float(ball["vy"])
	var vn := vx * nx + vy * ny
	if vn < 0.0:
		var bounce := param("ball_bounce")
		var slide := 1.0 - param("ball_grip")
		# Tangential part slows by the grip, normal part bounces back softly.
		var tx := (vx - vn * nx) * slide
		var ty := (vy - vn * ny) * slide
		ball["vx"] = tx - bounce * vn * nx
		ball["vy"] = ty - bounce * vn * ny
		_impact(ball, nx, ny, -vn)


## Returns true when a touch fault ended the rally.
func _collide_players(ball: Dictionary) -> bool:
	var physics: Dictionary = cfg["physics"]
	var reach := param("blob_radius") + param("ball_radius")
	var players: Array = state["players"]
	for i in players.size():
		var player: Dictionary = players[i]
		var dx := float(ball["x"]) - float(player["x"])
		var dy := float(ball["y"]) - float(player["y"])
		var d2 := dx * dx + dy * dy
		if d2 >= reach * reach:
			continue
		var dist := sqrt(d2)
		var nx: float
		var ny: float
		if dist < 0.001:
			nx = 0.0
			ny = 1.0
			dist = 0.0
		else:
			nx = dx / dist
			ny = dy / dist
		# Blobs are kinematic: always separate the ball.
		var push := reach - dist
		ball["x"] = float(ball["x"]) + nx * push
		ball["y"] = float(ball["y"]) + ny * push

		if int(ball["last_toucher"]) == i and int(ball["cooldown"]) > 0:
			continue
		var stick_ticks := int(physics["ball_stick_ticks"])
		if stick_ticks > 0:
			# Tar: glue to the blob now, launch in `_step_stuck` once the stick runs out.
			var rel_vn := (float(ball["vx"]) - float(player["vx"])) * nx + (float(ball["vy"]) - float(player["vy"])) * ny
			_impact(ball, nx, ny, -rel_vn)
			ball["stick"] = stick_ticks
			ball["stick_player"] = i
			ball["stick_dx"] = nx * reach
			ball["stick_dy"] = ny * reach
		else:
			_apply_hit(player, ball, nx, ny)
			ball["cooldown"] = int(physics["touch_cooldown_ticks"])
		ball["last_toucher"] = i
		state["touch_serial"] = int(state["touch_serial"]) + 1
		state["touch_player"] = i
		if _register_touch(int(player["team"])):
			return true
		if stick_ticks > 0:
			return false
	return false


func _apply_hit(player: Dictionary, ball: Dictionary, nx: float, ny: float) -> void:
	var loft := clampf(ny, 0.0, 1.0)
	var ivx := float(ball["vx"])
	var ivy := float(ball["vy"])
	var dot := ivx * nx + ivy * ny
	var bx := ivx - 2.0 * dot * nx
	var by := ivy - 2.0 * dot * ny
	var hit := param("hit_speed") * param("hit_push")
	var reflect := param("hit_reflect")
	var nvx := bx * reflect + nx * hit + float(player["vx"]) * 0.75
	var nvy := by * reflect + ny * hit + float(player["vy"]) * 0.5
	if loft > 0.2:
		nvy = maxf(nvy, param("hit_min_up") * loft)
	else:
		nvy = maxf(nvy, param("hit_floor_vy"))
	ball["vx"] = nvx
	ball["vy"] = nvy


## Returns true when this touch is one too many for the team (rally lost).
func _register_touch(team: int) -> bool:
	if team != int(state["touch_team"]):
		state["touch_team"] = team
		state["touch_count"] = 1
	else:
		state["touch_count"] = int(state["touch_count"]) + 1
	if int(state["touch_count"]) > int(cfg["rules"]["max_touches"]):
		_rally_lost(team, Reason.TOUCHES)
		return true
	return false


## xorshift32 on the int stored in the state.
func _next_random() -> int:
	var x := int(state["rng"])
	x ^= (x << 13) & 0xFFFFFFFF
	x ^= x >> 17
	x ^= (x << 5) & 0xFFFFFFFF
	x &= 0xFFFFFFFF
	state["rng"] = x
	return x
