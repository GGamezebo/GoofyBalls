# Project (always)
- Layout: `src/sim/` deterministic sim · `src/view/` rendering/fx · `src/net/` sessions/online · `src/ui/` menus · `core/lib/` shared libs · `server/` Nakama · `tests/` headless.
- Sim is the only gameplay truth; view/net/ui never change game state directly.
- Never assume 2 players or left/right: N teams × N players, indices only.
- No pay-to-win: purchasable stuff is cosmetic only, never touches sim.
- Docs in Russian; code, identifiers, commits in English.
- Changed a rule-worthy decision → update the matching rule file + doc in the same commit.
