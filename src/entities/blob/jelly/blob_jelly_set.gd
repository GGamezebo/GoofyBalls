class_name BlobJellySet
extends Resource

## Which jelly feel each blob character has (`SlotSetup.character_id` → `BlobJellyConfig`).
## A new character's feel = a new `.tres` next to this file plus a line in `by_character`.

## Feel of any character not listed below.
@export var default_jelly: BlobJellyConfig
@export var by_character: Dictionary[StringName, BlobJellyConfig] = {}


## false = `for_character` falls back to `default_jelly` (a missing or misspelled character).
func has_character(character_id: StringName) -> bool:
	return by_character.has(character_id)


func for_character(character_id: StringName) -> BlobJellyConfig:
	var jelly: BlobJellyConfig = by_character.get(character_id)
	return jelly if jelly != null else default_jelly
