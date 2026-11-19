class_name BlobJellyConfig
extends SoftRingConfig

## How one kind of blob feels as jelly: its spring ring (inherited) plus how much running,
## flying, landing, hits and walls squash it, and its goo strands. One `.tres` per character in
## `jelly/` (picked by `SlotSetup.character_id` through `BlobJellySet`), so every future blob can
## wobble its own way. View-only: never read by the sim. `BlobView` reads it every frame.

@export_group("Jelly")
## Rest shape on the floor: the bottom is flattened to this share of the radius.
@export var rest_flatten: float = 0.94
## Stretch along the flight per m/s of speed, and the longest stretch.
@export var stretch_per_mps: float = 0.022
@export var max_stretch: float = 1.3
## Below this flight speed (m/s) the blob is not stretched along its path.
@export var stretch_min_mps: float = 0.5
## Lean into the run per m/s of speed.
@export var lean_per_mps: float = 0.02
## Lean bends the body from this height down (share of the radius above the center, 0 = middle).
@export var lean_height_bias: float = 0.3
## Ring speed (radius / s) one m/s of landing speed adds to the pancake.
@export var land_per_mps: float = 0.2
## On landing the sides bulge by this share of the squeeze; the top is pushed down by this share.
@export var land_bulge: float = 0.8
@export var land_top_share: float = 0.7
## Dent where the blob touched the ball (ring speed, radius / s).
@export var hit_dent: float = 2.4
## Share of the hit dent the far side bulges out by.
@export var hit_bulge: float = 0.5
## Side pressed against a sticky wall is flattened to this share of the radius.
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
