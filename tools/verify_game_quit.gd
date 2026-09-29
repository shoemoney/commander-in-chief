extends SceneTree
## Exercises production exit routes without Quiesce or manually stopping audio.
## Run through tools/run_tests.sh; its stdout gate catches final audio leaks.

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	create_timer(15.0, true, false, true).timeout.connect(func():
		push_error("QUIT PATH FAIL: application did not exit")
		quit(1))
	var scene: PackedScene = load("res://src/main.tscn")
	var main: Node = scene.instantiate()
	root.add_child(main)
	await create_timer(0.7, true, false, true).timeout
	if main._sfx._pb == null or main._sfx._ui_pb == null:
		push_error("QUIT PATH FAIL: audio was never initialized")
		quit(1)
		return
	main._end_splash()
	var route := OS.get_environment("QUIT_PROBE_ROUTE")
	if route in ["window", "paused-window"]:
		main.start_game(false)
	var last_tick: int = main.sim.tick_count
	if route == "paused-window":
		paused = true
		Engine.time_scale = 0.0
	print("QUIT PATH REQUESTED: ", route if not route.is_empty() else "menu")
	if route in ["window", "paused-window"]:
		root.propagate_notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
		root.propagate_notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	else:
		main._menu.open(main._menu.Mode.TITLE, "quit")
		main._menu._press()
		main._menu._press()
	await create_timer(0.05, true, false, true).timeout
	if main.process_mode != Node.PROCESS_MODE_DISABLED or main._sfx._pb != null or main._sfx._ui_pb != null or main.sim.tick_count != last_tick:
		push_error("QUIT PATH FAIL: gameplay/audio did not stop before exit")
		quit(1)
		return
	print("QUIT DRAIN OBSERVED")
