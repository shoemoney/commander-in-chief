extends SceneTree
## Biome/visual-tour harness: sweeps the campaign sector march (jungle ->
## scorched -> marsh -> ruins -> foundry, via opened-gate count) plus an
## endless-mode wave state, posing water banks, cover-rock kinds, and a
## mid-jet foundry vent so asset review sees ground-stop modulation, bank
## tints, and vent-burn feedback in their real gameplay context — not just
## the hand-authored combat beats screenshots.gd already covers.
## Run under X (or Xvfb):
##   SHOT_DIR=/abs/path godot --path . --rendering-method gl_compatibility \
##       -s res://tools/biome_capture.gd
## Dev tool only — never shipped; not part of the deterministic sim.

const F := Fixed.ONE
const Shots := preload("res://tools/screenshots.gd")   # shared capture-liveness gate

var main: Node2D
var _digests := {}   # md5 -> path, so two biomes can never be the same picture
var shots: Array[Dictionary] = []
var current := -1
const WARMUP_FRAMES := 6   # main must render live at least once before it is frozen
const SETTLE_FRAMES := 12  # rendered frames between posing a shot and grabbing the pixels
var out_dir := "/tmp"
var expect_w := 640   # overwritten below from the project's actual viewport size
var expect_h := 360


func _initialize() -> void:
	# --headless is a dummy renderer: frame_post_draw never fires, so the capture
	# loop below would hang forever instead of failing. Say why, up front.
	if DisplayServer.get_name() == "headless":
		push_error("biome_capture: --headless has no framebuffer — run under a GL context (X/Xvfb), e.g. --rendering-method gl_compatibility")
		print("SHOTS UNUSABLE — headless has no framebuffer; nothing was captured")
		quit(1)
		return
	# Read the real viewport size instead of hardcoding 640x360, so this guard
	# doesn't false-fail (or worse, silently pass a wrong-size frame) if
	# display/window/size/viewport_* ever changes in project.godot.
	expect_w = ProjectSettings.get_setting("display/window/size/viewport_width", expect_w)
	expect_h = ProjectSettings.get_setting("display/window/size/viewport_height", expect_h)
	out_dir = OS.get_environment("SHOT_DIR")
	if out_dir.is_empty():
		out_dir = "/tmp"
	var mkerr := DirAccess.make_dir_recursive_absolute(out_dir)   # SHOT_DIR may not exist yet
	if mkerr != OK and mkerr != ERR_ALREADY_EXISTS:
		push_error("biome_capture: couldn't create SHOT_DIR %s (%d)" % [out_dir, mkerr])
		quit(1)
		return
	main = (load("res://src/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	main._menu.mode = GameMenu.Mode.HIDDEN
	main.no_autopause = true
	_build_shots()
	_run()


func _run() -> void:
	## ONE linear coroutine, matching screenshots.gd. The old process_frame handler
	## + `wait` counter froze main with PROCESS_MODE_DISABLED, which also suppresses
	## CanvasItem redraws AND freezes the node before it has drawn once — so this
	## harness was writing solid 1-colour PNGs and printing SAVED for every one of
	## them. The liveness gate below is what finally caught it.
	for _i in WARMUP_FRAMES:
		await RenderingServer.frame_post_draw
	Shots._kill_splash(main)      # opaque intro cinematic would cover every shot
	Shots._freeze_physics(main)   # stop sim.step() WITHOUT stopping _draw
	var failures := 0
	for i in shots.size():
		current = i
		_pose()
		for _s in SETTLE_FRAMES:
			Shots._redraw_all(main)   # bg root, HUD and menu are separate CanvasItems
			await RenderingServer.frame_post_draw
		# frame_post_draw is the ONLY point where the viewport texture holds real pixels.
		var img := root.get_texture().get_image()
		var path := "%s/%02d-%s.png" % [out_dir, i + 1, shots[i]["name"]]
		if img == null or img.is_empty():
			push_error("biome_capture: viewport handed back no image for %s" % path)
			print("FAILED ", path, " — no framebuffer")
			failures += 1
			continue
		if img.get_width() != expect_w or img.get_height() != expect_h:
			push_error("biome_capture: captured frame is %dx%d (expected %dx%d) for %s" %
				[img.get_width(), img.get_height(), expect_w, expect_h, path])
			print("FAILED ", path, " — wrong size")
			failures += 1
			continue
		var err := img.save_png(path)
		if err != OK:
			push_error("biome_capture: save_png failed (%d) for %s" % [err, path])
			print("FAILED ", path)
			failures += 1
			continue
		# Written to disk even when dead: a human needs to SEE the garbage. It just
		# never gets to call itself SAVED.
		var st := Shots.frame_stats(img)
		if not Shots._frame_is_live(img):
			push_error("biome_capture: %s carries no picture (%d distinct colours, luma stddev %.2f) — the pose never reached the viewport" % [path, st["colors"], st["stddev"]])
			print("FAILED %s — dead frame (colors=%d stddev=%.2f)" % [path, st["colors"], st["stddev"]])
			failures += 1
			continue
		var digest := FileAccess.get_md5(path)
		if _digests.has(digest):
			push_error("biome_capture: %s is byte-identical to %s — the pose never reached the viewport" % [path, _digests[digest]])
			print("FAILED %s — identical to %s" % [path, _digests[digest]])
			failures += 1
			continue
		_digests[digest] = path
		print("SAVED %s (colors=%d stddev=%.2f)" % [path, st["colors"], st["stddev"]])
	if failures > 0:
		push_error("biome_capture: %d of %d shots are unusable — refusing to report success" % [failures, shots.size()])
		print("SHOTS UNUSABLE — %d of %d failed; do not hand these to a reviewer" % [failures, shots.size()])
		quit(1)
		return
	print("ALL SHOTS DONE — %d live, %d unique" % [shots.size(), _digests.size()])
	quit(0)


func _pose() -> void:
	var sim: SimWorld = shots[current]["build"].call()
	main.sim = sim
	main._fx.clear()
	main._damage_vignette = 0.0
	main._banners.clear()
	# main._recoil is declared `Array[Vector2]` (per-player gun kick, see
	# src/main.gd) — a typed array, so an in-place Vector2.ZERO assign is safe.
	# Asserted here (not just commented) so a future refactor that swaps the
	# container shape can't silently leak recoil state between posed shots.
	assert(main._recoil is Array, "main._recoil is no longer an Array; update this reset")
	for k in main._recoil.size():
		main._recoil[k] = Vector2.ZERO
	for w in main._wheel:
		w["open"] = false
		w["sel"] = -1
	if shots[current].has("dress"):
		shots[current]["dress"].call(main)
	# Force the retained ground canvas to repaint at THIS shot's march (see the
	# matching note in screenshots.gd::_pose — the same seam bites here).
	main._bg_march = main._sector_march()
	main._bg_cam = -2147483647
	main._litter_cam_snap = 9223372036854775807
	# _update_hud() must run AFTER the ground-canvas invalidation above: HUD
	# elements keyed on the current march (e.g. sector name/progress) need to
	# read the just-set _bg_march, not the previous shot's stale value.
	Shots._kill_splash(main)   # re-assert: a pose must never surface the intro cinematic
	main._update_hud()
	main.queue_redraw()


func _cam(sim: SimWorld, offset_px: int) -> int:
	return sim.camera_top + offset_px * F


# --- Shot builders: gates-opened count drives _sector_march() deterministically
# (mopened / 5.0) so each shot lands on one of the five biome-ramp stops. ---

func _build_shots() -> void:
	shots = [
		{"name": "sector0-jungle-bank", "build": _shot_sector.bind(0)},
		{"name": "sector1-scorched-cover", "build": _shot_sector.bind(1)},
		{"name": "sector2-marsh-crossing", "build": _shot_sector.bind(2)},
		{"name": "sector3-ruins-cover", "build": _shot_sector.bind(3)},
		{"name": "sector4-foundry-vent-burn", "build": _shot_sector.bind(4), "dress": _dress_vent_jet},
		{"name": "endless-midwave", "build": _shot_endless},
	]


func _shot_sector(opened: int) -> SimWorld:
	var sim := SimWorld.new(7, 2)
	for og in opened:
		sim.gates.append({"y": _cam(sim, 500 + og * 400), "open": true, "b1": {}, "b2": {}, "boss": {}})
	var w := {"y": _cam(sim, 140), "ford_x": 340 * F}
	sim.waters.append(w)
	# One of each cover kind so grass(1)/wall(2)/hero-wreck(3)/stone(0) all read
	# at this march's palette in the same frame.
	sim.rocks.append({"x": 150 * F, "y": _cam(sim, 200), "kind": 0})
	sim.rocks.append({"x": 230 * F, "y": _cam(sim, 230), "kind": 1})
	sim.rocks.append({"x": 380 * F, "y": _cam(sim, 210), "kind": 2})
	sim.rocks.append({"x": 460 * F, "y": _cam(sim, 250), "kind": 3})
	var p := sim.players[0]
	p["x"] = 260 * F
	p["y"] = _cam(sim, 300)
	p["aim_x"] = 0
	p["aim_y"] = -F
	var p2 := sim.players[1]
	p2["x"] = 300 * F
	p2["y"] = _cam(sim, 260)
	sim.war_chest = 120
	sim.score = 20000 + opened * 15000
	sim._spawn_enemy(200 * F, _cam(sim, 90), false)
	sim._spawn_enemy(420 * F, _cam(sim, 110), opened >= 3)
	return sim


func _dress_vent_jet(m: Node2D) -> void:
	# Park tick_count on a mid-jet phase next to the grass(kind 1) cover so the
	# burn hazard is caught mid-feedback, not idle. main._draw_vents re-derives
	# the flame column with no vent-side state at all: ph = posmod(tick_count +
	# 7*(vent.x/F), CYCLE) (same formula the sim steps by). Solve tick_count so
	# THIS vent's x rolls that phase into the jet window at capture time.
	var sim: SimWorld = m.sim
	# Offset from the kind-1 grass rock (230,230) rather than sitting on top of
	# it — close enough (30px right, 20px up-screen) to read as "this vent
	# burns that clump" without the vent's own flame-column draw occluding the
	# cover it's meant to show off. Eyeball on a real-GL capture: the jet's
	# glow should visibly overlap the grass sprite's south edge, not float
	# clear of it.
	var vx := 260 * F
	sim.vents.append({"x": vx, "y": _cam(sim, 210)})
	var jet_at := SimWorld.VENT_CYCLE_TICKS - SimWorld.VENT_JET_TICKS
	sim.tick_count = jet_at + SimWorld.VENT_JET_TICKS / 2 - 7 * (vx / F)
	# Self-check: recompute the exact phase main._draw_vents will read, so a
	# future VENT_* constant change fails this assert instead of silently
	# posing an idle grate and calling it "vent-burn".
	var ph := posmod(sim.tick_count + 7 * (vx / F), SimWorld.VENT_CYCLE_TICKS)
	assert(ph >= jet_at and ph < SimWorld.VENT_CYCLE_TICKS,
		"vent phase solver landed outside the jet window: ph=%d jet_at=%d" % [ph, jet_at])


func _shot_endless() -> SimWorld:
	var sim := SimWorld.new(7, 2, "endless")
	sim.wave = 6   # march = wave/12 = 0.5, mid-ramp — distinct progression axis from campaign gates
	var w := {"y": _cam(sim, 130), "ford_x": 320 * F}
	sim.waters.append(w)
	sim.rocks.append({"x": 150 * F, "y": _cam(sim, 200), "kind": 0})
	sim.rocks.append({"x": 200 * F, "y": _cam(sim, 190), "kind": 1})
	sim.rocks.append({"x": 400 * F, "y": _cam(sim, 220), "kind": 2})
	sim.rocks.append({"x": 460 * F, "y": _cam(sim, 250), "kind": 3})
	var p := sim.players[0]
	p["x"] = 280 * F
	p["y"] = _cam(sim, 260)
	p["aim_x"] = 0
	p["aim_y"] = -F
	var p2 := sim.players[1]
	p2["x"] = 340 * F
	p2["y"] = _cam(sim, 240)
	sim.war_chest = 260
	sim.score = 71000
	sim._spawn_enemy(230 * F, _cam(sim, 100), false)
	sim._spawn_enemy(380 * F, _cam(sim, 130), true)
	return sim
