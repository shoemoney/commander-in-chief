extends SceneTree
## External driver. All game resources must come from --main-pack.
const FONT_AWESOME_ICONS := [
	"volume-high", "volume-xmark", "music", "bell-slash", "trophy", "book-open",
	"play", "gamepad", "gear", "rotate", "house", "desktop", "door-open",
	"person-rifle", "stopwatch", "circle-xmark", "minus", "plus", "filter",
	"file-lines", "closed-captioning", "text-height", "film", "medal",
]

func _initialize() -> void:
	_run.call_deferred()


func _fail(message: String) -> void:
	push_error("NATIVE EXPORT FAIL: " + message)
	quit(1)


func _run() -> void:
	create_timer(20.0, true, false, true).timeout.connect(func(): _fail("production exit timed out"))
	if Engine.has_singleton("Steam"):
		_fail("offline smoke requires stock Godot; live Steam initialization needs its own acceptance test")
		return
	var profile := OS.get_environment("NATIVE_EXPORT_PROFILE").replace("\\", "/").simplify_path()
	var save_path := ProjectSettings.globalize_path("user://").replace("\\", "/").simplify_path()
	if not save_path.to_lower().begins_with(profile.to_lower() + "/"):
		_fail("user data escaped the isolated profile")
		return
	if FileAccess.file_exists("res://project.godot") or FileAccess.file_exists("res://tools/native_export_smoke.gd"):
		_fail("source files are visible; this is not an isolated release pack")
		return
	if str(ProjectSettings.get_setting("application/config/version", "")) != OS.get_environment("NATIVE_EXPORT_VERSION"):
		_fail("packed project version does not match the requested release")
		return
	for icon in FONT_AWESOME_ICONS:
		var path: String = "res://assets/fontawesome/solid/" + icon + ".svg"
		var texture: Texture2D = load(path)
		if texture == null or texture.get_width() <= 0 or texture.get_height() <= 0:
			_fail("packed Font Awesome icon cannot load: " + path)
			return
	print("NATIVE EXPORT FONT AWESOME PASS: ", FONT_AWESOME_ICONS.size(), " packed textures loaded")
	var scene: PackedScene = load("res://src/main.tscn")
	if scene == null:
		_fail("packed main scene cannot load")
		return
	var main: Node = scene.instantiate()
	root.add_child(main)
	main.no_autopause = true
	await create_timer(0.7, true, false, true).timeout
	if main._sfx._pb == null or main._sfx._ui_pb == null:
		_fail("audio was never initialized")
		return
	main._end_splash()
	main.start_game(false)
	var start_tick: int = main.sim.tick_count
	for _i in 120:
		await physics_frame
	if main.sim.tick_count <= start_tick:
		_fail("campaign did not advance")
		return
	print("NATIVE EXPORT PROGRESS PASS: packed campaign advanced with initialized audio")
	var last_tick: int = main.sim.tick_count
	var route := OS.get_environment("NATIVE_EXPORT_ROUTE")
	if route == "paused-window":
		paused = true
		Engine.time_scale = 0.0
	if route == "menu":
		main._menu.open(main._menu.Mode.TITLE, "quit")
		main._menu._press()
		main._menu._press()
	else:
		root.propagate_notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
		root.propagate_notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	await create_timer(0.05, true, false, true).timeout
	if main.process_mode != Node.PROCESS_MODE_DISABLED or main._sfx._pb != null or main._sfx._ui_pb != null or main.sim.tick_count != last_tick:
		_fail("production close did not freeze gameplay and release audio")
		return
	print("NATIVE EXPORT QUIT DRAIN PASS: production close froze gameplay and released audio")
