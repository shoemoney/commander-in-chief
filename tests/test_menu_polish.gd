extends RefCounted
## Menu chrome system: ONE identity (steel-olive base + brass accent) on every framed screen,
## bevelled plates with a pressed state, a strong focus cue and a shared header ornament.

const Runner := preload("res://tests/run_tests.gd")
const Menu := preload("res://src/view/menu.gd")
const Polish := preload("res://src/view/menu_polish.gd")
const LayoutTests := preload("res://tests/test_menu_layout.gd")


func test_bevel_flips_when_pressed() -> void:
	var b := Rect2(100, 100, 200, 21)
	var up := Polish.bevel_rects(b, false, false, false)
	var dn := Polish.bevel_rects(b, false, true, false)
	Runner.T.eq(up.size(), 4, "raised bevel has four edges")
	Runner.T.ok(up[0]["c"].a > 0.2 and up[0]["c"].r > 0.9, "raised: top edge is the LIGHT one")
	Runner.T.ok(dn[0]["c"].r < 0.1, "pressed: top edge is the SHADE (sunken)")
	Runner.T.eq(Polish.shadow_rect(b, true).size.x, 0.0, "a pressed plate is flush, no contact shadow")
	Runner.T.ok(Polish.shadow_rect(b, false).size.x > 0.0, "a raised plate casts a contact shadow")


func test_focus_cue_is_unmistakable_and_static_under_reduce_motion() -> void:
	var b := Rect2(209, 130, 222, 21)
	var f := Polish.focus_cue(b, 0.0)
	var ring: Rect2 = f["ring"]
	Runner.T.ok(ring.encloses(b), "ring hugs outside the plate")
	Runner.T.ok(f["left"][2].x < b.position.x and f["right"][2].x > b.end.x, "pointer wedges sit in both margins")
	Runner.T.ok(f["ring_col"].a >= 0.85, "focus ring is near-opaque even at breath 0 (reduce-motion)")
	Runner.T.ok(Polish.ease_open(0.3, 0.0) == 1.0, "open ease is a flat 1.0 under reduce-motion")
	Runner.T.ok(Polish.ease_open(0.5, 1.0) > 0.5, "open ease is cubic-out under motion")


func test_every_framed_screen_wears_the_one_chrome_through_the_real_draw() -> void:
	var stub = LayoutTests._StubMain.new()
	var tints := {}
	var rules := 0
	for m in Menu.Mode.values():
		if m in Menu.UNFRAMED_MODES:
			continue
		var cap = LayoutTests._CaptureMenu.new()
		cap.main = stub
		cap.mode = m
		cap._open_t = 1.0
		cap._draw_content_frame()
		for op in cap.ops:
			if op["k"] == "fit" and op["id"] == "ui_frame_lrg":
				tints[str(op["col"])] = true
			elif op["k"] == "rect" and op["box"].size.y == 1.0 and is_equal_approx(op["box"].size.x, 90.0):
				rules += 1
		cap.free()
	stub.free()
	Runner.T.eq(tints.size(), 1, "every framed screen shares ONE frame tint")
	Runner.T.ok(rules >= 2, "framed screens draw the shared header rule via the real draw (%d)" % rules)


func test_plate_body_is_domed_and_flips_when_pressed() -> void:
	var b := Rect2(100, 100, 200, 22)
	var up: Array = MenuPolish.body_rects(b, false, false)
	var dn: Array = MenuPolish.body_rects(b, true, false)
	Runner.T.eq(up.size(), 2, "plate body has a lit half and a shaded half")
	Runner.T.ok(up[0]["c"].a > 0.0 and up[0]["c"].r > up[1]["c"].r, "resting plate is lit on top, shaded below")
	Runner.T.ok(dn[0]["c"].r < dn[1]["c"].r, "pressed plate swaps to shaded top, lit bottom")
