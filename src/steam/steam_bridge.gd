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
## Targets GodotSteam 4.22.1 / Steamworks 1.65. The method and signal surface
## was checked against its official Godot 4.7.2 macOS module build, without
## initializing Steam. See docs/godotsteam_api_version.md for the pinned
## source, binary hash, reproduction command and remaining live-account gates.
## Plain Godot remains offline. This is not a Steam Deck certification claim.
##
## assets/input/actions.vdf is the matching Steam Input action manifest --
## _init() below stages it to user:// and activates it at runtime; its
## action names mirror the verbs in main.gd's PAD_DEFAULTS/MENU_BIND_DEFAULTS.
## assets/steam/steam_rich_presence_english.vdf is NOT loaded by the game at
## runtime (Rich Presence localization has no local-file API) -- it's a
## reference artifact for pasting the "#StatusGeneric" -> "%status%" token
## into Steamworks > App Admin > Rich Presence when that page is set up.

const ACHIEVEMENTS_CACHE := "user://steam_achievements.cfg"
const ACHIEVEMENTS_SCHEMA := 1

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
var _stats_ready := false       # our reconciliation gate: successful own-account refresh
                                 # before pushing that account's cached unlocks
var _steam: Object = null       # the `Steam` engine singleton, when present
var _steam_user_id := 0
var _input_ready := false
var _input_devices_dirty := false
var _cache_writable := true
var _cache_primary_valid := false
var _unlocked: Dictionary = {}  # local cache: achievement id -> true, so an offline unlock
                                 # is never lost and never re-fires once Steam does light up
var _pending_score := 0         # score queued for the leaderboard whose async find is in flight
var _lb_busy := false           # true while a find->upload round trip is in flight -- guards
                                 # against a second upload_score() racing the first, since
                                 # find_leaderboard/uploadLeaderboardScore are both async
var _warned_missing: Dictionary = {}   # method name -> true, so a missing-method warning fires once

# Steam Input action handles (Deck/Steam Controller glyph + rebind path) --
# resolved after setup and refreshed after Steam device callbacks.
# 0 means "not resolved" (no Steam Input controller at that
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
# Remaining hardware work: move/aim still use raw axes. Rebinding, raw-device
# mapping and physical reconnect behavior need real Steam Input tests. Surviving
# Steam handles retain their seats when another device leaves or the list reorders.


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
	if not Engine.has_singleton("Steam"):
		_load_cache()
		return   # no GodotSteam addon loaded -- stay fully offline, nothing above notices
	_steam = Engine.get_singleton("Steam")
	var init: Variant = _call("steamInitEx")
	available = init is Dictionary and init.get("status", 1) == 0
	if not available:
		_load_cache()
		return
	if available:
		_call("connect", ["user_stats_received", _on_stats_received])
		_call("connect", ["leaderboard_score_uploaded", _on_leaderboard_uploaded])
		var user_id: Variant = _call("getSteamID")
		if user_id is int and user_id > 0:
			_steam_user_id = user_id
			_load_cache()   # account-owned data only; never merge the anonymous cache
			# Current stats are preloaded by modern Steam clients. This explicit
			# refresh gates our offline-cache reconciliation on a successful reply.
			_call("requestUserStats", [_steam_user_id])
		else:
			available = false
			_load_cache()
			return
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
				var ok: Variant = _call("setInputActionManifestFilePath",
					[ProjectSettings.globalize_path(dst)])
				if ok != true:
					push_warning("SteamBridge: setInputActionManifestFilePath reported failure")
				copied = ok == true
		if not copied:
			push_warning("SteamBridge: failed to stage actions.vdf -- Steam Input glyphs/rebinding will not activate")
		if copied:
			_input_ready = _call("inputInit", [false]) == true
		if _input_ready:
			_call("connect", ["input_device_connected", _on_input_device_connected])
			_call("connect", ["input_device_disconnected", _on_input_device_disconnected])
			_call("enableDeviceCallbacks")
			_refresh_action_handles()


## Resolves the Steam Input controller + action-set + action handles the
## rest of this file polls (fire_trigger_value()/button_pressed() below).
## Called after setup and after the callback pump reports device changes.
## Preserve connected players' seats; new handles fill only vacant slots.
## Enumeration order initializes seats but never moves a surviving controller.
func _refresh_action_handles() -> void:
	_input_devices_dirty = false
	_action_set_gameplay = 0
	_fire_action = 0
	_digital_actions.clear()
	if not available or not _input_ready:
		_controller_handles.fill(0)
		return
	var controllers: Variant = _call("getConnectedControllers")
	var connected: Array[int] = []
	if controllers is Array:
		for handle in controllers:
			if handle is int and handle > 0 and not connected.has(handle):
				connected.append(handle)
	for i in _controller_handles.size():
		if not connected.has(_controller_handles[i]):
			_controller_handles[i] = 0
	for handle in connected:
		if _controller_handles.has(handle):
			continue
		var seat := _controller_handles.find(0)
		if seat == -1:
			break
		_controller_handles[seat] = handle
	var set_h: Variant = _call("getActionSetHandle", ["Gameplay"])
	if set_h is int:
		_action_set_gameplay = set_h
	if _action_set_gameplay == 0:
		return
	for handle in _controller_handles:
		if handle != 0:
			_call("activateActionSet", [handle, _action_set_gameplay])
	var fire_h: Variant = _call("getAnalogActionHandle", ["fire"])
	if fire_h is int:
		_fire_action = fire_h
	for action_name in BUTTON_ACTIONS:
		var button_h: Variant = _call("getDigitalActionHandle", [action_name])
		if button_h is int:
			_digital_actions[action_name] = button_h


func _on_input_device_connected(_input_handle: int) -> void:
	if _input_ready:
		_input_devices_dirty = true


func _on_input_device_disconnected(input_handle: int) -> void:
	if not _input_ready:
		return
	# Invalidate immediately; refresh once after the complete callback batch.
	for i in _controller_handles.size():
		if _controller_handles[i] == input_handle:
			_controller_handles[i] = 0
	_input_devices_dirty = true


## Reads the "fire" AnalogTrigger action through the pinned Steam Input API.
## `player` is 0 (P1) or 1 (P2). main.gd retains its raw-input fallback.
## Returns -1.0 ("never fires") when Steam Input isn't wired up at that slot
## so callers can OR the comparison straight into their existing raw-axis
## check with no extra branch.
func fire_trigger_value(player: int = 0) -> float:
	if not available or player < 0 or player >= _controller_handles.size():
		return -1.0
	var controller: int = _controller_handles[player]
	if controller == 0 or _fire_action == 0:
		return -1.0
	var data: Variant = _call("getAnalogActionData", [controller, _fire_action])
	if data is Dictionary and data.get("active", false):
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
	var data: Variant = _call("getDigitalActionData", [controller, handle])
	if data is Dictionary:
		# GodotSteam 4.22.1 maps the SDK's bState/bActive to state/active.
		return bool(data.get("active", false)) and bool(data.get("state", false))
	return false


## Steam is the source of truth once it answers: an achievement granted
## through a different client/build (or a Steamworks admin reset) must show
## up here too, not just what THIS install's offline cache happens to know.
## Verified 4.22.1 signal: user_stats_received(game_id, result, user_id).
## Defaults reject an incomplete callback without authorizing a cache push.
func _on_stats_received(_game_id: int = 0, _result: int = 0, _user_id: int = 0) -> void:
	# EResult OK is 1, not 0. Other-user and failed callbacks must not
	# reconcile this account's offline unlocks or enable writes.
	if not available or _result != 1 or _steam_user_id == 0 or _user_id != _steam_user_id:
		return
	_stats_ready = true
	var pushed := false
	for id in ACHIEVEMENTS:
		var got: Variant = _call("getAchievement", [id])
		if not (got is Dictionary) or not got.get("ret", false):
			continue   # unknown/unpublished achievement is not a confirmed locked one
		if got.get("achieved", false):
			_unlocked[id] = true   # Steam already has it -- reconcile it into the offline cache
		elif _unlocked.get(id, false):
			# Earned under this Steam identity before the refresh returned.
			# Anonymous/legacy caches are never included in this reconciliation.
			_call("setAchievement", [id])
			pushed = true
	if pushed:
		_call("storeStats")
	_save_cache()


static func achievement_cache_path(user_id: int) -> String:
	if user_id <= 0:
		return ACHIEVEMENTS_CACHE   # legacy/unattributed progress remains local
	return "user://steam_accounts/%d/achievements.cfg" % user_id


func _read_cache(path: String) -> Dictionary:
	var cf := ConfigFile.new()
	if cf.load(path) != OK:
		return {"valid": false, "protected": false}
	var version: Variant = cf.get_value("cache", "version", 0)
	if not (version is int) or version < 0:
		return {"valid": false, "protected": true}
	if version > ACHIEVEMENTS_SCHEMA:
		return {"valid": false, "protected": true}
	# Only the anonymous file may migrate the old ownerless schema.
	if (version == 0 and _steam_user_id != 0) or (version == 1 and
			cf.get_value("cache", "account", "") != str(_steam_user_id)):
		return {"valid": false, "protected": true}
	var data: Variant = cf.get_value("achievements", "unlocked", null)
	if not (data is Dictionary):
		return {"valid": false, "protected": false}
	var validated := {}
	for id in data:
		if not (id is String) or not (data[id] is bool):
			return {"valid": false, "protected": false}
		if ACHIEVEMENTS.has(id) and data[id]:
			validated[id] = true
	return {"valid": true, "protected": false, "unlocked": validated}


func _load_cache() -> void:
	_unlocked.clear()
	_cache_writable = true
	_cache_primary_valid = false
	var path := achievement_cache_path(_steam_user_id)
	var primary := _read_cache(path)
	if primary.valid:
		_unlocked = primary.unlocked
		_cache_primary_valid = true
		return
	if primary.protected:
		_cache_writable = false
		push_warning("SteamBridge: cache owner/schema mismatch; preserving file without using it")
		return
	var backup := _read_cache(path + ".bak")
	if backup.valid:
		_unlocked = backup.unlocked
		push_warning("SteamBridge: recovered achievement cache from backup")
	elif backup.protected:
		_cache_writable = false
		push_warning("SteamBridge: backup owner/schema mismatch; preserving files without using them")
	elif FileAccess.file_exists(path):
		push_warning("SteamBridge: no valid achievement cache; starting empty")


func _save_cache() -> void:
	if not _cache_writable:
		return   # never downgrade a future schema or overwrite another owner's file
	var path := achievement_cache_path(_steam_user_id)
	var err := DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if err != OK:
		push_warning("SteamBridge: achievement directory creation failed (%d)" % err)
		return
	var cf := ConfigFile.new()
	cf.set_value("cache", "version", ACHIEVEMENTS_SCHEMA)
	cf.set_value("cache", "account", str(_steam_user_id))
	cf.set_value("achievements", "unlocked", _unlocked)
	var tmp := path + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		push_warning("SteamBridge: achievement temporary save could not be opened")
		return
	file.store_string(cf.encode_to_text())
	file.flush()
	err = file.get_error()
	file.close()
	if err != OK:
		push_warning("SteamBridge: achievement temporary save failed (%d)" % err)
		return
	# A corrupt primary must never replace the valid backup we just recovered.
	if _cache_primary_valid and FileAccess.file_exists(path):
		err = DirAccess.copy_absolute(path, path + ".bak")
		if err != OK:
			push_warning("SteamBridge: achievement backup failed (%d)" % err)
			return
	err = DirAccess.rename_absolute(tmp, path)
	if err != OK:
		push_warning("SteamBridge: achievement cache replacement failed (%d)" % err)
	else:
		_cache_primary_valid = true


## Unlock once. Idempotent locally (the cache blocks a repeat) AND against
## Steam itself (SetAchievement is a no-op on an already-set stat) -- safe to
## call with the same id from every _record_run. `flush` skips the immediate
## storeStats() -- _report_to_steam (main.gd) unlocks several ids in one
## tick and calls flush_stats() once itself instead of round-tripping per id.
## If stats haven't been confirmed yet (_stats_ready), the Steam push is
## deferred entirely: _on_stats_received's reconciliation pass covers it once
## this bridge has confirmed an own-account stats refresh.
func unlock(id: String, flush := true) -> void:
	if not ACHIEVEMENTS.has(id):
		push_warning("SteamBridge: unlock() called with an undeclared id '%s'" % id)
		return
	if _unlocked.get(id, false):
		return
	_unlocked[id] = true
	_save_cache()
	if available and _stats_ready:
		_call("setAchievement", [id])
		if flush:
			_call("storeStats")


## Flushes any unlock(id, false) calls made since the last flush. Safe to
## call even when nothing changed (storeStats is a cheap no-op then).
func flush_stats() -> void:
	if available and _stats_ready:
		_call("storeStats")


## Posts a run's score to that mode's leaderboard (created server-side on
## first upload). findOrCreateLeaderboard is async on real Steam; the
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
	_call("findOrCreateLeaderboard", ["scores_%s" % mode, LB_SORT_DESCENDING, LB_DISPLAY_NUMERIC])


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
	_call("uploadLeaderboardScore", [_pending_score, true, PackedInt32Array(), handle])


## Verified 4.22.1 signal: leaderboard_score_uploaded(success: bool,
## this_handle: int, this_score: Dictionary). Consume all three arguments.
## The null default rejects an incomplete direct call rather than claiming success.
func _on_leaderboard_uploaded(result: Variant = null, _handle: int = 0, _details: Dictionary = {}) -> void:
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
		_call("setRichPresence", ["steam_display", "#StatusGeneric"])
		_call("setRichPresence", ["status", status])


## Pumps the Steamworks callback queue -- every async result above (stats,
## achievements, leaderboards) is only ever DELIVERED via this call, so it
## must run every frame once Steam is present. Call from main.gd's _process.
func process() -> void:
	if available:
		_call("run_callbacks")
		if _input_ready and _input_devices_dirty:
			_refresh_action_handles()
