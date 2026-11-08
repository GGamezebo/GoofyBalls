class_name SimPhaseEvents
extends RefCounted

## FSM events between the match phases. Payloads are plain ints (rollback-safe).

## Serve delay is over: release the ball. No payload.
const SERVE_DONE: String = "ev_serve_done"
## Ball hit the floor or a team touched too often. {"losing_team": int, "reason": VolleySim.Reason}
const RALLY_LOST: String = "ev_rally_lost"
## Point pause is over, nobody has won yet. No payload.
const NEXT_SERVE: String = "ev_next_serve"
## Point pause is over and a team reached the win score. {"winner_team": int}
const MATCH_WON: String = "ev_match_won"
