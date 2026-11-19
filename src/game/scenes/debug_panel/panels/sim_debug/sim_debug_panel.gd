class_name SimDebugPanel
extends DebugTab

## "Симуляция" tab, always there (no target): the determinism probe runs a reference input log
## through its own sim and shows whether the final hash matches the recorded one. The same result
## on PC and phone means both compute identically.

@export var probe: DeterminismProbe
@export var probe_button: Button
@export var probe_label: Label
@export var ok_color: Color = Color("#7CFF4F")
@export var fail_color: Color = Color("#FF3B3B")

var _listener := EventListener.new()


func attach(_target: Node, _memory: Dictionary) -> void:
	_listener.add(probe_button.pressed, _run_probe)


func detach() -> void:
	_listener.deinit()


func _run_probe() -> void:
	if probe == null:
		return
	var result := probe.run()
	log_channel.info("determinism_probe", result)
	var ok := bool(result.get("ok", false))
	probe_label.text = "%s хеш %d (эталон %d)" % ["✓ совпал" if ok else "✗ НЕ совпал", int(result.get("hash", 0)), int(result.get("expected", 0))]
	probe_label.add_theme_color_override("font_color", ok_color if ok else fail_color)
