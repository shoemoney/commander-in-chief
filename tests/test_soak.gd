extends RefCounted
## Long-run stability gate (CI/perf item): steps the sim far past any real
## match to catch unbounded array growth -- there are no engine objects in
## src/sim, so "leak" here means an entity array that never gets swept.
## Runs at a CI-fast default on every PR; the nightly soak workflow overrides
## SOAK_TICKS=648000 (3 hours at 60 Hz) for the real long-haul gate.
## NOTE: array-size ceiling is a heuristic, not an RSS profiler -- upgrade
## to an actual memory sample (OS.get_static_memory_usage) if one ever slips
## through this and a real leak needs chasing.

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
	for tick in ticks:
		sim.step([Determinism.scripted_input(tick, 0), Determinism.scripted_input(tick, 1)])
		if (tick + 1) % CHECK_EVERY == 0:
			_assert_bounded(sim, tick + 1)
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
