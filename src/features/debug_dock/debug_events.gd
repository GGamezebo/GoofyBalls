class_name DebugEvents
extends Resource

## App-wide debug dock events (shared `.tres`, no autoload). A context enables its tab in
## `initialize` and disables it in `deinit`; the dock in App root listens. In release builds
## nobody listens, so emitting costs nothing.

@warning_ignore("unused_signal")
signal ev_panel_enabled(panel: DebugPanelDef)
@warning_ignore("unused_signal")
signal ev_panel_disabled(panel: DebugPanelDef)
