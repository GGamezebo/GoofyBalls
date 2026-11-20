class_name FSMState
extends RefCounted

## State of `FSM`, ported from quizmatik `core/lib/fsm/fsm/fsm_state.gd` (`RefCounted` instead
## of `Node`, int `state_id` instead of a name). Subclass and override `enter` / `leave` /
## `reenter`; fire transitions with `add_event`. Holds the FSM weakly, so FSM ↔ states never
## form a reference cycle.

## Value of the owner's state enum (e.g. `VolleySim.Phase.SERVE`).
var state_id: int
var fsm: WeakRef

func _init(p_state_id: int) -> void:
	state_id = p_state_id

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

## Readable name for logs. Default: the id as text; override to map the owner's enum,
## e.g. `return MyEnum.keys()[state_id].to_lower()`.
func get_state_name() -> String:
	return str(state_id)

func sync_fsm(p_fsm) -> void:
	fsm = weakref(p_fsm)
