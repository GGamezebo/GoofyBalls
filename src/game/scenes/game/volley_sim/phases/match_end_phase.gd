class_name MatchEndPhase
extends SimPhase

## Final phase: the winner is set, the sim keeps ticking (blobs still move) until the scene leaves.


func _init(sim: VolleySim) -> void:
	super(VolleySim.Phase.MATCH_END, sim)


func get_state_name() -> String:
	return "match_end"


func enter(prev_state: FSMState, event_data: Dictionary) -> void:
	super(prev_state, event_data)
	_sim().state.winner_team = int(event_data["winner_team"])


func tick() -> void:
	_count_tick(_sim().state)
