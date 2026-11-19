class_name DebugEvents
extends Resource

## App/Debug state events (shared `.tres`, no autoload). A context enables its tab in
## `initialize` and disables it in `deinit`; the DebugPanel context listens. In release builds
## the state is never opened, so nobody listens and emitting costs nothing.

@warning_ignore("unused_signal")
signal ev_tab_enabled(tab: DebugTabDef)
@warning_ignore("unused_signal")
signal ev_tab_disabled(tab: DebugTabDef)
