class_name PresetFieldRow
extends HBoxContainer

## One field of a preset debug tab: its name and a spin box (numbers) or a check box (flags).
## Emits the new value typed like the preset field (int stays int).

signal ev_changed(key: String, value: Variant)

@export var name_label: Label
@export var spin: SpinBox
@export var check: CheckBox

var key: String = ""
var _is_int: bool = false
## Set while the tab writes a value in: no `ev_changed` for it.
var _quiet: bool = false


func _ready() -> void:
	spin.value_changed.connect(_on_spin_changed)
	check.toggled.connect(_on_check_toggled)


## `limits` = [min, max, step]; `ranged` = the field has an export range: stay inside it.
func setup_number(p_key: String, value: float, limits: Array, is_int: bool, ranged: bool, arrow_step: float) -> void:
	key = p_key
	_is_int = is_int
	name_label.text = p_key
	check.visible = false
	spin.visible = true
	spin.min_value = float(limits[0])
	spin.max_value = float(limits[1])
	spin.step = float(limits[2])
	spin.allow_lesser = not ranged
	spin.allow_greater = not ranged
	spin.custom_arrow_step = 1.0 if is_int else arrow_step
	set_value(value)


func setup_bool(p_key: String, value: bool) -> void:
	key = p_key
	name_label.text = p_key
	spin.visible = false
	check.visible = true
	set_value(value)


func set_value(value: Variant) -> void:
	_quiet = true
	if check.visible:
		check.button_pressed = bool(value)
	else:
		spin.value = float(value)
	_quiet = false


func set_editable(on: bool) -> void:
	spin.editable = on
	check.disabled = not on


func _on_spin_changed(value: float) -> void:
	if _quiet:
		return
	if _is_int:
		ev_changed.emit(key, roundi(value))
	else:
		ev_changed.emit(key, value)


func _on_check_toggled(on: bool) -> void:
	if not _quiet:
		ev_changed.emit(key, on)
