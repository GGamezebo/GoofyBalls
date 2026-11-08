class_name MatchEndPhase
extends SimPhase

## Final phase: the winner is set, the sim keeps ticking (blobs still move) until the scene leaves.


static func get_state() -> String:
	return SimPhaseStates.MATCH_END


func _init() -> void:
	super(get_state(), VolleySim.Phase.MATCH_END)


func enter(prev_state: FSMState, event_data: Dictionary) -> void:
	super(prev_state, event_data)
	_sim().state["winner_team"] = int(event_data["winner_team"])


func tick() -> void:
	_count_tick(_sim().state)
