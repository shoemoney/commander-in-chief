extends SceneTree
## Screenshot harness: stages signature game moments as hand-authored sim
## states and captures them through the real view (src/main.gd rendering).
## Run under X (or Xvfb):
##   SHOT_DIR=/abs/path godot --path . --rendering-method gl_compatibility \
##       -s res://tools/screenshots.gd
## Dev tool only — never shipped; not part of the deterministic sim.

const F := Fixed.ONE

var main: Node2D
var shots: Array[Dictionary] = []
var current := -1
var wait := 0
var out_dir := "/tmp"


func _initialize() -> void:
	out_dir = OS.get_environment("SHOT_DIR")
	if out_dir.is_empty():
		out_dir = "/tmp"
	main = (load("res://src/main.tscn") as PackedScene).instantiate()
	root.add_child(main)
	# We pose states; nothing may simulate. PROCESS_MODE_DISABLED freezes
	# _physics_process for main AND children (set_physics_process(false)
	# alone still let a few ticks through — staged sims drifted).
	main.process_mode = Node.PROCESS_MODE_DISABLED
	main._menu.mode = GameMenu.Mode.HIDDEN   # staged shots show gameplay, not the title
	main.no_autopause = true   # harness window never holds focus; don't pause-overlay every shot
	# SHOT_PAD=xbox|ps|switch forces the pad-glyph path for prompt verification —
	# the harness has no gamepad, so brand glyphs otherwise never render in shots.
	var pad := OS.get_environment("SHOT_PAD")
	if not pad.is_empty():
		Art.use_pad = true
		Art.pad_brand = pad
	_build_shots()
	process_frame.connect(_on_frame)
	# First _advance happens on the first frame — after main._ready() has run
	# (its _reset() would otherwise clobber the first staged sim).


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
		img.save_png(path)
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
	# Feel decay never runs while posing — scrub prior dress state so one
	# shot's garnish can't leak into the next.
	main._fx.clear()
	main._damage_vignette = 0.0
	main._banners.clear()
	# Mutate in place: cross-script assignment of a fresh Array into the
	# typed Array[...] properties fails at runtime.
	for k in main._recoil.size():
		main._recoil[k] = Vector2.ZERO
	for w in main._wheel:
		w["open"] = false
		w["sel"] = -1
	if shots[current].has("dress"):
		shots[current]["dress"].call(main)   # view-layer garnish (fx, recoil)
	main._update_hud()
	# Force the retained grass/dirt base to repaint for THIS pose with the FULL
	# posed-sector palette. _paint_bg skips the rebuild when (camera_top, march) is
	# unchanged, AND freezes a per-row palette south of _litter_cam_snap (so a live
	# march sweeps in gradually during play). Under instant posing that seam leaves
	# the visible field on the PRIOR shot's palette. Pre-sync _bg_march so _draw's
	# transition-reset is skipped, invalidate _bg_cam to force the repaint, and clear
	# the freeze snap so every visible row uses the posed sector march.
	main._bg_march = main._sector_march()
	main._bg_cam = -2147483647
	main._litter_cam_snap = 9223372036854775807
	main.queue_redraw()
	wait = 6


func _cam(sim: SimWorld, offset_px: int) -> int:
	return sim.camera_top + offset_px * F


# --- Scenario builders: pure state posing, no stepping ---

func _build_shots() -> void:
	shots = [
		{"name": "jungle-firefight", "build": _shot_firefight, "dress": _dress_firefight},
		{"name": "tank-assault", "build": _shot_tank},
		{"name": "river-crossing", "build": _shot_river},
		{"name": "bridge-gunship", "build": _shot_gunship},
		{"name": "foundry-colossus-last-stand", "build": _shot_colossus, "dress": _dress_colossus},
		{"name": "victoly", "build": _shot_victoly},
		{"name": "endless-war-shop", "build": _shot_shop, "dress": _dress_shop},
		{"name": "title-screen", "build": _shot_firefight, "dress": _dress_title},
		{"name": "pause-menu", "build": _shot_firefight, "dress": _dress_pause},
		{"name": "how-to-play", "build": _shot_firefight, "dress": _dress_howto},
		{"name": "hall-of-fame", "build": _shot_firefight, "dress": _dress_hall},
	]


func _shot_firefight() -> SimWorld:
	var sim := SimWorld.new(7, 1)
	var p := sim.players[0]
	p["x"] = 300 * F
	p["y"] = _cam(sim, 270)
	p["aim_x"] = 0
	p["aim_y"] = -F
	p["mg_ammo"] = 64
	p["grenade_ammo"] = 9
	sim.war_chest = 185
	sim.score = 12760
	for e in [[210, 90, false], [270, 60, false], [350, 75, true], [430, 110, false], [160, 140, false], [490, 55, false]]:
		sim._spawn_enemy(e[0] * F, _cam(sim, e[1]), e[2])
	sim.bunkers.append({"x": 60 * F, "y": _cam(sim, 40), "alive": true, "spawn_cd": 60})
	for i in 4:
		sim.bullets.append({"x": (296 + i * 3) * F, "y": _cam(sim, 220 - i * 38),
			"vx": 0, "vy": -6 * F, "ttl": 60, "owner": 0})
	sim.grenades.append({"x": 340 * F, "y": _cam(sim, 160), "vx": F, "vy": -3 * F,
		"z": 14 * F, "zv": F / 2, "owner": 0, "shell": false})
	sim.pickups.append({"x": 380 * F, "y": _cam(sim, 240), "kind": 0})
	sim.pickups.append({"x": 150 * F, "y": _cam(sim, 200), "kind": 1})
	return sim


func _dress_firefight(m: Node2D) -> void:
	# Mid-burst garnish: muzzle flash at the gun tip, casings, recoil kick.
	var sim: SimWorld = m.sim
	var p := sim.players[0]
	m._fx.append({"x": p["x"], "y": p["y"] - 13 * F, "t": 0.05, "kind": "muzzle",
		"rate": 0.34, "a": -PI / 2})
	m._recoil[0] = Vector2(0, 2.2)
	for i in 3:
		m._fx.append({"x": p["x"] + (6 + i * 5) * F, "y": p["y"] + (2 + i) * F,
			"t": 0.15 + i * 0.22, "kind": "casing", "rate": 0.055,
			"vx": 1.5, "vy": 0.3, "spin": i * 2.1})


func _shot_tank() -> SimWorld:
	var sim := SimWorld.new(7, 1)
	var p := sim.players[0]
	var tank := {"x": 320 * F, "y": _cam(sim, 250), "alive": true, "burning": false,
		"fuel": 840, "burn_ticks": 0, "fire_cd": 0, "occupant": 0}
	sim.tanks.append(tank)
	p["in_tank"] = 0
	p["x"] = tank["x"]
	p["y"] = tank["y"]
	p["aim_x"] = 0
	p["aim_y"] = -F
	p["grenade_ammo"] = 7
	sim.war_chest = 310
	sim.score = 28450
	for e in [[250, 120, false], [300, 80, false], [370, 100, true], [420, 140, false], [200, 60, false]]:
		sim._spawn_enemy(e[0] * F, _cam(sim, e[1]), e[2])
	sim.grenades.append({"x": 330 * F, "y": _cam(sim, 150), "vx": 0, "vy": -5 * F,
		"z": 10 * F, "zv": F / 2, "owner": 0, "shell": true})
	sim.bunkers.append({"x": 470 * F, "y": _cam(sim, 30), "alive": true, "spawn_cd": 60})
	return sim


func _shot_river() -> SimWorld:
	var sim := SimWorld.new(7, 2)
	var w := {"y": _cam(sim, 120), "ford_x": 430 * F}
	sim.waters.append(w)
	var p := sim.players[0]
	p["x"] = 250 * F
	p["y"] = _cam(sim, 160)   # mid-river, wading
	p["aim_x"] = -F
	p["aim_y"] = 0
	var p2 := sim.players[1]
	p2["x"] = 430 * F
	p2["y"] = _cam(sim, 250)  # heading for the ford
	p2["aim_x"] = 0
	p2["aim_y"] = -F
	sim.war_chest = 95
	sim.score = 41200
	sim._spawn_frogman(180 * F, _cam(sim, 150))
	sim._spawn_frogman(320 * F, _cam(sim, 175))
	sim._spawn_frogman(140 * F, _cam(sim, 135))
	var lunger := sim.enemies[1]
	lunger["submerged"] = false
	lunger["lunge_ticks"] = 30
	# Third frogman caught mid-surface: the new telegraph ripple burst.
	var surfacing := sim.enemies[2]
	surfacing["submerged"] = false
	surfacing["surface_ticks"] = 12
	sim.grenades.append({"x": 200 * F, "y": _cam(sim, 145), "vx": -F, "vy": -2 * F,
		"z": 12 * F, "zv": F / 4, "owner": 0, "shell": false})
	sim._spawn_enemy(520 * F, _cam(sim, 60), false)
	sim._spawn_enemy(560 * F, _cam(sim, 90), false)
	return sim


func _shot_gunship() -> SimWorld:
	var sim := SimWorld.new(7, 2)
	var gy := _cam(sim, 90)
	var gate := {"y": gy, "open": false, "b1": {}, "b2": {}, "final": false,
		"boss": {"alive": true, "hp": 23, "x": 360 * F, "dir": 1, "phase_t": 210, "gate_y": gy}}
	sim.gates.append(gate)
	var p := sim.players[0]
	p["x"] = 260 * F
	p["y"] = _cam(sim, 290)
	p["aim_x"] = F / 2
	p["aim_y"] = -F
	p["roll_ticks"] = 9   # mid-roll shimmer
	var p2 := sim.players[1]
	p2["x"] = 420 * F
	p2["y"] = _cam(sim, 310)
	p2["aim_x"] = 0
	p2["aim_y"] = -F
	sim.war_chest = 240
	sim.score = 67300
	for i in 5:
		sim.enemy_bullets.append({"x": (330 + i * 22) * F, "y": _cam(sim, 120 + i * 34),
			"vx": (i - 2) * F / 3, "vy": 3 * F, "ttl": 90})
	for i in 3:
		sim.bullets.append({"x": (270 + i * 8) * F, "y": _cam(sim, 240 - i * 45),
			"vx": F, "vy": -5 * F, "ttl": 60, "owner": 0})
	sim.strikes.append({"x": 430 * F, "y": _cam(sim, 300), "ticks": 25})
	return sim


func _shot_colossus() -> SimWorld:
	var sim := SimWorld.new(7, 1)
	var gy := _cam(sim, 30)
	# Four opened gates behind us: _sector_march() = 0.8 -> band-4 foundry
	# ground/litter/dressing (c2: the finale must LOOK like the foundry, not
	# "a big enemy in a green field" — which this pose used to stage).
	for og in 4:
		sim.gates.append({"y": gy + (og + 1) * 1000 * F, "open": true, "b1": {}, "b2": {}, "boss": {}})
	sim.gates.append({"y": gy, "open": false, "b1": {}, "b2": {}, "boss": {}, "final": true})
	sim.colossus = {"alive": true, "hp": 14, "x": 320 * F, "y": _cam(sim, 110),
		"spray_cd": 10, "volley_cd": 40, "spawn_cd": 20}
	sim.last_stand = true
	sim.war_chest = 430
	sim.score = 152800
	var p := sim.players[0]
	p["x"] = 300 * F
	p["y"] = _cam(sim, 300)
	p["aim_x"] = 0
	p["aim_y"] = -F
	p["grenade_ammo"] = 5
	for i in 6:
		sim.enemy_bullets.append({"x": (250 + i * 28) * F, "y": _cam(sim, 150 + (i % 3) * 40),
			"vx": (i - 3) * F / 4, "vy": 3 * F, "ttl": 90})
	sim.strikes.append({"x": 290 * F, "y": _cam(sim, 290), "ticks": 30})
	sim.strikes.append({"x": 360 * F, "y": _cam(sim, 310), "ticks": 12})
	sim._spawn_enemy(280 * F, _cam(sim, 140), false)
	sim._spawn_enemy(360 * F, _cam(sim, 150), false)
	sim.pickups.append({"x": 160 * F, "y": _cam(sim, 260), "kind": 1})
	sim.grenades.append({"x": 320 * F, "y": _cam(sim, 180), "vx": 0, "vy": -3 * F,
		"z": 16 * F, "zv": F / 3, "owner": 0, "shell": false})
	return sim


func _shot_victoly() -> SimWorld:
	var sim := SimWorld.new(7, 2)
	sim.victory = true
	sim.last_stand = true
	sim.war_chest = 0
	sim.score = 264500
	var p := sim.players[0]
	p["x"] = 290 * F
	p["y"] = _cam(sim, 260)
	var p2 := sim.players[1]
	p2["x"] = 350 * F
	p2["y"] = _cam(sim, 265)
	sim.gates.append({"y": _cam(sim, 60), "open": true, "b1": {}, "b2": {}, "boss": {}, "final": true})
	return sim


func _shot_shop() -> SimWorld:
	var sim := SimWorld.new(7, 2, "endless")
	sim.wave = 6
	sim.intermission_ticks = 240
	sim.war_chest = 175
	sim.score = 88900
	var shop_y := _cam(sim, 120)
	sim.pickups.append({"x": 200 * F, "y": shop_y, "kind": 0, "cost": SimWorld.SHOP_AMMO_COST})
	sim.pickups.append({"x": 320 * F, "y": shop_y, "kind": 2, "cost": SimWorld.SHOP_VEST_COST})
	sim.pickups.append({"x": 440 * F, "y": shop_y, "kind": 3, "cost": SimWorld.SHOP_AIRSTRIKE_COST})
	var p := sim.players[0]
	p["x"] = 290 * F
	p["y"] = _cam(sim, 200)
	p["vest"] = true
	var p2 := sim.players[1]
	p2["x"] = 440 * F
	p2["y"] = _cam(sim, 160)
	p2["aim_x"] = F
	p2["aim_y"] = 0
	return sim


func _dress_shop(m: Node2D) -> void:
	# P1 mid-decision on the spend-wheel, grenades highlighted.
	m._wheel[0] = {"open": true, "sel": 3}
	m._show_banner("WAVE CLEARED — SHOP OPEN")


func _dress_colossus(m: Node2D) -> void:
	# Vest just broke: damage vignette mid-pulse.
	m._damage_vignette = 0.55
	# Pre-align the bg march so the first-frame step doesn't freeze on-screen
	# litter at march 0 (staged sims are BORN deep — there was no journey),
	# and poke the camera sentinel so the retained ground canvas REPAINTS at
	# the staged march instead of keeping main._ready's jungle paint.
	m._bg_march = m._sector_march()
	m._bg_cam = 1 << 60


func _dress_title(m: Node2D) -> void:
	m._menu.open(GameMenu.Mode.TITLE)
	m._hud_icons.visible = false


func _dress_pause(m: Node2D) -> void:
	m._menu.open(GameMenu.Mode.PAUSE)
	m._menu.sel = 4   # RESTART highlighted


func _dress_howto(m: Node2D) -> void:
	m._menu.open(GameMenu.Mode.HOWTO)
	m._hud_icons.visible = false


func _dress_hall(m: Node2D) -> void:
	# main.gd's `hall` is typed Array[Dictionary]; assign() converts the untyped
	# literal (a bare `=` throws "Invalid assignment ... value of type 'Array'").
	m.hall.assign([
		{"score": 264500, "mode": "campaign", "wave": 0, "sector": 5, "dist": 512, "streak": 14, "won": true},
		{"score": 88900, "mode": "endless", "wave": 12, "sector": 1, "dist": 40, "streak": 9, "won": false},
		{"score": 41200, "mode": "campaign", "wave": 0, "sector": 3, "dist": 210, "streak": 6, "won": false},
	])
	m._menu.open(GameMenu.Mode.HALL)
	m._hud_icons.visible = false
