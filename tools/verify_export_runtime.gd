extends SceneTree
## Run EXTERNALLY against a pack, with --path pointing at an empty directory.
## No project class preloads: every game dependency must resolve from the pack.
## The sole external helper is this tool's sibling quiet-shutdown implementation.
const Quiesce := preload("quiesce.gd")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	create_timer(30.0, true, false, true).timeout.connect(func():
		push_error("EXPORT RUNTIME FAIL: probe exceeded its deadline")
		quit(1))
	# This probe loads the main scene, whose bridge initializes a native Steam
	# singleton immediately. Account tests are separate and explicitly scoped.
	if Engine.has_singleton("Steam"):
		push_error("EXPORT RUNTIME FAIL: use plain Godot for this offline pack inspector")
		quit(1)
		return
	if FileAccess.file_exists("res://project.godot") or not FileAccess.file_exists("res://project.binary"):
		push_error("EXPORT RUNTIME FAIL: expected a packed project with no source-tree fallback")
		quit(1)
		return
	for directory in ["tests", "docs", "tools", "addons/godot_mcp", "tmp",
			"assets_src", "art_candidates", "build", "reviews", "skills"]:
		if DirAccess.dir_exists_absolute("res://" + directory):
			push_error("EXPORT RUNTIME FAIL: bundled development directory: " + directory)
			quit(1)
			return
	var manifest := FileAccess.get_file_as_bytes("res://assets/input/actions.vdf")
	if manifest.is_empty():
		push_error("EXPORT RUNTIME FAIL: missing Steam Input manifest")
		quit(1)
		return
	var shader: Shader = load("res://src/view/hud_visibility.gdshader")
	if shader == null or not shader.code.contains("uniform vec2 player_one"):
		push_error("EXPORT RUNTIME FAIL: HUD visibility shader missing or invalid")
		quit(1)
		return
	var texture_paths: Array[String] = []
	for pose in ["idle", "move_forward_0", "move_forward_1", "move_backward_0",
			"move_backward_1", "crouch", "shoot", "throw", "roll", "downed", "interact", "bash"]:
		texture_paths.append("res://assets/troops/anim/player/" + pose + ".png")
	for enemy in ["assault", "smg", "shotgun", "lmg", "sniper"]:
		for pose in ["idle", "move_0", "move_1", "crouch", "windup", "shoot", "stunned", "downed"]:
			texture_paths.append("res://assets/troops/anim/enemy_" + enemy + "/" + pose + ".png")
	for bullet in ["player", "enemy", "sniper", "piercing"]:
		texture_paths.append("res://assets/projectiles/bullet_" + bullet + ".png")
	for path in texture_paths:
		var texture: Texture2D = load(path)
		if texture == null or texture.get_width() <= 0 or texture.get_height() <= 0:
			push_error("EXPORT RUNTIME FAIL: missing or empty packed texture: " + path)
			quit(1)
			return
	var scene: PackedScene = load("res://src/main.tscn")
	if scene == null:
		push_error("EXPORT RUNTIME FAIL: main scene cannot load")
		quit(1)
		return
	var main: Node = scene.instantiate()
	root.add_child(main)
	await process_frame
	main._end_splash()
	main.start_game(false)
	var start_tick: int = main.sim.tick_count
	for i in 60:
		await physics_frame
	var advanced: bool = main.sim.tick_count > start_tick
	var hud: Control = main._hud_icons
	hud._sync_visibility()
	var material: ShaderMaterial = hud.material
	var shader_attached: bool = material != null and material.shader == shader
	print("EXPORT RESOURCES: ", texture_paths.size(), " character/projectile textures; HUD shader attached=", shader_attached)
	# Verify the new shipped behavior, not just a version label or source file.
	var ready_verified := false
	if main.has_method("_ready_tally_state"):
		main.start_game(true)
		main.set_physics_process(false)
		main.sim.intermission_ticks = 180
		main.sim.ready_hold = 0
		var input_script: Script = load("res://src/sim/sim_input.gd")
		var input: RefCounted = input_script.new()
		input.set("revive", true)
		# Preserve the packed script's typed Array[SimInput]; an untyped external
		# array assignment cannot cross that exported class boundary.
		main._last_inputs.clear()
		main._last_inputs.append(input)
		main.sim._step_waves(main._last_inputs)
		var held: Dictionary = main._ready_tally_state()
		input.set("revive", false)
		main.sim._step_waves(main._last_inputs)
		ready_verified = String(held.get("detail", "")).contains("RELEASE") \
			and float(held.get("progress", 0.0)) > 0.0 \
			and main._ready_tally_state().is_empty() and main.sim.ready_hold == 0
	await Quiesce.teardown(self, main)
	if not advanced or not shader_attached:
		push_error("EXPORT RUNTIME FAIL: campaign did not advance or HUD shader not attached")
		quit(1)
		return
	if not ready_verified:
		push_error("EXPORT RUNTIME FAIL: packed solo ready-up feedback is missing or does not cancel")
		quit(1)
		return
	print("EXPORT READY PASS: packed solo hold shows progress and release clears it")
	print("EXPORT RUNTIME PASS: packed main scene boots, manifest reads, campaign advances")
	quit(0)
