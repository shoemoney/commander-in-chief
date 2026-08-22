extends SceneTree
## Dense frame capture for README/promo GIFs — frames from a REAL run, never a posed state.
##
##   SHOT_DIR=/abs/dir GIF_CHAPTER=3 GIF_SKIP=240 GIF_FRAMES=500 GIF_EVERY=2 \
##     godot --path . --rendering-method gl_compatibility -s res://tools/gif_capture.gd
##
## Env:
##   SHOT_DIR     where to write (default /tmp). MUST EXIST — save_png fails silently into a
##                missing directory, so `mkdir -p` it first.
##   GIF_CHAPTER  1..6 -> main.start_arcade(N) -> SimWorld.jump_to_chapter: start at that zone's
##                mouth instead of grinding from gate 1. This is what makes four clips show four
##                LEVELS rather than four takes of sector 1.
##   GIF_MODE     "endless" -> start_game(true). Ignored when GIF_CHAPTER is set.
##   GIF_SKIP     frames to run before capturing, so the clip opens mid-firefight and not on a
##                spawn. Too small and you capture a soldier walking: 120 measured score=0.
##   GIF_FRAMES   frames to run while capturing.  GIF_EVERY  capture every Nth (2 = 30fps).
##
## ⚠️ NEEDS A GL CONTEXT. No --headless, or every frame is black.
##
## ⚠️ THIS DELIBERATELY DOES NOT SET god_mode, and you must not add it back. god_mode keeps a run
## from ending — tempting for a capture — but it also stamps "GOD MODE — DEBUG ONLY — RUN CANNOT
## END" across its own HUD band row, unmissable by construction (main.gd::_draw_god_badge). That is
## correct design and cost four unusable takes before anyone looked at the pixels. start_arcade()
## already puts the bot at the zone, so it only has to survive the clip itself.
##
## ⚠️ CAPTURING ≠ CAPTURING SOMETHING. Two failure modes that both write files and exit 0:
##   - the player DIED and the clip is a rally screen (tell: the .gif is ~10x smaller than its
##     siblings, and the HUD reads 0 PTS / RALLYING);
##   - in ENDLESS the camera is pinned (_step_camera never runs), so frame-to-frame delta stays
##     near zero even during real combat, and captures keep landing in the SHOP intermission.
## Capture a LONG window and select the liveliest 40-48 frame slice by counting ACTIVE frames
## (neighbour luma delta above a threshold) rather than by mean delta. And note the AAA loop's
## verify_shots.py gate is calibrated for 1fps sampling: at GIF_EVERY=2 it reports a healthy
## capture as "idle". Measure over a ~0.5s stride instead.
var main: Node2D
var out_dir := "/tmp"
var skip := 240
var total := 180
var every := 2
var shot := 0

func _env_i(k: String, d: int) -> int:
	var v := OS.get_environment(k)
	return int(v) if v.is_valid_int() else d

func _initialize() -> void:
	out_dir = OS.get_environment("SHOT_DIR")
	if out_dir.is_empty():
		out_dir = "/tmp"
	skip = _env_i("GIF_SKIP", 240)
	total = _env_i("GIF_FRAMES", 180)
	every = maxi(1, _env_i("GIF_EVERY", 2))
	main = (load("res://src/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	main.no_autopause = true   # the harness window never holds focus; without this every frame pauses
	_run()

func _kill_splash() -> void:
	## The boot splash paints the whole frame for its first seconds and would eat the opening shots.
	if main == null:
		return
	main._splash_t = 0.0
	if main._splash_layer != null:
		main._splash_layer.visible = false

func _run() -> void:
	await RenderingServer.frame_post_draw
	_kill_splash()
	var chapter := _env_i("GIF_CHAPTER", 0)
	if chapter > 0:
		main.start_arcade(chapter)
	else:
		main.start_game(OS.get_environment("GIF_MODE") == "endless")
	main.demo_autoplay = true   # scripted bot: marches north, fires, grenades, boards tanks
	var f := 0
	while f < skip:
		await RenderingServer.frame_post_draw
		_kill_splash()
		f += 1
	var frame := 0
	while frame < total:
		await RenderingServer.frame_post_draw
		frame += 1
		_kill_splash()
		if frame % every == 0:
			var img := root.get_texture().get_image()
			shot += 1
			if img.save_png("%s/f%04d.png" % [out_dir, shot]) != OK:
				push_error("gif_capture: save_png failed — does SHOT_DIR exist?")
				quit(1)
				return
	print("CAPTURED %d frames  sector_gate=%d  score=%d  wiped=%s"
		% [shot, main.sim._gate_counter, main.sim.score, main.sim.wiped])
	quit(0)
