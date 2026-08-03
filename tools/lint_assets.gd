extends SceneTree
## Asset import lint — guards against a PNG landing without its .import
## sidecar (the failure mode that makes the engine throw missing-resource
## errors at load time), a directory of tracked assets with no ASSETS.md
## provenance row, and a texture import that reverted to lossy VRAM
## compression.
##
##   godot --headless --path . -s res://tools/lint_assets.gd
##
## Scans every assets/**/*.png for a matching assets/**/*.png.import file,
## and every assets/**/*.png.import for a matching source PNG (orphaned
## sidecars left behind by a deleted/renamed asset). Prints each offending
## path and exits 1 if any are found, else prints OK and exits 0.

const ASSETS_DIR := "res://assets"

# compress/mode=2 (VRAM) reverts the "lossless canvas sprite" art policy.
# Keep this list short and justified — it is not a place to grandfather a
# backlog, only to record a deliberate exception.
const COMPRESS_MODE_ALLOW := {
	"res://assets/ui/intro/bigit_sheet.png": true,
}


func _init() -> void:
	var pngs: Array[String] = []
	var imports: Array[String] = []
	var tracked: Array[String] = []  # pngs + mp3s + ttfs, for the ASSETS.md provenance check
	var scan_ok := _collect(ASSETS_DIR, pngs, imports, tracked)
	pngs.sort()
	imports.sort()

	var hits := 0
	if not scan_ok:
		hits += 1
	# Fail closed on a zero-file scan: a wiped assets dir (or an all-PNGs-deleted
	# commit) must never print "OK — 0 PNGs". Same guard lint_sim grew 2026-07-31.
	if pngs.is_empty() and imports.is_empty():
		print("lint_assets: scanned 0 PNGs and 0 sidecars under %s — refusing to report a false OK" % ASSETS_DIR)
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
		elif not COMPRESS_MODE_ALLOW.has(source):
			var cf := ConfigFile.new()
			if cf.load(path) == OK and int(cf.get_value("params", "compress/mode", -1)) != 0:
				print("lossy VRAM compress/mode on %s (expected 0/lossless) — add to COMPRESS_MODE_ALLOW with a reason, or reimport" % source)
				hits += 1

	hits += _check_provenance(tracked)

	if hits > 0:
		print("lint_assets: FAIL — %d issue(s) across %d PNGs" % [hits, pngs.size()])
		quit(1)
	else:
		print("lint_assets: OK — %d PNGs, all import sidecars present and matched" % pngs.size())
		quit(0)


## CONTRIBUTING.md/ASSETS.md require every asset directory to have a provenance
## row. ponytail: matched at the depth-2 prefix (assets/<subdir>/), not the
## full leaf directory — ASSETS.md documents several subfolders only via shell-
## brace notation (`assets/art/{decor,p2,mil2,cast2}`), so a full-path substring
## match false-fails on already-documented assets. This is deliberately coarser
## than "directory-granular" but still catches the real defect: an entirely new
## undocumented top-level folder (e.g. assets/newthing/).
func _check_provenance(tracked: Array[String]) -> int:
	var doc := FileAccess.get_file_as_string("res://ASSETS.md")
	if doc.is_empty():
		print("lint_assets: could not read res://ASSETS.md for provenance check")
		return 1
	var prefixes := {}
	for path in tracked:
		var rel := path.trim_prefix("res://")  # "assets/troops/anim/foo.png"
		var parts := rel.split("/")
		if parts.size() >= 2:
			prefixes["%s/%s/" % [parts[0], parts[1]]] = true
	var missing := prefixes.keys()
	missing.sort()
	var hits := 0
	for prefix in missing:
		if not doc.contains(prefix):
			print("no ASSETS.md provenance row mentions %s" % prefix)
			hits += 1
	return hits


## Returns false (and prints why) if a directory could not be opened or
## scanned -- a silent skip there would let this lint report a false OK.
func _collect(dir_path: String, pngs: Array[String], imports: Array[String], tracked: Array[String]) -> bool:
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
				ok = _collect(full, pngs, imports, tracked) and ok
			elif name.ends_with(".png"):
				pngs.append(full)
				tracked.append(full)
			elif name.ends_with(".png.import"):
				imports.append(full)
			elif name.ends_with(".mp3") or name.ends_with(".ttf"):
				tracked.append(full)
		name = d.get_next()
	d.list_dir_end()
	return ok
