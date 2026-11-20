class_name BallView
extends Node2D

## Glowing tar volleyball (concept + Gish squish). The look lives in ball_view.tscn and is tuned
## there in the editor: two glow rings, a yellow skin, a light spot, two spinning seams, a dark rim,
## plus a short trail and a floor shadow. The skin, light, glow, seams and rim are a spring ring:
## impacts dent it, a blob it sticks to flattens it, speed stretches it (how much: `squish`, a
## `BallSquishConfig`). The script only moves and reshapes those nodes. View-only state (ring,
## spin, trail) never feeds back into the sim.

## Ball radius the nodes in the scene are drawn for.
@export var design_radius_px: float = 64.0
@export_group("Squish")
## How the ball feels as jelly (spring ring, dents, stretch). Empty = the class defaults.
@export var squish: BallSquishConfig
@export_group("Shape")
## Glow ring sizes and the rim's ring size, relative to the body.
@export var glow_outer_scale: float = 1.45
@export var glow_inner_scale: float = 1.2
@export var rim_scale: float = 0.94
## Line widths as shares of the radius.
@export var seam_width_ratio: float = 0.08
@export var rim_width_ratio: float = 0.12
@export_group("Seams")
## Seam arc center distance from the ball center and arc radius (shares of the radius).
@export var seam_offset: float = 0.9
@export var seam_radius: float = 0.75
## Seam arc length (radians) and the points it is drawn with.
@export var seam_arc: float = 1.8
@export var seam_points: int = 13
@export_group("Trail")
@export var trail_points: int = 5
@export var trail_spacing_px: float = 14.0
@export_group("Nodes")
## Yellow body, reshaped by the ring.
@export var skin: Polygon2D
## Light spot over the skin; the script maps its UVs onto the ring.
@export var shine: Polygon2D
@export var glow_outer: Polygon2D
@export var glow_inner: Polygon2D
@export var seam_a: Line2D
@export var seam_b: Line2D
@export var rim: Line2D
## Fade and size by height are tuned on the node.
@export var shadow: FloorShadow
@export var trail: Line2D

var radius_px: float = 64.0:
	set(value):
		radius_px = value
		_apply_size()

var _trail_width: float = 0.0
var _history := PackedVector2Array()
var _spin: float = 0.0
var _press := Vector2.ZERO
var _stretch: float = 1.0
var _stretch_dir := Vector2.RIGHT
var _ring: SoftRing
var _uvs := PackedVector2Array()


func _ready() -> void:
	_trail_width = trail.width
	trail.clear_points()
	if squish == null:
		squish = BallSquishConfig.new()
	_ring = SoftRing.new(squish)
	# Polygon2D UVs are in texture pixels.
	_uvs = _ring.uvs(shine.texture.get_size() if shine.texture != null else Vector2.ONE)
	_apply_size()


func setup(p_radius_px: float) -> void:
	radius_px = p_radius_px
	_history.clear()
	trail.clear_points()
	if _ring != null:
		_ring.reset()


## `vel_mps` = ball velocity (m/s, y up); `press` = unit direction from the blob the ball sticks
## to towards the ball (screen space), zero when free.
func apply(pos: Vector2, vel_mps: Vector2, frozen: bool, press: Vector2, floor_y: float, px_per_m: float, delta: float) -> void:
	position = pos
	_spin += vel_mps.x * px_per_m * delta / maxf(radius_px, 1.0)
	_press = press
	var speed := vel_mps.length()
	_stretch = 1.0
	if not frozen and press == Vector2.ZERO and speed > squish.stretch_min_mps:
		_stretch_dir = Vector2(vel_mps.x, -vel_mps.y) / speed
		_stretch = minf(1.0 + speed * squish.stretch_per_mps, squish.max_stretch)
	_update_targets()
	_ring.step(delta)
	shadow.apply(floor_y - pos.y, radius_px, _size_factor())
	_update_trail(frozen)
	_update_shapes()


## Splat: the ball was pushed along `push_dir` (screen space) with `power` m/s.
func impact(push_dir: Vector2, power: float) -> void:
	if _ring == null:
		return
	var kick := minf(power, squish.max_impact) * squish.dent_per_mps
	# The contact side faces against the push: it dents in, the sides bulge out.
	_ring.kick(-push_dir, kick, squish.impact_bulge, squish.impact_swell)


## Rest shape per ring point: stretched along the flight, flattened against the sticking blob.
func _update_targets() -> void:
	for i in _ring.size():
		var d := _ring.dirs[i]
		var target := 0.0
		if _stretch > 1.0:
			target += SoftRing.stretch_target(d, _stretch_dir, _stretch)
		if _press != Vector2.ZERO:
			target += SoftRing.flatten_target(d, -_press, squish.stick_flatten)
		_ring.targets[i] = target


## Unit-circle point → deformed body (px), in the ball's local space.
func _warp(p: Vector2) -> Vector2:
	return _ring.warp(p, radius_px)


func _ring_points(ring_scale: float) -> PackedVector2Array:
	return _ring.points(ring_scale, radius_px)


func _update_shapes() -> void:
	if _ring.size() == 0:
		return
	var r := radius_px
	var body := _ring_points(1.0)
	skin.polygon = body
	shine.polygon = body
	shine.uv = _uvs
	glow_outer.polygon = _ring_points(glow_outer_scale)
	glow_inner.polygon = _ring_points(glow_inner_scale)
	for k in 2:
		var seam := seam_a if k == 0 else seam_b
		var angle := _spin + PI * float(k)
		var center := Vector2(cos(angle), sin(angle)) * seam_offset
		var arc := PackedVector2Array()
		for j in seam_points:
			var a := angle + PI - seam_arc * 0.5 + seam_arc * float(j) / float(maxi(seam_points - 1, 1))
			arc.append(_warp(center + Vector2(cos(a), sin(a)) * seam_radius))
		seam.points = arc
		seam.width = r * seam_width_ratio
	var rim_points := _ring_points(rim_scale)
	rim_points.append(rim_points[0])
	rim.points = rim_points
	rim.width = r * rim_width_ratio


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
	trail.width = _trail_width * _size_factor()


func _size_factor() -> float:
	return radius_px / maxf(design_radius_px, 1.0)
