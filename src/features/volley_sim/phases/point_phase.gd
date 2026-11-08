class_name PointPhase
extends SimPhase

## A rally was lost: the other team scores and serves next, the ball freezes.
## After `point_pause_ticks` → MATCH_END when someone reached `win_score`, else the next SERVE.


static func get_state() -> String:
	return SimPhaseStates.POINT


func _init() -> void:
	super(get_state(), VolleySim.Phase.POINT)


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
		ball["frozen"] = true
		ball["vx"] = 0.0
		ball["vy"] = 0.0
		ball["stick"] = 0
		ball["stick_player"] = -1


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
