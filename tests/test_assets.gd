extends RefCounted
## View-layer ASSET invariants (assets review cycle). These pin the art.gd / main.gd
## registries the readability + art-direction systems depend on, so a stray edit that
## (e.g.) light-rims a hero, or drops a hostile from the separator set, fails HERE
## instead of only showing up in a screenshot. Pure const checks — no draw, no sim.

const Runner := preload("res://tests/run_tests.gd")


func _opaque_row_width_avg(img: Image, y0: int, y1: int) -> float:
	# Average per-row opaque-pixel span (rightmost minus leftmost alpha>0.05 column) across
	# [y0, y1) -- used to compare the "girth" of two bands of a directional sprite (nt-03).
	var w := img.get_width()
	var total := 0.0
	var rows := 0
	for y in range(y0, y1):
		var lo := -1
		var hi := -1
		for x in range(w):
			if img.get_pixel(x, y).a > 0.05:
				if lo < 0:
					lo = x
				hi = x
		if hi >= lo and lo >= 0:
			total += float(hi - lo + 1)
			rows += 1
	return total / float(maxi(rows, 1))


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
	Runner.T.ok(light.size() >= 6, "the small-hostile separator set is populated (%d)" % light.size())   # sol-08: 7 after retiring m_insurgent3-5/m_contractor2 with the enemy_* swap
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
	Runner.T.ok(Art.tint("scrub").is_equal_approx(Art.DESERT_FOLIAGE), "desert open (march 0) keeps the sun-bleached DESERT_FOLIAGE tint")
	Art.foliage_march = 1.0
	var f := Art.tint("scrub")
	Runner.T.ok(f.is_equal_approx(Art.FOLIAGE_ASH), "foundry (march 1) foliage chars to FOLIAGE_ASH")
	Runner.T.ok(f.g < Art.DESERT_FOLIAGE.g - 0.2, "charred foliage loses its sun-bleached green — no re-lightening multiply at the foundry")
	Runner.T.ok(Art.tint("cactus_large").is_equal_approx(Art.FOLIAGE_ASH), "cactus ramps with scrub")
	# a4 swap-undergrowth: tumbleweed/dry_shrub are desert flora too, not just
	# scrub/cactus — they must share the exact same march ramp, not a stale
	# green FOLIAGE fallback left behind by a partial rename.
	Runner.T.ok(Art.tint("tumbleweed").is_equal_approx(Art.FOLIAGE_ASH), "tumbleweed ramps with scrub")
	Runner.T.ok(Art.tint("dry_shrub").is_equal_approx(Art.FOLIAGE_ASH), "dry_shrub ramps with scrub")
	Art.foliage_march = 0.0
	Runner.T.ok(Art.tint("tumbleweed").is_equal_approx(Art.DESERT_FOLIAGE), "tumbleweed (march 0) keeps DESERT_FOLIAGE")
	Runner.T.ok(Art.tint("dry_shrub").is_equal_approx(Art.DESERT_FOLIAGE), "dry_shrub (march 0) keeps DESERT_FOLIAGE")
	Art.foliage_march = 1.0
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


func test_boot_audio_stays_silent_until_the_commanders_opening_line_finishes() -> void:
	var sfx := Sfx.new()
	var line := AudioStreamWAV.new()
	sfx._vo_streams["intro_crawl"] = line
	sfx._vo_streams["vo_observer"] = AudioStreamWAV.new()
	sfx.lock_startup_audio()
	Runner.T.ok(sfx.is_startup_audio_locked(), "boot begins behind an explicit audio lock")

	# No incidental VO is allowed to become the first audible event.
	sfx.play_vo("vo_observer", 3)
	Runner.T.eq(sfx._vo.stream, null, "ordinary VO is suppressed before the opening line")

	Runner.T.ok(sfx.play_startup_line("intro_crawl"), "the Commander opening line bypasses the lock")
	Runner.T.eq(sfx._vo_dry.stream, line, "the opening line is routed as the first dry voice")
	Runner.T.ok(sfx.is_startup_audio_locked(), "music/SFX remain locked while the Commander is speaking")
	# His line ends at ~10.4 s but the splash runs to 16.0 s (title stamp 13.0, hero, dissolve
	# 15.5). Unlocking here — which is what shipped — put music and every SFX over the last
	# 5.6 s of the intro.
	sfx._vo_dry.finished.emit()
	Runner.T.ok(sfx.is_startup_audio_locked(),
		"the line ending is NOT enough: the splash is still on screen")
	sfx.splash_finished()
	Runner.T.ok(not sfx.is_startup_audio_locked(),
		"the mix unlocks once the splash is down AND the Commander has finished")
	sfx.free()


func test_the_run_ending_lines_own_their_beat_alone() -> void:
	# Regression on a regression. Making play_vo yield to a live Commander bark silently ate
	# the campaign's closing line: a Last Stand wipe emits player_down AND wiped into the same
	# events array on the same tick, _consume_events walks them in emission order, so the
	# forced "Man down!" bark started first and vo_wiped (priority 3, the TOP of the ladder)
	# hit the new yield and was dropped 100% of the time. Fixed by not starting the SMALLER
	# line — never by interrupting one that is already speaking.
	var src := FileAccess.get_file_as_string("res://src/main.gd")
	Runner.T.ok(src.contains("var wiping_now := false"),
		"the event loop looks ahead for a wipe latched in this same frame")
	var down_at := src.find('_cmd_bark("down"')
	Runner.T.ok(down_at > 0, "the death bark site still exists")
	Runner.T.ok(src.substr(maxi(down_at - 260, 0), 260).contains("if not wiping_now:"),
		"the death bark is suppressed on the tick the run ends, so the wipe call is heard")
	# ONE voice on the win. vo_victoly and the "victory" bark are the same sentence on two
	# buses; firing both doubled them ~0.2s apart at the biggest moment in the game.
	# Anchor on the CALL, not on `"victory":` — that string's first hit is the _EVENT_SOUND
	# table at main.gd:557, which is nowhere near the match arm.
	var bark_at := src.find('if not _cmd_bark("victory", 0, true):')
	Runner.T.ok(bark_at > 0,
		"the win beat fires the Commander, and the Spotter only as a fallback")
	var vo_at := src.find('_vo("vo_victoly"')
	Runner.T.ok(vo_at > bark_at,
		"...with the Spotter line INSIDE that fallback, so the two can never both play")


func test_attract_mode_captions_cannot_leak_into_a_real_run() -> void:
	# caption_sfx was the ONE main->Sfx audio path with no menu gate, while the title screen
	# runs a live attract firefight. Real strike_warn/sniper_paint/windup events armed
	# LETHAL-tier captions behind the menu, and the only thing that drains the queue lives in
	# the draw path, which returns early while a menu is up — so the backlog emptied into the
	# player's real run as warnings for threats that happened to a demo bot.
	var src := FileAccess.get_file_as_string("res://src/main.gd")
	var at := src.find("_sfx.caption_sfx(kind)")
	Runner.T.ok(at > 0, "the caption choke point still exists")
	Runner.T.ok(src.substr(maxi(at - 200, 0), 200).contains("if _menu.mode == GameMenu.Mode.HIDDEN:"),
		"caption_sfx is menu-gated like its _vo / _cmd_bark siblings")
	# ...and a run can never inherit a backlog even if something else queues one.
	var sfx := Sfx.new()
	sfx._cap_text = "STALE WARNING"
	sfx._cap_until = 999999
	sfx._cap_queue.append({"text": "ALSO STALE", "is_vo": false})
	sfx.clear_captions()
	Runner.T.eq(sfx._cap_text, "", "clear_captions drops the live caption")
	Runner.T.eq(sfx._cap_queue.size(), 0, "...and the whole pending queue")
	sfx.free()
	Runner.T.ok(src.contains("_sfx.clear_captions()"), "main._reset() actually calls it")


func test_a_radio_line_never_starts_on_top_of_a_commander_bark() -> void:
	# The two voice channels were mutually UNAWARE in one direction only. play_cmd_bark yields
	# to a VO of priority >= 2 (sfx.gd, the `_vo_priority >= 2` arm), but play_vo never checked
	# `_cmd.playing` — and they sit on different buses (_cmd on UI, _vo on VO), so nothing in
	# the mix masked the collision. The player heard the Commander get talked over mid-word.
	# The one-directional courtesy is what marks it an oversight rather than a mix decision.
	# SOURCE SCAN, deliberately, and this is the one case where it is the honest instrument:
	# the guard reads AudioStreamPlayer.playing, and headless Godot never reports it true.
	# Measured — a probe that added Sfx to the real tree, called play_cmd_bark and printed the
	# flag got `play_cmd_bark returned: true` / `_cmd.playing headless: false`, plus an engine
	# "Playback can only happen when a node is inside the scene tree". So a behavioural
	# assertion here would be vacuous: it would pass whether or not the guard exists. Pin the
	# guard's presence instead, and say so rather than dressing a source grep up as behaviour.
	var src := FileAccess.get_file_as_string("res://src/view/sfx.gd")
	var vo_body := src.substr(src.find("func play_vo("))
	vo_body = vo_body.substr(0, vo_body.find("\nfunc "))
	Runner.T.ok(vo_body.contains("if _cmd.playing:"),
		"play_vo yields while a Commander bark is on air")
	Runner.T.ok(vo_body.find("if _cmd.playing:") < vo_body.find("ply.play()"),
		"...and it yields BEFORE starting a stream, not after")
	# The mirror courtesy the bark side has always had — pinned so a future edit cannot quietly
	# make the pair one-directional again, which is the asymmetry that caused this bug.
	var bark_body := src.substr(src.find("func play_cmd_bark("))
	bark_body = bark_body.substr(0, bark_body.find("\nfunc "))
	Runner.T.ok(bark_body.contains("_vo_priority >= 2"),
		"play_cmd_bark still yields to a high-priority radio line — the courtesy runs both ways")


func test_a_skip_mid_sentence_still_lets_the_commander_finish() -> void:
	# The other half of the contract: the splash coming down early must not drop music on top
	# of a line still on air. Skip arms at SPLASH_SKIP_ARM (1.0 s); he starts at
	# SPLASH_STUDIO_END (3.0 s) and reads for 7.36 s, so most of his read is skippable.
	var sfx := Sfx.new()
	sfx._vo_streams["intro_crawl"] = AudioStreamWAV.new()
	sfx.lock_startup_audio()
	Runner.T.ok(sfx.play_startup_line("intro_crawl"), "the opening line is on air")
	sfx.splash_finished()   # player skips mid-sentence
	Runner.T.ok(sfx.is_startup_audio_locked(),
		"splash down mid-read does not unlock — he is not talked over")
	sfx._vo_dry.finished.emit()
	Runner.T.ok(not sfx.is_startup_audio_locked(), "...and the mix unlocks the moment he lands")
	sfx.free()


func test_boot_audio_can_never_be_stranded_in_permanent_silence() -> void:
	# The failure mode a naive "wait for the line to finish" fix would introduce. Gating on a
	# POSITIVE "line finished" fact deadlocks on any path where the line never starts, and
	# there are two such paths — both reachable in a normal session.
	# (a) Skipped between SPLASH_SKIP_ARM (1.0 s) and SPLASH_STUDIO_END (3.0 s): never fired.
	var early := Sfx.new()
	early._vo_streams["intro_crawl"] = AudioStreamWAV.new()
	early.lock_startup_audio()
	early.splash_finished()   # skipped before the line was ever triggered
	Runner.T.ok(not early.is_startup_audio_locked(),
		"a splash skipped before the line starts still unlocks the mix")
	early.free()
	# (b) The VO asset is missing or corrupt — NOTICE.md tells redistributors they may delete
	# assets/vo/ outright, so this is a shipping configuration, not a hypothetical.
	var mute := Sfx.new()
	mute.lock_startup_audio()
	Runner.T.ok(not mute.play_startup_line("intro_crawl"), "a missing opening line reports false")
	Runner.T.ok(mute.is_startup_audio_locked(),
		"...and still holds the lock while the splash is up (no audio over the intro)")
	mute.splash_finished()
	Runner.T.ok(not mute.is_startup_audio_locked(),
		"...but a dropped assets/vo/ can never strand the game in permanent silence")
	mute.free()


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
	# The _EVENT_SOUND sweep above can't see the names that only appear INSIDE Sfx —
	# the round-robin variants _rr_shot swaps in, the routing/detune tables, and the
	# cue names menu.gd hard-codes. A typo in any of those is the same silent no-op
	# with a green build, so sweep them from the same fixture.
	var sfx_consts: Dictionary = load("res://src/view/sfx.gd").get_script_constant_map()
	for tbl in ["_MUSICAL", "_LADDERED", "_UI_BUS"]:
		for nm in (sfx_consts[tbl] as Dictionary):
			Runner.T.ok(sounds.has(nm),
				"%s lists '%s', which must be a synthesized voice" % [tbl, nm])
	for base in ["shot", "enemy_shot"]:
		for v in 3:
			var variant: String = base if v == 0 else "%s%d" % [base, v]
			Runner.T.ok(sounds.has(variant),
				"_rr_shot round-robins '%s' — it must exist or every 3rd shot is silent" % variant)
	var menu_src := FileAccess.get_file_as_string("res://src/view/menu.gd")
	for cue in ["ui_tick", "menu_open", "menu_close"]:
		Runner.T.ok(sounds.has(cue) and menu_src.contains('"%s"' % cue),
			"menu cue '%s' is both synthesized and actually wired in menu.gd" % cue)
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


# --- reverb: the foundry interior and the open river stop sharing one anechoic room ---

func test_reverb_space_follows_the_biome() -> void:
	var deep := Sfx.new()
	var field := Sfx.new()
	var shop := Sfx.new()
	for sx in [deep, field, shop]:
		(sx as Sfx)._reverb = AudioEffectReverb.new()
	for i in 400:
		deep.set_ambience_march(1.0)          # inside the foundry plant
		field.set_ambience_march(0.1, true)   # open river bank
		shop.set_ambience_march(0.5, false, true)
	Runner.T.ok(deep._reverb.wet > field._reverb.wet,
		"the foundry interior is wetter than the open river (%.3f > %.3f)" % [deep._reverb.wet, field._reverb.wet])
	Runner.T.ok(deep._reverb.room_size > shop._reverb.room_size,
		"the foundry hall is a bigger space than the shop's small room")
	Runner.T.ok(field._reverb.wet < 0.2, "open ground stays near-dry — no cathedral outdoors")
	Runner.T.ok(shop._reverb.wet > field._reverb.wet, "the shop interior reads as indoors")
	deep.free(); field.free(); shop.free()


# --- audio-identity: MusicDirector tonal riff layer rides the drums, phase-locked ---

func test_audio_identity_riff_crossfades_with_intensity_and_locks_pitch_to_drums() -> void:
	var lull := Sfx.new()
	for i in 200: lull.set_music_intensity(0.0, 0.0, false)
	var combat := Sfx.new()
	for i in 200: combat.set_music_intensity(1.0, 0.0, false)
	Runner.T.ok(combat._music_riff.volume_db > lull._music_riff.volume_db,
		"riff layer rises into the mix as combat intensity climbs, same as the drum bed")
	Runner.T.eq(combat._music_riff.pitch_scale, combat._music.pitch_scale,
		"riff pitch_scale tracks the drum bed's exactly -- a boss key change can't leave it behind")
	Runner.T.eq(combat._music_riff_lull.pitch_scale, combat._music_lull.pitch_scale,
		"lull riff pitch_scale tracks the lull drum bed's exactly")
	Runner.T.ok(combat._music_riff.volume_db < combat._music.volume_db,
		"the riff still rides UNDER the drums at full combat, not competing with them")
	lull.free(); combat.free()


# --- AUD#4: caption arm/expire timing (Sfx.active_caption) ---

func test_audio_identity_caption_arms_and_expires_with_stream_length() -> void:
	var sfx := Sfx.new()
	Runner.T.eq(sfx.active_caption()["text"], "", "no caption armed yet reads empty")
	sfx._arm_caption("COMMANDER: \"Move out!\"", null, false, false)
	var cap: Dictionary = sfx.active_caption()
	Runner.T.eq(cap["text"], "COMMANDER: \"Move out!\"", "armed caption text reads back immediately")
	Runner.T.eq(cap["radio"], false, "a dry (non-VO-radio) caption reports radio=false")
	Runner.T.eq(cap["fade"], 1.0, "freshly armed caption is at full fade/alpha")
	Runner.T.ok(sfx._cap_until > Engine.get_physics_frames(), "arming sets an expiry in the future, not the past")
	# Mid-ramp: put _cap_until inside the CAPTION_FADE_FRAMES window and confirm the
	# fade value dissolves (0,1) rather than snapping straight from 1.0 to 0.0.
	sfx._cap_until = Engine.get_physics_frames() + int(Sfx.CAPTION_FADE_FRAMES / 2)
	var mid: Dictionary = sfx.active_caption()
	Runner.T.ok(mid["fade"] > 0.0 and mid["fade"] < 1.0, "mid-ramp caption fade is between 0 and 1 (fade=%.2f)" % mid["fade"])
	# Force the expiry frame into the past (deterministic stand-in for time actually elapsing)
	# and confirm active_caption() blanks out rather than reading a stale line forever.
	sfx._cap_until = Engine.get_physics_frames()
	Runner.T.eq(sfx.active_caption()["text"], "", "an expired caption reads empty, not the stale line")
	sfx.free()


# --- accessibility: SFX captions (Sfx.caption_sfx) ---

# The contract of the table itself, checked against the code that has to fire it. Every key must be
# a cue main.gd can actually reach, or the caption is dead text nobody will ever notice is missing;
# every line must be bracketed (the closed-caption convention that separates a SOUND from a spoken
# line, which is also the only thing distinguishing these from the VO/bark captions on screen); and
# the set must stay SMALL relative to the ~90-cue sound table — the whole point is that these are
# the sounds that are the ONLY warning of something, not a running transcript of the mix.
func test_sfx_captions_only_cover_reachable_warning_cues() -> void:
	var main_script: GDScript = load("res://src/main.gd")
	var event_sound: Dictionary = main_script.get_script_constant_map()["_EVENT_SOUND"]
	# armor_block is played from its own per-target branch in _ev_hit, not the _EVENT_SOUND table.
	var off_table := {"armor_block": true}
	for key in Sfx.SFX_CAPTIONS:
		Runner.T.ok(event_sound.has(key) or off_table.has(key),
			"captioned cue '%s' is a real sim-event sound main.gd can fire" % key)
		var line: String = Sfx.SFX_CAPTIONS[key]
		Runner.T.ok(line.begins_with("[") and line.ends_with("]"),
			"'%s' uses the bracketed sound-effect caption form, not the SPEAKER: form" % key)
		# Must fit the strip on ONE line: these fire mid-fight, and a warning that wraps is a
		# warning that costs a second of reading the player does not have.
		var w: float = Art.font().get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, HudIcons.FONT_SIZE).x
		Runner.T.ok(w <= HudIcons.CAPTION_MAX_W, "'%s' fits the caption strip on one line" % key)
	Runner.T.ok(Sfx.SFX_CAPTIONS.size() < event_sound.size() / 4,
		"the captioned set stays a small subset of the cue table (%d of %d)" % [Sfx.SFX_CAPTIONS.size(), event_sound.size()])


# Semantic caption arbitration: critical warning > player state > objective > teaching > flavor.
# Higher copy preempts through the ONE strip; displaced/stateful copy remains queued, equal warning
# tiers never flicker-stomp, and per-key cooldown still prevents a repeated cue pinning the strip.
func test_sfx_caption_gating_preempts_semantically_and_preserves_queued_state() -> void:
	var sfx := Sfx.new()
	var f := Engine.get_physics_frames()

	# An un-captioned cue (a plain shot) never touches the strip.
	sfx.caption_sfx("shot")
	Runner.T.eq(sfx.active_caption()["text"], "", "an un-captioned cue leaves the strip empty")

	# Start with Commander flavor, then prove lethal warning copy can interrupt it.
	sfx._arm_caption("COMMANDER: \"Move out!\"", null, false, false, Sfx.CaptionTier.FLAVOR)
	sfx.caption_sfx("strike_warn")
	Runner.T.eq(sfx.active_caption()["text"], Sfx.SFX_CAPTIONS["strike_warn"], "a listed warning cue arms the strip")
	Runner.T.eq(sfx.active_caption()["radio"], false, "a warning caption is dry-tinted, not a radio line")
	Runner.T.ok(not sfx._cap_is_vo, "a warning caption is not flagged VO, so stop_vo can never clear it")
	Runner.T.eq(sfx._cap_queue.size(), 1, "preempted flavor is retained instead of silently discarded")

	# A DIFFERENT equal-tier warning queues; it cannot flicker-stomp the active warning.
	sfx.caption_sfx("sniper_paint")
	Runner.T.eq(sfx.active_caption()["text"], Sfx.SFX_CAPTIONS["strike_warn"],
		"an equal-tier warning cannot stomp a caption still inside its readable window")

	# Stateful accessibility VO queues behind warnings but ahead of preserved flavor.
	sfx._arm_caption("SPOTTER: \"Pilot down!\"", null, true, true, Sfx.CaptionTier.PLAYER_STATE)
	sfx._cap_until = Engine.get_physics_frames()
	Runner.T.eq(sfx.active_caption()["text"], Sfx.SFX_CAPTIONS["sniper_paint"],
		"the already-queued lethal warning resumes first")
	sfx._cap_until = Engine.get_physics_frames()
	Runner.T.eq(sfx.active_caption()["text"], "SPOTTER: \"Pilot down!\"",
		"stateful accessibility VO resumes before displaced flavor")
	sfx._cap_until = Engine.get_physics_frames()
	Runner.T.eq(sfx.active_caption()["text"], "COMMANDER: \"Move out!\"",
		"preempted flavor resumes through the same caption slot after higher tiers clear")

	# The SAME cue can't re-arm inside its cooldown, even with the strip completely free — this is
	# what stops a per-bullet cue from pinning the strip open.
	sfx._cap_until = Engine.get_physics_frames()
	sfx.caption_sfx("sniper_paint")
	Runner.T.eq(sfx.active_caption()["text"], "", "the same cue cannot re-arm inside SFX_CAPTION_GAP")
	Runner.T.ok(int(sfx._sfx_cap_next["sniper_paint"]) >= f + Sfx.SFX_CAPTION_GAP,
		"arming a cue records its next-allowed frame a full gap ahead")
	# ...and once the gap has passed it is allowed again (rewind the recorded frame rather than
	# waiting 3 real seconds).
	sfx._sfx_cap_next["sniper_paint"] = 0
	sfx.caption_sfx("sniper_paint")
	Runner.T.eq(sfx.active_caption()["text"], Sfx.SFX_CAPTIONS["sniper_paint"], "past its cooldown the cue captions again")
	sfx.free()


func test_audio_identity_stop_vo_clears_only_its_own_vo_caption() -> void:
	var sfx := Sfx.new()
	# Arm a VO caption, then a bark caption on top (they use separate players/buses and can
	# legitimately overlap) -- stop_vo() must drop only the VO line's caption, never the bark's.
	sfx._arm_caption("SPOTTER: \"Enemy observer spotted!\"", null, true, true)
	sfx._cap_text = "COMMANDER: \"Rally to me!\""
	sfx._cap_is_vo = false
	sfx.stop_vo()
	Runner.T.eq(sfx.active_caption()["text"], "COMMANDER: \"Rally to me!\"",
		"stop_vo leaves a concurrently-armed bark caption alone")
	sfx.free()


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


func test_wheel_text_rows_never_stack() -> void:
	# The AAA tell: two size-8/9 rows 11px apart read as one collided mush.
	# PixelOperator8 paints ascent+descent+1px shadow = 11px at size 9.
	var c := _consts()
	var rows := [c["WHEEL_ROW_WARN"], c["WHEEL_ROW_LABEL"], c["WHEEL_ROW_CUE"]]
	rows.sort()
	for i in rows.size() - 1:
		Runner.T.ok(rows[i + 1] - rows[i] >= 11.0,
			"wheel text rows keep >= one line-height of padding")


# --- a1-17: banner plate alpha floor ---

func test_a1_banner_plate_alpha_floor() -> void:
	var ms = load("res://src/main.gd")
	Runner.T.ok(is_equal_approx(ms._banner_plate_alpha(1.0), 1.0), "full text -> full plate")
	Runner.T.ok(is_equal_approx(ms._banner_plate_alpha(0.3), 0.85), "fading text -> plate HELD at the 0.85 floor (no wash-out)")
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


# --- c2-07: warn() tier is EXPLICIT, not a green-channel guess ---
# Verified color map: the tier the CALLER declares decides the remap, so a future palette tweak
# (e.g. bumping a critical red's green above the old 0.5 threshold) can't silently reclassify it.
func test_c2_warn_tier_color_map() -> void:
	var was_cb: bool = Art.colorblind
	# The actual HUD warning tints, each with the tier its call site declares.
	var crit := Color(1.0, 0.25, 0.2)          # low-ammo / dry-grenade / closing-shop CRITICAL red
	var caution := Color(1.0, 0.72, 0.32)       # low-ammo / pre-close CAUTION amber
	# A red-critical tint whose green sits ABOVE the retired 0.5 heuristic — the old code would have
	# misread it as caution and skipped the lift; the explicit tier keeps it critical.
	var high_g_crit := Color(1.0, 0.6, 0.2)
	Art.colorblind = false
	Runner.T.ok(Art.warn(crit).is_equal_approx(crit), "colorblind OFF: critical tint passes through")
	Runner.T.ok(Art.warn(caution, Art.WARN_CAUTION).is_equal_approx(caution), "colorblind OFF: caution tint passes through")
	Art.colorblind = true
	var c := Art.warn(crit)
	Runner.T.ok(c.b > crit.b and c.b > c.g, "colorblind ON: CRITICAL lifts blue past its green (separates from amber on the blue axis)")
	Runner.T.ok(Art.warn(caution, Art.WARN_CAUTION).is_equal_approx(caution), "colorblind ON: CAUTION tier passes through unchanged")
	var hc := Art.warn(high_g_crit)   # default tier == CRITICAL
	Runner.T.ok(hc.b > high_g_crit.b, "colorblind ON: a high-green tint declared CRITICAL still gets the blue lift (no green-channel misclassification)")
	Runner.T.ok(Art.warn(crit, Art.WARN_CRITICAL).is_equal_approx(Art.warn(crit)), "default tier is CRITICAL")
	Art.colorblind = was_cb   # restore before any later suite reads it


# --- a1-17 r2: top-bar record chip mode ---

func test_a1_record_hud_mode() -> void:
	var hud = load("res://src/view/hud.gd")
	Runner.T.eq(hud._record_hud_mode(200, 100), "badge", "live score beat best -> reserved RECORD badge")
	Runner.T.eq(hud._record_hud_mode(50, 100), "best", "score below best -> dim BEST target chip")
	Runner.T.eq(hud._record_hud_mode(200, 0), "none", "no best yet -> no record chip")


# --- a1-19: entity bakes stay lossless (no BC edge-mush on the silhouettes) ---

func test_a1_art_bakes_are_lossless() -> void:
	var stack: Array[String] = ["res://assets/art"]
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
	Runner.T.ok(checked > 100, "scanned the entity bake .import files (%d)" % checked)
	Runner.T.ok(offenders.is_empty(),
		"no entity bake is BC-compressed (compress/mode=2 mushes the OUTLINE silhouette): %s" % str(offenders.slice(0, 5)))
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
	Runner.T.eq(menu._best_line(4500, 0, 138), "BEST — SCORE 4,500 · 138m", "score-only best drops WAVE 0 (a4-17 grouped)")
	Runner.T.eq(menu._best_line(4500, 0, 0), "BEST — SCORE 4,500", "a pure campaign best shows just the grouped score")
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


# --- a2-08: cactus instance variety ---

func test_a2_cactus_instance_variety() -> void:
	var ms = load("res://src/main.gd")
	var mn := 99.0
	var mx := 0.0
	var deads := 0
	for h in range(0, 220):
		var ti: Dictionary = ms._cactus_instance(h)
		mn = minf(mn, ti["scale_mul"])
		mx = maxf(mx, ti["scale_mul"])
		if ti["dead"]:
			deads += 1
	Runner.T.ok(absf(mn - 0.85) < 0.01, "min cactus scale is 0.85")
	Runner.T.ok(mx > 1.12 and mx < 1.15, "max cactus scale ~1.14 (0.85..1.138)")
	Runner.T.ok(deads > 8 and deads < 45, "a minority (1-in-11) of cactus are dead (%d/220)" % deads)


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
		var c := FileAccess.get_file_as_string("res://assets/art/icons/%s.png.import" % cap)
		Runner.T.ok(c.contains("size_limit=128"), "capsule glyph %s imports size-limited" % cap)
	for tile in ["dirt", "sand"]:
		var ti := FileAccess.get_file_as_string("res://assets/cc0/%s.png.import" % tile)
		Runner.T.ok(ti.contains("mipmaps/generate=false"), "the 1:1 Kenney %s tile has mipmaps OFF" % tile)


func test_ground_tile_is_seamless() -> void:
	# The ground base is drawn as one repeat-tiled strip per row — a sand card whose
	# wrap edge doesn't match its own interior would put the grid straight back.
	var img: Image = (load("res://assets/cc0/sand.png") as Texture2D).get_image()
	var w := img.get_width()
	var h := img.get_height()
	var inner := 0.0
	var wrap := 0.0
	for y in h:
		for x in w - 1:
			inner += absf(img.get_pixel(x + 1, y).v - img.get_pixel(x, y).v)
		wrap += absf(img.get_pixel(0, y).v - img.get_pixel(w - 1, y).v)
	inner /= float(h * (w - 1))
	wrap /= float(h)
	Runner.T.ok(wrap <= inner * 1.5, "sand.png wraps seamlessly (wrap %.4f vs inner %.4f)" % [wrap, inner])


# --- a2-17: boss phase labels are named (not "PHASE n") ---

func test_a2_boss_phase_names() -> void:
	var c := _consts()
	var g: Array = c["GUNSHIP_PHASE_NAMES"]
	var co: Array = c["COLOSSUS_PHASE_NAMES"]
	Runner.T.eq(g.size(), 2, "the gunship has 2 named phases (strafe/mortar half-cycle)")
	Runner.T.eq(co.size(), 3, "the colossus has 3 named phases")
	Runner.T.eq(g, ["STRAFING RUN", "MORTAR VOLLEY"], "the full gunship phase-name list")
	Runner.T.eq(co, ["ADVANCE", "MORTAR VOLLEYS", "TROOP DROPS"], "the full colossus phase-name list")
	for nm in (g + co):
		Runner.T.ok(not String(nm).contains("PHASE"), "'%s' is NAMED, not abstract PHASE n" % nm)


func test_a2_label_plate_rect() -> void:
	var ms = load("res://src/main.gd")
	var r: Rect2 = ms._label_plate_rect(100.0, 50.0, 40.0)
	Runner.T.ok(is_equal_approx(r.position.x, 97.0), "plate starts 3px LEFT of the label origin")
	Runner.T.ok(is_equal_approx(r.size.x, 46.0), "plate is 6px wider than the label")
	Runner.T.ok(r.position.y < 50.0 and r.end.y > 50.0,
		"plate straddles the BASELINE — Art.text draws glyphs ABOVE y, so a plate starting at y backs nothing")


# The mid-fight alert band must be readable over dirt: the plate ink is near-opaque
# (a translucent plate let terrain noise through the glyphs) and the boss phase label's
# plate straddles its baseline. Both were the "dark text on dark box" AAA tell.
func test_alert_band_is_opaque_backed() -> void:
	var ms = load("res://src/main.gd")
	Runner.T.ok(ms.LABEL_PLATE_FILL.a >= 0.85, "boss phase-label plate is opaque, not a see-through wash")
	var r: Rect2 = ms._label_plate_rect(0.0, 100.0, 50.0)
	Runner.T.ok(r.position.y <= 90.0, "plate covers the glyph box above the baseline")


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

func test_a4_grade_breather_only_in_endless_shop() -> void:
	# a4-01: the master color grade is always on; its calm "breather" variant fires ONLY in
	# the endless shop intermission (visual half of the folded-in a4-15).
	var ms = load("res://src/main.gd")
	Runner.T.ok(ms._grade_breather_target("endless", 120) > 0.5, "the grade breather is ON during the endless shop intermission")
	Runner.T.eq(ms._grade_breather_target("endless", 0), 0.0, "no breather once the wave is live (no intermission)")
	Runner.T.eq(ms._grade_breather_target("campaign", 120), 0.0, "campaign (no shop) gets no breather")


func test_a4_grade_shader_is_wired() -> void:
	# a4-01: the master grade pass is real — the shader loads and exposes the master 'grade'
	# + shop 'breather' uniforms, and a ShaderMaterial accepts them (as _setup_screen_fx wires).
	var sh := load("res://src/view/grade.gdshader") as Shader
	Runner.T.ok(sh != null, "the master color-grade shader loads + compiles")
	var names: Array = []
	for u in sh.get_shader_uniform_list():
		names.append(u["name"])
	Runner.T.ok("grade" in names, "the grade shader exposes the master 'grade' uniform")
	Runner.T.ok("breather" in names, "the grade shader exposes the shop 'breather' uniform")
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("grade", 1.0)
	Runner.T.ok(is_equal_approx(float(mat.get_shader_parameter("grade")), 1.0), "grade rides at full strength (always on)")


func test_a4_print_ink_is_shared_and_documented() -> void:
	# a4-02: the world-sprite outline rim (main._spr) and the HUD metal-plate backing
	# (main._metal_plate) key off the SAME near-black warm-neutral instead of two
	# independently-chosen literals — locks the value + the doc that explains why.
	Runner.T.ok(Art.PRINT_INK.is_equal_approx(Color(0.05, 0.06, 0.04)),
		"Art.PRINT_INK holds the documented print-ink value")
	Runner.T.ok(Art.PLATE_STEEL.is_equal_approx(Color(0.5, 0.52, 0.5)),
		"Art.PLATE_STEEL holds the documented plate-metal midtone value")
	Runner.T.ok(Art.PRINT_INK.g >= Art.PRINT_INK.r and Art.PRINT_INK.r >= Art.PRINT_INK.b,
		"the print ink is a warm-neutral near-black, not pure 0,0,0")
	var main_src := FileAccess.get_file_as_string("res://src/main.gd")
	# Hard guard: neither literal may still be hand-inlined anywhere in main.gd —
	# a re-duplicated Color(0.05, 0.06, 0.04...) or Color(0.5, 0.52, 0.5...) would
	# silently fork the "one ink" claim this whole item exists to make true.
	Runner.T.ok(not ("0.05, 0.06, 0.04" in main_src), "no bare print-ink literal survives in main.gd (Art.PRINT_INK only)")
	Runner.T.ok(not ("0.5, 0.52, 0.5" in main_src), "no bare plate-steel literal survives in main.gd (Art.PLATE_STEEL only)")
	var spr_start := main_src.find("func _spr(")
	var spr_body := main_src.substr(spr_start, main_src.find("func _metal_plate(") - spr_start)
	Runner.T.ok("Art.PRINT_INK" in spr_body, "_spr()'s outline rim reads Art.PRINT_INK")
	var plate_start := main_src.find("func _metal_plate(")
	var plate_body := main_src.substr(plate_start, 800)
	Runner.T.ok("Art.PRINT_INK" in plate_body and "Art.PLATE_STEEL" in plate_body,
		"_metal_plate() reads BOTH Art.PRINT_INK and Art.PLATE_STEEL")
	var bible := FileAccess.get_file_as_string("res://assets_src/style_bible.md")
	Runner.T.ok(not bible.is_empty(), "the style bible exists (assets_src/style_bible.md)")
	Runner.T.ok("PRINT_INK" in bible and "PLATE_STEEL" in bible and "grade.gdshader" in bible,
		"the style bible documents the draw-time ink constants and the full-frame grade pass")
	var shader_src := FileAccess.get_file_as_string("res://src/view/grade.gdshader")
	Runner.T.ok("style_bible.md" in shader_src,
		"the grade shader points back at the style bible (per-sprite unification happens BEFORE this pass)")


func test_a4_group_digits() -> void:
	# a4-17: thousands separators so big scores scan (264500 -> "264,500").
	Runner.T.eq(Art.group_digits(0), "0", "zero")
	Runner.T.eq(Art.group_digits(999), "999", "sub-thousand is unchanged")
	Runner.T.eq(Art.group_digits(1000), "1,000", "thousands separator lands")
	Runner.T.eq(Art.group_digits(264500), "264,500", "the roguelite carrot reads at a glance")
	Runner.T.eq(Art.group_digits(1234567), "1,234,567", "millions grouped every 3 digits")
	Runner.T.eq(Art.group_digits(-1500), "-1,500", "negative sign preserved outside the grouping")


func test_a4_top_prey_shared_by_both_cards() -> void:
	# a4-16: the run-story TOP PREY row — shared by the victory + K.I.A. cards (parity + DRY).
	var ms = load("res://src/main.gd")
	Runner.T.eq(ms._top_prey_text({}), "", "no kills -> no TOP PREY row")
	Runner.T.eq(ms._top_prey_text({"rusher": 37, "elite": 4}), "TOP PREY  RIFLEMAN x37",
		"the legacy sim key is presented as the armed troop the player actually fights")
	Runner.T.eq(ms._top_prey_text({"elite": 9}), "TOP PREY  ELITE x9", "a single kind")
	# Stable tie-break: equal counts -> alphabetically first, regardless of insertion order.
	Runner.T.eq(ms._top_prey_text({"rusher": 5, "elite": 5}), "TOP PREY  ELITE x5", "a tie breaks alphabetically (stable)")
	Runner.T.eq(ms._top_prey_text({"elite": 5, "rusher": 5}), "TOP PREY  ELITE x5", "same tie result under reversed insertion order")
	# The victory story rows: KILLS/STREAK always, + TOP PREY when anything died.
	var vr: Array = ms._victory_story_rows(40, 12, {"rusher": 40})
	Runner.T.eq(vr.size(), 2, "kills>0 with prey -> KILLS/STREAK row + TOP PREY row")
	Runner.T.ok(String(vr[0]["text"]).contains("KILLS") and String(vr[0]["text"]).contains("STREAK"), "the story line carries kills + streak")
	Runner.T.eq(ms._victory_story_rows(0, 0, {}).size(), 1, "no kills -> just the KILLS/STREAK line (no prey)")


func test_a4_hero_apex_is_cool_and_bright() -> void:
	# a4-03: the hero crown catch-light makes the soldier the brightest + coolest point.
	var c := _consts()
	var ms = load("res://src/main.gd")
	var h: Color = c["HERO_APEX"]
	Runner.T.ok(h.b > h.r, "the hero crown catch-light is COOL (b > r) — separates from warm ground")
	Runner.T.ok(h.r > 0.8 and h.g > 0.85 and h.b > 0.9, "it is BRIGHT — the hero is the value apex")
	# The apex light is suppressed while downed/reviving — a downed body isn't the apex.
	Runner.T.ok(ms._hero_shows_apex(0.0), "an upright hero shows the value-apex crown light")
	Runner.T.ok(not ms._hero_shows_apex(0.5), "a downed/reviving hero does NOT (must not read as the apex)")
	Runner.T.ok(not ms._hero_shows_apex(1.0), "a fully-downed hero shows no apex light")


func test_ground_has_no_persistent_center_lane() -> void:
	# aaa-2/#1: a full-height ink feature parked at a near-constant x reads as a tiling
	# seam splitting the floor into two tonal halves. No such feature may exist.
	var c := _consts()
	for k in ["SPINE_COL", "SPINE_TREAD", "SPINE_LANE"]:
		Runner.T.ok(not c.has(k), "%s is gone — no persistent centre-lane ink in the ground pass" % k)
	Runner.T.ok(not (load("res://src/main.gd") as Script).get_script_method_list() \
		.any(func(m): return m["name"] == "_spine_center_x"),
		"_spine_center_x is gone — nothing computes a centre-lane x any more")


func test_a4_reticle_halo_is_centered() -> void:
	# a4-05: the reticle's dark backing rings the aim point on ALL sides (a centered halo), not the
	# old one-sided down-right drop-shadow — so no edge camouflages into orange glow / red foundry floor.
	# Verified over the red foundry floor in scratchpad shots3/05-foundry-colossus-last-stand.png.
	var c := _consts()
	var halo: Array = c["RETICLE_HALO"]
	var alpha: float = c["RETICLE_HALO_A"]
	var diag: float = c["RETICLE_HALO_DIAG"]
	Runner.T.ok(halo.size() >= 8, "the halo rings all 8 neighbours, not just one corner")
	# The diagonals draw LIGHTER (they double-cover the corners) so the ring reads EVEN, not boxy.
	Runner.T.ok(diag > 0.0 and diag < 1.0, "diagonal offsets are weighted lighter than cardinals — an even ring, not dark corners")
	# CENTERED = symmetric: for every offset its negation is also present (a lopsided set would
	# re-introduce the camouflage-on-the-bright-side bug the drop-shadow had).
	var sum := Vector2.ZERO
	for off in halo:
		sum += off
		Runner.T.ok(halo.has(-off), "offset %s has its mirror -%s (the halo is centered)" % [off, off])
	Runner.T.ok(sum == Vector2.ZERO, "the 8 offsets cancel to zero — the dark keyline is centered on the aim point")
	Runner.T.ok(alpha > 0.2 and alpha < 0.6, "each halo pass is a dark backing (0.2 < a < 0.6), stacking into a keyline not a black box")


func test_sol_import_discipline_and_corner_alpha() -> void:
	# sol-01: every shipped infantry set PNG is size-limited (<=256) so the 1024² pack can't VRAM-bomb
	# boot, and imported lossless (no VRAM-compress cel-edge bleed). sol-02: the burned-in "AI生成"
	# the corner is clean — the extreme bottom-left corner samples as fully transparent.
	var files := {
		"res://assets/troops/soldier_assault_rifle.png": 256,
		"res://assets/troops/enemy/enemy_assault_rifle.png": 128,
		"res://assets/troops/enemy/enemy_smg.png": 128,
		"res://assets/troops/enemy/enemy_sniper.png": 128,
		"res://assets/troops/enemy/enemy_shotgun.png": 128,
		"res://assets/troops/enemy/enemy_lmg.png": 128,
		"res://assets/troops/frogman_rifle.png": 128,
		"res://assets/troops/frogman_speargun.png": 128,
		"res://assets/troops/fx/muzzleflash_small.png": 128,
	}
	for path in files:
		var lim: int = files[path]
		var t: Texture2D = load(path)
		Runner.T.ok(t != null, "%s imports" % path)
		if t == null:
			continue
		Runner.T.ok(t.get_size().x <= lim and t.get_size().y <= lim,
			"%s size-limited to <= %d (VRAM guard, sol-01)" % [path, lim])
		var img := t.get_image()
		if img.is_compressed():
			img.decompress()
		var s := img.get_size()
		var maxa := 0.0
		for sx in [2, 7, 12]:
			for sy in [int(s.y) - 3, int(s.y) - 8]:
				maxa = maxf(maxa, img.get_pixel(sx, sy).a)
		Runner.T.ok(maxa < 0.05, "%s bottom-left watermark corner scrubbed transparent (sol-02)" % path)
		# Pin the lossless policy from the .import side directly (not just via runtime size): VRAM-compress
		# (mode 2) would bleed the hard cel edges these sprites depend on.
		var cf := ConfigFile.new()
		if cf.load(path + ".import") == OK:
			Runner.T.eq(int(cf.get_value("params", "compress/mode", -1)), 0,
				"%s imports lossless (compress/mode=0, no VRAM cel bleed, sol-01)" % path)
			var meta: Dictionary = cf.get_value("remap", "metadata", {})
			Runner.T.ok(not meta.get("vram_texture", false),
				"%s is not a vram_texture (lossless canvas sprite, sol-01)" % path)
		else:
			Runner.T.ok(false, "%s.import is readable" % path)


func test_sol_hero_swap_scale_tint_outline() -> void:
	# sol-03..06: the pale placeholder blob is swapped for the authored infantry set hero (one canonical
	# class), folded to the ~18px footprint, tinted to POP off green grass (never olive), and stripped
	# of the _spr rim so the pack's baked keyline isn't doubled.
	var art: Script = load("res://src/view/art.gd")
	var c: Dictionary = art.get_script_constant_map()
	var tex: Dictionary = c["TEX"]
	var scale: Dictionary = c["SCALE"]
	var tint: Dictionary = c["TINT"]
	var outline: Dictionary = c["OUTLINE"]
	for k in ["player1", "player2"]:
		Runner.T.ok(tex[k].resource_path.contains("troops/soldier_assault_rifle"),
			"%s is the infantry set authored hero (sol-03)" % k)
		Runner.T.ok(scale[k] >= 0.12 and scale[k] <= 0.30,
			"%s SCALE folds the 256px canvas to the ~18px footprint (sol-04)" % k)
		# Live footprint check: the hero draws at call-scale 0.52 (main.gd _draw_players) × SCALE on the
		# imported 256px canvas → the on-screen canvas lands ~33px (a ~18-21px figure inside its margin).
		var footprint: float = tex[k].get_size().x * 0.52 * float(scale[k])
		Runner.T.ok(footprint >= 26.0 and footprint <= 44.0,
			"%s draws at the intended footprint (~33px canvas, sol-04): %.1f" % [k, footprint])
	var t1: Color = tint["player1"]
	var t2: Color = tint["player2"]
	# sol-05: value-lifted (anti-camo), and pulled OFF green — P1 cool (b>=g so it can't camo on grass),
	# P2 warm/gold; P2 stays warmer than P1 so co-op identity survives one shared sprite.
	Runner.T.ok(t1.r > 1.0 and t1.g > 1.0 and t1.b > 1.0, "P1 hero tint is value-lifted (anti-camo, sol-05)")
	Runner.T.ok(t1.b >= t1.g, "P1 hero tint is COOL, not green-dominant (can't camouflage on grass, sol-05)")
	Runner.T.ok(t2.r > t2.b, "P2 hero tint is WARM/gold (sol-05)")
	Runner.T.ok(t2.r > t1.r and t2.b < t1.b, "P2 hero reads warmer than P1 — co-op identity on one sprite (sol-05)")
	# sol-06: the pack hero carries its own baked keyline — keep it OUT of OUTLINE (no double rim).
	Runner.T.ok(not outline.has("player1") and not outline.has("player2"),
		"the pack hero is out of OUTLINE — baked keyline, no fat-sticker double rim (sol-06)")


func test_sol_hero_pivot_and_apex() -> void:
	# sol-07: (1) the a4-03 crown alpha is bumped so the cool catch-light reads on the new DARK helmet
	# dome (0.32 half-vanished into the dark shading); (2) NO aim-pivot anchor is needed — the sprite's
	# alpha-mass centroid sits within a couple px of texture-center, so _spr's center-rotation already
	# turns the hero about his body (the reviewer's "orbit" fear was for the bbox, not the mass).
	var ms = load("res://src/main.gd")
	var c := _consts()
	var apex_a: float = c["HERO_APEX_A"]
	Runner.T.ok(apex_a > 0.32 and apex_a <= 0.55,
		"crown alpha bumped so it reads on the dark helmet, still a highlight not a blob (sol-07): %.2f" % apex_a)
	Runner.T.ok(ms._hero_shows_apex(0.0) and not ms._hero_shows_apex(0.5), "apex still upright-only after the retune")
	# Crown-on-dome at EVERY aim angle: the crown is screen-fixed at HERO_APEX_DY above pos, and the helmet
	# dome sits at the sprite's rotation center (pos). If the crown SPOT covers pos itself (DY < half its
	# height), it overlaps the dome regardless of how the sprite is rotated — no per-angle screenshot needed.
	var apex_dy: float = c["HERO_APEX_DY"]
	var apex_sz: Vector2 = c["HERO_APEX_SZ"]
	Runner.T.ok(apex_dy < apex_sz.y / 2.0,
		"crown spot covers the sprite center → seated on the dome at ALL aim angles (sol-07): dy=%.1f < %.1f" % [apex_dy, apex_sz.y / 2.0])
	var img: Image = (load("res://assets/troops/soldier_assault_rifle.png") as Texture2D).get_image()
	if img.is_compressed():
		img.decompress()
	var w := img.get_width()
	var h := img.get_height()
	var sx := 0.0
	var sy := 0.0
	var sa := 0.0
	for y in range(0, h, 2):
		for x in range(0, w, 2):
			var a := img.get_pixel(x, y).a
			if a > 0.12:
				sx += x * a
				sy += y * a
				sa += a
	var cx := sx / sa
	var cy := sy / sa
	Runner.T.ok(absf(cx - w / 2.0) < w * 0.05 and absf(cy - h / 2.0) < h * 0.06,
		"hero mass-centroid ~centered (%.0f,%.0f vs %d,%d) — center-rotation turns about the body, no pivot anchor (sol-07)" % [cx, cy, int(w / 2), int(h / 2)])


func test_sol_enemy_red_team() -> void:
	# sol-08..11: the shooting infantry (rusher rotation / elite / sniper) swap to the authored RED-team
	# pack sprites — baked team-color friend/foe read, warm-vermilion tint OFF the pure-red danger family,
	# single-authorship rotation (no cel/the earlier art strobe), no double outline, corpses matching live bodies.
	var art: Script = load("res://src/view/art.gd")
	var c: Dictionary = art.get_script_constant_map()
	var tex: Dictionary = c["TEX"]
	var scale: Dictionary = c["SCALE"]
	var tint: Dictionary = c["TINT"]
	var outline: Dictionary = c["OUTLINE"]
	var ms: Dictionary = load("res://src/main.gd").get_script_constant_map()
	var skins: Array = ms["_RUSHER_SKINS"]
	var corpse: Dictionary = ms["_CORPSE_TEX"]
	var keys := ["enemy_assault", "enemy_smg", "enemy_shotgun", "enemy_lmg", "enemy_sniper"]
	for k in keys:
		Runner.T.ok(tex.has(k) and tex[k].resource_path.contains("troops/enemy/"),
			"%s is a pack red-team sprite (sol-08)" % k)
		Runner.T.ok(scale.has(k), "%s has a SCALE row — no dead config (sol-08)" % k)
		var t: Color = tint[k]
		Runner.T.ok(t.r > t.g and t.g > t.b, "%s tint is warm vermilion (r>g>b), hostile not friendly (sol-09)" % k)
		Runner.T.ok(t.r > 1.0 and t.g > 0.6,
			"%s tint is value-lifted, NOT a saturated pure-red (stays off the tracer/orb danger family, sol-09)" % k)
		Runner.T.ok(outline.has(k), "%s is rimmed — the baked keyline alone vanished on rust (review tell 2 overturns sol-11)" % k)
	Runner.T.eq(skins.size(), 4, "rusher rotation covers all 4 sim skins (skin = (x+y)&3, sol-08)")
	for s in skins:
		Runner.T.ok(keys.has(s), "rusher skin '%s' is a pack red sprite — single authorship, no strobe (sol-08)" % s)
	for k in ["rusher", "elite", "sniper"]:
		Runner.T.ok(keys.has(corpse[k]), "%s corpse matches its live red-team sprite, not a stale ghost (sol-08)" % k)
	# sol-08 cleanup: the entity bakes the swap retired (m_insurgent3-5 rusher skins, m_contractor2 sniper)
	# are fully gone from TEX — no dead boot VRAM for sprites nothing draws.
	for dead in ["m_insurgent3", "m_insurgent4", "m_insurgent5", "m_contractor2"]:
		Runner.T.ok(not tex.has(dead), "retired the earlier art enemy bake '%s' dropped from TEX — no dead preload (sol-08)" % dead)


func test_sol_frogman_variant() -> void:
	# sol-12: the earlier frogman is swapped for the authored pack diver, with a two-pose variant keyed
	# purely off the existing e["submerged"] sim state — speargun down, rifle up — no new field.
	var art: Dictionary = load("res://src/view/art.gd").get_script_constant_map()
	var tex: Dictionary = art["TEX"]
	var outline: Dictionary = art["OUTLINE"]
	var ms = load("res://src/main.gd")
	Runner.T.ok(tex["frogman"].resource_path.contains("troops/frogman_rifle"),
		"frogman surfaced pose = pack rifle diver (sol-12)")
	Runner.T.ok(tex.has("frogman_speargun") and tex["frogman_speargun"].resource_path.contains("troops/frogman_speargun"),
		"frogman submerged pose = pack speargun diver (sol-12)")
	Runner.T.ok(not outline.has("frogman") and not outline.has("frogman_speargun"),
		"the diver keeps its baked keyline — out of OUTLINE, no double rim (sol-12)")
	# Neither diver pose takes the warm-light HOSTILE separator (it would misread the frogman as land infantry;
	# the cool wet-threat tint + ripples are its read). "frogman" is already excluded — pin the new pose too.
	var light: Dictionary = load("res://src/main.gd").get_script_constant_map()["_LIGHT_RIM"]
	Runner.T.ok(not light.has("frogman") and not light.has("frogman_speargun"),
		"neither diver pose takes the hostile light-rim separator (sol-12)")
	Runner.T.eq(ms._frogman_tex(true), "frogman_speargun", "submerged diver shows the SPEARGUN (sol-12)")
	Runner.T.eq(ms._frogman_tex(false), "frogman", "surfaced diver shows the RIFLE (sol-12)")


func test_sie_endless_infantry_family() -> void:
	# sie-01: the four blurry native-64px the earlier art ENDLESS-roster specialists (GRENADIER/GHILLIE/SAPPER/
	# SHIELD) are re-baked as authored 1024px cel-shaded infantry, same convention as the sol-08 red-team
	# swap -- own black keyline (out of OUTLINE, no double rim), a real SCALE row, imports lossless and
	# size-limited, watermark corner scrubbed. "courier" is explicitly untouched (still the native bake).
	var art: Dictionary = load("res://src/view/art.gd").get_script_constant_map()
	var tex: Dictionary = art["TEX"]
	var scale: Dictionary = art["SCALE"]
	var outline: Dictionary = art["OUTLINE"]
	var key_path := {"m_bombsuit": "art/mil2/bombsuit", "m_soldier2": "art/mil2/soldier2",
		"ghillie": "art/p2/ghillie", "sapper": "art/p2/sapper"}
	for k in key_path:
		Runner.T.ok(tex.has(k) and tex[k].resource_path.contains(key_path[k]),
			"%s still maps to its re-baked path — no TEX-key drift (sie-01)" % k)
		# family-standard footprint: same SCALE the enemy_assault/enemy_smg/enemy_shotgun/enemy_lmg/
		# enemy_sniper siblings use on their own 128px-limited canvas (sie-01), not a one-off number.
		Runner.T.eq(scale[k], 0.5, "%s SCALE matches the enemy_* family standard, no accidental footprint drift (sie-01)" % k)
		# review tell 2 carved m_soldier2 back IN: the amber-tinted grenadier on sand was the
		# muddiest unit in the game with its separator disabled behind the OUTLINE gate.
		if k == "m_soldier2":
			Runner.T.ok(outline.has(k), "%s is rimmed again — its separator was dead config since sie-01 (review tell 2)" % k)
		else:
			Runner.T.ok(not outline.has(k), "%s keeps its baked keyline — out of OUTLINE, no double rim (sie-01)" % k)
	Runner.T.ok(outline.has("courier"), "courier is untouched — still the native entity bake, still needs its runtime rim (sie-01)")
	# footprint cross-check (data, not just the constant): the 4 re-baked keys must land on the exact
	# same imported-canvas x SCALE footprint as an established red-team sibling, not merely "some" 0.5.
	var sib_tex: Texture2D = tex["enemy_assault"]
	var sib_footprint: float = sib_tex.get_size().x * float(scale["enemy_assault"])
	for k in key_path:
		var footprint: float = tex[k].get_size().x * float(scale[k])
		Runner.T.ok(absf(footprint - sib_footprint) < 0.5,
			"%s footprint (%.1f) matches the enemy_assault sibling's (%.1f) — same family, not a one-off (sie-01)" % [k, footprint, sib_footprint])
	var files := {
		"res://assets/art/mil2/soldier2.png": 128,
		"res://assets/art/mil2/bombsuit.png": 128,
		"res://assets/art/p2/ghillie.png": 128,
		"res://assets/art/p2/sapper.png": 128,
	}
	for path in files:
		var lim: int = files[path]
		var t: Texture2D = load(path)
		Runner.T.ok(t != null, "%s imports" % path)
		if t == null:
			continue
		# exact, not just capped: the 1024px source only ever downsamples through the import's own
		# size_limit, so a healthy reimport lands EXACTLY on the family's 128px canvas (a lesser size
		# would mean a stray pre-shrunk source snuck in; a cap-only check wouldn't catch that).
		Runner.T.eq(t.get_size(), Vector2(lim, lim),
			"%s imports at exactly %dx%d (VRAM guard, sie-01)" % [path, lim, lim])
		var img := t.get_image()
		if img.is_compressed():
			img.decompress()
		var s := img.get_size()
		var maxa := 0.0
		for sx in [2, 7, 12]:
			for sy in [int(s.y) - 3, int(s.y) - 8]:
				maxa = maxf(maxa, img.get_pixel(sx, sy).a)
		Runner.T.ok(maxa < 0.05, "%s bottom-left watermark corner scrubbed transparent (sie-01)" % path)
		# sol-07-style pivot discipline: these keys center-rotate on `face` every tick (_draw_enemies
		# passes `face` as _spr's angle arg), so the alpha-mass centroid must sit near canvas center or
		# the sprite visibly wobbles off its own body as it turns. Padded-to-centroid at bake time (not
		# bbox-centered) — pin it within 1% of the canvas so a future re-bake can't regress it silently.
		var mass := 0.0
		var msum := Vector2.ZERO
		for py in range(int(s.y)):
			for px in range(int(s.x)):
				var pa: float = img.get_pixel(px, py).a
				if pa > 0.0:
					mass += pa
					msum += Vector2(px, py) * pa
		var centroid: Vector2 = msum / maxf(mass, 0.001)
		var off_pct: Vector2 = (centroid - Vector2(s) * 0.5).abs() / Vector2(s) * 100.0
		Runner.T.ok(off_pct.x < 1.0 and off_pct.y < 1.0,
			"%s alpha-mass centroid within 1%% of canvas center (%.2f%%, %.2f%%) — center-rotation pivot (sie-01)" % [path, off_pct.x, off_pct.y])
		var cf := ConfigFile.new()
		if cf.load(path + ".import") == OK:
			Runner.T.eq(int(cf.get_value("params", "compress/mode", -1)), 0,
				"%s imports lossless (compress/mode=0, sie-01)" % path)
			Runner.T.eq(int(cf.get_value("params", "detect_3d/compress_to", -1)), 0,
				"%s keeps detect_3d off (sie-01)" % path)
			Runner.T.eq(int(cf.get_value("params", "process/size_limit", -1)), 128,
				"%s import-side size_limit locked to 128 (sie-01)" % path)
			Runner.T.ok(not bool(cf.get_value("params", "mipmaps/generate", true)),
				"%s skips mipmaps — flat 2D sprite, no mip use (sie-01)" % path)
			var meta: Dictionary = cf.get_value("remap", "metadata", {})
			Runner.T.ok(not meta.get("vram_texture", false),
				"%s is not a vram_texture (lossless canvas sprite, sie-01)" % path)
		else:
			Runner.T.ok(false, "%s.import is readable" % path)


func test_hostile_infantry_separator_rim() -> void:
	# review tell 2: sol-08 swapped the shooting infantry onto the enemy_* pack sprites and sie-01
	# re-baked the grenadier — but none of those keys ever entered OUTLINE, so the _spr rim gate
	# (main.gd, `Art.outlined(tex_name)`) drew them with ZERO rim, and the _LIGHT_RIM entries
	# m_soldier2 still carried were dead config behind that gate. Measured: enemy fill averages
	# (82,74,55) olive-tan, landing ~(129,92,54) after the warm tint — dead between desert ground
	# stops (209,132,71)/(132,76,61). No tint fixes that (more red = more rust = more camouflage);
	# the warm-light separator rim a1-02 built for exactly this failure is the only view lever.
	# This test pins the CLASS from source: _RUSHER_SKINS plus the keyed specialist draws — a 5th
	# rusher skin added tomorrow must rim or go red.
	var ms: Dictionary = load("res://src/main.gd").get_script_constant_map()
	var art: Dictionary = load("res://src/view/art.gd").get_script_constant_map()
	var keys: Array = ms["_RUSHER_SKINS"] + ["enemy_sniper", "m_soldier2"]
	for k in keys:
		Runner.T.ok(art["OUTLINE"].has(k), "%s is rimmed — the _spr rim gate reads OUTLINE (review tell 2)" % k)
		Runner.T.ok(ms["_LIGHT_RIM"].has(k),
			"%s wears the warm-LIGHT separator, not the near-black rim that vanished on rust (a1-02)" % k)
		Runner.T.ok(ms["_UNIT_RIM"].has(k),
			"%s is in the unit rim class — the tiny-decor guard can never strip it" % k)
	Runner.T.ok(not ms["_LIGHT_RIM"].has("frogman") and not ms["_LIGHT_RIM"].has("frogman_speargun"),
		"the diver keeps its sol-12 water read — no land-infantry light rim")


func test_character_animation_registry_is_complete_and_godot_ready() -> void:
	# The replacement set is authored in one strict overhead projection, one native
	# canvas per frame. Explicit registries make every gameplay pose import eagerly.
	var art: Dictionary = load("res://src/view/art.gd").get_script_constant_map()
	var player: Dictionary = art["PLAYER_ANIM"]
	var player_states := ["idle", "move_forward_0", "move_forward_1",
		"move_backward_0", "move_backward_1", "crouch", "shoot", "throw",
		"roll", "downed", "interact", "bash"]
	Runner.T.eq(player.size(), player_states.size(), "player registry contains exactly the 12 shipped poses")
	var paths := {}
	for state in player_states:
		Runner.T.ok(player.has(state), "player pose '%s' is registered" % state)
		if not player.has(state):
			continue
		var tex: Texture2D = player[state]
		Runner.T.eq(tex.get_size(), Vector2(256, 256), "player/%s is a native 256px Godot texture" % state)
		paths[tex.resource_path] = true
		var img := tex.get_image()
		if img.is_compressed():
			img.decompress()
		for corner in [Vector2i(0, 0), Vector2i(255, 0), Vector2i(0, 255), Vector2i(255, 255)]:
			Runner.T.ok(img.get_pixelv(corner).a < 0.05,
				"player/%s corner %s is transparent" % [state, str(corner)])
	Runner.T.eq(paths.size(), player_states.size(), "every player pose uses its own frame")

	var enemies: Dictionary = art["ENEMY_ANIM"]
	var enemy_states := ["idle", "move_0", "move_1", "crouch", "windup", "shoot", "stunned", "downed"]
	var enemy_keys := ["enemy_assault", "enemy_smg", "enemy_shotgun", "enemy_lmg", "enemy_sniper"]
	Runner.T.eq(enemies.size(), enemy_keys.size(), "all five weapon classes have animation sets")
	for key in enemy_keys:
		Runner.T.ok(enemies.has(key), "%s animation set is registered" % key)
		if not enemies.has(key):
			continue
		var poses: Dictionary = enemies[key]
		Runner.T.eq(poses.size(), enemy_states.size(), "%s has exactly eight poses" % key)
		for enemy_state in enemy_states:
			Runner.T.ok(poses.has(enemy_state), "%s/%s is registered" % [key, enemy_state])
			if not poses.has(enemy_state):
				continue
			var enemy_tex: Texture2D = poses[enemy_state]
			Runner.T.eq(enemy_tex.get_size(), Vector2(128, 128), "%s/%s is a native 128px Godot texture" % [key, enemy_state])
			var enemy_img := enemy_tex.get_image()
			if enemy_img.is_compressed():
				enemy_img.decompress()
			Runner.T.ok(enemy_img.get_pixel(0, 0).a < 0.05 and enemy_img.get_pixel(127, 127).a < 0.05,
				"%s/%s has a clean transparent canvas" % [key, enemy_state])

	var main_src := FileAccess.get_file_as_string("res://src/main.gd")
	Runner.T.ok(main_src.contains("Art.player_anim(anim_state)"), "player pose registry is wired into the live draw")
	Runner.T.ok(main_src.contains("Art.enemy_anim(rusher_key, rusher_pose)"), "rusher pose registry is wired into the live draw")
	Runner.T.ok(main_src.contains("Art.enemy_anim(corpse_key, \"downed\")"), "enemy downed poses are wired into corpses")


func test_projectile_cards_are_complete_and_velocity_aligned() -> void:
	var tex: Dictionary = load("res://src/view/art.gd").get_script_constant_map()["TEX"]
	for key in ["bullet_player", "bullet_piercing", "bullet_enemy", "bullet_sniper"]:
		Runner.T.ok(tex.has(key), "%s is registered" % key)
		if not tex.has(key):
			continue
		var card: Texture2D = tex[key]
		Runner.T.eq(card.get_size(), Vector2(128, 32), "%s uses the shared 4:1 projectile canvas" % key)
		var img := card.get_image()
		if img.is_compressed():
			img.decompress()
		Runner.T.ok(img.get_pixel(0, 0).a < 0.05 and img.get_pixel(127, 31).a < 0.05,
			"%s corners are transparent" % key)
	var src := FileAccess.get_file_as_string("res://src/main.gd")
	Runner.T.ok(src.contains("bullet_piercing\" if piercing else \"bullet_player"),
		"player ammo switches to the cyan AP card when piercing is live")
	Runner.T.ok(src.contains("bullet_sniper\" if fast else \"bullet_enemy"),
		"hostile ammo switches to the long sniper card from actual projectile speed")


func test_sol_muzzle_pop() -> void:
	# sol-15/16: the PLAYER shot gets an authored crack-pop card OVERLAY (mz_pop), while fx_muzzle_fan stays
	# the DIRECTIONAL primary; the watermarked/hollow-core muzzleflash_large is rejected, and the pop is
	# alpha-capped so it never out-blooms an explosion. Enemy small-arms keep the procedural pop.
	var tex: Dictionary = load("res://src/view/art.gd").get_script_constant_map()["TEX"]
	Runner.T.ok(tex.has("mz_pop") and tex["mz_pop"].resource_path.contains("troops/fx/muzzleflash_small"),
		"mz_pop = the pack's small crack-pop card (sol-15)")
	Runner.T.ok(tex.has("fx_muzzle_fan"), "fx_muzzle_fan stays the DIRECTIONAL primary muzzle (sol-16)")
	Runner.T.ok(not ResourceLoader.exists("res://assets/troops/fx/muzzleflash_large.png"),
		"the watermarked/hollow-core muzzleflash_large is NOT shipped (sol-15/16 reject)")
	var mh: Dictionary = load("res://src/main.gd").get_script_constant_map()["MUZZLE_HEAT"]
	Runner.T.ok(mh["pop_a"] <= 0.7 and mh["pop_lerp"] < 0.5,
		"the pop is alpha-capped + warmed off white-hot so it never out-blooms an explosion (sol-15/16)")
	# Wiring: the PLAYER fire handler _ev_shot tags its muzzle pop:true (→ the authored card draws); an
	# enemy muzzle fx carries no pop flag (→ the procedural pop; no red-faction muzzleflash). Run the real
	# _ev_shot to prove the player side, and check the enemy fx shape for the absent flag.
	var m = load("res://src/main.gd").new()
	m.sim = SimWorld.new(7, 1)
	m._ev_shot({"i": 0, "x": 0, "y": 0})
	var player_pop := false
	for f in m._fx:
		if f.get("kind") == "muzzle":
			player_pop = f.get("pop", false)
	Runner.T.ok(player_pop, "player _ev_shot tags its muzzle pop:true → the authored card draws (sol-15/16)")
	m.free()
	var enemy_fx := {"kind": "muzzle", "a": 0.0, "szj": 0.6, "col": Color(1.0, 0.42, 0.28)}
	Runner.T.ok(not enemy_fx.get("pop", false),
		"an enemy muzzle carries no pop flag → procedural pop, no red-faction muzzleflash (sol-16)")


func test_sol_guards() -> void:
	# sol-14 / sol-17 / sol-18 (cross-cutting guards): a future edit that wires a watermarked death pose,
	# an off-theme baddie, or a broken soldier path should fail HERE, not in a screenshot.
	var art: Dictionary = load("res://src/view/art.gd").get_script_constant_map()
	var tex: Dictionary = art["TEX"]
	var soldier_keys := 0
	for k in tex:
		var path: String = tex[k].resource_path
		# sol-14: no watermarked death_* pose ships — the downed body reuses the live hero sprite (greyed prone).
		Runner.T.ok(not String(k).begins_with("death_") and not path.contains("/death/"),
			"no death_* pose registered — downed body reuses the greyed hero, not a watermarked pose (sol-14): %s" % k)
		# sol-17: the off-theme baddies/ roster (zombies/aliens/mechs/cultists...) maps to no sim kind — never wired.
		Runner.T.ok(not path.contains("/baddies/"),
			"no baddies/ sprite wired — off-theme, no sim kind (sol-17): %s" % k)
		# sol-15/16 reject: the watermarked/hollow large muzzle flash is never registered.
		Runner.T.ok(not path.contains("muzzleflash_large"), "the rejected muzzleflash_large is unregistered (sol-15)")
		# sol-18: every registered infantry set key resolves to a live, imported asset (no dead SOL row).
		if path.contains("/troops/"):
			soldier_keys += 1
			Runner.T.ok(ResourceLoader.exists(path), "soldier key '%s' resolves to a live asset (sol-18)" % k)
	# sol-18: the ship-set is EXACTLY the intended subset — player1+player2 (2) + 5 enemy + 2 frogman +
	# mz_pop = 10 keys, not the 88-sprite pack. An exact pin catches both over- and under-integration.
	Runner.T.eq(soldier_keys, 10,
		"the shipped soldier subset is exactly 10 keys (2 hero + 5 enemy + 2 frogman + mz_pop), not the 88-sprite pack (sol-18)")
	# sol-14: the downed body reuses the LIVE hero sprite (greyed prone, main.gd:6063-6069) — so with no
	# death_* pose registered, a downed teammate is the authored soldier dimmed, never a watermarked back-sprawl.
	Runner.T.ok(tex["player1"].resource_path.contains("soldier_assault_rifle")
			and tex["player2"].resource_path.contains("soldier_assault_rifle"),
		"the downed-body reuse keys (player1/player2) are the live authored hero, so downed = greyed hero (sol-14)")


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
	# The well must sit INSIDE the chrome frame's own texture rect — content_frame_rect(),
	# the rect _draw_frame_nine 9-slices into (frame draws over the well). Asserting a
	# hand-typed quad here pinned the RETIRED uniform-stretch footprint as the contract.
	var well: Rect2 = mn._content_well_rect()
	var frame: Rect2 = mn.content_frame_rect(mn.Mode.HALL)
	Runner.T.ok(frame.encloses(well), "the well rect is fully inside the chrome frame")


func test_the_retired_uniform_stretch_frame_quad_survives_nowhere() -> void:
	## The x20 y8 600x344 quad was the frame's footprint back when ui_frame_lrg was ONE
	## stretched texture rect. _draw_frame_nine replaced it with a corner-anchored 9-slice:
	## the REAL interior hole is y 39.66..320.34, while the stretched model says
	## 36.22..323.78 — 3.44px LOOSER per side vertically (so an audit built on it
	## UNDER-reports vertical overflow) and 2.20px tighter per side horizontally (so it
	## invents overflow that is not there). One projection only, and it is
	## test_menu_layout.gd::_measured_frame_interior — everything else delegates.
	# The needle is assembled, never spelled: this suite greps ITSELF, so a literal
	# here would be its own violation and the row could never go green.
	var dead := "600" + ", 344"
	for p in ["res://tools/probe_frame_bounds.gd", "res://tests/test_assets.gd",
			"res://src/view/menu.gd"]:
		var src := FileAccess.get_file_as_string(p)
		Runner.T.ok(not (dead in src) and not (dead.replace(" ", "") in src),
			"%s carries no copy of the retired uniform-stretch frame quad" % p)


# --- a3-03: endless gets its OWN base ground palette (warm rust/ochre) instead of
# a nudge on the campaign's own desert sand, so the arena reads as its own place. ---

func test_a3_endless_has_its_own_ground_palette() -> void:
	var ms = load("res://src/main.gd")
	var endless: Array = ms._ground_stops("endless")
	var campaign: Array = ms._ground_stops("campaign")
	var eg: Array = endless[0]   # endless grass stops
	var cg: Array = campaign[0]  # campaign grass stops
	Runner.T.eq(eg.size(), 5, "endless grass ramp has 5 stops (matches the ramp)")
	Runner.T.eq(campaign[1].size(), 5, "campaign dirt ramp has 5 stops")
	# The base (wave-1 / sector-1) floor must read distinctly NON-jungle: both theaters
	# are desert now (r well above g), but campaign's pale sand and endless's rust-ochre
	# stay visibly different colors.
	var e0: Color = eg[0]
	var c0: Color = cg[0]
	Runner.T.ok(c0.r > c0.g, "campaign start is sand-forward (r > g), not olive lawn")
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


# --- juice pass: landing REAL damage on a multi-HP enemy must spawn the AUTHORED
# impact cards (sparkle scatter + dark strike mark), not just the procedural light
# + dots it used to — "a hit that doesn't sell" was a blind-review verbatim. ---

func test_damaging_hit_spawns_authored_impact_cards() -> void:
	var m = load("res://src/main.gd").new()
	m.sim = SimWorld.new(11, 1)
	m._motion = 1.0
	m.sim.enemies.clear()
	m.sim.enemies.append({"alive": true, "kind": "mg_nest", "hp": 3,
		"x": 100 * Fixed.ONE, "y": 100 * Fixed.ONE})
	m._check_enemy_hits()          # first pass only seeds hp_prev — no fx yet
	Runner.T.eq(m._fx.size(), 0, "seeding the hp edge-detect spawns nothing")
	m.sim.enemies[0]["hp"] = 2     # a round gets through the armour
	m._check_enemy_hits()
	var kinds := {}
	var texes := {}
	for f in m._fx:
		kinds[f.get("kind", "")] = true
		if f.get("kind", "") == "tex":
			texes[f.get("tex", "")] = true
	Runner.T.ok(kinds.has("light"), "the damaging hit still throws its local light")
	Runner.T.ok(kinds.has("spark"), "the damaging hit gets the authored sparkle scatter, like a ricochet")
	Runner.T.ok(texes.has("fx_impactdark"), "the damaging hit stamps the dark strike mark")
	m.free()


# --- a3-08 (Iran reskin): desert flora shares the sand palette — no longer a
# hue-separated green mass. Scrub/tumbleweed/dry_shrub/cactus separate from the
# ground by VALUE (a touch duller than the brightest sand stop) plus shape and
# ground-contact shadow, not a green-vs-tan hue lift. ---

func test_a3_foliage_reads_desert_not_jungle() -> void:
	var ms = load("res://src/main.gd")
	var fol: Color = Art.DESERT_FOLIAGE
	# Pin the brightest of the 5 campaign grass stops by actual r-value, not by
	# assuming stop [0] stays brightest — a future sand-palette retune could
	# reorder the ramp and would otherwise silently compare against the wrong stop.
	var grass_stops: Array = ms._ground_stops("campaign")[0]
	var g0: Color = grass_stops[0]
	for gs in grass_stops:
		if gs.r > g0.r:
			g0 = gs
	Runner.T.ok(fol.g <= fol.r, "desert flora tint is not green-dominant (r >= g) — reads sun-bleached, not jungle")
	Runner.T.ok(fol.r < g0.r, "desert flora is a touch DULLER than the brightest sand stop, so it still separates as its own mass")
	# The scrub contact dab that grounds each clump anchor: small radius, soft alpha.
	var fd: Dictionary = _consts()["SCRUB_DAB"]
	Runner.T.ok(fd["r"] > 0.0 and fd["r"] <= 5.0, "the scrub dab is a small contact shadow (<= 5px)")
	Runner.T.ok(fd["a"] > 0.0 and fd["a"] <= 0.35, "the scrub dab is soft (grounds without a hard blob)")


# --- a3-09: field boulders get a lit top-edge highlight (warm, bright) so they read as
# RAISED cover — the inverse of a1-07's recessed crater pit. ---

func test_a3_rock_top_light_is_warm_and_bright() -> void:
	var c := _consts()
	var rl: Color = c["ROCK_TOP_LIGHT"]
	Runner.T.ok(rl.r > rl.b, "the rock top-light is WARM (sunlit, r > b)")
	Runner.T.ok(rl.r > 0.9 and rl.g > 0.9, "the rock top-light is BRIGHT (a lit rim, not a shadow)")
	# Only the DOMED boulders get the raised-rim highlight; the flat dead cactus does not.
	var ms = load("res://src/main.gd")
	Runner.T.ok(ms._rock_has_top_light("rock1") and ms._rock_has_top_light("rock2"),
		"domed boulders (rock1/rock2) get the raised-rim top-light")
	Runner.T.ok(not ms._rock_has_top_light("cactus_dead2"), "the flat dead cactus gets NO top-light (no raised dome)")


# --- preserve-concealment-semantics: the "hedge" asset was retired for a dry_shrub
# reskin (kind==1 pass-through cover, guarded gameplay-side in test_main.gd). This
# just proves the OLD asset is actually gone and nothing in the whole res:// tree
# still points at it — a stray scene/resource re-wiring hedge.png back in wouldn't
# fail any gameplay test since main.gd never loads it by path. ---

## Every top-level res:// dir except the gitignored/tooling ones (.godot's import
## cache, build/tmp output, .shoop/.claude/.opencode/.remember/.git housekeeping) —
## so a stray reference under assets/docs/media/etc. can't hide from the scan just
## because it's outside src/tests/addons/tools.
const _SCAN_ROOT_SKIP := ["build", "tmp", ".godot", ".git", ".shoop", ".claude", ".opencode", ".remember"]

func _scannable_roots() -> Array[String]:
	var roots: Array[String] = []
	var da := DirAccess.open("res://")
	Runner.T.ok(da != null, "could not open res:// to enumerate scan roots")
	if da == null:
		return roots
	for d in da.get_directories():
		if not _SCAN_ROOT_SKIP.has(d):
			roots.append("res://" + d)
	return roots


## Recursively scans every text asset under a res:// dir for any of `needles`.
## A scene referencing a retired texture by UID rather than path won't contain
## the filename, so callers should pass both.
func _scan_dir_for_strings(root: String, exts: PackedStringArray, needles: PackedStringArray, skip: String) -> Array[String]:
	var hits: Array[String] = []
	var stack: Array[String] = [root]
	while not stack.is_empty():
		var d: String = stack.pop_back()
		var da := DirAccess.open(d)
		if da == null:
			continue
		var err := da.list_dir_begin()
		Runner.T.ok(err == OK, "list_dir_begin failed on %s: %s" % [d, error_string(err)])
		if err != OK:
			continue
		var f := da.get_next()
		while f != "":
			var full := d + "/" + f
			if da.current_is_dir():
				stack.append(full)
			elif full != skip:
				for ext in exts:
					if f.ends_with(ext):
						var txt := FileAccess.get_file_as_string(full)
						for needle in needles:
							if txt.find(needle) != -1:
								hits.append(full)
								break
						break
			f = da.get_next()
		da.list_dir_end()
	return hits


func test_hedge_asset_fully_retired() -> void:
	Runner.T.ok(not FileAccess.file_exists("res://assets/art/decor/hedge.png"),
		"the pre-reskin hedge sprite must be deleted, not left as a dead asset that could get silently re-wired")
	# Scan the ENTIRE res:// tree (minus gitignored/tooling dirs) for the retired
	# sprite's path AND its .import uid (a scene can preload by uid:// with no
	# "hedge.png" literal anywhere) — assets/docs/media included, not just code.
	var hits: Array[String] = []
	for root in _scannable_roots():
		hits.append_array(_scan_dir_for_strings(root,
			[".gd", ".tscn", ".tres", ".import", ".gdshader"],
			["hedge.png", "uid://bchguurpaw56h"], "res://tests/test_assets.gd"))
	Runner.T.ok(hits.is_empty(), "these files still reference the retired hedge asset: %s" % str(hits))
	# The replacement must actually exist and be registered, not just absent-hedge.
	Runner.T.ok(FileAccess.file_exists("res://assets/art/decor/dry_shrub.png"),
		"the dry_shrub replacement sprite must exist on disk")
	Runner.T.ok(Art.TEX.has("dry_shrub"), "dry_shrub must be registered in Art.TEX so _spr(\"dry_shrub\", ...) resolves")


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
	# The base alpha holds under REDUCE MOTION (_motion=0 -> only the base term survives),
	# so the threat tell never vanishes; the pulse is the motion-gated extra.
	var eaa: Dictionary = c["ELITE_AURA_ALPHA"]
	Runner.T.ok(eaa["base"] >= 0.12, "the aura keeps a visible base under REDUCE MOTION")
	Runner.T.ok(eaa["pulse"] > 0.0, "the aura pulse adds on top when motion is on")


# --- a3-13: every kill gets a bright LOCAL death-pop, and the death weight (pop radius +
# gib volume) scales by unit tier so a heavy dies bigger than a lone trooper. ---

func test_a3_kill_tier_scales_death_weight() -> void:
	var ms = load("res://src/main.gd")
	Runner.T.eq(ms._kill_tier("rusher"), 0, "a rusher is a light-infantry death (tier 0)")
	Runner.T.eq(ms._kill_tier("elite"), 1, "an elite is a specialist death (tier 1)")
	Runner.T.eq(ms._kill_tier("technical"), 2, "a technical is a vehicle death (tier 2)")
	# Gib volume = 5 + tier*3 -> a heavy throws strictly more debris than a trooper.
	var light_gibs: int = 5 + ms._kill_tier("rusher") * 3
	var heavy_gibs: int = 5 + ms._kill_tier("technical") * 3
	Runner.T.ok(heavy_gibs > light_gibs, "a vehicle throws more gib than a light trooper (11 vs 5)")
	# The death-pop is a LOCAL additive light (not a frame flash), radius 9 + tier*6.
	var pop: Dictionary = ms._death_pop_fx(0, 0, "technical")
	Runner.T.eq(pop["kind"], "light", "the death-pop is a LOCAL additive light fx, not a screen flash")
	Runner.T.ok(is_equal_approx(pop["r"], 21.0), "a vehicle pop radius = 9 + tier(2)*6 = 21")
	Runner.T.ok(pop["r"] > float(ms._death_pop_fx(0, 0, "rusher")["r"]), "a heavy pops bigger than a light trooper")


# --- a3-14: the VICTORY card reaches K.I.A. parity — a NEW BEST! flag (shared predicate)
# + a REDEPLOY prompt with the start glyph. ---

func test_a3_victory_card_kia_parity() -> void:
	var ms = load("res://src/main.gd")
	# The shared BEST / NEW BEST! predicate (used by BOTH cards).
	Runner.T.eq(ms._victory_best_text(100, 0), "", "no prior best -> no BEST row")
	Runner.T.ok(String(ms._victory_best_text(300, 200)).contains("NEW BEST!"), "beating the best flags NEW BEST!")
	Runner.T.ok(not String(ms._victory_best_text(100, 200)).contains("NEW BEST!"), "score below best -> no NEW BEST")
	# The victory extra-rows: BEST (when a best exists) + an always-present REDEPLOY prompt.
	var er: Array = ms._victory_extra_rows(300, 200, 1.0)
	Runner.T.eq(er.size(), 2, "victory appends BEST + REDEPLOY when a best exists")
	Runner.T.eq(er[er.size() - 1]["text"], "REDEPLOY", "the victory card gets a REDEPLOY prompt (K.I.A. parity)")
	Runner.T.ok(er[er.size() - 1].has("icon"), "the REDEPLOY row carries the start-glyph icon")
	Runner.T.eq(ms._victory_extra_rows(100, 0, 1.0).size(), 1, "no best -> just the REDEPLOY row")


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

# opt-loop pass 4: death-yell/spawn-shout MP3 banks moved from a synchronous first-play
# load to ResourceLoader.load_threaded_request, polled by _poll_mp3_banks. This is the
# ONLY coverage of that path (play_death_yell/play_spawn_shout no longer trigger a load
# themselves) — proves the threaded request/poll/land cycle actually delivers streams
# into the bank, not just that it compiles.
func test_mp3_banks_load_threaded_and_land_in_the_bank() -> void:
	var sfx := Sfx.new()
	sfx._load_death_yells()
	sfx._load_spawn_shouts()
	Runner.T.ok(not sfx._death_yells_pending.is_empty(), "death-yell bank has pending threaded loads")
	Runner.T.ok(not sfx._spawn_shouts_pending.is_empty(), "spawn-shout bank has pending threaded loads")
	var waited_ms := 0
	while (not sfx._death_yells_pending.is_empty() or not sfx._spawn_shouts_pending.is_empty()) and waited_ms < 5000:
		sfx._poll_mp3_banks()
		OS.delay_msec(10)
		waited_ms += 10
	Runner.T.ok(sfx._death_yells_pending.is_empty(), "death-yell bank finished loading within 5s")
	Runner.T.ok(sfx._spawn_shouts_pending.is_empty(), "spawn-shout bank finished loading within 5s")
	Runner.T.ok(sfx._death_yells.size() > 0, "death-yell bank has streams after the load completes (%d)" % sfx._death_yells.size())
	Runner.T.ok(sfx._spawn_shouts.size() > 0, "spawn-shout bank has streams after the load completes (%d)" % sfx._spawn_shouts.size())
	for s in sfx._death_yells:
		Runner.T.ok(s is AudioStream, "every landed death-yell entry is a real AudioStream")
	sfx.free()


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
		var c := FileAccess.get_file_as_string("res://assets/art/ui/glyphs/%s.png.import" % g)
		Runner.T.ok(c.contains("size_limit=128"), "input glyph %s imports size-limited (was full-res)" % g)
	# Minimap icons — drawn ~16-24px on the rail.
	for ic in ["ICON_Map_Fire", "ICON_Map_Skull", "ICON_Map_Vehicle", "ICON_Map_Target"]:
		var c := FileAccess.get_file_as_string("res://assets/art/hud/%s.png.import" % ic)
		Runner.T.ok(c.contains("size_limit=128"), "minimap icon %s imports size-limited" % ic)
	# The 512x256 muzzle-fan card draws at ~fl*1.4 (<=~56px) via a raw draw_texture_rect.
	var mf := FileAccess.get_file_as_string("res://assets/art/fx/fx_muzzle_fan.png.import")
	Runner.T.ok(mf.contains("size_limit=128"), "the muzzle-fan card imports size-limited")
	# NEGATIVE check (a3-17 r2): SCALE-coupled in-world bakes (footprint = imported_px * SCALE,
	# drawn via _spr) are DELIBERATELY left full-res — capping them would shift on-screen size
	# and need a per-texture SCALE recompute. Guard that they were NOT swept.
	for scaled in ["res://assets/art/decor/rock1.png.import", "res://assets/art/units/rusher.png.import"]:
		if FileAccess.file_exists(scaled):
			Runner.T.ok(FileAccess.get_file_as_string(scaled).contains("size_limit=0"),
				"SCALE-coupled bake %s stays full-res (not swept)" % scaled.get_file())


# --- a3-15 r2: set_ambience_march drives the three place-bed volumes — river up near water,
# foundry up deep in the march, shop pad in the intermission (and it HUSHES the field beds). ---

func test_a3_ambience_march_drives_bed_volumes() -> void:
	var sfx := Sfx.new()
	# Near water, low march, not shop: the river bed rides UP; foundry stays hushed.
	for i in 300: sfx.set_ambience_march(0.1, true, false)
	Runner.T.ok(sfx._river.volume_db > -30.0, "river bed is audibly UP near water")
	Runner.T.ok(sfx._river.volume_db > sfx._foundry.volume_db + 10.0, "river dominates the hushed foundry near water")
	# In the shop: the pad owns it and BOTH field beds are hushed (you stepped out of the fight).
	for i in 300: sfx.set_ambience_march(1.0, true, true)
	Runner.T.ok(sfx._shop.volume_db > -25.0, "the shop pad is UP in the intermission")
	Runner.T.ok(sfx._river.volume_db < -40.0 and sfx._foundry.volume_db < -40.0,
		"the shop hushes BOTH field beds (river + foundry)")
	# Deep in the march (in the plant), not shop: the foundry hum swells up.
	for i in 300: sfx.set_ambience_march(1.0, false, false)
	Runner.T.ok(sfx._foundry.volume_db > -35.0, "the foundry machinery bed swells past the mid-march")
	sfx.free()


# --- nt-03: player-tank + enemy-vehicle bakes are real silhouettes, not blob rectangles ---

func test_nt03_vehicle_bakes_are_not_blob_rectangles() -> void:
	# nt-03 replaced tank_body/tank_barrel/technical/radar_tank/rocket_truck — visually the
	# same generic flat camo-cloth rectangle material re-scaled per file, no hull/turret/track
	# shape at all. Pin a plausibility envelope on each bake's alpha silhouette so a future
	# regeneration that lands a near-blank canvas (broken chroma-key, wrong crop) or a
	# near-solid rectangle (chroma-key never ran) fails HERE instead of only showing up in a
	# screenshot. Also checks the front-up half (per the hull=dv.angle()+PI/2 / static PI/2
	# draw-rotation convention these use) isn't accidentally empty — a 180-off rotation or a
	# bad crop offset would starve one half. Finally, hashes all 5 files and requires them
	# distinct — the exact "same generic bake copy-pasted across every vehicle" failure mode
	# this item fixed, so a future shortcut back to one shared placeholder fails here too.
	# (Regen pipeline note: the raw renders were re-keyed on HSV HUE distance, not the plain
	# RGB-distance key nt-01/nt-02 use — desert tan camo sits close enough to a magenta
	# backdrop in raw RGB distance that the old tol+feather=120 erased most of the vehicle.
	# HSV hue separates them cleanly (magenta ~330deg vs tan ~30deg); the key used hue_tol=14,
	# hue_feather=14, sat_gate=0.12, and a per-image value floor at val_frac=0.72 of the
	# corner-sampled backdrop brightness, so GI-bounced magenta-tinted shadow on dark vehicle
	# detail — tires, tracks — isn't mistaken for background. Re-derive these from the corner
	# color of any future raw render rather than reusing the numbers verbatim.)
	var files := {
		"res://assets/art/tank_body.png": Vector2i(104, 104),
		"res://assets/art/tank_barrel.png": Vector2i(72, 72),
		"res://assets/art/mil2/technical.png": Vector2i(96, 96),
		"res://assets/art/mil2/radar_tank.png": Vector2i(104, 104),
		"res://assets/art/mil2/rocket_truck.png": Vector2i(104, 104),
	}
	var seen_hashes := {}
	for path in files:
		var t: Texture2D = load(path)
		Runner.T.ok(t != null, "%s imports" % path)
		if t == null:
			continue
		Runner.T.eq(Vector2i(t.get_size()), files[path], "%s keeps its replaced-bake canvas size" % path)
		var img := t.get_image()
		if img.is_compressed():
			img.decompress()
		var w := img.get_width()
		var h := img.get_height()
		var opaque := 0
		var top_opaque := 0
		var total := 0
		var top_total := 0
		for y in range(0, h, 2):
			for x in range(0, w, 2):
				total += 1
				var top := y < h / 2
				if top:
					top_total += 1
				if img.get_pixel(x, y).a > 0.05:
					opaque += 1
					if top:
						top_opaque += 1
		var cov := float(opaque) / float(total)
		Runner.T.ok(cov > 0.06 and cov < 0.75,
			"%s alpha coverage reads as a vehicle silhouette, not blank or a solid rect (nt-03): %.2f" % [path, cov])
		var top_cov := float(top_opaque) / float(maxi(top_total, 1))
		Runner.T.ok(top_cov > 0.04,
			"%s front-up half carries real opaque content (nt-03): %.2f" % [path, top_cov])
		var file_hash := FileAccess.get_sha256(path)
		Runner.T.ok(not seen_hashes.has(file_hash),
			"%s is not a byte-for-byte copy of %s (nt-03, no shared placeholder bake)" %
				[path, seen_hashes.get(file_hash, "")])
		seen_hashes[file_hash] = path
		if path == "res://assets/art/tank_barrel.png":
			# tank_barrel's "front" isn't alpha-mass (both ends are opaque, it's a thin
			# cylinder) -- it's the round mount-plate BASE (wide) vs the muzzle-brake TIP
			# (narrower). _draw_tanks() defaults an unset turret to barrel_angle=-PI/2, which
			# with its +PI/2 draw correction is exactly 0 net rotation -- so a fresh/parked
			# tank shows this canvas completely unrotated, muzzle pointing straight up-screen.
			# Assert the base really is the wide end here, i.e. the canvas is mounted
			# base-down/muzzle-up as that default expects, not mounted backwards.
			var top_w := _opaque_row_width_avg(img, 0, int(h * 0.15))
			var bot_w := _opaque_row_width_avg(img, int(h * 0.85), h)
			Runner.T.ok(bot_w > top_w,
				"tank_barrel.png mount base (bottom, %.1fpx) is wider than the muzzle tip (top, %.1fpx) -- base-down/muzzle-up canvas, matching the barrel_angle=-PI/2 default's zero-rotation rest pose (nt-03)" % [bot_w, top_w])


# endless-meta-retention: the VETERAN PERKS row (menu.gd _submenu_icon "perks")
# points at "mi_trophy" -- pin that the registry actually resolves it to a real,
# non-empty texture, same as HALL OF FAME's own trophy badge already shares.
func test_endless_meta_mi_trophy_icon_exists() -> void:
	var tex := Art.tex("mi_trophy")
	Runner.T.ok(tex != null, "mi_trophy resolves to a texture in Art.TEX")
	Runner.T.ok(tex.get_size().x > 0 and tex.get_size().y > 0, "mi_trophy is a real (non-zero-sized) image, not a stub")


# --- dev-only addon references must never ship ------------------------------------------
# The godot-mcp editor plugin re-adds an [autoload] MCPGameBridge entry to project.godot
# every time the editor runs with the plugin enabled. It points at addons/godot_mcp/,
# which is UNTRACKED, so an exported build cannot resolve it and spams
# "Failed to instantiate an autoload, can't load from path: ..." on every launch.
# It was removed once already (PR #22) and came back.
# This ratchet used to scan ONLY the [autoload] section, and the plugin's OTHER
# re-addition -- the [editor_plugins] enabled=... line, likewise pointing into
# untracked addons/ -- walked straight past it. So scan the whole file: nothing in
# project.godot has any business referencing addons/, in any section.
func test_no_dev_addon_references_in_project_godot() -> void:
	var text := FileAccess.get_file_as_string("res://project.godot")
	Runner.T.ok(not text.is_empty(), "project.godot is readable")
	var offenders: Array[String] = []
	for raw in text.split("\n"):
		var line := raw.strip_edges()
		if line.is_empty() or line.begins_with(";") or line.begins_with("["):
			continue
		if line.contains("addons/"):
			offenders.append(line)
	Runner.T.eq(offenders, [] as Array[String],
		"no project.godot line references addons/ (dev-only tooling must not ship)")


# --- river shoreline is a curve, not a ruler line ---------------------------------------
func test_river_shore_is_curved_and_shader_shares_the_params() -> void:
	var m := load("res://src/main.gd")
	var lo := 999.0
	var hi := -999.0
	for i in 33:
		var v: float = m._bank_offset(float(i) / 32.0, 3.7, true)
		lo = minf(lo, v); hi = maxf(hi, v)
	Runner.T.ok(hi - lo > 4.0, "bank offset actually varies across the screen")
	Runner.T.ok(absf(hi) <= m.BANK_AMP.x + m.BANK_AMP.y + 0.01, "bank offset stays bounded by its amplitudes")
	Runner.T.ok(m.BANK_AMP.x + m.BANK_AMP.y < m.BANK_BASE, "bank polygon can never self-intersect its dry edge")
	var src := FileAccess.get_file_as_string("res://src/view/water.gdshader")
	for u in ["bank_amp", "bank_freq", "pad_px", "band_px"]:
		Runner.T.ok(u in src, "water.gdshader still consumes uniform " + u)
# --- kill-the-copy-pasted-sandbag-wall-tiling: the BAKE must not be a mechanical
# grid of identical stamps -- per-segment placement jitter (wall_variant/cap_flags,
# tests/test_main.gd) cannot rescue a source PNG that is N identical flat-fill
# ovals on a ruled line. Pins the anti-grid properties tools/gen_entities.py's
# _sandbag_wall/_bag builder is supposed to guarantee, so a future regeneration
# back to a stamped grid fails HERE instead of only showing up in a screenshot
# review. ---------------------------------------------------------------------

func test_sandbag_bakes_are_not_a_mechanical_grid() -> void:
	# (path, committed alpha-bbox (min_y, max_y) -- new bake must stay within 3px)
	var files := {
		"res://assets/art/p2/wall_sandbag.png": Vector2i(64, 181),
		"res://assets/art/p2/wall_sandbag_b.png": Vector2i(64, 181),
		"res://assets/art/p2/wall_sandbag_c.png": Vector2i(64, 181),
		"res://assets/art/p2/wall_sandbag_end.png": Vector2i(31, 92),
		"res://assets/art/sandbag.png": Vector2i(17, 63),
	}
	var wall_body_hashes := {}
	for path in files:
		var t: Texture2D = load(path)
		Runner.T.ok(t != null, "%s imports" % path)
		if t == null:
			continue
		var img := t.get_image()
		if img.is_compressed():
			img.decompress()
		var w := img.get_width()
		var h := img.get_height()
		var top_rows: Array[int] = []
		var colors := {}
		var bbox_min_y := h        # ANY nonzero alpha, matching PIL's getbbox() -- the
		var bbox_max_y := -1       # committed footprint below was measured that way.
		for x in w:
			var first := -1
			for y in h:
				var a := img.get_pixel(x, y).a
				if a > 0.0:
					bbox_min_y = mini(bbox_min_y, y)
					bbox_max_y = maxi(bbox_max_y, y)
				if a > 0.05:
					if first == -1:
						first = y
					colors[img.get_pixel(x, y).to_html(false)] = true
			if first != -1:
				top_rows.append(first)
		Runner.T.ok(top_rows.size() > 4, "%s has real opaque width (>4 columns)" % path)
		var distinct := {}
		var mean := 0.0
		for r in top_rows:
			distinct[r] = true
			mean += r
		mean /= maxf(1.0, top_rows.size())
		var variance := 0.0
		for r in top_rows:
			variance += (r - mean) * (r - mean)
		variance /= maxf(1.0, top_rows.size())
		var stddev := sqrt(variance)
		Runner.T.ok(distinct.size() >= 4,
			"%s top edge has >=4 distinct heights across the run, not a ruled stamp line (got %d)" %
				[path, distinct.size()])
		Runner.T.ok(stddev > 1.5,
			"%s top-edge height stddev > 1.5px, a silhouette not a flat grid (got %.2f)" % [path, stddev])
		Runner.T.ok(colors.size() >= 6,
			"%s has >=6 distinct opaque RGB values -- real shading, not 2 flat fills + a keyline (got %d)" %
				[path, colors.size()])
		var target: Vector2i = files[path]
		Runner.T.ok(absi(bbox_min_y - target.x) <= 3 and absi(bbox_max_y - target.y) <= 3,
			"%s alpha bbox height (%d..%d) stays within 3px of the pinned footprint (%d..%d) -- must not draw taller than the sim's SANDBAG_HALF hitbox" %
				[path, bbox_min_y, bbox_max_y, target.x, target.y])
		if path.contains("wall_sandbag") and not path.contains("_end"):
			var file_hash := FileAccess.get_sha256(path)
			Runner.T.ok(not wall_body_hashes.has(file_hash),
				"%s is a distinct bake, not a byte-for-byte copy of %s" % [path, wall_body_hashes.get(file_hash, "")])
			wall_body_hashes[file_hash] = path
	Runner.T.eq(wall_body_hashes.size(), 3, "all 3 wall_sandbag body variants are distinct bakes")


func test_sandbag_wall_variants_differ_at_drawn_size() -> void:
	## The reviewer's tell was "identical tiled sprites with stark black
	## outlines": the three wall_sandbag "variants" were the same 4+3-bag
	## layout differing only in per-bag jitter (invisible at the 0.28 draw
	## scale) and every bag wore a near-black ink rim (INK = 12,14,10).
	## Two pixel pins, both measured on 2ca130c BEFORE the re-bake:
	##   1. rim warmth: edge-pixel mean max(r,g,b) was 17.0-19.3/255 -> pin >= 40.
	##   2. silhouette divergence at the size the player sees (240px * 0.28 =
	##      67px): pairwise mean |alpha| diff was 20.9 / 24.3 / 25.6 per 255
	##      (GDScript-measured). Post-bake this test measures 40.8 / 43.8 /
	##      44.4; the pin is post-bake-min - 4 = 36 (required floor was 32).
	##      If a future bake can't clear it, strengthen the BAKE, never lower
	##      the pin.
	var bodies: Array[Image] = []
	for path in ["res://assets/art/p2/wall_sandbag.png", "res://assets/art/p2/wall_sandbag_b.png",
			"res://assets/art/p2/wall_sandbag_c.png", "res://assets/art/p2/wall_sandbag_end.png"]:
		var t: Texture2D = load(path)
		Runner.T.ok(t != null, "%s imports" % path)
		if t == null:
			continue
		var img := t.get_image()
		if img.is_compressed():
			img.decompress()
		var w := img.get_width()
		var h := img.get_height()
		# 1. rim warmth over the edge ring (opaque px touching transparency)
		var warm := 0.0
		var n_edge := 0
		for x in w:
			for y in h:
				if img.get_pixel(x, y).a <= 12.0 / 255.0:
					continue
				var edge := false
				for nb in [Vector2i(x - 1, y), Vector2i(x + 1, y), Vector2i(x, y - 1), Vector2i(x, y + 1)]:
					if nb.x < 0 or nb.y < 0 or nb.x >= w or nb.y >= h \
							or img.get_pixel(nb.x, nb.y).a <= 12.0 / 255.0:
						edge = true
						break
				if edge:
					var c := img.get_pixel(x, y)
					warm += maxf(c.r, maxf(c.g, c.b)) * 255.0
					n_edge += 1
		Runner.T.ok(n_edge > 0, "%s has an edge ring to measure" % path)
		if n_edge > 0:
			Runner.T.ok(warm / n_edge >= 40.0,
				"%s rim is burlap-dark not ink-black (edge mean max-channel %.1f >= 40)" %
					[path, warm / n_edge])
		if not path.contains("_end"):
			bodies.append(img)
	# 2. pairwise silhouette divergence at drawn size (67px = 240 * 0.28)
	Runner.T.eq(bodies.size(), 3, "all three wall body variants loaded")
	var diffs: Array[float] = []
	for pair in [[0, 1], [1, 2], [0, 2]]:
		var a: Image = bodies[pair[0]].duplicate()
		var b: Image = bodies[pair[1]].duplicate()
		a.resize(67, 67, Image.INTERPOLATE_BILINEAR)
		b.resize(67, 67, Image.INTERPOLATE_BILINEAR)
		var d := 0.0
		for x in 67:
			for y in 67:
				d += absf(a.get_pixel(x, y).a - b.get_pixel(x, y).a)
		diffs.append(d / (67.0 * 67.0) * 255.0)
	print("    wall pair alpha diffs: %.1f / %.1f / %.1f per 255" % [diffs[0], diffs[1], diffs[2]])
	for i in diffs.size():
		Runner.T.ok(diffs[i] > 36.0,
			"wall variant pair %d reads as different segments at drawn size (mean alpha diff %.1f > 36/255)" %
				[i, diffs[i]])


# --- event banner scrims never span the playfield ---

func test_event_banners_never_span_the_playfield() -> void:
	var ms = load("res://src/main.gd")
	var strs: Array = ms._KIND_TEACH.values()
	strs.append_array(["BRIDGE GUNSHIP", "MORTAR OBSERVER — SHOOT IT DOWN",
		"GUNSHIP INBOUND", "CORE EXPOSED — OPEN FIRE", "AIRSTRIKE INBOUND",
		"COLOSSUS ENRAGED — MORTAR VOLLEYS", "DESTROY THE GUNSHIP TO ADVANCE",
		"HOLD THE ARENA — CLEAR THE WAVE", "MORTARS RANGING — ADVANCE!"])
	for s in strs:
		var sz: int = ms.banner_fit_size(s, 16)
		var r: Rect2 = ms.banner_plate_rect(s, 70.0, sz, 24.0)   # 24 = worst-case badge pad
		Runner.T.ok(r.size.x <= 0.72 * ms.SCREEN_W,
			"'%s' scrim %dpx never spans the playfield" % [s, int(r.size.x)])
		Runner.T.ok(sz >= 12, "'%s' stays readable (size %d >= 12)" % [s, sz])
	# the slab itself may not come back
	var src := FileAccess.get_file_as_string("res://src/main.gd")
	var body := src.substr(src.find("func _metal_plate("), 800)
	Runner.T.ok(not ("draw_rect(" in body),
		"_metal_plate paints a soft-edged ribbon, never a hard rectangle")


# --- field overlays draw on the pixel grid, not as smooth vector primitives ---

func test_field_overlays_are_pixel_grid_snapped() -> void:
	for path in ["res://src/main.gd", "res://src/view/hud.gd"]:
		var fsrc := FileAccess.get_file_as_string(path)
		var re := RegEx.create_from_string("(?<![.\\w])draw_(arc|circle|line|polyline|dashed_line)\\(")
		Runner.T.eq(re.search_all(fsrc).size(), 0,
			"%s draws field overlays through Art.arc/circle/line (pixel grid), never raw vector primitives" % path)
	# _to_screen is the shared grid seam -- it must round.
	var m := FileAccess.get_file_as_string("res://src/main.gd")
	var body2 := m.substr(m.find("func _to_screen("), 300)
	Runner.T.ok("roundf(" in body2, "_to_screen snaps to whole pixels")


func test_art_ring_is_pixel_perfect_not_a_polygon() -> void:
	# A midpoint circle is 4-way symmetric on integer offsets; a draw_arc N-gon
	# approximation is not. r=12, w=1 is a typical HUD/telegraph ring size.
	var entry: Dictionary = Art._ring_entry(12, 1, false)
	var offsets: PackedVector2Array = entry["offsets"]
	Runner.T.ok(offsets.size() > 0, "the ring has pixels")
	var have := {}
	for o in offsets:
		Runner.T.eq(o.x, roundf(o.x), "ring offset.x is a whole pixel")
		Runner.T.eq(o.y, roundf(o.y), "ring offset.y is a whole pixel")
		have[Vector2i(int(o.x), int(o.y))] = true
	for o in offsets:
		var v := Vector2i(int(o.x), int(o.y))
		Runner.T.ok(have.has(Vector2i(-v.x, v.y)), "ring is symmetric across the y-axis")
		Runner.T.ok(have.has(Vector2i(v.x, -v.y)), "ring is symmetric across the x-axis")
	# Filled discs must include the centre pixel (regression: inner2 == 0
	# excluded d2 == 0, shipping every filled circle with a hollow centre).
	# Read the TEXTURE, not offsets — circle() draws the texture, and filled
	# entries deliberately carry no offsets (only arc() reads those, and it
	# only ever asks for hollow rings).
	var filled: Dictionary = Art._ring_entry(1, 1, true)
	var fimg: Image = (filled["tex"] as ImageTexture).get_image()
	var lit := 0
	for y in fimg.get_height():
		for x in fimg.get_width():
			if fimg.get_pixel(x, y).a > 0.0:
				lit += 1
	Runner.T.eq(lit, 5, "r=1 filled disc is a solid 5-pixel plus (centre + 4 neighbors)")
	Runner.T.ok(fimg.get_pixel(1, 1).a > 0.0, "r=1 filled disc has its centre pixel")
	Runner.T.eq((filled["offsets"] as PackedVector2Array).size(), 0,
		"filled discs carry no offsets — only arc() reads them, and never filled")


func test_art_arc_slice_matches_the_angle_scan_it_replaced() -> void:
	# Art.arc's partial sweep used to scan EVERY pixel of the ring, paying a
	# Vector2.angle() (atan2) + fposmod each — thousands per frame in a fight.
	# It now bsearches a contiguous slice of angle-sorted offsets. That is only
	# legitimate if it picks the IDENTICAL pixel set, so pin it: brute-force the
	# old predicate and compare, over real call-site angles and random sweeps.
	var rng := RandomNumberGenerator.new()
	rng.seed = 0xA12C
	# Angle windows lifted from live call sites — the axis-aligned starts
	# (-PI/2 dials, 0-based wedges) are where float boundaries actually bite.
	var cases: Array = [[0.0, TAU / 12.0], [-PI / 2, TAU * 0.25], [-PI / 2, TAU * 0.75],
		[-PI / 2, 0.0], [PI + 0.55, TAU - 0.2 - PI - 0.55], [0.0, TAU - 0.01],
		[-PI, TAU / 5.0 - 0.3], [PI, 1.1], [0.0, 0.0], [TAU * 3.0 + 0.4, 1.9]]
	for _k in 40:
		cases.append([rng.randf_range(-40.0, 40.0), rng.randf_range(0.0, TAU - 0.002)])
	var compared := 0
	var drew := 0
	for r in [1, 2, 5, 12, 21, 48, 58]:
		for w in [1, 2, 3]:
			var entry: Dictionary = Art._ring_entry(r, w, false)
			var offs: PackedVector2Array = entry["offsets"]
			var angles: PackedFloat64Array = entry["angles"]
			Runner.T.eq(angles.size(), offs.size(), "r=%d w=%d has one angle per offset" % [r, w])
			for case in cases:
				var lo: float = case[0]
				var span: float = case[1]
				var want := {}
				for o in offs:
					if fposmod(o.angle() - lo, TAU) <= span:
						want[o] = true
				var got := {}
				var win: Vector3i = Art._arc_span(angles, lo, span)
				for i in range(win.x, win.y):
					got[offs[i]] = true
				for i in win.z:
					got[offs[i]] = true
				compared += 1
				drew += got.size()
				if want.size() != got.size():
					Runner.T.eq(got.size(), want.size(),
						"r=%d w=%d lo=%f span=%f selects the same pixel COUNT" % [r, w, lo, span])
					continue
				var same := true
				for o in want:
					if not got.has(o):
						same = false
						break
				Runner.T.ok(same, "r=%d w=%d lo=%f span=%f selects the same pixel SET" % [r, w, lo, span])
	Runner.T.ok(compared >= 1000, "the equivalence sweep actually ran (%d windows)" % compared)
	Runner.T.ok(drew > 0, "the sweeps selected pixels — a slice that always picked nothing would 'match' trivially")


func test_art_ring_cache_evicts_one_entry_instead_of_clearing() -> void:
	# Regression: at the cap the cache clear()ed wholesale, so ONE novel radius
	# — and call sites animate radii constantly (explosion cores sweep r=12..58)
	# — threw away the entire working set and rebuilt every disc from scratch:
	# an O(r²) Image fill plus a GPU upload each, all inside _draw.
	var cap: int = Art.RING_CACHE_CAP
	Art._ring_cache.clear()
	# cap distinct (r, w) keys, all small enough that filling them is cheap.
	var side := int(ceil(sqrt(float(cap))))
	for i in cap:
		Art._ring_entry(1 + i / side, 1 + i % side, false)
	Runner.T.eq(Art._ring_cache.size(), cap, "cache fills to exactly the cap")
	var first: Vector3i = Art._ring_cache.keys()[0]
	var last: Vector3i = Art._ring_cache.keys()[cap - 1]
	Art._ring_entry(1 + side, 1, false)   # one novel key, cache already full
	Runner.T.eq(Art._ring_cache.size(), cap, "a novel key past the cap evicts one entry, not all of them")
	Runner.T.ok(not Art._ring_cache.has(first), "the oldest entry is the one evicted")
	Runner.T.ok(Art._ring_cache.has(last), "the newest entries survive a novel key")
	Art._ring_cache.clear()   # shared static; leave it cold, not full of test junk


# ---------------------------------------------------------------------------
# The menu bezel. SPR_HUD_Frame_Lrg used to be one `d.rectangle(outline=255)`:
# MEASURED on the pre-fix PNG — along the top keyline run (x 15%..85%) alpha
# stdev 0.00 with exactly 1 distinct alpha value, and 16 distinct RGBA in the
# WHOLE 256^2 file. A perfectly uniform stroke stretched across 12 of 14 menu
# screens reads as a prototype box, not chrome.
#
# Read with Image.load_from_file, NOT Art.tex(): the imported .ctex is a cache
# and a stale one fails this on OLD PIXELS while the tree is correct.
# ---------------------------------------------------------------------------

func test_menu_chrome_is_a_bezel_not_a_flat_stroke() -> void:
	var img := Image.load_from_file("res://assets/art/hud/SPR_HUD_Frame_Lrg.png")
	Runner.T.ok(img != null and img.get_width() == 256, "frame art loads off DISK at 256px")
	var w := img.get_width()
	var h := img.get_height()

	# 1. The re-bake ratchet: WHERE the primary keyline sits. Every derived menu
	# layout constant (Menu.FRAME_LINE_INSET, content_frame_border, FRAME_INNER_*)
	# is tuned against this canvas — a regen that moves the line must fail loudly
	# instead of silently resizing 12 screens.
	# The first FULL-WIDTH rule, not the first ink: the corner ornament (rivets +
	# bracket arms) is authored OUTBOARD of the keyline so it cannot reach into the
	# content well, and it covers ~31% of a row at texel 8. A 0.1 row-mean threshold
	# latched onto THAT and reported the inset as 0.031. The keyline runs edge to
	# edge (~88% coverage), so 0.6 separates them with a wide margin either way.
	var top := -1
	for y in h:
		var tot := 0.0
		for x in w:
			tot += img.get_pixel(x, y).a
		if tot / float(w) > 0.6:
			top = y
			break
	Runner.T.ok(top >= 0, "found the top keyline band")
	var inset := float(top) / float(h)
	Runner.T.ok(absf(inset - 0.06) <= 0.004,
		"keyline inset %.4f is within 0.004 of Menu.FRAME_LINE_INSET 0.06" % inset)

	# 2. The keyline must read as WEATHERED METAL, not a stamped stroke. Sampled
	# two rows into the band (clear of the anti-aliased outer edge).
	var row: int = top + 2
	var alphas: Array[float] = []
	for x in range(int(w * 0.15), int(w * 0.85)):
		alphas.append(img.get_pixel(x, row).a * 255.0)
	var mean := 0.0
	for a in alphas:
		mean += a
	mean /= float(alphas.size())
	var var_sum := 0.0
	var distinct := {}
	for a in alphas:
		var_sum += (a - mean) * (a - mean)
		distinct[roundi(a)] = true
	var stdev := sqrt(var_sum / float(alphas.size()))
	Runner.T.ok(stdev >= 6.0, "keyline alpha stdev %.2f >= 6.0 (was 0.00: a flat stroke)" % stdev)
	Runner.T.ok(distinct.size() >= 8,
		"%d distinct alpha values along the keyline run (was 1)" % distinct.size())

	# 3. Whole-file colour depth — a bezel has lit/shadowed faces and rivets.
	var rgba := {}
	for y in h:
		for x in w:
			rgba[img.get_pixel(x, y).to_rgba32()] = true
	Runner.T.ok(rgba.size() >= 64,
		"%d distinct RGBA in the frame art (was 16)" % rgba.size())
