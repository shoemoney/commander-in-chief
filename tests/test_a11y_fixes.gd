extends RefCounted
## ACCESSIBILITY FIXES: (1) the low-reinforcements warning never dims; (2) the three CAPTIONS
## modes mean what they say. Asserts the HUD's computed layout / captured text alphas.

const Runner := preload("res://tests/run_tests.gd")
const HudTests := preload("res://tests/test_hud.gd")
const MainScript := preload("res://src/main.gd")


# --- 1. reinforcements warning -----------------------------------------------------------------

func _paint(h, sim: SimWorld, tick: int) -> void:
	sim.tick_count = tick
	h.boxes.clear()
	h._fit_full = HudIcons.RIGHT
	h._measure = true
	var plan: Dictionary = h._plan_row0(sim, 8.0, 6.0, false)
	h._measure = false
	h._opt_keep = plan["keep"]
	h._row0_opt(sim, 8.0, 6.0, false)


## Alpha of the REINFORCEMENTS text after `ticks` quiet ticks with `left` stand-ups remaining.
func _reinf_alpha(left: int, ticks: int) -> float:
	Art.text_scale = 1.0
	var sim := SimWorld.new(0, 1, "campaign")
	sim.deaths_since_gate = SimWorld.SECTOR_STANDUPS - left
	var main = HudTests._RowMain.new()
	main.sim = sim
	main._motion = 0.0
	var h = HudTests._FrameCaptureHud.new()
	h.main = main
	var a := -1.0
	var t := 100
	while t <= 100 + ticks:
		_paint(h, sim, t)
		t += 3
	for b in h.boxes:
		if b["k"] == "text" and String(b["id"]).begins_with("REINFORCEMENTS"):
			a = float(b["alpha"])
	h.free()
	main.free()
	return a


func test_the_low_reinforcements_warning_never_dims() -> void:
	Runner.T.eq(sim_left_check(), true, "the rig really produces the stand-ups it claims")
	for left in [2, 1, 0]:
		var a := _reinf_alpha(left, 600)
		Runner.T.ok(absf(a - 1.0) < 0.001, "%d left, 600 quiet ticks: warning is full strength (measured %.2f)" % [left, a])
	var calm := _reinf_alpha(SimWorld.SECTOR_STANDUPS - 1, 600) if SimWorld.SECTOR_STANDUPS - 1 > 2 else -2.0
	if calm >= 0.0:
		Runner.T.ok(absf(calm - HudDiet.DIM_ALPHA) < 0.02, "above the warning threshold the chip still dims (measured %.2f)" % calm)


func sim_left_check() -> bool:
	var sim := SimWorld.new(0, 1, "campaign")
	sim.deaths_since_gate = SimWorld.SECTOR_STANDUPS - 2
	return sim.standups_left() == 2


func test_a_chip_above_two_dims_as_before() -> void:
	var left := 5
	var sim := SimWorld.new(0, 1, "campaign")
	sim.deaths_since_gate = SimWorld.SECTOR_STANDUPS - left
	if sim.standups_left() != left:
		return   # SECTOR_STANDUPS too small for a 5-left rig: nothing to compare
	var a := _reinf_alpha(left, 600)
	Runner.T.ok(absf(a - HudDiet.DIM_ALPHA) < 0.02, "5 left dims after the idle window (measured %.2f)" % a)


# --- 2. caption modes --------------------------------------------------------------------------

class _CapMain extends Node2D:
	var sim: SimWorld = null
	var _debrief := false
	var _menu = null
	var _motion := 1.0
	var _captions := true
	var _caption_mode := 0
	var _sfx = null
	var _grenade_dry: Array = [0, 0]
	var _token_loss_t := 0.0
	var best_score := 0
	var best_wave := 0
	var _record_fired := false
	func bind_for_glyph(_a: String) -> int: return 0
	func pad_bind_for_glyph(_a: String, _device := 0) -> int: return -1


## Fire `key` for the nth time under `mode` and return the HUD's resolved layout.
func _layout(mode: int, key: String, exposures: int, sfx_step := 10, text_scale := 1.0) -> Dictionary:
	Art.text_scale = text_scale
	var stub := _CapMain.new()
	stub._caption_mode = mode
	stub._captions = mode != CuePolicy.CAP_OFF
	var sfx := Sfx.new()
	stub._sfx = sfx
	sfx.caption_mode = mode
	sfx.sfx_step = sfx_step
	var hud := HudIcons.new()
	hud.main = stub
	for i in exposures:
		sfx.clear_captions()
		sfx._sfx_cap_next.clear()
		sfx.caption_sfx(key)
	var lay: Dictionary = hud.caption_layout()
	hud.free()
	sfx.free()
	stub.free()
	Art.text_scale = 1.0
	return lay


func test_all_draws_the_full_bracket_at_full_size_every_time() -> void:
	for n in [1, 3, 4, 50]:
		var lay := _layout(CuePolicy.CAP_ALL, "sniper_paint", n)
		Runner.T.ok(not lay.is_empty() and not lay.has("icon"), "ALL exposure %d: no abbreviated chip" % n)
		var joined := " ".join(lay["lines"])
		Runner.T.ok(joined.contains("[") and joined.length() > 12, "ALL exposure %d: the bracketed text (%s)" % [n, joined])
		Runner.T.eq(lay["cs"], Art.fs(HudIcons.FONT_SIZE), "ALL exposure %d: full caption font size" % n)


func test_smart_draws_a_chip_then_glyph_only_and_never_nothing() -> void:
	var first := _layout(CuePolicy.CAP_SMART, "sniper_paint", 1)
	Runner.T.ok(first.has("icon") and String(first["lines"][0]) == "SNIPER", "SMART exposure 1: glyph plus the word")
	var third := _layout(CuePolicy.CAP_SMART, "sniper_paint", 3)
	Runner.T.eq(String(third["lines"][0]), "SNIPER", "exposure 3 still has the word")
	var fourth := _layout(CuePolicy.CAP_SMART, "sniper_paint", 4)
	Runner.T.ok(fourth.has("icon") and bool(fourth.get("glyph_only", false)) and String(fourth["lines"][0]) == "",
		"exposure 4: the glyph alone")
	Runner.T.ok((fourth["bg"] as Rect2).size.x < (first["bg"] as Rect2).size.x, "...on a narrower plate")
	var late := _layout(CuePolicy.CAP_SMART, "sniper_paint", 50)
	Runner.T.ok(not late.is_empty() and late.has("icon"), "a cue is still drawn at exposure 50")
	for step in [0, 1]:
		var muted := _layout(CuePolicy.CAP_SMART, "sniper_paint", 50, step)
		Runner.T.eq(String(muted["lines"][0]), "SNIPER", "SFX step %d: the word comes back" % step)


func test_off_draws_no_cue_caption_and_enlarged_text_forces_words() -> void:
	Runner.T.ok(_layout(CuePolicy.CAP_OFF, "sniper_paint", 1).is_empty(), "OFF: nothing")
	var big := _layout(CuePolicy.CAP_SMART, "sniper_paint", 50, 10, 1.5)
	Runner.T.ok(not big.has("icon") and " ".join(big["lines"]).contains("["), "SMART at 150% text: the full words")


func test_defaults_and_old_saves_migrate() -> void:
	Runner.T.eq(MainScript.SETTINGS_DEFAULTS["captions"], CuePolicy.CAP_SMART, "a fresh config is SMART")
	Runner.T.eq(CuePolicy.migrate_caption_mode(true), CuePolicy.CAP_ALL, "saved true stays ALL")
	Runner.T.eq(CuePolicy.migrate_caption_mode(false), CuePolicy.CAP_OFF, "saved false stays OFF")
	Runner.T.eq(CuePolicy.migrate_caption_mode(CuePolicy.CAP_ALL), CuePolicy.CAP_ALL, "saved ALL stays ALL")


func test_pickup_words_per_mode() -> void:
	Runner.T.ok(CuePolicy.pickup_word(CuePolicy.CAP_ALL, 40, 1.0), "ALL: the word is always spelled out")
	Runner.T.ok(CuePolicy.pickup_word(CuePolicy.CAP_SMART, 1, 1.0), "SMART: grab 2 still has the word")
	Runner.T.ok(not CuePolicy.pickup_word(CuePolicy.CAP_SMART, 2, 1.0), "SMART: grab 3 is an icon")
	Runner.T.ok(CuePolicy.pickup_word(CuePolicy.CAP_SMART, 40, 1.5), "enlarged text forces the word")
	var m := MainScript.new()
	m._menu.mode = GameMenu.Mode.HIDDEN
	m._caption_mode = CuePolicy.CAP_ALL
	for i in 6:
		Runner.T.ok(m._pickup_word_due("4"), "main, ALL, grab %d: word due" % (i + 1))
	m.free()
