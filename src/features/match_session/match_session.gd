class_name MatchSession
extends Node

## Drives the deterministic sim tick loop. Game code is session-agnostic: it hands over
## callables and listens to the signals; where inputs come from (keyboard, bot, network)
## and when ticks run (locally, or re-simulated after a rollback) is the session's business.
##   sample(slot) -> Dictionary   local input of a slot for this tick
##   step(inputs: Array) -> int   advance the sim one tick, return the new tick
##   save() -> Dictionary / load(state) -> void   snapshot / restore (rollback only)

## The tick loop runs (online: both peers are in sync).
@warning_ignore("unused_signal")
signal ev_started
## After every sim step, including re-simulated ones during a rollback.
@warning_ignore("unused_signal")
signal ev_ticked(tick: int)
## State was restored `ticks` back; the following ev_ticked calls re-simulate them.
@warning_ignore("unused_signal")
signal ev_rolled_back(ticks: int)
## Short status for the HUD ("" = clear).
@warning_ignore("unused_signal")
signal ev_status(text: String)
## The tick loop stopped normally (online: the host stopped the match).
@warning_ignore("unused_signal")
signal ev_stopped
## The match cannot continue (opponent left, sync lost, desync).
@warning_ignore("unused_signal")
signal ev_aborted(reason: AbortReason)

## Why a match ended without a result. NONE = it did not abort.
enum AbortReason {
	NONE,
	NO_CONNECTION,
	OPPONENT_MISSING,
	HANDSHAKE_TIMEOUT,
	OPPONENT_LEFT,
	SYNC_ERROR,
	## The tick loop stopped before the match was over (the owner reports it, not the session).
	STOPPED,
}

## Greppable name for logs, e.g. `opponent_left`.
static func abort_reason_name(reason: AbortReason) -> String:
	return String(AbortReason.keys()[reason]).to_lower()


## Player-facing text for the HUD status and the results screen.
static func abort_reason_text(reason: AbortReason) -> String:
	match reason:
		AbortReason.OPPONENT_LEFT:
			return "Соперник отключился"
		AbortReason.SYNC_ERROR:
			return "Связь потеряна"
		AbortReason.HANDSHAKE_TIMEOUT, AbortReason.OPPONENT_MISSING:
			return "Соперник не подключился"
		AbortReason.STOPPED:
			return "Матч остановлен"
	return "Матч прерван"


var _sample: Callable
var _step: Callable
var _save: Callable
var _load: Callable
var _slot_count: int = 0
var _neutral: Dictionary = {}
## Last sim tick whose state can no longer change (see `confirmed_tick()`).
var _confirmed_tick: int = 0


func bind_sim(slot_count: int, sample: Callable, step: Callable, save_fn: Callable, load_fn: Callable, neutral: Dictionary) -> void:
	_slot_count = slot_count
	_sample = sample
	_step = step
	_save = save_fn
	_load = load_fn
	_neutral = neutral


## Begin the match; call after `bind_sim()` and once the session is in the tree.
## `slot_peers[i]` = peer id that owns slot i (offline ignored). Offline starts at once; online
## runs the handshake. false = could not begin (`ev_aborted` was already emitted).
func setup(_slot_peers: Array[int], _log_channel: LogChannel) -> bool:
	start()
	return true


func start() -> void:
	pass


func shutdown() -> void:
	pass


## The local player quits a match that is still running (exit button, scene closed).
## Online sessions tell the opponent first, so they do not sit waiting for our input.
func leave() -> void:
	shutdown()


func set_paused(_paused: bool) -> void:
	pass


## Last sim tick that can no longer be rolled back: every tick up to it ran with real inputs.
## Online it lags the current tick by about the ping; an event at tick T is final once T <= this.
func confirmed_tick() -> int:
	return _confirmed_tick


func is_online() -> bool:
	return false


## Numbers for the net overlay; empty for local play.
func get_stats() -> Dictionary:
	return {}


## Titles of the network emulation presets the debug overlay may offer; empty = none (offline).
func lag_preset_titles() -> Array[String]:
	return []


## Switch network emulation to preset `index` of `lag_preset_titles()`; no-op when out of range.
func select_lag_preset(_index: int) -> void:
	pass
