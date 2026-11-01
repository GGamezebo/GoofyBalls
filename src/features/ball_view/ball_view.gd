class_name BallView
extends Node2D

## Glowing volleyball (concept). The look lives in ball_view.tscn and is tuned there in the editor:
## Body (Halo, Base, Light, Seams, Rim) is drawn for a ball of `design_radius_px`, Shadow and
## Trail next to it. The script only moves those nodes:
## - Body is scaled to the real radius, Seams spin with the ball's horizontal speed;
## - Shadow sits on the floor and shrinks / fades with height;
## - Trail follows the flying ball (its points in the scene are an editor preview only).
## View-only state (spin, trail) never feeds back.

## Ball radius the nodes in the scene are drawn for.
@export var design_radius_px: float = 64.0
@export_group("Trail")
@export var trail_points: int = 5
@export var trail_spacing_px: float = 14.0
@export_group("Shadow")
## Height (in ball radii) where the shadow is the faintest.
@export var shadow_fade_radii: float = 10.0
@export_range(0.0, 1.0) var shadow_min_fade: float = 0.1
## Shadow size at the faintest, relative to the size on the floor.
@export_range(0.0, 1.0) var shadow_min_size: float = 0.5
@export_group("Nodes")
@export var body: Node2D
@export var seams: Node2D
@export var shadow: Node2D
@export var trail: Line2D

var radius_px: float = 64.0:
	set(value):
		radius_px = value
		_apply_size()

var _shadow_scale := Vector2.ONE
var _shadow_alpha: float = 1.0
var _trail_width: float = 0.0
var _history := PackedVector2Array()


func _ready() -> void:
	_shadow_scale = shadow.scale
	_shadow_alpha = shadow.modulate.a
	_trail_width = trail.width
	trail.clear_points()
	_apply_size()


func setup(p_radius_px: float) -> void:
	radius_px = p_radius_px
	_history.clear()
	trail.clear_points()


func apply(pos: Vector2, vx_mps: float, frozen: bool, floor_y: float, px_per_m: float, delta: float) -> void:
	position = pos
	seams.rotation += vx_mps * px_per_m * delta / maxf(radius_px, 1.0)

	var floor_offset := floor_y - pos.y
	var height := maxf(0.0, floor_offset - radius_px)
	var fade := clampf(1.0 - height / (shadow_fade_radii * radius_px), shadow_min_fade, 1.0)
	shadow.position = Vector2(0.0, floor_offset)
	shadow.scale = _shadow_scale * _size_factor() * lerpf(shadow_min_size, 1.0, fade)
	shadow.modulate.a = _shadow_alpha * fade

	_update_trail(frozen)


func _update_trail(frozen: bool) -> void:
	if frozen:
		_history.clear()
		trail.clear_points()
		return
	var here := trail.to_local(global_position)
	if _history.is_empty() or _history[-1].distance_to(here) >= trail_spacing_px:
		_history.append(here)
		while _history.size() > trail_points:
			_history.remove_at(0)
	var points := _history.duplicate()
	if points[-1] != here:
		points.append(here)
	trail.points = points


func _apply_size() -> void:
	if not is_node_ready():
		return
	var k := _size_factor()
	body.scale = Vector2(k, k)
	trail.width = _trail_width * k


func _size_factor() -> float:
	return radius_px / maxf(design_radius_px, 1.0)
