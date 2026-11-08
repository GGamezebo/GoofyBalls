---
paths:
  - "src/game/scenes/game/volley_sim/**"
  - "tests/**"
---
# volley_sim (deterministic, rollback-safe)
- `RefCounted`, no nodes/engine physics/`randf`/wall-clock; ticks @60Hz.
- Floats: `+ - * /`, `sqrt` only; no sin/cos/atan2 → table or stored vectors.
- RNG: xorshift int in state, seed from `MatchSetup`.
- State = plain Dictionary/Arrays; supports save/load/hash. Fixed iteration order.
- Match phases (serve/play/point/end) = `core/lib/fsm` FSM inside the sim, never a separate GameManager: one `SimPhase` per phase in `volley_sim/phases/` (`get_state()`, `enter`, `tick`), names `SimPhaseStates`, transitions only via `SimPhaseEvents` + `add_event` (int payloads). Truth = `state["phase"]`: phases keep no fields, `step()` re-syncs the FSM (`restore_state`) so save/load/rollback work. New phase = new `SimPhase` + transition in `VolleySim._build_phases`, no `match phase`.
- Physics values via `param(name, target)` (preset ⊕ modifiers); no balance literals in sim code — new number → `PhysicsPreset`/`ArenaPreset`/`RuleSet` field.
- Visual events → `*_serial` counters; no signals/fx from `step()`.
- Hitboxes circles/capsules; deformation is view-only.
- Keep determinism + save/load hash tests green.
