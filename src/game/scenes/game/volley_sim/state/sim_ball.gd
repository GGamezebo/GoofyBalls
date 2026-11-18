class_name SimBall
extends RefCounted

## The ball inside `SimState` (metres, m/s). Plain data: the sim changes it, views and bots read it.

var x: float = 0.0
var y: float = 0.0
var vx: float = 0.0
var vy: float = 0.0
## Hangs still (serve, point pause): no gravity, no collisions.
var frozen: bool = true
## Player index of the last touch (-1 = none) and ticks before that player may touch again.
var last_toucher: int = -1
var cooldown: int = 0
## Tar stick: ticks left glued to `stick_player`, at offset (`stick_dx`, `stick_dy`) from it.
var stick: int = 0
var stick_player: int = -1
var stick_dx: float = 0.0
var stick_dy: float = 0.0
## Visual squish event (view-only): counter + push direction + speed change.
var impact_serial: int = 0
var impact_nx: float = 0.0
var impact_ny: float = 0.0
var impact_power: float = 0.0


## Rally over: the ball hangs still and lets go of any blob.
func freeze() -> void:
	frozen = true
	vx = 0.0
	vy = 0.0
	stick = 0
	stick_player = -1


## Snapshot form (rollback / hash). Keys and order are part of the determinism hash.
func to_dict() -> Dictionary:
	return {
		"x": x, "y": y, "vx": vx, "vy": vy, "frozen": frozen, "last_toucher": last_toucher, "cooldown": cooldown,
		"stick": stick, "stick_player": stick_player, "stick_dx": stick_dx, "stick_dy": stick_dy,
		"impact_serial": impact_serial, "impact_nx": impact_nx, "impact_ny": impact_ny, "impact_power": impact_power,
	}


static func from_dict(d: Dictionary) -> SimBall:
	var ball := SimBall.new()
	ball.x = d["x"]
	ball.y = d["y"]
	ball.vx = d["vx"]
	ball.vy = d["vy"]
	ball.frozen = d["frozen"]
	ball.last_toucher = d["last_toucher"]
	ball.cooldown = d["cooldown"]
	ball.stick = d["stick"]
	ball.stick_player = d["stick_player"]
	ball.stick_dx = d["stick_dx"]
	ball.stick_dy = d["stick_dy"]
	ball.impact_serial = d["impact_serial"]
	ball.impact_nx = d["impact_nx"]
	ball.impact_ny = d["impact_ny"]
	ball.impact_power = d["impact_power"]
	return ball
