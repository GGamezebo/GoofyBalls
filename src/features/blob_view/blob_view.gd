class_name BlobView
extends Node2D

## Jelly tar blob (concept/art-direction.md + Gish): halo, body, light spot, outline, highlight
## drop, eyes that follow the ball, floor shadow. The body is a spring ring that keeps its
## volume: it stretches up on take-off, is round at the apex, pancakes and wobbles on landing,
## dents where the ball hits, leans into its run and flattens against a wall it sticks to
## (with a few goo strands). View-only; pure function of what `apply()` / `pulse()` get.

@export var name_label: Label
@export var outline_ratio: float = 0.07
@export var halo_alpha: float = 0.14
@export_group("Jelly")
@export var ring_points: int = 20
## Wobble frequency (Hz) and damping ratio: low = gooey tar, high = rubber.
@export var wobble_hz: float = 3.2
@export var wobble_damping: float = 0.2
## Neighbour coupling: keeps dents one smooth blob-like shape.
@export var ring_tension: float = 0.35
@export var rest_flatten: float = 0.94
@export var stretch_per_mps: float = 0.022
@export var max_stretch: float = 1.3
@export var lean_per_mps: float = 0.02
## Ring speed (radius / s) one m/s of landing speed adds to the pancake.
@export var land_per_mps: float = 0.2
@export var hit_dent: float = 2.4
@export var wall_flatten: float = 0.72

var color: Color = Color("#03B8FF")
var radius_px: float = 48.0

var _light: GradientTexture2D
var _floor_offset: float = 0.0
var _height_px: float = 0.0
var _look := Vector2.ZERO
var _was_on_floor: bool = true
var _on_floor: bool = true
var _last_vy: float = 0.0
var _vel_mps := Vector2.ZERO
var _cling: int = 0
var _goo_t: float = 0.0
var _dirs := PackedVector2Array()
var _uvs := PackedVector2Array()
var _off := PackedFloat32Array()
var _ring_v := PackedFloat32Array()
var _shift := Vector2.ZERO


func setup(p_color: Color, p_radius_px: float, display_name: String, is_local: bool) -> void:
	color = p_color
	radius_px = p_radius_px
	_light = _make_light_texture()
	if name_label != null:
		name_label.text = ("ТЫ" if is_local else display_name)
		name_label.add_theme_color_override("font_color", color.lightened(0.35))
		name_label.position = Vector2(-name_label.size.x * 0.5, -radius_px - 64.0)
	_dirs.resize(ring_points)
	_uvs.resize(ring_points)
	_off.resize(ring_points)
	_ring_v.resize(ring_points)
	for i in ring_points:
		var angle := TAU * float(i) / float(ring_points)
		_dirs[i] = Vector2(cos(angle), sin(angle))
		_uvs[i] = Vector2(0.5, 0.5) + _dirs[i] * 0.5
	_off.fill(0.0)
	_ring_v.fill(0.0)
	queue_redraw()


## `pos` = body center (px), `floor_y` = floor line (px), `look_target` = ball (px),
## velocities in m/s (y up), `cling` = wall side the blob sticks to (-1 left, 1 right, 0 none).
func apply(pos: Vector2, vy_mps: float, on_floor: bool, floor_y: float, look_target: Vector2, delta: float,
		vx_mps: float = 0.0, cling: int = 0) -> void:
	position = pos
	_floor_offset = floor_y - pos.y
	_height_px = maxf(0.0, _floor_offset - radius_px)
	if on_floor and not _was_on_floor:
		# Pancake: squeezed from below and above, spreads sideways.
		var land := -minf(_last_vy, 0.0) * land_per_mps
		_kick(Vector2.DOWN, land, 0.8)
		_kick(Vector2.UP, land * 0.7, 0.0)
	if not on_floor:
		_last_vy = vy_mps
	_was_on_floor = on_floor
	_on_floor = on_floor
	_vel_mps = Vector2(vx_mps, vy_mps)
	if cling != 0 and _cling == 0:
		_kick(Vector2(float(cling), 0.0), 1.2, 0.6)
	_cling = cling
	_goo_t = move_toward(_goo_t, 1.0 if cling != 0 else 0.0, delta / 0.12)
	var to_ball := look_target - pos
	_look = to_ball.normalized() if to_ball.length() > 1.0 else Vector2.ZERO
	_step_ring(delta)
	queue_redraw()


## Dent where this blob touched the ball; `toward` = from the blob to the ball (screen space).
func pulse(toward: Vector2 = Vector2.UP) -> void:
	_kick(toward.normalized() if toward != Vector2.ZERO else Vector2.UP, hit_dent, 0.5)


## Push the side facing `side` in by `amount` (radius / s); the rest bulges out (volume).
func _kick(side: Vector2, amount: float, bulge: float) -> void:
	for i in _dirs.size():
		var facing := _dirs[i].dot(side)
		if facing > 0.0:
			_ring_v[i] -= amount * facing * facing
		else:
			_ring_v[i] += amount * bulge * (1.0 - facing * facing)


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
			var accel := -stiffness * (_off[i] - _target(i)) - damping * _ring_v[i] + stiffness * ring_tension * neighbours
			_ring_v[i] += accel * dt
		var mean := 0.0
		for i in n:
			_off[i] += _ring_v[i] * dt
			mean += _off[i]
		mean /= float(n)
		for i in n:
			_off[i] = clampf(_off[i] - mean, -0.5, 0.6)
	# Sit on the floor: the lowest point of a squashed body touches it.
	_shift = Vector2.ZERO
	if _on_floor:
		var lowest := -INF
		for i in n:
			lowest = maxf(lowest, _dirs[i].y * (1.0 + _off[i]))
		_shift.y = (1.0 - lowest) * radius_px


## Rest shape for point i (radius offset): stretched along the flight, leaning into the run,
## a little flat on the floor, flattened against a sticky wall.
func _target(i: int) -> float:
	var d := _dirs[i]
	var target := 0.0
	if not _on_floor:
		var speed := _vel_mps.length()
		if speed > 0.5:
			var along_dir := Vector2(_vel_mps.x, -_vel_mps.y) / speed
			var s := minf(1.0 + speed * stretch_per_mps, max_stretch)
			var along := d.dot(along_dir)
			var across := d.dot(along_dir.orthogonal())
			target += 1.0 / sqrt(along * along / (s * s) + across * across * s * s) - 1.0
	else:
		if d.y > rest_flatten:
			target += rest_flatten / d.y - 1.0
		# Tar rolls: the front bulges forward and low, the back trails.
		target += d.x * _vel_mps.x * lean_per_mps * maxf(d.y + 0.3, 0.0)
	if _cling != 0:
		var facing := d.x * float(_cling)
		if facing > wall_flatten:
			target += wall_flatten / facing - 1.0
	return target


## Unit-circle point → deformed body (px, node space).
func _warp(p: Vector2) -> Vector2:
	var n := _dirs.size()
	var length := p.length()
	if n == 0 or length < 0.0001:
		return p * radius_px + _shift
	var angle := fposmod(p.angle(), TAU) / TAU * float(n)
	var i0 := int(angle) % n
	var t := angle - floorf(angle)
	var scale := 1.0 + lerpf(_off[i0], _off[(i0 + 1) % n], t)
	return p * radius_px * scale + _shift


func _ring(scale: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	points.resize(_dirs.size())
	for i in _dirs.size():
		points[i] = _dirs[i] * radius_px * (1.0 + _off[i]) * scale + _shift
	return points


func _draw() -> void:
	var r := radius_px
	_draw_shadow(r)
	if _dirs.is_empty():
		return
	_draw_goo(r)
	var body := _ring(1.0)
	draw_colored_polygon(_ring(1.2), Color(color, halo_alpha * 0.6))
	draw_colored_polygon(_ring(1.09), Color(color, halo_alpha))
	draw_colored_polygon(body, color)
	if _light != null:
		draw_polygon(body, PackedColorArray([Color.WHITE]), _uvs, _light)
	var outline_w := r * outline_ratio
	var outline := _ring(1.0 - outline_ratio * 0.5)
	outline.append(outline[0])
	draw_polyline(outline, color.lightened(0.35), outline_w, true)
	var stretch := _local_stretch(Vector2(-0.4, -0.5))
	_draw_ellipse(_warp(Vector2(-0.4, -0.5)), Vector2(0.22 * r, 0.12 * r) * stretch, -0.61, Color(1, 1, 1, 0.75))
	draw_circle(_warp(Vector2(-0.12, -0.72)), 0.05 * r, Color(1, 1, 1, 0.8), true, -1.0, true)
	for side in [-1.0, 1.0]:
		var unit := Vector2(side * 0.3, -0.12)
		var eye := _warp(unit)
		_draw_ellipse(eye, Vector2(0.17 * r, 0.22 * r) * _local_stretch(unit), 0.0, Color.WHITE)
		draw_circle(eye + _look * 0.07 * r, 0.09 * r, Color("#0A0F25"), true, -1.0, true)


## How the body is squeezed around a unit-circle point: (width, height) scale for features.
func _local_stretch(p: Vector2) -> Vector2:
	var w := (_warp(p + Vector2(0.15, 0.0)) - _warp(p - Vector2(0.15, 0.0))).length() / (0.3 * radius_px)
	var h := (_warp(p + Vector2(0.0, 0.15)) - _warp(p - Vector2(0.0, 0.15))).length() / (0.3 * radius_px)
	return Vector2(clampf(w, 0.6, 1.6), clampf(h, 0.6, 1.6))


## Gish-like goo strands between the body and the wall it sticks to.
func _draw_goo(r: float) -> void:
	if _goo_t <= 0.01 or _cling == 0:
		return
	var side := float(_cling)
	var goo := color.darkened(0.15)
	for k in 3:
		var y := (float(k) - 1.0) * 0.45
		var root := _warp(Vector2(side * sqrt(1.0 - y * y) * 0.9, y))
		var tip := root + Vector2(side * 0.22 * r * _goo_t, 0.06 * r * float(k - 1))
		draw_line(root, tip, goo, r * 0.1 * _goo_t, true)
		draw_circle(tip, r * 0.08 * _goo_t, goo, true, -1.0, true)


func _draw_shadow(r: float) -> void:
	var fade := clampf(1.0 - _height_px / (6.0 * r), 0.15, 1.0)
	var center := Vector2(0.0, _floor_offset)
	draw_set_transform(center, 0.0, Vector2(1.0, 0.18))
	draw_circle(Vector2.ZERO, r * (0.6 + 0.35 * fade), Color(0, 0, 0, 0.5 * fade), true, -1.0, true)
	draw_set_transform_matrix(Transform2D.IDENTITY)


func _draw_ellipse(center: Vector2, radii: Vector2, angle: float, fill: Color) -> void:
	draw_set_transform_matrix(Transform2D(angle, Vector2(radii.x / radii.y, 1.0), 0.0, center))
	draw_circle(Vector2.ZERO, radii.y, fill, true, -1.0, true)
	draw_set_transform_matrix(Transform2D.IDENTITY)


func _make_light_texture() -> GradientTexture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 1.0])
	gradient.colors = PackedColorArray([Color(color.lightened(0.6), 0.85), Color(color.lightened(0.6), 0.0)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.width = 64
	texture.height = 64
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.4, 0.35)
	texture.fill_to = Vector2(0.72, 0.35)
	return texture
