class_name NetDebugPanel
extends VBoxContainer

## Debug dock tab for online matches: link, ping, input delay, rollbacks, skipped ticks,
## desyncs, FPS, plus lag emulation presets for our outgoing traffic.
## Talks only through `NetDebugEvents`: asks for the preset titles when it appears and pulls
## stats while it is on screen; the session owner (battle context) answers.

@export var events: NetDebugEvents
@export var stats_label: Label
@export var lag_buttons: Array[Button] = []
## Stats refresh period (s) while the tab is on screen.
@export var refresh_sec: float = 0.25

var _listener := EventListener.new()
var _stats: Dictionary = {}
var _refresh_left: float = 0.0


func _ready() -> void:
	for i in lag_buttons.size():
		lag_buttons[i].visible = false
		_listener.add(lag_buttons[i].pressed, func() -> void: events.ev_lag_preset_selected.emit(i))
	_listener.add(events.ev_stats, _on_stats)
	_listener.add(events.ev_lag_presets, _on_lag_presets)
	events.ev_lag_presets_requested.emit()


func _exit_tree() -> void:
	_listener.deinit()


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_refresh_left -= delta
	if _refresh_left > 0.0:
		return
	_refresh_left = refresh_sec
	events.ev_stats_requested.emit()
	stats_label.text = format_stats(_stats, Engine.get_frames_per_second())


func _on_stats(stats: Dictionary) -> void:
	_stats = stats


## One title per emulation preset button; extra buttons are hidden.
func _on_lag_presets(titles: Array[String]) -> void:
	for i in lag_buttons.size():
		lag_buttons[i].visible = i < titles.size()
		if i < titles.size():
			lag_buttons[i].text = titles[i]


static func format_stats(stats: Dictionary, fps: float) -> String:
	if stats.is_empty():
		return "Офлайн\nFPS %d" % fps
	var link := "напрямую (UDP)" if str(stats.get("link", "")) == "p2p" else "через сервер (TCP)"
	var lines: Array[String] = [
		"Связь: %s" % link,
		"Ping %d мс  (ср. %d, макс. %d)" % [stats.get("ping_ms", 0), stats.get("ping_avg", 0), stats.get("ping_max", 0)],
		"Задержка ввода %d тик." % stats.get("input_delay", 0),
		"Откаты %.1f/с, макс. %d тик." % [stats.get("rollbacks_per_sec", 0.0), stats.get("max_rollback", 0)],
		"Пропуски тиков %d, потеря синхр. %d" % [stats.get("skipped_ticks", 0), stats.get("sync_lost", 0)],
		"Рассинхроны %d" % stats.get("mismatches", 0),
		"FPS %d" % fps,
	]
	if not str(stats.get("lag", "")).is_empty():
		lines.append("Эмуляция: %s" % stats["lag"])
	return "\n".join(lines)
