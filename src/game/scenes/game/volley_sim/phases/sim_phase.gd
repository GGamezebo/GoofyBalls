class_name SimPhase
extends FSMState

## Base of a match phase inside `VolleySim` (FSM from `core/lib/fsm`).
## - Keeps no runtime fields: everything lives in `sim.state`, so save / load / rollback just work.
##   The sim re-syncs the FSM from `state["phase"]` every tick (`FSM.restore_state`).
## - `enter` writes the phase into the state; `tick` runs once per sim tick while active.
## - Holds the sim weakly (the sim owns the FSM, the FSM owns the phases).

## `VolleySim.Phase` this state stands for (index in the sim's phase list).
var phase: int

var _sim_ref: WeakRef


static func get_state() -> String:
	return ""


func _init(p_state_name: String, p_phase: int) -> void:
	super(p_state_name)
	phase = p_phase


func initialize(sim: VolleySim) -> void:
	_sim_ref = weakref(sim)


func deinit() -> void:
	_sim_ref = null


func enter(_prev_state: FSMState, _event_data: Dictionary) -> void:
	var state: Dictionary = _sim().state
	state["phase"] = phase
	state["phase_ticks"] = 0


## One sim tick while this phase is active (players have already moved).
func tick() -> void:
	pass


func _sim() -> VolleySim:
	return _sim_ref.get_ref() as VolleySim


## Counts ticks spent in this phase; returns the new count.
func _count_tick(state: Dictionary) -> int:
	var ticks := int(state["phase_ticks"]) + 1
	state["phase_ticks"] = ticks
	return ticks
