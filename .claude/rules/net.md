---
paths:
  - "src/net/**"
  - "server/**"
---
# Net / server
- Clients send inputs only `{x:-100..100, j, a}`; never positions/score.
- MatchSession: Local | Rollback (SyncManager over Nakama relay) | Authoritative (future, same sim in headless Godot). Keep game code session-agnostic.
- Server owns: seed, MatchSetup, tick numbering, input log (ranked), result + rating (Glicko-2).
- Ranked/cups always via relay; P2P (WebRTC) only as optional transport for rooms/casual.
- Cost: batch inputs (30Hz×2 ticks), protobuf, relayed matches for casual; authoritative handler only for ranked.
- Reuse from branch `prototype-3d`: `server/` modules, nakama addon; from `claude/mobile-game-build-run-le59yg`: online_rollback.gd.
