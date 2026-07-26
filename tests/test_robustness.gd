extends RefCounted
## Edge/robustness paths: replay-file trust boundary, the checksum/events
## decoupling seam, infinite-spawn + roll-invincibility grammar, and the
## save-file data-loss paths (corrupt-primary .bak recovery + failed-write
## dirty-flag retention).

const Runner := preload("res://tests/run_tests.gd")
const MainScript := preload("res://src/main.gd")


func _write_json(path: String, data: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))


func test_replay_load_rejects_corrupt_input() -> void:
	var bad_magic := "user://tmp_test_bad_magic.json"
	_write_json(bad_magic, {"magic": "NOT_IKARI", "seed": 0, "mode": "campaign",
		"players": 1, "frames": []})
	Runner.T.ok(Replay.load_from(bad_magic) == null, "wrong magic header rejected")

	var missing_frames := "user://tmp_test_missing_frames.json"
	_write_json(missing_frames, {"magic": Replay.MAGIC, "seed": 0, "mode": "campaign",
		"players": 1})
	Runner.T.ok(Replay.load_from(missing_frames) == null, "missing 'frames' field rejected")

	var bad_frames_type := "user://tmp_test_bad_frames_type.json"
	_write_json(bad_frames_type, {"magic": Replay.MAGIC, "seed": 0, "mode": "campaign",
		"players": 1, "frames": "nope"})
	Runner.T.ok(Replay.load_from(bad_frames_type) == null, "non-array 'frames' field rejected")

	var not_a_dict := "user://tmp_test_not_a_dict.json"
	var f := FileAccess.open(not_a_dict, FileAccess.WRITE)
	f.store_string(JSON.stringify(["just", "an", "array"]))
	f.close()
	Runner.T.ok(Replay.load_from(not_a_dict) == null, "non-dictionary top-level JSON rejected")


func test_replay_load_rejects_version_mismatch() -> void:
	# Replay has no separate format_version field — MAGIC itself encodes the
	# format version (bumped to a new string on a breaking change). A file
	# stamped with a different version's magic, or with no magic at all,
	# must be rejected the same as a fully bogus file.
	var future := "user://tmp_test_future_version.json"
	_write_json(future, {"magic": "IKARI_REPLAY_2", "seed": 0, "mode": "campaign",
		"players": 1, "frames": []})
	Runner.T.ok(Replay.load_from(future) == null, "mismatched format-version magic rejected")

	var no_magic := "user://tmp_test_no_magic.json"
	_write_json(no_magic, {"seed": 0, "mode": "campaign", "players": 1, "frames": []})
	Runner.T.ok(Replay.load_from(no_magic) == null, "missing magic key entirely rejected")


func test_checksum_excludes_events_but_hashes_state() -> void:
	var sim := SimWorld.new(7, 1)
	var before := sim.checksum()
	sim.events.append({"t": "test_event", "x": 0, "y": 0})
	Runner.T.eq(sim.checksum(), before,
		"appending to events[] does not change checksum (view-only seam, checksum-excluded)")
	sim.war_chest += 50
	Runner.T.ok(sim.checksum() != before,
		"mutating a hashed field (war_chest) changes checksum")


func test_bunker_infinite_spawn_and_seal() -> void:
	var sim := SimWorld.new(4, 1)
	var bunker := {"x": 300 * Fixed.ONE, "y": -100 * Fixed.ONE, "alive": true, "spawn_cd": 1}
	sim.bunkers.clear()
	sim.bunkers.append(bunker)
	sim.enemies.clear()
	var before: int = sim.enemies.size()

	sim._step_bunkers()
	Runner.T.eq(sim.enemies.size(), before + 1, "bunker spawned infantry once its cooldown hit 0")
	Runner.T.eq(bunker["spawn_cd"], SimWorld.BUNKER_SPAWN_INTERVAL_TICKS,
		"spawn_cd reset to the full interval after spawning")

	for i in SimWorld.BUNKER_SPAWN_INTERVAL_TICKS - 1:
		sim._step_bunkers()
	Runner.T.eq(sim.enemies.size(), before + 1, "no new spawn before the interval elapses again")
	sim._step_bunkers()
	Runner.T.eq(sim.enemies.size(), before + 2,
		"bunker spawns again once the interval elapses — the 1986 infinite-spawn grammar")

	# Seal it: destroy the bunker, spawning stops even across many more intervals.
	bunker["alive"] = false
	for i in SimWorld.BUNKER_SPAWN_INTERVAL_TICKS * 3:
		sim._step_bunkers()
	Runner.T.eq(sim.enemies.size(), before + 2, "a destroyed bunker never spawns again")


func test_gated_spawn_cooldowns_never_run_negative() -> void:
	## CLASS ratchet, not an instance one. Four cooldowns share one shape: decrement
	## unconditionally, reset only when `enemies.size() < MAX_ENEMIES`. A saturated
	## roster therefore drives each of them negative forever unless it is floored.
	## Only the bunker's is player-visible — main.gd:6130 draws the hatch-charge glow
	## as `1 - spawn_cd / BUNKER_SPAWN_INTERVAL_TICKS`, which a negative pins past 100%,
	## so a blocked hatch sat glowing "about to fire". Measured before the fix
	## (tools/probe_cd_clamp.gd, 6 campaign seeds): 3 of 6 saturated, worst reached
	## -332 and lied for 1,758 ticks. The floor is behaviour-neutral — `<= 0` fires on
	## the same tick at 0 as at -332 — so this asserts the floor, never a spawn count.
	var sim := SimWorld.new(4, 1)
	var bunker := {"x": 300 * Fixed.ONE, "y": -100 * Fixed.ONE, "alive": true, "spawn_cd": 1}
	sim.bunkers.clear()
	sim.bunkers.append(bunker)
	# Saturate the roster so every reset above is refused for the whole loop.
	sim.enemies.clear()
	while sim.enemies.size() < SimWorld.MAX_ENEMIES:
		sim.enemies.append({"x": 0, "y": 0, "alive": true, "kind": 0, "hp": 1})
	var floor_held := true
	for i in 400:
		sim._step_bunkers()
		if bunker["spawn_cd"] < 0:
			floor_held = false
	Runner.T.ok(floor_held,
		"bunker spawn_cd holds at 0 while the enemy cap blocks its reset (the glow stops lying)")
	Runner.T.eq(bunker["spawn_cd"], 0, "and it rests exactly at the floor, not below it")

	# The endless wave trickle shares the shape; deep waves are where it saturates.
	var esim := SimWorld.new(4, 1, "endless")
	esim.enemies.clear()
	while esim.enemies.size() < SimWorld.MAX_ENEMIES:
		esim.enemies.append({"x": 0, "y": 0, "alive": true, "kind": 0, "hp": 1})
	esim.wave = 3
	esim.wave_pending = 5
	esim.wave_spawn_cd = 1
	var wave_floor_held := true
	for i in 400:
		esim._step_waves()
		if esim.wave_spawn_cd < 0:
			wave_floor_held = false
	Runner.T.ok(wave_floor_held, "wave_spawn_cd holds at 0 under a saturated roster too")


func test_passed_by_bunker_stops_spawning_and_is_pruned() -> void:
	## Budget leak: `bunkers` was never removed from and _step_bunkers had no
	## on-screen gate, so every passed-but-unsealed bunker kept spawning infantry
	## behind the camera — rushers that eat the shared MAX_ENEMIES budget and get
	## culled the next tick, starving the real front-line spawner on deep runs.
	var sim := SimWorld.new(4, 1)
	sim.bunkers.clear()
	sim.enemies.clear()
	var behind := {"x": 300 * Fixed.ONE, "y": sim.camera_top + 500 * Fixed.ONE,
		"alive": true, "spawn_cd": 1}
	sim.bunkers.append(behind)
	sim._step_bunkers()
	Runner.T.eq(sim.enemies.size(), 0, "a bunker below the live band spawns nothing")
	Runner.T.ok(sim.bunkers.is_empty(), "and is swept out of the array")

	# Band edge: the sweep uses the same +420 test as the enemy cull, so a bunker
	# still on screen keeps its 1986 infinite spawn.
	var edge := {"x": 300 * Fixed.ONE, "y": sim.camera_top + 420 * Fixed.ONE,
		"alive": true, "spawn_cd": 1}
	sim.bunkers.append(edge)
	sim._step_bunkers()
	Runner.T.eq(sim.enemies.size(), 1, "a bunker inside the band still spawns")
	Runner.T.eq(sim.bunkers.size(), 1, "and survives the sweep")


func test_mine_roll_safety() -> void:
	var sim := SimWorld.new(9, 1)
	var p := sim.players[0]
	p["roll_ticks"] = 5
	p["roll_iframe"] = true   # mid-roll i-frame guard now keys off this, not roll_ticks
	var mine := {"x": p["x"], "y": p["y"], "armed": true}
	sim.mines.clear()
	sim.mines.append(mine)

	sim._step_mines()
	Runner.T.ok(p["alive"], "a rolling player survives standing directly on an armed mine")
	Runner.T.ok(mine["armed"], "mine stays armed — the roll dodges the trigger, doesn't disarm it")
	Runner.T.eq(sim.mines.size(), 1, "mine is not removed (still armed, within despawn range)")


# --- save-file data-loss paths -------------------------------------------------
# The save is a single ikari_best.cfg holding EVERY section (hall/best/life/meta/
# settings/binds/replay/…), written by two read-merge-write callers (_persist and
# _record_run). Four ways it used to lose data, all covered below: a corrupt
# primary silently merging into an EMPTY config (dropping every section the caller
# doesn't rewrite), the .bak being refreshed FROM that corrupt primary (destroying
# the only recoverable copy), a failed write clearing the dirty flags anyway (a
# silent no-op save that never retried), and a single wrong-typed scalar aborting
# the loader mid-function.

# Move the dev's real save ASIDE on disk rather than deleting it, so even a hard
# exception mid-test (GDScript has no try/finally) leaves real progress
# recoverable. Mirrors test_endless_meta.gd / test_menu_layout.gd.
func _stash_save(tag: String) -> Dictionary:
	var path: String = MainScript.SAVE_PATH
	var bak: String = MainScript.SAVE_BAK
	var stash := path + tag
	var stashb := bak + tag
	# Self-heal a stranded stash — or a stranded .tmp DIRECTORY left by a crashed
	# failed-write test, which would otherwise break every real save from here on.
	if DirAccess.dir_exists_absolute(MainScript.SAVE_TMP):
		DirAccess.remove_absolute(MainScript.SAVE_TMP)
	if FileAccess.file_exists(stash) and not FileAccess.file_exists(path):
		DirAccess.rename_absolute(stash, path)
	if FileAccess.file_exists(stashb) and not FileAccess.file_exists(bak):
		DirAccess.rename_absolute(stashb, bak)
	if FileAccess.file_exists(path):
		DirAccess.rename_absolute(path, stash)
	if FileAccess.file_exists(bak):
		DirAccess.rename_absolute(bak, stashb)
	return {"path": path, "bak": bak, "stash": stash, "stashb": stashb}


func _restore_save(s: Dictionary) -> void:
	if DirAccess.dir_exists_absolute(MainScript.SAVE_TMP):
		DirAccess.remove_absolute(MainScript.SAVE_TMP)
	for p in [s["path"], s["bak"]]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(p)
	if FileAccess.file_exists(s["stash"]):
		DirAccess.rename_absolute(s["stash"], s["path"])
	if FileAccess.file_exists(s["stashb"]):
		DirAccess.rename_absolute(s["stashb"], s["bak"])


# An unterminated string value is what a torn/half-flushed write actually leaves:
# ConfigFile.load returns ERR_PARSE_ERROR. The console "ERROR: ConfigFile parse
# error" line these tests provoke is the intended diagnostic, not a failure.
const TORN_CFG := "[best]\nscore = \"torn\n"


func _write_text(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func test_persist_recovers_from_bak_when_the_primary_is_corrupt() -> void:
	var s := _stash_save(".savetest")
	var good := ConfigFile.new()
	good.set_value("hall", "runs", [{"score": 4242, "hid": 7}])
	good.set_value("best", "score", 4242)
	good.set_value("life", "runs", 9)
	good.set_value("meta", "vp", 55)
	Runner.T.eq(good.save(MainScript.SAVE_BAK), OK, "sanity: the last-good .bak snapshot wrote")
	_write_text(MainScript.SAVE_PATH, TORN_CFG)
	Runner.T.ok(ConfigFile.new().load(MainScript.SAVE_PATH) != OK, "sanity: the primary really is unparseable")

	var main := MainScript.new()   # not tree-parented: _ready never fires, no audio/sim boot
	Runner.T.eq(main._persist({"settings": {"music_vol": 7}}), OK, "_persist reports the write landed")

	var after := ConfigFile.new()
	Runner.T.eq(after.load(MainScript.SAVE_PATH), OK, "the primary is a valid config again")
	Runner.T.eq(after.get_value("settings", "music_vol", -1), 7, "_persist wrote its own section")
	Runner.T.eq(after.get_value("best", "score", -1), 4242, "[best] survived — recovered from the .bak, not silently zeroed")
	Runner.T.eq(after.get_value("meta", "vp", -1), 55, "[meta] Veteran Points survived a corrupt-primary _persist")
	Runner.T.eq(after.get_value("life", "runs", -1), 9, "[life] career totals survived a corrupt-primary _persist")
	var runs: Array = after.get_value("hall", "runs", [])
	Runner.T.eq(runs.size(), 1, "[hall] survived a corrupt-primary _persist")

	# The .bak must STILL be the good snapshot: refreshing it from the corrupt
	# primary would have destroyed the only recoverable copy mid-recovery.
	var bak := ConfigFile.new()
	Runner.T.eq(bak.load(MainScript.SAVE_BAK), OK, "the .bak was never overwritten with the corrupt primary")
	Runner.T.eq(bak.get_value("best", "score", -1), 4242, "the .bak still holds the last good [best]")
	main.free()
	_restore_save(s)


func test_record_run_recovers_from_bak_when_the_primary_is_corrupt() -> void:
	# _record_run rewrites hall/life/best/seen/meta — so a corrupt primary used to
	# cost the player their [settings], [binds] and [replay] on the debrief frame.
	var s := _stash_save(".savetest2")
	var good := ConfigFile.new()
	good.set_value("settings", "music_vol", 3)
	good.set_value("binds", "roll", KEY_J)
	good.set_value("replay", "last_score", 1234)
	Runner.T.eq(good.save(MainScript.SAVE_BAK), OK, "sanity: the last-good .bak snapshot wrote")
	_write_text(MainScript.SAVE_PATH, TORN_CFG)

	var main := MainScript.new()
	main.sim = SimWorld.new(0xC0FFEE, 1, "campaign")
	main.sim.score = 500
	main._record_run(500)

	var after := ConfigFile.new()
	Runner.T.eq(after.load(MainScript.SAVE_PATH), OK, "_record_run left a parseable save")
	Runner.T.eq(after.get_value("settings", "music_vol", -1), 3, "[settings] survived a corrupt-primary _record_run")
	Runner.T.eq(after.get_value("binds", "roll", -1), KEY_J, "[binds] survived a corrupt-primary _record_run")
	Runner.T.eq(after.get_value("replay", "last_score", -1), 1234, "[replay] survived a corrupt-primary _record_run")
	var runs: Array = after.get_value("hall", "runs", [])
	Runner.T.eq(runs.size(), 1, "the run itself still banked")
	main.free()
	_restore_save(s)


func test_failed_write_keeps_the_dirty_flags_for_a_retry() -> void:
	var s := _stash_save(".savetest3")
	# Real failure injection, not a stub: a DIRECTORY sitting where the .tmp
	# scratch file goes makes ConfigFile.save() fail, so _save_cfg never reaches
	# the rename and has to report the failure up to its caller.
	var tmp: String = MainScript.SAVE_TMP
	DirAccess.make_dir_absolute(tmp)

	var main := MainScript.new()
	main.best_score = 777
	main._best_dirty = true
	main._seen["intro"] = true
	main._seen_dirty = true
	main._flush_bests()
	Runner.T.ok(main._best_dirty, "a failed save leaves [best] dirty so the next flush retries it")
	Runner.T.ok(main._seen_dirty, "a failed save leaves [seen] dirty too")
	Runner.T.ok(not FileAccess.file_exists(MainScript.SAVE_PATH), "a failed save wrote nothing over the real file")

	# Clear the blocker — the RETAINED flags are exactly what make the next flush land.
	DirAccess.remove_absolute(tmp)
	main._flush_bests()
	Runner.T.ok(not main._best_dirty, "the retry cleared the flag once the write actually landed")
	Runner.T.ok(not main._seen_dirty, "the retry cleared the [seen] flag too")
	var after := ConfigFile.new()
	Runner.T.eq(after.load(MainScript.SAVE_PATH), OK, "the retry produced a real save")
	Runner.T.eq(after.get_value("best", "score", -1), 777, "the retry banked the best score that would otherwise have been lost")
	main.free()
	_restore_save(s)


func test_corrupt_scalar_values_never_abort_the_loader() -> void:
	# A wrong-typed scalar (a String where an int lives) used to throw on the typed
	# assignment and abort _load_bests BEFORE _apply_settings ran — the zeroed state
	# was then flushed back over the still-good save. Each bad value must cost only
	# its own field.
	var s := _stash_save(".savetest4")
	var cf := ConfigFile.new()
	cf.set_value("best", "score", "not-an-int")
	cf.set_value("meta", "vp", [1, 2, 3])
	cf.set_value("meta", "levels", "not-a-dict")
	cf.set_value("seen", "hints", 42)
	cf.set_value("life", "kills", {})
	cf.set_value("best", "wave", 12)         # a GOOD neighbour, to prove the loader kept going
	cf.set_value("settings", "captions", false)   # only reached if the loader didn't abort
	Runner.T.eq(cf.save(MainScript.SAVE_PATH), OK, "sanity: the type-corrupt save wrote")

	var main := MainScript.new()
	main._load_bests()
	Runner.T.eq(main.best_score, 0, "a String best score falls back to the default instead of throwing")
	Runner.T.eq(main.vet_points, 0, "an Array VP value falls back to the default")
	Runner.T.ok(main._perk_levels.is_empty(), "a String perk-levels value falls back to an empty map")
	Runner.T.ok(main._seen.is_empty(), "an int seen-hints value falls back to an empty map")
	Runner.T.eq(main._life_kills, 0, "a Dictionary kills value falls back to the default")
	Runner.T.eq(main.best_wave, 12, "the loader kept going — the good neighbouring field still loaded")
	Runner.T.ok(not main._captions, "_apply_settings still ran, so settings were NOT silently reverted to defaults")
	main.free()
	_restore_save(s)
