extends SceneTree
## Sim determinism lint — guards the cross-arch bit-identical guarantee.
##
##   godot --headless --path . -s res://tools/lint_sim.gd
##
## Scans every src/sim/**.gd file for code that would break determinism across
## x86_64 and arm64. All four legs of the "no floats, no engine RNG, no Time,
## no scene tree" rule are enforced here:
##
##   float literal    2.5, .75          — the one that actually moves checksums
##   float type       : float, float()
##   float constant   PI TAU INF NAN
##   float math       sqrt/sin/cos/lerp/deg_to_rad/maxf/... (whole-word + '(')
##   engine RNG       randf/randi/randomize
##   wall-clock time  Time.
##   scene tree       get_tree( / get_node(
##   OS query         OS.get_
##   frame counter    Engine.get_physics_frames
##
## SimRng and Fixed are the sim's sanctioned math/randomness sources and are
## NOT flagged: the patterns are whole-word anchored so `Fixed.fsqrt(`,
## `isqrt(`, `INFANTRY`, `PILOT_SPEED`, `SPIN_RAW` and `TAUNT_TICKS` stay clean.
##
## Comments are stripped before matching, so the decimals in the tuning notes
## ("1.4px/t (0.58x player)") don't fire the float-literal rule.
## ponytail: the strip cuts at the first '#', so a '#' inside a string literal
## blinds the rest of that line — false NEGATIVE only, and src/sim has none.
##
## Prints each offending file:line:kind:text and exits 1 if any are found, else
## prints OK and exits 0. Exit is via SceneTree.quit(code) — no OS.exit() in G4.

const SIM_DIR := "res://src/sim"
const FORBIDDEN: Array = [
	["float literal", r"(?<![\w.])\d*\.\d"],
	["float type", r"\bfloat\b"],
	["float constant", r"\b(?:PI|TAU|INF|NAN)\b"],
	["float math", r"\b(?:sqrt|sin|cos|tan|asin|acos|atan|atan2|pow|exp|log|lerp|lerpf|inverse_lerp|smoothstep|ease|deg_to_rad|rad_to_deg|snappedf|absf|maxf|minf|clampf|roundf|floorf|ceilf|fmod|fposmod|is_equal_approx|is_zero_approx)\s*\("],
	["engine RNG", r"\b(?:randf|randi|randomize)\w*"],
	["wall-clock time", r"\bTime\."],
	["scene tree", r"\bget_(?:tree|node)\s*\("],
	["OS query", r"\bOS\.get_"],
	["frame counter", r"\bEngine\.get_physics_frames"],
]


func _init() -> void:
	var rules: Array = []
	for rule in FORBIDDEN:
		var re := RegEx.create_from_string(rule[1])
		if re == null:
			printerr("lint_sim: bad pattern for %s" % rule[0])
			quit(1)
			return
		rules.append([rule[0], re])

	var files: Array[String] = []
	_collect(SIM_DIR, files)
	files.sort()

	var hits := 0
	for path in files:
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			printerr("lint_sim: could not open %s" % path)
			hits += 1
			continue
		var lines := f.get_as_text().split("\n")
		f.close()
		for i in lines.size():
			var code: String = lines[i]
			var hash_at := code.find("#")
			if hash_at >= 0:
				code = code.substr(0, hash_at)
			if code.strip_edges().is_empty():
				continue
			for rule in rules:
				var m: RegExMatch = rule[1].search(code)
				if m != null:
					print("%s:%d:%s:%s" % [path, i + 1, rule[0], m.get_string()])
					hits += 1

	if hits > 0:
		print("lint_sim: FAIL — %d forbidden-token hit(s) in src/sim" % hits)
		quit(1)
	else:
		print("lint_sim: OK — %d files scanned, src/sim is determinism-clean" % files.size())
		quit(0)


func _collect(dir_path: String, out: Array[String]) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		if name != "." and name != "..":
			var full := dir_path.path_join(name)
			if d.current_is_dir():
				_collect(full, out)
			elif name.ends_with(".gd"):
				out.append(full)
		name = d.get_next()
	d.list_dir_end()
