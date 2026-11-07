class_name FloorShadow
extends Node2D

## Soft shadow of a body on the floor: stays on the floor line under the owner, fades and shrinks as
## the body rises. Put it on the shadow node of an entity `.tscn`; its texture, base scale and alpha
## are tuned there in the editor, `apply()` only moves, scales and fades it from those.

## Height (in body radii) where the shadow is the faintest.
@export var fade_radii: float = 6.0
@export_range(0.0, 1.0) var min_fade: float = 0.15
## Shadow size at the faintest, relative to the size on the floor.
@export_range(0.0, 1.0) var min_size: float = 0.63

var _base_scale := Vector2.ONE
var _base_alpha: float = 1.0


func _ready() -> void:
	_base_scale = scale
	_base_alpha = modulate.a


## `floor_offset` = floor line below the owner's center (px), `radius_px` = body radius (px),
## `size_factor` = real size / the design size the node was tuned at.
func apply(floor_offset: float, radius_px: float, size_factor: float) -> void:
	var height := maxf(0.0, floor_offset - radius_px)
	var fade := clampf(1.0 - height / (fade_radii * radius_px), min_fade, 1.0)
	position = Vector2(0.0, floor_offset)
	scale = _base_scale * size_factor * lerpf(min_size, 1.0, fade)
	modulate.a = _base_alpha * fade
