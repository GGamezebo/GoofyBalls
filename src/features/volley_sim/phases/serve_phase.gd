class_name ServePhase
extends SimPhase

## Blobs line up in their zones, the ball hangs above the serving team's first player.
## After `serve_delay_ticks` → PLAY.


static func get_state() -> String:
	return SimPhaseStates.SERVE


func _init() -> void:
	super(get_state(), VolleySim.Phase.SERVE)


func enter(prev_state: FSMState, event_data: Dictionary) -> void:
	super(prev_state, event_data)
	var sim := _sim()
	var state := sim.state
	var arena: Dictionary = sim.cfg["arena"]
	state["touch_team"] = -1
	state["touch_count"] = 0

	var radius := sim.param("blob_radius")
	var players: Array = state["players"]
	var zones: Array = state["zones"]
	var team_sizes: Array = sim.cfg["team_sizes"]
	var index := 0
	for team in team_sizes.size():
		var zone: Dictionary = zones[team]
		var size := int(team_sizes[team])
		for k in size:
			var player: Dictionary = players[index]
			var t := float(k + 1) / float(size + 1)
			player["x"] = float(zone["x_min"]) + (float(zone["x_max"]) - float(zone["x_min"])) * t
			player["y"] = radius
			player["vx"] = 0.0
			player["vy"] = 0.0
			player["cling"] = 0
			index += 1

	var server := _first_player_of(state, int(state["serving_team"]))
	var server_x := float(server["x"])
	var toward_center := 0.0
	if server_x < 0.0:
		toward_center = 1.0
	elif server_x > 0.0:
		toward_center = -1.0
	var ball: Dictionary = state["balls"][0]
	ball["x"] = server_x + toward_center * float(arena["serve_offset"])
	ball["y"] = float(arena["serve_height"])
	ball["vx"] = 0.0
	ball["vy"] = 0.0
	ball["frozen"] = true
	ball["last_toucher"] = -1
	ball["cooldown"] = 0
	ball["stick"] = 0
	ball["stick_player"] = -1


func tick() -> void:
	var sim := _sim()
	if _count_tick(sim.state) >= int(sim.cfg["rules"]["serve_delay_ticks"]):
		add_event(SimPhaseEvents.SERVE_DONE)


static func _first_player_of(state: Dictionary, team: int) -> Dictionary:
	for player in state["players"]:
		if int(player["team"]) == team:
			return player
	return state["players"][0]
