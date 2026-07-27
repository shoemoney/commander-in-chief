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
## RE-RECORDED (2026-07-24, game-design loop — input-buffer + anti-exploit pass): five
## deliberate sim behavior changes, all lens-consensus picks.
##   1. grenade presses now BUFFER (new hashed `grenade_buf`, 8t, parity with roll) —
##      grenade was the panic button and the only armor-cracker, yet the one verb whose
##      presses inside its own cooldown were discarded outright.
##   2. the roll buffer is armed on the RISING EDGE only (new hashed `roll_prev`). It was
##      a level read, so HOLDING roll re-armed it every tick and auto-rolled the instant
##      the cd expired — a free perpetual i-frame chain off one held button.
##   3. empty-clip bash passes no_score as well as no_coin: bash guarantees a kill on a
##      40t cd against a 90t streak window, so running dry sustained the 20-streak (and
##      its 100% score bonus + token mint) forever at zero cost. Matches the airstrike rule.
##   4. shop buys credit 6x instead of 10x. At 10x it exactly matched the unspent-chest
##      victory conversion, making spending score-neutral — the "gear now vs. revives
##      later" decision the shop is built around was fake and buy-everything dominated.
##   5. killing the mortar observer halves the stall clock instead of zeroing it — the
##      anti-camp valve was paying the camper AND buying back the whole stall window.
## Both GOLDEN and ENDLESS_GOLDEN move: (1) and (2) add player fields hashed from tick 0
## in every mode, and the torture script both holds roll and empties its clip.
## RE-RECORDED (2026-07-24, design-loop phase 3 — panel-consensus economy + input pass):
##   1. respawn gives a PARTIAL kit (49 rounds / 4 grenades, was a free 99/12). A full
##      restock cost ~190 coins at shop rates and the broke fallback is free, so dying
##      strictly dominated buying and the supply economy was decorative.
##   2. a Triple/Trench fan now costs 2 rounds instead of 1 — 3-5 pellets per single
##      decrement made the permanent Triple mod a free 3-5x DPS multiplier.
##   3. supply prices creep on GATES OPENED in campaign. Campaign is always wave 0, so
##      the existing `wave/3` creep never fired there and every price was frozen for the
##      whole run; the endless creep is now capped at +150 so late waves stop starving.
##   4. bash is edge-triggered (new hashed `fire_prev`) — as a level read, holding fire
##      in a swarm auto-bashed a guaranteed kill every 40t with no further input.
##   5. the roll buffer no longer decays DURING a roll (buffer 8 < ROLL_TICKS 18, so a
##      press made mid-roll — the usual way anyone queues the next dodge — always
##      expired unheard), and a roll pressed in water is dropped with a deny event
##      instead of auto-firing the instant you reach dry land.
## Every sample moves in both modes: (4) adds a field hashed from tick 0 and the torture
## script holds fire, and (1)/(2) change ammo state as soon as it dies or fans.
## RE-RECORDED (2026-07-24, kill the firing-range tutorial: the LZ replaces it): campaign
## _init now authors the landing zone -- a 6-rock seawall at -180, a free kind-1 grenade
## crate at (320,-300) and a center bunker at (296,-420) -- so the opening teaches
## shoot/cover/grenade-vs-armor by placement instead of a boot tutorial room. All 6
## campaign samples move (the torture walks the LZ from tick 0); no rng draw is added, so
## the streamed world past -500 is unchanged. ENDLESS_GOLDEN VERIFIED UNCHANGED (the
## authoring is campaign-gated).
## RE-RECORDED (2026-07-25, seawall depth stagger): the LZ seawall's six rocks
## moved off a single y=-180 line onto a hand-authored +-26px depth stagger --
## pure placement, no new rng draw, no kind change, lane still >= HULL_CLEARANCE.
## All 6 campaign samples move; ENDLESS_GOLDEN VERIFIED UNCHANGED (the authoring
## is campaign-gated).
## RE-RECORDED (2026-07-25, ghost-bunker budget leak): `bunkers` was never removed
## from and _step_bunkers had no on-screen gate, so every passed-but-unsealed bunker
## kept spawning infantry behind the camera forever — rushers that ate the shared
## MAX_ENEMIES budget, drew from the shared stream-rng, and were culled by
## _step_enemies the very next tick, starving the real front-line spawner on deep
## runs. Bunkers now ride the same `y > camera_top + 420` sweep as enemies/sandbags/
## rocks, which both prunes them and gates their spawning. The campaign torture
## ratchets past the LZ bunker inside the first sample window, so ALL 6 campaign
## samples move (fewer ghost spawns = a different rng trajectory from there on).
## Gate arenas are unaffected: gates hold their own b1/b2 dict refs, and a closed
## gate pins the camera within GATE_CAMERA_PAD+150px of its pair — always in band.
## ENDLESS_GOLDEN VERIFIED UNCHANGED: endless streams no bunkers at all, and the
## same-pass rooted-spawn fix (endless mg_nest/broadcast now spawn at camera_top+40
## instead of the unreachable camera_top-24, and the rally mast lost its blanket
## exemption from the off-screen cull) is wave-3+/wave-7+ — the endless torture
## wipes during wave 2. Proven instead by the two new tests in test_endless.gd.
## RE-RECORDED (2026-07-25, the LZ grenade crate was a placebo): players spawn at
## GRENADE_AMMO_MAX, so the free kind-1 crate at (320,-300) -- BEFORE the bunker --
## granted mini(MAX, ammo+4) = ZERO and taught nothing. It moved PAST the bunker to
## (320,-480), where it refills the grenade the bunker just cost. Pure placement:
## no new rng draw, no kind/cost change, and -480 is clear of both the LZ bunker
## (-420..-388) and the streamed bunker row at y=-500 (x=120). Also in this pass:
## _collect_pickups now refuses a PRICED crate the player is capped on instead of
## charging the chest + crediting cost*10 for a no-op -- inert for the campaign
## torture (it never stands on a priced crate at cap) but it is sim logic, so it is
## noted here. All 6 campaign samples move (the torture walks the LZ from tick 0, so
## the crate's new y shifts collection timing). ENDLESS_GOLDEN VERIFIED UNCHANGED
## (the LZ authoring is campaign-gated and endless has no priced-crate-at-cap beat).
## VERIFIED UNCHANGED (2026-07-25, enemy movement honours collision): _step_sapper,
## _step_frogman and _step_technical now route through the shared _advance_toward step
## instead of open-coding their movement, so they respect sandbags (a 40-coin player
## purchase), rocks, tank hulks and sealed lane blocks, plus the mud/rubble/wire slow
## and the broadcast rally aura, like every other ground mover. Behavioural, not a
## rounding artifact -- test_archetypes::test_sapper_cannot_cross_a_sandbag_line fails
## on the old code -- but golden-inert HERE: the campaign torture carries frogmen for
## ~10.9k enemy-ticks and not one of them ever surfaces, so the touched lunge branch
## never executes; sappers and technicals are endless-only.
## RE-RECORDED ONCE FOR THE COMBINED TREE (2026-07-25): three of the changes above
## landed as separate branches, and two of them each re-recorded GOLDEN in isolation
## against their own baseline. Neither set survives the merge — the real checksums of
## the combined sim match only a fresh recording, so this is that recording. The
## individual notes above still explain WHY each change moves the trajectory; this
## line explains why the numbers match none of them.
## VERIFIED UNCHANGED (2026-07-25, economy inversion fix -- price/income parity): the
## supply creep went flat-and-capped -> proportional-and-uncapped on a shared _econ_depth
## axis, the campaign vest stopped bypassing that creep, the Clean Wave bonus now calls
## _econ_scale(40) (VALUE-IDENTICAL to the `40 + (wave/3)*10` it replaced -- proven by
## test_shop::test_clean_wave_bonus_rides_the_price_curve), and _try_buy/_collect_pickups
## refuse to bill for a supply that delivers nothing. BOTH goldens hold byte-for-byte: the
## torture never presses buy (a purchase needs progress the 60s script never reaches), the
## endless torture wipes in wave 2 so no shop crate is ever priced or collected, and the
## Clean Wave payout is arithmetically the same integer at every wave.
## RE-RECORDED (2026-07-25, per-sector enemy rosters + duplicate-pair splits): the
## campaign field spawner stopped rolling ONE flat ["grenadier","sniper","shield"]
## +mg_nest list from sector 2 to the finale and now draws from SECTOR_SPECIALS --
## a per-zone roster indexed 1:1 with ZONE_INFO, so the six authored sectors field
## six different threat vocabularies. The torture opens gate 1 late in its 60s, so
## it enters MARSH BASIN ["grenadier","sapper"]: a different roster, a different
## draw span (2 entries, not 4), and therefore a different shared-rng sequence from
## that point on. ONLY samples 4-5 move -- 0-3 are byte-identical to the seawall
## record, which is exactly the fingerprint of a change that bites only after the
## first gate opens. Riding along in the same pass (and NOT what moved these
## values -- both are past the torture's reach): the grenadier's lob became a
## THREE-blast cluster walked across the firing line (the drone keeps the single
## precise circle, so the two _add_strike users are no longer the same dodge), and
## the ghillie now fires-and-vanishes -- back under the grass, bullet-immune, for
## GHILLIE_RECLOAK_TICKS -- where the sniper stays standing and can be traded with
## at any time. ENDLESS_GOLDEN VERIFIED UNCHANGED: the endless wave spawner has its
## own roster, and its torture wipes at wave 2, before grenadiers/ghillies exist.
## VERIFIED UNCHANGED (2026-07-25, gunship act-two pacing): BOSS_CYCLE_TICKS
## 360 -> 300, the strafe/mortar boundary moved to BOSS_STRAFE_TICKS = 120 and
## BOSS_MORTAR_TICKS shifted to [140,180,220]. Both goldens hold: the campaign
## torture never streams as far as gate 3 (the first bridge gunship) and the
## endless torture wipes at wave 2, well before the wave-5 miniboss -- so no
## torture tick ever runs _step_one_boss. Re-checked, not assumed.
## RE-RECORDED (2026-07-25, 17-branch merge): samples 4 and 5 ONLY. 0-3 are byte-identical
## to the previous record, which is the exact fingerprint of a change that bites once the
## first gate opens — the per-sector special roster gives MARSH BASIN a 2-entry table, so the
## shared stream-rng draw span differs from that point on. Every other sim change merged here
## (frogman re-telegraph, bunker sweep, LZ crate, colossus damage, endless armor, economy
## creep, enemy cover collision) argued its own inertness to the torture and all of them hold:
## if any were wrong, samples 0-3 would have moved too.
## BOTH GOLDENS VERIFIED UNCHANGED (2026-07-25, two sim guards: the pilot no longer feeds
## kill_streak, and a walking pilot no longer vetoes the ghillie all-cloaked force-reveal).
## NO sample moved in either stream, and that is proven, not assumed: replaying this exact
## 2P torture with a counter over both windows reports ticks_with_pilot=0, pilot_kills=0,
## ticks_with_ghillie=0, all_cloaked_states=0 in BOTH campaign and endless. Neither entity
## ever exists in a torture tick -- the pilot ejects only from a gunship death the campaign
## stream never reaches, and the endless torture wipes at wave 2, before ghillies spawn --
## so both new branches are structurally unreachable here. Covered instead by two direct
## tests: test_mechanics::test_shooting_the_pilot_does_not_feed_the_kill_streak and
## test_archetypes::test_all_ghillie_wave_force_reveals_even_with_a_pilot_walking, each
## confirmed red against the pre-guard sim.
## BOTH GOLDENS VERIFIED UNCHANGED (2026-07-25, concealment beats aim not area):
## area fire (grenadier lobs, drone paints, observer barrage, gunship mortars,
## every colossus strike) no longer checks _concealed and instead takes the
## _blind_scatter offset, which draws from `rng` -- so it WOULD move the stream,
## but only on a tick where a player is actually concealed. MEASURED, not assumed:
## replaying both torture inputs and counting concealed player-ticks gives 0 in
## campaign and 0 in endless (torture segs 0-1 stream no grass and no trench, no
## smoke capsule is ever collected, and endless wipes at wave 2). Zero rng draws
## added, zero aim points displaced -> both sample sets byte-identical.
## RE-RECORDED (2026-07-25, honest telegraph grammar — elite lock + technical gate):
##   1. the ELITE now locks aim_lx/aim_ly at WINDUP START and fires down that vector,
##      instead of re-aiming at the live target on the fire tick. The sniper already
##      worked this way, so the game taught "a drawn line is a committed shot" and then
##      broke the promise on its most common ranged unit. aim_lx/aim_ly are already
##      hashed for every enemy, so an elite that previously fed 0/0 now feeds a real
##      vector -- and the fired bullet velocity changes wherever the player moved
##      during the 24t windup.
##   2. TECHNICAL_REV_TICKS 18 -> 24 (the reaction floor REAR_WARN_TICKS/VENT_WARN_TICKS
##      already pin and comment), and the rev is now gated on dlen <= the charge's own
##      reach (TECHNICAL_CHARGE_TICKS * TECHNICAL_SPEED = 150px). 300ms in front of a
##      one-hit-kill charge is below human reaction time, and an ungated rev telegraphed
##      a 150px charge at targets 400px away.
## WHICH SAMPLES MOVED: CAMPAIGN 1, 2, 4 and 5 (0 and 3 byte-identical). That is the
## ELITE change alone -- MEASURED by replaying this exact 2P campaign torture with a
## counter: 1070 elite windup-ticks, 0 technical entity-ticks, max wave 0 (technicals
## are endless-only). ENDLESS: all six samples moved, and that stream carries BOTH
## changes -- the same probe on the endless torture reports 416 elite windup-ticks and
## 208 technical entity-ticks, reaching wave 3 (technicals debut at wave 3).
##
## RE-RECORDED (2026-07-25, endless intermission is a decision, not a ritual): the
## campaign stream moved for ONE reason and it is not behavioral — `ready_hold` (the
## ready-up hold counter) joined checksum() and is hashed from tick 0, shifting every
## sample by a constant-zero field. PROVEN, not assumed: with only that one feed line
## commented out and every other edit of this pass in place, all six campaign samples
## match the previous committed values byte-for-byte (and endless sample 0 does too).
## The three sim changes are endless-gated or inert here:
##   1. Shop crates draw 3 of CRATE_POOL (ammo/grenade/vest/triple/claymore) instead of
##      shuffling the literal [0,1,2] — endless-only, inside the wave-clear branch.
##   2. The intermission length falls with depth (_intermission_len) and the whole living
##      party holding REVIVE for READY_HOLD_TICKS deploys early — endless-only, and wave
##      1 still returns the old flat WAVE_INTERMISSION_TICKS. The torture taps revive on a
##      53-tick cycle, so it never sustains the 20-tick hold.
##   3. Airstrike wipe kills score at WIPE_SCORE_PCT and feed the kill-streak instead of
##      being worth literally nothing (_kill_enemy gained a score_pct arg, default 100 =
##      the old arithmetic exactly). The torture never presses buy, so no strike is ever
##      called in either stream — same argument the wheel-only-airstrike note makes above.
## MERGED: neither branch's numbers survive this merge — re-recorded ONCE on the
## combined tree. Both notes above still describe what moved and why.
##
## RE-RECORDED (2026-07-25, HITBOX FAIRNESS AUDIT). Every lethal interaction was
## measured against the sprite the player actually sees (tools/measure_hitbox.gd
## dumps the opaque alpha bbox of each drawn texture x its call scale; the ratios
## are now pinned by tests/test_hitbox_fairness.gd). Five sim changes move this
## stream, all of them from tick 0 because the torture is nose-to-nose with
## rushers the whole run:
##   1. RESOLUTION ORDER — contact death left the tail of _step_players for its
##      own pass, _step_contact_deaths(), which step() now runs AFTER
##      _step_bullets/_step_enemy_bullets/_step_grenades and BEFORE _step_enemies.
##      It used to resolve FIRST, so a rusher the player's own round killed on
##      tick T still killed the player on tick T. A tie now goes to the player,
##      and nothing can kill from a position that was never rendered. This alone
##      moves sample 0: the torture holds fire into point-blank rushers.
##   2. ENEMY_BULLET_HIT_RADIUS 8 -> 7. The hero silhouette draws 19.1x20.4px
##      (inscribed radius 9.55), so 8 made 84% of the drawn body lethal in a
##      one-hit-kill game; 7 is 73% — the round must be visibly INSIDE the man.
##   3. BULLET_HIT_RADIUS 9 -> 10. The player's OWN round was 98% of a fodder
##      half-width (9.2px) — no generosity at all on the one hitbox that should
##      have some. 10 = 109%, a one-pixel forgiveness collar.
##   4. BLAST_KILL_RADIUS 30 splits the ENEMY-kill scan out of GRENADE_RADIUS 28.
##      The drawn fireball peaks at ~33px radius, so enemies standing in visible
##      flame used to walk out. Player-LETHAL blast checks (strike, barrel) and
##      every cover/bunker/boss keep-out still use 28 — incoming never grew.
##   5. PILOT_RESCUE_RADIUS 14 splits the friendly pilot grab off the lethal
##      ENEMY_TOUCH_RADIUS 10 they used to share, plus the barrel's player-hurt
##      check moved from `roll_ticks == 0` to `not roll_iframe` (it was the one
##      lethal check in the sim with a one-tick hole in the dodge i-frames).
## ENDLESS_GOLDEN VERIFIED UNCHANGED: re-measured with these values committed and
## the endless samples are byte-identical (the endless torture wipes in wave 2,
## before its stream diverges on any of the above).
##
##
## 2026-07-25 -- 2P CO-OP AUDIT: campaign GOLDEN RE-RECORDED (samples 1-5; sample 0
## byte-identical, the change needs a death first). ENDLESS_GOLDEN VERIFIED UNCHANGED.
## The torture script mashes revive on a 2P run, so it walks straight through the two
## sim fixes: (1) the broke fallback is armed/disarmed by _step_dead_player every tick
## against the CURRENT shared chest instead of once at _kill_player -- a partner
## draining the chest under a downed body now arms it (previously: down forever), and
## a recovered chest cancels the free respawn; the arming also lands one tick later
## than it used to. (2) a downed player may pay their own revive while a partner is
## still up (it was blocked outright), so the mashed revive in the script now fires
## where it used to no-op. Both shift respawn ticks/positions, which is the whole
## stream downstream. The elite lane-leash party-trip (3) is torture-inert: the script
## never reaches a fork gauntlet.
##
## 2026-07-25 -- ONE SPEND RATE: ENDLESS_GOLDEN RE-RECORDED (samples 1-5; sample 0
## byte-identical). Campaign GOLDEN VERIFIED UNCHANGED, measured not assumed: it was
## re-run with this change in place and all 6 campaign samples came back identical.
## `_collect_pickups` credited a priced ground crate `cost * 10` under a comment
## claiming parity with the spend wheel's `cost * 6`; both now read the single
## SPEND_SCORE_MULT (= 6). `score` IS hashed, so every sample after the torture's
## first priced purchase shifts. MEASURED, not assumed: replaying both torture inputs
## while counting `pickup` events carrying cost > 0 reports campaign=0 (it never
## streams a priced crate at all) and endless=1, collected at TICK 840. SAMPLE_EVERY
## is 600, so tick 840 lands inside sample 1 -- which is precisely the observed
## fingerprint: sample 0 byte-identical, samples 1-5 moved. This is a pure VALUE
## shift; no branch and no rng draw changed, so nothing moved but the number hashed.
##
## BOTH GOLDENS VERIFIED UNCHANGED (2026-07-25, colossus spray_cd clamped at 0 so
## sustained smoke can no longer drive it unbounded negative -- the view's barrel-tip
## warm-up glow is 1 - spray_cd/CD_TICKS and was rendering a warm factor of 20.83).
## Inert three times over, and the first two are measured: the same replay counts
## colossus-alive ticks and reports 0 in BOTH streams (endless tops out at wave 2 and
## never fields it; the campaign torture never streams as far as the Foundry), and the
## clamp is behaviour-identical regardless -- `<= 0` fires on the same tick at 0 as at
## -595, so only the hashed value could ever have moved. Covered instead by a direct
## test: test_colossus::test_spray_cooldown_stays_bounded_under_smoke.
##
## BOTH GOLDENS VERIFIED UNCHANGED (2026-07-25, ALWAYS-FIRE control scheme). The scheme
## removes the fire key: the MG runs continuously and aim is the whole weapon verb. That is
## a change to main._gather_inputs — the VIEW — and this torture drives SimWorld directly
## from its own scripted_input, so the input change cannot reach these numbers at all.
## The one SIM edit it forced is the empty-clip bash: it was gated on a RISING EDGE of
## `fire`, which with no button would arrive exactly once per run and delete the mechanic,
## so it is level-triggered again (still rationed by BASH_COOLDOWN_TICKS, still no_coin/
## no_score). That edit IS reachable here and was MEASURED rather than assumed — instrument
## the two torture streams and they report:
##     campaign  dry ticks P1=0  P2=72   bash=1  dry_fire=4    (never leaves sector 0)
##     endless   dry ticks P1=838 P2=511 bash=3  dry_fire=454  (wipes at tick 1813, wave 2)
## So both streams DO run dry and DO bash — and all 12 sampled checksums still came back
## byte-identical, because the torture holds fire on (t%3)!=0: a rising edge is never more
## than two ticks from any level-true tick, and in these two streams the bash landed on the
## same tick either way. Inert by measurement, not by argument. The behaviour change itself
## is pinned directly by test_controls::test_empty_clip_bash_survives_the_loss_of_the_fire_edge
## and ::test_bash_is_still_rationed_by_its_cooldown_not_by_the_button.
## 2026-07-25 -- FORK-ISLAND CLEARANCE: campaign GOLDEN RE-RECORDED (samples 2-5; 0 and 1
## byte-identical). ENDLESS_GOLDEN VERIFIED UNCHANGED (endless streams no gate arenas at
## all). Three authored ARENAS coordinates were sitting inside a fork gate's wreck island,
## i.e. in scenery boots cannot enter: gate 4's b2 (368 -> 432; its whole 48px body was
## inside the blocked 336..424 band), gate 2's b1 (300 -> 312; west face 4px in), and gate
## 2's front sentinel mine (240 -> 120; buried where no player can ever reach
## MINE_TRIGGER_RADIUS of it). Gate 4's flank mine moved 500 -> 528 to stay outside the
## relocated b2's blast+AABB envelope.
##
## WHY THESE SAMPLES: gate 4 is genuinely torture-inert, but GATE 2 IS NOT -- and the
## ARENAS comment that claimed it was ("never streams past gate 1, probe-verified --
## camera_top ends ~43 units short of gate 2") had gone STALE and is corrected in this
## same commit. MEASURED, not argued (tools/probe_torture_gates.gd): the torture now
## constructs gate 1 @tick 0, gate 2 @tick 1309 and gate 3 @tick 3108, ending at
## camera_top = -2563 px -- 563 px PAST gate 2, not 43 short of it. At SAMPLE_EVERY=600
## a gate-2 construction at tick 1309 can first reach the sample at tick 1800, which is
## sample index 2 -- and samples 2,3,4,5 are exactly the four that moved, with 0 and 1
## byte-identical. The delta is fully accounted for; nothing else in the sim was touched.
## 2026-07-26 -- FORK-GATE-BUNKER: campaign GOLDEN RE-RECORDED AGAIN (samples 2-5; 0 and 1
## byte-identical, same reasoning as the entry above -- gate 4 is still torture-inert, gate 2
## still first reaches a sample at index 2). This is the SAME class the entry above fixed,
## finishing the other 97% of the set: the entry above only fixed the 3 AUTHORED ARENAS
## coordinates that predated the fork wreck-island; it left the STREAMED fork beats (the free
## crate, guard mines, gauntlet elites, deep cache mines -- all rng-drawn, gate 2 AND gate 4)
## still authored as bare gate-2 x's, unmirrored for gate 4 and unclamped off the divider at
## either gate. `_fork_lane_x`/`_clear_fork_divider_x` now mirror (gate 4 only) and clamp
## every one of those beats. Gate 4 is torture-inert so its half is golden-invisible; gate 2's
## beats DO stream in the torture window, and the clamp nudges a few of them off the divider
## face by a handful of px, moving samples 2-5 exactly like last time. ENDLESS_GOLDEN VERIFIED
## UNCHANGED (endless streams no gate arenas, fork or otherwise).
## 2026-07-26 -- CLAYMORE PLANTER GRACE: campaign GOLDEN RE-RECORDED (ALL 6 samples). A new hashed
## mine field `grace` joins checksum() and the mines[] block feeds unconditionally, so every sample
## shifts by the added field even though the torture never plants a claymore -- the same structural
## shift the barrels[] block caused. ENDLESS_GOLDEN: expected unchanged for the same reason it always
## is (endless streams no gate arenas), verified by the suite.
##
## WHY THE FIELD EXISTS, measured not argued (tools/probe_claymore.gd): the charge planted ALONG the
## aim and armed instantly, so ADVANCING while aiming the same way -- the twin-stick input the game
## teaches -- detonated it on YOU at tick 5. Placement cannot fix this: the earlier behind-the-aim
## placement had the mirror bug at ~5 ticks on a full backpedal, which is why it was moved in the
## first place. So the charge now ignores PLAYERS for CLAYMORE_ARM_TICKS (20, sized from the measured
## ~2.2px/tick approach across an 18px trigger zone) and stays live to everything else. Counter-checked
## so the fix cannot have simply neutered the weapon: an enemy standing on it during that window
## still dies at tick 2, and once grace expires the planter is hurt again at tick 5.
## RE-RECORDED (2026-07-26, cover-slide fix): _advance_toward and _step_players now
## resolve cover (rocks/sandbags/hulks/sealed lane blocks/the keyed barricade) per-axis
## (slide) instead of reverting both axes on any contact — every mover that touches
## cover shifts position from the first contact tick onward. Sample 0 (t=600) is
## byte-identical: the torture hasn't reached any cover yet at 10s in. Samples 1-5 all
## moved (the torture streams rocks/sandbags/hulks well before 20s).
## 2026-07-27 -- CAMERA-HELD STALL FREEZE: campaign GOLDEN RE-RECORDED (ALL 6 samples).
## ENDLESS_GOLDEN VERIFIED UNCHANGED, measured not assumed (see below).
##
## stall_ticks scored "the camera did not advance this tick" as the player loitering. But a closed
## gate CLAMPS the camera (sim_world.gd _step_camera pins camera_top to g["y"] - GATE_CAMERA_PAD),
## so the counter was scoring the game's own wall against the player, then answering with a mortar
## observer and an on-screen order to PUSH NORTH that could not be obeyed. _step_observer now
## consults the new pure predicate camera_held() and does not accrue while the SIM holds the camera;
## an observer already up when the clamp binds also stands down, because escaping costs
## OBSERVER_DESPAWN_ADVANCE (150px) of advance the clamp forbids.
##
## WHY EVERY SAMPLE MOVES, measured (.aaa/probe_c7.gd, .aaa/probe_c7b.gd): the 60s 2P torture spends
## 1845 of its 3600 ticks pinned on a closed gate, peaks at stall_ticks 924 (the observer fuse is
## 480) and spawns 1 observer while pinned. tools/probe_torture_gates.gd shows gate 1 exists from
## tick 0, so sample 0 (t=600) moves too -- unlike most re-records here, nothing is byte-identical.
## stall_ticks is hashed directly (checksum feed), and the observer/strikes it gates drag every
## enemy downstream of that mortar with them.
##
## ENDLESS: camera_held() returns true unconditionally for endless (it never calls _step_camera at
## all -- camera_top is pinned at -VIEW_H by design), so its stall_ticks freezes too. The endless
## goldens still do not move because _step_observer only runs in endless once the Spotter wave
## mutator has dropped an observer, and the endless torture never draws one -- stall_ticks is 0
## either way. Verified by running the suite, not inferred.
## RE-RECORDED (2026-07-27, the sapper stops standing on its own charge): CAMPAIGN ONLY,
## samples 2-5. _step_sapper laid its mine AT the sapper's feet, and _step_mines' enemy
## scan deliberately ignores `grace` (so a claymore dropped in a pursuer's path works on
## the tick it lands) -- so every mine tripped against its own layer on the tick it landed
## and the advertised trail never existed. The drop now sits one CLAYMORE_PLANT_OFFSET back
## down the sapper's approach, clear of its own 9px trigger, and mine x/y are checksummed,
## so this stream legitimately moves. PREDICTED FIRST, THEN CONFIRMED: sappers are in the
## MARSH BASIN roster, so the campaign torture reaches them once gate 1 opens -- a replay
## with a counter reports first sapper at TICK 1637, first mine_lay at TICK 1778, 17 mines
## laid over the run. 1778 / SAMPLE_EVERY(600) = 2, so samples 2-5 move and 0-1 must not.
## They did not: both came back byte-identical, which is the proof nothing else moved.
## ENDLESS GOLDEN VERIFIED UNCHANGED: that torture wipes at tick 1393 (wave 2) and freezes,
## and the sapper is a wave-3+ elite roll, so no mine is ever laid in it.
## The other three sim fixes shipped alongside this one are golden-inert, and that is
## MEASURED rather than argued: with ONLY the mine offset reverted and the other three
## fixes still in the tree, this stream reproduces the PRE-FIX goldens byte-for-byte
## (3102861628708881044 / 650205415488164338 / 1254423104984790566 / 6447189277068568902
## at samples 2-5). If any of the three touched the campaign stream, that revert could not
## land back on the old values. The three:
##   - endless ghillie spawns at rooted_y instead of camera_top-24 (endless, wave>=3 -- the
##     endless torture never gets there; the committed note above already records
##     ticks_with_ghillie=0 in both streams);
##   - the empty-clip bash no longer executes the rescue pilot (the same note records
##     ticks_with_pilot=0 and pilot_kills=0 in both streams);
##   - step()'s boss_rush branch now calls _step_mines/_step_barrels (neither torture runs
##     that mode at all).
##
## RE-RECORD 2026-07-26 (mg_nest lead): the nest now aims where the target WILL be
## rather than where it was. Its rounds' vx/vy are hashed, so the stream diverges the
## first time a nest fires inside the torture window.
##
## PREDICTED BEFORE RE-RECORDING, and the prediction is the point: mg_nests are authored
## seg>=2, and the torture reaches that band late, so ONLY the trailing sample should move.
## It did — samples 0-4 (ticks 600..3000) are byte-identical and only sample 5 (tick 3600)
## changed, 6016516403530113665 -> 7360276865937536353. A change that moved earlier samples
## would have meant the lead leaked somewhere it should not, and this note would be a bug
## report instead of a re-record.
##
## ENDLESS_GOLDEN VERIFIED UNCHANGED: the endless torture wipes during wave 2 and never
## streams an mg_nest, so the endless stream cannot reach this code at all.
##
## RE-RECORD 2026-07-27 (MERGE of two independently-recorded trees): the two notes above
## were recorded on SEPARATE branches, so neither array could be assumed correct here and
## neither side was picked. The values below were re-derived once on the COMBINED tree.
##
## THE MEASUREMENT CONTRADICTED THE PREDICTION, so it is written down rather than smoothed
## over. Predicted: the mg_nest lead moves sample 5 here as it did on its own branch.
## Measured: the combined tree reproduces the SAPPER-side values byte-for-byte at all six
## samples -- the lead is INERT in this torture once the sapper's mine offset is also in
## the tree, because the two changes' streams diverge from tick 1778 and the campaign
## torture no longer reaches a firing nest inside its 3600-tick window.
##
## DO NOT read that as "the lead got lost in the merge" -- that was checked, not assumed:
## mg_nest_led_aim is defined at sim_world.gd:6148 and CALLED at :3882 in this tree, and
## `git diff origin/main -- src/sim/sim_world.gd` shows no drift in any nest code. The
## guard for that feature is its own unit test (test_mg_nest_leads_a_moving_target...),
## which is what should hold it -- a golden that happens to be insensitive to a change is
## not evidence about the change either way.
## RE-RECORDED (2026-07-27, per-kind bullet reach): BULLET_HIT_RADIUS (10px) was one
## constant for every enemy, but four kinds are drawn far larger than the fodder
## silhouette it was tuned against (measured drawn half-extents: elite 11.75, technical
## 11.63, mg_nest 14.62, broadcast 15.51 px), so a round landing squarely INSIDE their
## own bodies passed through. KIND_HIT_RADIUS gives those four their own reach; the
## 10px DEFAULT did not move, so the fodder/courier band test_hitbox_fairness pins at
## 1.00-1.30 is untouched. `alive`/`hp` are hashed, so an earlier kill forks the stream.
##
## THREE OTHER SIM EDITS SHIPPED IN THE SAME COMMIT AND ARE PROVABLY INERT HERE — this
## was MEASURED, not argued: with KIND_HIT_RADIUS temporarily set to {} and
## OBSERVER_HIT_RADIUS back to 10, BOTH arrays came back byte-identical to the previous
## committed values. So the god-mode _latch_wipe guard (god_mode is false in both
## streams), the arcade _econ_depth guard (neither stream constructs "arcade"), and the
## bash armour rules all contribute nothing. The bash result also CONFIRMS the campaign
## torture's single bash lands on an hp-1, non-shield body.
##
## THE MEASUREMENT CONTRADICTED THE PREDICTION, so it is written down rather than
## smoothed over. Predicted: all six campaign samples move, because the first elite
## exists at tick ~315 (SPAWN_INTERVAL_TICKS 45, every 7th spawn elite at opened == 0),
## which is inside sample 0's window. Measured: samples 0-2 (ticks 0-1799) are
## BYTE-IDENTICAL and the fork begins inside sample 3's window (1800-2399). Elites
## existing is not the same as a round landing in the new 10..13px annulus of one — with
## ALWAYS-FIRE most rounds land dead-on or clean past, and the first round to fall in
## that ring took ~1800 ticks to arrive.
##
## WHICH KIND: isolated with KIND_HIT_RADIUS := {"elite": 13 * F_ONE} alone, which
## reproduces all three moved campaign samples BYTE-FOR-BYTE. The elite is the sole
## campaign driver; mg_nest and broadcast contribute nothing to this stream (broadcast
## is sector-5 only, and the campaign torture never lands a round in a nest's annulus).
## The observer needs a 480-tick stall the advancing torture never takes.
const GOLDEN: Array[int] = [
	2407026767914979979,
	461371032039649670,
	5063156605900622803,
	7840083679643977125,
	8428269569959002222,
	6332735790241153794,
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
## VERIFIED UNCHANGED (2026-07-25, enemy movement honours collision): see GOLDEN note.
## The endless torture wipes at wave 2, before the first sapper spawn; the 208 technical
## enemy-ticks it does step sit clear of every piece of cover and slow terrain the shared
## step adds, so _advance_toward reproduces the old positions byte for byte.
## BOTH GOLDENS VERIFIED UNCHANGED (2026-07-25, endless difficulty curve + reachable
## failure state). Four sim changes, none of which the torture windows can observe:
##   1. Veteran armor (_wave_armor) hardens endless spawns — gated wave >= 13, and it
##      only WRITES e["hp"] when the bonus is nonzero, so the (already hashed) hp feed
##      stays absent everywhere the torture reaches.
##   2. second_mod()/has_mod() stack a second wave mutator — gated wave >= 15, derived
##      purely from wave + world seed (no new hashed field, no rng draw), and has_mod()
##      reduces to `wave_mod == m` whenever second_mod() is 0.
##   3. The bullet armor branch now reads e.get("hp", 1) > 1 instead of a kind whitelist
##      (mg_nest/technical/broadcast) — behaviour-identical for those three, since they
##      are the only kinds that carried an hp field.
##   4. revive_cost() compounds uncapped and wave-multiplies IN ENDLESS ONLY. Campaign
##      keeps the 3-death soft cap verbatim -> GOLDEN untouched by construction. Below
##      wave 5 the endless formula (50 * max(deaths,1) * 1) equals the old one for 0-3
##      deaths, which is the entire reach of the endless torture (it wipes in wave 2).
## VERIFIED UNCHANGED (2026-07-25, pilot streak guard + pilot-skipping ghillie reveal):
## see the GOLDEN note -- measured zero pilot and zero ghillie ticks in this stream too.
##
## 2026-07-25 — endless arena-shift / supply-pod congestion fix: BOTH GOLDEN AND
## ENDLESS_GOLDEN VERIFIED UNCHANGED, no re-record. The every-3rd-wave L-drop now walks
## the slot table TWICE (second lap recycles stale non-player cover via _cover_blocked)
## and the wave-5 supply pod gained the same walk plus a supply_pod_blocked report.
## Every edited branch is gated `mode == "endless" and wave >= 3` / `>= 5`; the endless
## torture wipes in wave 2, so the recycle path is never reached, and campaign never
## enters either branch at all. Confirmed empirically: the full suite is green with the
## committed values untouched.
## RE-RECORDED (2026-07-25, honest telegraph grammar) -- see the note above GOLDEN.
## All six endless samples move: this stream fields elites from tick 0 (locked aim
## vector) and technicals from wave 3 (24t rev + charge-range gate).
##
## ENDLESS RE-RECORDED (2026-07-25, endless intermission is a decision, not a ritual):
## see the GOLDEN note for the three changes. Here they are NOT inert, and the split is
## measured rather than argued: with `ready_hold` alone removed from checksum(), sample 0
## still matched the old value and samples 1-5 did not. So sample 0 moves only from the
## new hashed field, and 1-5 move from the wave-1 shop opening — the crate draw is a
## partial Fisher-Yates over a 5-item pool (three rng calls) where the old one shuffled a
## 3-item literal (two calls), so the shared rng stream legitimately shifts from the first
## wave clear onward, which is ~tick 700 in this torture. Wave 1's intermission LENGTH is
## unchanged (_intermission_len returns WAVE_INTERMISSION_TICKS at wave 1) and the run
## still wipes in wave 2, so nothing here is the ready-up or the airstrike change.
## MERGED: neither branch's numbers survive this merge — re-recorded ONCE on the
## combined tree. Both notes above still describe what moved and why.
## RE-RECORDED (2026-07-26, cover-slide fix): see the GOLDEN note above — the endless
## torture also streams the seeded quadrant rocks/sandbags and touches them well before
## 20s, so samples 1-5 move too. Sample 0 (t=600) is byte-identical (too early to reach
## any of them, same as campaign).
## ENDLESS RE-RECORDED (2026-07-27, a lost run finally converts the War Chest):
## SimWorld._latch_wipe() is now the single terminal latch for the losing end, and it
## does what _damage_colossus() always did for the winning end — banks the unspent chest
## as score and zeroes it. Both `score` and `war_chest` are checksummed, so the endless
## torture legitimately moves. MEASURED, not argued: the 2P endless torture wipes at
## TICK 1393 (wave 2) holding 25 coin; score goes 730 -> 805 (+75 == 25 * WIPE_SCORE_MULT)
## and war_chest 25 -> 0 on that tick, and the sim is frozen behind `wiped` afterwards, so
## every later sample carries exactly that delta. Samples 0 and 1 (ticks 599/1199, both
## BEFORE the wipe) are byte-identical to the previous values — which is the proof that
## nothing else moved. GOLDEN (campaign) VERIFIED UNCHANGED: the campaign torture never
## reaches ANY terminal state (measured: wiped=false victory=false, chest 235, score
## 32497 at tick 3600), so neither converter executes in that stream.
## ENDLESS RE-RECORDED (2026-07-27, per-kind bullet reach): see the GOLDEN note above
## for the change and for the proof that the other three sim edits in this commit are
## inert. Here ALL SIX samples move, including sample 0 — this stream fields elites from
## tick 0, so the very first sample window can already contain a round in the new
## 10..13px annulus, which is exactly the campaign stream's difference (it took until
## sample 3 to land one).
##
## THE SPLIT IS MEASURED, not argued: with KIND_HIT_RADIUS := {"elite": 13 * F_ONE}
## alone, endless samples 0 and 1 already match the values below byte-for-byte while
## samples 2-5 do not. So the elite alone drives the first ~1200 ticks.
##
## CORRECTED 2026-07-27, and the correction is the point. The first version of this
## paragraph credited samples 2-5 to the TECHNICAL, and contradicted itself in its own
## sentence: it also said this torture wipes in wave 2, and the technical is a wave-3
## special, so both could not be true. Re-driving the exact torture (SEED 0xDEADBEEF,
## 2P, scripted_input, 3600 ticks) settles it — the kinds this stream EVER fields are:
##   courier, drone, elite, ghillie, grenadier, rusher, sapper, sniper
## No technical, no mg_nest, no broadcast. THREE of the four KIND_HIT_RADIUS entries
## provably cannot touch this stream at all.
##
## The real second driver is OBSERVER_HIT_RADIUS (10 -> 14). The same run spawns exactly
## ONE observer, at TICK 1225 — between sample 1 (t=1200) and sample 2 (t=1800), which is
## exactly where the elite-only isolation stops reproducing. One measured tick explains
## the whole split; the kind-roster guess explained none of it.
##
## Two premises inherited from the note above are ALSO stale and are corrected here
## rather than left to be re-quoted: this torture reaches WAVE 5, not wave 2, and wipes
## at TICK 3132, not 1393. Those numbers were true when they were written and the sim
## has moved since. Re-drive the probe; do not trust the prose.
const ENDLESS_GOLDEN: Array[int] = [
	8610209561549742921,
	4307715087271070947,
	2392889603967106672,
	2697056323710043292,
	3080589168965590143,
	706117180998451249,
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
