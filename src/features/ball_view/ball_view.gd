class_name BallView
extends Node2D

## Glowing tar volleyball (concept + Gish squish): yellow halo, light spot, dark rim, two
## spinning seams, a short fading trail and a floor shadow. The body is a spring ring:
## impacts dent it and bulge the sides, a blob it sticks to flattens it, speed stretches it.
## View-only state (ring, spin, trail) never feeds back into the sim.

@export var trail_length: int = 5
@export var trail_spacing_px: float = 14.0
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
@export var stretch_per_mps: float = 0.012
@export var max_stretch: float = 1.22

var radius_px: float = 34.0

var _light: GradientTexture2D
var _spin: float = 0.0
var _trail: Array[Vector2] = []
var _floor_offset: float = 0.0
var _height_px: float = 0.0
var _frozen: bool = true
var _dirs: PackedVector2Array = []
var _off := PackedFloat32Array()
var _vel := PackedFloat32Array()
var _stretch_dir := Vector2.RIGHT
var _stretch: float = 1.0
var _press := Vector2.ZERO
var _uvs := PackedVector2Array()


func setup(p_radius_px: float) -> void:
	radius_px = p_radius_px
	_light = _make_light_texture()
	_trail.clear()
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
	queue_redraw()


## `vel_mps` = ball velocity (m/s, y up); `press` = unit direction from the blob the ball sticks
## to towards the ball (screen space), zero when free.
func apply(pos: Vector2, vel_mps: Vector2, frozen: bool, press: Vector2, floor_y: float, px_per_m: float, delta: float) -> void:
	if not frozen and (_trail.is_empty() or _trail.back().distance_to(pos) >= trail_spacing_px):
		_trail.append(pos)
		while _trail.size() > trail_length:
			_trail.pop_front()
	if frozen:
		_trail.clear()
	_frozen = frozen
	position = pos
	_floor_offset = floor_y - pos.y
	_height_px = maxf(0.0, _floor_offset - radius_px)
	_spin += vel_mps.x * px_per_m * delta / maxf(radius_px, 1.0)
	_press = press
	var speed := vel_mps.length()
	_stretch = 1.0
	if not frozen and press == Vector2.ZERO and speed > 0.5:
		_stretch_dir = Vector2(vel_mps.x, -vel_mps.y) / speed
		_stretch = minf(1.0 + speed * stretch_per_mps, max_stretch)
	_step_ring(delta)
	queue_redraw()


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


## Unit-circle point → deformed body (px).
func _warp(p: Vector2) -> Vector2:
	var n := _dirs.size()
	var length := p.length()
	if n == 0 or length < 0.0001:
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


func _draw() -> void:
	var r := radius_px
	var fade := clampf(1.0 - _height_px / (10.0 * r), 0.1, 1.0)
	draw_set_transform(Vector2(0.0, _floor_offset), 0.0, Vector2(1.0, 0.2))
	draw_circle(Vector2.ZERO, r * (0.5 + 0.5 * fade), Color(0, 0, 0, 0.45 * fade), true, -1.0, true)
	draw_set_transform_matrix(Transform2D.IDENTITY)

	for i in _trail.size():
		var t := float(i + 1) / float(_trail.size() + 1)
		draw_circle(_trail[i] - position, r * (0.35 + 0.45 * t), Color(1.0, 0.82, 0.04, 0.18 * t), true, -1.0, true)

	if _dirs.is_empty():
		return
	var body := _ring(1.0)
	draw_colored_polygon(_ring(1.45), Color(1.0, 0.82, 0.04, 0.07))
	draw_colored_polygon(_ring(1.2), Color(1.0, 0.82, 0.04, 0.14))
	draw_colored_polygon(body, Color("#FFD20A"))
	if _light != null:
		draw_polygon(body, PackedColorArray([Color.WHITE]), _uvs, _light)
	var seam := Color("#B07B00", 0.6)
	var seam_w := r * 0.08
	for k in 2:
		var angle := _spin + PI * float(k)
		var center := Vector2(cos(angle), sin(angle)) * 0.9
		var arc := PackedVector2Array()
		for j in 13:
			var a := angle + PI - 0.9 + 1.8 * float(j) / 12.0
			arc.append(_warp(center + Vector2(cos(a), sin(a)) * 0.75))
		draw_polyline(arc, seam, seam_w, true)
	var rim := _ring(0.94)
	rim.append(rim[0])
	draw_polyline(rim, Color("#C98F00"), r * 0.12, true)


func _make_light_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 1.0])
	gradient.colors = PackedColorArray([Color("#FFF6C2", 0.95), Color("#FFF6C2", 0.0)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 64
	texture.height = 64
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.38, 0.33)
	texture.fill_to = Vector2(0.72, 0.33)
	return texture
