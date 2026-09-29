extends SceneTree
## Positive and negative controls for capture-only input isolation.
const Capture := preload("res://tools/capture_gameplay_trailer.gd")
const Quiesce := preload("res://tools/quiesce.gd")

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var main: Node2D = (load("res://src/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	await process_frame
	main.no_autopause = true
	main._splash_t = 0.0
	main._splash_layer.visible = false
	main.start_game(true)
	main.set_physics_process(false)
	var original: SimWorld = main.sim
	Capture.isolate_capture_input(root)
	var key := InputEventKey.new()
	key.keycode = KEY_R
	key.physical_keycode = KEY_R
	key.pressed = true
	root.push_input(key)
	await process_frame
	var blocked: bool = main.sim == original
	root.set_disable_input(false)
	root.push_input(key)
	await process_frame
	var control: bool = main.sim != original
	print("MOVIE INPUT CHECK blocked=%s normal_restart=%s" % [blocked, control])
	await Quiesce.teardown(self, main)
	quit(0 if blocked and control else 1)
