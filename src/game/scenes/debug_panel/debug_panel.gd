class_name DebugPanel
extends IScene

## App/Debug context: the debug window above every scene. AppRoot opens this HFSM state
## (`ev.open_debug`) only in non-release builds, before the menu.
## An always-visible button (works on touch) or F3 (`toggle_debug_panel`) opens the window.
## All debug code lives here: the panel watches the scene tree itself and, when a scene listed as
## a tab's `target_scene` enters it (e.g. the battle), creates that tab and hands it the scene.
## Tabs may read and change their target's private fields; game code never knows about the panel.

@export var tab_defs: Array[DebugTabDef] = []
@export var log_settings: LogSettings
@export var open_button: Button
@export var window: Control
@export var tabs: TabContainer
## Shown instead of the tabs while there are none.
@export var empty_label: Label

var _listener := EventListener.new()
var _log: LogChannel
## Target node (null = always-on tabs) → Array of [DebugTabDef, DebugTab].
var _attached: Dictionary = {}
## DebugTabDef → Dictionary the tab keeps its settings in across targets.
var _memory: Dictionary = {}
## Tab node → index of its def in `tab_defs`.
var _order: Dictionary = {}


func initialize(_data: Dictionary) -> void:
	_log = LogChannel.new("debug", log_settings)
	window.visible = false
	_listener.add(open_button.pressed, _toggle)
	_listener.add(get_tree().node_added, _on_node_added)
	_attach_tabs(null)
	_refresh_empty()
	_log.info("ready", {"tabs": tab_defs.size()})


func deinit() -> void:
	_listener.deinit()
	for target in _attached.keys():
		_detach_tabs(target)
	super.deinit()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_debug_panel"):
		_toggle()
		get_viewport().set_input_as_handled()


func _toggle() -> void:
	window.visible = not window.visible


func _on_node_added(node: Node) -> void:
	if node.scene_file_path.is_empty():
		return
	for def in tab_defs:
		if def != null and def.target_path() == node.scene_file_path:
			# After the HFSM has called the scene's `initialize` (it follows `add_child`).
			_attach_tabs.call_deferred(node)
			return


func _attach_tabs(target: Node) -> void:
	if target != null:
		if not is_instance_valid(target) or not target.is_inside_tree() or _attached.has(target):
			return
		# A rematch mounts the new battle before the old one is freed: let go of the old one first.
		for old in _attached.keys():
			if old != null and (not is_instance_valid(old) or old.is_queued_for_deletion()):
				_detach_tabs(old)
	var path := target.scene_file_path if target != null else ""
	var made: Array = []
	for def in tab_defs:
		if def == null or def.scene == null or def.target_path() != path:
			continue
		var node := def.scene.instantiate()
		var tab := node as DebugTab
		if tab == null:
			_log.warn("tab_not_debug_tab", {"tab": _tab_id(def)})
			node.free()
			continue
		tab.log_channel = _log
		if not tab.accepts(target):
			tab.free()
			continue
		_order[tab] = tab_defs.find(def)
		tabs.add_child(tab)
		tabs.move_child(tab, _insert_index(tab))
		tabs.set_tab_title(tabs.get_tab_idx_from_control(tab), def.title)
		if not _memory.has(def):
			_memory[def] = {}
		tab.attach(target, _memory[def])
		made.append([def, tab])
		_log.debug("tab_attached", {"tab": _tab_id(def), "target": path.get_file()})
	if made.is_empty():
		return
	_attached[target] = made
	if target != null:
		target.tree_exiting.connect(_detach_tabs.bind(target), CONNECT_ONE_SHOT)
	_refresh_empty()


func _detach_tabs(target: Node) -> void:
	# Also called by the target's `tree_exiting` after an early detach: then there is nothing left.
	var made: Array = _attached.get(target, [])
	_attached.erase(target)
	for pair in made:
		var tab := pair[1] as DebugTab
		if not is_instance_valid(tab):
			continue
		tab.detach()
		_order.erase(tab)
		tabs.remove_child(tab)
		tab.queue_free()
		_log.debug("tab_detached", {"tab": _tab_id(pair[0])})
	_refresh_empty()


## Tabs stay in `tab_defs` order whenever they come and go.
func _insert_index(tab: DebugTab) -> int:
	var index := 0
	for child in tabs.get_children():
		if child != tab and int(_order.get(child, -1)) < int(_order[tab]):
			index += 1
	return index


func _refresh_empty() -> void:
	var has_tabs := tabs.get_child_count() > 0
	empty_label.visible = not has_tabs
	tabs.visible = has_tabs


static func _tab_id(def: DebugTabDef) -> String:
	return def.resource_path.get_file().get_basename()
