extends TestCase

## Rules and physics of the deterministic sim: serve, scoring, match end, net, zones, jump.

const SETUP_PATH := "res://src/common/setups/local_2p.tres"


func _new_sim(team_sizes: Array = [1, 1], seed_value: int = 42) -> VolleySim:
	var setup := load(SETUP_PATH) as MatchSetup
	var config := setup.to_sim_config()
	config["team_sizes"] = team_sizes
	config["seed"] = seed_value
	var sim := VolleySim.new()
	sim.reset(config)
	return sim


func _idle(sim: VolleySim) -> Array:
	var inputs: Array = []
	for _i in sim.player_count():
		inputs.append(VolleySim.neutral_input())
	return inputs


func test_serve_then_play() -> void:
	var sim := _new_sim()
	expect_eq(sim.state.phase, VolleySim.Phase.SERVE, "starts with a serve")
	var ball := sim.state.balls[0]
	expect(ball.frozen, "serve ball hangs")
	expect_eq(ball.y, 5.0, "serve height")
	var delay := int(sim.cfg["rules"]["serve_delay_ticks"])
	for _t in delay:
		sim.step(_idle(sim))
	expect_eq(sim.state.phase, VolleySim.Phase.PLAY, "play after the serve delay")
	expect(not sim.state.balls[0].frozen, "ball released")


func test_ball_on_floor_scores_for_other_team() -> void:
	var sim := _new_sim()
	var server := sim.state.serving_team
	# Move every blob far from the ball so the serve drops untouched on the server side.
	for _t in 1200:
		var inputs: Array = []
		for player in sim.state.players:
			var away := -100 if player.x > sim.state.balls[0].x else 100
			inputs.append({"x": -away, "j": 0, "a": 0})
		sim.step(inputs)
		if sim.state.point_serial > 0:
			break
	expect_eq(sim.state.point_serial, 1, "one point scored")
	var scores := sim.state.scores
	expect_eq(int(scores[1 - server]), 1, "the other team scored")
	expect_eq(int(scores[server]), 0, "server team did not score")
	expect_eq(sim.state.phase, VolleySim.Phase.POINT, "point pause")
	expect_eq(sim.state.serving_team, 1 - server, "scorer serves next")


func test_match_ends_at_win_score() -> void:
	var sim := _new_sim()
	var guard := 0
	while not sim.is_match_over() and guard < 60 * 60 * 10:
		var inputs: Array = []
		for player in sim.state.players:
			var away := -100 if player.x > sim.state.balls[0].x else 100
			inputs.append({"x": -away, "j": 0, "a": 0})
		sim.step(inputs)
		guard += 1
	expect(sim.is_match_over(), "match ended")
	var winner := sim.state.winner_team
	expect(winner == 0 or winner == 1, "winner set")
	expect_eq(sim.state.scores[winner], 7, "winner has 7")


func test_net_stops_low_ball() -> void:
	var sim := _new_sim()
	var ball := sim.state.balls[0]
	sim.state.phase = VolleySim.Phase.PLAY
	ball.frozen = false
	ball.x = -2.0
	ball.y = 1.0
	ball.vx = 30.0
	ball.vy = 0.0
	# Park the blobs far away so only the net can touch the ball.
	for player in sim.state.players:
		player.x = -6.0 if player.team == 0 else 6.0
	var crossed := false
	for _t in 30:
		sim.step(_idle(sim))
		if sim.state.balls[0].x > 0.0 and sim.state.balls[0].y < 2.4:
			crossed = true
	expect(not crossed, "a low fast ball never tunnels through the net")


func test_players_stay_in_their_zone() -> void:
	var sim := _new_sim()
	for _t in 240:
		sim.step([{"x": 100, "j": 0, "a": 0}, {"x": -100, "j": 0, "a": 0}])
	var limits0 := sim.player_limits(0)
	var limits1 := sim.player_limits(1)
	expect(sim.state.players[0].x <= float(limits0[1]) + 0.0001, "team 0 stops before the net")
	expect(sim.state.players[1].x >= float(limits1[0]) - 0.0001, "team 1 stops before the net")
	expect(float(limits0[1]) < 0.0 and float(limits1[0]) > 0.0, "net gap on both sides")


func test_jump_apex() -> void:
	var held := _jump_top(90)
	var tap := _jump_top(1)
	expect(held > 2.5 and held < 4.5, "held jump apex 2.5..4.5 m (got %.2f)" % held)
	expect(tap < held - 0.5, "tap = short hop (%.2f vs %.2f)" % [tap, held])


func _jump_top(hold_ticks: int) -> float:
	var sim := _new_sim()
	var top := 0.0
	for t in 90:
		sim.step([{"x": 0, "j": 1 if t < hold_ticks and not (t > 0 and sim.is_on_floor(0)) else 0, "a": 0}, VolleySim.neutral_input()])
		top = maxf(top, sim.state.players[0].y)
	expect(sim.is_on_floor(0), "lands again")
	return top


func test_blob_sticks_to_outer_wall_not_net() -> void:
	var sim := _new_sim()
	var player := sim.state.players[0]
	var limits := sim.player_limits(0)
	player.x = float(limits[0])
	player.y = 3.0
	player.vy = -6.0
	sim.step([{"x": -100, "j": 0, "a": 0}, VolleySim.neutral_input()])
	player = sim.state.players[0]
	expect_eq(player.cling, -1, "clings to the back wall")
	expect(player.vy >= -sim.param("wall_slide_speed") - 0.001, "slides down slowly")
	sim.step([{"x": -100, "j": 1, "a": 0}, VolleySim.neutral_input()])
	player = sim.state.players[0]
	expect(player.vy > 0.0 and player.vx > 0.0, "wall jump goes up and away")

	player.x = float(limits[1])
	player.y = 3.0
	player.vy = -6.0
	sim.step([{"x": 100, "j": 0, "a": 0}, VolleySim.neutral_input()])
	expect_eq(sim.state.players[0].cling, 0, "the net never sticks")


func test_three_team_geometry() -> void:
	var sim := _new_sim([1, 1, 1])
	expect_eq(sim.state.zones.size(), 3, "three zones")
	expect_eq(sim.state.nets.size(), 2, "two nets")
	for i in 3:
		var player := sim.state.players[i]
		var zone := sim.state.zones[i]
		expect(player.x > zone.x_min and player.x < zone.x_max, "player %d starts in its zone" % i)


func test_two_by_two_spreads_players() -> void:
	var sim := _new_sim([2, 2])
	expect_eq(sim.player_count(), 4, "four players")
	var a := sim.state.players[0].x
	var b := sim.state.players[1].x
	expect(absf(a - b) > 1.0, "teammates start apart")


func test_tar_ball_sticks_then_launches() -> void:
	var sim := _new_sim()
	var stick_ticks := int(sim.cfg["physics"]["ball_stick_ticks"])
	var ball := sim.state.balls[0]
	var blob := sim.state.players[0]
	sim.state.phase = VolleySim.Phase.PLAY
	ball.frozen = false
	ball.x = blob.x + 0.1
	ball.y = blob.y + 1.0
	ball.vx = 0.0
	ball.vy = -6.0
	var touched_at := -1
	for t in 20:
		sim.step(_idle(sim))
		ball = sim.state.balls[0]
		if touched_at < 0 and sim.state.touch_serial > 0:
			touched_at = t
			expect_eq(ball.stick, stick_ticks, "ball sticks on the touch")
			expect(ball.impact_serial > 0, "touch squishes the ball")
		if touched_at >= 0 and t == touched_at + stick_ticks:
			break
	expect(touched_at >= 0, "blob touched the ball")
	expect_eq(ball.stick, 0, "stick runs out")
	expect(ball.vy > 0.0, "ball launched upwards")
	expect_eq(sim.state.touch_count, 1, "one touch for the whole stick")


func test_wall_bounce_is_soft_and_grips() -> void:
	var sim := _new_sim()
	var ball := sim.state.balls[0]
	sim.state.phase = VolleySim.Phase.PLAY
	ball.frozen = false
	var limit := float(sim.cfg["arena"]["half_width"]) - sim.param("ball_radius")
	ball.x = limit - 0.05
	ball.y = 4.0
	ball.vx = 10.0
	ball.vy = 5.0
	for player in sim.state.players:
		player.x = -6.0 if player.team == 0 else 3.0
	sim.step(_idle(sim))
	ball = sim.state.balls[0]
	expect(ball.vx < 0.0 and absf(ball.vx) <= 10.0 * sim.param("ball_bounce") + 0.01, "bounced back softer")
	expect(ball.vy < 5.0 * (1.0 - sim.param("ball_grip")) + 0.01, "wall grip slows the slide")
