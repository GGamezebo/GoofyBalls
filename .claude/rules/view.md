---
paths:
  - "src/features/*_view/**"
  - "src/features/buff_fx/**"
  - "src/features/virtual_controls/**"
  - "src/game/scenes/game/**"
  - "src/ui/**"
---
# View / battle scene
- Views = pure function of sim state (+ local interpolation); never write to sim.
- Look = nodes in the view's `.tscn` (Sprite2D + GradientTexture2D, Line2D, materials), drawn at a design size and tuned in the editor; script only moves/scales/rotates them. No `_draw()` art. Runtime colors: parts drawn white, script tints listed nodes (`self_modulate`). Repeated parts (nets) = template `.tscn` + `instantiate()`. Ref: `ball_view`, `blob_view`, `court_view`.
- `game` scene only orchestrates: builds sim from `MatchSetup`, picks MatchSession, composes views/HUD; HUD listens to `GameEvents`.
- 2D dark neon + glow; gameplay brightest. Ref: `concept/art-direction.md`.
- Blob = spring-ring soft body (16–24 pts) + highlight + outline; rest shape circle (slightly flat on floor); squash/stretch preserves area (`concept/jump.png`). Limbs appear from buffs.
- Keep 60fps on low-end phones; Compatibility-safe effects.
- Touch: left half drag = move; right = Jump + Action.
- Exit battle via `root_events.ev_exit_game` with post-battle payload.
