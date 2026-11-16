class_name FriendRoomPanel
extends Node

## «С другом» flow of the menu: connects the `FriendWindow` to the online context (create / join a
## room, show its code, status and errors, change the server). Menu creates it and calls
## `initialize()` / `deinit()`; it needs nothing back.

@export var online_events: OnlineEvents
@export var online_config: OnlineConfig
@export var window: FriendWindow

var _listener := EventListener.new()


func initialize() -> void:
	_listener.add(window.ev_create_pressed, _on_create_pressed)
	_listener.add(window.ev_join_pressed, _on_join_pressed)
	_listener.add(window.ev_closed, _on_closed)
	_listener.add(window.ev_server_submitted, _on_server_submitted)
	_listener.add(online_events.ev_room_created, _on_room_created)
	_listener.add(online_events.ev_room_status, func(text: String) -> void: window.set_status(text, false))
	_listener.add(online_events.ev_room_error, _on_room_error)
	window.set_server_address(online_config.address())


func deinit() -> void:
	_listener.deinit()


func _on_create_pressed() -> void:
	window.set_busy(true)
	window.set_status("Подключаемся к серверу…", false)
	online_events.ev_create_room.emit()


func _on_join_pressed(code: String) -> void:
	window.set_busy(true)
	window.set_status("Ищем комнату %s…" % code, false)
	online_events.ev_join_room.emit(code)


func _on_room_created(code: String) -> void:
	window.show_code(code)
	window.set_status("Ждём друга… Скажи ему код.", false)


func _on_room_error(text: String) -> void:
	window.set_busy(false)
	window.set_status(text, true)


## Closing the window drops a room that was being opened (no-op when there is none).
func _on_closed() -> void:
	online_events.ev_leave_room.emit()


func _on_server_submitted(address: String) -> void:
	online_events.ev_set_server.emit(address)
	window.set_server_address(online_config.address())
	window.set_status("Сервер: %s" % online_config.address(), false)
