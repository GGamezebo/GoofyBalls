extends IScene

## Main menu context (concept/ui-home): hero blob, yellow launch block — «Против AI»,
## «С другом», and «Вдвоём на одном ПК» (only where PlatformCaps allows). Starts local battles with
## `root_events.ev_start_game({"match_setup": ...})`; the friend-room flow lives in FriendRoomPanel.

@export var root_events: RootEvents
@export var platform_caps: PlatformCaps
@export var vs_ai_setup: MatchSetup
@export var local_2p_setup: MatchSetup
@export var log_settings: LogSettings
@export var vs_ai_button: Button
@export var local_2p_button: Button
@export var friend_room: FriendRoomPanel
@export var hero_blob: BlobView
@export var palette: TeamPalette
## Idle hop of the hero blob.
@export var hero_idle: BlobIdleConfig
@export var hero_radius_px: float = 120.0

var _listener := EventListener.new()
var _log: LogChannel
var _hop: BlobIdle
var _hero_base := Vector2.ZERO


func initialize(_data: Dictionary) -> void:
	_log = LogChannel.new("menu", log_settings)
	_listener.add(vs_ai_button.pressed, _start_local.bind(vs_ai_setup))
	_listener.add(local_2p_button.pressed, _start_local.bind(local_2p_setup))
	_listener.add(platform_caps.changed, _refresh_caps)
	_refresh_caps()
	friend_room.initialize()
	_hop = BlobIdle.new(hero_idle)
	hero_blob.setup(palette.color(0), hero_radius_px, "", false)
	hero_blob.name_label.visible = false
	_hero_base = hero_blob.position
	vs_ai_button.grab_focus()
	_log.info("open", {"local_2p": platform_caps.local_multiplayer})


func deinit() -> void:
	friend_room.deinit()
	_listener.deinit()
	super.deinit()


func _process(delta: float) -> void:
	if _hop == null:
		return
	_hop.advance(delta)
	hero_blob.apply(_hero_base - Vector2(0.0, _hop.height), _hop.speed, _hop.grounded,
		_hero_base.y + hero_radius_px, hero_blob.get_global_mouse_position(), delta)


func _refresh_caps() -> void:
	local_2p_button.visible = platform_caps.local_multiplayer


func _start_local(template: MatchSetup) -> void:
	var setup := template.duplicate(true) as MatchSetup
	setup.match_seed = randi()
	_log.info("start_local", {"humans": setup.local_human_count()})
	root_events.ev_start_game.emit({"match_setup": setup})
