class_name SimNet
extends RefCounted

## Net between two neighbouring zones (metres). Set once per match, never changed afterwards.

var x: float = 0.0
var half_w: float = 0.0
var top: float = 0.0


static func create(p_x: float, p_half_w: float, p_top: float) -> SimNet:
	var net := SimNet.new()
	net.x = p_x
	net.half_w = p_half_w
	net.top = p_top
	return net


## Snapshot form (rollback / hash). Keys and order are part of the determinism hash.
func to_dict() -> Dictionary:
	return {"x": x, "half_w": half_w, "top": top}


static func from_dict(d: Dictionary) -> SimNet:
	return create(d["x"], d["half_w"], d["top"])
