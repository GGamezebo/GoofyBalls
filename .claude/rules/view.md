---
paths:
  - "src/view/**"
  - "src/ui/**"
---
# View / UI
- Pure function of SimState (+ local interpolation); never write to sim.
- 2D, dark neon, glow; gameplay objects brightest. Details: `concept/art-direction.md`.
- Blob = spring-ring soft body (16–24 pts) + highlight + outline; limbs appear from buffs.
- Blob rest shape = circle (slightly flat on floor); squash/stretch preserves area. Ref: `concept/jump.png`.
- Renderer: Compatibility (web/mobile). Keep 60fps on low-end phones.
- Touch: left half = move drag; right = Jump + Action. Local 2P hidden on mobile (`OS.has_feature("mobile")`).
