---
paths:
  - "src/features/nakama_room/**"
  - "server/**"
---
# Online / server
- Clients send inputs only `{x:-100..100, j, a}`; never positions/score.
- MatchSession: Local | Rollback (SyncManager; transport per message: P2P if ready, else Nakama relay). No authoritative / headless server sim, ever — don't design for it. Game code session-agnostic.
- Friend rooms: rollback traffic over WebRTC P2P (UDP, `WebRTCTransport`, webrtc-native GDExtension); signaling, room RPCs and fallback over the relay. P2P link reaches the battle via `NetLink` (.tres).
- Server is thin (friends-first game): room codes, match seed, relay, later matchmaking + stored ratings. It never runs or checks the game: no input log, no server tick numbering, no replay validation, no anti-cheat.
- Result + rating: every client of the match reports the final score; equal reports → rating applied, any mismatch or missing report → match not rated. Plain Elo (2×2: team average, same change for both). Collusion/cheating is accepted.
- One matchmaking queue (when built), always rated (stake from rating gap); no separate casual/ranked queues, no cups.
- Rated formats: 1×1 and 2×2 (party, or two solos after 20 s); one shared rating. Rated conditions fixed: Classic + weekly rule, to 7, random arena from the rated pool. 3×3 / 3+ teams: rooms and AI only.
- Queue matches use the same transport as rooms (P2P when the link opens, relay fallback). Relay-only (to hide IPs from strangers) is an option to decide when the queue is built.
- Many players: 2×2 over a full P2P mesh. 6–8 players (phones) → relay star + bigger input delay; decide when built, keep the sim N-player.
- Cost: inputs 30Hz×2 ticks, protobuf, P2P first so the relay carries only fallback traffic.
- Reuse: `server/` + nakama addon from branch `prototype-3d`; `online_rollback.gd` from `claude/mobile-game-build-run-le59yg`.
