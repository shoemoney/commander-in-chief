extends SceneTree
## Headless boot smoke-test: instantiates the real main scene, lets it run
## _ready() + a couple hundred physics ticks, then reads ONE frame back and
## asserts it carries a picture. Catches parse/runtime errors in main.gd/view
## that the sim-only test suite can't see (it never touches src/main.gd or the
## scene tree), plus the "boots fine, renders nothing" class of bug that a
## crash-only smoke test happily reports as OK.
## Run:  godot --headless -s res://tools/smoke.gd          (boot check only)
##       godot --rendering-method gl_compatibility -s res://tools/smoke.gd
##                                                          (+ pixel check)
## Godot prints "SCRIPT ERROR"/"Parse Error" to stderr on any fault — the
## caller greps for that; exit code is 1 if the frame check fails.

const Shots := preload("res://tools/screenshots.gd")   # shared liveness predicate
const Quiesce := preload("res://tools/quiesce.gd")     # quiet audio-graph shutdown

const FRAMES := 200


var _main: Node2D


func _initialize() -> void:
	_main = (load("res://src/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	_run()


func _run() -> void:
	for _i in FRAMES:
		await process_frame
	# Structural class pin (works headless — it walks the tree, not the frame):
	# a shader that reads the screen ANYWHERE but bare SCREEN_UV distorts what it
	# samples (blur/wobble/chroma), so it must sit BELOW the $HUD canvas layer or
	# it smears boss bars / objective chips / control prompts. The concussion
	# low-pass shipped on fx_layer at 100, above the HUD at 1, and radial-blurred
	# the HUD with the world. Per-pixel grades (bare SCREEN_UV only: grade.gdshader)
	# and FRAGCOORD passes (crt.gdshader) are exempt — they cannot smear.
	if not _check_screen_distortion_layers():
		print("SMOKE FAILED — a screen-distorting shader draws at/above the HUD canvas layer")
		await Quiesce.teardown(self, _main)
		quit(1)
		return
	# The boot splash is an opaque near-monochrome cinematic that legitimately
	# measures 3 colours / low spread for its whole run — grading THAT frame would
	# just be grading the splash. Retire it (same reason screenshots.gd does) so the
	# check grades the real title screen, which measures ~2200 colours / stddev ~22.
	_main._splash_t = 0.0
	if _main._splash_layer != null:
		_main._splash_layer.visible = false
	await process_frame
	# --headless is a dummy display server with NO framebuffer: get_image() returns
	# null there no matter how healthy the game is. Say so out loud rather than
	# letting a skipped check read as a passed one.
	if DisplayServer.get_name() == "headless":
		print("SMOKE OK (boot only — headless has no framebuffer, pixel check SKIPPED)")
		await Quiesce.teardown(self, _main)
		quit(0)
		return
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	if not Shots._frame_is_live(img):
		var st := {"colors": 0, "stddev": 0.0} if img == null or img.is_empty() else Shots.frame_stats(img)
		push_error("smoke: the game booted but rendered nothing — %d distinct colours, luma stddev %.2f" % [st["colors"], st["stddev"]])
		print("SMOKE FAILED — blank frame (colors=%d stddev=%.2f)" % [st["colors"], st["stddev"]])
		await Quiesce.teardown(self, _main)
		quit(1)
		return
	var s := Shots.frame_stats(img)
	print("SMOKE OK (live frame: colors=%d stddev=%.2f)" % [s["colors"], s["stddev"]])
	await Quiesce.teardown(self, _main)
	quit(0)


func _check_screen_distortion_layers() -> bool:
	var hud := _main.get_node_or_null("HUD") as CanvasLayer
	if hud == null:
		push_error("smoke: no $HUD CanvasLayer in the main scene — the distortion-layer pin has nothing to compare against")
		return false
	var ok := true
	var stack: Array[Node] = [_main]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		stack.append_array(n.get_children())
		if not n is CanvasItem:
			continue
		var mat: Variant = n.get("material")
		if not mat is ShaderMaterial or mat.shader == null:
			continue
		var code: String = mat.shader.code
		if not code.contains("hint_screen_texture") or not _samples_beyond_screen_uv(code):
			continue
		var layer := 0   # no enclosing CanvasLayer = the world canvas itself
		var p := n.get_parent()
		while p != null:
			if p is CanvasLayer:
				layer = p.layer
				break
			p = p.get_parent()
		if layer >= hud.layer:
			push_error("smoke: %s offset-samples the screen (blur/distortion class) at canvas layer %d, >= the HUD's %d — it smears the HUD chrome" % [n.get_path(), layer, hud.layer])
			ok = false
	return ok


func _samples_beyond_screen_uv(code: String) -> bool:
	# Any texture() sample whose UV argument is not literally SCREEN_UV smears
	# neighbourhoods, not pixels — that is the distortion class this pin governs.
	var re := RegEx.create_from_string("texture\\(\\s*[A-Za-z_]\\w*\\s*,\\s*([^)]+?)\\s*\\)")
	for m in re.search_all(code):
		if m.get_string(1) != "SCREEN_UV":
			return true
	return false
