class_name CourtView
extends Node2D

## Court (concept): dark floor strip with a cyan neon edge, faint walls and ceiling, glowing nets
## with a white cap; a zone flashes in the scoring team color after a point. The look lives in
## court_view.tscn and net_view.tscn and is tuned in the editor (the scene shows the default
## 1600×900 layout of arena S). The script only fits the nodes to the court MatchView gives:
## wall and floor points, floor strip width, one NetView per net, the flash rectangle.

@export var flash_sec: float = 0.6
## How far the floor sticks out past the walls.
@export var floor_overhang_px: float = 24.0
@export_group("Nodes")
## Its color alpha is the flash strength; the color itself comes from the scoring team.
@export var flash: ColorRect
@export var walls: Line2D
@export var floor_strip: ColorRect
## Lines drawn along the floor edge (glow, line).
@export var floor_lines: Array[Line2D] = []
## Holds the nets; whatever is there in the scene is an editor preview.
@export var nets_parent: Node2D
@export var net_template: PackedScene

## Court rectangle in px: x from left wall to right wall, y from ceiling to floor.
var court := Rect2(60, 120, 1480, 640)
## Each net: {"x": px, "top": px, "w": px}.
var nets: Array[Dictionary] = []
## Each zone: {"x_min": px, "x_max": px}.
var zones: Array[Dictionary] = []

var _flash_alpha: float = 0.12
var _flash_t: float = 0.0


func _ready() -> void:
	_flash_alpha = flash.color.a
	flash.visible = false


func setup(p_court: Rect2, p_nets: Array[Dictionary], p_zones: Array[Dictionary]) -> void:
	court = p_court
	nets = p_nets
	zones = p_zones
	var floor_y := court.end.y
	walls.points = PackedVector2Array([
		Vector2(court.position.x, floor_y), court.position,
		Vector2(court.end.x, court.position.y), Vector2(court.end.x, floor_y),
	])
	var left := court.position.x - floor_overhang_px
	var right := court.end.x + floor_overhang_px
	floor_strip.position = Vector2(left, floor_y)
	floor_strip.size = Vector2(right - left, floor_strip.size.y)
	for line in floor_lines:
		line.points = PackedVector2Array([Vector2(left, floor_y), Vector2(right, floor_y)])
	for child in nets_parent.get_children():
		nets_parent.remove_child(child)
		child.queue_free()
	for net in nets:
		var view: NetView = net_template.instantiate()
		nets_parent.add_child(view)
		var top := float(net["top"])
		view.setup(Vector2(float(net["x"]), top), floor_y - top, float(net["w"]))


func flash_zone(zone: int, color: Color) -> void:
	if zone < 0 or zone >= zones.size():
		return
	var rect: Dictionary = zones[zone]
	flash.position = Vector2(float(rect["x_min"]), court.position.y)
	flash.size = Vector2(float(rect["x_max"]) - float(rect["x_min"]), court.size.y)
	flash.color = Color(color, _flash_alpha)
	flash.visible = true
	_flash_t = 1.0


func _process(delta: float) -> void:
	if _flash_t <= 0.0:
		return
	_flash_t = maxf(0.0, _flash_t - delta / flash_sec)
	flash.color.a = _flash_alpha * _flash_t
	flash.visible = _flash_t > 0.0
