extends RefCounted
## The soundtrack and the director that plays it were built in parallel, in separate
## worktrees, against a written contract — each one tested alone, neither one ever having
## seen the other. This suite is where they meet.
##
## It exists because the director's fallback is SILENT by design: a missing stem, a load
## failure, or a combat/lull pair whose lengths differ by 10 ms all quietly hand the track
## back to the old synthesized drum loop. That is the right behaviour at runtime and the
## worst possible behaviour for noticing a broken contract — the game would boot, play
## "music", pass every director test (those use fixture streams), and ship the score it was
## supposed to replace. So: real files, real manifest, default loader, and every id the
## director can pick has to come up on STEMS.

const Runner := preload("res://tests/run_tests.gd")

const LOOPS := ["title", "sector1", "sector2", "sector3", "sector4", "sector5", "sector6",
		"boss", "shop", "laststand"]
const STINGS := ["boss_intro", "sector_clear", "victory", "defeat"]


func test_manifest_lists_every_id_the_director_can_pick() -> void:
	var d := MusicDirector.new()
	var tracks: Dictionary = d.manifest.get("tracks", {})
	var stings: Dictionary = d.manifest.get("stingers", {})
	Runner.T.ok(not tracks.is_empty(), "the shipped manifest loaded (assets/music/manifest.json)")
	for id in LOOPS:
		Runner.T.ok(tracks.has(id), "manifest has loop '%s'" % id)
		Runner.T.ok(float(tracks.get(id, {}).get("bpm", 0)) >= 60.0, "loop '%s' declares a real tempo" % id)
	for s in STINGS:
		Runner.T.ok(stings.has(s), "manifest has stinger '%s'" % s)
	# Every id pick_track() can return must be one of the loops that exists.
	var pickable := {}
	for sec in 6:
		pickable[MusicDirector.pick_track("play", sec, false, false, false, "")] = true
	pickable[MusicDirector.pick_track("title", 0, false, false, false, "")] = true
	pickable[MusicDirector.pick_track("play", 0, true, false, false, "")] = true
	pickable[MusicDirector.pick_track("play", 0, false, true, false, "")] = true
	pickable[MusicDirector.pick_track("play", 0, false, false, true, "")] = true
	for id in pickable:
		Runner.T.ok(tracks.has(id), "pick_track can return '%s' and the soundtrack ships it" % id)
	d.free_unparented()


func test_every_loop_plays_from_shipped_stems_not_the_synth_fallback() -> void:
	for id in LOOPS:
		var d := MusicDirector.new()
		d.request(id)
		Runner.T.ok(d.stems_on, "'%s' comes up on real stems, not the synth fallback" % id)
		Runner.T.eq(d.last_started, [id + "_combat", id + "_lull"], "'%s' started its own stem pair" % id)
		var info: Dictionary = d.manifest.get("tracks", {}).get(id, {})
		var want_bar := 60.0 / float(info.get("bpm", 1.0)) * float(info.get("beats_per_bar", 4))
		Runner.T.ok(absf(d.bar_len - want_bar) < 0.0001, "'%s' quantises to its own bar (%.3f s)" % [id, d.bar_len])
		# The pair must stay sample-locked, and a loop that is not a whole number of bars
		# would drift against the bar clock on every wrap.
		var pr: Array = d._pairs[d._slot]
		var c: AudioStream = pr[0].stream
		var l: AudioStream = pr[1].stream
		Runner.T.ok(c != null and l != null, "'%s' has both stems on the players" % id)
		if c != null and l != null:
			Runner.T.ok(absf(c.get_length() - l.get_length()) < 0.01,
				"'%s' combat and lull are the same length (%.3f vs %.3f s)" % [id, c.get_length(), l.get_length()])
			var bars := c.get_length() / want_bar
			Runner.T.ok(absf(bars - roundf(bars)) < 0.02,
				"'%s' loops on a bar line (%.3f bars)" % [id, bars])
			Runner.T.ok(bool(c.get("loop")) and bool(l.get("loop")), "'%s' stems are set to loop" % id)
		d.free_unparented()


func test_every_stinger_plays_from_its_shipped_file() -> void:
	for s in STINGS:
		var d := MusicDirector.new()
		d.request("sector1")
		Runner.T.ok(d.play_sting(s), "stinger '%s' plays its file, not the silent duck-only fallback" % s)
		Runner.T.ok(d.sting_left >= 1.0 and d.sting_left <= 8.0,
			"stinger '%s' is a one-shot of sane length (%.2f s)" % [s, d.sting_left])
		d.free_unparented()
