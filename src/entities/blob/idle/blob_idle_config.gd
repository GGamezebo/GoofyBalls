class_name BlobIdleConfig
extends Resource

## Tuning of a `BlobIdle` decorative bounce. One `.tres` per screen that uses it.

## Time of one full hop cycle (seconds).
@export var period_sec: float = 1.6
## Peak height of a hop (px).
@export var hop_px: float = 70.0
## Peak vertical speed handed to `BlobView.apply` (drives its squash and stretch).
@export var peak_speed: float = 8.0
## Below this height (px) the thing counts as standing on the floor.
@export var floor_epsilon_px: float = 0.5
