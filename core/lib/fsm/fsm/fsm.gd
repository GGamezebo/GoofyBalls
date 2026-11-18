class_name FSM
extends RefCounted

## Event-driven finite state machine, ported from quizmatik `core/lib/fsm/fsm/fsm.gd`.
## Differences: `RefCounted` instead of `Node` (usable inside pure-logic code such as a
## deterministic sim), `restore_state()` to jump back to a saved state (rollback), and states
## are ints (values of the owner's enum) instead of strings, so a snapshot can store them as is.
## Config: {"initial": {"state": int, "event"?}, "transitions": [{"src"?, "dst": int, "event"}],
## "states"?: [FSMState], "final"?: int}. `src` may be an id, an Array of ids or ALL_STATES.
## Names for logs come from `FSMState.get_state_name()`.

signal ev_state_changed(from_state: int, to_state: int)

# Special state ids (never valid enum values: enums start at 0)
const ALL_STATES := -1
const SAME_DST := -2
const INIT_STATE := -3
const NO_STATE := -4
const INIT_EVENT_NAME = "__default_root_setup_event"

var _states_map: Dictionary = {}        # {state_id: FSMState}
var _transaction_map: Dictionary = {}   # {event_name: {src_state_id: dst_state_id}}
var _current_state: int = INIT_STATE
var _final_state: int = NO_STATE
var _event_queue: Array = []
var _is_running: bool = false
var _callbacks: Dictionary = {}         # {Vector2i(from, to): [Callable]}

func _init(cfg: Dictionary):
	_setup(cfg)

func _setup(cfg: Dictionary):
	if not cfg.has("initial"):
		push_error("FSM Config: missing 'initial'")
		return

	var initial = cfg["initial"]
	var initial_event = initial.get("event", INIT_EVENT_NAME)

	if not cfg.has("transitions"):
		push_error("FSM Config: missing 'transitions'")
		return

	# Register provided state objects
	if cfg.has("states"):
		for state in cfg["states"]:
			state.sync_fsm(self)
			_states_map[state.state_id] = state

	# Build the transition table
	_add_transaction(INIT_STATE, int(initial["state"]), initial_event)

	for t in cfg["transitions"]:
		_add_transaction(t["src"] if t.has("src") else ALL_STATES, int(t["dst"]), t["event"])

	_final_state = int(cfg.get("final", NO_STATE))

	# Initial startup
	if not initial.has("event"):
		add_event(INIT_EVENT_NAME)

func deinit():
	for key in _states_map:
		_states_map[key].deinit()
	_states_map.clear()
	_transaction_map.clear()
	_callbacks.clear()
	_event_queue.clear()
	_is_running = false

func add_callback(from_state: int, to_state: int, callback: Callable):
	var key := Vector2i(from_state, to_state)
	if not _callbacks.has(key):
		_callbacks[key] = []
	_callbacks[key].append(callback)

func remove_callback(from_state: int, to_state: int, callback: Callable):
	var key := Vector2i(from_state, to_state)
	if _callbacks.has(key):
		_callbacks[key].erase(callback)

func add_event(event_name: String, event_data: Dictionary = {}):
	_event_queue.append({"name": event_name, "data": event_data})

	if _is_running:
		return

	_is_running = true
	_run_queue()
	_is_running = false

func _run_queue():
	while _event_queue.size() > 0:
		var event = _event_queue.pop_front()
		_process_event(event["name"], event["data"])

func _process_event(event_name: String, event_data: Dictionary):
	if not can_fire(event_name):
		push_error("FSM Error: event %s invalid in state %s" % [event_name, state_to_string(_current_state)])
		return

	var src := _current_state
	var transitions: Dictionary = _transaction_map[event_name]
	var dst: int = transitions.get(src, transitions.get(ALL_STATES))

	if dst == SAME_DST:
		dst = src

	if _current_state != dst:
		var prev_state: FSMState = _states_map[_current_state]
		prev_state.leave(event_data)

		_current_state = dst
		var current_state: FSMState = _states_map[_current_state]
		current_state.enter(prev_state, event_data)

		_call_callbacks(prev_state.state_id, current_state.state_id)
	else:
		_states_map[_current_state].reenter(event_data)

## Jump to `state_id` without leave / enter / callbacks: the owner restored a snapshot whose
## state was saved elsewhere (rollback, save/load). Pending events are dropped.
func restore_state(state_id: int) -> void:
	if not _states_map.has(state_id):
		push_error("FSM Error: restore to unknown state %s" % state_to_string(state_id))
		return
	_event_queue.clear()
	_current_state = state_id

func can_fire(event: String) -> bool:
	if is_finished() or not _transaction_map.has(event):
		return false
	var transitions = _transaction_map[event]
	return transitions.has(_current_state) or transitions.has(ALL_STATES)

func is_finished() -> bool:
	return _final_state != NO_STATE and _current_state == _final_state

func _add_transaction(src, dst: int, event: String):
	var srcs: Array = []
	if src is Array:
		srcs = src
	else:
		srcs = [src]

	# Auto-create states missing from statesMap
	for s_id in srcs:
		_ensure_state(int(s_id))
	_ensure_state(dst)

	if not _transaction_map.has(event):
		_transaction_map[event] = {}

	for s_id in srcs:
		_transaction_map[event][int(s_id)] = dst

func _ensure_state(state_id: int):
	if state_id != SAME_DST and state_id != ALL_STATES and not _states_map.has(state_id):
		var new_state = FSMState.new(state_id)
		new_state.sync_fsm(self)
		_states_map[state_id] = new_state

func _call_callbacks(from_id: int, to_id: int) -> void:
	ev_state_changed.emit(from_id, to_id)
	var key := Vector2i(from_id, to_id)
	if _callbacks.has(key):
		for callback in _callbacks[key]:
			if callback.is_valid():
				callback.call(from_id, to_id)

func get_current_state_id() -> int:
	return _current_state

## Object of the current state (null before the initial event fired).
func get_current_state() -> FSMState:
	return _states_map.get(_current_state)

## Readable name of a state id for logs: the state object's `get_state_name()`, else the number.
func state_to_string(state_id: int) -> String:
	if state_id == INIT_STATE:
		return "init"
	var state: FSMState = _states_map.get(state_id)
	return state.get_state_name() if state != null else str(state_id)
