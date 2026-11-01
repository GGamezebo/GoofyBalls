class_name PhysicsPreset
extends Resource

## Physics numbers for one preset (Classic, Moon, ...). Meters, seconds, y up.
## Balance knobs: every number the sim uses for movement, hits and the ball lives here, so a
## preset is tuned in the inspector (hover a field for what it does).

@export_group("Blob")
@export var blob_radius: float = 0.5
## Top run speed (m/s).
@export var move_speed: float = 6.5
## How fast the run speed is reached on the floor when `snap_move` is off (m/s²).
@export var ground_accel: float = 18.0
## Steering in the air, as a share of the run speed.
@export_range(0.0, 1.0) var air_control: float = 0.55
## Air acceleration = move_speed × air_control × this (1/s): how quickly the air steering bites.
@export var air_accel_scale: float = 8.0
## Upward speed at the jump (m/s): jump height = v² / (2 × gravity).
@export var jump_velocity: float = 11.6
## Blob gravity (m/s²).
@export var gravity: float = 22.0
## Snap horizontal speed to the stick on the floor (crisp control) instead of accelerating.
@export var snap_move: bool = true

@export_group("Hit")
## Base speed the ball gets from a touch (m/s), multiplied by `hit_push`.
@export var hit_speed: float = 8.0
@export var hit_push: float = 0.75
## Share of the ball's incoming speed that bounces back off the blob.
@export_range(0.0, 1.0) var hit_reflect: float = 0.4
## Share of the blob's own run speed passed to the ball.
@export_range(0.0, 2.0) var hit_carry_x: float = 0.75
## Share of the blob's own jump speed passed to the ball.
@export_range(0.0, 2.0) var hit_carry_y: float = 0.5
## A touch counts as "from below" when the contact normal points up more than this (0..1).
@export_range(0.0, 1.0) var hit_loft_min: float = 0.2
## Minimal upward ball speed after a touch from below (m/s), scaled by how much from below.
@export var hit_min_up: float = 4.0
## Side / top touches: the ball never goes down faster than this (m/s, negative = down).
@export var hit_floor_vy: float = -10.0
## The same blob can't touch the ball again for this many ticks (60 = 1 s).
@export var touch_cooldown_ticks: int = 12

@export_group("Ball")
@export var ball_radius: float = 0.35
## Ball gravity (m/s²): lower = floatier ball.
@export var ball_gravity: float = 3.92
## Air drag per second (share of speed lost).
@export_range(0.0, 1.0) var ball_damp: float = 0.115
## Share of speed kept after hitting a wall or the net.
@export_range(0.0, 1.0) var ball_bounce: float = 0.78
@export var ball_max_speed: float = 38.0
## Collision steps per tick (more = no tunnelling through thin nets at high speed).
@export var ball_substeps: int = 4


func to_dict() -> Dictionary:
	return {
		"blob_radius": blob_radius, "move_speed": move_speed, "ground_accel": ground_accel,
		"air_control": air_control, "air_accel_scale": air_accel_scale,
		"jump_velocity": jump_velocity, "gravity": gravity,
		"snap_move": snap_move, "hit_speed": hit_speed, "hit_min_up": hit_min_up,
		"hit_reflect": hit_reflect, "hit_push": hit_push, "hit_floor_vy": hit_floor_vy,
		"hit_carry_x": hit_carry_x, "hit_carry_y": hit_carry_y, "hit_loft_min": hit_loft_min,
		"touch_cooldown_ticks": touch_cooldown_ticks, "ball_radius": ball_radius,
		"ball_gravity": ball_gravity, "ball_damp": ball_damp, "ball_bounce": ball_bounce,
		"ball_max_speed": ball_max_speed, "ball_substeps": ball_substeps,
	}
