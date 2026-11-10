extends RefCounted
## The audio director: per-place music, stingers, danger-driven intensity, hit-confirm.
## The runner has a dummy audio driver, so every assertion is on director STATE (chosen ids,
## commit order, start stamps, lengths, throttle returns) - never on sound.

const Runner := preload("res://tests/run_tests.gd")


func _wav(seconds: float) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = 8000
	var d := PackedByteArray()
	d.resize(int(seconds * 8000.0) * 2)
	w.data = d
	return w


## Fixture loader: serves tiny streams for the ids in `have`, null for everything else.
func _fixture(have: Array, skew := {}) -> Callable:
	return func(path: String) -> AudioStream:
		var f := path.get_file().get_basename()
		var id := f.trim_suffix("_combat").trim_suffix("_lull")
		if f.begins_with("sting_"):
			return _wav(0.5) if have.has(f) else null
		if not have.has(id):
			return null
		return _wav(2.0 + float(skew.get(f, 0.0)))


func _dir(have: Array, skew := {}) -> MusicDirector:
	var d := MusicDirector.new()
	d.loader = _fixture(have, skew)
	return d


# --- (a) which track plays where ---------------------------------------------------

func test_track_choice_for_every_context() -> void:
	var P := MusicDirector.pick_track
	Runner.T.eq(P.call("title", 3, true, true, true, "sector2"), "title", "title screen is the title theme")
	for s in 6:
		Runner.T.eq(P.call("play", s, false, false, false, ""), "sector%d" % (s + 1), "sector %d has its own loop" % s)
	Runner.T.eq(P.call("play", 99, false, false, false, ""), "sector6", "sector index clamps high")
	Runner.T.eq(P.call("play", -1, false, false, false, ""), "sector1", "sector index clamps low")
	Runner.T.eq(P.call("play", 2, true, false, false, ""), "boss", "boss beats the sector loop")
	Runner.T.eq(P.call("play", 2, false, true, false, ""), "shop", "endless shop has its own loop")
	Runner.T.eq(P.call("play", 5, true, false, true, ""), "laststand", "last stand beats the boss loop")
	Runner.T.eq(P.call("hold", 4, true, true, true, "sector3"), "sector3", "pause keeps the current track")
	Runner.T.eq(P.call("hold", 4, false, false, false, ""), "title", "pause with nothing playing falls to title")
	Runner.T.eq(P.call("debrief", 4, true, false, true, "boss"), "title", "the debrief resolves to the calm theme")


func test_every_track_id_is_reachable() -> void:
	var seen := {}
	for s in 6:
		seen[MusicDirector.pick_track("play", s, false, false, false, "")] = true
	seen[MusicDirector.pick_track("title", 0, false, false, false, "")] = true
	seen[MusicDirector.pick_track("play", 0, true, false, false, "")] = true
	seen[MusicDirector.pick_track("play", 0, false, true, false, "")] = true
	seen[MusicDirector.pick_track("play", 0, false, false, true, "")] = true
	for id in MusicDirector.TRACK_IDS:
		Runner.T.ok(seen.has(id), "track id '%s' can be chosen" % id)


# --- bar-boundary deferral ---------------------------------------------------------

func test_track_change_waits_for_a_bar_line() -> void:
	var d := _dir(["title", "sector1"])
	d.request("title")
	Runner.T.eq(d.current_id, "title", "the first request commits immediately")
	d.request("sector1")
	Runner.T.eq(d.current_id, "title", "a later request does not switch mid-bar")
	Runner.T.eq(d.pending_id, "sector1", "...it is parked")
	var bar := d.bar_len
	d.update(0.1, bar * 0.25)
	d.update(0.1, bar * 0.9)
	Runner.T.eq(d.current_id, "title", "still mid-bar at 0.9 of a bar")
	d.update(0.1, bar * 1.02)
	Runner.T.eq(d.current_id, "sector1", "the bar line commits it")
	Runner.T.eq(d.pending_id, "", "pending clears")
	d.free_unparented()


func test_loop_wrap_counts_as_a_bar_line() -> void:
	var d := _dir(["title", "sector1"])
	d.request("title")
	d.update(0.1, d.bar_len * 3.5)
	d.request("sector1")
	d.update(0.1, d.bar_len * 3.9)
	Runner.T.eq(d.current_id, "title", "no switch inside the bar")
	d.update(0.1, 0.05)   # position wrapped to the loop start
	Runner.T.eq(d.current_id, "sector1", "the loop wrap is a bar line")
	d.free_unparented()


func test_re_requesting_the_current_track_cancels_a_pending_change() -> void:
	var d := _dir(["title", "sector1"])
	d.request("title")
	d.request("sector1")
	d.request("title")
	Runner.T.eq(d.pending_id, "", "going back to the current track drops the pending switch")
	d.free_unparented()


# --- stems start together, equal length, fall back cleanly --------------------------

func test_stems_start_in_one_call_and_match_length() -> void:
	var d := _dir(["sector1"])
	d.request("sector1")
	Runner.T.ok(d.stems_on, "both stems present -> stems own the score")
	Runner.T.eq(d.start_count, 1, "the pair started exactly once")
	Runner.T.eq(d.last_started, ["sector1_combat", "sector1_lull"], "combat and lull started together")
	var pr: Array = d._pairs[d._slot]
	Runner.T.ok(absf(pr[0].stream.get_length() - pr[1].stream.get_length()) < 0.001,
		"both stems report equal length")
	Runner.T.ok(pr[0].stream.loop_mode == AudioStreamWAV.LOOP_FORWARD and pr[1].stream.loop_mode == AudioStreamWAV.LOOP_FORWARD,
		"loop is set in code on both streams")
	d.free_unparented()


func test_missing_stem_falls_back_to_synth_without_error() -> void:
	var d := _dir(["sector1_combat"])   # no 'sector1' id at all
	d.request("sector1")
	Runner.T.eq(d.current_id, "sector1", "the track is still current")
	Runner.T.ok(not d.stems_on, "no stems -> synthesized beds carry it")
	Runner.T.eq(d.start_count, 0, "nothing was started")
	Runner.T.eq(d.synth_offset_db(), 0.0, "the synth beds are not muted")
	d.free_unparented()


func test_one_missing_stem_of_a_pair_falls_back() -> void:
	var d := MusicDirector.new()
	d.loader = func(path: String) -> AudioStream:
		return _wav(2.0) if path.ends_with("_combat.ogg") else null
	d.request("boss")
	Runner.T.ok(not d.stems_on, "a lone combat stem is not a track")
	d.free_unparented()


func test_length_mismatched_stems_fall_back() -> void:
	var d := _dir(["boss"], {"boss_lull": 0.5})
	d.request("boss")
	Runner.T.ok(not d.stems_on, "stems of different length could never stay locked -> fallback")
	d.free_unparented()


func test_stems_to_synth_and_back_mutes_and_unmutes_synth() -> void:
	var d := _dir(["sector1"])
	d.request("sector1")
	for _i in 120:
		d.update(1.0 / 60.0)
	Runner.T.ok(d.synth_offset_db() <= -59.0, "synth beds fall away under stems")
	d.request("sector2")        # no stems for sector2
	d.update(1.0 / 60.0, d.bar_len + 0.01)
	for _i in 120:
		d.update(1.0 / 60.0)
	Runner.T.ok(not d.stems_on, "sector2 is synth")
	Runner.T.eq(d.synth_offset_db(), 0.0, "synth beds are back at full")
	d.free_unparented()


func test_crossfade_is_equal_power_and_old_pair_is_released() -> void:
	var d := _dir(["sector1", "sector2"])
	d.request("sector1")
	for _i in 60:
		d.update(1.0 / 60.0)
	d.request("sector2")
	d.update(1.0 / 60.0, d.bar_len + 0.01)
	Runner.T.eq(d.start_count, 2, "the second pair started")
	d.update(XFADE_HALF(), -1.0)
	var g_in: float = d._pair_gain[d._slot]
	var g_out: float = d._pair_gain[1 - d._slot]
	Runner.T.ok(absf(g_in * g_in + g_out * g_out - 1.0) < 0.02, "equal power: in^2 + out^2 = 1 (%.3f)" % (g_in * g_in + g_out * g_out))
	for _i in 120:
		d.update(1.0 / 60.0)
	var old: Array = d._pairs[1 - d._slot]
	Runner.T.ok(old[0].stream == null and old[1].stream == null, "the old pair is released after the fade")
	d.free_unparented()


func XFADE_HALF() -> float:
	return MusicDirector.XFADE_SEC * 0.5


# --- stingers duck and release on a bar --------------------------------------------

func test_sting_ducks_then_releases_on_the_next_bar() -> void:
	var d := _dir(["sector1", "sting_defeat"])
	d.request("sector1")
	var played := d.play_sting("defeat")
	Runner.T.ok(played, "a present sting file is used")
	Runner.T.ok(d.sting_hold, "the score is held down")
	for _i in 30:
		d.update(1.0 / 60.0, 0.1)    # mid-bar, sting still ringing
	Runner.T.ok(d.sting_duck() > 0.3, "the score ducks (%.2f)" % d.sting_duck())
	# sting tail over (0.5 s) but no bar line yet: still ducked
	var t := 0.1
	for _i in 60:
		t = minf(t + 0.01, d.bar_len * 0.9)
		d.update(1.0 / 60.0, t)
	Runner.T.ok(d.sting_left <= 0.0, "the sting has finished")
	Runner.T.ok(d.sting_hold, "...but the score waits for the bar line to come back")
	d.update(1.0 / 60.0, d.bar_len + 0.01)
	Runner.T.ok(not d.sting_hold, "the bar line re-enters the score")
	for _i in 120:
		d.update(1.0 / 60.0, d.bar_len + 0.02)
	Runner.T.ok(d.sting_duck() < 0.05, "the duck has released (%.3f)" % d.sting_duck())
	d.free_unparented()


func test_missing_sting_still_ducks_but_reports_false() -> void:
	var d := _dir(["sector1"])
	d.request("sector1")
	Runner.T.ok(not d.play_sting("victory"), "no file -> false (the synth cue covers the sound)")
	Runner.T.ok(d.sting_hold and d.sting_left > 0.0, "the duck still happens")
	d.free_unparented()


# --- (c) danger lifts intensity -----------------------------------------------------

func test_danger_intensity_ladder() -> void:
	Runner.T.eq(MusicDirector.danger_intensity(false, -1), 0.0, "endless/unbounded adds nothing")
	Runner.T.eq(MusicDirector.danger_intensity(false, 5), 0.0, "a healthy budget adds nothing")
	var two := MusicDirector.danger_intensity(false, 2)
	var one := MusicDirector.danger_intensity(false, 1)
	var ls := MusicDirector.danger_intensity(true, 3)
	Runner.T.ok(0.0 < two and two < one and one < ls, "fewer stand-ups left sounds more urgent (%.2f < %.2f < %.2f)" % [two, one, ls])


# --- (d) hit-confirm ---------------------------------------------------------------

func test_hit_bank_loads_three_variants_per_kind() -> void:
	var sfx := Sfx.new()
	sfx._load_hit_bank()
	for kind in ["flesh", "wall"]:
		for v in 3:
			Runner.T.ok(sfx._sounds.has("hit_%s%d" % [kind, v]), "hit_%s%d is loaded from the Kenney impacts" % [kind, v])
	sfx.free()


func test_hit_confirm_throttles_to_one_per_three_frames() -> void:
	var sfx := Sfx.new()
	sfx._load_hit_bank()
	Runner.T.ok(sfx.play_hit("flesh", Vector2(100, 100), 10), "first hit plays")
	Runner.T.ok(not sfx.play_hit("flesh", Vector2(100, 100), 11), "next frame is throttled")
	Runner.T.ok(not sfx.play_hit("wall", Vector2(100, 100), 12), "two frames later is still throttled (any kind)")
	Runner.T.ok(sfx.play_hit("wall", Vector2(100, 100), 13), "three frames later plays")
	sfx.free()


func test_hit_confirm_round_robins_three_variants() -> void:
	var sfx := Sfx.new()
	sfx._load_hit_bank()
	var names: Array[String] = []
	for i in 6:
		sfx.play_hit("flesh", Vector2(50, 50), 10 + i * 3)
		names.append(sfx.last_hit_sound)
	Runner.T.eq(names.slice(0, 3), ["hit_flesh0", "hit_flesh1", "hit_flesh2"], "variants cycle in order")
	Runner.T.eq(names.slice(3, 6), names.slice(0, 3), "...and wrap")
	Runner.T.ok(sfx.last_hit_db >= -18.0 and sfx.last_hit_db <= -14.0, "level sits at -14..-18 dB (%.1f)" % sfx.last_hit_db)
	sfx.free()


func test_hit_confirm_is_wired_into_enemy_hits() -> void:
	var src := FileAccess.get_file_as_string("res://src/main.gd")
	var i := src.find("func _check_enemy_hits()")
	var j := src.find("\nfunc ", i + 10)
	Runner.T.ok(src.substr(i, j - i).contains("_sfx.play_hit("), "_check_enemy_hits calls the hit-confirm")


func test_stinger_sites_are_wired() -> void:
	var src := FileAccess.get_file_as_string("res://src/main.gd")
	for name in MusicDirector.STINGERS:
		Runner.T.ok(src.contains('_sfx.play_sting("%s")' % name), "stinger '%s' fires from main" % name)
	Runner.T.ok(src.contains("_sfx.set_music_track("), "_drive_audio picks the track")


# --- Sfx integration + leak hygiene ------------------------------------------------

func test_sfx_exposes_the_director_and_frees_cleanly() -> void:
	var sfx := Sfx.new()
	Runner.T.ok(sfx.music_director() is MusicDirector, "Sfx owns a MusicDirector")
	sfx.set_music_track("sector3")
	Runner.T.eq(sfx.music_director().current_id, "sector3", "set_music_track reaches the director")
	sfx.play_sting("victory")
	Runner.T.ok(sfx.music_director().sting_hold, "play_sting reaches the director")
	sfx.free()
