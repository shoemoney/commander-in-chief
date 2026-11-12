extends RefCounted
## Hero presence (view-only): muzzle flash, brass, dust, reticle overlay, hurt/downed reads.

const Runner := preload("res://tests/run_tests.gd")
const Main := preload("res://src/main.gd")


func _sim() -> SimWorld:
	return SimWorld.new(7, 2, "campaign")


func _idle() -> Array[SimInput]:
	return [SimInput.new(), SimInput.new()] as Array[SimInput]


func test_fire_cd_constant_mirrors_sim() -> void:
	Runner.T.eq(PlayerPolish.FIRE_CD, SimWorld.FIRE_COOLDOWN_TICKS, "view copy of the fire cooldown matches the sim")


func test_a_real_shot_starts_flash_and_ejects_brass() -> void:
	var sim := _sim()
	var pol := PlayerPolish.new()
	sim.step(_idle())
	pol.observe(sim.players, sim.tick_count, 1.0)
	Runner.T.eq(pol.flash_age[0], -1, "no flash before firing")
	var inp := _idle()
	inp[0].fire = true
	inp[0].aim_x = 0
	inp[0].aim_y = -256
	sim.step(inp)
	pol.observe(sim.players, sim.tick_count, 1.0)
	Runner.T.eq(pol.flash_age[0], 0, "the shot tick opens the flash")
	Runner.T.eq(pol.casings.size(), 1, "one casing ejected per shot")
	for _k in PlayerPolish.FLASH_TICKS + 2:
		sim.step(_idle())
		pol.observe(sim.players, sim.tick_count, 1.0)
	Runner.T.eq(pol.flash_age[0], -1, "flash is brief")
	Runner.T.eq(pol.casings.size(), 1, "brass lingers on the ground")
	for _k in PlayerPolish.CASING_LIFE:
		sim.step(_idle())
		pol.observe(sim.players, sim.tick_count, 1.0)
	Runner.T.eq(pol.casings.size(), 0, "brass fades away")


func test_observe_is_idempotent_per_tick_and_reduce_motion_skips_flight() -> void:
	var sim := _sim()
	var pol := PlayerPolish.new()
	sim.step(_idle())
	pol.observe(sim.players, sim.tick_count, 0.0)
	var inp := _idle()
	inp[0].fire = true
	inp[0].aim_y = -256
	sim.step(inp)
	pol.observe(sim.players, sim.tick_count, 0.0)
	pol.observe(sim.players, sim.tick_count, 0.0)
	Runner.T.eq(pol.casings.size(), 1, "same tick observed twice emits once")
	Runner.T.ok(pol.casings[0]["rest"], "reduce-motion brass lands immediately")


func test_flash_layers_directional_and_accessible() -> void:
	var full := PlayerPolish.flash_layers(0, 1.0)
	Runner.T.ok(full.size() >= 3, "full flash: spike layers plus crack spike")
	var tip := 0.0
	for l in full:
		for v: Vector2 in l["pts"]:
			tip = maxf(tip, v.x)
	Runner.T.ok(tip >= 15.0, "cone reaches well past the muzzle (%.1f)" % tip)
	Runner.T.ok(PlayerPolish.flash_layers(0, 0.3).size() < full.size(), "calm mode drops the spikes")
	Runner.T.ok(PlayerPolish.flash_layers(0, 0.0).is_empty(), "flash off means nothing drawn")
	Runner.T.ok(PlayerPolish.flash_layers(PlayerPolish.FLASH_TICKS + 1, 1.0).is_empty(), "flash expires")
	Runner.T.ok(PlayerPolish.light_pool(0, 1.0)["col"].a > PlayerPolish.light_pool(5, 1.0)["col"].a, "light pool fades")


func test_dust_on_footsteps_and_reduce_motion() -> void:
	var sim := _sim()
	var pol := PlayerPolish.new()
	var inp := _idle()
	inp[0].move_x = 256
	for _k in 40:
		sim.step(inp)
		pol.observe(sim.players, sim.tick_count, 1.0)
	Runner.T.ok(pol.dust.size() > 0, "walking kicks footstep dust")
	var still := PlayerPolish.new()
	var sim2 := _sim()
	for _k in 40:
		sim2.step(_idle())
		still.observe(sim2.players, sim2.tick_count, 1.0)
	Runner.T.eq(still.dust.size(), 0, "standing still kicks none")
	var calm := PlayerPolish.new()
	var sim3 := _sim()
	for _k in 40:
		sim3.step(inp)
		calm.observe(sim3.players, sim3.tick_count, 0.0)
	Runner.T.eq(calm.dust.size(), 0, "reduce motion: no dust")


func test_reticle_ident_hurt_downed_shapes() -> void:
	var segs := PlayerPolish.reticle_segments(Color.WHITE, Color.GREEN, 0.0)
	var dark := 0
	for s in segs:
		if s["col"].r == 0.0:
			dark += 1
	Runner.T.ok(dark >= 5, "reticle ticks carry dark keylines")
	var solo := PlayerPolish.marker_segments(Color.GREEN, false, 0)
	var duo := PlayerPolish.marker_segments(Color.GOLD, true, 1)
	Runner.T.eq(solo.size(), 4, "solo marker is a keylined chevron")
	Runner.T.eq(duo.size(), 4 + 4, "P2 marker adds two keylined pip bars")
	Runner.T.eq(solo[0]["col"].r, 0.0, "marker keyline comes first")
	Runner.T.eq(PlayerPolish.KEYLINE_OFFSETS.size(), 4, "body keyline is a 4-way dark outline")
	Runner.T.eq(PlayerPolish.ident_pips(0, Color.GREEN).size(), 1, "P1 one pip")
	Runner.T.eq(PlayerPolish.ident_pips(1, Color.GOLD).size(), 2, "P2 two pips")
	Runner.T.ok(PlayerPolish.hurt_look(0, 1.0)["ring"].a > PlayerPolish.hurt_look(10, 1.0)["ring"].a, "hurt ring fades")
	Runner.T.ok(PlayerPolish.hurt_look(0, 0.0).is_empty(), "no hurt flash with flashes off")
	Runner.T.eq(PlayerPolish.downed_marker(Color.GREEN, 0.3, true)["segs"].size(), 4, "downed cross is two keylined strokes")


func test_wired_through_real_main() -> void:
	var src := FileAccess.get_file_as_string("res://src/main.gd")
	var body := src.substr(src.find("func _draw_players_under()"))
	body = body.substr(0, body.find("\nfunc _coin_trail"))
	for needle in ["_polish.observe(", "_polish.draw_ground(", "_polish.draw_flash(",
			"PlayerPolish.reticle_segments(", "PlayerPolish.downed_marker(", "PlayerPolish.hurt_look(", "PlayerPolish.marker_segments(", "PlayerPolish.KEYLINE_OFFSETS"]:
		Runner.T.ok(body.contains(needle), "the player draw passes call " + needle)
	var m := Main.new()
	Runner.T.ok(m.get("_polish") is PlayerPolish, "main holds a PlayerPolish")
	m.free()


func test_player_light_and_shade_draw_under_enemy_bullets() -> void:
	var src := FileAccess.get_file_as_string("res://src/main.gd")
	var d := src.substr(src.find("func _draw() -> void:"))
	d = d.substr(0, d.find("\nfunc ", 10))
	var i_under := d.find("_draw_players_under()")
	var i_proj := d.find("_draw_projectiles()")
	var i_over := d.find("\t_draw_players()")
	Runner.T.ok(i_under >= 0 and i_under < i_proj, "the under pass runs before _draw_projectiles")
	Runner.T.ok(i_proj < i_over, "the sprite pass runs after the projectiles")
	var under := src.substr(src.find("func _draw_players_under()"))
	under = under.substr(0, under.find("\nfunc _draw_players()"))
	for needle in ["_polish.draw_ground(", "_polish.draw_flash(", "Vector2(42, 42)", "Vector2(26, 11)"]:
		Runner.T.ok(under.contains(needle), "under pass owns " + needle)
	var over := src.substr(src.find("\nfunc _draw_players()"))
	over = over.substr(0, over.find("\nfunc _coin_trail"))
	for needle in ["_polish.draw_ground(", "_polish.draw_flash(", "Vector2(42, 42)", "Vector2(26, 11)", "_polish.observe("]:
		Runner.T.ok(not over.contains(needle), "over pass no longer draws " + needle)


func test_memoised_segments_track_their_inputs() -> void:
	var a := PlayerPolish.marker_segments(Color.GREEN, false, 0)
	Runner.T.ok(PlayerPolish.marker_segments(Color.GREEN, false, 0) == a, "same inputs, same segments")
	var gold := PlayerPolish.marker_segments(Color.GOLD, false, 0)
	Runner.T.eq(gold[2]["col"], Color(Color.GOLD.r, Color.GOLD.g, Color.GOLD.b, 1.0), "a new identity colour is not served the old memo")
	Runner.T.eq(PlayerPolish.marker_segments(Color.GREEN, false, 0), PlayerPolish._build_marker_segments(Color.GREEN, false, 0), "memo equals a fresh build")
	Runner.T.eq(PlayerPolish.marker_segments(Color.GREEN, true, 1).size(), PlayerPolish._build_marker_segments(Color.GREEN, true, 1).size(), "co-op slot 1 keeps its extra bars")
	Runner.T.ok(PlayerPolish.marker_segments(Color.GREEN, true, 1).size() > PlayerPolish.marker_segments(Color.GREEN, false, 1).size(), "coop flag is part of the key")
	var r0 := PlayerPolish.reticle_segments(Color.WHITE, Color.GREEN, 0.0)
	var r2 := PlayerPolish.reticle_segments(Color.WHITE, Color.GREEN, 2.0)
	Runner.T.ok(r0[0]["a"] != r2[0]["a"], "reticle grow is part of the key")
	Runner.T.eq(PlayerPolish.reticle_segments(Color.WHITE, Color.GREEN, 2.0), PlayerPolish._build_reticle_segments(Color.WHITE, Color.GREEN, 2.0), "reticle memo equals a fresh build")
	var r_col := PlayerPolish.reticle_segments(Color.RED, Color.GREEN, 2.0)
	Runner.T.eq(r_col[4]["col"], Color(1.0, 0.0, 0.0, 1.0), "reticle colour is part of the key")


func test_flash_triangulation_cache_matches_the_layers() -> void:
	for age in range(0, 7):
		for st in [1.0, 0.4]:
			var cached := PlayerPolish._flash_cached(age, st)
			var fresh := PlayerPolish.flash_layers(age, st)
			Runner.T.eq(cached.size(), fresh.size(), "age %d strength %s layer count" % [age, st])
			for i in fresh.size():
				Runner.T.eq(cached[i]["pts"], fresh[i]["pts"], "flash points")
				Runner.T.eq(cached[i]["idx"], Geometry2D.triangulate_polygon(fresh[i]["pts"]), "flash indices")
	Runner.T.ok(PlayerPolish._flash_cached(9, 1.0).is_empty() and PlayerPolish._flash_cached(2, 0.0).is_empty(), "no flash past its life or with flashes off")


func test_arc_px_runs_cover_the_pixels_art_arc_stamps() -> void:
	var bad := 0
	for r in [4, 8, 14]:
		for w in [1, 2]:
			for a0 in [0.15, 1.7, -1.5707963267948966, 4.0]:
				for span in [0.3, 1.2, 2.5, 5.0]:
					var entry: Dictionary = Art._ring_entry(r, w, false)
					var win: Vector3i = Art._arc_span(entry["angles"], a0, span)
					var ref := {}
					for i in range(win.x, win.y):
						ref[Vector2i(entry["offsets"][i])] = true
					for i in win.z:
						ref[Vector2i(entry["offsets"][i])] = true
					var runs := PlayerPolish._build_arc_runs(r, w, a0, a0 + span)
					var got := {}
					var k := 0
					while k < runs.size():
						for xx in int(runs[k + 2]):
							got[Vector2i(int(runs[k]) + xx, int(runs[k + 1]))] = true
						k += 3
					if got != ref:
						bad += 1
	Runner.T.eq(bad, 0, "arc_px stamps exactly the pixels Art.arc does")


func test_arc_texture_holds_exactly_the_arc_pixels() -> void:
	var bad := 0
	for a0 in [0.15, 2.0, -1.5707963267948966]:
		var runs := PlayerPolish._build_arc_runs(8, 2, a0, a0 + 1.4)
		var e: Array = [null, 0, null, 0.0, 0.0, 0.0, 0.0]
		ProjectilesPolish._promote_rects(e, runs, 3)
		var img: Image = e[2].get_image()
		var want := {}
		var k := 0
		while k < runs.size():
			for xx in int(runs[k + 2]):
				want[Vector2i(int(runs[k]) + xx, int(runs[k + 1]))] = true
			k += 3
		var got := {}
		for yy in img.get_height():
			for xx in img.get_width():
				if img.get_pixel(xx, yy).a > 0.0:
					got[Vector2i(xx + int(e[3]), yy + int(e[4]))] = true
		if got != want:
			bad += 1
	Runner.T.eq(bad, 0, "the baked arc texture matches the stamped pixels")


func test_gapped_ring_bakes_the_five_arcs_it_replaced() -> void:
	var want := {}
	for si in 5:
		var a0 := si * TAU / 5.0 + 0.15
		var entry: Dictionary = Art._ring_entry(14, 1, false)
		var win: Vector3i = Art._arc_span(entry["angles"], a0, TAU / 5.0 - 0.3)
		for i in range(win.x, win.y):
			want[Vector2i(entry["offsets"][i])] = true
		for i in win.z:
			want[Vector2i(entry["offsets"][i])] = true
	var runs := PackedFloat32Array()
	for si in 5:
		var b0 := si * TAU / 5.0 + 0.15
		runs.append_array(PlayerPolish._build_arc_runs(14, 1, b0, b0 + TAU / 5.0 - 0.3))
	var got := {}
	var k := 0
	var dup := 0
	while k < runs.size():
		for xx in int(runs[k + 2]):
			var key := Vector2i(int(runs[k]) + xx, int(runs[k + 1]))
			if got.has(key):
				dup += 1
			got[key] = true
		k += 3
	Runner.T.eq(got, want, "the merged ring has the pixels of the five Art.arc calls")
	Runner.T.eq(dup, 0, "the five windows never share a pixel (so one draw blends the same)")
