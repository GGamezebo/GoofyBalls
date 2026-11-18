class_name SimZone
extends RefCounted

## Court part owned by one team (metres). Set once per match, never changed afterwards.

var team: int = 0
var x_min: float = 0.0
var x_max: float = 0.0


static func create(p_team: int, p_x_min: float, p_x_max: float) -> SimZone:
	var zone := SimZone.new()
	zone.team = p_team
	zone.x_min = p_x_min
	zone.x_max = p_x_max
	return zone


## Snapshot form (rollback / hash). Keys and order are part of the determinism hash.
func to_dict() -> Dictionary:
	return {"team": team, "x_min": x_min, "x_max": x_max}


static func from_dict(d: Dictionary) -> SimZone:
	return create(d["team"], d["x_min"], d["x_max"])
