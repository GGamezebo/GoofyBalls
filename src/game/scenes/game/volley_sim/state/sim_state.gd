class_name SimState
extends RefCounted

## Whole match state of `VolleySim`: typed fields, changed only by the sim and its phases;
## views, the bot and the game scene read it.
## Rollback / save / hash use `to_dict()` / `from_dict()`: the snapshot is a plain Dictionary
## (SyncManager stores and hashes it). Its keys, order and value types are part of the
## determinism golden hash (`DeterminismProbe`): a new field goes at the end of `to_dict()`.

var tick: int = 0
var phase: VolleySim.Phase = VolleySim.Phase.SERVE
var phase_ticks: int = 0
## xorshift32 state (`VolleySim._next_random`).
var rng: int = 0
## Points per team.
var scores: Array[int] = []
var serving_team: int = 0
var winner_team: int = -1
## Team that touched the ball last in this rally and how many times in a row (-1 = nobody yet).
var touch_team: int = -1
var touch_count: int = 0
## Set once per match: one zone per team, a net between neighbours.
var zones: Array[SimZone] = []
var nets: Array[SimNet] = []
var players: Array[SimPlayer] = []
var balls: Array[SimBall] = []
## View events: counters bump when something happens, the view edge-detects them.
var touch_serial: int = 0
var touch_player: int = -1
var point_serial: int = 0
var point_team: int = -1
var point_reason: VolleySim.Reason = VolleySim.Reason.NONE


## Tick 0, phase SERVE, no score, one frozen ball.
static func create(p_rng: int, p_scores: Array[int], p_zones: Array[SimZone], p_nets: Array[SimNet], p_players: Array[SimPlayer]) -> SimState:
	var state := SimState.new()
	state.rng = p_rng
	state.scores = p_scores
	state.zones = p_zones
	state.nets = p_nets
	state.players = p_players
	state.balls = [SimBall.new()]
	return state


## New rally: nobody has touched the ball yet.
func reset_touches() -> void:
	touch_team = -1
	touch_count = 0


## Snapshot form (rollback / hash): same keys, order and types as the old Dictionary state.
func to_dict() -> Dictionary:
	var score_list: Array = []
	for score in scores:
		score_list.append(score)
	var zone_list: Array = []
	for zone in zones:
		zone_list.append(zone.to_dict())
	var net_list: Array = []
	for net in nets:
		net_list.append(net.to_dict())
	var player_list: Array = []
	for player in players:
		player_list.append(player.to_dict())
	var ball_list: Array = []
	for ball in balls:
		ball_list.append(ball.to_dict())
	return {
		"tick": tick,
		"phase": phase,
		"phase_ticks": phase_ticks,
		"rng": rng,
		"scores": score_list,
		"serving_team": serving_team,
		"winner_team": winner_team,
		"touch_team": touch_team,
		"touch_count": touch_count,
		"zones": zone_list,
		"nets": net_list,
		"players": player_list,
		"balls": ball_list,
		"touch_serial": touch_serial,
		"touch_player": touch_player,
		"point_serial": point_serial,
		"point_team": point_team,
		"point_reason": point_reason,
	}


static func from_dict(d: Dictionary) -> SimState:
	var state := SimState.new()
	state.tick = d["tick"]
	state.phase = int(d["phase"]) as VolleySim.Phase
	state.phase_ticks = d["phase_ticks"]
	state.rng = d["rng"]
	for score in d["scores"]:
		state.scores.append(score)
	state.serving_team = d["serving_team"]
	state.winner_team = d["winner_team"]
	state.touch_team = d["touch_team"]
	state.touch_count = d["touch_count"]
	for zone in d["zones"]:
		state.zones.append(SimZone.from_dict(zone))
	for net in d["nets"]:
		state.nets.append(SimNet.from_dict(net))
	for player in d["players"]:
		state.players.append(SimPlayer.from_dict(player))
	for ball in d["balls"]:
		state.balls.append(SimBall.from_dict(ball))
	state.touch_serial = d["touch_serial"]
	state.touch_player = d["touch_player"]
	state.point_serial = d["point_serial"]
	state.point_team = d["point_team"]
	state.point_reason = int(d["point_reason"]) as VolleySim.Reason
	return state
