class_name SimDebugEvents
extends Resource

## Simulation debug tab ↔ the battle context (shared `.tres`).

## Panel → owner: run the cross-platform determinism probe.
@warning_ignore("unused_signal")
signal ev_probe_requested
## Owner → panel: {"ok": bool, "hash": int, "expected": int, ...}.
@warning_ignore("unused_signal")
signal ev_probe_result(result: Dictionary)
