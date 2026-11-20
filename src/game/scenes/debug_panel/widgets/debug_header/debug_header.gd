class_name DebugHeader
extends HBoxContainer

## "Включено" + "Сбросить" row shared by debug tabs. Only reports presses; the tab that owns it
## decides what on / off and reset mean there.

signal ev_enabled_toggled(on: bool)
signal ev_reset_pressed

@export var enabled_toggle: CheckButton
@export var reset_button: Button


func _ready() -> void:
	enabled_toggle.toggled.connect(ev_enabled_toggled.emit)
	reset_button.pressed.connect(ev_reset_pressed.emit)


## Shows the state without emitting `ev_enabled_toggled`.
func set_enabled(on: bool) -> void:
	enabled_toggle.set_pressed_no_signal(on)
