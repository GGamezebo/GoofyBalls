---
paths:
  - "src/features/online/**"
  - "server/**"
---
# Online / server
- Clients send inputs only `{x:-100..100, j, a}`; never positions/score.
- MatchSession: Local | Rollback (SyncManager over Nakama relay) | Authoritative (future, same sim headless). Game code session-agnostic.
- Server owns: seed, MatchSetup, tick numbering, input log (ranked), result + rating (Glicko-2).
- Ranked/cups always relay; P2P (WebRTC) only optional for rooms/casual.
- Cost: inputs 30Hz×2 ticks, protobuf, relayed matches casual; authoritative handler only ranked.
- Reuse: `server/` + nakama addon from branch `prototype-3d`; `online_rollback.gd` from `claude/mobile-game-build-run-le59yg`.
