extends RefCounted
## BANNERS & WORLD LABELS: the top-center banner is a crisp plate with solid lettering that is
## dealt DOWN from the HUD rail (its plate never reaches under the corner plate), animates inside
## its own footprint, and the small in-world plates share one pointer-bearing style.

const Runner := preload("res://tests/run_tests.gd")
const Main := preload("res://src/main.gd")


func _src() -> String:
	return FileAccess.get_file_as_string("res://src/main.gd")


func test_plate_top_never_rises_above_the_rail() -> void:
	# The OLD arbiter handed out the BASELINE, so the plate top sat size+2 above the rail --
	# under the HUD corner plate. Every row's plate must now start at or below y_top.
	var bad := 0
	for y in [40.0, 56.0, 76.0, 88.0, 132.0]:
		for size in [10, 11, 12, 16]:
			for god in [false, true]:
				var rows: Array = Main.band_rows(y, "WAVE CLEARED — SHOP OPEN", size, false,
					"GRENADES CRACK ARMOR", god)
				for r in rows:
					var pr: Rect2 = r["plate"]
					if pr.position.y < y - 0.01:
						bad += 1
	Runner.T.eq(bad, 0, "no band plate reaches above the rail it was dealt from")


func test_real_band_clears_the_real_hud_plate() -> void:
	var m := Main.new()
	m.sim = SimWorld.new(3, 1, "campaign")
	m._hud_icons.main = m
	m._menu.mode = GameMenu.Mode.HIDDEN
	m._banners.append({"text": "FROGMAN — KILL IT ON THE SURFACE", "t": 1.0})
	var row: Dictionary = Main.band_row(m._band_rows("splash"), "top")
	Runner.T.ok(not row.is_empty(), "the splash gets a top row through the real _band_rows")
	var plate: Rect2 = row["plate"]
	Runner.T.ok(plate.position.y >= m._hud_icons.panel_bottom(),
		"banner plate top %.1f is at or below the HUD plate bottom %.1f"
			% [plate.position.y, m._hud_icons.panel_bottom()])
	Runner.T.eq(row["rect"], row["plate"], "the footprint IS the plate: nothing paints outside it")
	m.free()


func test_hint_row_stays_put_and_clear_of_the_alert() -> void:
	var alone: Array = Main.band_rows(56.0, "", 16, false, "AIM DOWN THE COLUMN")
	var under: Array = Main.band_rows(56.0, "WAVE CLEARED — SHOP OPEN", 16, false, "AIM DOWN THE COLUMN")
	Runner.T.eq(alone[0]["baseline"], under[1]["baseline"], "row 0 stays reserved")
	var a: Rect2 = under[0]["rect"]
	var b: Rect2 = under[1]["rect"]
	Runner.T.ok(b.position.y >= a.end.y, "hint row starts below the alert plate")


func test_anim_enters_readable_and_exits_closed() -> void:
	var first: Dictionary = BannersPolish.anim(1.0, 1.0)
	Runner.T.ok(first["a"] >= 0.85 and first["r"] >= 0.99, "frame-0 banner is already readable")
	Runner.T.ok(first["dy"] > 0.0, "it settles up into place from below")
	var mid: Dictionary = BannersPolish.anim(0.5, 1.0)
	Runner.T.ok(mid["a"] >= 0.99 and mid["dy"] == 0.0 and mid["r"] >= 0.99, "mid-life is settled")
	var dying: Dictionary = BannersPolish.anim(0.04, 1.0)
	Runner.T.ok(dying["r"] < 1.0 and dying["a"] < 1.0, "the plate wipes closed as it dies")
	Runner.T.eq(BannersPolish.anim(0.0, 1.0)["a"], 0.0, "gone is gone")
	# reduce-motion: static
	for bt in [1.0, 0.95, 0.5, 0.05]:
		var st: Dictionary = BannersPolish.anim(bt, 0.0)
		Runner.T.ok(st["r"] == 1.0 and st["a"] == 1.0 and st["dy"] == 0.0,
			"reduce-motion holds the banner static at t=%.2f" % bt)


func test_wipe_never_leaves_its_footprint() -> void:
	var full := Rect2(100.0, 80.0, 301.0, 23.0)
	for r in [0.0, 0.2, 0.5, 0.97, 1.0, 1.5]:
		var w: Rect2 = BannersPolish.wiped_rect(full, r)
		Runner.T.ok(full.grow(0.51).encloses(w), "wipe r=%.2f stays inside the reserved plate" % r)
	Runner.T.eq(BannersPolish.wiped_rect(full, 1.0).size.y, 23.0, "full wipe keeps the full height")


func test_pointer_aims_at_its_subject() -> void:
	var plate := Rect2(100.0, 50.0, 40.0, 14.0)
	var down: PackedVector2Array = BannersPolish.pointer_points(plate, Vector2(120.0, 90.0))
	Runner.T.ok(down[2].y > plate.end.y, "subject below -> the tip hangs below the plate")
	Runner.T.eq(down[2].x, 120.0, "tip is centred on the subject")
	var up: PackedVector2Array = BannersPolish.pointer_points(plate, Vector2(300.0, 10.0))
	Runner.T.ok(up[2].y < plate.position.y, "subject above -> the tip rises above the plate")
	Runner.T.ok(up[0].x >= plate.position.x and up[1].x <= plate.end.x,
		"a far-away subject is clamped so the pointer base stays on the plate")


func test_lettering_records_through_the_capture_seam() -> void:
	var boxes: Array = []
	Art.text_capture = boxes
	var n := Node2D.new()
	BannersPolish.draw_lettering(n, "SHOP OPEN", 320.0, 100.0, 16, Color.WHITE, 1.0)
	BannersPolish.draw_lettering(n, "INVISIBLE", 320.0, 100.0, 16, Color.WHITE, 0.0)
	Art.text_capture = null
	n.free()
	Runner.T.eq(boxes.size(), 1, "layout tests still see banner ink; an alpha-0 banner paints nothing")
	Runner.T.eq(boxes[0]["id"], "SHOP OPEN", "and it is the banner's own string")


func test_draw_paths_are_wired_to_the_module() -> void:
	var src := _src()
	var a := src.find("func _draw_banners(")
	var b := src.find("static func _banner_plate_alpha(")
	var body := src.substr(a, b - a)
	for needle in ["BannersPolish.anim(", "BannersPolish.draw_plate(", "BannersPolish.draw_lettering(",
			"_polish_alert("]:
		Runner.T.ok(body.find(needle) != -1, "_draw_banners calls %s" % needle)
	Runner.T.ok(body.find("_metal_plate(") == -1, "no banner path still paints the feathered smear")
	Runner.T.ok(body.find("Art.text_center(self, trow") == -1, "no alert still prints striped bare ink")
	var c := src.find("func _draw_ready_tally(")
	Runner.T.ok(src.substr(c, 1400).find("BannersPolish.draw_label_plate(") != -1, "ready tally wears the shared label plate")
	var d := src.find("func _draw_objective_markers(")
	Runner.T.ok(src.substr(d, 6000).find("BannersPolish.draw_label_plate(") != -1,
		"on-screen objective markers wear the shared plate with a pointer")
	Runner.T.ok(src.substr(src.find("func _banner_plate("), 500).find("BannersPolish.draw_plate(") != -1,
		"_banner_plate (last stand) routes through the module too")


func test_lettering_draws_one_shadow_and_one_ink_pass() -> void:
	var src := FileAccess.get_file_as_string("res://src/view/banners_polish.gd")
	var a := src.find("static func draw_lettering(")
	var body := src.substr(a, src.find("\nstatic func ", a + 10) - a)
	Runner.T.eq(body.count("ci.draw_string("), 2, "lettering is one shadow string plus one ink string (no doubled shadow, no fake-bold pass)")
	Runner.T.eq(body.count("draw_string_outline("), 1, "and one rim")


func test_plate_ends_are_notches_not_pipe_bars() -> void:
	var src := FileAccess.get_file_as_string("res://src/view/banners_polish.gd")
	var a := src.find("static func draw_plate(")
	var body := src.substr(a, src.find("\n## Solid lettering", a) - a)
	Runner.T.ok(body.find("b.size.y - 4.0), cap)") == -1, "no full-height accent bar at either end")
	Runner.T.ok(body.contains("CAP_NOTCH_H"), "the ends are short corner notches")
	Runner.T.ok(BannersPolish.CAP_NOTCH_H < 6.0, "notch is a tick, not a bar")


func test_objective_marker_plates_reserve_their_label_slot() -> void:
	var src := FileAccess.get_file_as_string("res://src/main.gd")
	var d := src.find("func _draw_objective_markers(")
	var body := src.substr(d, src.find("\nstatic func _marker_icon(", d) - d)
	var p := body.find("BannersPolish.draw_label_plate(")
	Runner.T.ok(p != -1 and body.substr(p, 300).contains("_label_slots.append("),
		"a drawn marker plate appends its rect to _label_slots")
