# Backlog

Open defects, design calls and debt for Commander In Chief, as of **2026-07-29** (branch
`main` @ `2bedaf1`).

> ⚠️ **Read the severities sceptically — that is a rule this project paid for.** Handed-down
> reports here have repeatedly named a real smell and got the consequence wrong by a whole
> class: a "softlock" that was minor legibility, a "sector 4 wall" that was a bot that could
> not aim, a hitbox complaint that was rotor blades. Before designing a fix, enumerate every
> call site of the predicate you are about to touch and the actual damage/progress path. See
> `docs/` history and the `/triple-a-game` skill notes for the worked examples.

**Provenance.** Entries come from `/triple-a-game` runs — a multimodal reviewer judges
screenshots while a second lens reads `src/sim/` and *drives it headlessly to measure*.
Measured numbers are copied **verbatim**; a paraphrased measurement is just an opinion. Where
an entry was only reasoned about, the entry says so. This file MERGES: entries that shipped
are marked RESOLVED with their commit sha, not deleted — a decision and its outcome belong
next to each other. Several 2026-07-29 lens findings re-flag ground a commit this same run
already touched; those carry the sha inline so the next reader starts from the remainder, not
the original complaint.

**Counts this snapshot:** 17 new open (2026-07-29) · 1 new owner decision · 20 shipped this
run · older carried entries marked per-section.

---

## 1. Owner decisions — these need a human, not a fix

1. **NEW 2026-07-29 — `tools/probe_concussion_hud.gd` runs in NO automated gate.** The plan
   said to wire it into "the CI step that already runs gl_compatibility pixel smoke", but no
   such CI step exists (verified `.github/workflows/ci.yml` — every job is `--headless`). The
   CI-gated coverage is `smoke.gd`'s structural layer pin (mutation-proven); the pixel probe
   is local-only. Adding a GL-capable CI job (macOS runner, Xvfb+gl_compatibility on Linux) is
   a cost/flakiness tradeoff only the owner can call.
2. **Shop-wheel plate alpha overturns a deliberate design.** The c2 author cut the plate to
   0.55 *on purpose* so mast, scars, drops and hazards read through during a buy; a later cycle
   raised it. Measured cost: a ~100px donut of ground around a stationary soldier is masked for
   the ~1s buy, and terrain contrast through the disc drops from **±24.3 to ±3.8 luma**. If
   hazard-reading-during-buy is a real requirement, the honest answer is pausing hazards or
   offsetting the wheel — not a lower alpha. *(2026-07-29: `ee25263` shipped a shop-overlay
   scrim fix, and the lens still flags the unmasked radial menu — see §4. The alpha-design
   question above is still unanswered.)*
3. **The cue row is flush-cut at the arena edge.** It is ~167px wide including its plate, but
   `_draw_wheel` clamps `c.x` to `[78, 562]` on a 640px viewport, so at the left edge the plate
   starts at about `x = -8`. Reads as deliberate framing or as a bug. If it should never touch
   the edge, raise the clamp floor to ~87 (and drop the ceiling symmetrically).
4. **`test_no_hostile_stalls_an_endless_wave` samples in 800-tick windows** because it
   force-clears the field by fiat. It therefore pins "no wedge within any 800-tick window", not
   "no wedge, ever" — and the mutation run logged a **764-tick streak**, comfortably inside one
   window. *(Note: the stated reason — "there is no combat-capable headless bot" — is no longer
   true; `demo_input` gained endless targeting on 2026-07-26. This test can now be strengthened.)*
5. **The mg_nest teaches a second lane grammar.** Sniper/elite/ghillie/technical paint "this
   line is committed, sidestep it"; the nest paints "this line follows you". Locking the sim to
   match the others would delete the tracking rake the sim comments call deliberate, and move
   `test_determinism` GOLDEN. Keep two grammars, or lose the rake. *(2026-07-29: `37e8287`
   shipped "MG nest telegraph never fires down the drawn lane" — the honesty half. The
   two-grammars design call itself is still open.)*
6. ~~**Should the nest lead its target?**~~ **RESOLVED 2026-07-26** — `ca3ed3f` added lead
   (`SimWorld.mg_nest_led_aim`), no new sim state, view follows via `main.telegraph_dir()`,
   goldens re-recorded (only the trailing sample moved).
7. **HOW TO PLAY ignores the 200% TEXT SIZE accessibility setting.** `Art.text_scale` routes
   only through `Art.fs()`, which no HOWTO call site uses. Honouring it would overflow every
   band the `FRAME_INNER_*` constants just tightened — a real scope decision, not an oversight.
8. ~~duplicate of #6~~ **RESOLVED**.

---

## 2. Sim / gameplay defects — player-facing

### New this run (2026-07-29), measured

- **Downed-pilot ransom is geometry-locked: he walks AWAY from every reachable position, and
  the game's own camera anchor puts him out of reach.** Where: `src/sim/sim_world.gd:6355-6357`
  (eject, floored at `camera_top+120`), `:3287-3290` (walks north at `PILOT_SPEED` 1.4px/t,
  captured at `camera_top-30`), `:1428-1435` (rescue = touch within 14px, only after the 36t
  punch-out grace); comments at `:95-109`. Measured: staged the post-gunship beat headlessly
  (real `_step_gates` open path, pilot injected exactly as `_damage_boss` does) and ran **120
  strategy/offset/seed combinations** stepping the sim directly. The pilot always ejects at or
  NORTH of `camera_top+120` and always walks NORTH — away from every position the player can
  legally stand (the gate is a hard wall, so the player is always south of him). The capture
  fuse after grace is **~107 ticks**; a chasing… *(report text truncated at source)*
- **The grenade landing telegraph lies on held throws: marker + kill circle draw the 99px full
  lob while a >=0.27s press airbursts at 51px — a 48px lie, bigger than the blast ring, taught
  nowhere.** Where: `src/sim/sim_world.gd:2903-2918` (the hold/apex airburst), `:2869-2893`
  (`predict_grenade_landing` — "Airburst is deliberately NOT modelled: the marker answers where
  does it land if I let it fly"), `src/main.gd:9453-9469` (the view draws the marker + 28px
  blast circle from that prediction), `src/main.gd:5771-5777` (the dev demo bot encoding the
  rule: "TAP ... 96 px / HOLD ... ~48 px"). Measured by stepping the sim: a tapped grenade lobs
  **99px, every time**; a HELD grenade button pops the airburst at **51px** — and throws
  exactly once in 400 ticks (the buffer is edge-triggered, so holding never re-arms), while
  **6 taps** landed in the same window. The apex trips at **~16 ticks (0.27s)**, so this is…
  *(report text truncated at source)*
- **Endless miniboss is drawn and shootable for a 7s fly-in while bullets pass through it
  unanswered.** Where: sim guard at `src/sim/sim_world.gd:6446` (`endless_boss["phase_t"] >= 0`
  required for a bullet to register) + the visible presence kit at `src/main.gd:9176-9196` (the
  helicopter drawn on-screen, alpha-ramping 0.35→1.0 across the 420-tick approach). Measured:
  for **7 full seconds** the miniboss is on-screen, growing, with a real shadow — and player
  tracers pass clean through it with no spark, no ping, no `armor_block`, nothing (the bullet
  simply isn't dead). The sim comment says "unhittable and silent until arrival"; the view
  comment says the haze is meant to read "high-alt / not here yet". A visible target that eats
  a mag with zero feedback is the classic "my hits aren't regis…" *(report text truncated at
  source)*

### Carried from the 2026-07-26 snapshot — not re-verified this run

- **The tank is strictly dominant and it eats the game.** Measured **3.6× safer AND 1.44×
  deadlier per tick**, occupying **38.7% of a campaign**. It makes the on-foot game — the game
  this actually is — the worse way to play. *(Cycle 2's first fix attempt made the metric move
  the WRONG way and was rejected at closeness 56; re-measure before trusting any fix here.)*
- **Deep Endless plays a water-splash sound up to 15×/second, forever, on dry land, in a mode
  with no water.** Audible within ten seconds of deep Endless.
- **A frogman that beaches on dry land can never re-submerge**, and is stuck in that state.
- ~~**Unspent War Chest scores zero in Endless.**~~ **RESOLVED** — `d6c2aa9` ("Unspent War
  Chest worth zero score in Endless mode"). *(The 2026-07-29 lens still flags a related
  teaching gap — the HOWTO hides the 10x victory conversion; see §3.)*
- **The Riot Shield's advertised counterplay is impossible.** It says FLANK OR GRENADE;
  flanking is geometrically impossible solo because the shield re-aims at you on every hit
  test. **5,040 trials, 774 rounds reached the body, 774 blocked, zero kills.** 2P or the REND
  buff both kill it in 7–9 ticks, so the block is implemented correctly — the *advice* is
  false.
- **The anti-camp mortar punishes you for doing the objective.** A closed gate hard-pins
  `camera_top`, and the stall detector's only reset is the camera moving north — so every tick
  inside a gate arena scores as stalling while the HUD orders you to push north, which the
  sim's own clamp forbids. **46–58% of every campaign** measured as camera-pinned.
- **The victory card's letter grade is a constant.** RANK S locks in about **12% into every
  campaign** (measured 9.3% / 13.2% / 14.5% across three seeds) and ~75% of the real score
  range sits above the top grade. *(Note: `254b2a9` made the graded kill streak the simulated
  one — a different defect. The constant-grade curve above was not touched by it.)*
- ~~**Death silently deletes your Commendation token and Claymores** with no event or cue~~
  **RESOLVED this run** — shipped 2026-07-29 ("dying silently deletes an earned commendation
  and every carried claymore; the loss beat fires for the other three things it takes"); the
  loss beat now covers them. *(sha not located in this pass — find it and inline it.)*
- **Crate-chasing rusher can move TWICE in one tick** — introduced by the wedge slide fix.
- **Two movement rules revert your step with no persistent visual at all**; the one-way ledge
  has literally zero lines of view code. *(Suspicion only partly held — frequency of player
  contact was not established. Measure before acting.)*
- **The airstrike is the one supply the shared no-op guard forgot.** Buy it twice inside its
  own telegraph and you pay 200 coins for one strike — and the second purchase pushes the first
  later. *(Note: `254b2a9` measured the airstrike's net score by screen density — break-even
  ~10-11 bodies — and left the double-buy untouched.)*
- **CHAPTER SELECT / ARCADE plays a de-fanged campaign**: three movement hazards, the whole
  rear-pressure system, and every price increase are silently switched off.
- **A quarter of all enemy gunfire in the campaign is fired by a shooter drawn off the top of
  the screen**, and one telegraph in six is drawn where the player cannot see it.
- **The Recon Drone is the only lethal archetype with no telegraph.**
- **The Colossus finale is the one stage no pacing table has ever covered.**

---

## 3. Teaching / content honesty — the game says one thing, the sim does another

### New this run (2026-07-29), measured

- **WAR CHEST howto teaches spend-6x vs salvage-3x — and hides the 10x victory conversion the
  whole economy is built around.** Where: `src/view/menu.gd` — `_howto_page_warchest()`:
  `"Spend it — %d× score. What's left when you fall salvages at only %d×." %
  [SPEND_SCORE_MULT, WIPE_SCORE_MULT]` (6x / 3x), followed by "That's the choice." Rule:
  `src/sim/sim_world.gd:6147-6151` — a WIN converts the unspent chest at **10x plus 5000**
  (`score += war_chest * 10 + 5000`). Verified live: headless probe — 137-coin chest at
  Colossus death produced `banked=137 banked_score=1370`. The sim's own constants explain the
  design — `SPEND_SCORE_MULT` is "a discount against the 10x the victory payout gives an
  UNSPENT chest" (sim:421-424) and the 40% haircut exists precisely to make spend-vs-hoard a
  real trade. The teaching page pre… *(report text truncated at source)*
- **A duplicate TRIPLE SHOT capsule prints "CLAYMORES FULL" — the honest-receipt fix hardcoded
  the wrong item's name.** Where: `src/main.gd:2185-2192` — `if ev.get("kind", 0) >= 4 and
  ev.get("full", false): ... "text": "CLAYMORES FULL"`, one hardcoded string for every
  full-capsule pickup. Sim side: `src/sim/sim_world.gd:2232-2247` — `_supply_full` returns true
  for kind 6 (triple, already owned) and kind 8 (claymores at cap); `_collect_pickups`
  (:1794-1821) consumes a FREE duplicate capsule with `full: true` on the event (priced ones
  are left standing, so only free elite drops reach this). Verified live: headless probe —
  triple-owning player + kind-6 pickup produced `pickup event: kind=6 full=true cost=0`, i.e.
  the exact event that draws CLAYMORES FULL over a Triple Shot capsule. Reachable in BOTH
  modes: the elite… *(report text truncated at source)*
- **Five teaching hints stamp hardcoded key letters (E/F/Q) into verbs the rebind system can
  move — including the one that fires while you're bleeding out.** Where: `src/main.gd:2625`
  (`FEED THE WAR CHEST TO REVIVE — [E]`), `:2206` (claymore plant, `[F]`), `:4904` (`HOLD [Q]
  FOR THE SUPPLY WHEEL`), `:4909` (`HOLD [E] TO DEPLOY EARLY`), `:4914` (airstrike wheel,
  `[Q]`). All five read `Art.pad_label(...) if Art.use_pad else "<hardcoded letter>"`. The
  project ships a full keyboard-rebind system (`BIND_DEFAULTS` at main.gd:4020-4040, c1-18),
  and two sibling hints in the SAME file already read the live bind for exactly this reason —
  `:2303` uses `GameMenu.key_label(bind("grenade"))` and `:2888` uses
  `OS.get_keycode_string(bind("revive"))`, with the comment "a stamped key would have lied
  about it (and about every rebind) exactly like the old one did." *(Reasoned from code, not
  measured — the rebind path was read, not driven.)*
- **Smoke hint says "BLINDS THEIR AIM" — the MG nest, whose documented identity is suppressing
  through smoke, keeps firing aimed lethal rounds at you.** Where: `src/main.gd:2207` —
  `_hint("smoke", "SMOKE — BLINDS THEIR AIM. SHELLS STILL FALL BLIND. KEEP MOVING")`. Rule:
  `src/sim/sim_world.gd:4141-4145` — `_step_mg_nest` is "the one shooter with NO concealment
  gate (suppressing through smoke is its whole identity)"; its 3-round bursts are aimed, lethal
  `enemy_bullets` with lead (`mg_nest_led_aim`), so they are covered by neither half of the
  hint's hedge (not AIM-blinded, and not blind AREA shells). Every other aimed shooter — elite
  (:3443), sniper (:3507), technical (:3599), colossus spray (:6058), gunship spray (:6239) —
  is hard-gated by `_concealed`, so the hint's absolute first sentence is true for all of them
  and false for exactly this one ar… *(report text truncated at source)*
- **Claymore sells "IT HURTS BOTH SIDES" — its blast spares players entirely, while the
  barrel's identical fireball breaks your vest.** Where: hint at `src/main.gd:2211` ("CLAYMORE
  — PLANT WITH [%s] AWAY FROM TANKS (IT HURTS BOTH SIDES)") + HOWTO verb line at
  `src/view/menu.gd:5027` ("PLANT a claymore clear of any tank — it hurts BOTH sides.") + sim
  comment `src/sim/sim_world.gd:46` ("it hurts both sides") + the blast itself at
  `src/sim/sim_world.gd:2930` (`_explode`) and the barrel comparison at `:3016-3029`. Measured:
  an enemy-tripped claymore calls `_explode()`, which has NO player-damage scan — verified by
  stepping the sim headlessly: player standing **16px** from a claymore an enemy trips takes
  **ZERO damage** (vest intact), while the identical setup with a barrel detonation **breaks
  the vest** (`vest_break` fired) at the same 16px. The only way… *(report text truncated at
  source)*
- **Trench Gun countdown is hidden exactly when it matters — "same fan" comment is wrong: on
  Triple it's the 5-fan, and its silent expiry cuts your pellets 5→3 mid-fight.** Where:
  `src/view/hud.gd:2071` (chip gate `if p["spread_ticks"] > 0 and not p["triple"]: # redundant
  once Triple is owned (same fan)`) and the sibling expiry-urgency gate at
  `src/view/hud.gd:408` (same `and not p["triple"]` clause); the contradicting sim truth at
  `src/sim/sim_world.gd:1365-1374` (the `p["spread_ticks"] > 0 and p["triple"]` branch spawns
  the ±24° outer pair — "a 5-pellet fan, not a no-op" — at +2 ammo per trigger pull); the
  game's own pickup pitch at `src/main.gd:2208` ("TRENCH GUN — 3-ROUND FAN WHILE IT LASTS. ON
  TRIPLE IT'S A 5-WAY FAN"). Spread on a Triple owner is NOT "the same fan" — it is a 5-pellet
  fan with a doubled ammo tax, i.e. the single largest timed DPS swing… *(report text
  truncated at source)*
- **SUPPLY CALL spends a Commendation on a hidden random table — the only purchase whose
  outcome is unstated anywhere.** Where: the wheel item at `src/main.gd:424` (`{"kind": 5,
  ..., "label": "SUPPLY CALL"} # Commendation spend — costs a token`) vs the resolution at
  `src/sim/sim_world.gd:2262-2285` (`_try_token_drop`: seeded roll over kinds 0-3 filtered by
  `_supply_full`). The one spend in the game whose outcome is a dice roll is also the one whose
  terms appear nowhere — the wheel shows "SUPPLY CALL 1* — N* HELD" (name, cost, stock, no
  table, no "random"), the HOW TO PLAY pages never mention what a Commendation buys at all
  (grep over `src/view/menu.gd` and locale finds zero), and the result is only named AFTER
  release ("SUPPLY CALL — +30 AMMO", `src/main.gd:2791`). The roll only filters at the hard
  cap, so a p… *(report text truncated at source)*

### Carried from the 2026-07-26 snapshot — not re-verified this run

- **HOW TO PLAY mis-sells the Flak Vest** — says armor never stops a bullet; it stops one
  completely. That is a 60-coin purchase decision made on false information.
- **HOW TO PLAY names grenades as the thing that cracks the Colossus.** A full grenade carry
  delivers **40%** of its health, and the MG out-damages grenades **5.6×**.
- **The taught threat model is wrong.** The campaign is **68% melee**, and the endless Mast
  pulse — taught nowhere — is **27% of every hit** on the waves it is armed.
- **Raw token string shown on world pickup UI.**
- ~~**TRIPLE SHOT hint says "PERMANENT" — the sim strips it on your very next death**~~
  **RESOLVED 2026-07-29** — `96d8928`.

---

## 4. UI / visual polish

### New this run (2026-07-29)

- **Unmasked Radial Shop Menu Overlay.** Screenshot 12 (Wave Cleared shop screen): the circular
  shop icon wheel drops directly onto the active map terrain without a background dark scrim,
  darken vignette, or focal blur, causing ground sandbags and rocks to clip visually into the
  item icons. AAA titles apply a soft full-screen dark overlay (e.g. 60% black scrim with
  background blur) whenever a shop opens. *(`ee25263` shipped a fix titled exactly this on
  2026-07-29 — the lens still flags a remainder. Re-measure against HEAD before acting; the
  open item is what survived `ee25263`, not the original complaint.)*
- **Full-Screen Low-Pass Distortion Blurring the HUD.** Heavy damage hit-stop frame
  (Screenshot 5): taking near-lethal damage applies a radial screen-space chromatic blur across
  the entire frame, smearing HUD numbers, objective banners, and bottom button legends into
  double-vision pixel noise. Applying heavy screen-space shaders blindly over top-layer HUD
  elements reveals a flat single-pass camera setup rather than rendering UI on a dedicated
  overlay camera buffer. Best-in-class titles restrict high-impact combat VFX to the game-world
  layer while keeping HUD bars, scores, and text crisp on an un-distorted top pass. *(A related
  fix shipped this run — "full screen low pass distortion blurring the hud" is on the shipped
  list, sha not located (`5cfea32` covered menus only). As above: the open item is the
  remainder.)*
- **Unaligned Leaderboard Column Formatting.** Hall of Fame table screen (Screenshot 16): the
  leaderboard table header ('# RANK SCORE MODE REACHED STREAK') features uneven horizontal
  spacing where column titles crowd together irregularly, above plain, unadorned sub-panel
  framing. AAA arcade menus use pixel-precise grid alignments, crisp column dividers, distinct
  visual hierarchy between headers and entries, and glowing selector states. *(`2bedaf1` — the
  current HEAD — shipped a fix titled exactly this; the lens still flags a remainder. Verify
  against HEAD before acting.)*
- **Raw Blocky Text World Signage.** Images 3, 15, and 17 (Bounty and Cache screen markers):
  huge, flat cyan and yellow pixel-font text strings reading 'BOUNTY >' and '< CACHE' sit drawn
  flat across the lower playfield directly over rocks, sandbags, and active combat sprites
  without depth or diegetic framing. Rendering massive raw text overlays flat across
  environmental art looks like developer debug flags rather than polished UI navigational
  signposting. AAA version: anchor directional markers to screen edges or render them as
  diegetic, styled UI badges with subtle floating animations and drop shadows. *(A fix titled
  "raw blocky text world signage" shipped this run — sha not located. The open item is the
  remainder.)*
- **Static Scanline Overlay Obscuring Menu Typography.** Options menu and Control Rebind
  sub-menus (Images 18, 19): a heavy, dark horizontal scanline filter is drawn over the entire
  menu container, cutting directly across fine pixel letters and rendering small button
  callouts and option labels dim and grainy. AAA version: top-tier retro-styled titles place UI
  text overlays on an unfiltered canvas or fine-tune scanline strength so interface typography
  remains sharp, bright, and effortlessly readable.
- **Floattext spawn punch can poke ~4.5px above `band_floor` for ~2 frames** (pre-existing, not
  from this diff). `src/main.gd` floattext: `fpivot.y` is clamped to `band_floor + fsz` (10294)
  but the 1.5x spawn punch scales the ascent about the pivot, so the text top reaches
  `fpivot.y - 1.5*ascent ≈ band_floor - 4.5px` for fsz=9 during the first ~2 frames — up to
  4.5px of a punched toast intrudes into the bottom edge of the top message band when pinned at
  the floor. The new arbiter claim preserves exactly this pre-existing bound via
  `min_y = band_floor + fsz - 16.5` (10322). Self-correcting and minor: the band draws AFTER
  `_draw_fx` in the screen-anchored pass (`_draw_banners` at 6608 vs `_draw_fx` at 6593), so
  the band plate over-paints the intrusion; it lasts ~2 frames at 60fps. Verified pre-existing
  by reading HEAD's… *(report text truncated at source)*

### Carried from the 2026-07-26 snapshot — not re-verified this run

- Inconsistent pixel typography and menu padding (How To Play, Options).
- Generic box-border menu framing — reads as prototype chrome.
- WARN and LABEL wheel plates overlap by 2px, leaving a double-blended dark band.
- HALL recency band collides with the filter tab row *(introduced by the cycle-1 diff)*.
- MODES tab row pitch is too tight for the new 2-line tips.
- HOWTO "N / 5" tab counter crowds the ENDLESS tab label.
- Wheel text is the only view text that ignores the accessibility text scale (pre-existing).
- ~~**Screen-cluttering world-space text overlays**~~ **RESOLVED** — `f255cab` part 2
  (`claim_label_slot()` body written to spec AND wired: `_draw()` clears the claim list each
  frame, `_world_label` routes every world-space string through the arbiter, plate and ink move
  together; ratchet: **15,320 colliding pairs and 361 off-frame escapes → 0 and 0**).

---

## 5. Test & tooling debt

- **NEW 2026-07-29 — Engine shutdown leak ERRORs on every suite run** (pre-existing, identical
  on HEAD). Every suite run prints `ERROR: 3 resources still in use at exit` plus `WARNING:
  4383 ObjectDB instances leaked at exit`, after the PASS line. Verified pre-existing: stashed
  the entire diff (tracked + untracked), re-ran the suite on HEAD, and got the identical leak
  counts (4383 ObjectDB, 3 resources). Not from the new CanvasLayer. These fall outside the
  engine-error gate's window (the gate reads the log mid-run; these print at shutdown), so they
  never fail anything — but they are ERROR lines every run trains people to ignore, which is
  exactly how a real one gets missed.
- **NEW 2026-07-29 — `tools/probe_concussion_hud.gd` is gated nowhere** — see Owner decision
  #1; the tooling half is that the probe exists and nothing runs it.
- **`tools/probe_frame_bounds.gd` reports 44 false `[OVER]` lines** — every one the footer
  legend strip, which the real test correctly excludes and the probe does not. **Its output
  contradicts a green test**, so it will mislead whoever runs it next. Fix or delete.
- **`test_wheel_plate_masks_the_terrain` really pins alpha ≥ ~0.72, not 0.93** — the assertion
  is weaker than it reads.
- **The "two-scale" half of check 1b is vacuous** — it tests the helper, not the call sites.
- **The content-well ratchet cannot see intra-content collisions.**
- `test_menu_layout.gd:1840` pins `HALL_RECENCY_Y` against a hardcoded `66.0`.
- `src/view/menu.gd:4852` comment is now stale and untested.
- `src/main.gd` mg_nest draw-block comments still say the lane is LOCKED — no longer true.
- **No mg_nest pose exists in the capture harness**, so the visual reviewer can never see that
  fix.
- New probe scripts have been committed without their `.gd.uid` sidecars (repo convention).

---

## 6. Process / infrastructure

- **A 20-cycle `/triple-a-game` run costs ~50 hours** at the current all-Opus/high settings
  (measured: cycle 1 = 2h29m; the skill's own estimate of 12–20h predates the model change).
  Decide whether that is the right trade or whether fewer cycles is better value.
- **The endless bot plateaus around wave 11** even with the wedge fix — deep-wave endless
  remains partly unobserved, which caps how deep the difficulty telemetry can see.
- **Backlog grows faster than it drains.** One cycle drains ~1 item while the reviewers bank
  several; this is a triage queue, not a work queue, and it will not converge on its own. A
  dedicated drain mode (skip the visual reviewer, spend every slot on banked findings) is the
  obvious answer and is not built.

---

## 7. Blocked / can't be fixed right now

Real, understood, and deliberately not actionable today. Each says WHY, so nobody re-derives
the reasoning and nobody mistakes them for oversights.

- **Miniboss tier escalation stops at wave 20 — LEAVE ALONE, premise was wrong.** Escalation
  does not stop: miniboss HP is uncapped and linear (`+20 HP per 5 waves`, forever). Two
  *cadence* curves floor — mortar shells at tier 3 (**wave 15**, not 20) and spray interval at
  tier 4 (wave 20) — and both are explicit `maxi()` floors, i.e. deliberate. `README.md:133`
  already scopes its promise to "extra mortars by w15", which is exactly what the code does,
  and `tests/test_boss.gd:119` pins the cap. Adding a T4 means reversing a tested design
  decision, and the mortar act is already spacing-compressed (T3 is +40/+40/+40/+20, so a 6th
  shell fits only at ~295 with 4 ticks of act left). **Blocked on: wanting it at all.**
- **`BOSS_HIT_RADIUS` 20 vs the gunship silhouette — OWNER CALL, not a bug.** The reported
  "47px half-extent" is **rotor blades**: four 7px blades reaching the canvas edge on
  `m_heli_attack2`, which `gunship_body` does not have. Eroded, the two hulls measure **30.92
  vs 31.14 drawn px** — 0.7% apart — so there is nothing to split with a per-boss radius.
  Raising the radius makes both bosses easier to hit; that is **balance, not a fix**. Also note
  the view already draws its hit bloom and damage art at r=34 against a 20px hit disc.
  **Blocked on: a difficulty decision.**
- **Deep-wave Endless is still largely unobserved.** The scripted bot plateaus around **wave
  11** even after the wedge fix, so the difficulty telemetry cannot see past it and wave-20
  behaviour has never actually been watched by anything. **Blocked on: a better bot, or a human
  playing it.**
- **The `/triple-a-game` ledger prompt is 12,272 chars and grows with the backlog.** Measured
  2026-07-26: `ledger.json` is **45,996 chars**, of which **36,547 are backlog `detail`** (mean
  1,142, max 3,807). That whole payload is embedded in a prompt every cycle and handed to a
  model whose only job is to reproduce it byte-for-byte — which is exactly the setup that
  produced the documented title-drift corruption. Capping stored `detail` at ~400 chars would
  cut it **69%** and now costs nothing, since full text lives in this file. **Blocked on:
  nothing — just not done yet.** (Do not "fix" it by paraphrasing entries; the titles are
  dedupe keys.)
- **`tools/probe_frame_bounds.gd` ships knowing it emits 44 false `[OVER]` lines.** The gate
  measured this, filed it, and committed anyway. The gate now blocks on it going forward, but
  the already-committed probe is still in the tree. **Blocked on: someone fixing or deleting
  it.**
- **A 20-cycle run now costs ~40-50 hours** at all-Opus/high (measured: cycle 1 = 2h29m, cycle
  2 > 2h25m and still going). The skill's own 12-20h estimate predates the model change.
  **Blocked on: deciding whether that is the right trade.**

---

## 8. Shipped this run (2026-07-29) — resolved, kept for the record

| Finding | Commit |
|---|---|
| Unmasked Radial Shop Menu Overlay | `ee25263` — lens still flags a remainder (§4) |
| TRIPLE SHOT hint says "PERMANENT" — the sim strips it on your very next death | `96d8928` |
| Unaligned Leaderboard Column Formatting | `2bedaf1` — lens still flags a remainder (§4) |
| Subtitle speaker name duplication | `8e4ea34` |
| Incorrect biome text string on results card (victory card said JUNGLE, screen showed DESERT) | `0708419` |
| Mismatched environment stat string on victory screen | `0708419` *(likely the same defect as the row above — dedupe on next pass)* |
| Abrupt water tile transitions without shore blending | `a81a8cc` |
| MG nest's 30-tick aim lane drawn but never fired down, HUD says dodge it | `37e8287` |
| Planting a claymore in the direction you're aiming kills you 4 ticks later | `2fe8b00` |
| Gate 4 route fork is a fake choice — one lane holds every reward, the other none | `23019c2` / `0e93888` |
| 40-coin sandbag plants on your firing axis and eats 100 of your own outgoing rounds | `170c8d9` |
| Buying the same item off the ground pays 67% more score than the wheel | `254b2a9` (crate `cost*10` vs wheel `cost*6` → both now `SPEND_SCORE_MULT`; measured: 30-coin ammo crate +300 / wheel +180 → both +180) |
| Endless unspent War Chest worth exactly zero score | `d6c2aa9` |
| Dying silently deletes an earned Commendation and every carried claymore | sha not located this pass |
| Screen-cluttering world-space text overlays | `f255cab` |
| Severe UI layering clutter during boss battles | `f255cab` *(likely — verify on next pass)* |
| Full-screen low-pass distortion blurring the HUD | sha not located this pass — lens still flags a remainder (§4) |
| Raw blocky text world signage | sha not located this pass — lens still flags a remainder (§4) |
| Subtitle box fails to clear or fade out | sha not located this pass |

### Resolved 2026-07-26 (for context)

`bc75b0f` sandbag no longer eats the buyer's own rounds · `ca3ed3f` MG nest leads its target ·
`3f1c11e` MG nest telegraph made honest · the four unclamped gated cooldowns · the VP parade ·
ten retired entity bakers · the endless bot's aim · fork-gate island coords (`0421d8a`) · the
claymore self-kill (`2fe8b00`).

---

## 9. Notes on how to read this file

- **Entries marked RESOLVED stay in place** so a decision and its outcome stay adjacent. Keep
  doing that.
- **The loop writes this file itself** at the end of each run and MERGES rather than
  overwrites. Hand-edits are safe, but expect it to reorganise entries into the same section
  headings.
- **The backlog grows faster than it drains** (~4 banked vs ~1 fixed per cycle). That is what
  an honest audit of a real codebase looks like — but it means this file is a **triage queue,
  not a work queue**, and it will not converge on its own.
- **Where an entry has no measured number, it says so.** Treat those as suspicions, not
  findings — this project has repeatedly had a real smell reported with the consequence wrong
  by a whole severity class.
- **Three report bodies arrived truncated at source** (marked "report text truncated at
  source"). The surviving measurements are verbatim; the missing tails were reasoning, not
  numbers.
- The 2026-07-26 snapshot this file replaces was already marked STALE against
  [`FINDINGS.md`](FINDINGS.md) (62 of 115 entries already fixed at re-triage on 2026-07-28).
  Carried entries above are marked "not re-verified this run" for the same reason: trust the
  measurement, re-verify the predicate before fixing.
