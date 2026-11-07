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
## Spring ring of the body (points, wobble, tension, offset limits).
@export var ring_config: SoftRingConfig
@export var rest_flatten: float = 0.94
@export var stretch_per_mps: float = 0.022
@export var max_stretch: float = 1.3
@export var lean_per_mps: float = 0.02
## Lean bends the body from this height down (share of the radius above the center, 0 = middle).
@export var lean_height_bias: float = 0.3
## Below this flight speed (m/s) the blob is not stretched along its path.
@export var stretch_min_mps: float = 0.5
## Ring speed (radius / s) one m/s of landing speed adds to the pancake.
@export var land_per_mps: float = 0.2
## On landing the sides bulge by this share of the squeeze; the top is pushed down by this share.
@export var land_bulge: float = 0.8
@export var land_top_share: float = 0.7
@export var hit_dent: float = 2.4
## Share of the hit dent the far side bulges out by.
@export var hit_bulge: float = 0.5
@export var wall_flatten: float = 0.72
## Splat when the blob sticks to a wall (ring speed, radius / s) and how much the rest bulges.
@export var cling_kick: float = 1.2
@export var cling_bulge: float = 0.6
@export_group("Goo")
## Goo strand reach toward the wall, and its thickness, as shares of the radius.
@export var goo_reach: float = 0.22
@export var goo_width: float = 0.1
## Seconds for the goo to grow or fade when the blob starts or stops sticking to a wall.
@export var goo_sec: float = 0.12
## Vertical gap between strands, how deep inside the body they root and how much each one droops
## (shares of the radius).
@export var goo_spacing: float = 0.45
@export var goo_root_inset: float = 0.9
@export var goo_droop: float = 0.06
@export_group("Eyes")
## How far pupils move toward the ball, in scene pixels (design radius).
@export var pupil_travel_px: float = 9.0
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
## Fade and size by height are tuned on the node.
@export var shadow: FloorShadow
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
var _ring: SoftRing
var _uvs := PackedVector2Array()
var _shift := Vector2.ZERO


func _ready() -> void:
	for pupil in pupils:
		_pupil_rest.append(pupil.position)
	# Face features sit where they are placed in the scene and ride the ring from there.
	for eye in eyes:
		_eye_units.append(eye.position / design_radius_px)
	_shine_unit = shine.position / design_radius_px
	_sparkle_unit = sparkle.position / design_radius_px
	for child in goo.get_children():
		_goo_lines.append(child)
	_ring = SoftRing.new(ring_config)
	# Polygon2D UVs are in texture pixels.
	_uvs = _ring.uvs(light.texture.get_size() if light.texture != null else Vector2.ONE)
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
	if _ring != null:
		_ring.reset()


## `pos` = body center (px), `floor_y` = floor line (px), `look_target` = ball (px),
## velocities in m/s (y up), `cling` = wall side the blob sticks to (-1 left, 1 right, 0 none).
func apply(pos: Vector2, vy_mps: float, on_floor: bool, floor_y: float, look_target: Vector2, delta: float,
		vx_mps: float = 0.0, cling: int = 0) -> void:
	position = pos
	if on_floor and not _was_on_floor:
		# Pancake: squeezed from below and above, spreads sideways.
		var land := -minf(_last_vy, 0.0) * land_per_mps
		_ring.kick(Vector2.DOWN, land, land_bulge)
		_ring.kick(Vector2.UP, land * land_top_share, 0.0)
	if not on_floor:
		_last_vy = vy_mps
	_was_on_floor = on_floor
	_on_floor = on_floor
	_vel_mps = Vector2(vx_mps, vy_mps)
	if cling != 0 and _cling == 0:
		_ring.kick(Vector2(float(cling), 0.0), cling_kick, cling_bulge)
	_cling = cling
	_goo_t = move_toward(_goo_t, 1.0 if cling != 0 else 0.0, delta / goo_sec)
	var to_ball := look_target - pos
	_look = to_ball.normalized() if to_ball.length() > 1.0 else Vector2.ZERO
	_step_ring(delta)
	_update_nodes()
	shadow.apply(floor_y - pos.y, radius_px, _size_factor())


## Dent where this blob touched the ball; `toward` = from the blob to the ball (screen space).
func pulse(toward: Vector2 = Vector2.UP) -> void:
	if _ring == null:
		return
	_ring.kick(toward.normalized() if toward != Vector2.ZERO else Vector2.UP, hit_dent, hit_bulge)


func _step_ring(delta: float) -> void:
	_update_targets()
	_ring.step(delta)
	# Sit on the floor: the lowest point of a squashed body touches it.
	_shift = Vector2.ZERO
	if _on_floor:
		_shift.y = (1.0 - _ring.extent(Vector2.DOWN)) * design_radius_px


## Rest shape per ring point (radius offset): stretched along the flight, leaning into the run,
## a little flat on the floor, flattened against a sticky wall.
func _update_targets() -> void:
	var speed := _vel_mps.length()
	var along_dir := Vector2(_vel_mps.x, -_vel_mps.y) / speed if speed > stretch_min_mps else Vector2.ZERO
	var stretch := minf(1.0 + speed * stretch_per_mps, max_stretch)
	for i in _ring.size():
		var d := _ring.dirs[i]
		var target := 0.0
		if not _on_floor:
			if speed > stretch_min_mps:
				target += SoftRing.stretch_target(d, along_dir, stretch)
		else:
			target += SoftRing.flatten_target(d, Vector2.DOWN, rest_flatten)
			# Tar rolls: the front bulges forward and low, the back trails.
			target += d.x * _vel_mps.x * lean_per_mps * maxf(d.y + lean_height_bias, 0.0)
		if _cling != 0:
			target += SoftRing.flatten_target(d, Vector2(float(_cling), 0.0), wall_flatten)
		_ring.targets[i] = target


## Unit-circle point → deformed body (design px, Art space).
func _warp(p: Vector2) -> Vector2:
	return _ring.warp(p, design_radius_px, _shift)


func _ring_points(ring_scale: float) -> PackedVector2Array:
	return _ring.points(ring_scale, design_radius_px, _shift)


func _update_nodes() -> void:
	if _ring.size() == 0:
		return
	var body := _ring_points(1.0)
	skin.polygon = body
	light.polygon = body
	light.uv = _uvs
	halo_outer.polygon = _ring_points(halo_outer_scale)
	halo_inner.polygon = _ring_points(halo_inner_scale)
	var outline_points := _ring_points(1.0 - outline_ratio * 0.5)
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
		var y := (float(k) - 1.0) * goo_spacing
		var root := _warp(Vector2(side * sqrt(1.0 - y * y) * goo_root_inset, y))
		var tip := root + Vector2(side * goo_reach * design_radius_px * _goo_t, goo_droop * design_radius_px * float(k - 1))
		var strand := _goo_lines[k]
		strand.points = PackedVector2Array([root, tip])
		strand.width = goo_width * design_radius_px * _goo_t


func _apply_size() -> void:
	if not is_node_ready():
		return
	var k := _size_factor()
	art.scale = Vector2(k, k)
	if name_label != null:
		name_label.position = Vector2(-name_label.size.x * 0.5, -radius_px - name_gap_px - name_label.size.y)


func _size_factor() -> float:
	return radius_px / maxf(design_radius_px, 1.0)
