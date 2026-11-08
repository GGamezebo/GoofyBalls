class_name PlayPhase
extends SimPhase

## Rally in progress: the ball flies, bounces off walls / nets / blobs, teams count touches.
## Ball on the floor or one touch too many → RALLY_LOST (→ POINT).
##
## Tar ball (Gish feel): heavy, soft bounces that grip walls and nets, and a short stick to the
## blob on a touch (it rides along, then launches). Hitbox stays a circle; squish is view-only,
## driven by `impact_serial` + `impact_nx/ny` (direction the ball was pushed) + `impact_power`.


static func get_state() -> String:
	return SimPhaseStates.PLAY


func _init() -> void:
	super(get_state(), VolleySim.Phase.PLAY)


func enter(prev_state: FSMState, event_data: Dictionary) -> void:
	super(prev_state, event_data)
	for ball in _sim().state["balls"]:
		ball["frozen"] = false


func tick() -> void:
	var sim := _sim()
	var state := sim.state
	var physics: Dictionary = sim.cfg["physics"]
	var arena: Dictionary = sim.cfg["arena"]
	var ball: Dictionary = state["balls"][0]
	ball["cooldown"] = maxi(0, int(ball["cooldown"]) - 1)
	if int(ball["stick"]) > 0:
		_step_stuck(sim, ball)
		return

	var vx := float(ball["vx"])
	var vy := float(ball["vy"])
	vy -= sim.param("ball_gravity") * VolleySim.DT
	var damp := maxf(0.0, 1.0 - sim.param("ball_damp") * VolleySim.DT)
	vx *= damp
	vy *= damp
	var max_speed := sim.param("ball_max_speed")
	var speed := sqrt(vx * vx + vy * vy)
	if speed > max_speed:
		vx = vx / speed * max_speed
		vy = vy / speed * max_speed
	ball["vx"] = vx
	ball["vy"] = vy

	var substeps := int(physics["ball_substeps"])
	var sub_dt := VolleySim.DT / float(substeps)
	for _k in substeps:
		ball["x"] = float(ball["x"]) + float(ball["vx"]) * sub_dt
		ball["y"] = float(ball["y"]) + float(ball["vy"]) * sub_dt
		_collide_walls(sim, ball)
		for net in state["nets"]:
			_collide_net(sim, ball, net)
		if _collide_players(sim, ball):
			return # touch fault ended the rally
		if int(ball["stick"]) > 0:
			return # glued to a blob: it carries the ball from the next tick

	var ball_radius := sim.param("ball_radius")
	if float(ball["y"]) <= float(arena["floor_score_y"]) and (float(ball["vy"]) < -1.0 or float(ball["y"]) <= ball_radius + 0.01):
		_impact(ball, 0.0, 1.0, -float(ball["vy"]))
		_lose_rally(sim.zone_of(float(ball["x"])), VolleySim.Reason.FLOOR)


func _lose_rally(losing_team: int, reason: int) -> void:
	add_event(SimPhaseEvents.RALLY_LOST, {"losing_team": losing_team, "reason": reason})


## The ball rides on its blob at the contact offset; on the last stuck tick the hit launches it.
## Velocity keeps the incoming value meanwhile (the hit reflects part of it).
func _step_stuck(sim: VolleySim, ball: Dictionary) -> void:
	var player: Dictionary = sim.state["players"][int(ball["stick_player"])]
	ball["x"] = float(player["x"]) + float(ball["stick_dx"])
	ball["y"] = maxf(float(player["y"]) + float(ball["stick_dy"]), sim.param("ball_radius"))
	ball["stick"] = int(ball["stick"]) - 1
	if int(ball["stick"]) > 0:
		return
	var dx := float(ball["stick_dx"])
	var dy := float(ball["stick_dy"])
	var dist := sqrt(dx * dx + dy * dy)
	var nx := 0.0
	var ny := 1.0
	if dist > 0.001:
		nx = dx / dist
		ny = dy / dist
	_apply_hit(sim, player, ball, nx, ny)
	ball["stick_player"] = -1
	ball["cooldown"] = int(sim.cfg["physics"]["touch_cooldown_ticks"])
	_impact(ball, nx, ny, sqrt(float(ball["vx"]) * float(ball["vx"]) + float(ball["vy"]) * float(ball["vy"])))
	# Launch from a legal spot: the ride may have pressed the ball into a wall or a net.
	_collide_walls(sim, ball)
	for net in sim.state["nets"]:
		_collide_net(sim, ball, net)


## Visual squish event: the ball was pushed along (nx, ny) with `power` m/s of speed change.
static func _impact(ball: Dictionary, nx: float, ny: float, power: float) -> void:
	if power < 1.0:
		return
	ball["impact_serial"] = int(ball["impact_serial"]) + 1
	ball["impact_nx"] = nx
	ball["impact_ny"] = ny
	ball["impact_power"] = power


func _collide_walls(sim: VolleySim, ball: Dictionary) -> void:
	var arena: Dictionary = sim.cfg["arena"]
	var radius := sim.param("ball_radius")
	var bounce := sim.param("ball_bounce")
	var slide := 1.0 - sim.param("ball_grip")
	var limit := float(arena["half_width"]) - radius
	var x := float(ball["x"])
	if x > limit or x < -limit:
		var nx := -1.0 if x > limit else 1.0
		var vn := float(ball["vx"]) * nx
		ball["x"] = -limit * nx
		if vn < 0.0:
			ball["vx"] = -vn * bounce * nx
			ball["vy"] = float(ball["vy"]) * slide
			_impact(ball, nx, 0.0, -vn)
	# Ceiling: no grip, so lobs stay readable.
	var top := float(arena["ceiling"]) - radius
	if float(ball["y"]) > top:
		ball["y"] = top
		if float(ball["vy"]) > 0.0:
			_impact(ball, 0.0, -1.0, float(ball["vy"]))
			ball["vy"] = -float(ball["vy"]) * bounce


func _collide_net(sim: VolleySim, ball: Dictionary, net: Dictionary) -> void:
	var radius := sim.param("ball_radius")
	var x := float(ball["x"])
	var y := float(ball["y"])
	var net_x := float(net["x"])
	var half_w := float(net["half_w"])
	var cx := clampf(x, net_x - half_w, net_x + half_w)
	var cy := clampf(y, 0.0, float(net["top"]))
	var dx := x - cx
	var dy := y - cy
	var d2 := dx * dx + dy * dy
	if d2 >= radius * radius:
		return
	var nx: float
	var ny: float
	var dist := sqrt(d2)
	if dist < 0.0001:
		# Center inside the net box: push out sideways, away from the net center.
		nx = 1.0 if x >= net_x else -1.0
		ny = 0.0
		dist = 0.0
	else:
		nx = dx / dist
		ny = dy / dist
	var push := radius - dist
	ball["x"] = x + nx * push
	ball["y"] = y + ny * push
	var vx := float(ball["vx"])
	var vy := float(ball["vy"])
	var vn := vx * nx + vy * ny
	if vn < 0.0:
		var bounce := sim.param("ball_bounce")
		var slide := 1.0 - sim.param("ball_grip")
		# Tangential part slows by the grip, normal part bounces back softly.
		var tx := (vx - vn * nx) * slide
		var ty := (vy - vn * ny) * slide
		ball["vx"] = tx - bounce * vn * nx
		ball["vy"] = ty - bounce * vn * ny
		_impact(ball, nx, ny, -vn)


## Returns true when a touch fault ended the rally.
func _collide_players(sim: VolleySim, ball: Dictionary) -> bool:
	var state := sim.state
	var physics: Dictionary = sim.cfg["physics"]
	var reach := sim.param("blob_radius") + sim.param("ball_radius")
	var players: Array = state["players"]
	for i in players.size():
		var player: Dictionary = players[i]
		var dx := float(ball["x"]) - float(player["x"])
		var dy := float(ball["y"]) - float(player["y"])
		var d2 := dx * dx + dy * dy
		if d2 >= reach * reach:
			continue
		var dist := sqrt(d2)
		var nx: float
		var ny: float
		if dist < 0.001:
			nx = 0.0
			ny = 1.0
			dist = 0.0
		else:
			nx = dx / dist
			ny = dy / dist
		# Blobs are kinematic: always separate the ball.
		var push := reach - dist
		ball["x"] = float(ball["x"]) + nx * push
		ball["y"] = float(ball["y"]) + ny * push

		if int(ball["last_toucher"]) == i and int(ball["cooldown"]) > 0:
			continue
		var stick_ticks := int(physics["ball_stick_ticks"])
		if stick_ticks > 0:
			# Tar: glue to the blob now, launch in `_step_stuck` once the stick runs out.
			var rel_vn := (float(ball["vx"]) - float(player["vx"])) * nx + (float(ball["vy"]) - float(player["vy"])) * ny
			_impact(ball, nx, ny, -rel_vn)
			ball["stick"] = stick_ticks
			ball["stick_player"] = i
			ball["stick_dx"] = nx * reach
			ball["stick_dy"] = ny * reach
		else:
			_apply_hit(sim, player, ball, nx, ny)
			ball["cooldown"] = int(physics["touch_cooldown_ticks"])
		ball["last_toucher"] = i
		state["touch_serial"] = int(state["touch_serial"]) + 1
		state["touch_player"] = i
		if _register_touch(sim, int(player["team"])):
			return true
		if stick_ticks > 0:
			return false
	return false


func _apply_hit(sim: VolleySim, player: Dictionary, ball: Dictionary, nx: float, ny: float) -> void:
	var loft := clampf(ny, 0.0, 1.0)
	var ivx := float(ball["vx"])
	var ivy := float(ball["vy"])
	var dot := ivx * nx + ivy * ny
	var bx := ivx - 2.0 * dot * nx
	var by := ivy - 2.0 * dot * ny
	var hit := sim.param("hit_speed") * sim.param("hit_push")
	var reflect := sim.param("hit_reflect")
	var nvx := bx * reflect + nx * hit + float(player["vx"]) * sim.param("hit_carry_x")
	var nvy := by * reflect + ny * hit + float(player["vy"]) * sim.param("hit_carry_y")
	if loft > sim.param("hit_loft_min"):
		nvy = maxf(nvy, sim.param("hit_min_up") * loft)
	else:
		nvy = maxf(nvy, sim.param("hit_floor_vy"))
	ball["vx"] = nvx
	ball["vy"] = nvy


## Returns true when this touch is one too many for the team (rally lost).
func _register_touch(sim: VolleySim, team: int) -> bool:
	var state := sim.state
	if team != int(state["touch_team"]):
		state["touch_team"] = team
		state["touch_count"] = 1
	else:
		state["touch_count"] = int(state["touch_count"]) + 1
	if int(state["touch_count"]) > int(sim.cfg["rules"]["max_touches"]):
		_lose_rally(team, VolleySim.Reason.TOUCHES)
		return true
	return false
