extends RefCounted
## endless-meta-retention: Veteran Points (VP), a persistent meta-currency
## banked from Endless runs (1 per wave survived) and spent on permanent,
## stacking Endless starting-loadout perks. Perks are applied post-
## construction in main.gd's _reset() -- SimWorld itself never learns a perk
## system exists, so these tests exercise the REAL main.gd, never a parallel
## re-implementation (see test_leaderboard.gd / test_menu_layout.gd for the
## same "extend the real script, stub only the risky side effects" pattern).

const Runner := preload("res://tests/run_tests.gd")
const MainScript := preload("res://src/main.gd")


class _NullSfx extends Sfx:
	func play(_sound: String, _vol_db := 0.0, _pitch := 1.0) -> void: pass


# Move the dev's real save aside to a stash file (self-healing if a previous
# crashed run left one stranded), so any test that persists to disk can never
# touch real progress. Mirrors test_menu_layout.gd's hall/daily integration tests.
func _stash_save(tag: String) -> Dictionary:
	var path: String = MainScript.SAVE_PATH
	var bak: String = MainScript.SAVE_BAK
	var stash := path + tag
	var stashb := bak + tag
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
	if FileAccess.file_exists(s["path"]):
		DirAccess.remove_absolute(s["path"])
	if FileAccess.file_exists(s["bak"]):
		DirAccess.remove_absolute(s["bak"])
	if FileAccess.file_exists(s["stash"]):
		DirAccess.rename_absolute(s["stash"], s["path"])
	if FileAccess.file_exists(s["stashb"]):
		DirAccess.rename_absolute(s["stashb"], s["bak"])


# _reset() never persists on a fresh instance (both dirty flags start false,
# so _flush_bests() writes nothing) -- no stash needed for this one.
func test_owned_perks_apply_to_a_fresh_endless_run() -> void:
	var main: Node2D = MainScript.new()   # not tree-parented: _ready never fires, no audio/sim boot
	main._sfx = _NullSfx.new()
	main._perk_levels = {MainScript.PERK_VEST: 1, MainScript.PERK_CHEST: 2, MainScript.PERK_TOKEN: 1}
	main._endless = true
	main._reset()
	Runner.T.eq(main.sim.mode, "endless", "the perk block only ever runs for an Endless run")
	for p in main.sim.players:
		Runner.T.ok(p["vest"], "VETERAN VEST tier 1 starts every player with a Flak Vest on")
	Runner.T.eq(main.sim.war_chest, main.PERK_CHEST_BONUS * 2,
		"HEAD START stacks: 2 owned tiers = 2x the per-tier War Chest bonus")
	Runner.T.eq(main.sim.tokens, 1, "SIGNAL FLARE tier 1 banks 1 Commendation at the start line")
	main.free()


func test_unowned_perks_leave_a_fresh_endless_run_untouched() -> void:
	var main: Node2D = MainScript.new()
	main._sfx = _NullSfx.new()
	main._endless = true
	main._reset()   # _perk_levels defaults to {} -- nothing bought yet
	for p in main.sim.players:
		Runner.T.ok(not p["vest"], "no VETERAN VEST owned -> no free starting vest")
	Runner.T.eq(main.sim.war_chest, 0, "no HEAD START owned -> Endless starts at the same 0 chest as ever")
	Runner.T.eq(main.sim.tokens, 0, "no SIGNAL FLARE owned -> no free starting Commendation")
	main.free()


func test_perk_levels_never_touch_a_non_endless_run() -> void:
	# The bitmask-turned-tier system must stay Endless-only -- Campaign/Arcade/
	# Boss Rush must never see a perk-boosted vest/chest/token.
	var main: Node2D = MainScript.new()
	main._sfx = _NullSfx.new()
	main._perk_levels = {MainScript.PERK_VEST: 1, MainScript.PERK_CHEST: 3, MainScript.PERK_TOKEN: 2}
	main._endless = false
	main._boss_rush = false
	main._arcade_chapter = -1
	main._reset()
	Runner.T.eq(main.sim.mode, "campaign", "sanity: this run is Campaign, not Endless")
	for p in main.sim.players:
		Runner.T.ok(not p["vest"], "owned perks must never leak a free vest into Campaign")
	Runner.T.eq(main.sim.war_chest, 0, "owned HEAD START tiers must never leak into Campaign's War Chest")
	Runner.T.eq(main.sim.tokens, 0, "owned SIGNAL FLARE tiers must never leak into Campaign's tokens")
	main.free()


func test_buy_perk_spends_vp_tiers_up_and_denies_when_short_or_maxed() -> void:
	var s := _stash_save(".emtest")
	var main: Node2D = MainScript.new()

	main.vet_points = 25
	Runner.T.ok(not main.buy_perk(MainScript.PERK_CHEST), "25 VP can't afford HEAD START tier 1 (30 VP) -- denied")
	Runner.T.eq(main.perk_level(MainScript.PERK_CHEST), 0, "a denied buy never advances the tier")
	Runner.T.eq(main.vet_points, 25, "a denied buy never spends VP")

	main.vet_points = 30
	Runner.T.ok(main.buy_perk(MainScript.PERK_CHEST), "30 VP exactly affords tier 1")
	Runner.T.eq(main.perk_level(MainScript.PERK_CHEST), 1, "tier advanced to 1")
	Runner.T.eq(main.vet_points, 0, "the exact cost was spent")

	main.vet_points = 45
	Runner.T.ok(main.buy_perk(MainScript.PERK_CHEST), "tier 2 costs 45 VP -- stacking perks get pricier per tier")
	Runner.T.eq(main.perk_level(MainScript.PERK_CHEST), 2, "tier advanced to 2")

	main.vet_points = 60
	Runner.T.ok(main.buy_perk(MainScript.PERK_CHEST), "tier 3 (max) costs 60 VP")
	Runner.T.eq(main.perk_level(MainScript.PERK_CHEST), 3, "HEAD START is now maxed (3 tiers, matching PERK_DEFS.cost.size())")

	main.vet_points = 9999
	Runner.T.ok(not main.buy_perk(MainScript.PERK_CHEST), "a maxed perk refuses to sell a 4th tier no matter the VP on hand")
	Runner.T.eq(main.vet_points, 9999, "a maxed-out denial never spends VP either")

	# VETERAN VEST is single-tier -- one buy maxes it immediately.
	main.vet_points = 40
	Runner.T.ok(main.buy_perk(MainScript.PERK_VEST), "single-tier VETERAN VEST buys at its one listed cost")
	Runner.T.eq(main.perk_level(MainScript.PERK_VEST), 1, "single-tier perk is maxed after one buy")
	Runner.T.ok(not main.buy_perk(MainScript.PERK_VEST), "a single-tier perk can't be bought twice")

	# Persistence round trip: a fresh instance reloading off disk sees the same VP + tiers.
	var main2: Node2D = MainScript.new()
	main2._load_bests()
	Runner.T.eq(main2.vet_points, main.vet_points, "_load_bests restores the exact banked VP")
	Runner.T.eq(main2.perk_level(MainScript.PERK_CHEST), 3, "_load_bests restores HEAD START's maxed tier")
	Runner.T.eq(main2.perk_level(MainScript.PERK_VEST), 1, "_load_bests restores VETERAN VEST's owned tier")
	Runner.T.eq(main2.perk_level(MainScript.PERK_TOKEN), 0, "_load_bests defaults an untouched perk to tier 0")

	main2.free()
	main.free()
	_restore_save(s)


func test_vp_awarded_only_for_endless_and_scales_with_wave() -> void:
	var s := _stash_save(".emtest2")
	var main: Node2D = MainScript.new()

	main.sim = SimWorld.new(0x5EED, 1, "campaign")
	main.sim.score = 500
	main._record_run(500)
	Runner.T.eq(main.vet_points, 0, "a Campaign run banks zero Veteran Points -- VP is an Endless-only carrot")

	main.sim = SimWorld.new(0x5EED, 1, "endless")
	main.sim.wave = 7
	main.sim.score = 700
	main._record_run(700)
	Runner.T.eq(main.vet_points, 7, "an Endless run banks 1 VP per wave survived")

	main.sim = SimWorld.new(0x5EED, 1, "endless")
	main.sim.wave = 3
	main.sim.score = 300
	main._record_run(300)
	Runner.T.eq(main.vet_points, 10, "VP accumulates across separate Endless runs (7 + 3)")

	main.free()
	_restore_save(s)


# replay-validated-leaderboards + endless-meta-retention: VP is gated behind the
# EXACT SAME score-verification flag that gates the Hall/Steam bank and the
# BANKED banner (see main.gd _apply_score_verdict / _track_bests) -- _record_run
# itself has no verified concept, so the gate has to live one level up, at the
# call site that decides whether _record_run runs at all. Driven through the
# real _apply_score_verdict (not main._record_run directly, as the test above
# does) so this proves the WIRING, not just that _record_run scales with wave.
func test_unverified_endless_run_awards_zero_vp() -> void:
	var s := _stash_save(".emtest3")
	var main: Node2D = MainScript.new()

	main.sim = SimWorld.new(0x5EED, 1, "endless")
	main.sim.wave = 9
	main.sim.score = 900
	main._apply_score_verdict(900, false)
	Runner.T.eq(main.vet_points, 0, "a failed-verification Endless run must not bank any Veteran Points")
	Runner.T.eq(main._run_vp_gain, 0, "_run_vp_gain (what the debrief card reads) stays 0 on a failed verification")

	main.sim = SimWorld.new(0x5EED, 1, "endless")
	main.sim.wave = 9
	main.sim.score = 900
	main._apply_score_verdict(900, true)
	Runner.T.eq(main.vet_points, 9, "the SAME run banks its VP once verification actually passes")
	Runner.T.eq(main._run_vp_gain, 9, "_run_vp_gain reports the exact amount just banked")

	main.free()
	_restore_save(s)
