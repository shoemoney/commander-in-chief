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
const GOLDEN: Array[int] = [
	8340780119376351956,
	6345185127394226400,
	447115406617573745,
	753412334351876725,
	7738070117799955651,
	586976185476678933,
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


func _run_sim() -> Array[int]:
	var sim := SimWorld.new(SEED, 2)
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


func test_checksum_is_idempotent() -> void:
	var sim := SimWorld.new(42, 1)
	for tick in 120:
		sim.step([scripted_input(tick, 0)])
	var c1 := sim.checksum()
	var c2 := sim.checksum()
	Runner.T.eq(c1, c2, "checksum must not mutate sim state")
