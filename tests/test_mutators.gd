extends RefCounted
## Endless War wave mutators: Blitz (fast/pure), Elite-Guard (all-elite),
## Spotter (Observer at wave start), Payday (double coin), Frenzy (+40% speed),
## and Night-Ops (view-only, must stay sim-inert) — plus the wave-clear ->
## intermission -> next wave progression they ride on.

const Runner := preload("res://tests/run_tests.gd")


func _idle() -> SimInput:
	return SimInput.new()


func test_blitz_halves_spawn_interval_and_bars_specials() -> void:
	var sim := SimWorld.new(11, 1, "endless")
	sim.wave = 3
	sim._start_wave()   # -> wave 4
	sim.wave_mod = 1    # force Blitz
	sim.wave_pending = 20
	sim.enemies.clear()
	sim.step([_idle()])   # wave_spawn_cd starts at 1, so this tick spawns immediately
	var normal_interval: int = maxi(8, SimWorld.WAVE_SPAWN_INTERVAL_TICKS - sim.wave)
	var expected_blitz: int = maxi(4, normal_interval / 2)
	Runner.T.eq(sim.wave_spawn_cd, expected_blitz, "blitz sets half the normal spawn interval")
	Runner.T.ok(expected_blitz < normal_interval, "blitz interval is strictly faster than normal")
	# Drain the rest of the budget: never a grenadier/sniper/shield in a Blitz wave.
	for i in 400:
		if sim.wave_pending <= 0:
			break
		sim.step([_idle()])
	var specials := 0
	for e in sim.enemies:
		if e["kind"] in ["grenadier", "sniper", "shield"]:
			specials += 1
	Runner.T.eq(specials, 0, "blitz wave spawns only rushers/elites, never ranged specials")


func test_elite_guard_forces_every_spawn_elite() -> void:
	var sim := SimWorld.new(23, 1, "endless")
	sim.wave = 3
	sim._start_wave()   # -> wave 4
	sim.wave_mod = 2    # force Elite-Guard
	sim.wave_pending = 20
	sim.enemies.clear()
	for i in 400:
		if sim.wave_pending <= 0:
			break
		sim.step([_idle()])
	Runner.T.ok(sim.enemies.size() > 0, "elite-guard wave actually spawned enemies")
	var non_elite := 0
	for e in sim.enemies:
		if not e["elite"]:
			non_elite += 1
	Runner.T.eq(non_elite, 0, "elite-guard wave spawns nothing but elites")


func test_spotter_wave_seeds_observer_at_start() -> void:
	var sim := SimWorld.new(5, 1, "endless")
	sim.wave = 2   # wave <= 2 never rolls a mutator, so land on 3 first
	sim._start_wave()   # -> wave 3, first wave eligible to roll Spotter
	var guard := 0
	while sim.wave_mod != 3 and guard < 200:
		sim._start_wave()
		guard += 1
	Runner.T.ok(sim.wave_mod == 3, "found a natural Spotter roll from _start_wave")
	Runner.T.ok(not sim.observer.is_empty(), "Spotter wave seeds an Observer at wave start")
	Runner.T.eq(sim.stall_ticks, 0, "the Observer came from the mutator, not the stall pressure path")


func test_payday_doubles_bounty_coin() -> void:
	# Baseline: a plain rusher kill with no mutator mints COIN_RUSHER.
	var base := SimWorld.new(7, 1, "endless")
	base._spawn_enemy(200 * 65536, 200 * 65536, false)
	var wc0: int = base.war_chest
	base._kill_enemy(base.enemies[0])
	var gain_normal: int = base.war_chest - wc0
	Runner.T.ok(gain_normal > 0, "a rusher kill mints some coin")
	# PAYDAY (wave_mod 4): the identical kill pays exactly double.
	var sim := SimWorld.new(7, 1, "endless")
	sim._spawn_enemy(200 * 65536, 200 * 65536, false)
	sim.wave_mod = 4
	var wc1: int = sim.war_chest
	sim._kill_enemy(sim.enemies[0])
	Runner.T.eq(sim.war_chest - wc1, gain_normal * 2, "PAYDAY doubles the bounty coin")


func test_frenzy_speeds_the_swarm() -> void:
	# Two identical sims, one FRENZY; measure how far the lone rusher advances in
	# 10 ticks. The +40% speed must show up as a strictly-larger advance.
	var normal := SimWorld.new(9, 1, "endless")
	normal.wave = 4
	normal.wave_pending = 0
	normal.enemies.clear()
	normal._spawn_enemy(200 * 65536, normal.camera_top + 30 * 65536, false)
	var ny0: int = normal.enemies[0]["y"]
	for i in 10:
		normal.step([SimInput.new()])
	var ndisp: int = absi(normal.enemies[0]["y"] - ny0)

	var frenzy := SimWorld.new(9, 1, "endless")
	frenzy.wave = 4
	frenzy.wave_pending = 0
	frenzy.enemies.clear()
	frenzy._spawn_enemy(200 * 65536, frenzy.camera_top + 30 * 65536, false)
	frenzy.wave_mod = 6
	var fy0: int = frenzy.enemies[0]["y"]
	for i in 10:
		frenzy.step([SimInput.new()])
	var fdisp: int = absi(frenzy.enemies[0]["y"] - fy0)

	Runner.T.ok(ndisp > 0, "the baseline rusher actually advanced")
	Runner.T.ok(fdisp > ndisp, "FRENZY advances the swarm farther per tick")
	Runner.T.ok(fdisp * 10 >= ndisp * 13, "FRENZY is at least ~1.3x the normal advance")


func test_night_ops_is_sim_inert() -> void:
	# NIGHT OPS (5) tightens VISION only — it must not touch spawn/coin/speed, or
	# it would break the 'view-only, golden-safe' contract it was built on.
	var plain := SimWorld.new(13, 1, "endless")
	plain.wave = 4
	plain.wave_pending = 0
	plain.enemies.clear()
	plain._spawn_enemy(200 * 65536, plain.camera_top + 30 * 65536, false)
	for i in 10:
		plain.step([SimInput.new()])

	var night := SimWorld.new(13, 1, "endless")
	night.wave = 4
	night.wave_pending = 0
	night.enemies.clear()
	night._spawn_enemy(200 * 65536, night.camera_top + 30 * 65536, false)
	night.wave_mod = 5
	for i in 10:
		night.step([SimInput.new()])

	Runner.T.eq(night.enemies[0]["y"], plain.enemies[0]["y"], "NIGHT OPS doesn't change enemy advance")
	Runner.T.eq(night.enemies[0]["x"], plain.enemies[0]["x"], "NIGHT OPS doesn't change enemy pathing")
	Runner.T.eq(night.war_chest, plain.war_chest, "NIGHT OPS doesn't change the economy")


func test_wave_clear_advances_wave_and_opens_shop() -> void:
	var sim := SimWorld.new(31, 1, "endless")
	sim.wave = 3
	sim._start_wave()   # -> wave 4 (not a miniboss wave)
	var wave_before: int = sim.wave
	sim.wave_pending = 0
	sim.enemies.clear()
	sim.step([_idle()])
	Runner.T.ok(sim.intermission_ticks > 0, "clearing the wave opens the intermission")
	Runner.T.eq(sim.pickups.size(), 4, "shop stocked four crates")
	Runner.T.eq(sim.wave, wave_before, "wave number itself hasn't advanced yet")
	for i in SimWorld.WAVE_INTERMISSION_TICKS + 2:
		sim.step([_idle()])
		if sim.wave > wave_before:
			break
	Runner.T.eq(sim.wave, wave_before + 1, "intermission elapsing starts the next wave")
