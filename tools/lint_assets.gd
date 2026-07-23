extends SceneTree
## Asset import lint — guards against a PNG landing without its .import
## sidecar (the failure mode that makes the engine throw missing-resource
## errors at load time).
##
##   godot --headless --path . -s res://tools/lint_assets.gd
##
## Scans every assets/**/*.png for a matching assets/**/*.png.import file,
## and every assets/**/*.png.import for a matching source PNG (orphaned
## sidecars left behind by a deleted/renamed asset). Prints each offending
## path and exits 1 if any are found, else prints OK and exits 0.

const ASSETS_DIR := "res://assets"


func _init() -> void:
	var pngs: Array[String] = []
	var imports: Array[String] = []
	var scan_ok := _collect(ASSETS_DIR, pngs, imports)
	pngs.sort()
	imports.sort()

	var hits := 0
	if not scan_ok:
		hits += 1
	for path in pngs:
		if not FileAccess.file_exists(path + ".import"):
			print("missing .import sidecar: %s" % path)
			hits += 1
	for path in imports:
		var source := path.substr(0, path.length() - ".import".length())
		if not FileAccess.file_exists(source):
			print("orphaned .import sidecar (no source PNG): %s" % path)
			hits += 1

	if hits > 0:
		print("lint_assets: FAIL — %d issue(s) across %d PNGs" % [hits, pngs.size()])
		quit(1)
	else:
		print("lint_assets: OK — %d PNGs, all import sidecars present and matched" % pngs.size())
		quit(0)


## Returns false (and prints why) if a directory could not be opened or
## scanned -- a silent skip there would let this lint report a false OK.
func _collect(dir_path: String, pngs: Array[String], imports: Array[String]) -> bool:
	var d := DirAccess.open(dir_path)
	if d == null:
		print("could not open dir %s: %s" % [dir_path, error_string(DirAccess.get_open_error())])
		return false
	var err := d.list_dir_begin()
	if err != OK:
		print("could not scan dir %s: %s" % [dir_path, error_string(err)])
		return false
	var ok := true
	var name := d.get_next()
	while name != "":
		if name != "." and name != "..":
			var full := dir_path.path_join(name)
			if d.current_is_dir():
				ok = _collect(full, pngs, imports) and ok
			elif name.ends_with(".png"):
				pngs.append(full)
			elif name.ends_with(".png.import"):
				imports.append(full)
		name = d.get_next()
	d.list_dir_end()
	return ok
