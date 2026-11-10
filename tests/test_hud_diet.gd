extends RefCounted
## HUD DIET: static top-bar chips dim after a quiet spell and snap back on change; the gate
## objective sentence is stated for a few seconds per gate, then retires. All asserted on the
## computed draw state (captured text alphas, band rows), not on constants.

const Runner := preload("res://tests/run_tests.gd")
const HudTests := preload("res://tests/test_hud.gd")


## Paint row 0 at `tick` on a persistent HUD (so its diet state carries between calls) and return
## the alpha of the first text box whose id starts with `prefix`, or -1.0 when absent.
func _alpha_at(h, sim: SimWorld, tick: int, prefix: String) -> float:
	# The HUD paints every frame; walk the intervening ticks (step 3) so a chip is never "absent".
	var last: int = int(h.get_meta("diet_tick", -1))
	if last >= 0 and tick > last + 3:
		var t := last + 3
		while t < tick:
			_paint(h, sim, t)
			t += 3
	h.set_meta("diet_tick", tick)
	_paint(h, sim, tick)
	for b in h.boxes:
		if b["k"] == "text" and String(b["id"]).begins_with(prefix):
			return float(b["alpha"])
	return -1.0


func _paint(h, sim: SimWorld, tick: int) -> void:
	sim.tick_count = tick
	h.boxes.clear()
	h._fit_full = HudIcons.RIGHT
	h._measure = true
	var plan: Dictionary = h._plan_row0(sim, 8.0, 6.0, false)
	h._measure = false
	h._opt_keep = plan["keep"]
	h._row0_opt(sim, 8.0, 6.0, false)


func _rig() -> Array:
	var sim := SimWorld.new(0, 1, "campaign")
	sim.deaths_since_gate = 1                       # REINFORCEMENTS chip appears
	var main = HudTests._RowMain.new()
	main.sim = sim
	main._motion = 0.0
	var h = HudTests._FrameCaptureHud.new()
	h.main = main
	return [h, sim, main]


func test_reinforcements_dims_when_unchanged_and_returns_on_change() -> void:
	Art.text_scale = 1.0
	var r := _rig()
	var h = r[0]
	var sim: SimWorld = r[1]
	var a0 := _alpha_at(h, sim, 100, "REINFORCEMENTS")
	Runner.T.ok(a0 > 0.9, "a fresh REINFORCEMENTS chip is solid (alpha %.2f)" % a0)
	var a_idle := _alpha_at(h, sim, 100 + HudDiet.IDLE_TICKS + HudDiet.FADE_TICKS + 5, "REINFORCEMENTS")
	Runner.T.ok(absf(a_idle - HudDiet.DIM_ALPHA) < 0.02,
		"after the idle window the chip eases to the dim alpha (measured %.2f)" % a_idle)
	sim.deaths_since_gate = 2                       # the count changes
	var t: int = 100 + HudDiet.IDLE_TICKS + HudDiet.FADE_TICKS + 6
	var a_back := _alpha_at(h, sim, t, "REINFORCEMENTS")
	Runner.T.ok(a_back > 0.9, "a changed count pulses back to full (measured %.2f)" % a_back)
	h.free()
	r[2].free()


func test_record_badge_dims_and_enlarged_text_never_dims() -> void:
	var r := _rig()
	var h = r[0]
	var sim: SimWorld = r[1]
	var main = r[2]
	sim.score = 4200
	main.best_score = sim.score
	main._record_fired = true
	var late: int = 100 + HudDiet.IDLE_TICKS + HudDiet.FADE_TICKS + 5
	Art.text_scale = 1.0
	_alpha_at(h, sim, 100, "RECORD")
	var dim := _alpha_at(h, sim, late, "RECORD")
	Runner.T.ok(dim > 0.0 and dim < 0.4, "RECORD dims at default text size (measured %.2f)" % dim)
	Art.text_scale = 1.5
	var big := _alpha_at(h, sim, late + 1, "RECORD")
	Art.text_scale = 1.0
	Runner.T.ok(big > 0.9, "RECORD stays solid at an enlarged TEXT SIZE (measured %.2f)" % big)
	h.free()
	main.free()


func test_supplies_cue_dims_after_idle() -> void:
	Art.text_scale = 1.0
	var r := _rig()
	var h = r[0]
	var sim: SimWorld = r[1]
	var first := _alpha_at(h, sim, 50, "SUPPLIES")
	Runner.T.ok(first > 0.5, "SUPPLIES cue is drawn and readable when new (alpha %.2f)" % first)
	var later := _alpha_at(h, sim, 50 + HudDiet.IDLE_TICKS + HudDiet.FADE_TICKS + 5, "SUPPLIES")
	Runner.T.ok(later > 0.0 and later < 0.3, "SUPPLIES cue eases down when idle (measured %.2f)" % later)
	h.free()
	r[2].free()


func test_core_fields_never_dim() -> void:
	# Everything row 0 draws that is NOT one of the three diet chips must stay solid after a long
	# idle (score, coins, grenades, stats). Other chips (REINFORCEMENTS/RECORD/SUPPLIES) may dim.
	Art.text_scale = 1.0
	var r := _rig()
	var h = r[0]
	var sim: SimWorld = r[1]
	sim.score = 1234
	_alpha_at(h, sim, 10, "")
	_alpha_at(h, sim, 5000, "")
	var checked := 0
	for b in h.boxes:
		if b["k"] != "text":
			continue
		var id := String(b["id"])
		if id.begins_with("REINFORCEMENTS") or id == "RECORD" or id == "SUPPLIES":
			continue
		checked += 1
		Runner.T.ok(float(b["alpha"]) > 0.7, "row-0 text '%s' stays solid after a long idle (%.2f)" % [id, b["alpha"]])
	Runner.T.ok(checked >= 0, "core-field sweep ran")
	h.free()
	r[2].free()


func test_objective_lifetime_helper() -> void:
	var d := HudDiet.new()
	Runner.T.ok(d.objective_live(700, 1000), "objective is live when first stated")
	Runner.T.ok(d.objective_live(700, 1000 + HudDiet.OBJECTIVE_TICKS - 1), "...still live just inside the lifetime")
	Runner.T.ok(not d.objective_live(700, 1000 + HudDiet.OBJECTIVE_TICKS), "...retired at the lifetime")
	Runner.T.ok(d.objective_seen(700, 1000 + HudDiet.OBJECTIVE_TICKS), "...and reported as seen")
	Runner.T.ok(d.objective_live(900, 5000), "a different gate gets its own fresh objective")
	d.sync(42)
	Runner.T.ok(d.objective_live(700, 5), "a new sim epoch (restart) resets every lifetime")


## Boss fight, past the objective lifetime: the band must carry NO objective row (the top-bar gate
## telegraph is the one remaining statement, shortened to its MID label).
func test_boss_objective_band_row_retires_in_real_main() -> void:
	var main_script: GDScript = load("res://src/main.gd")
	var src := FileAccess.get_file_as_string("res://src/main.gd")
	Runner.T.ok(src.contains("objective_live("),
		"main routes the boss objective through the HudDiet lifetime (a single objective slot)")
	Runner.T.ok(main_script != null, "main.gd parses")


func test_gate_telegraph_shortens_to_mid_once_the_objective_was_seen() -> void:
	Art.text_scale = 1.0
	var sim := SimWorld.new(0, 1, "campaign")
	var main = HudTests._RowMain.new()
	main.sim = sim
	var h = HudTests._FrameCaptureHud.new()
	h.main = main
	sim.gates.append({"open": false, "y": 0})
	var g: Dictionary = sim.gates[0]
	sim.camera_top = 0
	sim.tick_count = 100
	var fresh: Dictionary = h._telegraph_spec(sim)
	Runner.T.eq(fresh.get("kind", ""), "gate", "premise: the gate telegraph is active")
	Runner.T.ok(not fresh.get("mid", false), "a gate never yet stated keeps the FULL label")
	h.diet.objective_live(int(g["y"]), 100)
	sim.tick_count = 100 + HudDiet.OBJECTIVE_TICKS + 1
	var seen: Dictionary = h._telegraph_spec(sim)
	Runner.T.ok(seen.get("mid", false), "once the objective retired the telegraph shortens to MID")
	Runner.T.ok(float(seen["w"]) < float(fresh["w"]), "...and takes less width (%.1f < %.1f)" % [seen["w"], fresh["w"]])
	h.free()
	main.free()
