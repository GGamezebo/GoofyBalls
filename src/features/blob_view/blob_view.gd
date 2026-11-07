class_name BlobView
extends Node2D

## Jelly tar blob (concept/art-direction.md + Gish): halo, body, light spot, outline, highlight
## drop, eyes that follow the ball, goo strands, floor shadow. The look lives in blob_view.tscn and
## is tuned there in the editor. The body is a spring ring that keeps its volume: it stretches up on
## take-off, is round at the apex, pancakes and wobbles on landing, dents where the ball hits, leans
## into its run and flattens against a wall it sticks to (with goo strands). The script only moves,
## reshapes and tints those nodes; view-only, a pure function of what `apply()` / `pulse()` get.
## Parts are drawn in white: those in `tinted` take the team color at setup, those in `tinted_light`
## a lighter one (their alpha stays). Light is white on top of the body, so it lightens any color.

## Blob radius the nodes in the scene are drawn for. Ring geometry is in these units; `Art` is
## scaled to the real radius.
@export var design_radius_px: float = 128.0
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
@export_group("Goo")
## Goo strand reach toward the wall, and its thickness, as shares of the radius.
@export var goo_reach: float = 0.22
@export var goo_width: float = 0.1
## Seconds for the goo to grow or fade when the blob starts or stops sticking to a wall.
@export var goo_sec: float = 0.12
@export_group("Eyes")
## How far pupils move toward the ball, in scene pixels (design radius).
@export var pupil_travel_px: float = 9.0
@export_group("Shadow")
## Height (in blob radii) where the shadow is the faintest.
@export var shadow_fade_radii: float = 6.0
@export_range(0.0, 1.0) var shadow_min_fade: float = 0.15
## Shadow size at the faintest, relative to the size on the floor.
@export_range(0.0, 1.0) var shadow_min_size: float = 0.63
@export_group("Shape")
## Halo ring sizes, relative to the body.
@export var halo_outer_scale: float = 1.2
@export var halo_inner_scale: float = 1.09
## Outline width as a share of the radius.
@export var outline_ratio: float = 0.07
@export_group("Team color")
## How much lighter than the team color `tinted_light` parts and the name are.
@export_range(0.0, 1.0) var light_tint: float = 0.35
@export_group("Name")
## Gap between the top of the blob and the name.
@export var name_gap_px: float = 28.0
@export_group("Nodes")
## Scaled to the real radius; everything that moves with the body lives under it.
@export var art: Node2D
@export var goo: Node2D
@export var halo_outer: Polygon2D
@export var halo_inner: Polygon2D
@export var skin: Polygon2D
@export var light: Polygon2D
@export var outline: Line2D
@export var shine: Node2D
@export var sparkle: Node2D
@export var eyes: Array[Node2D] = []
@export var pupils: Array[Node2D] = []
@export var shadow: Node2D
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
var _eye_units: Array[Vector2] = []
var _shine_unit := Vector2.ZERO
var _sparkle_unit := Vector2.ZERO
var _goo_lines: Array[Line2D] = []
var _was_on_floor: bool = true
var _on_floor: bool = true
var _last_vy: float = 0.0
var _vel_mps := Vector2.ZERO
var _cling: int = 0
var _goo_t: float = 0.0
var _look := Vector2.ZERO
var _dirs := PackedVector2Array()
var _uvs := PackedVector2Array()
var _off := PackedFloat32Array()
var _ring_v := PackedFloat32Array()
var _shift := Vector2.ZERO


func _ready() -> void:
	_shadow_scale = shadow.scale
	_shadow_alpha = shadow.modulate.a
	for pupil in pupils:
		_pupil_rest.append(pupil.position)
	# Face features sit where they are placed in the scene and ride the ring from there.
	for eye in eyes:
		_eye_units.append(eye.position / design_radius_px)
	_shine_unit = shine.position / design_radius_px
	_sparkle_unit = sparkle.position / design_radius_px
	for child in goo.get_children():
		_goo_lines.append(child)
	_init_ring()
	_apply_size()


func setup(p_color: Color, p_radius_px: float, display_name: String, is_local: bool) -> void:
	color = p_color
	var light_color := color.lightened(light_tint)
	for part in tinted:
		part.self_modulate = Color(color, part.self_modulate.a)
	for part in tinted_light:
		part.self_modulate = Color(light_color, part.self_modulate.a)
	if name_label != null:
		name_label.text = ("ТЫ" if is_local else display_name)
		name_label.add_theme_color_override("font_color", light_color)
	radius_px = p_radius_px
	_off.fill(0.0)
	_ring_v.fill(0.0)


## `pos` = body center (px), `floor_y` = floor line (px), `look_target` = ball (px),
## velocities in m/s (y up), `cling` = wall side the blob sticks to (-1 left, 1 right, 0 none).
func apply(pos: Vector2, vy_mps: float, on_floor: bool, floor_y: float, look_target: Vector2, delta: float,
		vx_mps: float = 0.0, cling: int = 0) -> void:
	position = pos
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
	_goo_t = move_toward(_goo_t, 1.0 if cling != 0 else 0.0, delta / goo_sec)
	var to_ball := look_target - pos
	_look = to_ball.normalized() if to_ball.length() > 1.0 else Vector2.ZERO
	_step_ring(delta)
	_update_nodes()
	_update_shadow(floor_y - pos.y)


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


func _init_ring() -> void:
	_dirs.resize(ring_points)
	_uvs.resize(ring_points)
	_off.resize(ring_points)
	_ring_v.resize(ring_points)
	# Polygon2D UVs are in texture pixels.
	var uv_size := light.texture.get_size() if light.texture != null else Vector2.ONE
	for i in ring_points:
		var angle := TAU * float(i) / float(ring_points)
		_dirs[i] = Vector2(cos(angle), sin(angle))
		_uvs[i] = (Vector2(0.5, 0.5) + _dirs[i] * 0.5) * uv_size
	_off.fill(0.0)
	_ring_v.fill(0.0)


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
		_shift.y = (1.0 - lowest) * design_radius_px


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


## Unit-circle point → deformed body (design px, Art space).
func _warp(p: Vector2) -> Vector2:
	var n := _dirs.size()
	var length := p.length()
	if n == 0 or length < 0.0001:
		return p * design_radius_px + _shift
	var angle := fposmod(p.angle(), TAU) / TAU * float(n)
	var i0 := int(angle) % n
	var t := angle - floorf(angle)
	var stretch := 1.0 + lerpf(_off[i0], _off[(i0 + 1) % n], t)
	return p * design_radius_px * stretch + _shift


func _ring(ring_scale: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	points.resize(_dirs.size())
	for i in _dirs.size():
		points[i] = _dirs[i] * design_radius_px * (1.0 + _off[i]) * ring_scale + _shift
	return points


func _update_nodes() -> void:
	if _dirs.is_empty():
		return
	var body := _ring(1.0)
	skin.polygon = body
	light.polygon = body
	light.uv = _uvs
	halo_outer.polygon = _ring(halo_outer_scale)
	halo_inner.polygon = _ring(halo_inner_scale)
	var outline_points := _ring(1.0 - outline_ratio * 0.5)
	outline_points.append(outline_points[0])
	outline.points = outline_points
	outline.width = design_radius_px * outline_ratio
	shine.position = _warp(_shine_unit)
	sparkle.position = _warp(_sparkle_unit)
	for side in eyes.size():
		eyes[side].position = _warp(_eye_units[side])
		pupils[side].position = _pupil_rest[side] + _look * pupil_travel_px
	_update_goo()


func _update_goo() -> void:
	goo.visible = _goo_t > 0.01 and _cling != 0
	if not goo.visible:
		return
	var side := float(_cling)
	for k in _goo_lines.size():
		var y := (float(k) - 1.0) * 0.45
		var root := _warp(Vector2(side * sqrt(1.0 - y * y) * 0.9, y))
		var tip := root + Vector2(side * goo_reach * design_radius_px * _goo_t, 0.06 * design_radius_px * float(k - 1))
		var strand := _goo_lines[k]
		strand.points = PackedVector2Array([root, tip])
		strand.width = goo_width * design_radius_px * _goo_t


func _update_shadow(floor_offset: float) -> void:
	var height := maxf(0.0, floor_offset - radius_px)
	var fade := clampf(1.0 - height / (shadow_fade_radii * radius_px), shadow_min_fade, 1.0)
	shadow.position = Vector2(0.0, floor_offset)
	shadow.scale = _shadow_scale * _size_factor() * lerpf(shadow_min_size, 1.0, fade)
	shadow.modulate.a = _shadow_alpha * fade


func _apply_size() -> void:
	if not is_node_ready():
		return
	var k := _size_factor()
	art.scale = Vector2(k, k)
	if name_label != null:
		name_label.position = Vector2(-name_label.size.x * 0.5, -radius_px - name_gap_px - name_label.size.y)


func _size_factor() -> float:
	return radius_px / maxf(design_radius_px, 1.0)
