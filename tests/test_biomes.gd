extends RefCounted
## Biome-exclusive verbs (c2 5v): the seg-2 marsh current drifts airborne
## grenades; seg-4+ foundry rows grow phase-cycled heat vents. Both live PAST
## the golden window — these tests pin the mechanics AND the fairness contracts
## (lane clearance, warn duration, once-per-jet).

const Runner := preload("res://tests/run_tests.gd")


func _marsh_grenade(sim: SimWorld, shell := false) -> Dictionary:
	# Airborne grenade over seg-2 water (band row -2540..-2460 covers y -2500).
	sim.waters.append({"y": -2540 * Fixed.ONE, "ford_x": 600 * Fixed.ONE})
	var g := {"x": 300 * Fixed.ONE, "y": -2500 * Fixed.ONE, "vx": 0, "vy": 0,
		"z": 50 * Fixed.ONE, "zv": 0, "owner": 0, "shell": shell, "hold": false}
	sim.grenades.append(g)
	return g


func test_marsh_current_drifts_grenades() -> void:
	var sim := SimWorld.new(31, 1)
	var g := _marsh_grenade(sim)
	var x0: int = g["x"]
	var dir: int = 1 if SimWorld._mix(SimWorld.MARSH_SEG, sim._world_seed) & 1 else -1
	for i in 10:
		sim._step_grenades()
	Runner.T.eq(g["x"], x0 + dir * 10 * SimWorld.MARSH_DRIFT,
		"10 airborne ticks over marsh water drift exactly 10px in the hashed direction")


func test_marsh_current_exempts_shells() -> void:
	var sim := SimWorld.new(31, 1)
	var g := _marsh_grenade(sim, true)
	var x0: int = g["x"]
	for i in 10:
		sim._step_grenades()
	Runner.T.eq(g["x"], x0, "tank shells fly true over marsh water (heavy-ordnance rule)")


func test_marsh_current_needs_open_water() -> void:
	# Seg-2 but DRY under the arc (over the ford): no drift — the current is a
	# property of the water, not the sector (judge r1 negative case). Pin the
	# c4 collapsing-bridge phase OPEN (tick 400 -> band-2 phase 100 < 180) so the
	# ford is dry-foot for this negative case.
	var sim := SimWorld.new(31, 1)
	sim.tick_count = 400
	sim.waters.append({"y": -2540 * Fixed.ONE, "ford_x": 300 * Fixed.ONE})
	var g := {"x": 300 * Fixed.ONE, "y": -2500 * Fixed.ONE, "vx": 0, "vy": 0,
		"z": 50 * Fixed.ONE, "zv": 0, "owner": 0, "shell": false, "hold": false}
	sim.grenades.append(g)
	var x0: int = g["x"]
	for i in 10:
		sim._step_grenades()
	Runner.T.eq(g["x"], x0, "the ford is dry — a grenade arcing over it flies straight")


func test_marsh_current_is_seg2_exclusive() -> void:
	var sim := SimWorld.new(31, 1)
	# Same water geometry one segment up (band 1, the torture band): no drift.
	sim.waters.append({"y": -1540 * Fixed.ONE, "ford_x": 600 * Fixed.ONE})
	var g := {"x": 300 * Fixed.ONE, "y": -1500 * Fixed.ONE, "vx": 0, "vy": 0,
		"z": 50 * Fixed.ONE, "zv": 0, "owner": 0, "shell": false, "hold": false}
	sim.grenades.append(g)
	var x0: int = g["x"]
	for i in 10:
		sim._step_grenades()
	Runner.T.eq(g["x"], x0, "seg-1 water leaves grenades undrifted — the verb is marsh-exclusive")


func test_vents_stream_only_past_seg4() -> void:
	var sim := SimWorld.new(31, 1)
	sim.camera_top = -4500 * Fixed.ONE
	sim._step_camera()
	Runner.T.ok(not sim.vents.is_empty(), "foundry depth streams vents")
	# The campaign-reachable foundry stretch (seg 4) must KEEP vents after the
	# apron/water/gate keep-outs eat their rows — at the old 460px cadence the
	# guards killed every row and the mechanic never existed in a real run.
	var seg4_rows := {}
	for v in sim.vents:
		if absi(v["y"]) / SimWorld.GATE_SPACING == 4:
			seg4_rows[v["y"]] = true
	Runner.T.ok(seg4_rows.size() >= 2, "seg 4 keeps >= 2 vent rows (got %d)" % seg4_rows.size())
	for v in sim.vents:
		Runner.T.ok(absi(v["y"]) / SimWorld.GATE_SPACING >= SimWorld.VENT_START_SEG,
			"every vent sits at seg >= %d" % SimWorld.VENT_START_SEG)
		var off: int = absi(v["y"]) % SimWorld.GATE_SPACING
		Runner.T.ok(off < 460 * Fixed.ONE or off > 620 * Fixed.ONE,
			"no vent lands in the water-band keep-out (offsets 460-620)")


func test_vent_lanes_clear_hull() -> void:
	# The passage contract: every gap between two hurt discs in a chunk must
	# pass HULL_CLEARANCE (consumers test >= — the comparator contract).
	Runner.T.ok(100 * Fixed.ONE - 2 * SimWorld.VENT_HURT_RADIUS >= SimWorld.HULL_CLEARANCE,
		"the minimum 100px chunk pitch leaves a >= HULL_CLEARANCE lane between discs")
	# Full 2D clearance (judge r1): center distance minus both 24px discs must
	# clear the hull — squared-integer form, no sqrt: dx²+dy² >= (2r+HC)².
	var min_c: int = (2 * SimWorld.VENT_HURT_RADIUS + SimWorld.HULL_CLEARANCE) / Fixed.ONE
	for chunk in SimWorld.VENT_CHUNKS:
		for i in chunk.size():
			for j in range(i + 1, chunk.size()):
				var dx: int = chunk[i][0] - chunk[j][0]
				var dy: int = chunk[i][1] - chunk[j][1]
				Runner.T.ok(dx * dx + dy * dy >= min_c * min_c,
					"chunk pair (%d,%d) leaves a hull lane in FULL 2D distance" % [i, j])


func test_vent_warn_beats_reaction_floor() -> void:
	Runner.T.ok(SimWorld.VENT_WARN_TICKS >= 24,
		"the warn telegraph meets the 24t reaction floor (KIMK r4 precedent)")
	Runner.T.ok(SimWorld.VENT_CYCLE_TICKS > SimWorld.VENT_JET_TICKS + SimWorld.VENT_WARN_TICKS,
		"cycle leaves idle time — vents are a repositioning beat, not a wall")


func test_vent_jet_hurts_once_per_cycle() -> void:
	var sim := SimWorld.new(31, 1)
	var p: Dictionary = sim.players[0]
	var v := {"x": p["x"], "y": p["y"]}
	sim.vents.append(v)
	p["vest"] = true
	p["hurt_iframes"] = 0
	# Park the player on the vent through one full cycle, aligned to jet start.
	var jet_at: int = SimWorld.VENT_CYCLE_TICKS - SimWorld.VENT_JET_TICKS
	var base: int = 10 * SimWorld.VENT_CYCLE_TICKS   # keep posmod's operand positive
	var vx_px: int = v["x"] / Fixed.ONE
	for ph in SimWorld.VENT_CYCLE_TICKS:
		sim.tick_count = base + ph - 7 * vx_px + jet_at
		sim._step_mines()
	Runner.T.ok(not p["vest"], "the jet popped the vest")
	Runner.T.ok(p["alive"], "one full jet costs exactly one hit — the 90t iframe window outlasts the 60t jet")


func test_vent_warn_event_fires() -> void:
	var sim := SimWorld.new(31, 1)
	var v := {"x": 300 * Fixed.ONE, "y": 0}
	sim.vents.append(v)
	var warn_at: int = SimWorld.VENT_CYCLE_TICKS - SimWorld.VENT_JET_TICKS - SimWorld.VENT_WARN_TICKS
	sim.tick_count = 10 * SimWorld.VENT_CYCLE_TICKS - 7 * (v["x"] / Fixed.ONE) + warn_at
	sim.events.clear()
	sim._step_mines()
	var found := false
	for ev in sim.events:
		if ev["t"] == "vent_warn":
			found = true
	Runner.T.ok(found, "the warn event fires exactly VENT_WARN_TICKS before the jet")


func test_vents_perturb_checksum_only_when_present() -> void:
	var a := SimWorld.new(31, 1)
	var b := SimWorld.new(31, 1)
	Runner.T.eq(a.checksum(), b.checksum(), "twin sims agree with no vents")
	b.vents.append({"x": 300 * Fixed.ONE, "y": -4200 * Fixed.ONE})
	Runner.T.ok(a.checksum() != b.checksum(), "a live vent enters the hash (conditional feed)")


func test_c3_vent_burns_grass_and_cracks_wall() -> void:
	# c3 5v: a foundry vent jet burns off grass (kind 1) and cracks walls (kind
	# 2) after VENT_COVER_BURN_TICKS; stone (0) and hero wrecks (3) are immune.
	var sim := SimWorld.new(31, 1)
	var vy: int = -(SimWorld.VENT_START_SEG * SimWorld.GATE_SPACING) - 200 * Fixed.ONE
	var vx: int = 300 * Fixed.ONE
	sim.vents.append({"x": vx, "y": vy})
	var grass := {"x": vx, "y": vy, "kind": 1}
	var wall := {"x": vx + 8 * Fixed.ONE, "y": vy, "kind": 2}
	var stone := {"x": vx - 8 * Fixed.ONE, "y": vy, "kind": 0}
	var hero := {"x": vx, "y": vy + 8 * Fixed.ONE, "kind": 3}
	sim.rocks.append_array([grass, wall, stone, hero])
	# Drive enough jetting ticks (each cycle jets VENT_JET_TICKS) to exceed the burn.
	var jetted := 0
	var base: int = 10 * SimWorld.VENT_CYCLE_TICKS
	var jet_at: int = SimWorld.VENT_CYCLE_TICKS - SimWorld.VENT_JET_TICKS
	var vx_px: int = vx / Fixed.ONE
	while jetted < SimWorld.VENT_COVER_BURN_TICKS + 2:
		# Align tick_count to a jetting phase for this vent.
		sim.tick_count = base + (jetted % SimWorld.VENT_JET_TICKS) - 7 * vx_px + jet_at
		sim._step_mines()
		jetted += 1
	Runner.T.ok(not sim.rocks.has(grass), "grass burned off under the jet")
	Runner.T.ok(not sim.rocks.has(wall), "wall cracked apart under the jet")
	Runner.T.ok(sim.rocks.has(stone), "stone is immune (doesn't burn)")
	Runner.T.ok(sim.rocks.has(hero), "the hero wreck is immune")


func test_c3_grenade_breakwater() -> void:
	# c3 5v: a solid rock immediately downstream of a marsh-drifting grenade
	# stops the drift (leeward safe shadow); remove it and the drift resumes.
	var sim := SimWorld.new(31, 1)
	sim.waters.append({"y": -2540 * Fixed.ONE, "ford_x": 600 * Fixed.ONE})
	var dir: int = 1 if SimWorld._mix(SimWorld.MARSH_SEG, sim._world_seed) & 1 else -1
	var g := {"x": 300 * Fixed.ONE, "y": -2500 * Fixed.ONE, "vx": 0, "vy": 0,
		"z": 50 * Fixed.ONE, "zv": 0, "owner": 0, "shell": false, "hold": false}
	# Solid rock immediately downstream (in the drift direction).
	var breakwater := {"x": 300 * Fixed.ONE + dir * 14 * Fixed.ONE, "y": -2500 * Fixed.ONE, "kind": 0}
	sim.rocks.append(breakwater)
	sim.grenades.append(g)
	var x0: int = g["x"]
	for i in 6:
		sim._step_grenades()
	Runner.T.eq(g["x"], x0, "the breakwater rock stops the marsh drift (safe shadow)")
	# Remove the rock — drift resumes on an identical throw.
	var sim2 := SimWorld.new(31, 1)
	sim2.waters.append({"y": -2540 * Fixed.ONE, "ford_x": 600 * Fixed.ONE})
	var g2 := {"x": 300 * Fixed.ONE, "y": -2500 * Fixed.ONE, "vx": 0, "vy": 0,
		"z": 50 * Fixed.ONE, "zv": 0, "owner": 0, "shell": false, "hold": false}
	sim2.grenades.append(g2)
	for i in 6:
		sim2._step_grenades()
	Runner.T.ok(g2["x"] != x0, "with no breakwater the drift applies as before")
