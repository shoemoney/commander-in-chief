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
## RE-RECORDED (2026-07-16, sim gameplay backlog): four new capsules — Rend (kind 6, bullets punch
## the shield block), Claymore (kind 7, INTERACT plants a mine), Smoke (kind 8, breaks all enemy
## targeting), Flashbang (kind 9, field-wide stun) — plus the endless Recon Drone spotter. New
## checksummed state: player rend_ticks/smoke_ticks/claymores + world flash_ticks; the rare-drop
## table widens to six capsules (rng values shift on every elite kill) → all samples moved.
## VERIFIED UNCHANGED (2026-07-16, design-loop iter1 — lens-audit batch on the new mechanics):
## smoke now denies only ranged FIRE-COMMITS (the _nearest_alive_player guard froze all pathing —
## a free-kill printer that even halted the colossus finale), claymore plants ALONG the aim, the
## rare-capsule table is weighted 2:2:1:1:1:1 with Rend gated until shields can spawn, the drone
## tightens to 24t paint / 100t cd + wave-5 gate + marked bounty, flashbang re-arms frozen
## windups, ghillies force-reveal when they alone hold a wave open, and the observer defuses only
## his own obs-tagged strikes. Both goldens came back BYTE-IDENTICAL: the torture never rolls a
## rare capsule (same rng draw count either way), the endless torture wipes at wave 2 before any
## special spawns, and no torture player ever holds smoke/claymores — so every changed path is
## golden-inert here and proven instead by the direct tests in test_mechanics/test_observer.
## RE-RECORDED (2026-07-16, grafted design-loop iter 29 — Explosive Fuel Barrels): a new
## checksummed barrels[] block joins checksum(). Campaign torture streams + chains barrels
## (all samples moved); endless spawns none, but the unconditional feed.call(barrels.size()=0)
## structural add shifts every endless sample too.
## RE-RECORDED (2026-07-16, grafted design-loop iter 25 — Triple Shot): a new hashed player
## field int(p["triple"]) joins checksum() (unconditional per-player -> all samples shift), and the
## elite-drop roll widened 4+range_i(0,1) -> (0,2) to add the kind-6 capsule (shifts rng on drops).
## RE-RECORDED (2026-07-16, PR#9 reconcile merge): origin/main's grafted iters (Triple Shot kind 6
## w/ hashed p["triple"], Explosive Fuel Barrels barrels[] block, MG-nest emplacement) merged with
## this branch's capsule stack — the four tools renumber 7=Rend/8=Claymore/9=Smoke/10=Flashbang,
## the rare table becomes a 10-entry weighted pick [4,4,5,5,6,6,7,8,9,10], and the endless special
## roll widens 0..7 → 0..8 to seat drone AND mg_nest. Union sim = new state stream in both modes.
## RE-RECORDED (2026-07-16, PR#9 final merge-to-main): union of this branch's capsule/drone stack
## with main's PR#10 P3b sim batch (dodge-along-aim, grenade edge, wheel-only airstrike, boss HP
## scaling, score-on-buy, earlier specials) — both parents had re-recorded independently. The
## campaign samples match the previous reconcile exactly (every P3b campaign path is torture-inert:
## stationary panic-roll needs a neutral stick, buys/specials/boss-HP need progress the 60s torture
## never reaches); only the endless stream moved.
## VERIFIED UNCHANGED (2026-07-16, backlog items 6-7 — Technical raider + Downed Pilot ransom):
## the endless special roll widens 0..8 → 0..9 (slot 7 = technical) but the endless torture wipes
## before wave 3; the pilot spawns only on a gunship death the campaign torture never reaches; the
## wave-clear check now ignores pilots (reordered ahead of the ghillie anti-stall) in states the
## torture never enters. Proven instead by the three new direct tests in test_mechanics.
## RE-RECORDED (2026-07-16, PR#11 merge-to-main): union of main (capsule/drone stack + PR#10
## P3b batch + grafted Triple/Nest/Barrels) with pass2's P3 design changes (MG Nest hp armor +
## coin retier + aim re-acquire + streak/drop exclusion, barrels react to bullets/enemy-contact/
## fuse/coin-neutral, Triple+Spread 5-fan via SPREAD2, shop score parity). Both parents had
## re-recorded independently; new hashed fields e["hp"] and barrel fuse_ticks -> new stream.
## (Technical/pilot ride these values unchanged — still torture-inert on the union tree.)
## RE-RECORDED (2026-07-16, all-loops batch — 33-agent audit, 30 verified fixes): campaign ramp
## formula now actually reaches its advertised ceiling (interval 45-6*opened floors at 24, elite
## every 7-opened floors at 3, "by gate 4" — gate 5 only opens on Colossus death), dying broke
## auto-arms broke_timer at death (the endless wipe must not require a button press), self-revive
## is gated when a partner is alive, Rend drops unlock with the first shield sector (opened>=1),
## Clean Wave + avenge bounties scale with the same creep curves as their sinks, the endless
## miniboss bounty honors PAYDAY, near-miss board taps no longer arm claymores, and _dist_lte
## gains a byte-identical axis early-out. Campaign torture opens gates + dies broke -> all
## samples moved in both modes.
## RE-RECORDED (2026-07-17, mechanics-panel drain — Commendation tokens + Tank Hulk): the
## 9/9-vote score->power bridge adds hashed `tokens` right after war_chest (structural shift:
## every sample in BOTH modes moves even at 0), minted at the streak-20 surge the campaign
## torture reaches; and dead tanks now smolder as two-way bullet cover for HULK_TICKS
## (burn_ticks reused — no new field, but the torture torches tanks and its bullets/interacts
## now meet the hulk, so the trajectory itself moves). Same pass, PROVEN golden-inert and NOT
## part of this re-record: airburst, route fork, supply drop, broadcast tower, tank crew,
## sandbags (each verified byte-identical before this batch landed).
## RE-RECORDED (2026-07-17, level-panel cycle 1 — collidable rocks, 9/9 unanimous): natural
## hard cover now streams through sector 1 (rng-FREE Knuth-hash placement — the stream-rng
## sequence is untouched; the diff is the rocks themselves): they block boots, treads, enemy
## steps and bullets both ways inside the torture's first 1200px, so every campaign sample
## legitimately moves. ENDLESS_GOLDEN untouched (campaign-only stream + conditional feed).
## Same cycle, PROVEN inert and NOT part of this re-record: arena layout templates (pure
## _gate_counter lookup, gate 1 byte-identical) and the view-only biome journey.
## RE-RECORDED (2026-07-17, cycle 1 round-3 — KIMK's art==collision pin): the pin test CAUGHT
## cover sprites drawing 26-38px half-wide over a 10px collision half (the same lie, new
## sprite). Rock AABB honestly grown to 16x12 and the draw shrunk to fit (test-pinned <=20px
## half); torture rocks got bigger hitboxes -> campaign moves. ENDLESS moves too: the six
## endless quadrant rocks were PROMOTED from view dressing to real sim blockers (KIMK:
## art that reads as cover must BE cover).
## RE-RECORDED (2026-07-17, cycle 1 batch 2 — authored hazard chunks + mud banks): the mine
## and barrel stream loops now place AUTHORED chunk tables via a pure integer mix of
## (slot, run seed) — the loops' rng draws are GONE (removing draws shifts the shared
## sequence for water/frogmen after them), the torture minefield is a different (authored)
## field, and mud banks flanking the torture river halve enemy approach speed there.
## ENDLESS untouched (no camera streaming). Same batch, inert: trench parapets + foundry
## content (gate 5, unreached), water variation (band 1 hits neither branch).
## RE-RECORDED (2026-07-17, cycle 1 batch 3 — flank doors + hulk cover + victory strip):
## first-bunker-down now breaches 3-rusher flank squads from each wall (the torture's gate-1
## fight passes through the one-dead state), parked unoccupied tanks became solid to boots
## and bullets, and the gate-open cache moved to a composed center strip (its x rng draw
## DELETED, kind draw kept — the sequence past gate-open shifts once). Sample 0 unchanged
## (all three land later in the run). ENDLESS untouched (no gates/tanks/strips there).
## RE-RECORDED (2026-07-17, cycle 1 KIMK round-2): the no-immediate-repeat window re-picks
## torture-window mine chunks and the barrel table grew 4->7 (different authored field).
## Fork/blockade/ford/parity changes all land past gate 1 and rode along inert.
## RE-RECORDED (2026-07-18, cycle 2 c2-12 camera lookahead): CAMERA_LEAD 160->260
## anchors the player at 72% down-screen (the ratchet blind-death fix, both
## reviewers' #1 pick). camera_top derives from CAMERA_LEAD from tick ~1, so every
## CAMPAIGN sample moves — a deliberate sim behavior change, not drift. ENDLESS is
## UNCHANGED: it never advances the camera (CAMERA_LEAD never engages) and the
## courier spawn move (camera_top+240->+300) is wave-3+, past the wave-2 wipe.
## RE-RECORDED (2026-07-18, cycle 2 c2-13 flank telegraph+stagger): the gate-1
## flank breach now warns 45t early and staggers the two walls 30t apart (was a
## same-tick double-spawn) — 6 spawn timings shift + a conditional breach_cd feed
## enters the hash. Only samples 4-5 moved (the breach fires late in the torture,
## after gate 1's first bunker falls); 0-3 identical to the c2-12 lookahead record.
## ENDLESS unaffected — flank breaches are a campaign gate-streaming mechanic.
const GOLDEN: Array[int] = [
	3960584721031551345,
	996321938414542430,
	5287757350757329119,
	969675874419806883,
	2065829588026051076,
	5804671699702284095,
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
## RE-RECORDED (2026-07-16, sim gameplay backlog): see GOLDEN note — new hashed player/world
## fields shift the endless stream too, and the wave-3+ special roll widens 0..6 → 0..7 to seat
## the Recon Drone (rng values shift on every special spawn).
## VERIFIED UNCHANGED (2026-07-16, design-loop iter1): see GOLDEN note — the wave-2 wipe keeps
## the torture short of every touched endless path (specials, capsules, drones).
## RE-RECORDED (2026-07-16, grafted design-loop iter 29 — Explosive Fuel Barrels): a new
## checksummed barrels[] block joins checksum(). Campaign torture streams + chains barrels
## (all samples moved); endless spawns none, but the unconditional feed.call(barrels.size()=0)
## structural add shifts every endless sample too.
## RE-RECORDED (2026-07-16, grafted design-loop iter 25 — Triple Shot): a new hashed player
## field int(p["triple"]) joins checksum() (unconditional per-player -> all samples shift), and the
## elite-drop roll widened 4+range_i(0,1) -> (0,2) to add the kind-6 capsule (shifts rng on drops).
## RE-RECORDED (2026-07-16, PR#9 reconcile merge): see GOLDEN note.
## RE-RECORDED (2026-07-16, merge reconcile — P3b design fixes + grafted iter25/iter29): the P3b
## fixes (roll-along-aim, grenade edge-detect, airstrike out of crate pool, boss HP player-count
## scaling, score-on-purchase, early specials gate) stack with Triple Shot (hashed p["triple"]) and
## Explosive Fuel Barrels (checksummed barrels[]); all endless samples recomputed for the merged sim.
## RE-RECORDED (2026-07-16, PR#11 merge-to-main): union of main (capsule/drone stack + PR#10
## P3b batch + grafted Triple/Nest/Barrels) with pass2's P3 design changes (MG Nest hp armor +
## coin retier + aim re-acquire + streak/drop exclusion, barrels react to bullets/enemy-contact/
## fuse/coin-neutral, Triple+Spread 5-fan via SPREAD2, shop score parity). Both parents had
## re-recorded independently; new hashed fields e["hp"] and barrel fuse_ticks -> new stream.
## ENDLESS RE-RECORDED (2026-07-17, level-panel cycle 1 — endless-arena identity, 9/9): sixteen
## authored sandbag emplacements (quadrant L-stubs + a central diamond) now seed at endless
## _init — constant coords, no rng, riding the existing sandbag cover/checksum grammar — so
## the endless stream legitimately moves from tick 0. Campaign GOLDEN untouched (endless-gated).
## c2-12 (2026-07-18): VERIFIED UNCHANGED — endless never advances the camera so
## CAMERA_LEAD is inert here, and the courier-spawn move is past the wave-2 wipe.
const ENDLESS_GOLDEN: Array[int] = [
	5810251919466455340,
	6810029477436195130,
	1487056069058360237,
	5646829933815705845,
	8850168734188490941,
	5842112675654817413,
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
	sim._spawn_special(260 * Fixed.ONE, sim.camera_top - 60 * Fixed.ONE, "drone")
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


func test_c3_wave_themes_determinism_and_bias() -> void:
	# c3 2v: the two new composition THEMES (7 MARKSMEN, 8 BOMBARDMENT) step
	# deterministically (A==B) and actually BIAS the elite roster to their subset.
	# Endless-only, wave >= 3 -> past the wave-2 wipe, so goldens are untouched.
	for mod in [7, 8]:
		var a := _themed_wave_run(mod)
		var b := _themed_wave_run(mod)
		Runner.T.eq(a["cs"], b["cs"], "themed wave mod %d A/B checksum diverged" % mod)
		var k: Dictionary = a["kinds"]
		if mod == 7:
			var marksmen: int = k.get("sniper", 0) + k.get("ghillie", 0) + k.get("drone", 0)
			Runner.T.ok(marksmen > 0, "MARKSMEN wave fields ranged-paint specials")
			Runner.T.eq(k.get("grenadier", 0), 0, "MARKSMEN wave excludes off-theme grenadiers")
			Runner.T.eq(k.get("shield", 0), 0, "MARKSMEN wave excludes off-theme shields")
			Runner.T.eq(k.get("technical", 0), 0, "MARKSMEN wave excludes off-theme technicals")
		else:
			var bombard: int = k.get("grenadier", 0) + k.get("sapper", 0)
			Runner.T.ok(bombard > 0, "BOMBARDMENT wave fields area-denial specials")
			Runner.T.eq(k.get("sniper", 0), 0, "BOMBARDMENT wave excludes off-theme snipers")
			Runner.T.eq(k.get("shield", 0), 0, "BOMBARDMENT wave excludes off-theme shields")


func _themed_wave_run(mod: int) -> Dictionary:
	var sim := SimWorld.new(SEED, 1, "endless")
	sim.wave = 3
	sim._start_wave()
	var kinds := {}
	for tick in 300:
		sim.wave_mod = mod   # hold the theme across the window (both runs alike)
		sim.step([SimInput.new()])
		for e in sim.enemies:
			var kd: String = e.get("kind", "")
			kinds[kd] = kinds.get(kd, 0) + 1
	return {"cs": sim.checksum(), "kinds": kinds}
