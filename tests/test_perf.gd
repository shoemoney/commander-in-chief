extends RefCounted
## Frame-budget gate (CI/perf item): SimWorld.step() must stay well inside a
## 4 ms/tick budget so the view layer keeps headroom in the 16.6 ms/60 fps
## frame (this only measures the sim -- render cost is on top). Reuses the
## determinism torture script so the measured cost is worst-case input
## density, not an idle best case.
##
## LIVE TICKS, NOT WALL TICKS. SimWorld.step() early-returns on the second line
## once `wiped` latches, so a wiped tick costs one branch. Measured 2026-08-02:
## the endless torture wiped at tick 1392 and the gate then "stepped" a frozen
## sim for the remaining 61% of the run, reporting 39 us/tick when the live cost
## was 102 -- a 2.6x dilution that got GREENER the earlier a balance change
## killed the torture. Two guards now: `god_mode` (the debug auto-restore, which
## clears the wipe latch on its 60-tick heartbeat from inside step(), so its own
## cost stays inside the measurement) keeps the run escalating into the deep
## waves where the O(roster) collision loops actually cost something, and the
## live-tick assertion below fails outright if a future change re-hollows the
## gate. The average divides by live ticks for the same reason.

const Runner := preload("res://tests/run_tests.gd")
const Determinism := preload("res://tests/test_determinism.gd")

const TICKS := 3600                     # 60 s of 2P combat, same load as the golden torture
const AVG_BUDGET_USEC := 4000.0         # 4 ms/tick average -- the plan's stated gate
const MAX_TICK_BUDGET_USEC := 20000.0   # generous ceiling for a single worst-tick spike (CI jitter, first alloc)


func test_campaign_tick_budget() -> void:
	_assert_budget("campaign")


func test_endless_tick_budget() -> void:
	_assert_budget("endless")


func test_boss_rush_tick_budget() -> void:
	# The only leg that measures _step_boss/_step_colossus: _setup_boss_rush pre-authors
	# every gunship gate plus the Colossus finale, so the whole boss stack is under load
	# from tick 0 instead of sitting past the ~2 gates 3600 campaign ticks can reach.
	_assert_budget("boss_rush")


func _assert_budget(mode: String) -> void:
	var sim := SimWorld.new(0xDEADBEEF, 2, mode)
	sim.god_mode = true   # see the LIVE-TICKS note above; keeps the torture escalating instead of freezing
	var worst_usec := 0
	var live := 0
	var t0 := Time.get_ticks_usec()
	for tick in TICKS:
		if not sim.wiped:
			live += 1
		var tick_t0 := Time.get_ticks_usec()
		sim.step([Determinism.scripted_input(tick, 0), Determinism.scripted_input(tick, 1)])
		worst_usec = maxi(worst_usec, Time.get_ticks_usec() - tick_t0)
	var total_usec := Time.get_ticks_usec() - t0
	print("PROBE %s: live=%d/%d wave=%d enemies=%d sandbags=%d avg_all=%.1f avg_live=%.1f worst=%d" % [mode, live, TICKS, sim.wave, sim.enemies.size(), sim.sandbags.size(), float(total_usec) / TICKS, float(total_usec) / maxi(live, 1), worst_usec])
	Runner.T.ok(live >= TICKS * 9 / 10,
		"%s: only %d of %d ticks were live — the budget measured a frozen sim (step() early-returns while wiped)" % [mode, live, TICKS])
	var avg_usec := float(total_usec) / maxi(live, 1)
	Runner.T.ok(avg_usec < AVG_BUDGET_USEC,
		"%s: avg tick cost %.1f us exceeds %.1f us budget" % [mode, avg_usec, AVG_BUDGET_USEC])
	Runner.T.ok(worst_usec < MAX_TICK_BUDGET_USEC,
		"%s: worst tick cost %d us exceeds %.1f us spike ceiling" % [mode, worst_usec, MAX_TICK_BUDGET_USEC])
