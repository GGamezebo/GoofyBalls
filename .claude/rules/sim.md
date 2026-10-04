---
paths:
  - "src/sim/**"
  - "tests/**"
---
# Sim (deterministic, rollback-safe)
- `RefCounted`, no nodes, no engine physics, no `randf`, no wall-clock; ticks @60Hz.
- Float ops: `+ - * /`, `sqrt` only. No sin/cos/atan2 → lookup table or stored vectors.
- RNG: xorshift int stored in state; seed from MatchSetup.
- State = plain Dictionary/Arrays of primitives; must support save/load/hash.
- Fixed iteration order; never iterate Dictionaries with undefined order.
- Read physics values via `param(name, target)` (preset ⊕ modifiers), never raw constants.
- Visual events → bump `*_serial` counters; never emit signals/fx from `step()`.
- Hitboxes: circles/capsules. Slime deformation is view-only.
- Every change: keep determinism + save/load hash tests green.
