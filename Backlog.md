# Backlog

Open defects, design calls and debt for Commander In Chief, as of **2026-07-26 22:30**.

**Provenance.** Most entries came from `/triple-a-game` runs — a two-lens review where a
multimodal reviewer judges screenshots and a second lens reads `src/sim/` and *drives it
headlessly to measure*. Almost every number below was measured, not estimated; where something
was only reasoned about, it says so. The live source is `.aaa/ledger.json` in the run's worktree
(gitignored, so this file is the durable copy).

**Read the severities sceptically — that is a rule this project paid for.** Handed-down reports
here have repeatedly named a real smell and got the consequence wrong by a whole class: a
"softlock" that was minor legibility, a "sector 4 wall" that was a bot that could not aim, a
hitbox complaint that was rotor blades. Before designing a fix, enumerate every call site of the
predicate you are about to touch and the actual damage/progress path. See
`docs/` history and the `/triple-a-game` skill notes for the worked examples.

**Counts:** 32 open · 14 shipped · 2 dismissed · 7 owner decisions (2 now resolved).

---

## 1. Owner decisions — these need a human, not a fix

The loop refused to guess at these. They are product calls, and they are the highest-value
output of a review.

1. **Shop-wheel plate alpha overturns a deliberate design.** The c2 author cut the plate to 0.55
   *on purpose* so mast, scars, drops and hazards read through during a buy; a later cycle
   raised it. Measured cost: a ~100px donut of ground around a stationary soldier is masked for
   the ~1s buy, and terrain contrast through the disc drops from **±24.3 to ±3.8 luma**. If
   hazard-reading-during-buy is a real requirement, the honest answer is pausing hazards or
   offsetting the wheel — not a lower alpha.
2. **The cue row is flush-cut at the arena edge.** It is ~167px wide including its plate, but
   `_draw_wheel` clamps `c.x` to `[78, 562]` on a 640px viewport, so at the left edge the plate
   starts at about `x = -8`. Reads as deliberate framing or as a bug. If it should never touch
   the edge, raise the clamp floor to ~87 (and drop the ceiling symmetrically).
3. **`test_no_hostile_stalls_an_endless_wave` samples in 800-tick windows** because it
   force-clears the field by fiat. It therefore pins "no wedge within any 800-tick window", not
   "no wedge, ever" — and the mutation run logged a **764-tick streak**, comfortably inside one
   window. *(Note: the stated reason — "there is no combat-capable headless bot" — is no longer
   true; `demo_input` gained endless targeting on 2026-07-26. This test can now be strengthened.)*
4. **The mg_nest teaches a second lane grammar.** Sniper/elite/ghillie/technical paint "this line
   is committed, sidestep it"; the nest now paints "this line follows you". Locking the sim to
   match the others would delete the tracking rake the sim comments call deliberate, and move
   `test_determinism` GOLDEN. Keep two grammars, or lose the rake.
5. ~~**Should the nest lead its target?**~~ **RESOLVED 2026-07-26** — `ca3ed3f` added lead
   (`SimWorld.mg_nest_led_aim`), no new sim state, view follows via `main.telegraph_dir()`,
   goldens re-recorded (only the trailing sample moved).
6. **HOW TO PLAY ignores the 200% TEXT SIZE accessibility setting.** `Art.text_scale` routes only
   through `Art.fs()`, which no HOWTO call site uses. Honouring it would overflow every band the
   `FRAME_INNER_*` constants just tightened — a real scope decision, not an oversight.
7. ~~duplicate of #5~~ **RESOLVED**.

---

## 2. Gameplay / sim defects — player-facing, measured

- **The tank is strictly dominant and it eats the game.** Measured **3.6× safer AND 1.44× deadlier
  per tick**, occupying **38.7% of a campaign**. It makes the on-foot game — the game this
  actually is — the worse way to play. *(Cycle 2's first fix attempt made the metric move the
  WRONG way and was rejected at closeness 56; re-measure before trusting any fix here.)*
- **Deep Endless plays a water-splash sound up to 15×/second, forever, on dry land, in a mode
  with no water.** Audible within ten seconds of deep Endless.
- **A frogman that beaches on dry land can never re-submerge**, and is stuck in that state.
- **Unspent War Chest scores zero in Endless.** Campaign/colossus victory pays `chest×10 + 5000`;
  an endless wipe pays nothing — inverting the intended hoard-vs-spend tradeoff.
- **The Riot Shield's advertised counterplay is impossible.** It says FLANK OR GRENADE; flanking
  is geometrically impossible solo because the shield re-aims at you on every hit test.
  **5,040 trials, 774 rounds reached the body, 774 blocked, zero kills.** 2P or the REND buff
  both kill it in 7–9 ticks, so the block is implemented correctly — the *advice* is false.
- **The anti-camp mortar punishes you for doing the objective.** A closed gate hard-pins
  `camera_top`, and the stall detector's only reset is the camera moving north — so every tick
  inside a gate arena scores as stalling while the HUD orders you to push north, which the sim's
  own clamp forbids. **46–58% of every campaign** measured as camera-pinned.
- **The victory card's letter grade is a constant.** RANK S locks in about **12% into every
  campaign** (measured 9.3% / 13.2% / 14.5% across three seeds) and ~75% of the real score range
  sits above the top grade. The last thing a player sees says the same thing whether the run cost
  2 deaths or 210.
- **Death silently deletes your Commendation token and Claymores** with no event or cue — the
  `player_down` event flags triple/pierce/spread losses but omits these.
- **Crate-chasing rusher can move TWICE in one tick** — introduced by the wedge slide fix.
- **Two movement rules revert your step with no persistent visual at all**; the one-way ledge has
  literally zero lines of view code. *(Suspicion only partly held — frequency of player contact
  was not established. Measure before acting.)*
- **The airstrike is the one supply the shared no-op guard forgot.** Buy it twice inside its own
  telegraph and you pay 200 coins for one strike — and the second purchase pushes the first later.
- **CHAPTER SELECT / ARCADE plays a de-fanged campaign**: three movement hazards, the whole
  rear-pressure system, and every price increase are silently switched off.
- **A quarter of all enemy gunfire in the campaign is fired by a shooter drawn off the top of the
  screen**, and one telegraph in six is drawn where the player cannot see it.
- **The Recon Drone is the only lethal archetype with no telegraph.**
- **The Colossus finale is the one stage no pacing table has ever covered.**

## 3. Teaching / content honesty

- **HOW TO PLAY mis-sells the Flak Vest** — says armor never stops a bullet; it stops one
  completely. That is a 60-coin purchase decision made on false information.
- **HOW TO PLAY names grenades as the thing that cracks the Colossus.** A full grenade carry
  delivers **40%** of its health, and the MG out-damages grenades **5.6×**.
- **The taught threat model is wrong.** The campaign is **68% melee**, and the endless Mast pulse
  — taught nowhere — is **27% of every hit** on the waves it is armed.
- **Raw token string shown on world pickup UI.**

## 4. UI / visual polish

- Inconsistent pixel typography and menu padding (How To Play, Options).
- Generic box-border menu framing — reads as prototype chrome.
- WARN and LABEL wheel plates overlap by 2px, leaving a double-blended dark band.
- HALL recency band collides with the filter tab row *(introduced by the cycle-1 diff)*.
- MODES tab row pitch is too tight for the new 2-line tips.
- HOWTO "N / 5" tab counter crowds the ENDLESS tab label.
- Wheel text is the only view text that ignores the accessibility text scale (pre-existing).

## 5. Test & tooling debt

These came from the gate auditing its own diffs — the highest-yield source in the loop, and the
one finding class that is *not* re-derived next run.

- **`tools/probe_frame_bounds.gd` reports 44 false `[OVER]` lines** — every one the footer legend
  strip, which the real test correctly excludes and the probe does not. **Its output contradicts
  a green test**, so it will mislead whoever runs it next. Fix or delete.
- **`test_wheel_plate_masks_the_terrain` really pins alpha ≥ ~0.72, not 0.93** — the assertion is
  weaker than it reads.
- **The "two-scale" half of check 1b is vacuous** — it tests the helper, not the call sites.
- **The content-well ratchet cannot see intra-content collisions.**
- `test_menu_layout.gd:1840` pins `HALL_RECENCY_Y` against a hardcoded `66.0`.
- `src/view/menu.gd:4852` comment is now stale and untested.
- `src/main.gd` mg_nest draw-block comments still say the lane is LOCKED — no longer true.
- **No mg_nest pose exists in the capture harness**, so the visual reviewer can never see that fix.
- New probe scripts have been committed without their `.gd.uid` sidecars (repo convention).

## 6. Process / infrastructure

- **A 20-cycle `/triple-a-game` run costs ~50 hours** at the current all-Opus/high settings
  (measured: cycle 1 = 2h29m; the skill's own estimate of 12–20h predates the model change).
  Decide whether that is the right trade or whether fewer cycles is better value.
- **The endless bot plateaus around wave 11** even with the wedge fix — deep-wave endless remains
  partly unobserved, which caps how deep the difficulty telemetry can see.
- **Backlog grows faster than it drains.** One cycle drains ~1 item while the reviewers bank
  several; this is a triage queue, not a work queue, and it will not converge on its own. A
  dedicated drain mode (skip the visual reviewer, spend every slot on banked findings) is the
  obvious answer and is not built.

---

## 7. Blocked / can't be fixed right now

Real, understood, and deliberately not actionable today. Each says WHY, so nobody re-derives the
reasoning and nobody mistakes them for oversights.

- **Miniboss tier escalation stops at wave 20 — LEAVE ALONE, premise was wrong.** Escalation does
  not stop: miniboss HP is uncapped and linear (`+20 HP per 5 waves`, forever). Two *cadence*
  curves floor — mortar shells at tier 3 (**wave 15**, not 20) and spray interval at tier 4
  (wave 20) — and both are explicit `maxi()` floors, i.e. deliberate. `README.md:133` already
  scopes its promise to "extra mortars by w15", which is exactly what the code does, and
  `tests/test_boss.gd:119` pins the cap. Adding a T4 means reversing a tested design decision,
  and the mortar act is already spacing-compressed (T3 is +40/+40/+40/+20, so a 6th shell fits
  only at ~295 with 4 ticks of act left). **Blocked on: wanting it at all.**
- **`BOSS_HIT_RADIUS` 20 vs the gunship silhouette — OWNER CALL, not a bug.** The reported "47px
  half-extent" is **rotor blades**: four 7px blades reaching the canvas edge on `m_heli_attack2`,
  which `gunship_body` does not have. Eroded, the two hulls measure **30.92 vs 31.14 drawn px**
  — 0.7% apart — so there is nothing to split with a per-boss radius. Raising the radius makes
  both bosses easier to hit; that is **balance, not a fix**. Also note the view already draws its
  hit bloom and damage art at r=34 against a 20px hit disc. **Blocked on: a difficulty decision.**
- **Deep-wave Endless is still largely unobserved.** The scripted bot plateaus around **wave 11**
  even after the wedge fix, so the difficulty telemetry cannot see past it and wave-20 behaviour
  has never actually been watched by anything. **Blocked on: a better bot, or a human playing it.**
- **The `/triple-a-game` ledger prompt is 12,272 chars and grows with the backlog.** Measured
  2026-07-26: `ledger.json` is **45,996 chars**, of which **36,547 are backlog `detail`** (mean
  1,142, max 3,807). That whole payload is embedded in a prompt every cycle and handed to a model
  whose only job is to reproduce it byte-for-byte — which is exactly the setup that produced the
  documented title-drift corruption. Capping stored `detail` at ~400 chars would cut it **69%**
  and now costs nothing, since full text lives in this file. **Blocked on: nothing — just not done
  yet.** (Do not "fix" it by paraphrasing entries; the titles are dedupe keys.)
- **`tools/probe_frame_bounds.gd` ships knowing it emits 44 false `[OVER]` lines.** The gate
  measured this, filed it, and committed anyway. The gate now blocks on it going forward, but the
  already-committed probe is still in the tree. **Blocked on: someone fixing or deleting it.**
- **A 20-cycle run now costs ~40-50 hours** at all-Opus/high (measured: cycle 1 = 2h29m, cycle 2
  > 2h25m and still going). The skill's own 12-20h estimate predates the model change.
  **Blocked on: deciding whether that is the right trade.**

## 8. Other / notes

- **Two entries in section 1 are marked RESOLVED rather than deleted** so a decision and its
  outcome stay adjacent. Keep doing that.
- **The loop now writes this file itself** at the end of each run (the `Report` phase) and MERGES
  rather than overwrites. Hand-edits here are safe, but expect it to reorganise entries into the
  same section headings.
- **The ledger's backlog count grows faster than it drains** (~4 banked vs ~1 fixed per cycle).
  That is what an honest audit of a real codebase looks like — but it means this file is a
  **triage queue, not a work queue**, and it will not converge on its own.
- **Where an entry has no measured number, it says so.** Treat those as suspicions, not findings —
  this project has repeatedly had a real smell reported with the consequence wrong by a whole
  severity class.

## Resolved 2026-07-26 (for context)

`bc75b0f` sandbag no longer eats the buyer's own rounds · `ca3ed3f` MG nest leads its target ·
`3f1c11e` MG nest telegraph made honest · the four unclamped gated cooldowns · the VP parade ·
ten retired entity bakers · the endless bot's aim · fork-gate island coords · the claymore
self-kill.
