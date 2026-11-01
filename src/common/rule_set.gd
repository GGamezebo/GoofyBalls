class_name RuleSet
extends Resource

## Match rules. `kind` picks the scoring rule inside the sim.

enum Kind { TWO_TEAM_POINTS }

@export var kind: Kind = Kind.TWO_TEAM_POINTS
## Points to win the match.
@export var win_score: int = 7
## Touches a team may make before the ball must go over (one more loses the rally).
@export var max_touches: int = 3
## Ball hangs above the server this long before it drops (ticks, 60 = 1 s).
@export var serve_delay_ticks: int = 60
## Pause after a point before the next serve (ticks, 60 = 1 s).
@export var point_pause_ticks: int = 66


func to_dict() -> Dictionary:
	return {
		"kind": kind, "win_score": win_score, "max_touches": max_touches,
		"serve_delay_ticks": serve_delay_ticks, "point_pause_ticks": point_pause_ticks,
	}
