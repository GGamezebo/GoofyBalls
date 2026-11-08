extends TestCase

## core/lib/fsm: transitions, enter/leave order, payloads, final state, restore_state.


class Probe extends FSMState:
	var log: Array

	func _init(p_name: String, p_log: Array) -> void:
		super(p_name)
		log = p_log

	func enter(_prev_state: FSMState, event_data: Dictionary) -> void:
		log.append("enter:%s:%s" % [state_name, str(event_data.get("v", ""))])

	func leave(_event_data: Dictionary) -> void:
		log.append("leave:%s" % state_name)


func _make(log: Array) -> FSM:
	return FSM.new({
		"initial": {"state": "a"},
		"transitions": [
			{"src": "a", "dst": "b", "event": "go"},
			{"src": "b", "dst": "c", "event": "end"},
		],
		"states": [Probe.new("a", log), Probe.new("b", log), Probe.new("c", log)],
		"final": "c",
	})


func test_transitions_and_payload() -> void:
	var log: Array = []
	var fsm := _make(log)
	expect_eq(fsm.get_current_state_name(), "a", "starts in the initial state")
	expect(not fsm.can_fire("end"), "end is not valid from a")
	fsm.add_event("go", {"v": 7})
	expect_eq(fsm.get_current_state_name(), "b", "go: a → b")
	expect_eq(log, ["enter:a:", "leave:a", "enter:b:7"], "leave before enter, payload passed")
	fsm.add_event("end")
	expect(fsm.is_finished(), "c is final")
	expect(not fsm.can_fire("go"), "nothing fires after the final state")
	fsm.deinit()


func test_restore_state_skips_callbacks() -> void:
	var log: Array = []
	var fsm := _make(log)
	fsm.restore_state("b")
	expect_eq(fsm.get_current_state_name(), "b", "restored to b")
	expect_eq(log, ["enter:a:"], "restore runs no leave / enter")
	expect(fsm.can_fire("end"), "transitions follow the restored state")
	fsm.deinit()
