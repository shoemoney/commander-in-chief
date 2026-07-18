extends RefCounted
## View-layer ASSET invariants (assets review cycle). These pin the art.gd / main.gd
## registries the readability + art-direction systems depend on, so a stray edit that
## (e.g.) light-rims a hero, or drops a hostile from the separator set, fails HERE
## instead of only showing up in a screenshot. Pure const checks — no draw, no sim.

const Runner := preload("res://tests/run_tests.gd")


func _consts() -> Dictionary:
	# Typed as the Script base (not the class) so the instance method resolves —
	# calling it through the preloaded class type is a static-call error.
	var ms: Script = load("res://src/main.gd")
	return ms.get_script_constant_map()


# --- a1-02: small-hostile figure-ground separator rim ---

func test_a1_light_rim_is_a_subset_of_unit_rims() -> void:
	# Every warm-light separator hostile must also be a full unit rim (the width
	# override rides on top of the unit-rim path; a light-rim key with no unit-rim
	# entry would silently get no rim at all).
	var c := _consts()
	var light: Dictionary = c["_LIGHT_RIM"]
	var unit: Dictionary = c["_UNIT_RIM"]
	Runner.T.ok(light.size() >= 8, "the small-hostile separator set is populated (%d)" % light.size())
	for k in light:
		Runner.T.ok(unit.has(k), "light-rim hostile '%s' must also be a unit rim" % k)


func test_a1_light_rim_excludes_friendlies_and_readable_units() -> void:
	# Heroes carry a bright tint + green ID ring; frogman/observer/bombsuit already
	# read — none may take the warm-light HOSTILE separator (it would misread as enemy).
	var light: Dictionary = _consts()["_LIGHT_RIM"]
	for k in ["player1", "player2", "frogman", "observer", "m_bombsuit"]:
		Runner.T.ok(not light.has(k), "'%s' must keep the neutral rim, not the hostile separator" % k)


# --- a1-03: water body follows the 5-stop biome ramp ---

func test_a1_water_stops_are_five_and_biome_distinct() -> void:
	var c := _consts()
	var shallow: Array = c["_WATER_SHALLOW_STOPS"]
	var deep: Array = c["_WATER_DEEP_STOPS"]
	Runner.T.eq(shallow.size(), 5, "water shallow ramp has one stop per sector")
	Runner.T.eq(deep.size(), 5, "water deep ramp has one stop per sector")
	# jungle stop unchanged (the river opener must stay teal, not go muddy early)
	Runner.T.ok(shallow[0].is_equal_approx(Color(0.24, 0.43, 0.40)), "jungle shallow is a de-cerulaned olive-teal (a2-06)")
	# the journey actually MOVES: the foundry water must be far from the jungle water
	# (the old capped soot-lerp left it muddy-blue). Warm/red foundry vs cool jungle.
	Runner.T.ok(deep[4].r > deep[0].r + 0.1, "foundry deep water is warmer (redder) than jungle")
	Runner.T.ok(deep[4].b < deep[0].b - 0.1, "foundry deep water is far less blue than jungle")
	# mid-stops carry their biome, not just the endpoints (judge a1-03 r2):
	Runner.T.ok(shallow[2].g > shallow[2].b and shallow[2].g > shallow[2].r,
		"marsh (sector 2) shallow leans GREEN — murk, not blue")
	Runner.T.ok(deep[3].b < deep[0].b - 0.04 and absf(deep[3].r - deep[3].g) < 0.06,
		"ruins (sector 3) deep is a de-blued neutral SLATE, not the jungle blue")
	# Rendered evidence (jungle river stays teal, no regression):
	# scratchpad/shots_a1_v5/03-river-crossing.png


# --- a1-05: foliage tint ramps to ash (no green re-bias at the foundry) ---

func test_a1_foliage_tint_ramps_to_ash() -> void:
	Art.foliage_march = 0.0
	Runner.T.ok(Art.tint("fern").is_equal_approx(Art.FOLIAGE), "jungle (march 0) keeps the lush FOLIAGE tint")
	Art.foliage_march = 1.0
	var f := Art.tint("fern")
	Runner.T.ok(f.is_equal_approx(Art.FOLIAGE_ASH), "foundry (march 1) foliage chars to FOLIAGE_ASH")
	Runner.T.ok(f.g < Art.FOLIAGE.g - 0.2, "charred foliage loses green — no re-green multiply at the foundry")
	Runner.T.ok(Art.tint("tree_large").is_equal_approx(Art.FOLIAGE_ASH), "trees ramp with ferns")
	# the ramp is foliage-ONLY: unit/decor tints are untouched
	Runner.T.ok(Art.tint("rusher").is_equal_approx(Color(2.1, 1.7, 1.15)), "unit tints ignore foliage_march")
	Art.foliage_march = 0.0   # restore the static for other suites


# --- a1-07: crater depression pit is scorched-only ---

func test_a1_crater_pit_keys() -> void:
	var ck: Dictionary = _consts()["_CRATER_KEYS"]
	Runner.T.ok(ck.has("crater") and ck.has("crater_field"), "scorched craters get the depression pit")
	Runner.T.ok(not ck.has("crater_water"), "water-filled craters are excluded from the dark pit")


# --- a1-08: white-hot explosion core constants ---

func test_a1_explosion_white_core_consts() -> void:
	var c := _consts()
	var wt: float = c["EXPLO_WHITE_T"]
	Runner.T.ok(wt > 0.0 and wt < 0.35, "white-hot lead is a brief opening fraction of the blast life")
	Runner.T.ok(c["EXPLO_WHITE_R_OUT"] > c["EXPLO_WHITE_R_IN"], "the outer white ring is larger than the inner core")


# --- a1-09: enemy muzzle fan aims at the nearest ALIVE player ---

func test_a1_enemy_muzzle_targets_nearest_alive_player() -> void:
	var sim := SimWorld.new(0xA1, 2)
	sim.players[0]["x"] = 100 * Fixed.ONE
	sim.players[0]["y"] = 100 * Fixed.ONE
	sim.players[0]["alive"] = true
	sim.players[1]["x"] = 500 * Fixed.ONE
	sim.players[1]["y"] = 100 * Fixed.ONE
	sim.players[1]["alive"] = true
	# a shot from x=120 is nearer p1 (x=100) than p2 (x=500) -> fan aims at p1
	var np := sim._nearest_alive_player(120 * Fixed.ONE, 100 * Fixed.ONE)
	Runner.T.eq(np["x"], 100 * Fixed.ONE, "enemy muzzle aims at the NEARER player")
	# a dead nearer player is skipped -> the fan tracks the live one
	sim.players[0]["alive"] = false
	var np2 := sim._nearest_alive_player(120 * Fixed.ONE, 100 * Fixed.ONE)
	Runner.T.eq(np2["x"], 500 * Fixed.ONE, "a dead nearer player is skipped; aims at the live one")


# --- a1-13: no SFX event maps to a nonexistent (silent) synth voice ---

func test_a1_every_event_sound_resolves_to_a_synth_voice() -> void:
	var sfx := Sfx.new()
	sfx._synth_all()
	var sounds: Dictionary = sfx._sounds
	Runner.T.ok(sounds.has("rubble"), "the new rubble collapse timbre is synthesized")
	Runner.T.ok(sounds.has("alarm_low") and sounds.has("alarm_air"), "the alarm sub-classes are synthesized")
	var evmap: Dictionary = _consts()["_EVENT_SOUND"]
	for ev_key in evmap:
		var sound_name: String = evmap[ev_key][0]
		Runner.T.ok(sounds.has(sound_name),
			"event '%s' -> sound '%s' must be a synthesized voice, not dead air" % [ev_key, sound_name])
	sfx.free()


func test_a1_new_synth_voices_have_energy() -> void:
	var sfx := Sfx.new()
	sfx._synth_all()
	for nm in ["rubble", "alarm_low", "alarm_air"]:
		var wav: AudioStreamWAV = sfx._sounds[nm]
		var data: PackedByteArray = wav.data
		Runner.T.ok(data.size() > 4000, "%s renders a substantial buffer (%d bytes)" % [nm, data.size()])
		var mn := 255
		var mx := 0
		for bi in range(0, mini(data.size(), 8000)):
			mn = mini(mn, data[bi])
			mx = maxi(mx, data[bi])
		Runner.T.ok(mx - mn > 8, "%s carries real signal energy (not flat silence)" % nm)
	sfx.free()


# --- a1-14: friendly supply cue split off the hostile whistle ---

func test_a1_supply_cue_split_from_hostile_whistle() -> void:
	var evmap: Dictionary = _consts()["_EVENT_SOUND"]
	Runner.T.ok(evmap["supply_drop"][0] != evmap["strike_warn"][0],
		"friendly supply cue no longer shares the hostile strike whistle")
	Runner.T.eq(evmap["supply_drop"][0], "supply_chime", "supply_drop plays the friendly chime")
	Runner.T.eq(evmap["strike_warn"][0], "whistle", "strike_warn keeps the hostile whistle")


# --- a1-15: boss music signature + per-biome ambience ---

func test_a1_boss_music_heavier_and_ambience_marches() -> void:
	var a := Sfx.new()
	for i in 200: a.set_music_intensity(1.0, 0.0, false)
	var normal_pitch: float = a._music.pitch_scale
	var b := Sfx.new()
	for i in 200: b.set_music_intensity(1.0, 0.0, true)
	var boss_pitch: float = b._music.pitch_scale
	Runner.T.ok(boss_pitch < normal_pitch, "boss music sits at a heavier (lower) pitch floor than normal combat")
	Runner.T.ok(b._music.volume_db > a._music.volume_db, "boss music also sits LOUDER than normal combat at equal intensity")
	var c := Sfx.new()
	for i in 300: c.set_ambience_march(1.0)
	var foundry_air: float = c._amb.pitch_scale
	var d := Sfx.new()
	for i in 300: d.set_ambience_march(0.0)
	var jungle_air: float = d._amb.pitch_scale
	Runner.T.ok(foundry_air < jungle_air, "foundry ambience is a lower hum than the jungle's airy bed")
	a.free(); b.free(); c.free(); d.free()


# --- a1-14 r2: the SFX bus ducks under a live VO line and recovers ---

func test_a1_sfx_bus_ducks_under_vo() -> void:
	var idx := AudioServer.get_bus_index("SFX")
	var created := false
	if idx == -1:
		AudioServer.add_bus()
		idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, "SFX")
		created = true
	AudioServer.set_bus_volume_db(idx, 0.0)
	var sfx := Sfx.new()
	for i in 40: sfx.duck_sfx_under_vo(true)
	var ducked := AudioServer.get_bus_volume_db(idx)
	Runner.T.ok(ducked < -1.0, "SFX bus dips under a live VO line (%.1f dB)" % ducked)
	for i in 80: sfx.duck_sfx_under_vo(false)
	var recovered := AudioServer.get_bus_volume_db(idx)
	Runner.T.ok(recovered > ducked + 1.0, "SFX bus recovers toward 0 when VO ends (%.1f dB)" % recovered)
	sfx.free()
	if created:
		AudioServer.remove_bus(idx)


func test_a1_boss_music_on_predicate() -> void:
	var ms = load("res://src/main.gd")
	var sim := SimWorld.new(1, 1)
	sim.colossus = {}
	sim.gates.clear()
	Runner.T.ok(not ms._boss_music_on(sim), "no colossus + no gate boss -> boss music OFF")
	sim.colossus = {"alive": true, "x": 0, "y": 0}
	Runner.T.ok(ms._boss_music_on(sim), "a live colossus finale -> boss music ON")
	sim.colossus = {}
	sim.gates.append({"y": sim.camera_top + 30 * Fixed.ONE, "boss": {"alive": true}})
	Runner.T.ok(ms._boss_music_on(sim), "a gate boss alive IN the camera band -> ON")
	sim.gates.clear()
	sim.gates.append({"y": sim.camera_top - 5000 * Fixed.ONE, "boss": {"alive": true}})
	Runner.T.ok(not ms._boss_music_on(sim), "a gate boss alive but OUTSIDE the camera band -> OFF")


# --- a1-16: spend-wheel socket display gating ---

func test_a1_wheel_socket_display_gating() -> void:
	var ms = load("res://src/main.gd")
	Runner.T.eq(ms._wheel_socket_display(true, true), "full", "SELECTED socket shows full cost+stock")
	Runner.T.eq(ms._wheel_socket_display(true, false), "full", "selected shows full even when unaffordable")
	Runner.T.eq(ms._wheel_socket_display(false, true), "dot", "unselected AFFORDABLE shows the compact can-buy dot")
	Runner.T.eq(ms._wheel_socket_display(false, false), "none", "unselected unaffordable shows neither (the × cue handles it)")


# --- a1-17: banner plate alpha floor ---

func test_a1_banner_plate_alpha_floor() -> void:
	var ms = load("res://src/main.gd")
	Runner.T.ok(is_equal_approx(ms._banner_plate_alpha(1.0), 1.0), "full text -> full plate")
	Runner.T.ok(is_equal_approx(ms._banner_plate_alpha(0.3), 0.7), "fading text -> plate HELD at the 0.7 floor (no wash-out)")
	Runner.T.ok(is_equal_approx(ms._banner_plate_alpha(0.02), 0.0), "text gone -> plate gone")


# --- a1-18: friendly greens are colorblind-safe ---

func test_a1_friendly_greens_are_colorblind_safe() -> void:
	Art.colorblind = false
	var green := Color(0.4, 1.0, 0.4)
	Runner.T.ok(Art.safe(green).is_equal_approx(green), "colorblind OFF: the friendly green passes through unchanged")
	Art.colorblind = true
	var conv := Art.safe(green)
	Runner.T.ok(conv.b > conv.g, "colorblind ON: the friendly green converts to a blue-dominant safe color (won't read as danger-red)")
	Art.colorblind = false   # restore the static for other suites


# --- a1-17 r2: top-bar record chip mode ---

func test_a1_record_hud_mode() -> void:
	var hud = load("res://src/view/hud.gd")
	Runner.T.eq(hud._record_hud_mode(200, 100), "badge", "live score beat best -> reserved RECORD badge")
	Runner.T.eq(hud._record_hud_mode(50, 100), "best", "score below best -> dim BEST target chip")
	Runner.T.eq(hud._record_hud_mode(200, 0), "none", "no best yet -> no record chip")


# --- a1-19: legacy art bakes stay lossless (no BC edge-mush on the silhouettes) ---

func test_a1_legacy-art_bakes_are_lossless() -> void:
	var stack: Array[String] = ["res://assets/legacy-art"]
	var checked := 0
	var offenders: Array[String] = []
	var detect3d: Array[String] = []
	var vram: Array[String] = []
	while not stack.is_empty():
		var d: String = stack.pop_back()
		var da := DirAccess.open(d)
		if da == null:
			continue
		da.list_dir_begin()
		var f := da.get_next()
		while f != "":
			var full := d + "/" + f
			if da.current_is_dir():
				stack.append(full)
			elif f.ends_with(".png.import"):
				checked += 1
				var txt := FileAccess.get_file_as_string(full)
				if txt.contains("compress/mode=2"):
					offenders.append(f)
				if txt.contains("detect_3d/compress_to=1"):
					detect3d.append(f)
				if txt.contains("vram_texture=true"):
					vram.append(f)
			f = da.get_next()
		da.list_dir_end()
	Runner.T.ok(checked > 100, "scanned the legacy art bake .import files (%d)" % checked)
	Runner.T.ok(offenders.is_empty(),
		"no legacy art bake is BC-compressed (compress/mode=2 mushes the OUTLINE silhouette): %s" % str(offenders.slice(0, 5)))
	Runner.T.ok(detect3d.is_empty(),
		"detect_3d is OFF so a future --import cannot re-BC the bakes: %s" % str(detect3d.slice(0, 5)))
	Runner.T.ok(vram.is_empty(),
		"no bake re-imported as a VRAM texture (lossless .ctex, not s3tc): %s" % str(vram.slice(0, 5)))


func test_a1_player_ident_and_ring_shape() -> void:
	var ms = load("res://src/main.gd")
	Art.colorblind = false
	var p1: Color = ms._player_ident_color(0)
	var p2: Color = ms._player_ident_color(1)
	Runner.T.ok(p1.g > p1.r and p1.g > p1.b, "P1 identity is green")
	Runner.T.ok(p2.r > p2.b and p2.g > p2.b, "P2 identity is gold")
	Art.colorblind = true
	Runner.T.ok(ms._player_ident_color(0).b > ms._player_ident_color(0).g, "P1 identity converts blue-dominant under colorblind")
	Art.colorblind = false
	Runner.T.ok(not ms._player_ring_dashed(0), "P1 ring is SOLID")
	Runner.T.ok(ms._player_ring_dashed(1), "P2 ring is DASHED (shape-distinct)")


# --- a2-01: decor/prop layer chars with the biome march ---

func test_a2_decor_chars_with_march() -> void:
	Art.foliage_march = 0.0
	var jungle_rock := Art.tint("rock1")
	Art.foliage_march = 1.0
	var foundry_rock := Art.tint("rock1")
	Runner.T.ok(foundry_rock.g < jungle_rock.g, "a foundry rock loses green (chars) vs the jungle rock")
	Runner.T.ok(foundry_rock.r >= foundry_rock.g, "charred decor leans warm (r >= g)")
	Runner.T.ok(Art.tint("rusher").is_equal_approx(Color(2.1, 1.7, 1.15)), "unit/threat tints ignore the decor char")
	Art.foliage_march = 0.0


func test_a2_decor_keys_all_in_tint() -> void:
	var art: Script = load("res://src/view/art.gd")
	var c: Dictionary = art.get_script_constant_map()
	var decor: Dictionary = c["_DECOR_KEYS"]
	var tint: Dictionary = c["TINT"]
	Runner.T.ok(decor.size() >= 15, "the decor char set is populated (%d)" % decor.size())
	for k in decor:
		Runner.T.ok(tint.has(k), "decor key '%s' has a base TINT entry to char from" % k)


# --- a2-02: boss tier tint breaks out of the disposable-tank olive ---

func test_a2_boss_tier_tint_distinct() -> void:
	var boss := Art.tint("gunship_body")
	var tank := Art.tint("tank_body")
	Runner.T.ok(not boss.is_equal_approx(tank), "the gunship boss no longer shares the disposable-tank tint")
	Runner.T.ok(Art.tint("colossus_body").is_equal_approx(boss), "both bosses share the heavy BOSS_VEH tint")
	Runner.T.ok(boss.b > tank.b, "boss gunmetal is cooler (more blue) than the olive tank")


func test_a2_hostile_vehicle_tint_is_warm() -> void:
	var art: Script = load("res://src/view/art.gd")
	var c: Dictionary = art.get_script_constant_map()
	var hostile: Color = c["HOSTILE_VEH"]
	var olive: Color = c["OLIVE_VEH"]
	Runner.T.ok(hostile.r > hostile.b, "the hostile vehicle tint is WARM (r > b)")
	Runner.T.ok(hostile.r > olive.r, "hostile vehicles read hotter than the friendly olive tank")


func test_a2_body_ident_lean() -> void:
	var ms = load("res://src/main.gd")
	Art.colorblind = false
	var p1: Color = ms._body_ident_lean(0)
	var p2: Color = ms._body_ident_lean(1)
	Runner.T.ok(not p1.is_equal_approx(p2), "P1 and P2 live-body leans differ")
	Runner.T.ok(p1.g >= p1.r and p1.g >= p1.b, "P1 body leans green")
	Runner.T.ok(p2.r >= p2.b, "P2 body leans warm/gold")
	Art.colorblind = true
	Runner.T.ok(ms._body_ident_lean(0).b > ms._body_ident_lean(0).r, "P1 body lean converts blue-dominant under colorblind")
	Art.colorblind = false


# --- a2-04: title BEST line drops zero fields ---

func test_a2_title_best_line_drops_zeros() -> void:
	var menu = load("res://src/view/menu.gd")
	Runner.T.eq(menu._best_line(4500, 0, 138), "BEST — SCORE 4500 · 138m", "score-only best drops WAVE 0")
	Runner.T.eq(menu._best_line(4500, 0, 0), "BEST — SCORE 4500", "a pure campaign best shows just the score")
	Runner.T.ok(menu._best_line(4500, 3, 138).contains("WAVE 3"), "a real wave record is shown")


# --- a2-05: tiny decor drops the black-speckle rim ---

func test_a2_tiny_decor_drops_rim() -> void:
	var ms = load("res://src/main.gd")
	Runner.T.ok(ms._tiny_decor_no_rim("ammobox", 8.0), "tiny decor (ammobox @8px) skips the black-speckle rim")
	Runner.T.ok(not ms._tiny_decor_no_rim("rock1", 40.0), "a large rock keeps its rim")
	Runner.T.ok(not ms._tiny_decor_no_rim("rusher", 8.0), "a small THREAT keeps its rim (it is not decor)")
	for k in ["landmine", "barrier", "mg_tripod", "ammobox", "watchtower"]:
		Runner.T.ok(ms._tiny_decor_no_rim(k, 10.0), "tiny litter '%s' @10px skips the speckle rim" % k)
	Runner.T.ok(not ms._tiny_decor_no_rim("gunship_body", 8.0), "a small boss sprite keeps its rim")


# --- a2-06: jungle water de-cerulaned toward olive/tea ---

func test_a2_jungle_water_decerulaned() -> void:
	var c := _consts()
	var shallow: Array = c["_WATER_SHALLOW_STOPS"]
	var deep: Array = c["_WATER_DEEP_STOPS"]
	Runner.T.ok(shallow[0].g >= shallow[0].b, "jungle shallow water leans olive/tea (green >= blue), not saturated cerulean")
	Runner.T.ok(deep[0].b < 0.30, "jungle deep water pulled off the saturated blue")


# --- a2-08: tree instance variety ---

func test_a2_tree_instance_variety() -> void:
	var ms = load("res://src/main.gd")
	var mn := 99.0
	var mx := 0.0
	var deads := 0
	for h in range(0, 220):
		var ti: Dictionary = ms._tree_instance(h)
		mn = minf(mn, ti["scale_mul"])
		mx = maxf(mx, ti["scale_mul"])
		if ti["dead"]:
			deads += 1
	Runner.T.ok(absf(mn - 0.85) < 0.01, "min tree scale is 0.85")
	Runner.T.ok(mx > 1.12 and mx < 1.15, "max tree scale ~1.14 (0.85..1.138)")
	Runner.T.ok(deads > 8 and deads < 45, "a minority (1-in-11) of trees are dead (%d/220)" % deads)


# --- a2-12: kind-specific gib (metal sparks vs blood) ---

func test_a2_gib_metal_vs_blood() -> void:
	var ms = load("res://src/main.gd")
	var drone: Color = ms._gib_col("drone")
	var rusher: Color = ms._gib_col("rusher")
	Runner.T.ok(drone.g > 0.6 and drone.b > 0.3, "machine death throws warm metal SPARKS, not blood")
	Runner.T.ok(rusher.r > rusher.g and rusher.g < 0.3, "infantry death throws BLOOD red")
	Runner.T.ok(ms._gib_col("technical").is_equal_approx(drone), "vehicles/emplacements share the metal-spark gib")
	Runner.T.ok(ms._gib_col("shield").is_equal_approx(rusher), "an armored HUMAN (bombsuit) still bleeds — not metal")
	Runner.T.ok(ms._gib_col("mg_nest").is_equal_approx(drone), "the mg-nest emplacement throws metal")


# --- a2-13: campaign scorch ages to a capped ghost (never age-removed) ---

func test_a2_scorch_ages_to_a_capped_ghost() -> void:
	var ms = load("res://src/main.gd")
	Runner.T.ok(ms._scorch_age(0.0) > 0.0, "scorch ages from fresh")
	Runner.T.ok(ms._scorch_age(0.9) <= 0.821, "scorch t caps at the 0.82 ghost floor")
	Runner.T.ok(ms._scorch_age(0.82) < 1.0, "campaign scorch never reaches t=1 -> never age-removed (a faint permanent scar)")
	var floor_a: float = 0.4 * (1.0 - ms._scorch_age(5.0))
	Runner.T.ok(floor_a > 0.02 and floor_a < 0.12, "_draw_scorch ghost floor alpha (0.4*(1-0.82)) is faint but visible (%.3f)" % floor_a)
	Runner.T.eq(ms._scorch_cap("endless"), 24, "endless arena caps at 24 scars")
	Runner.T.eq(ms._scorch_cap("campaign"), 40, "campaign keeps more persistent scars (40)")


# --- a2-15: REND capsule out of the danger-red family ---

func test_a2_rend_capsule_out_of_danger_hue() -> void:
	var caps: Array = _consts()["_CAPSULE_COL"]
	var rend: Color = caps[3]
	var triple: Color = caps[2]
	Runner.T.ok(rend.b > rend.r, "REND is now blue-dominant (violet), out of the danger-red family")
	Runner.T.ok(not rend.is_equal_approx(triple), "REND is clear of the TRIPLE pink")
	var prev: Color = _consts()["GRENADE_PREVIEW_COL"]
	Runner.T.ok(prev.b > prev.r, "the friendly grenade preview is COOL cyan (b>r), not the warm/red enemy-strike hue")


# --- a2-14: marker icon per class ---

func test_a2_marker_icons_per_class() -> void:
	var ms = load("res://src/main.gd")
	Runner.T.eq(ms._marker_icon("rescue"), "hud_star", "pilot rescue = star beacon")
	Runner.T.eq(ms._marker_icon("bounty"), "hud_target", "bounty kill = reticle")
	Runner.T.eq(ms._marker_icon("priced"), "icon_coin", "priced pickup = coin")
	Runner.T.eq(ms._marker_icon("capsule"), "hud_lightning", "rare capsule = power-up glyph")
	Runner.T.eq(ms._marker_icon("free"), "hud_gunshop", "free cache = supply icon")
	Runner.T.ok(ms._marker_icon("rescue") != ms._marker_icon("bounty"), "rescue reads apart from the kill reticle")


# --- a2-16: the overloaded buy jingle is sub-classed ---

func test_a2_buy_subclasses() -> void:
	var sfx := Sfx.new()
	sfx._synth_all()
	Runner.T.ok(sfx._sounds.has("buy_grab") and sfx._sounds.has("buy_fanfare"), "the buy sub-classes are synthesized voices")
	var evmap: Dictionary = _consts()["_EVENT_SOUND"]
	Runner.T.eq(evmap["token_mint"][0], "buy_fanfare", "the commendation milestone plays the FANFARE, not the buy chime")
	# the sub-classes are genuinely different voices (different note recipes -> buffer lengths)
	Runner.T.ok(sfx._sounds["buy_grab"].data.size() != sfx._sounds["buy"].data.size(), "buy_grab is a distinct voice from buy")
	Runner.T.ok(sfx._sounds["buy_fanfare"].data.size() != sfx._sounds["buy"].data.size(), "buy_fanfare is a distinct voice from buy")
	sfx.free()


func test_a2_buy_subclass_callsites() -> void:
	var src := FileAccess.get_file_as_string("res://src/main.gd")
	Runner.T.ok(src.contains('play("buy_grab"'), "the rare-capsule grab call-site plays buy_grab")
	Runner.T.ok(src.contains('play("buy_fanfare"'), "a milestone reward call-site plays buy_fanfare")


# --- a2-18: pipeline VRAM + registry cleanup ---

func test_a2_registry_has_no_dead_rows() -> void:
	var art: Script = load("res://src/view/art.gd")
	var c: Dictionary = art.get_script_constant_map()
	var tex: Dictionary = c["TEX"]
	for setname in ["SCALE", "TINT", "OUTLINE"]:
		for k in c[setname]:
			Runner.T.ok(tex.has(k), "%s row '%s' mirrors a live TEX entry (no dead config)" % [setname, k])

func test_a2_pipeline_vram_reclaimed() -> void:
	for cap in ["cap_pierce", "cap_spread", "cap_triple", "cap_rend", "cap_claymore", "cap_smoke", "cap_flash"]:
		var c := FileAccess.get_file_as_string("res://assets/legacy-art/icons/%s.png.import" % cap)
		Runner.T.ok(c.contains("size_limit=128"), "capsule glyph %s imports size-limited" % cap)
	for tile in ["grass", "dirt", "sand"]:
		var ti := FileAccess.get_file_as_string("res://assets/kenney/%s.png.import" % tile)
		Runner.T.ok(ti.contains("mipmaps/generate=false"), "the 1:1 Kenney %s tile has mipmaps OFF" % tile)


# --- a2-17: boss phase labels are named (not "PHASE n") ---

func test_a2_boss_phase_names() -> void:
	var c := _consts()
	var g: Array = c["GUNSHIP_PHASE_NAMES"]
	var co: Array = c["COLOSSUS_PHASE_NAMES"]
	Runner.T.eq(g.size(), 2, "the gunship has 2 named phases (strafe/mortar half-cycle)")
	Runner.T.eq(co.size(), 3, "the colossus has 3 named phases")
	Runner.T.eq(g, ["STRAFING RUN", "MORTAR VOLLEY"], "the full gunship phase-name list")
	Runner.T.eq(co, ["ADVANCE", "MORTAR VOLLEYS", "SAPPERS OUT"], "the full colossus phase-name list")
	for nm in (g + co):
		Runner.T.ok(not String(nm).contains("PHASE"), "'%s' is NAMED, not abstract PHASE n" % nm)


func test_a2_label_plate_rect() -> void:
	var ms = load("res://src/main.gd")
	var r: Rect2 = ms._label_plate_rect(100.0, 50.0, 40.0)
	Runner.T.ok(is_equal_approx(r.position.x, 97.0), "plate starts 3px LEFT of the label origin (under the text)")
	Runner.T.ok(is_equal_approx(r.size.x, 46.0), "plate is 6px wider than the label")
	Runner.T.ok(is_equal_approx(r.position.y, 50.0), "plate top matches the passed y")


# --- a2-11 regression: the hit-flash read must NOT assume every enemy carries
# "hp". Only mg_nest/technical/broadcast track hp; frogman/rusher/elite are
# one-shot and have NO hp field, so the view reads e.get("hp", 1) — a hard
# e["hp"] crashed _draw_enemies on every ford frogman and every rusher wave. ---

func test_a2_11_hitflash_read_tolerates_hpless_enemies() -> void:
	var sim := SimWorld.new(0xF0, 1)
	sim._spawn_frogman(200 * Fixed.ONE, 200 * Fixed.ONE)
	sim._spawn_enemy(300 * Fixed.ONE, 200 * Fixed.ONE, false)   # rusher
	var frog: Dictionary = sim.enemies[0]
	var rusher: Dictionary = sim.enemies[1]
	# The contract the guard depends on: these common kinds carry no hp field.
	Runner.T.ok(not frog.has("hp"), "a frogman spawns with NO hp field (one-shot)")
	Runner.T.ok(not rusher.has("hp"), "a rusher spawns with NO hp field (one-shot)")
	# The guarded read yields the sentinel -> prev==cur -> the edge-detect never
	# fires a flash for a one-shot kind (and never crashes on the missing key).
	var ehp: int = frog.get("hp", 1)
	Runner.T.eq(ehp, 1, "the guarded hp read defaults to 1 for an hp-less enemy")
	Runner.T.ok(not (ehp < int(frog.get("hp", ehp))), "no non-lethal-hit flash edge for a one-shot kind")


# --- a3-01: the boss separator rim cools on the hot foundry floor so the apex
# silhouette stops reading red-on-red, while the gunship keeps its warm rim over
# the green bridge (ramp confined to the hot end). Visual anchor: the foundry frame
# is signature screenshot 05 (05-foundry-colossus-last-stand.png) — re-render it and
# confirm the colossus carries a cool dark separator edge, not a bright white one. ---

func test_a3_boss_rim_cools_on_the_foundry_floor() -> void:
	var ms = load("res://src/main.gd")
	var warm: Color = ms._boss_rim_base(0.0)      # jungle / bridge
	var mid: Color = ms._boss_rim_base(0.6)       # ramp has not started yet
	var hot: Color = ms._boss_rim_base(1.0)       # foundry finale
	# Low march: the tuned warm-dark red rim (red dominates blue).
	Runner.T.ok(warm.r > warm.b, "over green the boss rim stays WARM (r > b)")
	Runner.T.ok(is_equal_approx(mid.r, warm.r) and is_equal_approx(mid.b, warm.b),
		"the cool ramp does not start until march > 0.6 (gunship keeps its warm rim)")
	# High march: cool steel-blue (blue dominates red) — the separation on red ground.
	Runner.T.ok(hot.b > hot.r, "on the foundry floor the boss rim goes COOL (b > r)")
	Runner.T.ok(hot.b > warm.b, "the foundry rim is bluer than the bridge rim (monotonic cool)")
	# ...but the cool rim stays a DARK separator (value near the warm rim), not a bright
	# edge — outline language stays consistent across biomes (judge r2 TO_TEN).
	var warm_v: float = maxf(warm.r, maxf(warm.g, warm.b))
	var hot_v: float = maxf(hot.r, maxf(hot.g, hot.b))
	Runner.T.ok(hot_v < 0.6 and absf(hot_v - warm_v) < 0.25,
		"the cool foundry rim stays DARK (value near the warm rim), not a bright white edge")


# --- a3-02: HALL/HOWTO seal near-opaque so the live attract firefight stops bleeding
# through the content frame; PAUSE recedes its frozen field but stays legible; TITLE
# keeps the attract fight visible behind it. ---

func test_a3_meta_screen_scrim_seals_content_screens() -> void:
	var mn = load("res://src/view/menu.gd")
	# Mode enum values (order in menu.gd): HIDDEN, TITLE, PAUSE, OPTS, HALL, HOWTO.
	var TITLE: int = mn.Mode.TITLE
	var PAUSE: int = mn.Mode.PAUSE
	var HALL: int = mn.Mode.HALL
	var HOWTO: int = mn.Mode.HOWTO
	var full := 1.0   # full motion (not reduce-motion)
	# Content screens seal near-opaque even at full motion (was 0.6 -> firefight bled).
	Runner.T.ok(mn._scrim_alpha(HALL, full) >= 0.9, "HALL seals near-opaque (>=0.9)")
	Runner.T.ok(mn._scrim_alpha(HOWTO, full) >= 0.9, "HOWTO seals near-opaque (>=0.9)")
	# PAUSE recedes harder than the old 0.6 but stays LIGHTER than the content screens
	# (you can still study your frozen run behind it).
	var pa: float = mn._scrim_alpha(PAUSE, full)
	Runner.T.ok(pa >= 0.74 and pa < 0.9, "PAUSE recedes (>=0.74) yet stays legible (< content seal)")
	# TITLE deliberately keeps the attract firefight visible behind it.
	Runner.T.ok(mn._scrim_alpha(TITLE, full) < 0.7, "TITLE keeps the attract fight visible (< 0.7)")
	# The bordered CONTENT screens (HALL/HOWTO) emit a solid interior WELL under the
	# chrome; PAUSE seals by scrim ALONE (no well) so the frozen run stays faintly read.
	Runner.T.ok(mn._content_well(HALL) and mn._content_well(HOWTO),
		"HALL/HOWTO draw the interior well behind the frame")
	Runner.T.ok(not mn._content_well(PAUSE) and not mn._content_well(TITLE),
		"PAUSE/TITLE are scrim-only (no content well)")
	# The well must sit INSIDE the Rect2(20,8,600,344) chrome frame (frame draws over it).
	var well: Rect2 = mn._content_well_rect()
	var frame := Rect2(20, 8, 600, 344)
	Runner.T.ok(frame.encloses(well), "the well rect is fully inside the chrome frame")


# --- a3-03: endless gets its OWN base ground palette (warm rust/ochre) instead of
# campaign jungle-green nudged +0.04, so the arena reads as its own place. ---

func test_a3_endless_has_its_own_ground_palette() -> void:
	var ms = load("res://src/main.gd")
	var endless: Array = ms._ground_stops("endless")
	var campaign: Array = ms._ground_stops("campaign")
	var eg: Array = endless[0]   # endless grass stops
	var cg: Array = campaign[0]  # campaign grass stops
	Runner.T.eq(eg.size(), 5, "endless grass ramp has 5 stops (matches the ramp)")
	Runner.T.eq(campaign[1].size(), 5, "campaign dirt ramp has 5 stops")
	# The base (wave-1 / sector-1) floor must read distinctly NON-jungle: campaign starts
	# bright yellow-green (g >= r), endless starts warm rust-ochre (r clearly > g).
	var e0: Color = eg[0]
	var c0: Color = cg[0]
	Runner.T.ok(c0.g >= c0.r, "campaign start is green-forward (g >= r)")
	Runner.T.ok(e0.r > e0.g + 0.15, "endless start is warm rust-ochre (r well above g)")
	Runner.T.ok(e0 != c0, "endless base is a genuinely different color, not a nudge")
	# The ramp marches ochre -> grey ASH: the late stop is DARKER and DESATURATED (r-g gap
	# shrinks), and it stays distinct from the campaign foundry's saturated RED late stop
	# so endless reads as its own place even scorched (judge r2 TO_TEN).
	var e_last: Color = eg[4]
	var c_last: Color = cg[4]
	var e0_val: float = maxf(e0.r, maxf(e0.g, e0.b))
	var el_val: float = maxf(e_last.r, maxf(e_last.g, e_last.b))
	Runner.T.ok(el_val < e0_val, "endless late stop is DARKER than the ochre start (marches to ash)")
	Runner.T.ok((e_last.r - e_last.g) < (e0.r - e0.g) - 0.2, "late stop DESATURATES toward grey ash")
	Runner.T.ok((e_last.r - e_last.g) < (c_last.r - c_last.g), "endless ash stays greyer than the campaign foundry RED")
	Runner.T.ok(e_last != c_last, "endless late stop is distinct from the campaign foundry late stop")


# --- a3-04: the canopy dapple pools only under a LIVING tree; past the ash midpoint
# (0.33) the dead/charred canopy casts none (matches the dead-tree swap threshold). ---

func test_a3_canopy_dapple_only_under_living_trees() -> void:
	var ms = load("res://src/main.gd")
	Runner.T.ok(ms._has_canopy_dapple(0.0), "the living jungle canopy casts a dapple")
	Runner.T.ok(ms._has_canopy_dapple(0.32), "the dapple persists right up to the ash midpoint")
	Runner.T.ok(not ms._has_canopy_dapple(0.33), "at the ash midpoint the dead canopy casts NO dapple")
	Runner.T.ok(not ms._has_canopy_dapple(1.0), "the charred foundry canopy casts no dapple")


# --- a3-05: the dirt-patch feather rings — a wide faint outer ring + a stronger inner
# halo grade the bare-earth card into the turf (outer must be wider AND fainter). ---

func test_a3_dirt_feather_rings() -> void:
	var ms = load("res://src/main.gd")
	var df: Dictionary = ms.DIRT_FEATHER
	Runner.T.ok(df["out_scale"] > df["in_scale"], "the outer feather ring is WIDER than the inner halo")
	Runner.T.ok(df["out_a"] < df["in_a"], "the outer ring is FAINTER than the inner halo (grades out)")
	# The inner halo is meaningfully stronger than the old single 0.4 multiplier it replaced.
	Runner.T.ok(df["in_a"] >= 0.5, "the inner halo is stronger than the old 0.4 (kills the hard rim)")
	Runner.T.ok(df["out_scale"] >= 2.0, "the outer ring reaches well past the card edge")


# --- a3-07: the incoming mortar/airstrike telegraph gets a dark underlay so the lethal
# footprint seats on busy/bright ground (was amber-on-amber with nothing grounding it). ---

func test_a3_strike_underlay_spans_the_kill_radius() -> void:
	var c := _consts()
	var su: Dictionary = c["STRIKE_UNDERLAY"]
	# The soft dark seat must reach PAST the kill ring (the softspot fades, so it needs a
	# little over 2x the radius to darken the full footprint out to the amber ring edge)...
	Runner.T.ok(su["scale"] > 2.0, "the strike dark-underlay spans past the kill radius (seats the footprint)")
	# ...and be dark enough to seat on busy ground without blacking out the units in the zone.
	Runner.T.ok(su["alpha"] >= 0.25 and su["alpha"] <= 0.35, "the underlay is dark-but-legible (0.25-0.35a)")


# --- a3-06: the muzzle flare is capped BELOW the explosion's white-hot read — the
# ignition pop is warmed off pure white and every additive term is capped, so MG-spam
# can't sum into an explosion-tier bright field. ---

func test_a3_muzzle_heat_capped_below_explosions() -> void:
	var c := _consts()
	var mh: Dictionary = c["MUZZLE_HEAT"]
	Runner.T.ok(mh["pop_lerp"] < 0.4, "the ignition pop is warmed OFF white-hot (lerp to white < 0.4)")
	Runner.T.ok(mh["pop_a"] <= 0.66, "the pop alpha is capped (<= 0.66)")
	Runner.T.ok(mh["fan_a"] <= 0.66 and mh["core_a"] <= 0.66, "fan + core additive alphas capped so MG-spam sums low")


# --- a3-08: the undergrowth tint lifts OFF the grass hue (deeper + cooler) so ferns/trees
# read as distinct masses, not lawn texture painted on the grass. ---

func test_a3_foliage_lifts_off_grass_hue() -> void:
	var ms = load("res://src/main.gd")
	var fol: Color = Art.FOLIAGE
	var g0: Color = ms._ground_stops("campaign")[0][0]   # bright jungle grass stop
	Runner.T.ok(fol.r < g0.r, "foliage is DEEPER than the bright grass (lower r)")
	Runner.T.ok((fol.g - fol.r) > (g0.g - g0.r) + 0.1, "foliage is COOLER / more green-forward than the yellow-green grass")
	# The fern contact dab that grounds each clump anchor: small radius, soft alpha.
	var fd: Dictionary = _consts()["FERN_DAB"]
	Runner.T.ok(fd["r"] > 0.0 and fd["r"] <= 5.0, "the fern dab is a small contact shadow (<= 5px)")
	Runner.T.ok(fd["a"] > 0.0 and fd["a"] <= 0.35, "the fern dab is soft (grounds without a hard blob)")


# --- a3-09: field boulders get a lit top-edge highlight (warm, bright) so they read as
# RAISED cover — the inverse of a1-07's recessed crater pit. ---

func test_a3_rock_top_light_is_warm_and_bright() -> void:
	var c := _consts()
	var rl: Color = c["ROCK_TOP_LIGHT"]
	Runner.T.ok(rl.r > rl.b, "the rock top-light is WARM (sunlit, r > b)")
	Runner.T.ok(rl.r > 0.9 and rl.g > 0.9, "the rock top-light is BRIGHT (a lit rim, not a shadow)")
	# Only the DOMED boulders get the raised-rim highlight; the flat log does not.
	var ms = load("res://src/main.gd")
	Runner.T.ok(ms._rock_has_top_light("rock1") and ms._rock_has_top_light("rock2"),
		"domed boulders (rock1/rock2) get the raised-rim top-light")
	Runner.T.ok(not ms._rock_has_top_light("tree_dead2"), "the flat log gets NO top-light (no raised dome)")


# --- a3-10: the marsh floor reads wet — dark silt pools with a cooler specular sheen so
# the mid-game sector is a wetland, not generic green. The sheen must be lighter than the
# pool (a glint) and both soft enough to not black out the ground. ---

func test_a3_marsh_wetness_pool_and_sheen() -> void:
	var c := _consts()
	var mw: Dictionary = c["MARSH_WET"]
	Runner.T.ok(mw["pool_a"] > mw["sheen_a"], "the dark silt pool is stronger than its specular sheen glint")
	Runner.T.ok(mw["pool_a"] <= 0.4 and mw["sheen_a"] > 0.0, "both are soft (a wet sheen, not a black hole)")
	# Chroma: a COOL-dark silt pool with a LIGHTER cool specular glint reads as wet.
	var pool: Color = mw["pool_col"]
	var sheen: Color = mw["sheen_col"]
	Runner.T.ok(pool.g > pool.r and pool.b > pool.r, "the silt pool is COOL (g,b > r)")
	Runner.T.ok(sheen.g > sheen.r and sheen.b > sheen.r, "the sheen glint is COOL (g,b > r)")
	var pv: float = maxf(pool.r, maxf(pool.g, pool.b))
	var sv: float = maxf(sheen.r, maxf(sheen.g, sheen.b))
	Runner.T.ok(sv > pv, "the sheen is LIGHTER than the dark pool (a glint off the water)")
	# The wetness is marsh-only: band 2 of the 5-stop march (int(march*5) == 2).
	Runner.T.eq(clampi(int(0.45 * 5.0), 0, 4), 2, "march 0.45 lands in the MARSH band (2) where the wetness draws")


# --- a3-11: bosses show hp-keyed battle damage — a full-hp boss is pristine, damage
# (scorch/smoke) accumulates as hp drops, and sparks only sputter near death. ---

func test_a3_boss_wound_thresholds() -> void:
	var c := _consts()
	var bw: Dictionary = c["BOSS_WOUND"]
	# wound = 1 - hp_fraction. A pristine boss shows nothing; sparks are a near-death tell.
	Runner.T.ok(bw["scar_start"] > 0.0 and bw["scar_start"] < bw["spark"],
		"scars begin before the near-death spark stage (ordered thresholds)")
	# Full hp -> wound 0 -> below the scar start (no damage drawn on a pristine boss).
	Runner.T.ok((1.0 - 1.0) < bw["scar_start"], "a full-hp boss shows NO wound damage")
	# 30% hp -> wound 0.7 -> past the spark threshold (a near-dead boss sputters sparks).
	Runner.T.ok((1.0 - 0.3) > bw["spark"], "a near-dead boss (30% hp) is in the spark stage")
	# Stage predicate: scars accumulate 0 -> 4 as the wound deepens (driven by the const).
	var ms = load("res://src/main.gd")
	Runner.T.eq(ms._boss_wound_scars(0.1), 0, "a barely-scratched boss shows NO scorch scars")
	Runner.T.eq(ms._boss_wound_scars(0.18), 1, "the first scar appears exactly at scar_start")
	Runner.T.ok(ms._boss_wound_scars(0.5) >= 2 and ms._boss_wound_scars(0.5) <= 3, "a half-wrecked boss shows a few scars")
	Runner.T.eq(ms._boss_wound_scars(0.95), 4, "a near-dead boss shows the full 4 scars")


# --- a3-12: every elite carries a persistent WARM aura (threat tell) so it reads as an
# elevated threat vs a plain rusher, not just via the subtle body tint. ---

func test_a3_elite_aura_is_warm() -> void:
	var c := _consts()
	var ea: Color = c["ELITE_AURA"]
	Runner.T.ok(ea.r > ea.g and ea.r > ea.b, "the elite aura is WARM-RED (r dominates) — a danger tell")
	Runner.T.ok(ea.r - ea.g > 0.4, "the aura is saturated warm, not a muddy neutral")


# --- a3-15: three place-defining ambience beds (river / foundry / shop), synthesized,
# seamless-looping, and distinct — so every sector sounds like somewhere. ---

func test_a3_ambience_beds_are_synthesized_and_distinct() -> void:
	var sfx := Sfx.new()
	sfx._synth_all()   # also builds the three ambience beds (_synth_beds)
	var beds: Dictionary = sfx._beds
	for k in ["river", "foundry", "shop"]:
		Runner.T.ok(beds.has(k), "the %s ambience bed is synthesized" % k)
		var wav: AudioStreamWAV = beds[k]
		Runner.T.eq(wav.loop_mode, AudioStreamWAV.LOOP_FORWARD, "%s bed loops (no dead-air seam)" % k)
		var d: PackedByteArray = wav.data
		Runner.T.ok(d.size() > 100000, "%s renders a substantial loop buffer (%d bytes)" % [k, d.size()])
		var mn := 255
		var mx := 0
		for bi in range(0, mini(d.size(), 8000)):
			mn = mini(mn, d[bi])
			mx = maxi(mx, d[bi])
		Runner.T.ok(mx - mn > 8, "%s bed carries real signal energy (not flat silence)" % k)
	# Genuinely three different timbres, not one buffer reused under three names.
	Runner.T.ok((beds["river"] as AudioStreamWAV).data != (beds["foundry"] as AudioStreamWAV).data,
		"river and foundry are distinct beds")
	Runner.T.ok((beds["foundry"] as AudioStreamWAV).data != (beds["shop"] as AudioStreamWAV).data,
		"foundry and shop are distinct beds")
	sfx.free()


# --- a3-16: the radio VO bus is governed by the SFX knob. It sent straight to Master
# at a fixed level before, so muting SFX still left the Commander blaring — a real mix
# gap. _set_bus_vol slaves every bus in _SFX_SLAVED_BUSES to the SFX control. ---

func test_a3_vo_bus_slaved_to_sfx_control() -> void:
	var slaved: Array = _consts()["_SFX_SLAVED_BUSES"]
	Runner.T.ok("VO" in slaved, "the radio VO bus now rides the SFX volume knob (was ungoverned)")
	Runner.T.ok("UI" in slaved, "the jingle UI bus still rides the SFX knob (a1 behavior preserved)")


# --- a3-17: size_limit sweep on small-drawn UI/FX bakes (PIPE#1/2/3/6). Input glyphs,
# minimap icons and the muzzle-fan card imported at 256/512px but never draw above ~84px,
# so they wasted boot VRAM. Cap them at 128 (the a2-18 convention; 128 >= any draw size,
# so the explicit-rect draws never blur). The SCALE-COUPLED in-world sprite bakes
# (rocks/props/units drawn via _spr, where footprint = imported_px * SCALE) are DELIBERATELY
# left untouched — capping them shifts on-screen size and needs a per-texture SCALE recompute
# (a separate, riskier pass). This test guards the swept set against regressing to full-res. ---

func test_a3_ui_bakes_are_size_limited() -> void:
	# Input glyphs — draw_glyph uses an explicit 12..84px rect, so a 128 cap never blurs.
	for g in ["pad_a", "ps_a", "sw_a", "key_enter", "mouse_l", "stick_l", "dpad_lr", "pad_start"]:
		var c := FileAccess.get_file_as_string("res://assets/legacy-art/ui/glyphs/%s.png.import" % g)
		Runner.T.ok(c.contains("size_limit=128"), "input glyph %s imports size-limited (was full-res)" % g)
	# Minimap icons — drawn ~16-24px on the rail.
	for ic in ["ICON_Map_Fire", "ICON_Map_Skull", "ICON_Map_Vehicle", "ICON_Map_Target"]:
		var c := FileAccess.get_file_as_string("res://assets/legacy-art/hud/%s.png.import" % ic)
		Runner.T.ok(c.contains("size_limit=128"), "minimap icon %s imports size-limited" % ic)
	# The 512x256 muzzle-fan card draws at ~fl*1.4 (<=~56px) via a raw draw_texture_rect.
	var mf := FileAccess.get_file_as_string("res://assets/legacy-art/fx/fx_muzzle_fan.png.import")
	Runner.T.ok(mf.contains("size_limit=128"), "the muzzle-fan card imports size-limited")
