extends Node
## Inspects the shipped native singleton only. Never instantiates the bridge or
## main game, initializes Steam, invokes operational methods, or pumps callbacks.

func _ready() -> void:
	if not Engine.has_singleton("Steam"):
		push_error("STEAM TEMPLATE FAIL: native singleton missing")
		get_tree().quit(1)
		return
	var steam := Engine.get_singleton("Steam")
	var source := FileAccess.get_file_as_string("res://bridge.txt")
	var methods := RegEx.new()
	methods.compile('_call\\("([A-Za-z_][A-Za-z_0-9]*)"')
	var names := {}
	var missing: Array[String] = []
	for hit in methods.search_all(source):
		var method := hit.get_string(1)
		names[method] = true
		if not steam.has_method(method):
			missing.append(method)
	var signals := RegEx.new()
	signals.compile('_call\\("connect", \\["([A-Za-z_][A-Za-z_0-9]*)"')
	var signal_names := {}
	for hit in signals.search_all(source):
		var signal_name := hit.get_string(1)
		signal_names[signal_name] = true
		if not steam.has_signal(signal_name):
			missing.append("signal:" + signal_name)
	if names.is_empty() or signal_names.is_empty():
		missing.append("missing bridge inspection input")
	print("STEAM TEMPLATE ", "PASS" if missing.is_empty() else "FAIL",
		" methods=", names.size(), " signals=", signal_names.size(),
		" missing=", missing, " initialized_steam=false engine=", Engine.get_version_info().string)
	get_tree().quit(0 if missing.is_empty() else 1)
