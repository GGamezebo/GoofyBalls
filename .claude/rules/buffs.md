---
paths:
  - "src/features/volley_sim/buffs/**"
  - "src/features/buff_fx/**"
---
# Buffs / env events
- Kinds: PASSIVE (character), PICKUP (1 slot, Action button), ENV (global, EnvDirector).
- Action: use held pickup; empty → `self_destruct` (once per rally, out until rally ends).
- Pickup sources: blob touch · ball hits it after our touch (`ball.last_toucher`) · granted by ENV.
- New buff = `volley_sim/buffs/<id>.gd` (extends BuffBase; on_grant/on_activate/on_tick/on_contact/on_expire) + BuffRegistry entry + `buff_fx/<id>` visual. Don't edit sim core.
- Effects only via sim API: add_modifier, spawn_hazard, apply_impulse, explode, rng.
- Modifiers: GLOBAL|TEAM|PLAYER|BALL, ticks_left (-1 permanent); removed on expire.
- ENV: 1–2s warning first. Camera tilt/flip = `state.view`, not physics.
- Add to the generic buff test.
