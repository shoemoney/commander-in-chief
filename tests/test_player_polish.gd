extends RefCounted
## Hero presence (view-only): muzzle flash, brass, dust, reticle overlay, hurt/downed reads.

const Runner := preload("res://tests/run_tests.gd")
const Main := preload("res://src/main.gd")


func _sim() -> SimWorld:
	return SimWorld.new(7, 2, "campaign")


func _idle() -> Array[SimInput]:
	return [SimInput.new(), SimInput.new()] as Array[SimInput]


func test_fire_cd_constant_mirrors_sim() -> void:
	Runner.T.eq(PlayerPolish.FIRE_CD, SimWorld.FIRE_COOLDOWN_TICKS, "view copy of the fire cooldown matches the sim")


func test_a_real_shot_starts_flash_and_ejects_brass() -> void:
	var sim := _sim()
	var pol := PlayerPolish.new()
	sim.step(_idle())
	pol.observe(sim.players, sim.tick_count, 1.0)
	Runner.T.eq(pol.flash_age[0], -1, "no flash before firing")
	var inp := _idle()
	inp[0].fire = true
	inp[0].aim_x = 0
	inp[0].aim_y = -256
	sim.step(inp)
	pol.observe(sim.players, sim.tick_count, 1.0)
	Runner.T.eq(pol.flash_age[0], 0, "the shot tick opens the flash")
	Runner.T.eq(pol.casings.size(), 1, "one casing ejected per shot")
	for _k in PlayerPolish.FLASH_TICKS + 2:
		sim.step(_idle())
		pol.observe(sim.players, sim.tick_count, 1.0)
	Runner.T.eq(pol.flash_age[0], -1, "flash is brief")
	Runner.T.eq(pol.casings.size(), 1, "brass lingers on the ground")
	for _k in PlayerPolish.CASING_LIFE:
		sim.step(_idle())
		pol.observe(sim.players, sim.tick_count, 1.0)
	Runner.T.eq(pol.casings.size(), 0, "brass fades away")


func test_observe_is_idempotent_per_tick_and_reduce_motion_skips_flight() -> void:
	var sim := _sim()
	var pol := PlayerPolish.new()
	sim.step(_idle())
	pol.observe(sim.players, sim.tick_count, 0.0)
	var inp := _idle()
	inp[0].fire = true
	inp[0].aim_y = -256
	sim.step(inp)
	pol.observe(sim.players, sim.tick_count, 0.0)
	pol.observe(sim.players, sim.tick_count, 0.0)
	Runner.T.eq(pol.casings.size(), 1, "same tick observed twice emits once")
	Runner.T.ok(pol.casings[0]["rest"], "reduce-motion brass lands immediately")


func test_flash_layers_directional_and_accessible() -> void:
	var full := PlayerPolish.flash_layers(0, 1.0)
	Runner.T.ok(full.size() >= 4, "full flash: cone layers plus crack spikes")
	var tip := 0.0
	for l in full:
		for v: Vector2 in l["pts"]:
			tip = maxf(tip, v.x)
	Runner.T.ok(tip >= 15.0, "cone reaches well past the muzzle (%.1f)" % tip)
	Runner.T.ok(PlayerPolish.flash_layers(0, 0.3).size() < full.size(), "calm mode drops the spikes")
	Runner.T.ok(PlayerPolish.flash_layers(0, 0.0).is_empty(), "flash off means nothing drawn")
	Runner.T.ok(PlayerPolish.flash_layers(PlayerPolish.FLASH_TICKS + 1, 1.0).is_empty(), "flash expires")
	Runner.T.ok(PlayerPolish.light_pool(0, 1.0)["col"].a > PlayerPolish.light_pool(5, 1.0)["col"].a, "light pool fades")


func test_dust_on_footsteps_and_reduce_motion() -> void:
	var sim := _sim()
	var pol := PlayerPolish.new()
	var inp := _idle()
	inp[0].move_x = 256
	for _k in 40:
		sim.step(inp)
		pol.observe(sim.players, sim.tick_count, 1.0)
	Runner.T.ok(pol.dust.size() > 0, "walking kicks footstep dust")
	var still := PlayerPolish.new()
	var sim2 := _sim()
	for _k in 40:
		sim2.step(_idle())
		still.observe(sim2.players, sim2.tick_count, 1.0)
	Runner.T.eq(still.dust.size(), 0, "standing still kicks none")
	var calm := PlayerPolish.new()
	var sim3 := _sim()
	for _k in 40:
		sim3.step(inp)
		calm.observe(sim3.players, sim3.tick_count, 0.0)
	Runner.T.eq(calm.dust.size(), 0, "reduce motion: no dust")


func test_reticle_ident_hurt_downed_shapes() -> void:
	var segs := PlayerPolish.reticle_segments(Color.WHITE, Color.GREEN, 0.0)
	var dark := 0
	for s in segs:
		if s["col"].r == 0.0:
			dark += 1
	Runner.T.ok(dark >= 5, "reticle ticks carry dark keylines")
	Runner.T.eq(PlayerPolish.ident_pips(0, Color.GREEN).size(), 1, "P1 one pip")
	Runner.T.eq(PlayerPolish.ident_pips(1, Color.GOLD).size(), 2, "P2 two pips")
	Runner.T.ok(PlayerPolish.hurt_look(0, 1.0)["ring"].a > PlayerPolish.hurt_look(10, 1.0)["ring"].a, "hurt ring fades")
	Runner.T.ok(PlayerPolish.hurt_look(0, 0.0).is_empty(), "no hurt flash with flashes off")
	Runner.T.eq(PlayerPolish.downed_marker(Color.GREEN, 0.3, true)["segs"].size(), 4, "downed cross is two keylined strokes")


func test_wired_through_real_main() -> void:
	var src := FileAccess.get_file_as_string("res://src/main.gd")
	var body := src.substr(src.find("func _draw_players()"))
	body = body.substr(0, body.find("\nfunc _coin_trail"))
	for needle in ["_polish.observe(", "_polish.draw_ground(", "_polish.draw_flash(",
			"PlayerPolish.reticle_segments(", "PlayerPolish.downed_marker(", "PlayerPolish.hurt_look(", "PlayerPolish.ident_pips("]:
		Runner.T.ok(body.contains(needle), "_draw_players calls " + needle)
	var m := Main.new()
	Runner.T.ok(m.get("_polish") is PlayerPolish, "main holds a PlayerPolish")
	m.free()
