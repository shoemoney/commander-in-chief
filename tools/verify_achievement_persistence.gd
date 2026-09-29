extends SceneTree
## Run through tools/run_tests.sh: child processes inherit its private profile.
## Uses a mock Steam identity; no Steam client, account or service is contacted.

func _initialize() -> void:
	if Engine.has_singleton("Steam"):
		push_error("Persistence probe requires plain Godot, not a live Steam binding")
		quit(1)
		return
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		for phase in ["write-one", "read-two", "read-one", "read-anonymous"]:
			var output: Array = []
			var rc := OS.execute(OS.get_executable_path(), ["--headless", "--path",
				ProjectSettings.globalize_path("res://"), "-s",
				"res://tools/verify_achievement_persistence.gd", "--", phase], output, true)
			var log := "\n".join(output)
			if rc != 0 or not log.contains("PERSISTENCE PHASE PASS " + phase) or log.contains("ERROR:"):
				print(log)
				push_error("Achievement persistence child failed: " + phase)
				quit(1)
				return
			print("PERSISTENCE PHASE PASS ", phase)
		print("ACHIEVEMENT RESTART PASS")
		quit(0)
		return
	var phase := args[0]
	var mock = null
	if phase != "read-anonymous":
		mock = load("res://tests/mock_steam_singleton.gd").new()
		mock.user_id = 2 if phase == "read-two" else 1
		Engine.register_singleton("Steam", mock)
	var bridge := SteamBridge.new()
	var ok := false
	match phase:
		"write-one":
			bridge.unlock("FIRST_VICTORY")
			ok = FileAccess.file_exists(SteamBridge.achievement_cache_path(1))
		"read-one":
			ok = bridge._unlocked.get("FIRST_VICTORY", false)
		"read-two", "read-anonymous":
			ok = bridge._unlocked.is_empty()
	if mock != null:
		Engine.unregister_singleton("Steam")
	print("PERSISTENCE PHASE ", "PASS " if ok else "FAIL ", phase)
	quit(0 if ok else 1)
