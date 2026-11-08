class_name FSMState
extends RefCounted

## State of `FSM`, ported from quizmatik `core/lib/fsm/fsm/fsm_state.gd` (`RefCounted` instead
## of `Node`). Subclass and override `enter` / `leave` / `reenter`; fire transitions with
## `add_event`. Holds the FSM weakly, so FSM ↔ states never form a reference cycle.

var state_name: String
var fsm: WeakRef

func _init(_state_name: String) -> void:
	state_name = _state_name

func deinit() -> void:
	pass

func enter(_prev_state: FSMState, _event_data: Dictionary) -> void:
	pass

func leave(_event_data: Dictionary) -> void:
	pass

func reenter(_event_data: Dictionary) -> void:
	pass

func add_event(event_name: String, event_data: Dictionary = {}) -> void:
	var fsm_obj = fsm.get_ref()
	if fsm_obj:
		fsm_obj.add_event(event_name, event_data)

func sync_fsm(p_fsm) -> void:
	fsm = weakref(p_fsm)
