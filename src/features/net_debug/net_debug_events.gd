class_name NetDebugEvents
extends Resource

## Network debug tab ↔ the owner of the match session (shared `.tres`).
## The panel pulls: it asks, the owner answers right away (signals are synchronous), so a
## closed panel costs nothing.

## Panel → owner: send the current stats as `ev_stats`.
@warning_ignore("unused_signal")
signal ev_stats_requested
## Owner → panel: session stats (link, ping, rollbacks, ...); {} = no session data.
@warning_ignore("unused_signal")
signal ev_stats(stats: Dictionary)
## Panel → owner: send the lag emulation preset titles as `ev_lag_presets`.
@warning_ignore("unused_signal")
signal ev_lag_presets_requested
@warning_ignore("unused_signal")
signal ev_lag_presets(titles: Array[String])
## Panel → owner: emulation preset picked (index into the titles).
@warning_ignore("unused_signal")
signal ev_lag_preset_selected(index: int)
