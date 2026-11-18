class_name PointPhase
extends SimPhase

## A rally was lost: the other team scores and serves next, the ball freezes.
## After `point_pause_ticks` → MATCH_END when someone reached `win_score`, else the next SERVE.


func _init(sim: VolleySim) -> void:
	super(VolleySim.Phase.POINT, sim)


func get_state_name() -> String:
	return "point"


func enter(prev_state: FSMState, event_data: Dictionary) -> void:
	var state := _sim().state
	var scoring_team := TwoTeamPoints.rally_winner(int(event_data["losing_team"]))
	var scores: Array = state["scores"]
	scores[scoring_team] = int(scores[scoring_team]) + 1
	state["serving_team"] = scoring_team
	state["point_serial"] = int(state["point_serial"]) + 1
	state["point_team"] = scoring_team
	state["point_reason"] = int(event_data["reason"])
	super(prev_state, event_data)
	for ball in state["balls"]:
		SimState.freeze_ball(ball)


func tick() -> void:
	var sim := _sim()
	var state := sim.state
	var rules: Dictionary = sim.cfg["rules"]
	if _count_tick(state) < int(rules["point_pause_ticks"]):
		return
	var winner := TwoTeamPoints.match_winner(state["scores"], int(rules["win_score"]))
	if winner >= 0:
		add_event(SimPhaseEvents.MATCH_WON, {"winner_team": winner})
	else:
		add_event(SimPhaseEvents.NEXT_SERVE)
