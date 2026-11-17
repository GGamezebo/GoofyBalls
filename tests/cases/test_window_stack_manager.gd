extends TestCase

## WindowStackManager: open / back order, visibility, ev_opened / ev_closed and ui_cancel handling.


func test_open_and_back() -> void:
	var rig := _rig()
	var manager: WindowStackManager = rig["manager"]
	var main: Control = rig["main"]
	var friend: Control = rig["friend"]
	expect(main.visible and not friend.visible, "starts on the default window")
	manager.open_stacked_window(friend)
	expect(friend.visible and not main.visible, "forward shows the target and hides the previous window")
	expect(manager.can_go_back(), "can go back from the second window")
	manager.close_stacked_window()
	expect(main.visible and not friend.visible, "back restores the previous window")
	expect(not manager.can_go_back(), "the root window cannot be closed")
	manager.close_stacked_window()
	expect(main.visible, "closing the root window is a no-op")
	_free(rig)


func test_events_follow_visibility() -> void:
	var rig := _rig()
	var manager: WindowStackManager = rig["manager"]
	var main: Control = rig["main"]
	var friend: Control = rig["friend"]
	var log: Array[String] = []
	var label := func(window: Control) -> String: return "main" if window == main else "friend"
	manager.ev_opened.connect(func(window: Control) -> void: log.append("open " + label.call(window)))
	manager.ev_closed.connect(func(window: Control) -> void: log.append("close " + label.call(window)))
	manager.open_stacked_window(friend)
	expect_eq(log, ["close main", "open friend"] as Array[String], "forward: previous closes, target opens")
	log.clear()
	manager.close_stacked_window()
	expect_eq(log, ["close friend", "open main"] as Array[String], "back: top closes, previous reopens")
	expect(main.visible, "previous window is visible again")
	_free(rig)


func test_ui_cancel_goes_back_only_when_unhandled() -> void:
	var rig := _rig()
	var manager: WindowStackManager = rig["manager"]
	var main: Control = rig["main"]
	var friend: Control = rig["friend"]
	manager.open_stacked_window(friend)
	var cancel := InputEventAction.new()
	cancel.action = "ui_cancel"
	cancel.pressed = true
	manager._unhandled_input(cancel)
	expect(main.visible and not friend.visible, "ui_cancel closes the top window")
	manager._unhandled_input(cancel)
	expect(main.visible, "ui_cancel on the root window does nothing")
	_free(rig)


func _rig() -> Dictionary:
	var main := Control.new()
	var friend := Control.new()
	friend.hide()
	var manager := WindowStackManager.new()
	manager.default_window = main
	tree.root.add_child(main)
	tree.root.add_child(friend)
	tree.root.add_child(manager)
	return {"manager": manager, "main": main, "friend": friend}


func _free(rig: Dictionary) -> void:
	for key in rig:
		(rig[key] as Node).queue_free()
