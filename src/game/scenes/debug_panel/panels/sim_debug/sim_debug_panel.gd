class_name SimDebugPanel
extends VBoxContainer

## Debug panel tab for every match: the determinism probe runs a reference input log through
## the sim and shows whether the final hash matches the recorded one. The same result on PC and
## phone means both compute identically. Talks only through `SimDebugEvents`.

@export var events: SimDebugEvents
@export var probe_button: Button
@export var probe_label: Label
@export var ok_color: Color = Color("#7CFF4F")
@export var fail_color: Color = Color("#FF3B3B")

var _listener := EventListener.new()


func _ready() -> void:
	_listener.add(probe_button.pressed, func() -> void: events.ev_probe_requested.emit())
	_listener.add(events.ev_probe_result, _on_probe_result)


func _exit_tree() -> void:
	_listener.deinit()


func _on_probe_result(result: Dictionary) -> void:
	var ok := bool(result.get("ok", false))
	probe_label.text = "%s хеш %d (эталон %d)" % ["✓ совпал" if ok else "✗ НЕ совпал", int(result.get("hash", 0)), int(result.get("expected", 0))]
	probe_label.add_theme_color_override("font_color", ok_color if ok else fail_color)
