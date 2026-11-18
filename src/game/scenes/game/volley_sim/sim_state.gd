class_name SimState
extends RefCounted

## Builders of the sim's plain-Dictionary state: one place for every key and its start value.
## The state stays a Dictionary (save / load / hash, `sim.md`); these are only factories.
## Key order is part of `VolleySim.state_hash()` (determinism golden hash): add new keys at the end.


## Whole match state at tick 0 (phase SERVE, no score).
static func new_state(rng: int, scores: Array, zones: Array, nets: Array, players: Array) -> Dictionary:
	return {
		"tick": 0,
		"phase": VolleySim.Phase.SERVE,
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
		"balls": [new_ball()],
		"touch_serial": 0,
		"touch_player": -1,
		"point_serial": 0,
		"point_team": -1,
		"point_reason": VolleySim.Reason.NONE,
	}


## Court part owned by `team`, from `x_min` to `x_max` (m).
static func new_zone(team: int, x_min: float, x_max: float) -> Dictionary:
	return {"team": team, "x_min": x_min, "x_max": x_max}


## Net at `x` between two zones (m).
static func new_net(x: float, half_width: float, top: float) -> Dictionary:
	return {"x": x, "half_w": half_width, "top": top}


## Player standing still at height `y` (m); the serve phase lines players up.
static func new_player(team: int, y: float) -> Dictionary:
	return {"team": team, "x": 0.0, "y": y, "vx": 0.0, "vy": 0.0, "jh": 0, "cling": 0}


## Frozen ball at the origin; the serve phase places it.
static func new_ball() -> Dictionary:
	return {
		"x": 0.0, "y": 0.0, "vx": 0.0, "vy": 0.0, "frozen": true, "last_toucher": -1, "cooldown": 0,
		"stick": 0, "stick_player": -1, "stick_dx": 0.0, "stick_dy": 0.0,
		"impact_serial": 0, "impact_nx": 0.0, "impact_ny": 0.0, "impact_power": 0.0,
	}


## New rally: nobody has touched the ball yet (same values as `new_state`).
static func reset_touches(state: Dictionary) -> void:
	state["touch_team"] = -1
	state["touch_count"] = 0


## Rally over: the ball hangs still and lets go of any blob (same values as `new_ball`).
static func freeze_ball(ball: Dictionary) -> void:
	ball["frozen"] = true
	ball["vx"] = 0.0
	ball["vy"] = 0.0
	ball["stick"] = 0
	ball["stick_player"] = -1
