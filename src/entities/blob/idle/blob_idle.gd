class_name BlobIdle
extends RefCounted

## Endless decorative hop of a blob on a menu or results screen: a sine bounce with rests on the floor between hops.
## Pure math: call `advance(delta)` every frame, then read `height`, `speed` and `grounded`.

## Height above the floor (px, >= 0).
var height: float = 0.0
## Vertical speed, positive = moving up.
var speed: float = 0.0
var grounded: bool = true

var _config: BlobIdleConfig
var _time: float = 0.0


func _init(config: BlobIdleConfig) -> void:
	_config = config


func advance(delta: float) -> void:
	_time += delta
	var phase := fmod(_time, _config.period_sec) / _config.period_sec
	height = maxf(0.0, sin(phase * TAU)) * _config.hop_px
	speed = -cos(phase * TAU) * _config.peak_speed
	grounded = height <= _config.floor_epsilon_px
