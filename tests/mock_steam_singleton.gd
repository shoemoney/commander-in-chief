extends RefCounted
## Hand-rolled stand-in for the GodotSteam `Steam` engine singleton --
## registered via Engine.register_singleton("Steam", MockSteamSingleton.new())
## for the duration of a test in tests/test_steam_bridge.gd so the REAL
## src/steam/steam_bridge.gd code runs its online paths (init/connect,
## achievement reconcile, leaderboard find->upload round trip, both players'
## action-handle reads) instead of only ever hitting the `_steam == null`
## early return every other test in that file covers.
##
## This is NOT the real GodotSteam binding -- it implements just the method
## surface steam_bridge.gd's _call() sites use (see docs/godotsteam_api_
## version.md for the full list and the "diff before shipping" caveat). Every
## stats/leaderboard reply here is delivered synchronously via fire_signal().
## Device events are queued until run_callbacks() to exercise the production
## pump and batch refresh (no real hardware or network round trip), which is
## the strictest exercise of steam_bridge.gd's callback-handling code: it
## proves the wiring, not the timing.
##
## connect()/is_connected() are NOT overridden here (GDScript refuses to
## override those two Object methods with an incompatible signature -- a
## "Parse Error: function signature doesn't match the parent" that silently
## fails the whole script's compile, which is why an earlier version of this
## file made every test_mock_steam_* test below error with "Nonexistent
## function 'new'"). Real Godot signals are declared instead, so the
## INHERITED Object.connect()/is_connected() (which steam_bridge.gd's _call()
## reaches exactly the way it would the real GodotSteam singleton) just works.
signal user_stats_received(game_id: int, result: int, user_id: int)
signal leaderboard_find_result(handle: int, found: int)
signal leaderboard_score_uploaded(success: bool, handle: int, details: Dictionary)
signal input_device_connected(input_handle: int)
signal input_device_disconnected(input_handle: int)

var achievements: Dictionary = {}       # id -> true, set via setAchievement()
var stats_stored := false               # true once storeStats() is called at least once
var controllers: Array = [1001, 1002]   # fake controller handles: [0]=P1, [1]=P2
var activated_sets: Array = []          # [[controller_handle, action_set_handle], ...]
var find_calls: Array = []              # [[leaderboard_name, sort, display], ...]
var uploaded_scores: Dictionary = {}    # leaderboard handle -> last uploaded score
var requested_user := 0
var user_id := 1
var input_initialized := false
var manifest_ok := true
var input_ok := true
var actions_active := true
var device_callbacks_enabled := false
var device_events: Array = []

const _ACTION_SET_GAMEPLAY := 5000
var _analog_handles: Dictionary = {}    # action name -> handle
var _digital_handles: Dictionary = {}   # action name -> handle
var _next_handle := 5000
var _analog_data: Dictionary = {}       # "controller:handle" -> float
var _digital_data: Dictionary = {}      # "controller:handle" -> bool


func steamInitEx(_app_id: int = 0, _embed_callbacks: bool = false) -> Dictionary:
	return {"status": 0, "verbal": ""}


## Test-facing: emits `signal_name` (one of the signals declared above),
## simulating that Steamworks callback firing during run_callbacks(). Routes
## through the real, native emit_signal() so every real connect()ed Callable
## -- exactly what steam_bridge.gd's _init()/upload_score() wired up -- fires
## the same way it would against the real GodotSteam singleton.
func fire_signal(signal_name: String, args: Array = []) -> void:
	callv("emit_signal", [signal_name] + args)


func getSteamID() -> int:
	return user_id


func requestUserStats(user: int) -> void:
	requested_user = user


func inputInit(_explicitly_call_runframe: bool = false) -> bool:
	input_initialized = input_ok
	return input_ok


func run_callbacks() -> void:
	var pending := device_events.duplicate()
	device_events.clear()
	if device_callbacks_enabled:
		for event in pending:
			fire_signal(event[0], [event[1]])


func enableDeviceCallbacks() -> void:
	device_callbacks_enabled = true


func getAchievement(id: String) -> Dictionary:
	return {"ret": true, "achieved": achievements.get(id, false)}


func setAchievement(id: String) -> bool:
	achievements[id] = true
	return true


func storeStats() -> bool:
	stats_stored = true
	return true


func setInputActionManifestFilePath(_path: String) -> bool:
	return manifest_ok


func getConnectedControllers() -> Array:
	return controllers


func getActionSetHandle(name: String) -> int:
	return _ACTION_SET_GAMEPLAY if name == "Gameplay" else 0


func activateActionSet(controller: int, set_handle: int) -> void:
	activated_sets.append([controller, set_handle])


func getAnalogActionHandle(name: String) -> int:
	if not _analog_handles.has(name):
		_next_handle += 1
		_analog_handles[name] = _next_handle
	return _analog_handles[name]


func getDigitalActionHandle(name: String) -> int:
	if not _digital_handles.has(name):
		_next_handle += 1
		_digital_handles[name] = _next_handle
	return _digital_handles[name]


func getAnalogActionData(controller: int, handle: int) -> Dictionary:
	return {"x": _analog_data.get("%d:%d" % [controller, handle], -1.0), "y": 0.0, "mode": 0, "active": actions_active}


func getDigitalActionData(controller: int, handle: int) -> Dictionary:
	return {"state": _digital_data.get("%d:%d" % [controller, handle], false), "active": actions_active}


func setRichPresence(_key: String, _value: String) -> bool:
	return true


func findOrCreateLeaderboard(name: String, sort: int, display: int) -> void:
	find_calls.append([name, sort, display])


func uploadLeaderboardScore(score: int, _keep_best: bool = true, _details: PackedInt32Array = PackedInt32Array(), handle: int = 0) -> void:
	uploaded_scores[handle] = score


## Test-facing: sets the analog value steam_bridge.gd's fire_trigger_value(player)
## will read back, keyed by PLAYER INDEX (0/1) + action name -- resolves through
## whatever handle getAnalogActionHandle() already assigned (or assigns one now).
func set_analog_value(player: int, action: String, value: float) -> void:
	var handle := getAnalogActionHandle(action)
	_analog_data["%d:%d" % [controllers[player], handle]] = value


## Test-facing: sets the digital value steam_bridge.gd's button_pressed(player, action)
## will read back, same keying convention as set_analog_value() above.
func set_digital_value(player: int, action: String, value: bool) -> void:
	var handle := getDigitalActionHandle(action)
	_digital_data["%d:%d" % [controllers[player], handle]] = value
