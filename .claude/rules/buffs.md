---
paths:
  - "src/game/scenes/game/volley_sim/buffs/**"
  - "src/features/buff_fx/**"
---
# Buffs / env events
Effects plug into the sim core, never patch it. Details: `docs/tech/architecture.md` §5.
- Kinds: PASSIVE (character), PICKUP (1 slot, Action button), ENV (global, EnvDirector).
- Action: use held pickup; empty → `self_destruct` (once per rally, out until rally ends).
- Pickup sources: blob touch · ball hits it after our touch (`ball.last_toucher`) · granted by ENV.
- New buff = `volley_sim/buffs/<id>.tres` (`BuffDef`: int id, kind, duration, modifiers, view fields) + optional `<id>.gd` (extends `BuffBase`) + BuffRegistry entry + `buff_fx/<id>` visual. Number/view-only effects (moon, ice, giant, flip) = `.tres` only.
- `BuffBase` is stateless like `SimPhase`: no fields, one instance per match; runtime data only in `SimState` (`modifiers[]`, `hazards[]`, player pickup slot).
- Hooks, called by the core at fixed tick points: on_grant/on_activate/on_tick/on_contact/on_rally_end/on_expire; world objects: on_hazard_tick, on_ball_overlap (inside ball substeps), on_player_overlap.
- Effects only via sim API: add_modifier, spawn_hazard, despawn, apply_impulse, teleport, explode, rng.
- World objects = one generic `SimHazard` (def_id, shape, x/y/vx/vy, size, ticks_left, owner, link, data slots a/b/c). A new buff never changes the `to_dict()` schema.
- Core lacks a capability → add a generic verb/hook the next effects can reuse; never `if def_id == X`.
- `teleport` bumps the object's `warp_serial`; views snap on it instead of smoothing it as a rollback correction.
- Modifiers: GLOBAL|TEAM|PLAYER|BALL, ticks_left (-1 permanent); removed on expire.
- Registry order and state array order = hook call order; int ids, no string `match`.
- ENV: 1–2s warning first. Camera tilt/flip = `state.view`, not physics.
- `buff_fx` reads sim `state` only as data, never imports sim types (sim lives in the `game` context); `def_id` → template `.tscn` via its own `.tres`.
- Add to the generic buff test.
