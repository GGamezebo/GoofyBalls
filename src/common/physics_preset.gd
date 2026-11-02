class_name PhysicsPreset
extends Resource

## Physics numbers for one preset (Classic, Moon, ...). Meters, seconds, y up.

@export_group("Blob")
@export var blob_radius: float = 0.5
@export var move_speed: float = 6.5
## Tar blob (Gish): reaches full speed in ~0.15 s and stops a bit faster than it starts.
@export var ground_accel: float = 45.0
@export var ground_friction: float = 65.0
@export var air_control: float = 0.55
@export var jump_velocity: float = 11.6
@export var gravity: float = 22.0
## Gravity multiplier while rising with the jump released: tap = short hop, hold = full jump.
@export var jump_cut_gravity: float = 2.2
## Snap horizontal speed to the stick on the floor (crisp control) instead of accelerating.
@export var snap_move: bool = false
## Outer walls (never nets): pushing into one in the air sticks to it and slides down this slow.
@export var wall_slide_speed: float = 1.4
@export var wall_jump_velocity: float = 10.5
@export var wall_jump_push: float = 5.5

@export_group("Hit")
@export var hit_speed: float = 8.8
@export var hit_min_up: float = 4.5
@export var hit_reflect: float = 0.4
@export var hit_push: float = 0.75
@export var hit_floor_vy: float = -10.0
@export var touch_cooldown_ticks: int = 12

@export_group("Ball")
@export var ball_radius: float = 0.35
## Tar ball (Gish): heavier than a beach ball, soft, a little sticky.
@export var ball_gravity: float = 5.0
@export var ball_damp: float = 0.115
## Restitution along the normal on walls, ceiling and nets (soft: loses energy).
@export var ball_bounce: float = 0.62
## Share of the speed along a side wall / net the tar loses on contact (0 = slick, 1 = glued).
## Keep it low: high grip slides the ball down the back wall into cheap 4-touch faults.
@export var ball_grip: float = 0.15
## Ticks the ball sticks to a blob after a touch before it is launched (0 = instant hit).
## It rides along meanwhile, so moving / jumping while it sticks steers the shot.
@export var ball_stick_ticks: int = 3
@export var ball_max_speed: float = 38.0
@export var ball_substeps: int = 4


func to_dict() -> Dictionary:
	return {
		"blob_radius": blob_radius, "move_speed": move_speed, "ground_accel": ground_accel,
		"air_control": air_control, "jump_velocity": jump_velocity, "gravity": gravity,
		"snap_move": snap_move, "ground_friction": ground_friction,
		"jump_cut_gravity": jump_cut_gravity, "wall_slide_speed": wall_slide_speed,
		"wall_jump_velocity": wall_jump_velocity, "wall_jump_push": wall_jump_push,
		"hit_speed": hit_speed, "hit_min_up": hit_min_up,
		"hit_reflect": hit_reflect, "hit_push": hit_push, "hit_floor_vy": hit_floor_vy,
		"touch_cooldown_ticks": touch_cooldown_ticks, "ball_radius": ball_radius,
		"ball_gravity": ball_gravity, "ball_damp": ball_damp, "ball_bounce": ball_bounce,
		"ball_grip": ball_grip, "ball_stick_ticks": ball_stick_ticks,
		"ball_max_speed": ball_max_speed, "ball_substeps": ball_substeps,
	}
