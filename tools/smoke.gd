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

const FRAMES := 200


var _main: Node2D


func _initialize() -> void:
	_main = (load("res://src/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	_run()


func _run() -> void:
	for _i in FRAMES:
		await process_frame
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
		quit(0)
		return
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	if not Shots._frame_is_live(img):
		var st := {"colors": 0, "stddev": 0.0} if img == null or img.is_empty() else Shots.frame_stats(img)
		push_error("smoke: the game booted but rendered nothing — %d distinct colours, luma stddev %.2f" % [st["colors"], st["stddev"]])
		print("SMOKE FAILED — blank frame (colors=%d stddev=%.2f)" % [st["colors"], st["stddev"]])
		quit(1)
		return
	var s := Shots.frame_stats(img)
	print("SMOKE OK (live frame: colors=%d stddev=%.2f)" % [s["colors"], s["stddev"]])
	quit(0)
