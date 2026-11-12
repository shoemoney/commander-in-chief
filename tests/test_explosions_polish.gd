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


func test_blast_ages_out_on_the_view_clock_while_the_sim_is_frozen_on_the_result_card() -> void:
	var main := _main()
	main._fx.append({"x": 5000, "y": 6000, "t": 0.0, "kind": "explosion"})
	main._classify_fx()
	Runner.T.eq(main._explo_polish.blasts.size(), 1, "the blast is live before the card")
	var tick_before: int = main.sim.tick_count
	main._debrief = true
	for _f in 20:
		main._classify_fx()
		main._classify_fx(false)   # _draw_fx's second call must not double-age
	Runner.T.eq(main._explo_polish.blasts.size(), 1, "20 card frames in, the smoke still lingers")
	Runner.T.eq(main._explo_polish._clock, 20, "two classify calls per frame age the blast one tick per frame")
	for _f in ExplosionsPolish.SMOKE_FRAMES + 20:
		main._classify_fx()
	Runner.T.eq(main.sim.tick_count, tick_before, "the sim tick never moved")
	Runner.T.eq(main._explo_polish.blasts.size(), 0, "the blast finished and was pruned although the sim is stopped")
	main.free()


func test_hit_stop_still_freezes_a_blast_when_no_card_is_up() -> void:
	var p := ExplosionsPolish.new()
	var t0 := p.view_clock(100, false)
	Runner.T.eq(p.view_clock(100, false), t0, "an unchanged sim tick (hit-stop) holds the clock")
	Runner.T.eq(p.view_clock(101, false), t0 + 1, "a stepped sim advances it")
	Runner.T.eq(p.view_clock(101, true), t0 + 2, "a stopped sim on the result card free-runs")


func test_reset_clears_polish_state_through_the_real_main() -> void:
	var main := _main()
	main._fx.append({"x": 5000, "y": 6000, "t": 0.0, "kind": "explosion"})
	main.sim.events = [{"t": "kill", "x": 7000, "y": 8000, "kind": "rusher"}]
	main._classify_fx()
	main._polish.hurt_age.append(3)
	BossesPolish.push_track(0, 1000, 1000, 0.0)
	Runner.T.ok(not main._explo_polish.blasts.is_empty() and not BossesPolish._trails.is_empty(), "state exists before the reset")
	main._reset()
	Runner.T.eq(main._explo_polish.blasts.size() + main._explo_polish.puffs.size(), 0, "_reset drops blasts and puffs")
	Runner.T.eq(main._explo_polish._clock, 0, "_reset rewinds the view clock")
	Runner.T.ok(main._polish.hurt_age.is_empty(), "_reset clears the player polish state")
	Runner.T.ok(BossesPolish._trails.is_empty(), "_reset clears the tank trails")
	main.free()


func test_blast_statics_follow_the_blast_and_die_with_it() -> void:
	var p := ExplosionsPolish.new()
	p.add_blast(5000, 6000, 10)
	p.add_blast(5000, 6000, 10, 2.0)
	var a: Dictionary = ExplosionsPolish.blast_statics(p.blasts[0])
	var b: Dictionary = ExplosionsPolish.blast_statics(p.blasts[1])
	Runner.T.ok(a != b and b["fs"] > a["fs"], "a bigger blast gets its own, larger statics")
	var sd: int = p.blasts[0]["seed"]
	var sc: float = a["sc"]
	Runner.T.eq(a["s_spread"][3], (6.0 + 16.0 * ExplosionsPolish.hash01(sd, 23)) * sc, "smoke spread is the hashed value it replaced")
	Runner.T.eq(a["f_dist"][2], ExplosionsPolish.FIRE_R * sc * 0.38 * ExplosionsPolish.hash01(sd, 72), "lobe offset matches")
	Runner.T.eq(a["c_sz"][4], 1.3 + 1.6 * ExplosionsPolish.hash01(sd, 124), "chunk size matches")
	Runner.T.ok(ExplosionsPolish.blast_statics(p.blasts[0]) == a and p.blasts[0].has("pre"), "built once, held on the blast")
	p.reset()
	Runner.T.eq(p.blasts.size(), 0, "reset drops the blasts and their statics with them")
	p.add_blast(5000, 6000, 20)
	Runner.T.ok(not p.blasts[0].has("pre"), "a blast added after a reset starts without cached statics")
	Runner.T.eq(ExplosionsPolish.fire_color(0.0), Color(1.0, 1.0, 0.92), "ramp start unchanged")
	Runner.T.ok(ExplosionsPolish.fire_color(1.0).is_equal_approx(Color(0.46, 0.08, 0.04)), "ramp end unchanged")
