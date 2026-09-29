extends SceneTree
## Inspect the REAL registered binding without initializing Steam or sending data.
## Use an official GodotSteam engine, not the plain-Godot mock test runner.

func _initialize() -> void:
	if not Engine.has_singleton("Steam"):
		push_error("GodotSteam API verification requires the real Steam singleton")
		quit(1)
		return
	var steam := Engine.get_singleton("Steam")
	var source := FileAccess.get_file_as_string("res://src/steam/steam_bridge.gd")
	var call_pattern := RegEx.new()
	call_pattern.compile('_call\\("([A-Za-z_][A-Za-z_0-9]*)"')
	var names := {}
	for hit in call_pattern.search_all(source):
		names[hit.get_string(1)] = true
	var methods := {}
	var missing: Array[String] = []
	for method in steam.get_method_list():
		if names.has(method.name):
			methods[method.name] = method
	for name in names:
		if not methods.has(name):
			missing.append(name)
	# The test double must expose the same typed arguments and signal arity,
	# rather than teaching tests a fictional interface the native binding lacks.
	var mock = load("res://tests/mock_steam_singleton.gd").new()
	for name in names:
		if not mock.has_method(name):
			missing.append("mock-method:" + name)
	for method in mock.get_method_list():
		if not names.has(method.name) or not methods.has(method.name):
			continue
		var native: Dictionary = methods[method.name]
		if method.args.size() != native.args.size():
			missing.append("mock-arity:" + str(method.name))
			continue
		for i in method.args.size():
			if method.args[i].type != native.args[i].type:
				missing.append("mock-argument-type:%s:%d" % [method.name, i])
	var signal_pattern := RegEx.new()
	signal_pattern.compile('_call\\("connect", \\["([A-Za-z_][A-Za-z_0-9]*)"')
	var signals := {}
	for hit in signal_pattern.search_all(source):
		var name := hit.get_string(1)
		if not steam.has_signal(name):
			missing.append("signal:" + name)
		else:
			for entry in steam.get_signal_list():
				if entry.name == name:
					signals[name] = entry
					for mock_signal in mock.get_signal_list():
						if mock_signal.name == name:
							if mock_signal.args.size() != entry.args.size():
								missing.append("mock-signal-arity:" + name)
							else:
								for i in entry.args.size():
									if mock_signal.args[i].type != entry.args[i].type:
										missing.append("mock-signal-type:%s:%d" % [name, i])
	var report := {"engine": Engine.get_version_info(), "class": steam.get_class(),
		"methods": methods, "signals": signals, "missing": missing,
		"initialized_steam": false, "passed": missing.is_empty()}
	var path := OS.get_environment("STEAM_API_REPORT")
	if not path.is_empty():
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			push_error("Could not write Steam API report")
			quit(1)
			return
		file.store_string(JSON.stringify(report, "\t") + "\n")
	print("GODOTSTEAM API ", "PASS" if missing.is_empty() else "FAIL", " missing=", missing)
	quit(0 if missing.is_empty() else 1)
