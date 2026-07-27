# Owner Decision Brief — Commander In Chief

Distilled from the 51 `owner_decisions` banked by 9 cycles of `/triple-a-game` (source:
`Backlog.md`, itself rendered from a gitignored `.aaa/ledger.json`). **51 raw entries → 28
decisions + 4 misfiled defects.**

> **The headline: every one of these is already answered by the code as it stands.**
> "Do nothing" is not neutral — it ships the current answer. The four highest items changed what a
> default-difficulty player experiences and nobody signed off.

Measurements below are copied **verbatim** from the gate transcripts. A paraphrased measurement is
just an opinion.

---

## If you only do five things

1. **Play one run** and judge D13 (the 55%-weaker hit cue). Nothing else here benefits more from hands-on.
2. **D1** — give vestless riders the 30–45 tick bail grace. Default difficulty currently cannot reach a mechanic the HUD advertises.
3. **D14** — give the riot shield a turn rate. 0 kills / 16 strafe bearings means the flank verb does not exist.
4. **D6** — `SANDBAG_FIELD_CAP` 6 → 12. One constant, restores a halved coin sink.
5. **D25** — split the attract bot from the balance-probe bot, or keep distrusting every tank-vs-foot number in this file.

---

## TIER 1 — Changes what a player feels, right now

### D1. Tank brew-up: should an ordnance hit KILL a vestless rider on the same tick, or give a bail window? *(subsumes 3 entries)*

> "With assist_mode OFF there is no vest, so `_ignite_tank(tank, true)` → `_hurt_player` → `_kill_player` fires on the same tick the shell lands, and TANK_BAIL_TICKS = 180 becomes unreachable content for that difficulty… **16 of 22 occupied-tank ignitions per the pre-flight are artillery**, so this is the common case, not an edge."
>
> "treads detonate barrels inside their own GRENADE_RADIUS (sim_world.gd:2225-2227) → `_explode` → `_ignite_tank(…, true)`, so a non-assist driver who rolls over a barrel now dies instantly where HEAD gave 3 seconds. **2 of 22 ignitions.**"
>
> "occupied-hull ignitions are now ~50/50 fuel-out vs damage (**7/7 over 4 seeds**) versus **18% fuel-out pre-fix**… with the ring stubbed out, mounted knockdowns are **0 in 6,503 ticks** — the rider is unkillable again."
>
> Knob if you want a window: "'ring the crew only if still aboard N ticks after ignition' (**N≈30-45**)."

**Do nothing:** default-difficulty players never see the bail mechanic. The HUD prints `BAIL OUT! %ds`, a test (`test_burning_tank_crew_is_exposed_to_every_hazard` case 2a) *pins* the same-tick kill as intended, and only assist-ON players experience the 3-second race the game telegraphs.

**Rec:** Take the N≈30–45 grace. Advertising a mechanic on the HUD that the default config can never enter is the exact "the game wasn't watching" tell this loop exists to kill. The 0-knockdown measurement says don't remove the ring — delay it.

### D2. "The tank is dominant" — do you mean the rider's SAFETY or the tank's SHARE OF THE RUN? *(subsumes 3)*

> "This diff answers the second (**38.7% → 5.3% mounted**) and makes the first measurably worse (**3.6x → 52.6x safer**)."
>
> "the tank is still **3.47x safer per tick** than being on foot (was 3.97x), because the escape is instant and i-framed… an ordnance ignition costs the crew exactly one hit (a vest absorbs it outright) and the bail still grants **BAIL_BOOST_TICKS=90** plus BAIL_IFRAME_TICKS."
>
> "THE TANK IS STILL **3.46x SAFER AND 1.37x DEADLIER PER TICK** THAN BEING ON FOOT, and no honest change left on the table moves those."

**Do nothing:** the shipped answer is "share of run", and rider safety got 14x *worse* as a side effect. Real parity is a much larger change (hull HP → new hashed field → golden re-record) that the pre-flight already argued against.

**Rec:** Answer "share of run" explicitly and close it. A tank being 3.5x safer is what a tank is; the sin was it being free, and that is now priced. Do not chase parity.

### D3. Is 16.2% mount share the intended presence for a signature vehicle, or too low?

> "TANK_HIT_FUEL_COST=60 is a first-guess tuning knob with no telemetry behind it. It halves a contested ride from **20 s to 10 s at 20 hits**. Measured campaign mount share fell **31.7% → 16.2% across 8 seeds** with this plus the bail change combined — nobody has separated the two contributions."

**Do nothing:** the tank is on screen half as often as it was, from an untelemetered guess, with two changes' contributions still tangled.

**Rec:** Not enough to recommend a number, but the confound is cheap to resolve — run the 8 seeds with fuel cost reverted only. Do that before touching the constant.

### D4. MG nest lane: should it lock like every other telegraph, or track — and if it tracks, should it LEAD? *(subsumes 3)*

> "sniper/elite/ghillie/technical paint 'this line is committed, sidestep it', while the nest paints 'this line follows you'… making the sim lock like the rest (delete the re-acquire at **sim_world.gd:3543-3549**) removes the tracking rake, which the sim comments call deliberate ('punishes standing still'), and would move test_determinism GOLDEN."
>
> "**ENEMY_BULLET_SPEED is 3 px/tick (180 px/s) against a 144 px/s player** and the re-acquire adds NO lead, so a player who keeps strafing is missed by the bullet anyway — the tracking rake only lands on someone who sidesteps and stops."

**Do nothing:** the game ships two contradictory lane grammars, and the tracking one is toothless against anyone moving — a lane that follows you and still misses.

**Rec:** Add the lead term. Tracking-without-lead is the worst of both: it teaches the wrong grammar *and* does not threaten. Costs a golden re-record; that is routine.

### D5. Sandbag nest cover grammar — is walk-through, shoot-through, heading-dependent cover intended? *(subsumes 4)*

> "The two-wing nest gives the buyer a permanent **14 px embrasure** that enemy fire also comes through, and the player has no collision with sandbags… The sim currently treats it as strictly two-way (**sim_world.gd:5942** was a deliberate earlier choice)."
>
> "the visible embrasure is **17.2px on N/S (unclamped)** but **22-23px on the 45deg** and the two steepest off-axis headings (clamped). A player who plants diagonally gets a measurably wider firing slot — and a measurably leakier wall."
>
> "the boot-slide list at **sim_world.gd:1111/1122** covers hulks, rocks, fork dividers and sealed blocks, **never bags**, so the buyer can walk straight through the nest he just paid 40 coins for."
>
> "rushers path around sandbag AABBs — so a rusher charging along the aim now walks through the nest instead of being turned by it… (~**6 ticks of strafe** re-enters the cover trade), but it is a real nerf to bought cover against the exact threat it was sold to stop, and **no test pins how much**."

**Do nothing:** a 40-coin purchase is walk-through, shoot-through, leaks more if you plant diagonally, and lets the one enemy it is sold against walk right in.

**Rec:** Add player-tagged bags to the boot-slide list (one list entry) and make the slot width constant. Leave two-way fire — that is a fair arcade trade. The heading-dependent leak is the only part that reads as a bug to a player.

### D6. Sandbag economy: is 3 nests per field the intended cover budget, or should cap/price move to preserve 6? *(subsumes 3)*

> "SANDBAG_FIELD_CAP stayed 6 while a purchase went from 1 bag to 2, so the cover sink dropped from **6 buys (240 coins) to 3 (120)** per field."
>
> "the player's cover budget goes from **6 independent 36px segments to 3 fixed-geometry nests** for the same 40 coins each. Total bag pixels are unchanged (**258px across a ~592px lane**) but the number of distinct positions you can cover halves, and each nest now has a mandatory hole in it."
>
> "The HUD reads bags/6 either way and does not lie, so this is purely an economy call."

**Do nothing:** bought cover is half price per segment and the mid-game coin sink shrank 50%, silently.

**Rec:** Raise `SANDBAG_FIELD_CAP` to 12. Cheapest single-constant fix, restores the sink, keeps the 40-coin price the player already knows.

### D7. Sandbag placement: keep "you dig in facing the way you were shooting", or add an aiming mode? *(subsumes 2)*

> "**main.gd:5693-5700** pins p1.aim to `_wheel_aim`; `_step_players` runs the buy at **:995** before refreshing aim at **:1164**… the emplacement always faces the heading you were fighting on, never the one you are about to defend. The plan deliberately declined a placement mode on the grounds that the slot defuses it (YAGNI), and the captures back that up."

**Do nothing:** no placement UI, ever. Defensible.

**Rec:** Leave it. YAGNI held. Revisit only if D5's collision fix makes facing matter more.

---

## TIER 2 — Changes the run's shape or its payoff

### D8. Should completed campaigns read "competent" (B) or "triumphant" (S)?

> "Campaign completions now grade B (median of 5 measured completions: **B,B,A,B,A**) where every completion previously graded S… Best measured campaign run is **866 net mvp against an S band of 700**, so S is reachable (seed 4 non-god hit it) but no longer automatic."

**Do nothing:** every finishing player now sees B. Shipped.

**Rec:** Keep B. S-on-every-finish was the original defect; a reachable-but-not-automatic S is the point. But see misfiled defect **M4** — old S runs still sit on the board next to new Bs.

### D9. War-chest salvage: is 3x a courtesy payout or an economy lever? *(subsumes 2)*

> "WIPE_SCORE_MULT = 3 is half the 6x spend rate and the invariant test pins **0 < wipe < spend < 10**… at a typical solo wave-12 stranding (**<=224 coin**) it adds **~672 score** against the **~88,900** a wave-12 endless run is posed at (**0.76%**)."
>
> "the invariant test already pins the ceiling at 5."

**Do nothing:** salvage is a rounding error on the leaderboard — it stops the silent forfeit and nothing more.

**Rec:** Leave at 3 if the goal was "stop the silent forfeit" (it is doing that). Only move to ~5 if you want players to *feel* consoled.

### D10. Should the endless war chest feed persistent meta-progress at all?

> "vet_points += sim.wave (**main.gd:4436**) is independent of both score and chest, so the salvage buys nothing persistent."

**Do nothing:** hoarding coins buys zero long-term progress; VP is purely wave-depth.

**Rec:** Leave it. Wave-depth-only VP is legible and un-gameable; tying VP to hoarding directly fights the "spending must stay dominant" rule you just enforced in D9.

### D11. Is boss_rush's 3-mvp knockdown cost intentional scaling or an under-cost?

> "boss_rush pays **3 net mvp per knockdown** while campaign/arcade/endless pay **12**, because the rush's whole scale is **~200 mvp** and a 12-point cost graded **every measured rush D**. The asymmetry is commented in RANK_BANDS but it means a knockdown is worth **4x less** in the mode where the bot takes the MOST of them (**9-17 per run vs 25-52 in campaign** over ~half the ticks)."

**Do nothing:** dying is 4x cheaper in the mode you die most.

**Rec:** Intentional scaling — 12 graded *every* rush D, the same broken-scale failure as D8 in reverse. Keep 3, but record it in RANK_BANDS as a decision rather than a workaround.

### D12. Anti-camp: does a held camera (boss_rush / endless / closed gates) get its own pressure valve, or none? *(subsumes 4)*

> "the camera held on **3691 of 4000 boss_rush ticks** and observer spawns while held drop **from 6 to 0**, so in the mode whose premise is standing in an arena there is now no pressure valve at all."
>
> "endless now has `camera_held() == true` unconditionally, so its stall_ticks is pinned at **0 forever** and the REAR_CAMP_TICKS choke-rusher (**sim_world.gd:6047**, campaign-only today) plus every future stall-driven mechanic silently no-ops there."
>
> "Measured (.aaa/probe_camp_c7.gd, deliberate camp at the first closed gate, **4 seeds x 7691 held ticks**): observer_spawn **1 → 0** per seed, stall_ticks peak **5701 → 0**. Remaining pressure is the garrison, which **saturates at 64 alive enemies** in every seed."

**Do nothing:** camping a closed gate or a boss arena is free of the observer/mortar valve in three modes. A 64-enemy saturated garrison is the only remaining pressure.

**Rec:** 64 alive enemies is real pressure — accept it at closed gates. But boss_rush having *literally no* valve in the mode built around standing still deserves an explicit yes. The missing-test half of this is a backlog item, not a decision.

### D13. Should the damage vignette cap at 0.45, and should the airstrike's final strobe be perimeter-only? *(subsumes 2)*

> "with no other wash active, `wash_clamp(1.0 * peak 1.0, load 0.0) = min(1.0, (0.45 - 0)/1.0) = 0.45`, a **55% reduction** at the card's opaque border pixels… The plan traded it deliberately for silhouette contrast (**border retention 3% → 30%+**) and explicitly said it was reversing a standing 'more feedback is better' tuning intent, but **WASH_CAP = 0.45 is a feel number nobody has played against yet.**"
>
> "The airstrike telegraph's final-second strobe is now perimeter-only (peak raised **0.34 → 0.45**)… 'a lethal screen-clear is **0.4s** out' moved from the centre of vision to the edge of it."

**Do nothing:** the primary "you got hit" cue in a one-hit game is 55% weaker than it was, untested by a human.

**Rec:** **Play one run before deciding anything else on this list.** The only item where 10 minutes hands-on beats any measurement. Knob is `WASH_CAP`, not the per-kind peaks.

### D14. Should the riot shield's facing have a turn rate, or keep pivoting instantly?

> "facing is still recomputed toward the nearest player EVERY tick with zero turn rate (`sim_world.gd::_shield_blocks`)… measured today: **0 kills / 16 strafe bearings at a 40 px standoff**, **46 kills / 1,512 live trials all at 9.05-10.30 px closest approach** (contact range, not a flank)."
>
> "The plan deliberately declined option (b) because a stored heading is a hashed sim field and forces a golden re-record."

**Do nothing:** the copy no longer lies, but flanking a shieldman remains geometrically impossible — the only kills are at contact range, inside the ring that kills you.

**Rec:** Give it a turn rate. This was cycle 1's loudest finding, the copy fix was a patch over the mechanic, and "0 kills at a real standoff" is not an arcade rule, it is an absent verb. Golden re-record is routine.

---

## TIER 3 — Readability and framing

### D15. Bridge deck: should it mark the RELIABLE crossing or the DIRECT one? *(subsumes 2)*

> "Bands 2 and 5 own a PERMANENT second ford that never washes out, and it is still drawn as a bare sand strip while the only bridge asset in the game sits on the crossing that **fails 70% of the time**… the game's most authoritative 'cross here' asset sits on the crossing that fails 70% of the time while the one that never fails is unmarked. The plan deliberately deferred this as new art (§7)."

**Do nothing:** the game's strongest "safe way over" signal permanently points at its least reliable crossing.

**Rec:** Move the deck to the permanent ford, or mark the permanent ford. Costs art, but a 70%-failure crossing wearing the bridge asset actively teaches the wrong thing.

### D16. Is FORD_WARN_TICKS=30 too short, or is the chapter copy wrong?

> "FORD_WARN_TICKS is **30 ticks (0.5 s)** while the sibling lane telegraph gives **45 ticks (0.75 s)** and advertises its cycle in chapter copy ('time the crossing'). A tank at **~2 px/tick** needs **~40 ticks** to clear an **80px** band, so a driver who commits on the warn is still caught mid-river."

**Do nothing:** the copy tells you to time the crossing; timing it correctly still drowns you.

**Rec:** Raise to 45 to match the sibling telegraph. Cheapest fix, makes copy and rule agree, matches existing precedent.

### D17. Should the bridge deck fade in over ~10 ticks, or pop?

> "when the phase flips back to OPEN the entire plank bridge, both ramps, the beams, the shadow and the caustics appear in a single frame with only a **4-particle spray** and a 'click_dry' sfx. The close direction earns a **30-tick rising-waterline tell**; the reopen has no visual lead at all. Sim behaviour is untouched either way — this is a pure view call."

**Do nothing:** asymmetric telegraph — closing is earned, opening pops.

**Rec:** Fade it in. Pure view, no golden, ~10 ticks, and the asymmetry reads as "unfinished" without the player knowing why.

### D18. Should the revive loss readout be a 7-line itemised bill, or one summary line?

> "The revive loss readout names up to **7 items at once**… the current design reads the entire loadout back to a player who is being shot at."

**Do nothing:** a 7-line bill while under fire.

**Rec:** Collapse to one line. Nobody parses 7 items mid-firefight; the detail belongs on the debrief card.

### D19. Should the K.I.A. card name LAST STAND as the cause of run end?

> "A losing campaign card is always a LAST STAND death (the only pre-finale loss path does not exist), and the card never says so — 'DOWNED BY <x>' reads identically whether you fell at sector 1 with **6 revives banked** or inside the no-revive window."

**Do nothing:** the loss card cannot distinguish "you ran out of chances" from "you got unlucky once."

**Rec:** Name it. One string, and it is the difference between a results screen and a debrief.

### D20. Is a flat revive cost after the 3rd death the intent, now that the copy advertises it?

> "revive_cost is still flat after the 3rd death forever (solo **25/50/75/75/75…**) and this cycle correctly did not retune it — but the copy now advertises that forgiveness to the player."

**Do nothing:** unlimited cheap continues, now explicitly promised in copy.

**Rec:** Not enough to recommend — a retune needs human telemetry and `demo_input`'s is not it. Note that the copy change converted an unnoticed artifact into a promise you cannot quietly walk back.

### D21. Shop wheel plate: alpha 0.55 (hazards read through) or opaque (terrain masked)?

> "The c2 2v author cut the plate to **0.55 ON PURPOSE** so the mast, scars, drops and hazards read through during a buy; this cycle overturns that. Measured cost: a **~100px donut** of ground around a stationary soldier is now masked for the **~1s** buy, and terrain contrast through the disc drops **from ±24.3 to ±3.8 luma**."
>
> "If hazard-reading-during-buy is a real design requirement (e.g. the shop can open with a mortar marker under the player), the honest answer is not a lower alpha but pausing hazards or offsetting the wheel."

**Do nothing:** you can be killed by a hazard you could not see because the shop was over it — for 1 second, every buy.

**Rec:** Offset the wheel. This overturned a deliberate prior decision, and the entry itself names the right fix — alpha is the wrong axis.

### D22. Should the threat-chevron rail dodge the verb chip outside colorblind mode?

> "The bottom threat-chevron rail now dodges around the verb chip for the first **20-60 s** of every run (a **~258 px dead band**), trading positional accuracy of off-screen threat callouts for a collision that **only actually occurs in colorblind mode**."

**Do nothing:** every player pays 258px of degraded threat callouts for a collision only colorblind players have.

**Rec:** Gate the dodge on colorblind mode. Trivially correct.

### D23. Manned hull stops enemy rounds but not player rounds — explicit yes or no?

> "`_step_bullets:2406` still excludes `occupant >= 0`… in 2P it means a partner on foot standing behind a friend's tank is protected from enemy fire while the tank crew's own fire is unimpeded."

**Do nothing:** it is an arcade rule, undocumented.

**Rec:** Say yes and move on. You must be able to shoot out; the 2P shielding is a *good* co-op interaction, not a bug.

### D24. Should HOW TO PLAY honour the 200% TEXT SIZE setting?

> "Art.text_scale is routed only through `Art.fs()`, which no HOWTO call site uses. Verified still true after this diff. Honouring it would overflow every band the new FRAME_INNER_* constants just tightened."

**Do nothing:** the accessibility setting silently does nothing on the one screen that explains the game.

**Rec:** The worst possible place for the setting to no-op. Real scope (reflow, not a constant), but "the tutorial ignores your accessibility setting" is a shipping blocker, not a nice-to-have. Schedule it.

---

## TIER 4 — Internal / tooling scope

### D25. Should the attract bot be a representative player or a run-finisher? *(subsumes 2)*

> "The bot's new foot-sapper (main.gd::_demo_sap_target, **600-tick duty cycle**) dropped on-foot kills/1000t **from 34.23 to 30.75 across 8 seeds**. Every balance baseline in tools/ (sector_probe, sweep) that compares foot offense against a historical number is now measuring a different bot."
>
> "The tank's kills/1000t advantage went **1.31x → 1.48x** because the new foot sapper spends half the on-foot duty cycle throwing grenades at bunker WALLS (gate progress, not kills), diluting the foot denominator… (in which case it is working — **5/8 → 8/8 finishes**)."

**Do nothing:** every historical balance number in `tools/` silently compares against a different bot. Your measuring instrument moved and nothing says so.

**Rec:** Two bots. Sapper policy for attract/finishing, non-sapping policy for the balance probes. Otherwise every tank-vs-foot number in this file has an unknown bias.

### D26. Harness scope — three related "should the tests cover more" calls *(subsumes 3)*

> "force-clears the field every **800 ticks** by fiat because there is no combat-capable headless bot… it pins 'no wedge within any 800-tick window' rather than 'no wedge, ever' — the mutation run reported a **764-tick streak**, comfortably inside one window."
>
> "tools/screenshots.gd now shoots **14 moments** including REBIND and CHAPTERS, but **5 of the 12 framed modes** still have no capture at all."
>
> "The title tagline `ONE HIT. ONE WAR CHEST. NO MERCY.` (src/view/menu.gd:3758)… is NOT in the CHECK A corpus… so no automated check will ever see a false-scarcity claim written into that band."

**Do nothing:** an endless-wedge test that cannot see a 764-tick stall, 5 unscreenshotted modes, one uncheckable copy band.

**Rec:** The corpus fix is cheap — extend `_menu_text_corpus()`. Curated screenshots are fine, just say so. The 800-tick window needs a combat bot, which is a real project — **and D25 wants one too. Build it once and it pays for both.**

---

## MISFILED — defects, not owner decisions. Route to backlog.

| # | What it actually is | Fix named in the entry |
|---|---|---|
| **M1** | Layout bug. "at the left arena edge the cue plate's left edge lands at about **x = -8** and is flush-cut by the screen. Before this diff the same overflow just clipped a letter." | "the clamp floor needs to rise to **~87** (and the symmetric ceiling drop)" |
| **M2** | Allowlist hygiene. `p["in_tank"] = -1` is excluded from DEATH_LOSS_KEYS "by an accident of the regex instead" of a written justification, unlike its three documented siblings. | Add the justification or fix the regex |
| **M3** | Commit hygiene, likely stale. "The determinism goldens in this uncommitted tree were re-recorded for the camera-held stall freeze, which is NOT this cycle's work but shares the same files… If those two changes are meant to ship as separate commits, they need splitting by hand." | Split by hand — probably moot now |
| **M4** | Data migration bug. "Persisted Hall-of-Fame entries keep their old (inflated) letters with no migration, so the board will show historical S runs next to new B runs of comparable quality until it rolls over." | One-time regrade, or a version stamp on saved entries |

**Also partly misfiled:** the choke-rusher note counted inside D12 — "REAR_CAMP_TICKS' choke-rusher (sim_world.gd:6047) also reads stall_ticks and therefore stops arming inside any held arena… **it is not covered by any check**, so it is a silent behaviour change riding on the observer fix." The behaviour change was accepted; the *missing test* is a backlog item.
