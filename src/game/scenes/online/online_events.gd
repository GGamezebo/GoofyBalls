class_name OnlineEvents
extends Resource

## Contract of the App/Online context (shared `.tres`). Menu, battle and results talk to the
## online connection only through these signals; nobody holds a reference to the context.

# --- requests (menu / battle / results → online) ---
@warning_ignore("unused_signal")
signal ev_create_room
@warning_ignore("unused_signal")
signal ev_join_room(code: String)
## Drop the room being opened (friend window closed). Going back to the menu closes a room by
## itself (HFSM App/Online/Room leaves on `ev.open_menu`), nobody has to send this then.
@warning_ignore("unused_signal")
signal ev_leave_room
@warning_ignore("unused_signal")
signal ev_rematch_request
## "host:port" typed by the player; saved to user://online.cfg.
@warning_ignore("unused_signal")
signal ev_set_server(address: String)

# --- answers (online → UI) ---
@warning_ignore("unused_signal")
signal ev_room_created(code: String)
## Progress line for the friend window ("" hides it).
@warning_ignore("unused_signal")
signal ev_room_status(text: String)
@warning_ignore("unused_signal")
signal ev_room_error(text: String)
## Results screen: rematch progress ("Ждём соперника…").
@warning_ignore("unused_signal")
signal ev_rematch_status(text: String)
@warning_ignore("unused_signal")
signal ev_opponent_left
