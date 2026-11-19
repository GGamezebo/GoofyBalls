class_name ConfigEditor
extends VBoxContainer

## Editor of one game config (one sub-tab of "Конфиги"): a row per number / flag export of the
## config Resource, typed and ranged from its exports. Keeps its own copy of the values (memory).
## - "Включено": the copy is live. Sim configs (`sim_section`) go into the running offline
##   battle's `VolleySim.cfg` (read every tick; zones, nets and the court rebuilt) and into every
##   next battle while on; other configs are written into the loaded Resource itself.
##   Off puts the saved values back.
## - "Сбросить": the copy goes back to the saved default values.
## - "Сохранить…": after a confirmation dialog writes the copy into the config `.tres`, the game's
##   default from then on. Only when running from the editor: an exported build can't write res://.

## "Включено" + "Сбросить".
@export var header: DebugHeader
@export var save_button: Button
@export var status_label: Label
@export var file_label: Label
@export var fields_box: VBoxContainer
@export var confirm_dialog: ConfirmationDialog
## ConfigFieldRow scene, one per field.
@export var row_template: PackedScene
## Label scene for an export group title of the config.
@export var group_template: PackedScene
## Spin box limits for number fields without an export range.
@export var free_min: float = -1000.0
@export var free_max: float = 1000.0
## Spin box precision for float fields.
@export var float_step: float = 0.001
## Spin box arrow step for float fields.
@export var float_arrow_step: float = 0.1
## "Включено" when the editor first appears.
@export var enabled_by_default: bool = true

var _listener := EventListener.new()
var _log: LogChannel
var _def: DebugConfigDef
var _config: Resource
var _memory: Dictionary = {}
## Field values as they are in the config file (what "off" and "Сбросить" go back to).
var _saved: Dictionary = {}
## Field key → ConfigFieldRow.
var _rows: Dictionary = {}
var _battle: Node


func setup(def: DebugConfigDef, memory: Dictionary, log_channel: LogChannel) -> void:
	_def = def
	_config = def.config
	_memory = memory
	_log = log_channel
	_build_rows()
	if not _memory.has("values"):
		_memory["values"] = _saved.duplicate()
		_memory["enabled"] = enabled_by_default
	var values: Dictionary = _memory["values"]
	for key in _saved:
		if not values.has(key):
			values[key] = _saved[key]
		(_rows[key] as ConfigFieldRow).set_value(values[key])
	header.set_enabled(bool(_memory["enabled"]))
	var can_save := OS.has_feature("editor")
	save_button.disabled = not can_save
	_listener.add(header.ev_enabled_toggled, _on_enabled_toggled)
	_listener.add(header.ev_reset_pressed, _on_reset)
	_listener.add(save_button.pressed, _on_save_pressed)
	_listener.add(confirm_dialog.confirmed, _save)
	if bool(_memory["enabled"]):
		_apply(values)
	_refresh_labels()


func teardown() -> void:
	_listener.deinit()
	_battle = null


## The battle entered (or left: null). An enabled sim config goes straight into it.
func set_battle(battle: Node) -> void:
	_battle = battle
	if bool(_memory["enabled"]) and _applies_to_battle():
		_apply(_memory["values"])
		_log.info("config_override", {"path": _config.resource_path, "on": true, "carried": true})
	_refresh_labels()


# --- fields -----------------------------------------------------------------------------

func _build_rows() -> void:
	var pending_group := ""
	for prop in _config.get_property_list():
		var usage := int(prop["usage"])
		var key := str(prop["name"])
		if usage & PROPERTY_USAGE_CATEGORY:
			pending_group = ""
			continue
		if usage & PROPERTY_USAGE_GROUP:
			pending_group = key
			continue
		var type := int(prop["type"])
		var is_field := (usage & PROPERTY_USAGE_SCRIPT_VARIABLE) and (usage & PROPERTY_USAGE_EDITOR) \
			and (type == TYPE_FLOAT or type == TYPE_INT or type == TYPE_BOOL) and int(prop["hint"]) != PROPERTY_HINT_ENUM
		if not is_field:
			continue
		if not pending_group.is_empty():
			var group_label := group_template.instantiate() as Label
			group_label.text = pending_group
			fields_box.add_child(group_label)
			pending_group = ""
		_saved[key] = _config.get(key)
		var row := row_template.instantiate() as ConfigFieldRow
		fields_box.add_child(row)
		if type == TYPE_BOOL:
			row.setup_bool(key, bool(_saved[key]))
		else:
			var ranged := int(prop["hint"]) == PROPERTY_HINT_RANGE
			var is_int := type == TYPE_INT
			row.setup_number(key, float(_saved[key]), _limits(prop, is_int), is_int, ranged, float_arrow_step)
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


func _on_value_changed(key: String, value: Variant) -> void:
	_memory["values"][key] = value
	_log.debug("config_value", {"path": _config.resource_path, "key": key, "value": value})
	if bool(_memory["enabled"]):
		_apply({key: value})
	_refresh_labels()


func _on_enabled_toggled(on: bool) -> void:
	_memory["enabled"] = on
	_apply(_memory["values"] if on else _saved)
	_log.info("config_override", {"path": _config.resource_path, "on": on})
	_refresh_labels()


func _on_reset() -> void:
	_memory["values"] = _saved.duplicate()
	for key in _rows:
		(_rows[key] as ConfigFieldRow).set_value(_saved[key])
	if bool(_memory["enabled"]):
		_apply(_saved)
	_log.info("config_reset", {"path": _config.resource_path})
	_refresh_labels()


# --- save -------------------------------------------------------------------------------

func _on_save_pressed() -> void:
	var text := "Вы точно уверены, что хотите поменять дефолтный конфиг «%s»?\n\nФайл: %s\nНовые значения получат все следующие бои и запуски игры." % [_def.title, _config.resource_path]
	if not _def.save_note.is_empty():
		text += "\n\n" + _def.save_note
	confirm_dialog.dialog_text = text
	confirm_dialog.popup_centered()


func _save() -> void:
	var values: Dictionary = _memory["values"]
	for key in values:
		_config.set(key, values[key])
	var err := ResourceSaver.save(_config)
	if err != OK:
		_log.error("config_save_failed", {"path": _config.resource_path, "err": error_string(err)})
		# Keep the loaded default as it was, unless "Включено" keeps a plain config live anyway.
		if not (_def.sim_section.is_empty() and bool(_memory["enabled"])):
			for key in _saved:
				_config.set(key, _saved[key])
		_refresh_labels()
		status_label.text = "Не удалось сохранить: %s" % error_string(err)
		return
	_saved = values.duplicate()
	_log.info("config_saved", {"path": _config.resource_path, "fields": values.size()})
	_refresh_labels()


# --- live values ------------------------------------------------------------------------

## Sim configs apply to an offline battle whose setup uses this very config.
func _applies_to_battle() -> bool:
	if _def.sim_section.is_empty() or not is_instance_valid(_battle) or bool(_battle.get("_online")):
		return false
	var match_setup := _battle.get("_setup") as MatchSetup
	return match_setup != null and match_setup.get(_def.sim_section) == _config


## Plain configs: into the loaded Resource. Sim configs: into the battle's live sim config, then
## what is built from it once per match is rebuilt — zones and nets (the way `VolleySim.reset`
## does it) and the view's court and blob / ball sizes.
func _apply(values: Dictionary) -> void:
	if _def.sim_section.is_empty():
		for key in values:
			_config.set(key, values[key])
		return
	if not _applies_to_battle():
		return
	var sim := _battle.get("_sim") as VolleySim
	if sim == null or not sim.cfg.has(_def.sim_section):
		return
	var live: Dictionary = sim.cfg[_def.sim_section]
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


func _refresh_labels() -> void:
	var enabled := bool(_memory.get("enabled", false))
	if _def.sim_section.is_empty():
		status_label.text = "Значения действуют в игре сразу (в памяти)." if enabled else "Включи, чтобы значения сразу действовали в игре."
	elif not is_instance_valid(_battle):
		status_label.text = "Боя нет: включённые значения получит следующий бой." if enabled else "Боя нет."
	elif bool(_battle.get("_online")):
		status_label.text = "Онлайн-бой: значения к нему не применяются (иначе рассинхрон)."
	elif not _applies_to_battle():
		status_label.text = "В этом бою другой конфиг: значения к нему не применяются."
	else:
		status_label.text = "Значения действуют в текущем бою." if enabled else "Включи, чтобы значения действовали в текущем бою."
	var dirty: bool = _memory.get("values", {}) != _saved
	var lines: Array[String] = ["%s · %s" % [_config.resource_path, "есть несохранённые изменения" if dirty else "совпадает с файлом"]]
	if save_button.disabled:
		lines.append("Сохранение — только при запуске из редактора.")
	file_label.text = "\n".join(lines)
