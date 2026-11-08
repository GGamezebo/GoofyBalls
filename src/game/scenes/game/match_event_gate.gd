class_name MatchEventGate
extends RefCounted

## Turns sim state changes into match events (point, match over) only once the tick they
## happened on can no longer be rolled back. Online the latest ticks are predicted: a point
## seen there may vanish after a rollback, so the HUD must not flash "ОЧКО!" for it yet.
## Owner calls: `on_ticked(tick)` after every sim step (re-simulated ones too),
## `on_rolled_back()` when an older state was loaded, `release(confirmed_tick)` once per frame.

## Point scored on tick `tick`; `scores` = all team scores right after it.
signal ev_point(team: int, reason: int, scores: Array, tick: int)
signal ev_match_over(winner_team: int, tick: int)

var _sim: VolleySim
## `point_serial` along the timeline the sim is on now.
var _serial: int = 0
## Points seen but not confirmed yet, oldest first: {serial, tick, team, reason, scores}.
var _pending: Array[Dictionary] = []
## Tick the match ended on in the current timeline (-1 = not over there).
var _over_tick: int = -1
var _over_released: bool = false


func _init(sim: VolleySim) -> void:
	_sim = sim
	_serial = int(sim.state["point_serial"])
	if sim.is_match_over():
		_over_tick = int(sim.state["tick"])


func on_ticked(tick: int) -> void:
	var state := _sim.state
	var serial := int(state["point_serial"])
	if serial > _serial:
		_pending.append({
			"serial": serial, "tick": tick, "team": int(state["point_team"]),
			"reason": int(state["point_reason"]), "scores": (state["scores"] as Array).duplicate(),
		})
	_serial = serial
	if _over_tick < 0 and _sim.is_match_over():
		_over_tick = tick


## Returns how many unconfirmed points the rollback undid (they come back if re-simulated).
func on_rolled_back() -> int:
	_serial = int(_sim.state["point_serial"])
	var kept: Array[Dictionary] = []
	for point in _pending:
		if int(point["serial"]) <= _serial:
			kept.append(point)
	var dropped := _pending.size() - kept.size()
	_pending = kept
	if not _over_released and not _sim.is_match_over():
		_over_tick = -1
	return dropped


## Emits every event whose tick is <= `confirmed_tick`, each exactly once.
func release(confirmed_tick: int) -> void:
	while not _pending.is_empty() and int(_pending[0]["tick"]) <= confirmed_tick:
		var point: Dictionary = _pending.pop_front()
		ev_point.emit(int(point["team"]), int(point["reason"]), point["scores"], int(point["tick"]))
	if not _over_released and _over_tick >= 0 and _over_tick <= confirmed_tick:
		_over_released = true
		ev_match_over.emit(int(_sim.state["winner_team"]), _over_tick)


## True once the match end was confirmed (and announced).
func is_over_confirmed() -> bool:
	return _over_released
