extends SceneTree
## Sim determinism lint — guards the cross-arch bit-identical guarantee.
##
##   godot --headless --path . -s res://tools/lint_sim.gd
##
## Scans every src/sim/**.gd file for tokens that would break determinism
## across x86_64 and arm64: engine RNG (randf/randi[...]), wall-clock time
## (Time.), scene-tree access (get_tree(/get_node(), OS queries (OS.get_),
## and frame counters (Engine.get_physics_frames). SimRng and Fixed are the
## sim's sanctioned math/randomness sources and are NOT flagged.
##
## Comment-only lines (first non-tab char is '#') are skipped. Prints each
## offending file:line:token and exits 1 if any are found, else prints OK
## and exits 0. Exit is via SceneTree.quit(code) — Godot 4 has no OS.exit().

const SIM_DIR := "res://src/sim"
const FORBIDDEN: Array[String] = [
	"randf",
	"randi",
	"randf_range",
	"randi_range",
	"Time.",
	"get_tree(",
	"get_node(",
	"OS.get_",
	"Engine.get_physics_frames",
]


func _init() -> void:
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
			var line: String = lines[i]
			# Skip comment-only lines: first non-tab char is '#'.
			if line.lstrip("\t").begins_with("#"):
				continue
			for token in FORBIDDEN:
				if token in line:
					print("%s:%d:%s" % [path, i + 1, token])
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
