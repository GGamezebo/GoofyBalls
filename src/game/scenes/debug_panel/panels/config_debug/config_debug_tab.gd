class_name ConfigDebugTab
extends DebugTab

## "Конфиги": the game's default configs (.tres) a designer tunes, one sub-tab (ConfigEditor) per
## entry of `configs`. Always open (menu or battle); while a battle is in the tree its editors may
## apply their values to it. A new designer config = one more DebugConfigDef in `configs`.

@export var configs: Array[DebugConfigDef] = []
@export var config_tabs: TabContainer
## ConfigEditor scene, one per config.
@export var editor_template: PackedScene

var _editors: Array[ConfigEditor] = []


func attach(_target: Node, memory: Dictionary) -> void:
	for def in configs:
		if def == null or def.config == null or def.config.resource_path.is_empty():
			log_channel.warn("config_without_file", {"title": def.title if def != null else ""})
			continue
		var editor := editor_template.instantiate() as ConfigEditor
		config_tabs.add_child(editor)
		config_tabs.set_tab_title(config_tabs.get_tab_idx_from_control(editor), def.title)
		var key := def.config.resource_path
		if not memory.has(key):
			memory[key] = {}
		editor.setup(def, memory[key], log_channel)
		_editors.append(editor)


func detach() -> void:
	for editor in _editors:
		editor.teardown()


func on_target_changed(target: Node) -> void:
	for editor in _editors:
		editor.set_battle(target)
