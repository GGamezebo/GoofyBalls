class_name NetView
extends Node2D

## One net, the template CourtView instantiates per net; the node sits at the net top.
## Body (Glow, Pole) is drawn in net_view.tscn for a net of `design_width_px` × `design_height_px`
## and stretched to the real one; Cap is not stretched, so it stays round.

@export var design_width_px: float = 12.0
@export var design_height_px: float = 233.0
## Thin nets on small screens are drawn at least this wide.
@export var min_width_px: float = 6.0
@export var body: Node2D


func setup(top: Vector2, height_px: float, width_px: float) -> void:
	position = top
	body.scale = Vector2(maxf(width_px, min_width_px) / design_width_px, height_px / design_height_px)
