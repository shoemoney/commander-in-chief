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

var main: Node2D
var shots: Array[Dictionary] = []
var current := -1
var wait := 0
var out_dir := "/tmp"
var expect_w := 640   # overwritten below from the project's actual viewport size
var expect_h := 360


func _initialize() -> void:
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
	main.process_mode = Node.PROCESS_MODE_DISABLED   # pose states only, never step (see screenshots.gd)
	main._menu.mode = GameMenu.Mode.HIDDEN
	main.no_autopause = true
	_build_shots()
	process_frame.connect(_on_frame)


func _on_frame() -> void:
	if current == -1:
		_advance()
		return
	if current >= shots.size():
		return
	wait -= 1
	if wait == 2:
		main.queue_redraw()
	if wait <= 0:
		var img := root.get_texture().get_image()
		var path := "%s/%02d-%s.png" % [out_dir, current + 1, shots[current]["name"]]
		# save_png returning OK only means the write succeeded, not that the
		# viewport actually rendered — a dummy/headless driver can hand back a
		# null texture (no GL context) or a valid-looking blank/wrong-size
		# frame. Catch both here so a bad capture fails loud instead of
		# quietly reaching the downstream asset-review pass.
		if img == null:
			push_error("biome_capture: get_image() returned null (no renderable viewport) for %s" % path)
			quit(1)
			return
		if img.get_width() != expect_w or img.get_height() != expect_h or img.is_empty():
			push_error("biome_capture: captured frame is %dx%d (expected %dx%d) for %s" %
				[img.get_width(), img.get_height(), expect_w, expect_h, path])
			quit(1)
			return
		var err := img.save_png(path)
		if err != OK:
			# Fatal, not skip-and-continue: a hole in the tour silently starves
			# the downstream asset-review/winner-picking pass of that biome.
			push_error("biome_capture: save_png failed (%d) for %s" % [err, path])
			quit(1)
			return
		print("SAVED ", path)
		_advance()


func _advance() -> void:
	current += 1
	if current >= shots.size():
		print("ALL SHOTS DONE")
		quit(0)
		return
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
	# matching note in screenshots.gd::_advance — the same seam bites here).
	main._bg_march = main._sector_march()
	main._bg_cam = -2147483647
	main._litter_cam_snap = 9223372036854775807
	# _update_hud() must run AFTER the ground-canvas invalidation above: HUD
	# elements keyed on the current march (e.g. sector name/progress) need to
	# read the just-set _bg_march, not the previous shot's stale value.
	main._update_hud()
	main.queue_redraw()
	wait = 6


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
