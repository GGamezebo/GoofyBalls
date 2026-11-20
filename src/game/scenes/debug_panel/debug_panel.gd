class_name DebugPanel
extends IScene

## App/Debug context: the debug window above every scene. AppRoot opens this HFSM state
## (`ev.open_debug`) only in non-release builds, before the menu.
## An always-visible button (works on touch) or F3 (`toggle_debug_panel`) opens the window; drag
## it by its title (mouse or finger), × closes it.
## All debug code lives here: the panel watches the scene tree itself and, when a scene listed as
## a tab's `target_scene` enters it (e.g. the battle), creates that tab and hands it the scene;
## `always_open` tabs live all the time and only hear their target come and go.
## Tabs may read and change their target's private fields; game code never knows about the panel.

@export var tab_defs: Array[DebugTabDef] = []
@export var log_settings: LogSettings
@export var open_button: Button
@export var window: Control
## Drag handle of the window.
@export var title_bar: Control
@export var close_button: Button
@export var tabs: TabContainer
## Shown instead of the tabs while there are none.
@export var empty_label: Label

var _listener := EventListener.new()
var _log: LogChannel
## Target node → Array of [DebugTabDef, DebugTab] that live only while it is in the tree.
var _attached: Dictionary = {}
## Targets seen in the tree (node → true), so each is handled once.
var _targets: Dictionary = {}
## DebugTabDef → DebugTab: tabs without a target or `always_open`, made at start.
var _always: Dictionary = {}
## DebugTabDef → the target its always-open tab works on now (null = none).
var _always_target: Dictionary = {}
## DebugTabDef → Dictionary the tab keeps its settings in across targets.
var _memory: Dictionary = {}
## Tab node → index of its def in `tab_defs`.
var _order: Dictionary = {}


func initialize(_data: Dictionary) -> void:
	_log = LogChannel.new("debug", log_settings)
	window.visible = false
	_listener.add(open_button.pressed, _toggle)
	_listener.add(close_button.pressed, _toggle)
	_listener.add(title_bar.gui_input, _on_title_input)
	_listener.add(get_tree().node_added, _on_node_added)
	for def in tab_defs:
		if def != null and (def.target_path().is_empty() or def.always_open):
			var tab := _create_tab(def, null)
			if tab != null:
				_always[def] = tab
				_always_target[def] = null
	_refresh_empty()
	_log.info("ready", {"tabs": tab_defs.size()})


func deinit() -> void:
	_listener.deinit()
	for target in _attached.keys():
		_detach_tabs(target)
	for def in _always:
		_free_tab(_always[def])
	_always.clear()
	super.deinit()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_debug_panel"):
		_toggle()
		get_viewport().set_input_as_handled()


func _toggle() -> void:
	window.visible = not window.visible


## Drag the window by its title; touch arrives here as mouse (`emulate_mouse_from_touch`).
func _on_title_input(event: InputEvent) -> void:
	var motion := event as InputEventMouseMotion
	if motion == null or not (motion.button_mask & MOUSE_BUTTON_MASK_LEFT):
		return
	var area := (window.get_parent() as Control).size
	var limit := (area - window.size).max(Vector2.ZERO)
	window.position = (window.position + motion.relative).clamp(Vector2.ZERO, limit)
	title_bar.accept_event()


# --- targets ----------------------------------------------------------------------------

func _on_node_added(node: Node) -> void:
	if node.scene_file_path.is_empty():
		return
	for def in tab_defs:
		if def != null and def.target_path() == node.scene_file_path:
			# After the HFSM has called the scene's `initialize` (it follows `add_child`).
			_on_target_entered.call_deferred(node)
			return


func _on_target_entered(target: Node) -> void:
	if not is_instance_valid(target) or not target.is_inside_tree() or _targets.has(target):
		return
	# A rematch mounts the new battle before the old one is freed: let go of the old one first.
	for old in _targets.keys():
		if not is_instance_valid(old) or old.is_queued_for_deletion():
			_on_target_left(old)
	_targets[target] = true
	var path := target.scene_file_path
	var made: Array = []
	for def in tab_defs:
		if def == null or def.target_path() != path:
			continue
		if _always.has(def):
			_always_target[def] = target
			(_always[def] as DebugTab).on_target_changed(target)
			continue
		var tab := _create_tab(def, target)
		if tab != null:
			made.append([def, tab])
	if not made.is_empty():
		_attached[target] = made
	target.tree_exiting.connect(_on_target_left.bind(target), CONNECT_ONE_SHOT)
	_refresh_empty()


## Also runs from the target's `tree_exiting` after an early release: then nothing is left to do.
func _on_target_left(target: Node) -> void:
	if not _targets.has(target):
		return
	_targets.erase(target)
	_detach_tabs(target)
	for def in _always_target.keys():
		if _always_target[def] == target:
			_always_target[def] = null
			(_always[def] as DebugTab).on_target_changed(null)


# --- tabs -------------------------------------------------------------------------------

func _create_tab(def: DebugTabDef, target: Node) -> DebugTab:
	if def.scene == null:
		return null
	var node := def.scene.instantiate()
	var tab := node as DebugTab
	if tab == null:
		_log.warn("tab_not_debug_tab", {"tab": _tab_id(def)})
		node.free()
		return null
	tab.log_channel = _log
	if not tab.accepts(target):
		tab.free()
		return null
	_order[tab] = tab_defs.find(def)
	tabs.add_child(tab)
	tabs.move_child(tab, _insert_index(tab))
	tabs.set_tab_title(tabs.get_tab_idx_from_control(tab), def.title)
	if not _memory.has(def):
		_memory[def] = {}
	tab.attach(target, _memory[def])
	_log.debug("tab_attached", {"tab": _tab_id(def), "target": target.scene_file_path.get_file() if target != null else ""})
	return tab


func _detach_tabs(target: Node) -> void:
	var made: Array = _attached.get(target, [])
	_attached.erase(target)
	for pair in made:
		_free_tab(pair[1])
		_log.debug("tab_detached", {"tab": _tab_id(pair[0])})
	_refresh_empty()


func _free_tab(tab: DebugTab) -> void:
	if not is_instance_valid(tab):
		return
	tab.detach()
	_order.erase(tab)
	tabs.remove_child(tab)
	tab.queue_free()


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
