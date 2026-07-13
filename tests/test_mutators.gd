extends RefCounted
## Endless War wave mutators: Blitz (fast/pure), Elite-Guard (all-elite), and
## Spotter (Observer at wave start) — plus the wave-clear -> intermission -> next
## wave progression they ride on.

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
