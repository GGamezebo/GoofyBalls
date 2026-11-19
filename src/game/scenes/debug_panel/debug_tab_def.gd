class_name DebugTabDef
extends Resource

## One tab (subpanel) of the debug panel. The Resource itself is the tab id (its memory key).

## Tab title.
@export var title: String = ""
## Tab content: a scene whose root is a `DebugTab`.
@export var scene: PackedScene
## The tab exists while a scene from this file is in the tree (e.g. the battle) and works on it.
## Empty = the tab is always there, without a target.
@export_file("*.tscn") var target_scene: String = ""


## `target_scene` as a `res://` path (the inspector may store a `uid://`), compared with
## `Node.scene_file_path`; "" = no target.
func target_path() -> String:
	if target_scene.begins_with("uid://"):
		var id := ResourceUID.text_to_id(target_scene)
		return ResourceUID.get_id_path(id) if ResourceUID.has_id(id) else ""
	return target_scene
