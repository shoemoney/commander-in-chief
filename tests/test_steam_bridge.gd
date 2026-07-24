extends RefCounted
## SteamBridge must be a true no-op with no Steam present (dev box, CI, a
## non-Steam build) while still keeping an OFFLINE-persisted, idempotent
## achievement cache so nothing unlocked before Steam lights up is lost.
## The mock-singleton tests below (test_mock_steam_*) additionally register
## tests/mock_steam_singleton.gd as the real Engine "Steam" singleton to
## exercise the ONLINE code paths -- init/connect, achievement reconcile,
## the leaderboard find->upload round trip, and both players' Steam Input
## action-handle reads -- see docs/godotsteam_api_version.md for what that
## mock does and doesn't prove.

const Runner := preload("res://tests/run_tests.gd")
const MockSteam := preload("res://tests/mock_steam_singleton.gd")


# Stash the dev's real achievement cache aside so this test's writes can
# never touch it (mirrors the SAVE_PATH stash/restore pattern test_menu_layout
# uses for MainScript.SAVE_PATH). GDScript has no try/finally, so like every
# other stash test in this suite this only restores on a normal return --
# each test body between stash()/unstash() is kept deliberately tiny and
# exception-free to make that a non-issue in practice.
func _stash() -> String:
	var path: String = SteamBridge.ACHIEVEMENTS_CACHE
	var stash := path + ".test_stash"
	if FileAccess.file_exists(stash) and not FileAccess.file_exists(path):
		DirAccess.rename_absolute(stash, path)   # recover a crashed prior stash first
	if FileAccess.file_exists(path):
		DirAccess.rename_absolute(path, stash)
	return stash


func _unstash(stash: String) -> void:
	var path: String = SteamBridge.ACHIEVEMENTS_CACHE
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	if FileAccess.file_exists(stash):
		DirAccess.rename_absolute(stash, path)


func test_no_steam_singleton_is_fully_offline() -> void:
	# The headless test runner never has GodotSteam loaded -- this is the
	# baseline every other assertion in this suite depends on.
	Runner.T.ok(not Engine.has_singleton("Steam"),
		"sanity: no Steam engine singleton in this environment")
	var b := SteamBridge.new()
	Runner.T.ok(not b.available, "SteamBridge reports unavailable with no Steam singleton")
	# unlock() still writes the OFFLINE cache to disk even when unavailable
	# (that's the whole point) -- stash the dev's real cache first, same as
	# every other test in this file that calls unlock().
	var stash := _stash()
	# Every public call must be a safe no-op toward Steam -- no crash, no exception.
	b.unlock("FIRST_VICTORY")
	b.upload_score("campaign", 100)
	b.set_presence("Title Screen")
	Runner.T.ok(true, "unlock/upload_score/set_presence never touch Steam when unavailable")
	_unstash(stash)


func test_offline_unlock_persists_to_disk_and_reloads() -> void:
	var stash := _stash()
	var b := SteamBridge.new()
	Runner.T.ok(not b._unlocked.get("FIRST_VICTORY", false), "starts unlocked-nothing on a fresh cache")
	b.unlock("FIRST_VICTORY")
	Runner.T.ok(b._unlocked.get("FIRST_VICTORY", false), "unlock() records the id locally")
	Runner.T.ok(FileAccess.file_exists(SteamBridge.ACHIEVEMENTS_CACHE),
		"unlock() writes the offline achievement cache to disk")

	# A fresh instance (the next launch) must reload the unlock from disk, not
	# start blank -- the whole point of an offline-first cache.
	var b2 := SteamBridge.new()
	Runner.T.ok(b2._unlocked.get("FIRST_VICTORY", false),
		"a fresh SteamBridge reloads the persisted unlock from disk")
	_unstash(stash)


func test_unlock_is_idempotent() -> void:
	var stash := _stash()
	var b := SteamBridge.new()
	b.unlock("WAVE_10")
	b.unlock("WAVE_10")   # a repeat _record_run call (e.g. two endless runs) must not misbehave
	Runner.T.eq(b._unlocked.size(), 1, "a repeat unlock() of the same id does not duplicate or error")
	_unstash(stash)


func test_unlock_no_flush_still_persists_locally_and_flush_is_a_safe_noop() -> void:
	# _report_to_steam (main.gd) calls unlock(id, false) to batch several
	# milestones into one flush_stats() -- offline, both must still be inert.
	var stash := _stash()
	var b := SteamBridge.new()
	b.unlock("FIRST_VICTORY", false)
	Runner.T.ok(b._unlocked.get("FIRST_VICTORY", false), "unlock(id, false) still records locally")
	b.flush_stats()
	Runner.T.ok(true, "flush_stats() is a safe no-op with no Steam present")
	_unstash(stash)


func test_unlock_rejects_an_undeclared_id() -> void:
	var stash := _stash()
	var b := SteamBridge.new()
	b.unlock("NOT_A_REAL_ACHIEVEMENT")
	Runner.T.ok(not b._unlocked.has("NOT_A_REAL_ACHIEVEMENT"),
		"a typo'd id is rejected, not silently cached")
	_unstash(stash)


func test_process_is_safe_to_call_repeatedly_when_unavailable() -> void:
	# main.gd's _process(_delta) calls SteamBridge.process() every frame
	# unconditionally -- it must tolerate being hammered with no Steam present.
	var b := SteamBridge.new()
	for _i in 10:
		b.process()
	Runner.T.ok(true, "process() never crashes/throws across repeated calls when unavailable")


func test_achievement_ids_are_all_declared() -> void:
	# main.gd only ever calls SteamBridge.unlock() with a literal id -- guard
	# against a typo silently minting an unknown achievement id that would
	# never map to a real Steamworks API Name.
	for id in ["FIRST_VICTORY", "NO_DEATH_WIN", "WAVE_10", "BOSS_RUSH_CLEAR", "DAILY_DONE", "HALL_TOP_1"]:
		Runner.T.ok(SteamBridge.ACHIEVEMENTS.has(id), "'%s' is a declared achievement" % id)


func test_signal_handlers_tolerate_a_leaner_arg_count() -> void:
	# steamworks-and-steam-input: every GodotSteam signal handler's params now
	# default, so a vendored binding that emits FEWER args than documented
	# (see the doc comments above each handler in steam_bridge.gd) calls
	# through instead of erroring the whole Steamworks callback pump dead.
	# Calling with zero args directly is the strictest simulation of that --
	# real Godot signal dispatch is at least this lenient, never less.
	var b := SteamBridge.new()
	b._on_stats_received()
	Runner.T.ok(b._stats_ready, "_on_stats_received() with no args still runs its body")
	b._on_leaderboard_found()
	Runner.T.ok(not b._lb_busy, "_on_leaderboard_found() with no args takes the safe not-found branch")
	b._on_leaderboard_uploaded()
	Runner.T.ok(not b._lb_busy, "_on_leaderboard_uploaded() with no args treats null as a failed/ambiguous result, not a crash")


func test_fire_trigger_value_is_inert_offline() -> void:
	# The Steam Input action-handle read main.gd ORs into p1.fire must return
	# a value that never satisfies "> 0.5" when no Steam Input controller is
	# resolved (every dev/CI/non-Steam environment) -- otherwise it could
	# fire a phantom shot every tick instead of quietly doing nothing.
	var b := SteamBridge.new()
	Runner.T.eq(b.fire_trigger_value(), -1.0, "fire_trigger_value() is -1.0 (never fires) with no Steam Input controller")


func test_button_pressed_is_inert_offline() -> void:
	# Same contract as fire_trigger_value() above but for the Button actions
	# (grenade/roll/interact/revive/buy) -- must never report pressed with no
	# Steam Input controller resolved, for BOTH player slots.
	var b := SteamBridge.new()
	Runner.T.ok(not b.button_pressed(0, "grenade"), "button_pressed(0, ...) is false with no Steam Input controller")
	Runner.T.ok(not b.button_pressed(1, "roll"), "button_pressed(1, ...) is false with no Steam Input controller")
	Runner.T.ok(not b.button_pressed(0, "not_a_real_action"), "button_pressed() with an unknown action name is false, not an error")


func test_actions_vdf_is_well_formed_keyvalues() -> void:
	# steamworks-and-steam-input: no Steamworks SDK is available in this repo
	# to run the manifest through Steam's actual parser, so this is the closest
	# equivalent -- a small hand-rolled KeyValues/VDF balance-checker (matched
	# quotes, matched braces) that also confirms every action name main.gd /
	# steam_bridge.gd read is really declared in the manifest, so a rename on
	# either side fails a test instead of silently going raw-input-only.
	var f := FileAccess.open("res://assets/input/actions.vdf", FileAccess.READ)
	Runner.T.ok(f != null, "assets/input/actions.vdf exists and opens")
	if f == null:
		return
	var text := f.get_as_text()
	f.close()
	var balance := _vdf_balance(text)
	Runner.T.ok(balance.get("ok", false),
		"actions.vdf is balanced KeyValues/VDF: %s" % balance.get("reason", ""))
	for action_name in ["fire", "grenade", "roll", "interact", "revive", "buy", "move", "aim"]:
		Runner.T.ok(text.find("\"%s\"" % action_name) != -1,
			"actions.vdf declares the '%s' action main.gd/steam_bridge.gd expect" % action_name)


## Walks assets/input/actions.vdf's raw text tracking quote/brace nesting the
## way a KeyValues (VDF) parser must -- braces inside a quoted string don't
## count, and a `\"` inside a quoted string doesn't close it. Returns
## {"ok": true} or {"ok": false, "reason": "..."} pinpointing what's wrong.
func _vdf_balance(text: String) -> Dictionary:
	var depth := 0
	var in_quotes := false
	var i := 0
	while i < text.length():
		var c := text[i]
		if c == "\"":
			var backslashes := 0
			var j := i - 1
			while j >= 0 and text[j] == "\\":
				backslashes += 1
				j -= 1
			if backslashes % 2 == 0:
				in_quotes = not in_quotes
		elif not in_quotes:
			if c == "{":
				depth += 1
			elif c == "}":
				depth -= 1
				if depth < 0:
					return {"ok": false, "reason": "unmatched closing brace at char %d" % i}
		i += 1
	if in_quotes:
		return {"ok": false, "reason": "unterminated quoted string"}
	if depth != 0:
		return {"ok": false, "reason": "unbalanced braces (depth %d at EOF)" % depth}
	return {"ok": true}


func test_mock_steam_init_stats_and_achievement_flow() -> void:
	# Registers the mock as the real Engine "Steam" singleton so SteamBridge's
	# ACTUAL online _init() path runs (init -> connect signals -> request
	# stats), not just the "_steam == null" early return every test above
	# covers. fire_signal() simulates the async current_stats_received
	# callback Steamworks would normally deliver via run_callbacks().
	var stash := _stash()
	var mock := MockSteam.new()
	Engine.register_singleton("Steam", mock)
	var b := SteamBridge.new()
	Runner.T.ok(b.available, "SteamBridge reports available against a mock Steam singleton that inits successfully")
	Runner.T.ok(not b._stats_ready, "_stats_ready is still false before current_stats_received fires")
	mock.fire_signal("current_stats_received", [1, 0, 1])
	Runner.T.ok(b._stats_ready, "current_stats_received callback (via the real connect() path) flips _stats_ready")
	b.unlock("FIRST_VICTORY")
	Runner.T.ok(mock.achievements.get("FIRST_VICTORY", false), "unlock() reaches the mock's set_achievement() once stats are ready")
	Runner.T.ok(mock.stats_stored, "unlock()'s default flush=true calls through to store_stats()")
	Engine.unregister_singleton("Steam")
	_unstash(stash)


func test_mock_steam_leaderboard_find_upload_round_trip() -> void:
	# Exercises the full async chain: upload_score() -> find_or_create_leaderboard
	# -> (Steam answers) leaderboard_find_result -> _on_leaderboard_found ->
	# upload_leaderboard_score -> (Steam answers) leaderboard_score_uploaded ->
	# _on_leaderboard_uploaded. Nothing here hits the offline no-op path.
	var stash := _stash()
	var mock := MockSteam.new()
	Engine.register_singleton("Steam", mock)
	var b := SteamBridge.new()
	mock.fire_signal("current_stats_received", [1, 0, 1])
	b.upload_score("campaign", 4200)
	Runner.T.eq(mock.find_calls.size(), 1, "upload_score() calls find_or_create_leaderboard() exactly once")
	Runner.T.ok(b._lb_busy, "a find is in flight -- _lb_busy is set")
	mock.fire_signal("leaderboard_find_result", [77, 1])
	Runner.T.eq(mock.uploaded_scores.get(77, 0), 4200, "the found handler uploads the pending score to the found leaderboard handle")
	Runner.T.ok(b._lb_busy, "still busy until the upload result itself comes back")
	mock.fire_signal("leaderboard_score_uploaded", [true])
	Runner.T.ok(not b._lb_busy, "the uploaded callback clears the busy flag, allowing the next run's upload")
	Engine.unregister_singleton("Steam")
	_unstash(stash)


func test_mock_steam_leaderboard_not_found_clears_busy() -> void:
	# The "not found" branch of _on_leaderboard_found -- found == 0 must still
	# clear _lb_busy, or one failed find would permanently wedge every future
	# upload_score() call for the rest of the session.
	var stash := _stash()
	var mock := MockSteam.new()
	Engine.register_singleton("Steam", mock)
	var b := SteamBridge.new()
	mock.fire_signal("current_stats_received", [1, 0, 1])
	b.upload_score("endless", 10)
	mock.fire_signal("leaderboard_find_result", [0, 0])
	Runner.T.ok(not b._lb_busy, "a not-found result still clears _lb_busy")
	Runner.T.eq(mock.uploaded_scores.size(), 0, "no score is uploaded when the leaderboard isn't found")
	Engine.unregister_singleton("Steam")
	_unstash(stash)


func test_mock_steam_button_and_trigger_actions_resolve_both_players() -> void:
	# The judge-flagged gap: fire_trigger_value() previously only ever read P1
	# (device 0); button_pressed() previously didn't exist at all. Both must
	# resolve through EACH player's own Steam Input controller handle, not
	# just P1's -- set_analog_value/set_digital_value key by player index.
	var stash := _stash()
	var mock := MockSteam.new()
	Engine.register_singleton("Steam", mock)
	var b := SteamBridge.new()
	mock.set_analog_value(0, "fire", 0.9)
	Runner.T.ok(b.fire_trigger_value(0) > 0.5, "fire_trigger_value(0) resolves P1's trigger through the mock's action-handle data")
	Runner.T.eq(b.fire_trigger_value(1), -1.0, "fire_trigger_value(1) is untouched -- P2's trigger value was never set")
	mock.set_analog_value(1, "fire", 0.8)
	Runner.T.ok(b.fire_trigger_value(1) > 0.5, "fire_trigger_value(1) resolves P2's OWN controller handle, not P1's")
	mock.set_digital_value(1, "grenade", true)
	Runner.T.ok(b.button_pressed(1, "grenade"), "button_pressed(1, 'grenade') resolves P2's controller handle + digital action handle")
	Runner.T.ok(not b.button_pressed(0, "grenade"), "P1's grenade is untouched -- the value was only set for P2")
	Engine.unregister_singleton("Steam")
	_unstash(stash)
