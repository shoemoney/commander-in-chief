extends RefCounted
## c1-04: HUD verb-reminder window guards. The in-run ROLL/WHEEL/REVIVE legend
## must reliably rearm on EVERY run start/restart (keyed on a fresh SimWorld, not
## a tick_count), freeze while a menu is up, and re-brighten after an unpause —
## then decay to zero and fade FULLY OUT (transient, so it never permanently
## overlays the playfield; the recoverable reference lives on PAUSE + HOW TO PLAY).
## The window checks drive the pure static HudIcons.verb_step; the bounds check
## measures the ACTUAL drawn chip extent via HudIcons.verb_legend_extent in both
## device modes — no live Control / scene tree is needed.

const Runner := preload("res://tests/run_tests.gd")
const Hud := preload("res://src/view/hud.gd")

const DT := 1.0 / 60.0   # one 60 Hz frame


# A brand-new SimWorld (different instance id) rearms the full ~6s window and
# adopts the new id — this is what makes the reminder re-show on start AND restart
# without leaning on tick_count decreasing.
func test_new_sim_rearms_window() -> void:
	# Fresh HUD (sim_id 0) meeting the first real run's id: rearm to ~360 (less one frame).
	var r := Hud.verb_step(0.0, 0, 12345, false, false, DT)
	Runner.T.ok(r[0] > 350.0, "first run arms the bright window (show=%.1f)" % r[0])
	Runner.T.eq(int(r[1]), 12345, "adopts the new SimWorld id")
	# A restart mid-run (window already expired) still rearms on the NEW sim id —
	# even though the old tick_count was high, identity catches it.
	var r2 := Hud.verb_step(0.0, 12345, 67890, false, false, DT)
	Runner.T.ok(r2[0] > 350.0, "restart rearms on a fresh sim id (show=%.1f)" % r2[0])
	Runner.T.eq(int(r2[1]), 67890, "adopts the restarted SimWorld id")


# While a menu is up the window is frozen (same sim id passed in as current) — the
# sim isn't ticking either, so the reminder must not bleed down behind the menu.
func test_menu_freezes_window() -> void:
	var r := Hud.verb_step(180.0, 999, 999, true, false, DT)
	Runner.T.eq(r[0], 180.0, "paused: show is frozen")
	Runner.T.eq(int(r[1]), 999, "paused: sim id unchanged")


# Unpausing (same run) re-brightens a decayed window to at least ~3s, so bindings
# are legible again right after resuming — without a full 6s rearm.
func test_unpause_refreshes_window() -> void:
	# Expired to the floor, same sim id, first frame after a pause: bumped to ~180.
	var r := Hud.verb_step(0.0, 42, 42, false, true, DT)
	Runner.T.ok(r[0] > 175.0 and r[0] <= 180.0, "unpause refreshes to ~3s (show=%.1f)" % r[0])
	# A still-brighter window is NOT cut down by the unpause bump (maxf, not set).
	var r2 := Hud.verb_step(300.0, 42, 42, false, true, DT)
	Runner.T.ok(r2[0] > 295.0, "unpause never shortens a brighter window (show=%.1f)" % r2[0])


# Normal play (same run, no pause) decays one frame's worth and never underflows.
func test_window_decays_and_floors_at_zero() -> void:
	var r := Hud.verb_step(1.0, 7, 7, false, false, DT)
	Runner.T.eq(r[0], 0.0, "one frame from 1.0 clamps to 0 (transient chip fades fully out)")
	Runner.T.eq(int(r[1]), 7, "steady run keeps its sim id")
	var r2 := Hud.verb_step(120.0, 7, 7, false, false, DT)
	Runner.T.ok(absf(r2[0] - 119.0) < 0.001, "decays exactly one 60Hz frame (show=%.3f)" % r2[0])


# The transient verb chip lives low-center. Its 16px band must stay clear of the
# top-left stat panel + player rows (which occupy the top ~90px for any player
# count) and inside the 360px viewport — so it can never overlap other HUD chrome.
func test_verb_legend_sits_in_a_hud_safe_band() -> void:
	var band_top: float = Hud.VERB_LEGEND_Y - 8.0
	var band_bottom: float = Hud.VERB_LEGEND_Y + 8.0
	Runner.T.ok(band_top > 120.0, "verb chip top %d clears the top HUD panel" % int(band_top))
	Runner.T.ok(band_bottom <= 360.0, "verb chip bottom %d stays inside the viewport" % int(band_bottom))


# Whether an 'act' verb glyph resolves to a drawable texture on the CURRENT device —
# mirrors Art.draw_glyph's lookup (pad button sprite / blank keycap). Proves the
# ROLL/WHEEL/REVIVE actions are actually mapped, not just measured as _LEG_H squares.
func _act_glyph_resolves(act: String) -> bool:
	if Art.use_pad:
		if not Art._GLYPH_PAD.has(act):
			return false
		var t := Art.tex(Art._brand(Art._GLYPH_PAD[act]))
		return t != null and t.get_width() > 0
	return Art._GLYPH_KEY.has(act) and Art.tex("ui_key_blank") != null


class _VerbMain extends Node2D:
	var _menu = null
	var _motion := 1.0


# A HudIcons whose draw SEAMS record instead of paint — so calling the REAL
# _verb_legend() outside a live draw context captures the exact commands it issues.
class _CaptureHud extends HudIcons:
	var ops: Array = []
	func _emit_rect(r: Rect2, _c: Color) -> void:
		ops.append({"k": "rect", "id": "", "box": r})
	func _emit_glyph(act: String, center: Vector2, size: float, _c: Color) -> void:
		ops.append({"k": "glyph", "id": act, "box": Rect2(center - Vector2(size, size) / 2.0, Vector2(size, size))})
	func _emit_label(txt: String, pos: Vector2, _c: Color) -> void:
		var s := Art.font().get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 8)
		ops.append({"k": "label", "id": txt, "box": Rect2(pos - Vector2(0.0, Art.font().get_ascent(8)), s)})


# c1-04 TRUE draw-command capture: invoke the REAL _verb_legend() (bright window
# armed) in BOTH device modes and inspect what it actually emitted — the plate rect,
# the three device-aware verb glyphs (roll/wheel/revive), and their labels. Every
# emitted command's box (real font ascent/height, not a hard-coded label height) lands
# inside 640x360 and the low HUD-safe band, is centered on 320, never overlaps, and
# every verb glyph resolves to a real texture. Fails if _verb_legend stops drawing a
# verb. (Headless has no GL surface for pixel readback — capturing the emitted commands
# is the strongest render check available.)
func test_verb_legend_draw_commands_captured_both_devices() -> void:
	var was_pad: bool = Art.use_pad
	for pad in [false, true]:
		Art.use_pad = pad
		var dev := "pad" if pad else "kb"
		var cap := _CaptureHud.new()
		cap.main = _VerbMain.new()
		cap._verb_show = 300.0   # bright window armed so the chip actually draws
		cap._verb_legend()       # the REAL draw method — records into ops via the seams
		var labels: Array = []
		var glyphs: Array = []
		var plate := Rect2()
		for op in cap.ops:
			if op["k"] == "label":
				labels.append(op["id"])
			elif op["k"] == "glyph":
				glyphs.append(op["id"])
			elif op["k"] == "rect":
				plate = op["box"]
		Runner.T.ok("ROLL" in labels and "SUPPLY WHEEL" in labels and "REVIVE" in labels,
			"%s verb chip draws ROLL/WHEEL/REVIVE labels" % dev)
		for a in ["roll", "wheel", "revive"]:
			Runner.T.ok(a in glyphs, "%s verb chip emits the %s glyph" % [dev, a])
			Runner.T.ok(_act_glyph_resolves(a), "%s verb glyph '%s' resolves to a texture" % [dev, a])
		Runner.T.ok(plate.position.x >= 0.0 and plate.end.x <= 640.0, "%s verb plate within 640 [%d,%d]" % [dev, int(plate.position.x), int(plate.end.x)])
		Runner.T.ok(plate.position.y > 120.0 and plate.end.y <= 360.0, "%s verb plate in safe band [%d,%d]" % [dev, int(plate.position.y), int(plate.end.y)])
		Runner.T.ok(absf(plate.get_center().x - 320.0) < 2.0, "%s verb chip centered on 320" % dev)
		var prev_right := -1.0
		for op in cap.ops:
			if op["k"] == "rect":
				continue
			var box: Rect2 = op["box"]
			Runner.T.ok(box.position.x >= 0.0 and box.end.x <= 640.0, "%s verb %s '%s' within 640" % [dev, op["k"], op["id"]])
			Runner.T.ok(box.position.y > 120.0 and box.end.y <= 360.0, "%s verb %s '%s' in safe band" % [dev, op["k"], op["id"]])
			Runner.T.ok(box.position.x >= prev_right - 0.5, "%s verb %s '%s' does not overlap the previous" % [dev, op["k"], op["id"]])
			prev_right = maxf(prev_right, box.end.x)
		cap.main.free()
		cap.free()
	Art.use_pad = was_pad   # restore global so device state can't leak to other suites
