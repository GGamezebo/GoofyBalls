class_name DebugPanel
extends IScene

## App/Debug context: the debug window above every scene. AppRoot opens this HFSM state
## (`ev.open_debug`) only in non-release builds, before the menu, so it hears every context.
## An always-visible button (works on touch) or F3 (`toggle_debug_panel`) opens the window.
## Tabs = subpanels the active contexts enabled through `DebugEvents`: a context enables its tab
## in `initialize` and disables it in `deinit`, so the tabs follow the HFSM. This scene owns the
## tab nodes; a subpanel and its context talk only through the subpanel's own events Resource.

@export var debug_events: DebugEvents
@export var log_settings: LogSettings
@export var open_button: Button
@export var window: Control
@export var tabs: TabContainer
## Shown instead of the tabs while no context has a tab enabled.
@export var empty_label: Label

var _listener := EventListener.new()
## DebugTabDef → its tab node.
var _tabs: Dictionary = {}
var _log: LogChannel


func initialize(_data: Dictionary) -> void:
	_log = LogChannel.new("debug", log_settings)
	window.visible = false
	_listener.add(open_button.pressed, _toggle)
	_listener.add(debug_events.ev_tab_enabled, _on_tab_enabled)
	_listener.add(debug_events.ev_tab_disabled, _on_tab_disabled)
	_refresh_empty()
	_log.info("ready")


func deinit() -> void:
	_listener.deinit()
	super.deinit()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_debug_panel"):
		_toggle()
		get_viewport().set_input_as_handled()


func _toggle() -> void:
	window.visible = not window.visible


func _on_tab_enabled(tab: DebugTabDef) -> void:
	if tab == null or tab.scene == null or _tabs.has(tab):
		return
	var node := tab.scene.instantiate() as Control
	tabs.add_child(node)
	tabs.set_tab_title(tabs.get_tab_idx_from_control(node), tab.title)
	_tabs[tab] = node
	_refresh_empty()
	_log.debug("tab_enabled", {"tab": _tab_id(tab), "tabs": _tabs.size()})


func _on_tab_disabled(tab: DebugTabDef) -> void:
	var node := _tabs.get(tab) as Control
	if node == null:
		return
	_tabs.erase(tab)
	tabs.remove_child(node)
	node.queue_free()
	_refresh_empty()
	_log.debug("tab_disabled", {"tab": _tab_id(tab), "tabs": _tabs.size()})


func _refresh_empty() -> void:
	empty_label.visible = _tabs.is_empty()
	tabs.visible = not _tabs.is_empty()


static func _tab_id(tab: DebugTabDef) -> String:
	return tab.resource_path.get_file().get_basename()
