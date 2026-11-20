class_name RoomMatch
extends RefCounted

## One round of a friend room, ready to play: the same on both peers.

var match_seed: int = 0
## 0 = first match in the room, +1 per rematch.
var round_index: int = 0
## Players in slot order (host first): peer id and display name of each.
var peer_ids: Array[int] = []
var names: Array[String] = []


func player_count() -> int:
	return peer_ids.size()
