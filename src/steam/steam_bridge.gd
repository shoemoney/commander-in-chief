class_name SteamBridge
extends RefCounted
## Offline-first Steamworks facade (view-layer only, instantiated once by
## main.gd -- same pattern as Replay/Sfx, not an autoload).
##
## The sim/view split forbids Steam calls anywhere near src/sim (no
## non-deterministic engine calls in the deterministic core) -- this is a
## VIEW-side service exactly like Replay/SFX. It is built to run correctly
## with ZERO Steam present (dev box, the headless test runner, a non-Steam
## build): every public call below no-ops safely when the `Steam` engine
## singleton isn't there, so behavior is identical offline and simply
## "lights up" the moment GodotSteam + a valid steam_appid.txt are present.
##
## Wiring in a real GodotSteam build: drop the GodotSteam GDExtension under
## addons/godotsteam/, ship steam_appid.txt next to the binary -- this class
## finds the `Steam` engine singleton on its own; nothing else in the game
## needs to change. EXCEPT: GodotSteam's exact method-name surface (casing
## included) has shifted across versions and can't be pinned down without
## the real addon installed to check against -- see docs/godotsteam_api_
## version.md. Every call to `_steam` below goes through _call(), which
## checks has_method() first and push_warnings the exact missing name
## instead of an untested "Invalid call" runtime error, so a version
## mismatch fails loudly and diagnosably the first time it's exercised
## (none of this runs today -- Engine.has_singleton("Steam") is false in
## every dev/CI/non-Steam environment).
##
## assets/input/actions.vdf is the matching Steam Input action manifest --
## _init() below stages it to user:// and activates it at runtime; its
## action names mirror the verbs in main.gd's PAD_DEFAULTS/MENU_BIND_DEFAULTS.
## assets/steam/steam_rich_presence_english.vdf is NOT loaded by the game at
## runtime (Rich Presence localization has no local-file API) -- it's a
## reference artifact for pasting the "#StatusGeneric" -> "%status%" token
## into Steamworks > App Admin > Rich Presence when that page is set up.

const ACHIEVEMENTS_CACHE := "user://steam_achievements.cfg"

# Steamworks leaderboard enum values, kept as our own ints rather than read
# off `_steam` (an Object-typed variable can't statically resolve an unknown
# class constant -- same reasoning _call()'s has_method() check exists for
# methods: nothing about `_steam`'s real shape is knowable at parse time).
const LB_SORT_DESCENDING := 2   # ELeaderboardSortMethod::k_ELeaderboardSortMethodDescending
const LB_DISPLAY_NUMERIC := 1   # ELeaderboardDisplayType::k_ELeaderboardDisplayTypeNumeric

## id -> {name, desc} -- the "API Name" must match the Achievements admin page
## on the Steamworks app once one exists. Kept here so _record_run (main.gd)
## has one place to check milestones against, online or off. Every id here
## must have a matching unlock(id, ...) call in main.gd's _report_to_steam(),
## and test_steam_bridge.gd's test_achievement_ids_are_all_declared() checks
## the reverse direction (every id _report_to_steam unlocks is declared
## here) -- change one, check the other.
const ACHIEVEMENTS := {
	"FIRST_VICTORY": {"name": "Hold The Line", "desc": "Win a run."},
	"NO_DEATH_WIN": {"name": "Untouchable", "desc": "Win a run without ever going down."},
	"WAVE_10": {"name": "Dug In", "desc": "Reach wave 10 in Endless War."},
	"BOSS_RUSH_CLEAR": {"name": "Rush Hour", "desc": "Clear Boss Rush."},
	"DAILY_DONE": {"name": "Order Of The Day", "desc": "Win a Daily Run."},
	"HALL_TOP_1": {"name": "Top Of The Hall", "desc": "Set the #1 Hall of Fame score."},
}

var available := false          # true once a real Steam singleton answered init this session
var _stats_ready := false       # true once current_stats_received fires -- Steamworks requires
                                 # stats to be received before SetAchievement/StoreStats are valid,
                                 # so unlock() defers the actual Steam call until this flips (the
                                 # LOCAL cache write in unlock() is never gated -- offline is instant)
var _steam: Object = null       # the `Steam` engine singleton, when present
var _unlocked: Dictionary = {}  # local cache: achievement id -> true, so an offline unlock
                                 # is never lost and never re-fires once Steam does light up
var _pending_score := 0         # score queued for the leaderboard whose async find is in flight
var _lb_busy := false           # true while a find->upload round trip is in flight -- guards
                                 # against a second upload_score() racing the first, since
                                 # find_leaderboard/upload_leaderboard_score are both async
var _warned_missing: Dictionary = {}   # method name -> true, so a missing-method warning fires once

# Steam Input action handles (Deck/Steam Controller glyph + rebind path) --
# resolved once in _init() after the manifest in assets/input/actions.vdf is
# staged+activated. 0 means "not resolved" (no Steam Input controller at that
# slot, or the handle lookup no-op'd via _call()) -- every reader below must
# treat 0 as "keep using the raw Input/pad_pressed() fallback", never as a
# valid handle.
var _controller_handles: Array[int] = [0, 0]   # [P1, P2] connected Steam Input controller handles
var _action_set_gameplay := 0   # handle for the "Gameplay" action set (shared across controllers)
var _fire_action := 0           # handle for the "fire" AnalogTrigger action (see actions.vdf)
var _digital_actions: Dictionary = {}   # Button action name -> handle (grenade/roll/interact/revive/buy)
# Every Button action in the "Gameplay" set of assets/input/actions.vdf --
# resolved to a handle each in _refresh_action_handles() and read through
# button_pressed() below. Keep in sync with that manifest's "Button" block.
const BUTTON_ACTIONS := ["grenade", "roll", "interact", "revive", "buy"]
# FOLLOW-UP (not wired this pass, does not block Deck Verified): move/aim are
# StickPadGyro actions in actions.vdf and read fine via the raw joystick axes
# main.gd already has -- get_digital_action_data()/get_analog_action_data()
# only add value there once StickPadGyro's own handle API is needed for
# something raw axes can't do (e.g. gyro aim). _controller_handles is also
# resolved once at connect time -- a controller plugged in mid-session won't
# get Steam Input glyphs/rebinding until the next launch (add a hotplug
# refresh, e.g. polling get_connected_controllers() from process(), if that
# turns out to matter in practice).


## Calls `_steam.method(*args)` only if it actually exists on whatever Steam
## singleton is loaded -- a wrong/renamed method (see the version note at the
## top of this file) push_warnings ONCE per method instead of throwing an
## untested "Invalid call" at a random moment. Returns null when missing.
func _call(method: String, args: Array = []):
	if _steam == null or not _steam.has_method(method):
		if not _warned_missing.get(method, false):
			_warned_missing[method] = true
			push_warning("SteamBridge: Steam singleton has no method '%s' -- check docs/godotsteam_api_version.md" % method)
		return null
	return _steam.callv(method, args)


func _init() -> void:
	_load_cache()
	if not Engine.has_singleton("Steam"):
		return   # no GodotSteam addon loaded -- stay fully offline, nothing above notices
	_steam = Engine.get_singleton("Steam")
	var init: Variant = _call("steamInitEx")
	available = init is Dictionary and init.get("status", 1) == 0
	if available:
		_call("connect", ["current_stats_received", _on_stats_received])
		_call("connect", ["leaderboard_score_uploaded", _on_leaderboard_uploaded])
		_call("request_current_stats")   # -> current_stats_received once Steam answers
		# Activates the Steam Input action set from assets/input/actions.vdf so
		# Deck/Steam Controller glyphs + rebinding actually engage in-game, not
		# just exist as an uploaded config. The manifest is copied to user://
		# first: an exported build's res:// tree lives packed inside the .pck,
		# not as a real file on disk, and the Steamworks API needs a real path.
		var src := "res://assets/input/actions.vdf"
		var dst_dir := "user://steam_input"   # namespaced -- never risks clobbering an unrelated user:// file
		var dst := dst_dir + "/actions.vdf"
		var data := FileAccess.get_file_as_bytes(src)
		var copied := false
		if data.size() > 0:
			DirAccess.make_dir_recursive_absolute(dst_dir)
			var f := FileAccess.open(dst, FileAccess.WRITE)
			if f:
				f.store_buffer(data)
				f.close()
				var ok: Variant = _call("set_input_action_manifest_file_path",
					[ProjectSettings.globalize_path(dst)])
				if ok == false:
					push_warning("SteamBridge: set_input_action_manifest_file_path reported failure")
				copied = true
		if not copied:
			push_warning("SteamBridge: failed to stage actions.vdf -- Steam Input glyphs/rebinding will not activate")
		_refresh_action_handles()   # resolve handles now that the manifest is active (staging may have partially failed; the handle lookups below simply no-op via _call if so)


## Resolves the Steam Input controller + action-set + action handles the
## rest of this file polls (fire_trigger_value()/button_pressed() below).
## One-shot, called from _init() right after the action manifest is
## staged+activated -- see the FOLLOW-UP note on the handle vars above for
## what is still raw-input. Resolves BOTH player slots (get_connected_
## controllers()[0] = P1, [1] = P2, matching main.gd's device-0/device-1
## convention) so P2 gets Steam Input glyphs/rebinding too, not just P1.
func _refresh_action_handles() -> void:
	if not available:
		return
	var controllers: Variant = _call("get_connected_controllers")
	if controllers is Array:
		for i in mini(controllers.size(), _controller_handles.size()):
			_controller_handles[i] = int(controllers[i])
	var set_h: Variant = _call("get_action_set_handle", ["Gameplay"])
	if set_h is int:
		_action_set_gameplay = set_h
	if _action_set_gameplay == 0:
		return
	for handle in _controller_handles:
		if handle != 0:
			_call("activate_action_set", [handle, _action_set_gameplay])
	var fire_h: Variant = _call("get_analog_action_handle", ["fire"])
	if fire_h is int:
		_fire_action = fire_h
	for action_name in BUTTON_ACTIONS:
		var button_h: Variant = _call("get_digital_action_handle", [action_name])
		if button_h is int:
			_digital_actions[action_name] = button_h


## Reads the "fire" AnalogTrigger action (assets/input/actions.vdf) through
## the Steam Input action-HANDLE API -- the Deck-Verified-required path, as
## opposed to the raw JOY_AXIS_TRIGGER_RIGHT passthrough main.gd falls back
## to when no Steam Input controller is active (a real Steam Deck maps its
## triggers through Steam Input, not a plain XInput axis, so that raw read
## alone leaves the Deck's trigger silent). `player` is 0 (P1) or 1 (P2),
## matching main.gd's device index -- P2 gets the same Deck-safe read as P1.
## Returns -1.0 ("never fires") when Steam Input isn't wired up at that slot
## so callers can OR the comparison straight into their existing raw-axis
## check with no extra branch.
func fire_trigger_value(player: int = 0) -> float:
	if not available or player < 0 or player >= _controller_handles.size():
		return -1.0
	var controller: int = _controller_handles[player]
	if controller == 0 or _fire_action == 0:
		return -1.0
	var data: Variant = _call("get_analog_action_data", [controller, _fire_action])
	if data is Dictionary:
		# GodotSteam's InputAnalogActionData_t exposes a single-axis action's
		# pull amount as "x" (the other axis, "y", is unused for AnalogTrigger).
		return float(data.get("x", -1.0))
	return -1.0


## Reads one of the Button actions (grenade/roll/interact/revive/buy, see
## BUTTON_ACTIONS + assets/input/actions.vdf) through the Steam Input
## action-HANDLE API, same reasoning as fire_trigger_value() above -- a Deck
## in Steam Input mode routes button presses through this API, not raw
## JOY_BUTTON_* codes, so pad_pressed()'s raw read alone can miss on a real
## Deck. `player` is 0 (P1) or 1 (P2). Returns false (never satisfied) when
## Steam Input isn't wired up at that slot or `action` isn't a recognized
## Button action, so callers can OR it straight into pad_pressed() with no
## extra branch.
func button_pressed(player: int, action: String) -> bool:
	if not available or player < 0 or player >= _controller_handles.size():
		return false
	var controller: int = _controller_handles[player]
	var handle: int = int(_digital_actions.get(action, 0))
	if controller == 0 or handle == 0:
		return false
	var data: Variant = _call("get_digital_action_data", [controller, handle])
	if data is Dictionary:
		# GodotSteam's InputDigitalActionData_t exposes the button state as "bState".
		return bool(data.get("bState", false))
	return false


## Steam is the source of truth once it answers: an achievement granted
## through a different client/build (or a Steamworks admin reset) must show
## up here too, not just what THIS install's offline cache happens to know.
## Expected GodotSteam signal shape: current_stats_received(game_id: int,
## result: int, user_id: int) -- 3 args in every GodotSteam 4.x binding seen
## so far (see docs/godotsteam_api_version.md). Every param below still
## defaults to 0: Callable dispatch silently drops any args a signal emits
## BEYOND what a connected method declares, but ERRORS if the method's
## required params exceed what the signal actually provides -- a default
## on each makes this handler tolerate a leaner signal shape from some
## future/vendored GodotSteam build instead of erroring the whole callback
## pump (process() -> run_callbacks()) dead for the rest of the session.
func _on_stats_received(_game_id: int = 0, _result: int = 0, _user_id: int = 0) -> void:
	_stats_ready = true
	var pushed := false
	for id in ACHIEVEMENTS:
		var got: Variant = _call("get_achievement", [id])
		if got is Dictionary and got.get("achieved", false):
			_unlocked[id] = true   # Steam already has it -- reconcile it into the offline cache
		elif _unlocked.get(id, false):
			# Earned offline (a dev/CI/non-Steam build, or unlock() firing before this stats
			# callback returned) before Steam confirmed it -- push it up now instead of losing it.
			_call("set_achievement", [id])
			pushed = true
	if pushed:
		_call("store_stats")
	_save_cache()


func _load_cache() -> void:
	var cf := ConfigFile.new()
	var err := cf.load(ACHIEVEMENTS_CACHE)
	if err == OK:
		_unlocked = cf.get_value("achievements", "unlocked", {})
	elif err != ERR_FILE_NOT_FOUND:
		push_warning("SteamBridge: achievement cache load failed (%d) -- starting unlocked-nothing" % err)


func _save_cache() -> void:
	var cf := ConfigFile.new()
	cf.set_value("achievements", "unlocked", _unlocked)
	var err := cf.save(ACHIEVEMENTS_CACHE)
	if err != OK:
		push_warning("SteamBridge: achievement cache save failed (%d)" % err)


## Unlock once. Idempotent locally (the cache blocks a repeat) AND against
## Steam itself (SetAchievement is a no-op on an already-set stat) -- safe to
## call with the same id from every _record_run. `flush` skips the immediate
## store_stats() -- _report_to_steam (main.gd) unlocks several ids in one
## tick and calls flush_stats() once itself instead of round-tripping per id.
## If stats haven't been confirmed yet (_stats_ready), the Steam push is
## deferred entirely: _on_stats_received's reconciliation pass covers it once
## Steam is actually ready to accept it (Steamworks requires stats received
## before SetAchievement/StoreStats are valid).
func unlock(id: String, flush := true) -> void:
	if not ACHIEVEMENTS.has(id):
		push_warning("SteamBridge: unlock() called with an undeclared id '%s'" % id)
		return
	if _unlocked.get(id, false):
		return
	_unlocked[id] = true
	_save_cache()
	if available and _stats_ready:
		_call("set_achievement", [id])
		if flush:
			_call("store_stats")


## Flushes any unlock(id, false) calls made since the last flush. Safe to
## call even when nothing changed (store_stats is a cheap no-op then).
func flush_stats() -> void:
	if available and _stats_ready:
		_call("store_stats")


## Posts a run's score to that mode's leaderboard (created server-side on
## first upload). find_or_create_leaderboard is async on real Steam; the
## upload itself happens in _on_leaderboard_found once the result signal
## fires. A call that arrives while one is already in flight is dropped
## (ponytail: a run only ends once today; queueing multiple in-flight
## uploads is unneeded until a caller can actually race itself).
func upload_score(mode: String, score: int) -> void:
	if not available or _lb_busy:
		return
	_lb_busy = true
	_pending_score = score
	if not _call("is_connected", ["leaderboard_find_result", _on_leaderboard_found]):
		_call("connect", ["leaderboard_find_result", _on_leaderboard_found])
	# find_or_create (not a plain find): the leaderboard doesn't exist on Steam's
	# side until something creates it, and this bridge is that first upload.
	_call("find_or_create_leaderboard", ["scores_%s" % mode, LB_SORT_DESCENDING, LB_DISPLAY_NUMERIC])


## Expected GodotSteam signal shape: leaderboard_find_result(handle: int,
## found: int) -- 2 args (found is 0/1, not a bool, per GodotSteam convention).
## Both default to 0 for the same reason _on_stats_received's params do --
## a signal that emits fewer args than declared here would otherwise error
## instead of just landing on the safe "not found" branch below.
func _on_leaderboard_found(handle: int = 0, found: int = 0) -> void:
	if found == 0:
		push_warning("SteamBridge: leaderboard not found, score not uploaded")
		_lb_busy = false
		return
	_call("upload_leaderboard_score", [_pending_score, true, [], handle])


## Expected GodotSteam signal shape: leaderboard_score_uploaded(...) -- varies
## the most of the three handlers in this file by binding version: a plain
## bool success flag on some, a result Dictionary with a "success" key on
## others, an int result code on others, and some versions emit additional
## positional args (score, changed rank, ...) after the primary result --
## Callable dispatch drops those silently since only one param is declared
## here. `result` defaults to null so a version that emits ZERO args (or
## none at all) still lands in the explicit "unknown" branch below instead
## of erroring the handler outright.
func _on_leaderboard_uploaded(result: Variant = null) -> void:
	# A failed OR ambiguous (null -- no usable arg came through) upload is
	# logged, not retried: the score is already safe in the local Hall of
	# Fame (main.gd), so this only ever costs a leaderboard entry, never
	# player progress.
	var failed: bool = result == null or \
		(result is bool and not result) or \
		(result is int and result == 0) or \
		(result is Dictionary and not result.get("success", true))
	if failed:
		push_warning("SteamBridge: leaderboard score upload failed")
	_lb_busy = false


## Rich Presence: a short "what are they doing" string for the friends list
## and the Deck quick-access overlay. Cheap enough to call on every
## menu/run-state transition.
func set_presence(status: String) -> void:
	if available:
		_call("set_rich_presence", ["steam_display", "#StatusGeneric"])
		_call("set_rich_presence", ["status", status])


## Pumps the Steamworks callback queue -- every async result above (stats,
## achievements, leaderboards) is only ever DELIVERED via this call, so it
## must run every frame once Steam is present. Call from main.gd's _process.
func process() -> void:
	if available:
		_call("run_callbacks")
