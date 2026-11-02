class_name BallView
extends Node2D

## Glowing tar volleyball (concept + Gish squish). The look lives in ball_view.tscn and is tuned
## there in the editor: two glow rings, a yellow skin, a light spot, two spinning seams, a dark rim,
## plus a short trail and a floor shadow. The skin, light, glow, seams and rim are a spring ring:
## impacts dent it, a blob it sticks to flattens it, speed stretches it. The script only moves and
## reshapes those nodes. View-only state (ring, spin, trail) never feeds back into the sim.

## Ball radius the nodes in the scene are drawn for.
@export var design_radius_px: float = 64.0
@export_group("Squish")
@export var ring_points: int = 20
## Ring wobble frequency (Hz) and damping ratio: low = gooey tar, high = rubber.
@export var wobble_hz: float = 3.6
@export var wobble_damping: float = 0.22
## Neighbour coupling: smooths dents into one blob-like shape.
@export var ring_tension: float = 0.35
## Ring speed (radius / s) one m/s of impact adds to the dent; capped by `max_impact`.
@export var dent_per_mps: float = 0.32
@export var max_impact: float = 16.0
## Side of the ball pressed against a blob is flattened to this share of the radius.
@export var stick_flatten: float = 0.72
## Stretch along the flight per m/s of speed, and the longest stretch.
@export var stretch_per_mps: float = 0.012
@export var max_stretch: float = 1.22
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
## Yellow body, reshaped by the ring.
@export var skin: Polygon2D
## Light spot over the skin; the script maps its UVs onto the ring.
@export var shine: Polygon2D
@export var glow_outer: Polygon2D
@export var glow_inner: Polygon2D
@export var seam_a: Line2D
@export var seam_b: Line2D
@export var rim: Line2D
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
var _spin: float = 0.0
var _press := Vector2.ZERO
var _stretch: float = 1.0
var _stretch_dir := Vector2.RIGHT
var _dirs := PackedVector2Array()
var _uvs := PackedVector2Array()
var _off := PackedFloat32Array()
var _vel := PackedFloat32Array()


func _ready() -> void:
	_shadow_scale = shadow.scale
	_shadow_alpha = shadow.modulate.a
	_trail_width = trail.width
	trail.clear_points()
	_init_ring()
	_apply_size()


func setup(p_radius_px: float) -> void:
	radius_px = p_radius_px
	_history.clear()
	trail.clear_points()
	_off.fill(0.0)
	_vel.fill(0.0)


## `vel_mps` = ball velocity (m/s, y up); `press` = unit direction from the blob the ball sticks
## to towards the ball (screen space), zero when free.
func apply(pos: Vector2, vel_mps: Vector2, frozen: bool, press: Vector2, floor_y: float, px_per_m: float, delta: float) -> void:
	position = pos
	_spin += vel_mps.x * px_per_m * delta / maxf(radius_px, 1.0)
	_press = press
	var speed := vel_mps.length()
	_stretch = 1.0
	if not frozen and press == Vector2.ZERO and speed > 0.5:
		_stretch_dir = Vector2(vel_mps.x, -vel_mps.y) / speed
		_stretch = minf(1.0 + speed * stretch_per_mps, max_stretch)
	_step_ring(delta)
	_update_shadow(floor_y - pos.y)
	_update_trail(frozen)
	_update_shapes()


## Splat: the ball was pushed along `push_dir` (screen space) with `power` m/s.
func impact(push_dir: Vector2, power: float) -> void:
	if _dirs.is_empty():
		return
	var kick := minf(power, max_impact) * dent_per_mps
	for i in _dirs.size():
		# The contact side faces against the push: it dents in, the sides bulge out.
		var facing := -_dirs[i].dot(push_dir)
		if facing > 0.0:
			_vel[i] -= kick * facing * facing
		else:
			_vel[i] += kick * 0.35 * (1.0 - facing * facing)
		_vel[i] += kick * 0.25 * (1.0 - facing * facing)


func _init_ring() -> void:
	_dirs.resize(ring_points)
	_uvs.resize(ring_points)
	_off.resize(ring_points)
	_vel.resize(ring_points)
	for i in ring_points:
		var angle := TAU * float(i) / float(ring_points)
		_dirs[i] = Vector2(cos(angle), sin(angle))
		_uvs[i] = Vector2(0.5, 0.5) + _dirs[i] * 0.5
	_off.fill(0.0)
	_vel.fill(0.0)


func _step_ring(delta: float) -> void:
	var n := _dirs.size()
	if n == 0:
		return
	var omega := TAU * wobble_hz
	var stiffness := omega * omega
	var damping := 2.0 * wobble_damping * omega
	var steps := 2
	var dt := minf(delta, 1.0 / 30.0) / float(steps)
	for _s in steps:
		for i in n:
			var neighbours := _off[(i + n - 1) % n] + _off[(i + 1) % n] - 2.0 * _off[i]
			var accel := -stiffness * (_off[i] - _target(i)) - damping * _vel[i] + stiffness * ring_tension * neighbours
			_vel[i] += accel * dt
		var mean := 0.0
		for i in n:
			_off[i] += _vel[i] * dt
			mean += _off[i]
		# Tar keeps its volume: a dent on one side pushes the rest out.
		mean /= float(n)
		for i in n:
			_off[i] = clampf(_off[i] - mean, -0.45, 0.45)


## Rest shape for point i: stretched along the flight, flattened against the sticking blob.
func _target(i: int) -> float:
	var d := _dirs[i]
	var target := 0.0
	if _stretch > 1.0:
		var along := d.dot(_stretch_dir)
		var across := d.dot(_stretch_dir.orthogonal())
		var sx := _stretch
		var sy := 1.0 / _stretch
		# Ellipse radius in direction d with semi-axes (sx, sy).
		target += 1.0 / sqrt(along * along / (sx * sx) + across * across / (sy * sy)) - 1.0
	if _press != Vector2.ZERO:
		var facing := -d.dot(_press)
		if facing > stick_flatten:
			target += stick_flatten / facing - 1.0
	return target


## Unit-circle point → deformed body (px), in the ball's local space.
func _warp(p: Vector2) -> Vector2:
	var n := _dirs.size()
	if n == 0:
		return p * radius_px
	var angle := fposmod(p.angle(), TAU) / TAU * float(n)
	var i0 := int(angle) % n
	var t := angle - floorf(angle)
	var scale := 1.0 + lerpf(_off[i0], _off[(i0 + 1) % n], t)
	return p * radius_px * scale


func _ring(scale: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	points.resize(_dirs.size())
	for i in _dirs.size():
		points[i] = _dirs[i] * radius_px * (1.0 + _off[i]) * scale
	return points


func _update_shapes() -> void:
	if _dirs.is_empty():
		return
	var r := radius_px
	var body := _ring(1.0)
	skin.polygon = body
	shine.polygon = body
	shine.uv = _uvs
	glow_outer.polygon = _ring(1.45)
	glow_inner.polygon = _ring(1.2)
	for k in 2:
		var seam := seam_a if k == 0 else seam_b
		var angle := _spin + PI * float(k)
		var center := Vector2(cos(angle), sin(angle)) * 0.9
		var arc := PackedVector2Array()
		for j in 13:
			var a := angle + PI - 0.9 + 1.8 * float(j) / 12.0
			arc.append(_warp(center + Vector2(cos(a), sin(a)) * 0.75))
		seam.points = arc
		seam.width = r * 0.08
	var rim_points := _ring(0.94)
	rim_points.append(rim_points[0])
	rim.points = rim_points
	rim.width = r * 0.12


func _update_shadow(floor_offset: float) -> void:
	var height := maxf(0.0, floor_offset - radius_px)
	var fade := clampf(1.0 - height / (shadow_fade_radii * radius_px), shadow_min_fade, 1.0)
	shadow.position = Vector2(0.0, floor_offset)
	shadow.scale = _shadow_scale * _size_factor() * lerpf(shadow_min_size, 1.0, fade)
	shadow.modulate.a = _shadow_alpha * fade


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
