class_name DebugDock
extends CanvasLayer

## Debug window for non-release builds, in App root above every scene. An always-visible
## button (works on touch) or F3 (`toggle_debug_dock`) opens it.
## Tabs = panels the active contexts enabled through `DebugEvents`: a context enables its tab in
## `initialize` and disables it in `deinit`, so the tabs follow the HFSM without any config.
## The dock owns the panel nodes; a panel and its context talk only through the panel's events.

@export var debug_events: DebugEvents
@export var log_settings: LogSettings
## Keep the dock in release builds too (off: it removes itself there).
@export var show_in_release: bool = false
@export var open_button: Button
@export var window: Control
@export var tabs: TabContainer
## Shown instead of the tabs while no context has a panel enabled.
@export var empty_label: Label

var _listener := EventListener.new()
## DebugPanelDef → its tab node.
var _panels: Dictionary = {}
var _log: LogChannel


func _ready() -> void:
	if not OS.is_debug_build() and not show_in_release:
		queue_free()
		return
	_log = LogChannel.new("debug", log_settings)
	window.visible = false
	_listener.add(open_button.pressed, _toggle)
	if debug_events != null:
		_listener.add(debug_events.ev_panel_enabled, _on_panel_enabled)
		_listener.add(debug_events.ev_panel_disabled, _on_panel_disabled)
	_refresh_empty()


func _exit_tree() -> void:
	_listener.deinit()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_debug_dock"):
		_toggle()
		get_viewport().set_input_as_handled()


func _toggle() -> void:
	window.visible = not window.visible


func _on_panel_enabled(panel: DebugPanelDef) -> void:
	if panel == null or panel.scene == null or _panels.has(panel):
		return
	var node := panel.scene.instantiate() as Control
	tabs.add_child(node)
	tabs.set_tab_title(tabs.get_tab_idx_from_control(node), panel.title)
	_panels[panel] = node
	_refresh_empty()
	_log.debug("panel_enabled", {"panel": _panel_id(panel), "tabs": _panels.size()})


func _on_panel_disabled(panel: DebugPanelDef) -> void:
	var node := _panels.get(panel) as Control
	if node == null:
		return
	_panels.erase(panel)
	tabs.remove_child(node)
	node.queue_free()
	_refresh_empty()
	_log.debug("panel_disabled", {"panel": _panel_id(panel), "tabs": _panels.size()})


func _refresh_empty() -> void:
	empty_label.visible = _panels.is_empty()
	tabs.visible = not _panels.is_empty()


static func _panel_id(panel: DebugPanelDef) -> String:
	return panel.resource_path.get_file().get_basename()
