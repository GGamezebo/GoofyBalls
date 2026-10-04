---
paths:
  - "src/sim/buffs/**"
  - "src/view/fx/**"
---
# Buffs / env events
- Kinds: PASSIVE (character), PICKUP (1 slot, used by Action button), ENV (global, from EnvDirector).
- Action button: use held pickup; if empty → `self_destruct` (once per rally, player out until rally ends).
- Pickup sources: blob touch · ball hits it after our touch (`ball.last_toucher`) · granted by ENV.
- New buff = `src/sim/buffs/<id>.gd` (extends BuffBase, hooks on_grant/on_activate/on_tick/on_contact/on_expire) + register in BuffRegistry + `src/view/fx/<id>` visual. Don't edit sim core for a buff.
- Effects only via sim API: add_modifier, spawn_hazard, apply_impulse, explode, rng.
- Modifiers: target GLOBAL|TEAM|PLAYER|BALL, ticks_left (-1 = permanent); must be removed on expire.
- ENV events show a 1–2s warning before applying. Camera tilt/flip = `state.view`, not physics.
- Add the buff to the generic buff test.
