extends RefCounted
## Frame-budget gate (CI/perf item): SimWorld.step() must stay well inside a
## 4 ms/tick budget so the view layer keeps headroom in the 16.6 ms/60 fps
## frame (this only measures the sim -- render cost is on top). Reuses the
## determinism torture script so the measured cost is worst-case input
## density, not an idle best case.

const Runner := preload("res://tests/run_tests.gd")
const Determinism := preload("res://tests/test_determinism.gd")

const TICKS := 3600                     # 60 s of 2P combat, same load as the golden torture
const AVG_BUDGET_USEC := 4000.0         # 4 ms/tick average -- the plan's stated gate
const MAX_TICK_BUDGET_USEC := 20000.0   # generous ceiling for a single worst-tick spike (CI jitter, first alloc)


func test_campaign_tick_budget() -> void:
	_assert_budget("campaign")


func test_endless_tick_budget() -> void:
	_assert_budget("endless")


func _assert_budget(mode: String) -> void:
	var sim := SimWorld.new(0xDEADBEEF, 2, mode)
	var worst_usec := 0
	var t0 := Time.get_ticks_usec()
	for tick in TICKS:
		var tick_t0 := Time.get_ticks_usec()
		sim.step([Determinism.scripted_input(tick, 0), Determinism.scripted_input(tick, 1)])
		worst_usec = maxi(worst_usec, Time.get_ticks_usec() - tick_t0)
	var total_usec := Time.get_ticks_usec() - t0
	var avg_usec := float(total_usec) / TICKS
	Runner.T.ok(avg_usec < AVG_BUDGET_USEC,
		"%s: avg tick cost %.1f us exceeds %.1f us budget" % [mode, avg_usec, AVG_BUDGET_USEC])
	Runner.T.ok(worst_usec < MAX_TICK_BUDGET_USEC,
		"%s: worst tick cost %d us exceeds %.1f us spike ceiling" % [mode, worst_usec, MAX_TICK_BUDGET_USEC])
