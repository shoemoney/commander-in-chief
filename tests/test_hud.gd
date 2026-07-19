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


class _RowMain extends Node2D:
	var _motion := 1.0
	var best_score := 0
	var best_wave := 0
	var _menu = null


# c1-06: the row-0 planner keeps the highest-PRIORITY optional chips, not the ones that
# happen to draw first — combat readouts (HOSTILES, prio 90) outrank vanity (streak 50 /
# record 35) even though streak/record draw earlier.
func test_select_priority_keeps_highest_priority() -> void:
	var cands: Array = [
		{"id": "streak", "prio": 50, "w": 30.0},
		{"id": "record", "prio": 35, "w": 40.0},
		{"id": "hostiles", "prio": 90, "w": 120.0},
	]
	# Budget fits only one chip: the combat dashboard must be the survivor.
	var sel := HudIcons._select_priority(cands, 125.0)
	Runner.T.ok(sel["keep"].has("hostiles"), "HOSTILES (highest priority) is kept")
	Runner.T.ok(not sel["keep"].has("streak"), "vanity streak is dropped despite drawing first")
	Runner.T.ok(not sel["keep"].has("record"), "vanity record is dropped")
	Runner.T.eq(int(sel["hidden"]), 2, "the two dropped readouts feed the +N count")


func test_select_priority_no_lower_past_a_dropped_higher() -> void:
	# A wide high-priority chip that does not fit blocks the row — a narrow LOWER-priority
	# chip must not slip in behind it.
	var cands: Array = [
		{"id": "big", "prio": 90, "w": 300.0},
		{"id": "tiny", "prio": 20, "w": 5.0},
	]
	var sel := HudIcons._select_priority(cands, 100.0)
	Runner.T.eq(int(sel["hidden"]), 2, "the tiny low-priority chip does not jump ahead")
	Runner.T.ok(sel["keep"].is_empty(), "nothing is kept when the top priority misses")


func test_select_priority_all_fit() -> void:
	var cands: Array = [
		{"id": "a", "prio": 90, "w": 30.0},
		{"id": "b", "prio": 50, "w": 30.0},
	]
	var sel := HudIcons._select_priority(cands, 200.0)
	Runner.T.eq(int(sel["hidden"]), 0, "everything fits -> nothing hidden")
	Runner.T.ok(sel["keep"].has("a") and sel["keep"].has("b"), "both retained")


# c1-06 REAL row-0 layout: run the actual measure pass over a live endless SimWorld, then
# plan — proving the enumerated candidates include the combat dashboard at top priority and
# that a tight budget drops the vanity chips first (not an arithmetic-only planner test).
func test_row0_measure_prioritizes_combat_readouts() -> void:
	var h := HudIcons.new()
	h.main = _RowMain.new()
	var sim := SimWorld.new(0, 1, "endless")
	sim.kill_streak = 5          # streak chip (vanity, prio 50)
	sim.kill_streak_timer = 30
	sim.wave = 3                 # HOSTILES dashboard active (combat, prio 90)
	sim.deaths_this_wave = 1     # DEATHLESS suppressed
	sim.wave_mod = 0
	# Measure pass: enumerate every optional chip the row would draw.
	h._measure = true
	h._opt_cands = []
	h._opt_keep = {}
	h._row0_opt(sim, 8.0, 6.0, false)
	var ids: Array = []
	var hostiles_w := 0.0
	for c in h._opt_cands:
		ids.append(c["id"])
		if c["id"] == "hostiles":
			hostiles_w = float(c["w"])
	Runner.T.ok("hostiles" in ids, "the HOSTILES dashboard is enumerated as a candidate")
	Runner.T.ok("streak" in ids, "the streak chip is enumerated as a candidate")
	# A budget that fits only the widest single chip keeps HOSTILES, drops the rest.
	var sel := HudIcons._select_priority(h._opt_cands, hostiles_w + 1.0)
	Runner.T.ok(sel["keep"].has("hostiles"), "under pressure the combat readout survives")
	Runner.T.ok(not sel["keep"].has("streak"), "the vanity streak chip is dropped, surfaced as +N")
	Runner.T.ok(int(sel["hidden"]) >= 1, "dropped readouts are counted for the +N chip")
	h.main.free()
	h.free()


# c1-06: the shared two-pass planner. Reserve the +N slot ONLY on real overflow (no
# phantom overflow from a permanent reserve), and STOP at the first miss.
func test_plan_no_overflow_keeps_full_width() -> void:
	var p := HudIcons.plan_chips([40.0, 40.0, 40.0], 8.0, 200.0, 24.0)
	Runner.T.eq(int(p["shown"]), 3, "all three chips shown when they fit")
	Runner.T.eq(int(p["hidden"]), 0, "nothing hidden on a fitting row")
	Runner.T.ok(not p["reserved"], "the +N slot is NOT reserved on a fitting row")


func test_plan_reserves_only_on_real_overflow() -> void:
	# Both chips fit against the TRUE edge, but the last sits inside the +N slot. A
	# permanent 24px reserve would drop it as phantom overflow; the two-pass keeps it.
	var p := HudIcons.plan_chips([100.0, 90.0], 0.0, 200.0, 24.0)
	Runner.T.eq(int(p["shown"]), 2, "both chips fit against the true edge")
	Runner.T.eq(int(p["hidden"]), 0, "no phantom overflow from reserving the slot early")
	Runner.T.ok(not p["reserved"], "no reserve when everything genuinely fits")


func test_plan_first_frame_overflow_is_deterministic() -> void:
	# 80+80 fit, the third (240) misses -> overflow. Reserve pass (bound 176): 80+80 fit,
	# third still misses -> shown 2, hidden 1, decided on the FIRST frame (no lag).
	var p := HudIcons.plan_chips([80.0, 80.0, 80.0], 0.0, 200.0, 24.0)
	Runner.T.ok(p["reserved"], "real overflow reserves the +N slot")
	Runner.T.eq(int(p["shown"]), 2, "two chips fit against the reserved edge")
	Runner.T.eq(int(p["hidden"]), 1, "the tail chip is counted, not dropped silently")


func test_plan_stops_at_first_miss_priority() -> void:
	# An oversized HIGH-priority chip followed by a tiny LOW-priority one: the tiny chip
	# must NOT sneak in past the dropped high one.
	var p := HudIcons.plan_chips([300.0, 5.0], 0.0, 200.0, 24.0)
	Runner.T.eq(int(p["shown"]), 0, "the oversized leading chip blocks the row")
	Runner.T.eq(int(p["hidden"]), 2, "the narrow low-priority chip does not jump ahead")


func test_plan_overflow_appears_and_disappears() -> void:
	var full := HudIcons.plan_chips([120.0, 120.0], 0.0, 200.0, 24.0)
	Runner.T.eq(int(full["hidden"]), 1, "a crowded row overflows into +N")
	var clear := HudIcons.plan_chips([120.0], 0.0, 200.0, 24.0)
	Runner.T.eq(int(clear["hidden"]), 0, "when the row clears the +N disappears")
	Runner.T.ok(not clear["reserved"], "and the reserve is released")


# c1-06: a live CB/RM pip owns the top-right corner, so the usable edge pulls in.
func test_corner_reserve_for_cb_rm_pips() -> void:
	Runner.T.eq(HudIcons._corner_reserve(false, 1.0), 0.0, "no reserve without CB/RM")
	Runner.T.eq(HudIcons._corner_reserve(true, 1.0), 18.0, "colorblind pip reserves the corner")
	Runner.T.eq(HudIcons._corner_reserve(false, 0.0), 18.0, "reduce-motion pip reserves the corner")


# c1-06: the +N chip is right-anchored with its MEASURED width, so its border stays fully
# within the usable edge (never a fixed slot that could under-reserve a two-digit +N).
func test_ovf_chip_stays_within_usable_edge() -> void:
	var h := HudIcons.new()
	var usable := 632.0
	for n in [1, 9, 12]:
		var ow: float = h._tw("+%d" % n) + HudIcons.OVF_PAD
		var ovf_left := usable - ow
		Runner.T.ok(ovf_left >= 0.0, "+%d left edge is non-negative" % n)
		Runner.T.ok(ovf_left + ow <= usable + 0.01, "+%d border right edge within the usable edge" % n)
	h.free()


# c1-06: buff-chip widths are the EXACT x-advance the drawing produces (vest / timed /
# claymore-glyph), so the fit measure can never disagree with what actually lands.
func test_chip_width_matches_stat_advance() -> void:
	var h := HudIcons.new()
	Runner.T.eq(h._chip_w({"vest": true}), HudIcons.ICON + 2.0, "vest chip width")
	var w := h._chip_w({"icon": "wep_smoke", "txt": "5s", "col": Color.WHITE})
	Runner.T.eq(w, HudIcons.ICON + 13.0 + h._tw("5s"), "timed-buff chip width == _stat advance")
	var wg := h._chip_w({"icon": "wep_claymore", "txt": "x2", "col": Color.WHITE, "glyph": true})
	Runner.T.eq(wg, HudIcons.ICON + 13.0 + h._tw("x2") + 12.0, "claymore chip adds the interact glyph")
	h.free()


# c1-06: a crowded player buff run overflows into +N while every SHOWN chip ends within
# the reserved edge — identical for either player row (same planner, same start x).
func test_player_row_overflow_stays_within_edge() -> void:
	var h := HudIcons.new()
	var widths: Array[float] = []
	for i in 12:
		widths.append(60.0)
	var ovf_w: float = h._tw("+%d" % widths.size()) + HudIcons.OVF_PAD
	var p := HudIcons.plan_chips(widths, 8.0, 632.0, ovf_w)
	var shown: int = p["shown"]
	Runner.T.ok(p["hidden"] > 0, "the tail buff chips overflow into +N")
	var end_x := 8.0 + shown * 60.0
	Runner.T.ok(end_x <= 632.0 - ovf_w + 0.01, "last shown chip ends within the reserved edge")
	h.free()


# c1-06: the mandatory campaign PRESSURE / CLEAR THE GATE telegraph is measured up front
# as a right-side footprint (so optional chips co-layout around it); endless has none.
func test_telegraph_reserves_right_footprint() -> void:
	var h := HudIcons.new()
	var sim := SimWorld.new(0, 1, "campaign")
	sim.stall_ticks = 100   # past the 30-tick arm; observer empty on a fresh sim
	var spec := h._telegraph_spec(sim)
	Runner.T.ok(spec["kind"] == "pressure" or spec["kind"] == "gate", "campaign stall shows a telegraph")
	Runner.T.ok(float(spec["w"]) > 0.0, "the telegraph reserves a right-side footprint")
	var sim2 := SimWorld.new(0, 1, "endless")
	sim2.stall_ticks = 100
	Runner.T.eq(h._telegraph_spec(sim2)["kind"], "", "endless has no PRESSURE/GATE telegraph")
	Runner.T.eq(float(h._telegraph_spec(sim2)["w"]), 0.0, "endless reserves no telegraph footprint")
	h.free()


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
