class_name BlobView
extends Node2D

## Jelly blob (concept/art-direction.md). The look lives in blob_view.tscn and is tuned there in the
## editor: Body/Squash/Art (Halo, Base, Light, Outline, Shine, Sparkle, eyes) is drawn for a blob of
## `design_radius_px`. Parts are drawn in white: those in `tinted` take the team color at setup,
## those in `tinted_light` a lighter one (their alpha stays); Light is white on top of the body,
## so it lightens any team color.
## The script only moves those nodes:
## - Body is scaled to the real radius, Squash squashes / stretches around the bottom point
##   (the blob stays on the floor), pupils look at the ball;
## - Shadow sits on the floor and shrinks / fades with height, the name stays above.
## Pure function of what `apply()` gets.

## Blob radius the nodes in the scene are drawn for.
@export var design_radius_px: float = 128.0
@export_group("Squash")
## Vertical stretch per m/s of vertical speed while in the air.
@export var stretch_per_mps: float = 0.012
@export var max_stretch: float = 1.18
## Always a little flat on the floor.
@export var rest_squash: float = 0.06
@export var land_squash: float = 0.28
@export var land_squash_sec: float = 0.18
## Short squash when the blob touches the ball (`pulse()`).
@export var hit_squash: float = 0.12
@export var hit_squash_sec: float = 0.15
@export_group("Eyes")
## How far pupils move toward the ball, in scene pixels (design radius).
@export var pupil_travel_px: float = 9.0
@export_group("Shadow")
## Height (in blob radii) where the shadow is the faintest.
@export var shadow_fade_radii: float = 6.0
@export_range(0.0, 1.0) var shadow_min_fade: float = 0.15
## Shadow size at the faintest, relative to the size on the floor.
@export_range(0.0, 1.0) var shadow_min_size: float = 0.63
@export_group("Team color")
## How much lighter than the team color `tinted_light` parts and the name are.
@export_range(0.0, 1.0) var light_tint: float = 0.35
@export_group("Name")
## Gap between the top of the blob and the name.
@export var name_gap_px: float = 28.0
@export_group("Nodes")
@export var body: Node2D
@export var squash: Node2D
@export var shadow: Node2D
@export var pupils: Array[Node2D] = []
## White parts that take the team color.
@export var tinted: Array[CanvasItem] = []
## White parts that take the lighter team color (`light_tint`).
@export var tinted_light: Array[CanvasItem] = []
@export var name_label: Label

var color: Color = Color("#03B8FF")
var radius_px: float = 128.0:
	set(value):
		radius_px = value
		_apply_size()

var _shadow_scale := Vector2.ONE
var _shadow_alpha: float = 1.0
var _pupil_rest: Array[Vector2] = []
var _was_on_floor: bool = true
var _land_t: float = 0.0
var _hit_t: float = 0.0


func _ready() -> void:
	_shadow_scale = shadow.scale
	_shadow_alpha = shadow.modulate.a
	for pupil in pupils:
		_pupil_rest.append(pupil.position)
	_apply_size()


func setup(p_color: Color, p_radius_px: float, display_name: String, is_local: bool) -> void:
	color = p_color
	var light := color.lightened(light_tint)
	for part in tinted:
		part.self_modulate = Color(color, part.self_modulate.a)
	for part in tinted_light:
		part.self_modulate = Color(light, part.self_modulate.a)
	if name_label != null:
		name_label.text = ("ТЫ" if is_local else display_name)
		name_label.add_theme_color_override("font_color", light)
	radius_px = p_radius_px


## `pos` = body center (px), `floor_y` = floor line (px), `look_target` = ball (px).
func apply(pos: Vector2, vy_mps: float, on_floor: bool, floor_y: float, look_target: Vector2, delta: float) -> void:
	position = pos
	if on_floor and not _was_on_floor:
		_land_t = 1.0
	_was_on_floor = on_floor
	_land_t = maxf(0.0, _land_t - delta / land_squash_sec)
	_hit_t = maxf(0.0, _hit_t - delta / hit_squash_sec)

	var stretch := 1.0
	if not on_floor:
		stretch = clampf(1.0 + absf(vy_mps) * stretch_per_mps, 1.0, max_stretch)
	var flat := (rest_squash if on_floor else 0.0) + land_squash * _land_t + hit_squash * _hit_t
	var sy := stretch * (1.0 - flat)
	squash.scale = Vector2(1.0 / sy, sy)

	var to_ball := look_target - pos
	var look := to_ball.normalized() if to_ball.length() > 1.0 else Vector2.ZERO
	for i in pupils.size():
		pupils[i].position = _pupil_rest[i] + look * pupil_travel_px

	var floor_offset := floor_y - pos.y
	var height := maxf(0.0, floor_offset - radius_px)
	var fade := clampf(1.0 - height / (shadow_fade_radii * radius_px), shadow_min_fade, 1.0)
	shadow.position = Vector2(0.0, floor_offset)
	shadow.scale = _shadow_scale * _size_factor() * lerpf(shadow_min_size, 1.0, fade)
	shadow.modulate.a = _shadow_alpha * fade


## Short squash when this blob touches the ball.
func pulse() -> void:
	_hit_t = 1.0


func _apply_size() -> void:
	if not is_node_ready():
		return
	var k := _size_factor()
	body.scale = Vector2(k, k)
	if name_label != null:
		name_label.position = Vector2(-name_label.size.x * 0.5, -radius_px - name_gap_px - name_label.size.y)


func _size_factor() -> float:
	return radius_px / maxf(design_radius_px, 1.0)
