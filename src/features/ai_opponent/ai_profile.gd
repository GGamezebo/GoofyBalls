class_name AiProfile
extends Resource

## How a bot plays (balance knobs, meters and seconds). One `.tres` per difficulty; the battle
## scene picks it (`Game.ai_profile`).

@export_group("Moving")
## Distance to the target at which the bot runs at full speed; closer it slows down.
@export var full_speed_dist: float = 1.2
## Closer than this the bot stops (no jitter around the target).
@export var stop_dist: float = 0.08
## How fast the bot's stick follows what it wants (per second): lower = lazier, more human.
@export var axis_smooth: float = 14.0

@export_group("Positioning")
## Stand this far behind the landing point (away from the net) so the hit sends the ball over.
@export var aim_behind: float = 0.38
## Where to wait while the ball is on the other side (share of the zone depth from the net).
@export_range(0.0, 1.0) var home_fraction: float = 0.45
## Keep at least this far from the net (on top of the blob radius).
@export var net_margin: float = 0.15
## How many ticks ahead the bot predicts the ball (60 = 1 s).
@export var predict_ticks: int = 300

@export_group("Jumping")
## Jump only when the ball is this close horizontally.
@export var jump_range_x: float = 0.9
## Jump only when the falling ball is between these heights.
@export var jump_height_min: float = 1.4
@export var jump_height_max: float = 3.4
