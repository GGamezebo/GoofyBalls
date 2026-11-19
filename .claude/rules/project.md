# Project (always) — approaches mirror GGamezebo/quizmatik
Layout:
- `main.tscn` → `src/game/main.gd` HFSM bootstrap · `src/game/hfsm/app_hfsm.json` app phases
- `src/game/scenes/{app_root,online,room,menu,game,post_battle,debug_panel}` orchestration only (`online` = App/Online context beside Menu/Battle, turns `OnlineEvents` into HFSM events; `debug_panel` = App/Debug, non-release debug window: AppRoot opens it via `ev.open_debug` when `OS.is_debug_build()`, contexts enable its tabs, each tab in `debug_panel/panels/{name}/`; `room` = nested App/Online/Room: one friend room + Nakama connection, closes itself on `ev.open_menu`); `game` also owns the battle rules `game/volley_sim/` (+`phases/`, `state/`, `buffs/`; deterministic `RefCounted`, `sim.md`), like quizmatik `game_logic`
- `src/features/{name}/` isolated features (.gd+.tscn colocated): `match_session` (Local/Rollback, net tuning, lag emulation), `court_view`, `buff_fx`, `nakama_room` (Nakama client, friend room protocol, WebRTC link), `virtual_controls`, `ai_opponent`
- `src/entities/{blob,ball}/` entities built from shared components · `src/entities/components/{floor_shadow}/` their shared parts (`entities.md`)
- `src/common/` shared Resources/presets (.tres) · `src/ui/{theme,components,dialogs,overlays,backgrounds}/` shared game UI (`ui.md`) · `core/` project-agnostic libs (never import `src/`) · `server/` Nakama · `tests/` headless · `tools/` generators · `concept/` art (Godot-ignored)
Must:
- Feature talks out only via `ev_*` signals + `initialize`/`setup`; never import another feature's internals; scenes compose features.
- Every scene runs alone (F6): defaults in exported `.tres`; parent overrides via event → `initialize(data)` → `ResourceUtils.update_resource`.
- No new autoloads/singletons (use RootEvents/GameEvents Resources); exception: third-party plugins like rollback `SyncManager`. See `architecture.md`.
- `class_name`/`@export` over hardcoded `res://`.
- Mobile + Steam + HTML5: touch and KBM/gamepad; platform code only in platform HFSM contexts (`architecture.md`).
- volley_sim is the only gameplay truth; never assume 2 players/left-right (N teams × N players).
- No pay-to-win: cosmetics never touch sim.
- Docs Russian; code/identifiers/commits English.
- Structural/convention change → update matching rule + doc in same commit; rules ≤ ~50 lines, one concern each.
