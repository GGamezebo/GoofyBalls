extends TestCase

## core/lib/fsm: transitions, enter/leave order, payloads, final state, restore_state, names.

enum S { A, B, C }


class Probe extends FSMState:
	var log: Array

	func _init(p_id: int, p_log: Array) -> void:
		super(p_id)
		log = p_log

	func enter(_prev_state: FSMState, event_data: Dictionary) -> void:
		log.append("enter:%s:%s" % [get_state_name(), str(event_data.get("v", ""))])

	func leave(_event_data: Dictionary) -> void:
		log.append("leave:%s" % get_state_name())

	func get_state_name() -> String:
		return S.keys()[state_id].to_lower()


func _make(log: Array, with_states: bool = true) -> FSM:
	var cfg := {
		"initial": {"state": S.A},
		"transitions": [
			{"src": S.A, "dst": S.B, "event": "go"},
			{"src": S.B, "dst": S.C, "event": "end"},
		],
		"final": S.C,
	}
	if with_states:
		cfg["states"] = [Probe.new(S.A, log), Probe.new(S.B, log), Probe.new(S.C, log)]
	return FSM.new(cfg)


func test_transitions_and_payload() -> void:
	var log: Array = []
	var fsm := _make(log)
	expect_eq(fsm.get_current_state_id(), S.A, "starts in the initial state")
	expect(not fsm.can_fire("end"), "end is not valid from a")
	fsm.add_event("go", {"v": 7})
	expect_eq(fsm.get_current_state_id(), S.B, "go: a → b")
	expect_eq(log, ["enter:a:", "leave:a", "enter:b:7"], "leave before enter, payload passed")
	fsm.add_event("end")
	expect(fsm.is_finished(), "c is final")
	expect(not fsm.can_fire("go"), "nothing fires after the final state")
	fsm.deinit()


func test_restore_state_skips_callbacks() -> void:
	var log: Array = []
	var fsm := _make(log)
	fsm.restore_state(S.B)
	expect_eq(fsm.get_current_state_id(), S.B, "restored to b")
	expect(fsm.get_current_state() is Probe and fsm.get_current_state().state_id == S.B, "current state object follows")
	expect_eq(log, ["enter:a:"], "restore runs no leave / enter")
	expect(fsm.can_fire("end"), "transitions follow the restored state")
	fsm.deinit()


func test_state_names_for_logs() -> void:
	var fsm := _make([])
	expect_eq(fsm.state_to_string(S.C), "c", "overridden get_state_name is used")
	var changes: Array = []
	fsm.ev_state_changed.connect(func(from: int, to: int) -> void: changes.append([from, to]))
	fsm.add_event("go")
	expect_eq(changes, [[S.A, S.B]], "ev_state_changed carries ids")
	fsm.deinit()
	var plain := _make([], false)
	expect_eq(plain.state_to_string(S.B), str(S.B), "default get_state_name prints the id")
	expect_eq(FSMState.new(S.C).get_state_name(), str(S.C), "base FSMState name is the id as text")
	plain.deinit()
