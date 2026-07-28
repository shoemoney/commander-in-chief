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


func test_six_authored_zones_and_ruins_landmark_is_reachable() -> void:
	## authored-campaign-and-modes: FINAL_GATE_INDEX moved 5 -> 6 so gate 5
	## (previously "final" and untested arena territory) is a real bunker
	## arena wearing the RUINS crashed-convoy landmark -- lm_sector case 3 was
	## DEAD CODE before this (gate 3 is always the boss gate, never a bunker
	## arena), so this is the first time it can ever fire.
	Runner.T.eq(SimWorld.FINAL_GATE_INDEX, 6, "six gates now cap the campaign")
	Runner.T.eq(SimWorld.ZONE_INFO.size(), SimWorld.FINAL_GATE_INDEX, "one named zone per gate")
	for zi in SimWorld.ZONE_INFO:
		Runner.T.ok(not (zi["name"] as String).is_empty(), "every zone has a name")
		Runner.T.ok(not (zi["blurb"] as String).is_empty(), "every zone has a narrative blurb")
	Runner.T.ok(SimWorld.ARENAS.has(5), "gate 5 has its own authored arena template")
	var sim := SimWorld.new(3, 1)
	sim.camera_top = -10000 * Fixed.ONE
	sim._step_camera()
	Runner.T.ok(sim._world_ended, "streaming reaches the (now deeper) Foundry finale")
	var gate5_rocks := 0
	for rk in sim.rocks:
		if rk.get("kind", 0) == 2 and rk["y"] > -4900 * Fixed.ONE and rk["y"] < -4700 * Fixed.ONE:
			gate5_rocks += 1
	Runner.T.ok(gate5_rocks > 0, "the RUINS landmark actually placed rocks at gate 5 (was unreachable)")


func test_jump_to_chapter_offsets_every_stream_cursor() -> void:
	## authored-campaign-and-modes: Arcade's chapter jump must move the camera,
	## players, and every streaming cursor by an identical amount (an exact
	## multiple of GATE_SPACING) so the next gate streamed is chapter 4 at its
	## natural authored y -- not a chapter-1 gate relabeled.
	var jumped := SimWorld.new(7, 1, "arcade")
	jumped.jump_to_chapter(4)
	Runner.T.eq(jumped._gate_counter, 3, "gate_counter primed so the NEXT streamed gate is #4")
	var skip: int = 3 * SimWorld.GATE_SPACING
	Runner.T.eq(jumped.camera_top, -SimWorld.VIEW_H - skip, "camera starts chapter 4's distance in")
	jumped._step_camera()
	var found_gate4 := false
	for g in jumped.gates:
		if g["y"] == -4 * SimWorld.GATE_SPACING:
			found_gate4 = true
	Runner.T.ok(found_gate4, "the first streamed gate lands exactly at chapter 4's authored y")
	# Chapter 1 is a no-op (nothing to skip) — a plain campaign-shaped start.
	var fresh := SimWorld.new(7, 1, "arcade")
	var before := fresh.camera_top
	fresh.jump_to_chapter(1)
	Runner.T.eq(fresh.camera_top, before, "chapter 1 jump is a no-op")


func test_arcade_mode_streams_like_campaign() -> void:
	## Arcade reuses the FULL campaign streaming machinery (mines/barrels/
	## gates/landmarks) -- it must NOT hit the boss_rush/no-op early return in
	## _step_camera the way "campaign only" mode gating would otherwise cause.
	var sim := SimWorld.new(11, 1, "arcade")
	sim.camera_top = -3000 * Fixed.ONE
	sim._step_camera()
	Runner.T.ok(sim.gates.size() > 0, "arcade streams real gates, unlike boss_rush's guard")
	Runner.T.ok(not sim.mines.is_empty() or not sim.barrels.is_empty(),
		"arcade streams field hazards like campaign")


# --- The debrief copy must NAME the terrain the ground actually renders. The victory
# card shipped "%dm OF JUNGLE PUSHED" over sand, cacti and tumbleweed for the whole
# desert retheme: the words were hardcoded, the art moved, nothing failed. -------------

## Words no band of either ground palette may ever be called: every stop of both
## ramps is a warm sand/rust modulate, so a wet/green biome name is always a lie.
const WET_GREEN_WORDS := ["JUNGLE", "FOREST", "SWAMP", "GRASSLAND", "CANOPY",
	"TUNDRA", "SNOWFIELD", "ARCTIC", "MEADOW"]


func test_terrain_word_matches_the_ground_band_it_names() -> void:
	var MainS := load("res://src/main.gd")
	var m = MainS.new()
	for mode in ["campaign", "endless"]:
		var stops: Array = MainS._ground_stops(mode)[0]
		Runner.T.eq(MainS.TERRAIN_WORDS.size(), stops.size(),
			"%s: one terrain word per ground band" % mode)
		for band in stops.size():
			var c: Color = stops[band]
			var march := float(band) / 5.0
			var word: String = MainS.TERRAIN_WORDS[band]
			# Red-dominant with green suppressed == sand/ochre/rust. Both palettes are
			# built that way on purpose (see _ground_stops); if a retheme ever breaks it,
			# the words below stop being true and this fails first.
			Runner.T.ok(c.r > c.g and c.g >= c.b,
				"%s band %d ground stop %s is a warm desert color" % [mode, band, c])
			for w in WET_GREEN_WORDS:
				Runner.T.ok(not word.contains(w),
					"%s band %d renders warm sand but its word says %s (%s)" % [mode, band, w, word])
			# The word and the color are picked with the SAME band index — that is the
			# coupling that keeps the copy from desyncing from the art again.
			Runner.T.eq(MainS._terrain_word(march), word,
				"%s band %d word tracks the band index" % [mode, band])
			Runner.T.eq(m._biome_ramp(march, stops), c,
				"%s band %d color tracks the same band index" % [mode, band])
	Runner.T.eq(MainS._terrain_word(1.0), MainS.TERRAIN_WORDS[4],
		"a finished run holds the final band's word (same clamp as _biome_ramp)")
	m.free()


func test_no_view_string_names_a_biome_the_game_never_renders() -> void:
	## Source scan over every file that draws user-facing copy: an ALL-CAPS biome word
	## inside a string literal is player-visible text, and the game has exactly one
	## theater (Iran desert). This is the check that would have caught the victory card.
	for path in ["res://src/main.gd", "res://src/view/menu.gd", "res://src/view/hud.gd"]:
		var src := FileAccess.get_file_as_string(path)
		Runner.T.ok(not src.is_empty(), "read %s" % path)
		var offenders := PackedStringArray()
		var line_no := 0
		for line in src.split("\n"):
			line_no += 1
			if line.strip_edges().begins_with("#"):
				continue   # prose comments talk about the old jungle theme freely
			var parts := line.split("\"")
			if parts.size() % 2 == 0:
				continue   # unbalanced quotes (a comment quoting a word) — not scannable
			var i := 1
			while i < parts.size():
				for w in WET_GREEN_WORDS:
					if (parts[i] as String).contains(w):
						offenders.append("%s:%d %s" % [path, line_no, w])
				i += 2   # odd indices are the quoted spans
		Runner.T.eq(", ".join(offenders), "",
			"%s: user-facing copy names a biome the game never renders" % path)


func test_arcade_obeys_the_authored_corridor_rules() -> void:
	## ARCADE / CHAPTER SELECT routes through the campaign branch of step() and
	## streams the same authored world — but nine corridor predicates were gated on
	## the literal string "campaign", so Arcade played a hollowed-out version of the
	## same map: no lane seals, no one-way ledge, and (until the econ fix) base
	## prices. Scan for a seal rather than hard-coding a coordinate, and assert
	## campaign finds one so a vacuous scan can't go green.
	var arc := SimWorld.new(11, 1, "arcade")
	var cam := SimWorld.new(11, 1, "campaign")
	var arc_sealed := false
	var cam_sealed := false
	var arc_ledge := false
	var cam_ledge := false
	for step in range(2000, 6000, 5):
		var wy: int = -step * SimWorld.F_ONE
		for x in [SimWorld.WORLD_LEFT, SimWorld.WORLD_RIGHT]:
			if arc._lane_blocked(x, wy): arc_sealed = true
			if cam._lane_blocked(x, wy): cam_sealed = true
			if arc._crosses_ledge_south(x, wy + 4 * SimWorld.F_ONE, wy - 4 * SimWorld.F_ONE): arc_ledge = true
			if cam._crosses_ledge_south(x, wy + 4 * SimWorld.F_ONE, wy - 4 * SimWorld.F_ONE): cam_ledge = true
	Runner.T.ok(cam_sealed and cam_ledge, "guard: the scan window really contains a campaign seal and ledge")
	Runner.T.ok(arc_sealed, "ARCADE seals lanes past seg 2 — it is the same authored world")
	Runner.T.ok(arc_ledge, "ARCADE has the one-way ledge past seg 2")
	# Depth-scaled prices: pose 4 opened gates on both and compare the SHIPPED price.
	for _g in 4:
		arc.gates.append({"open": true})
		cam.gates.append({"open": true})
	Runner.T.eq(arc._supply_cost(0), cam._supply_cost(0), "ARCADE prices creep with depth like campaign")
