extends RefCounted
## The determinism spike (P0 §G1). Two fresh sims fed identical scripted
## inputs must produce bit-identical checksums at every sample point — and
## those checksums must equal the committed GOLDEN values on every platform
## and architecture. CI runs this same test on x86_64 Linux and Apple Silicon
## (M-series arm64) macOS runners; agreement is the Mac M4 compatibility proof.

const Runner := preload("res://tests/run_tests.gd")

const TICKS := 3600           # 60 seconds of 2P combat
const SAMPLE_EVERY := 600     # checksum every 10 seconds
const SEED := 0xDEADBEEF

## Golden checksums recorded on first green run (Linux x86_64, Godot 4.6.3;
## re-verified unchanged on Godot 4.7 and Apple Silicon arm64).
## If these ever change, determinism broke — do NOT re-record without
## understanding why. An empty array prints values to record.
## RE-RECORDED at the P3 session boundary (2026-07-08): the hurt pipeline
## (Flak Vest + post-respawn mercy window), priced pickups, the final gate
## ending world streaming, and Endless War state all legitimately alter the
## state stream. P2 goldens retired with this note, per the plan's
## "behavior changes only at phase boundaries" policy.
## RE-RECORDED for the P3.5 fairness pass (2026-07-10): roll input buffering
## (new roll_buf player state — the torture script's rolls now land more
## often) and the frogman surfacing telegraph (new surface_ticks enemy state,
## rooted+harmless wind-up) legitimately alter the state stream. Both fields
## joined checksum(). View-event additions in the same pass are checksum-
## excluded by design and did not move these values.
## RE-RECORDED (2026-07-11): elites became ranged skirmishers (standoff +
## telegraphed wind-up shot; new fire_cd/windup enemy state in checksum) —
## design-review iteration 1 behavior change.
## RE-RECORDED (2026-07-11, design-loop iter 4 balance): revive-cost
## multiplier soft-capped at 3 deaths (death-spiral guard) — only samples
## 2-5 moved (the cap bites only once the 2P torture exceeds 3 deaths).
## Same pass: airstrike screen-clear mints no coin + endless spawn scaling,
## both campaign-torture-inert, so they did NOT move these values.
const GOLDEN: Array[int] = [
	8340780119376351956,
	6345185127394226400,
	8964335448652624686,
	565685721398068558,
	6727277923065113226,
	4871685255518214231,
]


static func scripted_input(tick: int, player: int) -> SimInput:
	## Deterministic input torture script: strafes, aim sweeps, fire bursts,
	## grenade tosses, and revive mashing, phase-shifted per player.
	var inp := SimInput.new()
	var t := tick + player * 37
	inp.move_x = [-256, -128, 0, 128, 256][(t / 40) % 5]
	inp.move_y = -256 if (t / 60) % 3 != 2 else 128
	inp.aim_x = [-256, 0, 256, 0][(t / 25) % 4]
	inp.aim_y = [-256, -256, 0, 256][(t / 31) % 4]
	inp.fire = (t % 3) != 0
	inp.grenade = (t % 97) == 0
	inp.revive = (t % 53) == 0
	inp.roll = (t % 41) == 0
	inp.interact = (t % 67) < 2
	return inp


## Endless golden: the campaign torture never enters _step_waves, so the
## wave-mutator + spotter-observer state has no cross-arch golden without this.
## RE-RECORDED (2026-07-12): endless waves 3+ now spawn grenadier/sniper
## ranged archetypes — only samples 3-5 moved (waves 1-2 have no specials);
## campaign golden is bit-identical (the new kinds are endless-only, and they
## reuse the already-hashed fire_cd/windup enemy fields).
const ENDLESS_GOLDEN: Array[int] = [
	586311806716809943,
	5628042505202006876,
	3362890099836553207,
	1577991378673560792,
	5451074008481912581,
	1378020686060569927,
]


func _run_sim(mode := "campaign") -> Array[int]:
	var sim := SimWorld.new(SEED, 2, mode)
	var samples: Array[int] = []
	for tick in TICKS:
		sim.step([scripted_input(tick, 0), scripted_input(tick, 1)])
		if (tick + 1) % SAMPLE_EVERY == 0:
			samples.append(sim.checksum())
	return samples


func test_replay_determinism() -> void:
	var run_a := _run_sim()
	var run_b := _run_sim()
	Runner.T.eq(run_a.size(), TICKS / SAMPLE_EVERY, "expected sample count")
	for i in run_a.size():
		Runner.T.eq(run_a[i], run_b[i], "run A/B checksum diverged at sample %d" % i)
	if GOLDEN.is_empty():
		print("      GOLDEN CHECKSUMS (record these): ", run_a)
	else:
		Runner.T.eq(run_a.size(), GOLDEN.size(), "golden sample count")
		for i in mini(run_a.size(), GOLDEN.size()):
			Runner.T.eq(run_a[i], GOLDEN[i],
				"cross-platform golden checksum mismatch at sample %d — determinism broke" % i)


func test_endless_replay_determinism() -> void:
	# Exercises _step_waves: wave mutators (blitz/elite-guard/spotter) and the
	# spotter Observer's barrage — none of which the campaign torture reaches.
	var run_a := _run_sim("endless")
	var run_b := _run_sim("endless")
	for i in run_a.size():
		Runner.T.eq(run_a[i], run_b[i], "endless run A/B diverged at sample %d" % i)
	if ENDLESS_GOLDEN.is_empty():
		print("      ENDLESS GOLDEN (record these): ", run_a)
	else:
		for i in mini(run_a.size(), ENDLESS_GOLDEN.size()):
			Runner.T.eq(run_a[i], ENDLESS_GOLDEN[i],
				"endless golden mismatch at sample %d — determinism broke" % i)


func test_colossus_replay_determinism() -> void:
	# Force-engage the finale so the core-window cycle + bullet core-chip get a
	# determinism proof (the 60s torture never reaches gate 5).
	var a := _colossus_run()
	var b := _colossus_run()
	Runner.T.eq(a, b, "colossus run A/B checksum diverged")


func _colossus_run() -> int:
	var sim := SimWorld.new(SEED, 1)
	var g := {"y": sim.camera_top + 40 * Fixed.ONE, "open": false, "b1": {}, "b2": {},
		"boss": {}, "final": true}
	sim.gates.append(g)
	for tick in 600:
		sim.step([scripted_input(tick, 0)])
	return sim.checksum()


func test_checksum_is_idempotent() -> void:
	var sim := SimWorld.new(42, 1)
	for tick in 120:
		sim.step([scripted_input(tick, 0)])
	var c1 := sim.checksum()
	var c2 := sim.checksum()
	Runner.T.eq(c1, c2, "checksum must not mutate sim state")
