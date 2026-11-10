extends "res://tools/capture_completion_presentation.gd"

const F := Fixed.ONE
const PALETTES := ["jungle", "scorched", "marsh", "ruins", "foundry"]
var stage: Dictionary = {}
var pose_checksum := 0


func _build_cases() -> void:
	for scale in [1.0, 2.0]:
		for sector in 5:
			for heavy in [false, true]:
				_add("sector-%d-%s-%s" % [sector + 1, PALETTES[sector], "explosions" if heavy else "combat"],
					"combat", scale, {"sector": sector, "heavy": heavy})
		for phase in [-105, 60, 170]:
			var label := "inbound" if phase < 0 else ("strafe" if phase < SimWorld.BOSS_STRAFE_TICKS else "mortar")
			_add("gunship-" + label, "gunship", scale, {"phase": phase,
				"expected": "INBOUND" if phase < 0 else ("STRAFING RUN" if phase < SimWorld.BOSS_STRAFE_TICKS else "MORTAR VOLLEY")})
		for phase in [1, 2, 3]:
			for core in [0, 30]:
				_add("colossus-phase-%d-core-%s" % [phase, "sealed" if core == 0 else "exposed"],
					"colossus", scale, {"phase": phase, "core": core,
					"expected": ["ADVANCE", "MORTAR VOLLEYS", "TROOP DROPS"][phase - 1]})
		_add("coop-dense-world-labels", "labels", scale)


func _pose(spec: Dictionary) -> void:
	super._pose(spec)
	main._menu.mode = GameMenu.Mode.HIDDEN
	main._hud_icons.visible = true
	main._motion = 1.0
	main._fx.clear()
	main._scorch.clear()
	main._corpses.clear()
	main._forks.clear()
	main._fork_sign_fade.clear()
	main._boss_hpmax.clear()
	main._enemy_flash.clear()
	main._enemy_face.clear()
	main._seen_kinds.clear()
	main._player_motion.clear()
	main._enemy_pos_prev.clear()
	main._damage_vignette = 0.0
	main._flash_alpha = 0.0
	main._boss_flash = 0.0
	main._hitstop_frames = 0
	for i in main._recoil.size():
		main._recoil[i] = Vector2.ZERO
	var sector := int(spec.get("sector", 2 if spec["kind"] == "gunship" else 5))
	main.sim = _field(sector, spec["kind"] == "combat")
	if spec["kind"] == "combat" and sector in [1, 3]:
		main._forks.append({"x": (260 if sector == 1 else 380) * F,
			"y": main.sim.camera_top + (130 - int(main.fork_sign_row())) * F})
	for i in main.sim.players.size():
		main._player_face[i] = main._aim_angle(main.sim.players[i])
		main._dust_prev[i] = Vector2i(main.sim.players[i]["x"], main.sim.players[i]["y"])
	if spec["kind"] == "gunship":
		_pose_gunship(int(spec["phase"]))
	elif spec["kind"] == "colossus":
		_pose_colossus(int(spec["phase"]), int(spec["core"]))
	elif spec["kind"] == "labels":
		_pose_labels()
	if bool(spec.get("heavy", false)) or spec["kind"] in ["gunship", "colossus", "labels"]:
		_dress_explosions()
	main._hud_icons._disp_chest = float(main.sim.war_chest)
	main._hud_icons._disp_score = float(main.sim.score)
	main._hud_icons.verb_begin_run(main.sim.get_instance_id(), "keyboard", {})
	main._bg_march = main._sector_march()
	main._bg_cam = -2147483647
	main._litter_cam_snap = 9223372036854775807
	main._update_hud()
	main._hud_icons._dirty = true
	pose_checksum = main.sim.checksum()
	stage = {"explicitly_staged": true, "not_gameplay_or_store_evidence": true,
		"seed": 7, "tick": main.sim.tick_count, "sector_index": sector,
		"authored_zone": SimWorld.ZONE_INFO[sector]["name"],
		"ground_march": main._sector_march(), "players": main.sim.players.duplicate(true),
		"enemies": main.sim.enemies.duplicate(true), "friendly_bullets": main.sim.bullets.duplicate(true),
		"enemy_bullets": main.sim.enemy_bullets.duplicate(true), "grenades": main.sim.grenades.duplicate(true),
		"pickups": main.sim.pickups.duplicate(true), "gates": main.sim.gates.duplicate(true),
		"tanks": main.sim.tanks.duplicate(true), "bunkers": main.sim.bunkers.duplicate(true),
		"barrels": main.sim.barrels.duplicate(true), "mines": main.sim.mines.duplicate(true),
		"colossus": main.sim.colossus.duplicate(true), "endless_boss": main.sim.endless_boss.duplicate(true),
		"waters": main.sim.waters.duplicate(true), "strikes": main.sim.strikes.duplicate(true),
		"rocks": main.sim.rocks.duplicate(true), "vents": main.sim.vents.duplicate(true),
		"view_route_forks": main._forks.duplicate(true),
		"last_stand": main.sim.last_stand, "text_percent": main._text_scale,
		"motion": main._motion, "colorblind": main.colorblind, "physics_and_view_process_frozen": true,
		"first_encounter_memory_reset_per_case": true,
		"fx_kinds": [], "checksum_before_render": pose_checksum}
	for fx in main._fx:
		stage["fx_kinds"].append({"kind": fx["kind"], "x": fx["x"], "y": fx["y"],
			"age": fx["t"], "text": fx.get("text", "")})
	var expected_march := 1.0 if spec["kind"] in ["colossus", "labels"] else float(sector) / 5.0
	if spec["kind"] == "gunship" and int(spec["phase"]) < 0:
		expected_march = float(main.sim.wave) / 12.0
	if absf(main._sector_march() - expected_march) > 0.0001:
		_fail(spec, "The staged sector did not select the intended ground palette.")
	if spec["kind"] == "colossus" and main.sim.colossus_phase() != int(spec["phase"]):
		_fail(spec, "The posed HP did not select the intended Colossus phase.")


func _field(sector: int, with_gate: bool) -> SimWorld:
	var sw := SimWorld.new(7, 2, "campaign")
	sw.tick_count = 120 + sector * 31
	sw.camera_top = -2000 * F
	sw._gate_counter = sector + 1
	sw.rocks.clear()
	sw.tanks.clear()
	sw.pickups.clear()
	sw.war_chest = 250
	sw.score = 12500 + sector * 10000
	for i in sector:
		sw.gates.append({"y": sw.camera_top + (500 + i * 400) * F, "open": true, "b1": {}, "b2": {}, "boss": {}})
	if with_gate:
		var left := {"x": 60 * F, "y": sw.camera_top + 35 * F, "alive": true, "spawn_cd": 60}
		var right := {"x": 530 * F, "y": sw.camera_top + 35 * F, "alive": true, "spawn_cd": 60}
		sw.bunkers.append(left)
		sw.bunkers.append(right)
		sw.gates.append({"y": sw.camera_top + 75 * F, "open": false, "b1": left,
			"b2": right, "boss": {}, "final": false})
	for i in 2:
		var p: Dictionary = sw.players[i]
		p["x"] = (280 + i * 90) * F
		p["y"] = sw.camera_top + (280 + i * 18) * F
		p["aim_x"] = 0
		p["aim_y"] = -F
		p["mg_ammo"] = 64
		p["grenade_ammo"] = 9
		if i == 1:
			p["pierce_ticks"] = 600
	sw._spawn_enemy(180 * F, sw.camera_top + 135 * F, false)
	sw._spawn_enemy(450 * F, sw.camera_top + 135 * F, true)
	var roster: Array = SimWorld.SECTOR_SPECIALS[sector]
	for i in roster.size():
		var x := (225 + i * 90) * F
		var y := sw.camera_top + (185 + (i % 2) * 28) * F
		var kind := str(roster[i])
		if kind == "mg_nest":
			sw._spawn_mg_nest(x, y)
		elif kind == "broadcast":
			sw._spawn_broadcast(x, y)
		else:
			sw._spawn_special(x, y, kind)
		if kind == "ghillie":
			sw.enemies[-1]["submerged"] = false
			sw.enemies[-1]["surface_ticks"] = 12
	for e in sw.enemies:
		e["windup"] = 12
		e["aim_lx"] = 0
		e["aim_ly"] = 120 * F
	sw.waters.append({"y": sw.camera_top + 90 * F, "ford_x": 340 * F})
	if sector == 1:
		sw._spawn_frogman(260 * F, sw.camera_top + 92 * F)
		sw.enemies[-1]["submerged"] = false
		sw.enemies[-1]["surface_ticks"] = 12
	for i in 4:
		sw.rocks.append({"x": (120 + i * 125) * F, "y": sw.camera_top + (220 + (i % 2) * 18) * F, "kind": i})
	if sector >= 3:
		var vx := 500 * F
		sw.vents.append({"x": vx, "y": sw.camera_top + 290 * F})
		sw.tick_count = posmod(SimWorld.VENT_CYCLE_TICKS - SimWorld.VENT_JET_TICKS / 2
			- 7 * (vx / F), SimWorld.VENT_CYCLE_TICKS) + SimWorld.VENT_CYCLE_TICKS * 20
	sw.tanks.append({"x": 140 * F, "y": sw.camera_top + 285 * F, "alive": true,
		"burning": false, "fuel": 840, "burn_ticks": 0, "fire_cd": 0, "occupant": -1})
	for i in 4:
		sw.bullets.append({"x": (280 + (i % 2) * 90) * F, "y": sw.camera_top + (230 - i * 22) * F,
			"vx": 0, "vy": -6 * F, "ttl": 60, "owner": i % 2})
		sw.enemy_bullets.append({"x": (185 + i * 77) * F, "y": sw.camera_top + (175 + i * 16) * F,
			"vx": F / 3, "vy": 3 * F, "ttl": 90})
	for shell in [false, true]:
		sw.grenades.append({"x": (320 if shell else 250) * F, "y": sw.camera_top + 155 * F,
			"vx": 0, "vy": -3 * F, "z": 16 * F, "zv": F / 3, "owner": 0, "shell": shell})
	sw.strikes.append({"x": 410 * F, "y": sw.camera_top + 265 * F, "ticks": 25})
	if sector in [1, 4]:
		sw.mines.append({"x": 475 * F, "y": sw.camera_top + 250 * F, "armed": true, "hostile": true})
	sw.barrels.append({"x": 100 * F, "y": sw.camera_top + 175 * F, "armed": true, "fuse_ticks": 0})
	sw.pickups.append({"x": 210 * F, "y": sw.camera_top + 290 * F, "kind": 0})
	sw.pickups.append({"x": 435 * F, "y": sw.camera_top + 310 * F, "kind": 1})
	return sw


func _pose_gunship(phase: int) -> void:
	var sw: SimWorld = main.sim
	var gy := sw.camera_top + 125 * F
	var boss := {"alive": true, "hp": 23, "x": 320 * F, "dir": 1, "phase_t": phase, "gate_y": gy}
	main._boss_hpmax["boss%d" % gy] = 40.0
	if phase < 0:
		sw.mode = "endless"
		sw.wave = 5
		sw.endless_boss = boss
	else:
		sw.gates.append({"y": gy, "open": false, "b1": {}, "b2": {}, "final": false, "boss": boss})
	if phase < 0:
		# No firing during inbound. Field bullets remain; the incoming boss itself is silent.
		sw.strikes.clear()


func _pose_colossus(phase: int, core: int) -> void:
	var sw: SimWorld = main.sim
	sw.last_stand = true
	sw.colossus = {"alive": true, "hp": [55, 35, 15][phase - 1], "max_hp": 60,
		"x": 320 * F, "y": sw.camera_top + 125 * F, "spray_cd": 10,
		"volley_cd": 40, "spawn_cd": 20, "core_open": core, "core_cd": 75}
	sw.gates.append({"y": sw.camera_top + 50 * F, "open": false, "b1": {}, "b2": {}, "boss": {}, "final": true})
	sw.strikes.append({"x": 250 * F, "y": sw.camera_top + 290 * F, "ticks": 12})


func _pose_labels() -> void:
	var sw: SimWorld = main.sim
	sw.mode = "endless"
	sw.wave = 12
	sw.intermission_ticks = 240
	sw.pickups.clear()
	for i in 5:
		sw.pickups.append({"x": (230 + i * 42) * F, "y": sw.camera_top + 255 * F,
			"kind": i % 4, "cost": 20 + i * 10})
	for i in 5:
		main._fx.append({"x": (280 + i * 12) * F, "y": sw.camera_top + 260 * F, "t": 0.15,
			"kind": "floattext", "rate": 0.013, "size": 11,
			"text": ["BOUNTY +20¢", "FRAG x3", "SUPPLY CALL", "LOADOUT LOST", "VEST READY"][i],
			"col": Color(1.0, 0.85, 0.4)})


func _dress_explosions() -> void:
	for i in 2:
		main._ev_explosion({"t": "explosion", "x": (150 + i * 325) * F,
			"y": main.sim.camera_top + (155 + i * 60) * F})
	var explosion_index := 0
	for fx in main._fx:
		if fx["kind"] == "explosion":
			fx["t"] = 0.02 if explosion_index == 0 else 0.22
			explosion_index += 1


func _record(spec: Dictionary, path: String, img: Image, ops: Array) -> Dictionary:
	var record := super._record(spec, path, img, ops)
	record["stage"] = stage
	record["first_encounter_banners"] = []
	for banner in main._banners:
		record["first_encounter_banners"].append({"text": banner["text"],
			"remaining": banner["t"], "tier": banner.get("tier", -1)})
	record["stage"]["checksum_after_render"] = main.sim.checksum()
	if main.sim.checksum() != pose_checksum:
		_fail(spec, "Rendering changed the posed gameplay checksum.")
	record["world_label_slots"] = []
	for box in main._label_slots:
		record["world_label_slots"].append(_rect(box))
	record["source"] = {"main_sha256": FileAccess.get_sha256("res://src/main.gd"),
		"sim_sha256": FileAccess.get_sha256("res://src/sim/sim_world.gd"),
		"harness_sha256": FileAccess.get_sha256("res://tools/remaining_presentation_capture.gd")}
	return record
