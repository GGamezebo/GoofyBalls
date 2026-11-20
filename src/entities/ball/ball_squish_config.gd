class_name BallSquishConfig
extends SoftRingConfig

## How the ball feels as jelly: its spring ring (inherited) plus how much impacts, a sticking blob
## and speed squash it. View-only: never read by the sim. `BallView` reads it every frame.

@export_group("Squish")
## Ring speed (radius / s) one m/s of impact adds to the dent; capped by `max_impact`.
@export var dent_per_mps: float = 0.32
@export var max_impact: float = 16.0
## On impact the far side bulges out, and the sides swell, by these shares of the dent.
@export var impact_bulge: float = 0.35
@export var impact_swell: float = 0.25
## Side of the ball pressed against a blob is flattened to this share of the radius.
@export var stick_flatten: float = 0.72
## Stretch along the flight per m/s of speed, and the longest stretch.
@export var stretch_per_mps: float = 0.012
@export var max_stretch: float = 1.22
## Below this speed (m/s) the ball is not stretched along its path.
@export var stretch_min_mps: float = 0.5
