class_name ExplosionsPolishTests
extends RefCounted
## Layered explosions / impact VFX (src/view/explosions_polish.gd), view-only. Pure-state checks
## plus the wiring through the real main.gd classify pass.

const Runner := preload("res://tests/run_tests.gd")
const Acc := preload("res://tests/test_accessibility_main.gd")


func _main() -> Acc.ClockMain:
	var main := Acc.ClockMain.new()
	Acc.new()._prepare(main)
	return main


func _lum(c: Color) -> float:
	return c.r * 0.3 + c.g * 0.59 + c.b * 0.11


func test_fire_ramp_cools_white_to_yellow_to_orange_to_dark_red() -> void:
	var w := ExplosionsPolish.fire_color(0.0)
	var y := ExplosionsPolish.fire_color(1.0 / 3.0)
	var o := ExplosionsPolish.fire_color(2.0 / 3.0)
	var r := ExplosionsPolish.fire_color(1.0)
	Runner.T.ok(w.r > 0.95 and w.g > 0.95 and w.b > 0.85, "u=0 is white-hot")
	Runner.T.ok(y.r > 0.95 and y.g > 0.8 and y.b < 0.4, "a third in it is yellow")
	Runner.T.ok(o.r > 0.95 and o.g > 0.4 and o.g < 0.6 and o.b < 0.2, "two thirds in it is orange")
	Runner.T.ok(r.r < 0.55 and r.g < 0.12 and r.b < 0.08, "spent fire is dark red")
	Runner.T.ok(_lum(w) > _lum(y) and _lum(y) > _lum(o) and _lum(o) > _lum(r), "the ramp only ever darkens")


func test_hash_is_deterministic_and_spread() -> void:
	Runner.T.eq(ExplosionsPolish.hash01(123, 4), ExplosionsPolish.hash01(123, 4), "same seed, same value")
	var distinct := {}
	for k in 20:
		distinct[ExplosionsPolish.hash01(77, k)] = true
	Runner.T.ok(distinct.size() >= 15, "successive keys do not collapse to one value")


func test_ingest_takes_each_explosion_once_and_caps() -> void:
	var p := ExplosionsPolish.new()
	var fx: Array = [{"x": 1000, "y": 2000, "t": 0.0, "kind": "explosion"}, {"kind": "spark", "x": 0, "y": 0}]
	p.ingest(fx, [], 50, Callable())
	p.ingest(fx, [], 51, Callable())
	Runner.T.eq(p.blasts.size(), 1, "one explosion entry registers exactly one layered blast")
	for i in ExplosionsPolish.MAX_BLASTS + 6:
		p.add_blast(i * 100, 0, 51)
	Runner.T.eq(p.blasts.size(), ExplosionsPolish.MAX_BLASTS, "live blasts are capped")


func test_events_make_hit_and_death_puffs_once_per_tick_and_skip_water() -> void:
	var p := ExplosionsPolish.new()
	var evs: Array = [{"t": "bullet_dirt", "x": 10, "y": 10}, {"t": "kill", "x": 20, "y": 20, "kind": "rusher"},
		{"t": "kill", "x": 30, "y": 30, "kind": "pilot"}]
	p.ingest([], evs, 10, Callable())
	p.ingest([], evs, 10, Callable())
	Runner.T.eq(p.puffs.size(), 2, "a strike and a death puff; the pilot (rescue) gets none; same tick is not re-ingested")
	var q := ExplosionsPolish.new()
	q.ingest([], evs, 11, func(_x, _y): return true)
	Runner.T.eq(q.puffs.size(), 0, "water strikes are the splash path's, not dust")


func test_blasts_expire_and_a_restarted_clock_drops_stale_ones() -> void:
	var p := ExplosionsPolish.new()
	p.add_blast(0, 0, 100)
	p.prune(100 + ExplosionsPolish.SMOKE_FRAMES + 5, 1.0)
	Runner.T.eq(p.blasts.size(), 1, "smoke still lingers for the full ~2.5 s")
	p.prune(100 + ExplosionsPolish.SMOKE_FRAMES + 40, 1.0)
	Runner.T.eq(p.blasts.size(), 0, "then it is gone")
	p.add_blast(0, 0, 500)
	p.prune(3, 1.0)
	Runner.T.eq(p.blasts.size(), 0, "a sim restart (tick rewinds) discards stale blasts")
	Runner.T.ok(ExplosionsPolish.smoke_life(0.0) < ExplosionsPolish.smoke_life(1.0), "reduce-motion shortens the linger")


func test_real_main_classify_pass_feeds_the_module() -> void:
	var main := _main()
	main._fx.append({"x": 5000, "y": 6000, "t": 0.0, "kind": "explosion"})
	main.sim.events = [{"t": "kill", "x": 7000, "y": 8000, "kind": "rusher"}]
	main._classify_fx()
	main._classify_fx()
	Runner.T.eq(main._explo_polish.blasts.size(), 1, "main._classify_fx registers the blast once")
	Runner.T.eq(main._explo_polish.puffs.size(), 1, "main._classify_fx turns the kill event into a death puff")
	Runner.T.ok(main._fx[0].has("pf"), "the fx entry is flagged as taken")
	main.free()
