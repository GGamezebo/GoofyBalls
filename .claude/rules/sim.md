---
paths:
  - "src/features/volley_sim/**"
  - "tests/**"
---
# volley_sim (deterministic, rollback-safe)
- `RefCounted`, no nodes/engine physics/`randf`/wall-clock; ticks @60Hz.
- Floats: `+ - * /`, `sqrt` only; no sin/cos/atan2 → table or stored vectors.
- RNG: xorshift int in state, seed from `MatchSetup`.
- State = plain Dictionary/Arrays; supports save/load/hash. Fixed iteration order.
- Match phases (serve/play/point/end) live in sim state — no separate GameManager FSM for rules.
- Physics values via `param(name, target)` (preset ⊕ modifiers).
- Visual events → `*_serial` counters; no signals/fx from `step()`.
- Hitboxes circles/capsules; deformation is view-only.
- Keep determinism + save/load hash tests green.
