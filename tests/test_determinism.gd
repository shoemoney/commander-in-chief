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
## RE-RECORDED (2026-07-12, iter 24): grenade/shell explosions now ignite
## tanks in radius (emergent: torch a tank to deny it, or ignite-and-ride the
## bail-boost kamikaze). Only samples 3-5 moved (the torture reaches streamed
## tanks late and its grenade tosses now catch them). Endless golden unaffected.
## RE-RECORDED (2026-07-12, design-loop iter 2 sim/balance): campaign elite ratio now
## tightens with each opened gate (every 8th → 3rd by gate 5); a post-checkpoint spawn
## grace holds the field spawner off so "GATE SECURED" isn't stepped on; and a SCORE-ONLY
## kill-streak bonus (5/10/20 tiers) lands. New checksummed state: _spawn_grace,
## kill_streak, kill_streak_timer, and the sniper's paint-locked aim (aim_lx/aim_ly).
## RE-RECORDED (2026-07-12, iter 8): new `wiped` end-state joins checksum (0 in campaign, so
## all campaign samples shift by the added field but behavior is identical). See ENDLESS note.
## RE-RECORDED (2026-07-12, design-loop iter 5): landmines — a new deterministic field-hazard
## entity (mines[] w/ x/y/armed, hashed) that streams into the campaign world and detonates via
## _explode() when any grounded unit steps on it. All 6 campaign samples moved (the torture walks
## the minefield); endless moved too (the new mines.size() hash block feeds even when empty).
## RE-RECORDED (2026-07-12, iter 9 reward&fairness): Flawless-Gate bonus (deaths_since_gate joins
## checksum; +50 chest/+2000 score on a deathless checkpoint), streak-20 grants a speed boost,
## and a bail-out mercy window. Campaign torture opens gates flawlessly → all samples moved.
## RE-RECORDED (2026-07-12, iter 10): airstrike now telegraphs (pending_airstrike joins checksum;
## the wipe resolves after STRIKE_TELEGRAPH_TICKS instead of instantly) + a guaranteed free cache
## spawns past every gate open. Campaign torture opens gates → cache pickups + rng shift → all moved.
## RE-RECORDED (2026-07-12, iter 14 economy&bounty): ~1-in-7 elites are now marked BOUNTY targets
## (new checksummed enemy field `marked`; triple coin+score) and a grenade blast catching 3+ pays a
## frag bonus. The marked roll consumes rng on every elite spawn → all samples moved.
## RE-RECORDED (2026-07-13, PR#1 reconcile merge): the iter17-32 quality-loop branch merged
## onto main's iter17-25 loop. The reconciled sim is bit-identical to main's canonical core on
## this torture — the branch's roll-iframe fix / pickup + strikeable refactors don't perturb the
## sampled trajectory (the new test_combat roll test exercises the closed gap directly), so these
## match main's committed campaign checksums exactly.
## RE-RECORDED (2026-07-12, iter 26 power-ups, post-merge): Piercing Rounds — a rare elite-drop
## capsule (new checksummed player field pierce_ticks; kind-4 pickup) that lets bullets punch
## through a kill. The 1-in-12 drop roll shifts rng on every elite kill → all samples moved.
## RE-RECORDED (2026-07-12, iter 27): Spread Shot / Trench Gun — a 2nd power-up capsule (kind 5,
## new checksummed player field spread_ticks) firing a 3-bullet fan; the elite drop table now
## rolls a rare capsule (pierce OR spread), shifting rng on every elite kill → all samples moved.
const GOLDEN: Array[int] = [
	1942392792714788905,
	5254693104462641548,
	1869508768180451128,
	2957909663780844898,
	1766040305575453794,
	2825294671139700342,
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
## RE-RECORDED again (bug fix): grenadier lobs (telegraphed strikes) now
## detonate in endless — strike resolution was extracted from _step_observer
## (which endless only runs when an observer is present) into _resolve_strikes
## called every tick. Only sample 4 moved; campaign order/behavior identical.
## RE-RECORDED (iter 26): endless spawn roll gained the shield archetype
## (front-arc bullet block, flank/grenade kill) — the 5-way roll shifts rng
## consumption + spawns shields; samples 3-5 moved, campaign untouched.
## RE-RECORDED (2026-07-12, design-loop iter 2): the score-only kill-streak bonus plus the
## new checksummed scalars (kill_streak/kill_streak_timer/_spawn_grace) and the sniper's
## paint-locked aim vector shift the endless stream too — all 6 samples moved.
## RE-RECORDED (2026-07-12, iter 5): the new mines[] checksum block (size 0 in endless) shifts
## the endless hash even though mines never stream outside campaign.
## RE-RECORDED (2026-07-12, iter 6 agency&cover): empty-clip bash (dry MG becomes a point-blank
## melee kill), bunkers now block ENEMY bullets too, and Last-Stand doubles score. Only endless
## samples 1-5 moved (the endless torture depletes ammo + fields ranged shooters near bunkers);
## CAMPAIGN golden is bit-identical (the torture never runs dry near an enemy, and never reaches
## last_stand). Sample 0 (t=600) unchanged — too early for any of the three to bite.
## RE-RECORDED (2026-07-12, iter 8): endless now has a WIPED end-state — an all-down party with
## no rescue ends the run (fixes "endless can't be lost / never records"). The 2P torture wipes
## at ~tick 1413 (wave 2), so samples 2-5 sample a frozen post-wipe sim. Because the torture no
## longer organically reaches wave 3+, the ranged-specialist steppers get their own determinism
## proof in test_endless_specials_determinism (force-staged, A==B) below.
## RE-RECORDED (2026-07-12, iter 9): deaths_since_gate joins checksum (0 in endless — no gates)
## plus the streak-20 boost + bail mercy window shift the endless stream; all samples moved.
## RE-RECORDED (2026-07-12, iter 10): pending_airstrike joins checksum (shifts the endless hash;
## the gate cache is campaign-only so endless moves only from the new field).
## RE-RECORDED (2026-07-12, iter 14): marked-elite roll + bounty/frag scoring shift the endless
## stream too (elites spawn in the endless torture before it wipes at wave 2).
## RE-RECORDED (2026-07-13, PR#1 reconcile merge): see GOLDEN note. Endless samples recomputed
## from the merged sim (deaths_this_wave + wave mutators + sapper/ghillie enemies all live) and
## match main's committed endless checksums exactly.
const ENDLESS_GOLDEN: Array[int] = [
	8681953085351081569,
	6059987203174684048,
	3174963771928234834,
	1740422521085536138,
	2445779400911443234,
	7263092349450529370,
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


func test_endless_specials_determinism() -> void:
	# The endless wipe now ends the 2P torture at ~wave 2, so it no longer
	# organically reaches the wave-3+ ranged archetypes. Prove those (incl. the
	# sniper's paint-locked aim) step deterministically by force-staging them —
	# A==B, mirroring the colossus proof.
	var a := _specials_run()
	var b := _specials_run()
	Runner.T.eq(a, b, "endless ranged-specials run A/B checksum diverged")


func _specials_run() -> int:
	var sim := SimWorld.new(SEED, 1, "endless")
	sim._spawn_special(200 * Fixed.ONE, sim.camera_top - 60 * Fixed.ONE, "grenadier")
	sim._spawn_special(440 * Fixed.ONE, sim.camera_top - 60 * Fixed.ONE, "sniper")
	sim._spawn_special(320 * Fixed.ONE, sim.camera_top - 60 * Fixed.ONE, "shield")
	for tick in 400:
		sim.step([scripted_input(tick, 0)])
	return sim.checksum()


func test_endless_boss_determinism() -> void:
	# The wave-5 miniboss never spawns in the wiping 2P torture, so prove its
	# (gunship-schema) stepper is deterministic on its own — A==B.
	var a := _boss_run()
	var b := _boss_run()
	Runner.T.eq(a, b, "endless miniboss run A/B checksum diverged")


func _boss_run() -> int:
	var sim := SimWorld.new(SEED, 1, "endless")
	sim.wave = 4
	sim._start_wave()
	for tick in 300:
		sim.step([scripted_input(tick, 0)])
	return sim.checksum()


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
