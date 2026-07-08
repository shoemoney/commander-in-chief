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

## Golden checksums recorded on first green run (Linux x86_64, Godot 4.6.3).
## If these ever change, determinism broke — do NOT re-record without
## understanding why. An empty array prints values to record.
## RE-RECORDED at the P1 phase boundary (2026-07-08): the sim legitimately
## changed — dodge roll, tank vehicle, Mortar Observer strikes, and zone
## gates all alter the state stream and the input script now exercises
## roll/interact. P0 goldens are retired with this note, per the plan's
## "upgrades/behavior changes only at phase boundaries" policy.
const GOLDEN: Array[int] = [
	3310278622838979121,
	7282408627998066470,
	3523138520321241396,
	4872790277431049417,
	842717901354625989,
	8330232999275283171,
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
