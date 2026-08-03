extends RefCounted
## Long-run stability gate (CI/perf item): steps the sim far past any real
## match to catch unbounded array growth -- there are no engine objects in
## src/sim, so "leak" here means an entity array that never gets swept.
## Runs at a CI-fast default on every PR; the nightly soak workflow overrides
## SOAK_TICKS=648000 (3 hours at 60 Hz) for the real long-haul gate.
## NOTE: array-size ceiling is a heuristic, not an RSS profiler -- upgrade
## to an actual memory sample (OS.get_static_memory_usage) if one ever slips
## through this and a real leak needs chasing.
##
## LIVE RUN, NOT WALL RUN. SimWorld.step() early-returns once `wiped` latches,
## and FROZEN ARRAYS ARE TRIVIALLY BOUNDED -- a torture that dies at tick 1400
## turns this into a leak gate that exercises 4% of its ticks (0.06% on the
## nightly 648k run) and still reports PASS. `god_mode` keeps the run alive
## (its auto-restore clears the latch every 60 ticks) and the live-tick
## assertion below goes red if that ever stops working.

const Runner := preload("res://tests/run_tests.gd")
const Determinism := preload("res://tests/test_determinism.gd")

const DEFAULT_TICKS := 36000   # 10 minutes sim-time -- fast enough for every PR
const CHECK_EVERY := 3600
const MAX_ARRAY_SIZE := 4000   # generous; no entity kind legitimately grows this large


func test_long_run_arrays_stay_bounded() -> void:
	var ticks := DEFAULT_TICKS
	var override := OS.get_environment("SOAK_TICKS")
	if not override.is_empty():
		ticks = int(override)
	var sim := SimWorld.new(0xC0FFEE, 2, "endless")
	# See the LIVE-RUN note in the header: without this the endless torture wipes early
	# and every remaining step() is a one-branch early return over frozen arrays.
	sim.god_mode = true
	var live := 0
	for tick in ticks:
		if not sim.wiped:
			live += 1
		sim.step([Determinism.scripted_input(tick, 0), Determinism.scripted_input(tick, 1)])
		if (tick + 1) % CHECK_EVERY == 0:
			_assert_bounded(sim, tick + 1)
	print("SOAK: %d/%d live ticks, wave %d, %d enemies / %d sandbags at the end" % [live, ticks, sim.wave, sim.enemies.size(), sim.sandbags.size()])
	Runner.T.ok(live >= ticks * 9 / 10,
		"only %d of %d soak ticks were live — frozen arrays are trivially bounded, so the leak gate proved nothing" % [live, ticks])
	sim.checksum()   # must still hash cleanly after the full run


func _assert_bounded(sim: SimWorld, tick: int) -> void:
	var arrays := {
		"players": sim.players, "bullets": sim.bullets, "grenades": sim.grenades,
		"enemies": sim.enemies, "bunkers": sim.bunkers, "pickups": sim.pickups,
		"tanks": sim.tanks, "gates": sim.gates, "strikes": sim.strikes,
		"waters": sim.waters, "enemy_bullets": sim.enemy_bullets, "mines": sim.mines,
		"sandbags": sim.sandbags, "rocks": sim.rocks, "barrels": sim.barrels,
		"vents": sim.vents,
	}
	for field in arrays:
		Runner.T.ok(arrays[field].size() < MAX_ARRAY_SIZE,
			"tick %d: sim.%s grew to %d (possible leak)" % [tick, field, arrays[field].size()])
