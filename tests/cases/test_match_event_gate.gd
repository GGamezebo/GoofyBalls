extends TestCase

## MatchEventGate: points and the match end reach the HUD only once their tick is confirmed,
## and a point undone by a rollback is never shown.

const SETUP_PATH := "res://src/common/setups/local_2p.tres"


func _new_sim() -> VolleySim:
	var setup := load(SETUP_PATH) as MatchSetup
	var config := setup.to_sim_config()
	config["team_sizes"] = [1, 1]
	config["seed"] = 42
	var sim := VolleySim.new()
	sim.reset(config)
	return sim


## Every blob runs away from the ball, so the serve drops untouched.
func _dodge_inputs(sim: VolleySim) -> Array:
	var inputs: Array = []
	for player in sim.state.players:
		var away := -100 if player.x > sim.state.balls[0].x else 100
		inputs.append({"x": -away, "j": 0, "a": 0})
	return inputs


## Steps until the first point; returns the tick it happened on (-1 = none).
func _run_to_point(sim: VolleySim, gate: MatchEventGate) -> int:
	var start_serial := sim.state.point_serial
	for _t in 1200:
		sim.step(_dodge_inputs(sim))
		var tick := sim.state.tick
		gate.on_ticked(tick)
		if sim.state.point_serial > start_serial:
			return tick
	return -1


func test_point_released_once_when_confirmed() -> void:
	var sim := _new_sim()
	var gate := MatchEventGate.new(sim)
	var points: Array = []
	gate.ev_point.connect(func(team: int, _reason: int, scores: Array, tick: int) -> void: points.append([team, scores, tick]))
	var tick := _run_to_point(sim, gate)
	expect(tick > 0, "a point happened")
	gate.release(tick - 1)
	expect_eq(points.size(), 0, "not shown while its tick is unconfirmed")
	gate.release(tick)
	gate.release(tick + 10)
	expect_eq(points.size(), 1, "shown exactly once")
	var team := sim.state.point_team
	expect_eq(points[0][0], team, "scoring team")
	expect_eq(int(points[0][1][team]), 1, "scores right after the point")
	expect_eq(points[0][2], tick, "tick of the point")


func test_rolled_back_point_is_never_shown() -> void:
	var sim := _new_sim()
	var gate := MatchEventGate.new(sim)
	var points: Array = []
	gate.ev_point.connect(func(_team: int, _reason: int, _scores: Array, tick: int) -> void: points.append(tick))
	var before := sim.save_state()
	var predicted_tick := _run_to_point(sim, gate)
	# A late remote input proves the prediction wrong: back to the old state.
	sim.load_state(before)
	expect_eq(gate.on_rolled_back(), 1, "the predicted point is undone")
	gate.release(predicted_tick + 100)
	expect_eq(points.size(), 0, "an undone point never reaches the HUD")
	# Re-simulated with the same inputs, the point happens again and is shown once.
	var real_tick := _run_to_point(sim, gate)
	gate.release(real_tick)
	expect_eq(points, [real_tick], "the re-simulated point is shown once")


func test_match_over_waits_for_confirmation() -> void:
	var sim := _new_sim()
	var gate := MatchEventGate.new(sim)
	var winners: Array = []
	gate.ev_match_over.connect(func(winner: int, _tick: int) -> void: winners.append(winner))
	var over_tick := -1
	for _t in 60 * 60 * 10:
		sim.step(_dodge_inputs(sim))
		gate.on_ticked(sim.state.tick)
		if sim.is_match_over():
			over_tick = sim.state.tick
			break
	expect(over_tick > 0, "match ended")
	gate.release(over_tick - 1)
	expect(not gate.is_over_confirmed() and winners.is_empty(), "end not announced before its tick is confirmed")
	gate.release(over_tick)
	expect(gate.is_over_confirmed(), "end confirmed")
	expect_eq(winners, [sim.state.winner_team], "announced once with the winner")
