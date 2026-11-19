class_name PresetDebugTab
extends DebugTab

## Live editor of one preset of the running battle ("Физика", "Арена", "Правила"): one row per
## field the sim reads (the preset's `to_dict()`), typed and ranged from the preset's exports.
## The tab keeps its own copy of the values (memory: survives into the next battle).
## "Включено" writes the copy into the battle's sim config (`VolleySim.cfg[section]`, read every
## tick); off puts the battle's own preset values back. The `.tres` files are never touched.
## Online battles only show the values: an edit on one peer would desync the match.

## MatchSetup property and VolleySim.cfg key of the preset: "physics", "arena" or "rules".
@export var section: String = ""
@export var enabled_toggle: CheckButton
@export var reset_button: Button
@export var note_label: Label
@export var fields_box: VBoxContainer
## PresetFieldRow scene, one per field.
@export var row_template: PackedScene
## Label scene for an export group title of the preset.
@export var group_template: PackedScene
## Spin box limits for number fields without an export range.
@export var free_min: float = -1000.0
@export var free_max: float = 1000.0
## Spin box precision for float fields.
@export var float_step: float = 0.001
## Spin box arrow step for float fields.
@export var float_arrow_step: float = 0.1
@export_multiline var offline_note: String = "Включи, чтобы значения действовали в бою (сразу, со следующего тика). Файлы .tres не меняются; настройки сохраняются до следующего боя."
@export_multiline var online_note: String = "Онлайн-бой: только просмотр. Правка у одного игрока сломала бы синхронизацию."

var _listener := EventListener.new()
var _battle: Node
var _memory: Dictionary = {}
## The battle's own preset values (what "off" restores).
var _original: Dictionary = {}
## Field key → PresetFieldRow.
var _rows: Dictionary = {}
var _editable: bool = false


func attach(target: Node, memory: Dictionary) -> void:
	_battle = target
	_memory = memory
	var setup := target.get("_setup") as MatchSetup
	var preset: Resource = setup.get(section) as Resource if setup != null else null
	if preset == null or not preset.has_method("to_dict"):
		note_label.text = "В бою нет пресета «%s»." % section
		enabled_toggle.disabled = true
		reset_button.disabled = true
		return
	_original = preset.call("to_dict")
	_editable = not bool(target.get("_online"))
	if not _memory.has("values"):
		_memory["values"] = _original.duplicate()
		_memory["enabled"] = false
	var values: Dictionary = _memory["values"]
	for key in _original:
		if not values.has(key):
			values[key] = _original[key]
	_build_rows(preset, values if _editable else _live())
	enabled_toggle.set_pressed_no_signal(_editable and bool(_memory["enabled"]))
	enabled_toggle.disabled = not _editable
	reset_button.disabled = not _editable
	note_label.text = offline_note if _editable else online_note
	_listener.add(enabled_toggle.toggled, _on_enabled_toggled)
	_listener.add(reset_button.pressed, _on_reset)
	if _editable and bool(_memory["enabled"]):
		_apply(values)
		log_channel.info("preset_override", {"section": section, "on": true, "carried": true})


func detach() -> void:
	_listener.deinit()
	_battle = null


func _build_rows(preset: Resource, values: Dictionary) -> void:
	var pending_group := ""
	for prop in preset.get_property_list():
		var usage := int(prop["usage"])
		var key := str(prop["name"])
		if usage & PROPERTY_USAGE_CATEGORY:
			pending_group = ""
			continue
		if usage & PROPERTY_USAGE_GROUP:
			pending_group = key
			continue
		if not (usage & PROPERTY_USAGE_SCRIPT_VARIABLE) or not _original.has(key) or int(prop["hint"]) == PROPERTY_HINT_ENUM:
			continue
		if not pending_group.is_empty():
			var header := group_template.instantiate() as Label
			header.text = pending_group
			fields_box.add_child(header)
			pending_group = ""
		var row := row_template.instantiate() as PresetFieldRow
		fields_box.add_child(row)
		var value: Variant = values.get(key, _original[key])
		if typeof(_original[key]) == TYPE_BOOL:
			row.setup_bool(key, bool(value))
		else:
			var ranged := int(prop["hint"]) == PROPERTY_HINT_RANGE
			var is_int := typeof(_original[key]) == TYPE_INT
			row.setup_number(key, float(value), _limits(prop, is_int), is_int, ranged, float_arrow_step)
		row.set_editable(_editable)
		_listener.add(row.ev_changed, _on_value_changed)
		_rows[key] = row


## [min, max, step] for a number field: its export range, or the free limits.
func _limits(prop: Dictionary, is_int: bool) -> Array:
	var step := 1.0 if is_int else float_step
	if int(prop["hint"]) == PROPERTY_HINT_RANGE:
		var parts := str(prop["hint_string"]).split(",")
		if parts.size() >= 2 and parts[0].is_valid_float() and parts[1].is_valid_float():
			var range_step := float(parts[2]) if parts.size() >= 3 and parts[2].is_valid_float() else step
			return [float(parts[0]), float(parts[1]), range_step]
	return [free_min, free_max, step]


func _live() -> Dictionary:
	var sim := _battle.get("_sim") as VolleySim
	return sim.cfg.get(section, {}) if sim != null else {}


func _on_value_changed(key: String, value: Variant) -> void:
	_memory["values"][key] = value
	log_channel.debug("preset_value", {"section": section, "key": key, "value": value})
	if bool(_memory["enabled"]):
		_apply({key: value})


func _on_enabled_toggled(on: bool) -> void:
	_memory["enabled"] = on
	_apply(_memory["values"] if on else _original)
	log_channel.info("preset_override", {"section": section, "on": on})


func _on_reset() -> void:
	_memory["values"] = _original.duplicate()
	for key in _rows:
		(_rows[key] as PresetFieldRow).set_value(_original[key])
	if bool(_memory["enabled"]):
		_apply(_original)
	log_channel.info("preset_reset", {"section": section})


## Writes `values` into the battle's live sim config, then refreshes what is built from it once
## per match: zones and nets (rebuilt the way `VolleySim.reset` does) and the view's court and
## blob / ball sizes.
func _apply(values: Dictionary) -> void:
	if not is_instance_valid(_battle):
		return
	var sim := _battle.get("_sim") as VolleySim
	if sim == null or not sim.cfg.has(section):
		return
	var live: Dictionary = sim.cfg[section]
	for key in values:
		if live.has(key):
			live[key] = values[key]
	var fresh := VolleySim.new()
	fresh.reset(sim.cfg)
	sim.state.zones = fresh.state.zones
	sim.state.nets = fresh.state.nets
	var view := _battle.get("match_view") as MatchView
	if view != null:
		view._on_viewport_resized()
