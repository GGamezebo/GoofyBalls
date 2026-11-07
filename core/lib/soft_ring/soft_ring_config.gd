class_name SoftRingConfig
extends Resource

## Tuning of a `SoftRing` soft body. One `.tres` per kind of body (shared, read-only at runtime).

## Points on the ring: more = smoother dents, more work per frame.
@export var ring_points: int = 20
## Wobble frequency (Hz) and damping ratio: low = gooey tar, high = rubber.
@export var wobble_hz: float = 3.2
@export var wobble_damping: float = 0.2
## Neighbour coupling: keeps dents one smooth blob-like shape.
@export var tension: float = 0.35
## Limits of a point's radius offset (share of the radius) after the volume correction.
@export var min_offset: float = -0.5
@export var max_offset: float = 0.6
## Integration substeps per frame, and the longest frame step simulated (s) so hitches don't explode.
@export var substeps: int = 2
@export var max_step_sec: float = 1.0 / 30.0
