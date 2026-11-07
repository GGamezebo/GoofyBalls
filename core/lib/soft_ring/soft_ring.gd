class_name SoftRing
extends RefCounted

## Spring ring of a 2D soft body (jelly, tar, rubber): N points on a unit circle, each with a radius
## offset that springs toward a target shape, is coupled to its neighbours and keeps the area (the
## mean offset is removed every step, so a dent on one side pushes the rest out).
## The owner writes the target shape into `targets` (one buffer reused every frame) before `step()`
## and scales the unit-space output by its radius. Write `ring.targets[i] = …` directly: a local
## copy of a packed array is a copy. Pure float logic without nodes; meant for visuals, not for a
## deterministic simulation.

## Unit direction of each point.
var dirs := PackedVector2Array()
## Radius offset of each point (share of the radius, 0 = on the circle).
var offsets := PackedFloat32Array()
## Rest offset of each point the ring springs toward; the owner rewrites it before each `step()`
## (see the `*_target` helpers). 0 everywhere = round.
var targets := PackedFloat32Array()

var _speeds := PackedFloat32Array()
var _config: SoftRingConfig


func _init(config: SoftRingConfig = null) -> void:
	if config == null:
		push_warning("SoftRing: no SoftRingConfig given, using defaults")
		config = SoftRingConfig.new()
	_config = config
	var n := maxi(_config.ring_points, 0)
	dirs.resize(n)
	offsets.resize(n)
	targets.resize(n)
	_speeds.resize(n)
	for i in n:
		var angle := TAU * float(i) / float(n)
		dirs[i] = Vector2(cos(angle), sin(angle))
	reset()


func size() -> int:
	return dirs.size()


## Back to a still circle.
func reset() -> void:
	offsets.fill(0.0)
	targets.fill(0.0)
	_speeds.fill(0.0)


## Polygon2D UVs (texture pixels) that map the unit circle onto a texture of `texture_size`.
func uvs(texture_size: Vector2) -> PackedVector2Array:
	var result := PackedVector2Array()
	result.resize(dirs.size())
	for i in dirs.size():
		result[i] = (Vector2(0.5, 0.5) + dirs[i] * 0.5) * texture_size
	return result


## Push the side facing `side` in by `amount` (radius / s); the rest bulges out by `bulge` of it,
## and the sides (across `side`) swell by `swell` of it.
func kick(side: Vector2, amount: float, bulge: float, swell: float = 0.0) -> void:
	for i in dirs.size():
		var facing := dirs[i].dot(side)
		var across := 1.0 - facing * facing
		if facing > 0.0:
			_speeds[i] -= amount * facing * facing
		else:
			_speeds[i] += amount * bulge * across
		if swell != 0.0:
			_speeds[i] += amount * swell * across


## Advance by `delta` s toward `targets`.
func step(delta: float) -> void:
	var n := dirs.size()
	if n == 0:
		return
	var omega := TAU * _config.wobble_hz
	var stiffness := omega * omega
	var damping := 2.0 * _config.wobble_damping * omega
	var steps := maxi(_config.substeps, 1)
	var dt := minf(delta, _config.max_step_sec) / float(steps)
	for _s in steps:
		for i in n:
			var neighbours := offsets[(i + n - 1) % n] + offsets[(i + 1) % n] - 2.0 * offsets[i]
			var accel := -stiffness * (offsets[i] - targets[i]) - damping * _speeds[i] + stiffness * _config.tension * neighbours
			_speeds[i] += accel * dt
		var mean := 0.0
		for i in n:
			offsets[i] += _speeds[i] * dt
			mean += offsets[i]
		mean /= float(n)
		for i in n:
			offsets[i] = clampf(offsets[i] - mean, _config.min_offset, _config.max_offset)


## How far the deformed body reaches along `dir` (in radii), e.g. `Vector2.DOWN` = lowest point.
func extent(dir: Vector2) -> float:
	var reach := -INF
	for i in dirs.size():
		reach = maxf(reach, dirs[i].dot(dir) * (1.0 + offsets[i]))
	return reach


## Unit-circle point → deformed body point, scaled by `radius` and moved by `offset`.
func warp(p: Vector2, radius: float, offset: Vector2 = Vector2.ZERO) -> Vector2:
	var n := dirs.size()
	if n == 0 or p.length() < 0.0001:
		return p * radius + offset
	var angle := fposmod(p.angle(), TAU) / TAU * float(n)
	var i0 := int(angle) % n
	var t := angle - floorf(angle)
	var stretch := 1.0 + lerpf(offsets[i0], offsets[(i0 + 1) % n], t)
	return p * radius * stretch + offset


## The deformed outline at `ring_scale` of the body (halo, rim…), scaled by `radius`, moved by `offset`.
func points(ring_scale: float, radius: float, offset: Vector2 = Vector2.ZERO) -> PackedVector2Array:
	var result := PackedVector2Array()
	result.resize(dirs.size())
	for i in dirs.size():
		result[i] = dirs[i] * radius * (1.0 + offsets[i]) * ring_scale + offset
	return result


## Rest offset in `dir` for an ellipse stretched `stretch` times along `along_dir`, same area.
static func stretch_target(dir: Vector2, along_dir: Vector2, stretch: float) -> float:
	var along := dir.dot(along_dir)
	var across := dir.dot(along_dir.orthogonal())
	return 1.0 / sqrt(along * along / (stretch * stretch) + across * across * stretch * stretch) - 1.0


## Rest offset in `dir` for a body flattened against a flat surface facing `normal` (from the
## center to the surface), at `limit` of the radius.
static func flatten_target(dir: Vector2, normal: Vector2, limit: float) -> float:
	var facing := dir.dot(normal)
	return limit / facing - 1.0 if facing > limit else 0.0
