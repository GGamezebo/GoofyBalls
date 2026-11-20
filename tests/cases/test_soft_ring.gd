extends TestCase

## SoftRing (core/lib/soft_ring): dents wobble out, the mean radius is kept, it returns to a circle.

const FRAME := 1.0 / 60.0


func test_still_ring_stays_round() -> void:
	var ring := _ring()
	_run(ring, 1.0)
	expect(_max_offset(ring) < 0.0001, "zero targets and no kick keep a circle")
	var points := ring.points(1.0, 10.0)
	expect(absf(points[0].length() - 10.0) < 0.001, "points are scaled by the radius")


func test_dent_keeps_mean_and_settles() -> void:
	var ring := _ring()
	ring.kick(Vector2.DOWN, 2.0, 0.5)
	ring.step(FRAME)
	expect(_max_offset(ring) > 0.01, "a kick deforms the ring")
	expect(absf(_mean(ring)) < 0.0001, "mean offset stays 0 (volume kept)")
	var bottom := ring.extent(Vector2.DOWN)
	expect(bottom < 1.0, "kicked side is dented in (reach %.3f)" % bottom)
	_run(ring, 3.0)
	expect(_max_offset(ring) < 0.01, "the dent wobbles out back to a circle")


func test_ring_follows_targets() -> void:
	var ring := _ring()
	for i in ring.size():
		ring.targets[i] = SoftRing.flatten_target(ring.dirs[i], Vector2.DOWN, 0.8)
	_run(ring, 3.0)
	var bottom := ring.extent(Vector2.DOWN)
	expect(bottom < 0.95, "flattened against the floor (reach %.3f)" % bottom)
	ring.reset()
	expect(_max_offset(ring) == 0.0 and ring.targets[0] == 0.0, "reset gives a still circle")


func test_helpers() -> void:
	expect(absf(SoftRing.stretch_target(Vector2.RIGHT, Vector2.RIGHT, 1.2) - 0.2) < 0.0001, "stretched along")
	expect(SoftRing.stretch_target(Vector2.UP, Vector2.RIGHT, 1.2) < 0.0, "squeezed across")
	expect(SoftRing.flatten_target(Vector2.UP, Vector2.DOWN, 0.8) == 0.0, "far side not flattened")
	expect(absf(SoftRing.flatten_target(Vector2.DOWN, Vector2.DOWN, 0.8) + 0.2) < 0.0001, "facing side cut at the limit")


func _ring() -> SoftRing:
	var config := SoftRingConfig.new()
	return SoftRing.new(config)


func _run(ring: SoftRing, seconds: float) -> void:
	for _i in int(seconds / FRAME):
		ring.step(FRAME)


func _max_offset(ring: SoftRing) -> float:
	var worst := 0.0
	for offset in ring.offsets:
		worst = maxf(worst, absf(offset))
	return worst


func _mean(ring: SoftRing) -> float:
	var total := 0.0
	for offset in ring.offsets:
		total += offset
	return total / float(ring.size())
