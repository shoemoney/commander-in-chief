extends SceneTree
## Static check for always-on vignette legibility (1.3 view fix).
## HEAD carries Color(0.0, 0.0, 0.0, 0.12) in _draw_banners — a full-screen
## ui_vignette that darkens corners by ~12% and eats ghillie/sniper
## silhouettes in the opening jungle firefight. Fixed tree must not contain it.
## Expect: PASS after fix (no hit), FAIL on HEAD (hit at 0.12).

func _init() -> void:
	var path := "res://src/main.gd"
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("probe_vignette_static: could not read %s" % path)
		print("PROBE FAILED — unreadable")
		quit(1)
		return
	var needle := "Color(0.0, 0.0, 0.0, 0.12)"
	if text.contains(needle):
		# locate line for diagnostics
		var idx := text.find(needle)
		var line := text.substr(0, idx).count("\n") + 1
		push_error("probe_vignette_static: found always-on vignette %s at line %d — corner loss ~12%%, expected <5%%" % [needle, line])
		print("PROBE FAILED — always-on ui_vignette 0.12 still present (line %d)" % line)
		quit(1)
		return
	# also forbid any 0.12 vignette that is the always-on wash-exempt card
	# (night-ops uses 0.55, not 0.12 — so this is specific).
	print("PROBE OK — no always-on 0.12 vignette")
	quit(0)
