---
paths:
  - "src/features/*_view/**"
  - "src/entities/**"
  - "src/features/buff_fx/**"
  - "src/features/virtual_controls/**"
  - "src/game/scenes/game/**"
  - "src/ui/**"
---
# View / battle scene
- Views = pure function of sim state (+ local interpolation); never write to sim.
- Look = nodes in the view's `.tscn` (Sprite2D + GradientTexture2D, Line2D, materials), drawn at a design size and tuned in the editor; script only moves/scales/rotates them. No `_draw()` art. Soft bodies (`entities/ball`, `entities/blob`): spring ring = `core/lib/soft_ring` (`SoftRing` + per-entity `SoftRingConfig` `.tres`; entity computes the target shape), floor shadow = `entities/components/floor_shadow`; ring-shaped `Polygon2D`/`Line2D` keep a design-size circle in the `.tscn` as the editor preview, the script rewrites their points at runtime; color, texture, material and order are tuned on the node, ring sizes in exports. Runtime colors: parts drawn white, script tints listed nodes (`self_modulate`). Repeated parts (nets) = template `.tscn` + `instantiate()`. Ref: `entities/ball`, `entities/blob`, `court_view`.
- `game` scene only orchestrates: builds sim from `MatchSetup`, picks MatchSession, composes views/HUD; HUD listens to `GameEvents`.
- Online the latest ticks are predicted. Result-like events (score, point, match over, results) go out only for confirmed ticks: `MatchEventGate` + `MatchSession.confirmed_tick()`. Instant FX (touch pulse, ball squish) may play on predicted ticks.
- 2D dark neon + glow; gameplay brightest. Ref: `concept/art-direction.md`.
- Blob = spring-ring soft body (16–24 pts) + highlight + outline; rest shape circle (slightly flat on floor); squash/stretch preserves area (`concept/jump.png`). Limbs appear from buffs.
- Keep 60fps on low-end phones; Compatibility-safe effects.
- Touch: left half drag = move; right = Jump + Action.
- Exit battle via `root_events.ev_exit_game` with post-battle payload.
