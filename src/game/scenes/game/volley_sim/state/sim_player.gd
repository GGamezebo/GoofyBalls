class_name SimPlayer
extends RefCounted

## One blob inside `SimState` (metres, m/s). Plain data: the sim changes it, views and bots read it.

var team: int = 0
var x: float = 0.0
var y: float = 0.0
var vx: float = 0.0
var vy: float = 0.0
## Jump input was held last tick (a new press = edge for wall jumps).
var jump_held: bool = false
## -1 / 1 while stuck to the left / right outer wall, 0 otherwise.
var cling: int = 0


## Standing still at height `p_y`; the serve phase lines players up.
static func create(p_team: int, p_y: float) -> SimPlayer:
	var player := SimPlayer.new()
	player.team = p_team
	player.y = p_y
	return player


## Snapshot form (rollback / hash). Keys and order are part of the determinism hash.
func to_dict() -> Dictionary:
	return {"team": team, "x": x, "y": y, "vx": vx, "vy": vy, "jh": 1 if jump_held else 0, "cling": cling}


static func from_dict(d: Dictionary) -> SimPlayer:
	var player := SimPlayer.new()
	player.team = d["team"]
	player.x = d["x"]
	player.y = d["y"]
	player.vx = d["vx"]
	player.vy = d["vy"]
	player.jump_held = int(d["jh"]) != 0
	player.cling = d["cling"]
	return player
