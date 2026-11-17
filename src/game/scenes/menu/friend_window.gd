class_name FriendWindow
extends Control

## "Играть с другом" window (concept/ui-home, friend modal): create a room and show its code,
## or join with a friend's 4-letter code; server address row. Talks to App/Online only through
## OnlineEvents. Opened / closed by the menu WindowStackManager; the menu calls
## `initialize()` / `deinit()`.

const CODE_LENGTH := 4

@export var online_events: OnlineEvents
@export var online_config: OnlineConfig
@export var create_button: Button
@export var code_box: Control
@export var code_label: Label
@export var copy_button: Button
@export var code_edit: LineEdit
@export var join_button: Button
@export var status_label: Label
@export var server_edit: LineEdit
@export var server_button: Button

var _listener := EventListener.new()
var _busy: bool = false


func initialize() -> void:
	_listener.add(create_button.pressed, _on_create_pressed)
	_listener.add(join_button.pressed, _submit_join)
	_listener.add(code_edit.text_submitted, func(_text: String) -> void: _submit_join())
	_listener.add(code_edit.text_changed, _on_code_changed)
	_listener.add(copy_button.pressed, func() -> void: DisplayServer.clipboard_set(code_label.text))
	_listener.add(server_button.pressed, _on_server_submitted)
	_listener.add(online_events.ev_room_created, _on_room_created)
	_listener.add(online_events.ev_room_status, func(text: String) -> void: _set_status(text, false))
	_listener.add(online_events.ev_room_error, _on_room_error)
	server_edit.text = online_config.address()


func deinit() -> void:
	_listener.deinit()


func on_window_enter() -> void:
	_reset()


## Window left (back button / ui_cancel): drops a room that was being opened (no-op when none).
func on_window_exit() -> void:
	online_events.ev_leave_room.emit()


func _reset() -> void:
	_set_busy(false)
	code_box.visible = false
	create_button.visible = true
	code_edit.text = ""
	_set_status("", false)


func _on_create_pressed() -> void:
	_set_busy(true)
	_set_status("Подключаемся к серверу…", false)
	online_events.ev_create_room.emit()


func _submit_join() -> void:
	var code := code_edit.text.strip_edges().to_upper()
	if _busy or code.length() != CODE_LENGTH:
		return
	_set_busy(true)
	_set_status("Ищем комнату %s…" % code, false)
	online_events.ev_join_room.emit(code)


func _on_room_created(code: String) -> void:
	create_button.visible = false
	code_box.visible = true
	code_label.text = code
	_set_status("Ждём друга… Скажи ему код.", false)


func _on_room_error(text: String) -> void:
	_set_busy(false)
	_set_status(text, true)


func _on_server_submitted() -> void:
	online_events.ev_set_server.emit(server_edit.text.strip_edges())
	server_edit.text = online_config.address()
	_set_status("Сервер: %s" % online_config.address(), false)


func _on_code_changed(text: String) -> void:
	var clean := text.to_upper().strip_edges()
	if clean != text:
		var caret := code_edit.caret_column
		code_edit.text = clean
		code_edit.caret_column = caret
	join_button.disabled = _busy or clean.length() != CODE_LENGTH


func _set_busy(busy: bool) -> void:
	_busy = busy
	create_button.disabled = busy
	join_button.disabled = busy or code_edit.text.length() != CODE_LENGTH
	code_edit.editable = not busy


func _set_status(text: String, is_error: bool) -> void:
	status_label.text = text
	status_label.add_theme_color_override("font_color", Color("#FF6B6B") if is_error else Color("#FFD20A"))
