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
	Runner.T.ok(shallow[0].is_equal_approx(Color(0.21, 0.44, 0.47)), "jungle shallow stays teal")
	# the journey actually MOVES: the foundry water must be far from the jungle water
	# (the old capped soot-lerp left it muddy-blue). Warm/red foundry vs cool jungle.
	Runner.T.ok(deep[4].r > deep[0].r + 0.1, "foundry deep water is warmer (redder) than jungle")
	Runner.T.ok(deep[4].b < deep[0].b - 0.1, "foundry deep water is far less blue than jungle")
	# mid-stops carry their biome, not just the endpoints (judge a1-03 r2):
	Runner.T.ok(shallow[2].g > shallow[2].b and shallow[2].g > shallow[2].r,
		"marsh (sector 2) shallow leans GREEN — murk, not blue")
	Runner.T.ok(deep[3].b < deep[0].b - 0.08 and absf(deep[3].r - deep[3].g) < 0.06,
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
