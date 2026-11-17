extends IScene

## App/Online context: entry point of everything online. Lives next to Menu / Battle /
## PostBattle and turns OnlineEvents requests into HFSM events; the connection itself lives in
## the nested App/Online/Room state (`room` scene), which opens on create / join and closes by
## itself on return to the menu (`ev.open_menu`) or `ev_leave_room`.
## Later: the rated matchmaking queue becomes another nested state here.

@export var online_events: OnlineEvents
@export var online_config: OnlineConfig
@export var log_settings: LogSettings

var _listener := EventListener.new()
var _log: LogChannel


func initialize(_data: Dictionary) -> void:
	_log = LogChannel.new("online", log_settings)
	online_config.load_overrides()
	_listener.add(online_events.ev_create_room, func() -> void: add_event("ev.open_room", {"code": ""}))
	_listener.add(online_events.ev_join_room, func(code: String) -> void: add_event("ev.open_room", {"code": code}))
	_listener.add(online_events.ev_leave_room, func() -> void: add_event("ev.close_room"))
	_listener.add(online_events.ev_set_server, _on_set_server)
	_log.info("ready", {"server": online_config.address()})


func deinit() -> void:
	_listener.deinit()
	super.deinit()


## Saved for the next room: an open room keeps the server it connected to.
func _on_set_server(address: String) -> void:
	if online_config.set_address(address):
		_log.info("server_changed", {"server": online_config.address()})
	else:
		online_events.ev_server_address_invalid.emit(address)
