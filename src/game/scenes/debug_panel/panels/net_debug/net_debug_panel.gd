class_name NetDebugPanel
extends DebugTab

## "Сеть" tab of online battles: link, ping, input delay, rollbacks, skipped ticks, desyncs, FPS,
## plus lag emulation presets for our outgoing traffic. Reads the battle's session directly; the
## chosen preset is remembered and applied again in the next online battle.

@export var stats_label: Label
@export var lag_buttons: Array[Button] = []
## Emulation presets, one per button (index 0 = off).
@export var lag_presets: Array[LagProfile] = []
## Stats refresh period (s) while the tab is on screen.
@export var refresh_sec: float = 0.25

var _listener := EventListener.new()
var _session: RollbackSession
var _memory: Dictionary = {}
var _refresh_left: float = 0.0


func accepts(target: Node) -> bool:
	return target.get("_session") is RollbackSession


func attach(target: Node, memory: Dictionary) -> void:
	_session = target.get("_session") as RollbackSession
	_memory = memory
	for i in lag_buttons.size():
		var has_preset := i < lag_presets.size() and lag_presets[i] != null
		lag_buttons[i].visible = has_preset
		if has_preset:
			lag_buttons[i].text = lag_presets[i].title
			_listener.add(lag_buttons[i].pressed, _select_lag.bind(i))
	var remembered := int(_memory.get("lag", 0))
	if remembered > 0:
		_select_lag(remembered)


func detach() -> void:
	_listener.deinit()
	_session = null


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_refresh_left -= delta
	if _refresh_left > 0.0:
		return
	_refresh_left = refresh_sec
	var stats := _session.get_stats() if is_instance_valid(_session) else {}
	stats_label.text = format_stats(stats, Engine.get_frames_per_second())


func _select_lag(index: int) -> void:
	if not is_instance_valid(_session) or index < 0 or index >= lag_presets.size():
		return
	_session.set_lag_profile(lag_presets[index])
	_memory["lag"] = index


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
