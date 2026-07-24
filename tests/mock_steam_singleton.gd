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
## async Steam call here is answered synchronously by the caller invoking
## fire_signal() directly (no real network round trip to simulate), which is
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
signal current_stats_received(game_id: int, result: int, user_id: int)
signal leaderboard_find_result(handle: int, found: int)
signal leaderboard_score_uploaded(result: Variant)

var achievements: Dictionary = {}       # id -> true, set via set_achievement()
var stats_stored := false               # true once store_stats() is called at least once
var controllers: Array = [1001, 1002]   # fake controller handles: [0]=P1, [1]=P2
var activated_sets: Array = []          # [[controller_handle, action_set_handle], ...]
var find_calls: Array = []              # [[leaderboard_name, sort, display], ...]
var uploaded_scores: Dictionary = {}    # leaderboard handle -> last uploaded score

const _ACTION_SET_GAMEPLAY := 5000
var _analog_handles: Dictionary = {}    # action name -> handle
var _digital_handles: Dictionary = {}   # action name -> handle
var _next_handle := 5000
var _analog_data: Dictionary = {}       # "controller:handle" -> float
var _digital_data: Dictionary = {}      # "controller:handle" -> bool


func steamInitEx() -> Dictionary:
	return {"status": 0, "verbal": ""}


## Test-facing: emits `signal_name` (one of the three declared above),
## simulating that Steamworks callback firing during run_callbacks(). Routes
## through the real, native emit_signal() so every real connect()ed Callable
## -- exactly what steam_bridge.gd's _init()/upload_score() wired up -- fires
## the same way it would against the real GodotSteam singleton.
func fire_signal(signal_name: String, args: Array = []) -> void:
	callv("emit_signal", [signal_name] + args)


func request_current_stats() -> void:
	pass   # the test drives this by calling fire_signal("current_stats_received", ...) itself


func run_callbacks() -> void:
	pass   # nothing queued -- fire_signal() delivers synchronously in this mock


func get_achievement(id: String) -> Dictionary:
	return {"ret": true, "achieved": achievements.get(id, false)}


func set_achievement(id: String) -> bool:
	achievements[id] = true
	return true


func store_stats() -> bool:
	stats_stored = true
	return true


func set_input_action_manifest_file_path(_path: String) -> bool:
	return true


func get_connected_controllers() -> Array:
	return controllers


func get_action_set_handle(name: String) -> int:
	return _ACTION_SET_GAMEPLAY if name == "Gameplay" else 0


func activate_action_set(controller: int, set_handle: int) -> void:
	activated_sets.append([controller, set_handle])


func get_analog_action_handle(name: String) -> int:
	if not _analog_handles.has(name):
		_next_handle += 1
		_analog_handles[name] = _next_handle
	return _analog_handles[name]


func get_digital_action_handle(name: String) -> int:
	if not _digital_handles.has(name):
		_next_handle += 1
		_digital_handles[name] = _next_handle
	return _digital_handles[name]


func get_analog_action_data(controller: int, handle: int) -> Dictionary:
	return {"x": _analog_data.get("%d:%d" % [controller, handle], -1.0)}


func get_digital_action_data(controller: int, handle: int) -> Dictionary:
	return {"bState": _digital_data.get("%d:%d" % [controller, handle], false), "bActive": true}


func set_rich_presence(_key: String, _value: String) -> bool:
	return true


func find_or_create_leaderboard(name: String, sort: int, display: int) -> void:
	find_calls.append([name, sort, display])


func upload_leaderboard_score(score: int, _force: bool, _details: Array, handle: int) -> void:
	uploaded_scores[handle] = score


## Test-facing: sets the analog value steam_bridge.gd's fire_trigger_value(player)
## will read back, keyed by PLAYER INDEX (0/1) + action name -- resolves through
## whatever handle get_analog_action_handle() already assigned (or assigns one now).
func set_analog_value(player: int, action: String, value: float) -> void:
	var handle := get_analog_action_handle(action)
	_analog_data["%d:%d" % [controllers[player], handle]] = value


## Test-facing: sets the digital value steam_bridge.gd's button_pressed(player, action)
## will read back, same keying convention as set_analog_value() above.
func set_digital_value(player: int, action: String, value: bool) -> void:
	var handle := get_digital_action_handle(action)
	_digital_data["%d:%d" % [controllers[player], handle]] = value
