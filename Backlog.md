# Backlog

Open defects, design calls and debt for Commander In Chief, as of **2026-08-14** (branch
`overnight/2026-08-14-aaa-4` @ `35e24bb`; previous snapshot was `main` @ `390c12d`,
2026-07-31).

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
next to each other. Several lens findings re-flag ground a commit the same run already
touched; those carry the sha inline so the next reader starts from the remainder, not the
original complaint.

**Counts for the 2026-08-14 all-loops run:** 58 new open findings · 16 new owner decisions
(merged down from 23 handed-in items — near-duplicates were folded together with **both**
measurement sets kept verbatim, nothing dropped) · 8 titled fixes shipped. Several handed-in
items re-flag ground a commit *in the same run* already touched; those carry the sha inline so
the next reader starts from the remainder.

**Counts for the previous snapshot:** 31 new open from the run (2026-07-31) **+ 2 audit-lens findings
banked the same day** (PERFECT DODGE band, riot-shield drawn plate — §3, adversarially
CONFIRMED by the parallel audit sweep) · 6 new owner decisions · 10 shipped in
the 2026-07-31 window (5 clean, 5 with flagged remainders) · older carried entries marked
per-section.

---

## TODO — opening combat and readability follow-up (2026-08-01)

- [x] Stagger ordinary riflemen's first-shot phases so a formation cannot resolve as one
  synchronized bullet wall.
- [x] Separate living troops from corpse piles: living threats keep the warm separator rim;
  bodies settle smaller, flatter, darker and desaturated.
- [x] Keep rifleman contact lethal only as a deliberate close-range risk. Riflemen stop at a
  firing line and never seek body contact; the field manual now states the remaining rule.
- [x] Add ARCADE and BOSS RUSH to both normal and large-text versions of the MODES manual.
- [x] Reduce opening clutter with a 2-second field-spawn grace, a slower pre-gate cadence,
  and a delayed first spawn from the landing-zone bunker.
- [ ] If a suicide bomber is added later, require a unique silhouette, visible fuse tell,
  dedicated approach behavior and an explosion payoff. Ordinary riflemen are not bombers.
- [x] Pin splash skipping with a regression test: the skip press is marked handled and
  returns before the title menu can activate its default row.
- [ ] Run the opening with a genuinely new player. Pass target: 8/10 first encounters reach
  the seawall, identify the rifleman's painted lane, and can explain any death without help.
  If fewer pass, lengthen the grace by 30 ticks before reducing enemy damage or cadence.

---

## 1. Owner decisions — these need a human, not a fix

1. **`tools/probe_concussion_hud.gd` runs in NO automated gate.** The plan said to wire it
   into "the CI step that already runs gl_compatibility pixel smoke", but no such CI step
   exists (verified `.github/workflows/ci.yml` — every job is `--headless`). The CI-gated
   coverage is `smoke.gd`'s structural layer pin (mutation-proven); the pixel probe is
   local-only. Adding a GL-capable CI job (macOS runner, Xvfb+gl_compatibility on Linux) is
   a cost/flakiness tradeoff only the owner can call. *(Re-flagged 2026-07-31, unchanged.)*
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
9. **NEW 2026-07-31 — Hulk salvage at grenade cap is a cover-destroying no-op.** The untracked
   `tools/probe_salvage.gd` in this tree measures that a player at `GRENADE_AMMO_MAX` salvaging
   a smoldering hulk gets `_try_salvage_hulk` returning true, event n=0 (+0 grenades), and the
   hulk's `burn_ticks` stripped **100 → 0** — the cover is destroyed for zero gain. The sim
   docstring (`sim_world.gd:2392-2395`) frames strip-vs-keep as a deliberate trade ("keep the
   wall or take the ammo"), and the shop's own `_supply_full` rule refuses no-op purchases
   everywhere else ("none of them can bill for a no-op", `tests/test_shop.gd:249`) — so either
   salvage should refuse at cap (keep the wall) or the docstring's trade framing should be
   narrowed. A +0 "trade" is not a decision the player can read, but reversing the documented
   choice is the owner's call. The defect entry lives in §2. *(`probe_colossus.gd`, the other
   orphan probe, runs clean: seed 0xC0FFEE engage_t=288 fight_ticks=683 downs=3 victory=true.)*
10. **NEW 2026-07-31 — The flat airstrike deny removes the skilled "pre-call".** Buying in the
    last ~44 intermission ticks so the strike lands mid-trickle clips ~4 enemies; `8425bd7`'s
    deny kills that line. The plan weighed freezing `pending_airstrike` instead and rejected it
    (view countdown + lead-prediction + checksum ordering). If the owner considers the pre-call
    a feature worth keeping, the freeze alternative is the only honest route back — the deny
    makes that trade-off permanent.
11. **NEW 2026-07-31 — ghillie and sapper still have no working separator rim.** Their
    `_LIGHT_RIM` entries remain dead behind the OUTLINE gate, same root cause as the
    `m_soldier2` defect this cycle fixed. The plan deliberately deferred them: ghillie's cloak
    subtlety is the mechanic and sapper is a non-shooter with a satchel pip. If a future pass
    rims them, the same three-registry pattern (OUTLINE + `_UNIT_RIM` + `_LIGHT_RIM`) and the
    same source-derived test shape apply.
12. **NEW 2026-07-31 — The warm-light rim visibly enlarges/brightens the infantry silhouette
    slightly** (measured **~120 changed px per ~18px sprite**). This is the a1-02 separator
    class working as designed, but it is an aesthetic call: the rim reads as a soft glow
    outline rather than a hard keyline. If the owner prefers subtler separation, `_LIGHT_RIM`'s
    **2.2px width** is the single knob.
13. **NEW 2026-07-31 — An abandoned daily now leaves NO Hall/leaderboard trace of the
    attempt.** `d45132a` deliberately chose arm+demote over the finding's alternative of
    banking the quit with its standing score — the daily board only ever shows the one
    completed run. If the owner wants "attempted, abandoned" visible on the daily leaderboard,
    that is a product call, not a defect.
14. **NEW 2026-07-31 — A spent-daily re-deal keeps the SAME board as unranked practice**
    rather than re-seeding a fresh layout — `d45132a`'s chosen behavior; a fresh-seed practice
    would play differently and is equally defensible.

### New owner decisions from the 2026-08-14 all-loops run

15. **NEW 2026-08-14 — Is the COURIER meant to be catchable?** (`696db74`) Post-fix the demo
    bot kills **0 of 13 couriers (13/13 escape)** where HEAD killed **1 of 5**. Every escape
    now fires the deny sting and "GOT AWAY!", which *is* the fix — but a bounty that announces
    its own escape 100% of the time is a different feel from one that vanished silently.
    Measured with the scripted bot over **6 endless seeds × 12,000 ticks**: HEAD **1 kill / 17
    spawned**, post-fix **0 kills / 13 spawned, 13 escapes**. Killing one pays `COIN_ELITE * 4`
    (`sim_world.gd:3295`), so a player now hears the deny sting and loses a fat bounty **1–3
    times per run** unless they actively shoot the runner. It IS catchable on paper —
    **COURIER_SPEED 2.160 px/tick vs PLAYER_SPEED 2.400**, with **156–218 ticks (2.6–3.6 s)**
    of on-screen time crossing the full **360px** view — but a scripted bot that
    advances-and-shoots without chasing catches zero, and **nothing in this repo measures a
    human**. If the intent is "most players catch it", `COURIER_SPEED` or the `+300` spawn
    wants tuning; if the intent is "a fat prize you mostly miss", it is already right. Nobody
    has stated which.
16. **NEW 2026-08-14 — The 100% manual pages call `Art.text` directly, which never
    translates.** The 125%+ pager path does. At 100% in es/fr/ja the CONTROLS page is English
    and the enlarged one is not. Not the reported tell and not touched this run, but the fix
    expands every line **~25%** into the same content well this run's diff is already making
    fit — so single-sourcing the CONTROLS copy and translating it is a product decision about
    when to take that hit.
17. **NEW 2026-08-14 — `marked` bounty elites and drones leave the field south with no event
    at all** (**15 of 84 across 6 runs**, per the run's own triage). `696db74` deliberately
    excludes them from `ESCAPE_EVENT` on the grounds that an unclaimed bounty you walked past
    is not a modeled loss and has no copy. That is defensible, but it *is* a call: firing a
    deny sting **15× per run** for advancing north would itself read as a tell, and doing
    nothing means three of the things the objective locator points at resolve on two different
    rules. The exclusion is a design position, not a measurement — if an unclaimed bounty is
    supposed to read as a loss, it needs **copy first and the registry second**.
18. **NEW 2026-08-14 — TRIPLE SHOT is an UNDECLINABLE 120-coin auto-purchase with no drop
    verb.** (`4d493b7`) The Endless intermission shop still sells it at `SHOP_TRIPLE_COST 120`
    (`sim_world.gd:454`) via `CRATE_POOL` (`:464`), and `_collect_pickups` still **auto-debits**
    on proximity inside `PICKUP_RADIUS 12px` with no way to refuse (`tools/probe_triple_shop.gd`:
    chest **999 → 879 in one step**). The finding said the fix must reprice or remove that pool
    entry; the run deliberately left it, arguing 120 coins now buys a genuine upgrade —
    **measured 45.24 kills/100 rounds vs the bare gun's 38.09, never below 1.00 hits/round at
    any range or body**. Whether an undeclinable auto-purchase is acceptable *even for a good
    item* is a product call; the auto-debit is unchanged and still cannot be refused.
    Separately, there is still **no drop verb**: `sim_world.gd:2130 _respawn` (via
    `DEATH_LOSS_KEYS :2095`) remains the only removal path. With `fan_cost` gone that is
    ordinary arcade grammar (Contra/Ikari), and `src/main.gd::_loss_summary` now NAMES it in
    the receipt so the strip is no longer anonymous — but if the intent was that a player be
    able to shed a mod voluntarily, that verb was never built and this run did not build it.
19. **NEW 2026-08-14 — The stacked 5-fan is now the top of the upgrade ladder and strictly
    free.** (`4d493b7`) Trench Gun + Triple now delivers **up to 5.00 hits per ONE billed
    round** against a **34px** colossus body and **3.00** against everything else inside
    **~45px**, with **no ammo premium at all**. The invariant the fix was built on (never worse
    per round than the bare gun) forces `fan_cost = 0`, but it does not force the pellets to
    stay at full damage — cutting per-pellet damage was the plan's own listed alternative and
    was not taken. If the 5-fan trivialises close-range boss DPS, **the knob is per-pellet
    damage, not the price**.
20. **NEW 2026-08-14 — The 2026-07-24 decision that "ammo must be a real sink while a fan is
    held" is now unreplaced.** `fan_cost` went to 0 with no compensating penalty (the finding
    also offered "drop `fan_cost` to 0 AND cut per-pellet damage"; the run took only the first
    half). Measured on the repo bot over **4 seeds × 6000 ticks**: rounds billed **2350 → 2122
    (−9.7%)** while kills rose **895 → 960** — a Triple-holder's ammo pressure is genuinely
    *lower* than the base gun's. Correct direction for the reported defect; whether the ammo
    economy wants a different brake for fan holders is the owner's call.
21. **NEW 2026-08-14 — Suppress the far pickup tag, or widen the label ladder?** (`4d493b7`,
    `35e24bb`) The fix suppresses the FAR tag rather than fixing the arbiter's
    **13px-plate-on-11px-stride** overlap: every label plate is `size + 5` = **13px** tall while
    `LABEL_ROWS` strides **11px**, so adjacent rungs overlap by 2px and the 13-rung ladder
    yields only **~7 usable rows**. Widening the stride to 13px would give the full 13 rows and
    cut suppression, but it moves every world label's dodge geometry and would ripple through
    the existing layout ratchets — deliberately out of scope. The current tree picks "show
    fewer labels correctly" over "widen the ladder so more fit", and has the ratchets to keep
    it, but it means **a loot cluster is permanently under-labelled by design**.
22. **NEW 2026-08-14 — The fork signpost now has a hard 3.0 s life from first visibility.**
    (`7d26648`) A player who chooses to fight AT the fork loses the CACHE/BOUNTY labels
    permanently for that band and can never re-read the lane choice (the camera ratchet cannot
    go back; the sim never re-emits `route_fork`). Measured: an uninterrupted march clears the
    sign **on position at 96 ticks**, so the cap only ever bites the player who stops —
    precisely the player most likely to still want the information. The sign is born at
    **fy = −20** and the position fade zeroes it at **fy = 210**, i.e. **230 px of camera
    travel**, while the player's own screen band sits below that, so the plate is purely an
    advance telegraph in both designs. If the intent is "stop shouting" rather than "forget",
    the alternative is a floor (decay to ~0.25 instead of 0.0), a re-arm when the band re-enters
    the top third, or gating the cap on combat rather than wall time. The run did not guess.
23. **NEW 2026-08-14 — `BAND_SIGN_REACH` is 120 px symmetric, which implements "name it while
    you are choosing", not "name it while you are crossing".** (`7d26648`) Northbound, the
    PERMANENT FORD plate opens **120 px before the near bank** and closes **40 px past the far
    bank** (`WATER_H` is **80 px**), so the label is gone for the last stretch of the crossing
    itself. Measured live it still covers **71.6%** of the band's on-screen ticks. At
    `PLAYER_SPEED 144` that is **0.83 s** of warning before the south bank. The test pins the
    literal `120.0` so widening it is a deliberate act — but nobody has stated what the intended
    reading distance for a permanent crossing is, versus the `deck_open` / `tank_near` gates its
    siblings use, which are **state**-based rather than distance-based.
24. **NEW 2026-08-14 — Is 2.85 s the right read budget for a pinned-down player?**
    `SIGN_LIFE_HOLD_TICKS=120` / `SIGN_LIFE_DECAY_TICKS=60` gives a stalled player **2.85 s** of
    full-alpha legible signpost before it dissolves (measured, pinned-from-cull, seeds
    `0xC0FFEE`/1P and `42`/1P: **171 fully-on-screen ticks at peak alpha 1.00**). Gating the
    decay on "combat started in this band" was an allowed alternative; the code ships the
    time-only version.
25. **NEW 2026-08-14 — Nothing replaces the dissolved fork plate for a player who was still
    deciding.** After **180 ticks** the only remaining lane cue is the wreck-island geometry and
    the lane-tinted wire strips (verified visually — they all survive the dissolve). There is
    currently **no re-arm and no compact fallback** (e.g. a lane-tinted chevron at the island).
    Owner call whether the geometry alone is a sufficient telegraph.
26. **NEW 2026-08-14 — The WAR CHEST page is now at zero slack, and a line of voice paid for
    it.** (`35e24bb`) The authorial flourish *"Nothing pays like the chest you carry home."* had
    to be cut to fit the new, longer rule sentence — measured: keeping it puts the lowest
    content ink at **y=298** against a BACK plate top of **y=297**, **one pixel over**, and
    `SUITE=menu_layout` goes red. The next rule that needs stating on this page costs another
    sentence of voice. Accept the plainer page, or give the WAR CHEST tab a second authored page
    so copy and taste stop competing for the same 1px.
27. **NEW 2026-08-14 — Should a crate price tag whose plate clips the frame by 1px be DRAWN
    66px from its crate, or SUPPRESSED?** (`35e24bb`) The shipped guard chooses "drawn" (plate
    merely intersects the frame). Measured cost: **6.8% of drawn tags at 100% TEXT SIZE and
    12.9% at 200%** land **>22px** from what they name, **max 66px**. "Suppressed unless
    majority on-frame" would cut that further but silently hides prices for crates entering from
    the top of the screen — exactly when a player most wants to know what one costs. Someone who
    knows the intended reading distance should pick.
28. **NEW 2026-08-14 — Should a revive pay score at all?** (`35e24bb`) The copy now truthfully
    says "REVIVING scores nothing", and the ratchet tracks the sim in either direction (proven:
    crediting revives at `SPEND_SCORE_MULT` makes the test demand "6×" in the REVIVING clause
    and go red on the current copy). But the finding measured revives at **~40–50% of all chest
    outflow** in a revive-heavy 2P campaign run, with the foregone **6×** worth **~14% of final
    score**. Telling the player plainly that half their coin buys zero points may now read as a
    penalty on co-op play rather than a neutral rule. Crediting it is a balance decision
    (goldens move, revive becomes score-positive, death-farming becomes viable); the copy fix
    does not foreclose it.
29. **NEW 2026-08-14 — At 200% TEXT SIZE the new rule splits across a line break.** "BUYING
    scores 6× per coin" / "— REVIVING scores nothing.", with the em dash leading the second line
    (see `/tmp/shots4/wc-200.png`). Both halves are on the same subpage (**3 of 4**) so nothing
    is hidden, and the pager will re-flow with any future font — but if the two rates must read
    as one unbreakable clause at large text it needs an **explicit non-breaking construction**,
    not a hope about wrap points.
30. **NEW 2026-08-14 — A suppressed floattext toast is now permanently dropped.**
    `src/main.gd:11873` sets `fx['sup'] = true` ("dropped for good — no flicker as congestion
    shifts"). A toast that spawns entirely below the frame is killed on its first tick instead
    of being hunted up into view as it rises. Every such event is off-screen when it happens, so
    the run judged this correct — but it IS a behaviour change to reward feedback that the owner
    may want to see in play before it ships.

---

## 2. Sim / gameplay defects — player-facing

### New in the 2026-08-14 all-loops run, measured unless noted

- **Dying is the cheapest resupply in the game — and the code's own stated invariant says it
  must not be.** WHERE: `src/sim/sim_world.gd:2112-2113` (`_respawn` hands back `MG_AMMO_MAX/2`
  = **49 rounds** and **4 grenades**), the invariant comment at `:2111` ("test: dying must be
  worse EV than one 30-coin ammo buy"), `revive_cost` at `:984-1001`, `_supply_cost` at
  `:2410-2429`, `_econ_scale` at `:2351-2373`. Solo-campaign `revive_cost` is
  `REVIVE_BASE_COST * mini(deaths,3) / 2` — **25 / 50 / 75, HARD CAPPED at 75** for the rest of
  the run. Shop prices are `base + base * depth / 4`, uncapped by design, so the two curves
  diverge for the whole campaign. Measured straight off the sim's own functions
  (`.aaa/probe_feel.gd` price ladder): **depth 0: ammo(30rd)=30, grenade(4)=30 → buying
  49rd+4 grenades = 90c; a death costs …** *(report text truncated at source)*. A second,
  independently-run lens reached the same place from the other end and adds: the broke fallback
  in `_step_dead_player :1939-1960` with `BROKE_RESPAWN_TICKS=300` at `:261`; `_supply_cost`
  `:2415-2434` / `_econ_scale` `:2355-2379`; solo self-revive stands you up **where you fell**
  (`_try_revive :2070-2078`); and `VEST_IFRAME_TICKS=90` gives **1.5 s of invulnerability** on
  the way back up. Every other price in the game scales **+25% per gate opened**; the death
  price does not.
- **"A FLAK VEST eats ONE hit" is false in exactly one place — and the vest is still on your
  corpse.** WHERE: `src/sim/sim_world.gd:2858` (`_step_tanks`, bail-window expiry) calls
  `_kill_player(players[ci])` **DIRECTLY**. Every other lethal touch in the entire sim funnels
  through `_hurt_player` at `:2140`, whose own docstring calls itself "the AUTHORITATIVE copy of
  the rule" and which checks `hurt_iframes`, `_exposed()`, and then spends the vest. A grep of
  the whole file finds exactly **two** callers of `_kill_player`: `_hurt_player` itself (`:2157`)
  and this one line. The promise is stated verbatim to the player **twice**:
  `src/view/menu.gd:5174` and `:5358` — "ROLL to dodge — you can't be hit mid-roll. A FLAK VEST
  eats ONE hit." MEASURED (`.aaa/probe_vest.gd`, direct sim construction): a player with
  `vest = true` boards a tank … *(report text truncated at source)*.
- **The MG Nest has no engagement range — it opens an aimed tracking burst on you from ~300px
  beyond the top of the screen.** WHERE: `src/sim/sim_world.gd:4537` —
  `if e["fire_cd"] == 0 and dlen > F_ONE and target["alive"]:` opens a 3-round tracking burst.
  Every other ranged archetype gates on a standoff constant (**RIFLEMAN_STANDOFF 100, ELITE
  120, DRONE 130, GRENADIER 150, SNIPER 240**). The nest has `MG_NEST_AIM_TICKS`,
  `MG_NEST_LEAD_CAP`, `MG_NEST_BURST_*` — and **no range term at all**. `dlen > F_ONE` means
  "not standing on me". MEASURED (`.aaa/probe_nest.gd`, 4 campaign seeds, full runs to
  victory): **8–24 shots or aim-locks per run fired from more than 60px ABOVE the top of the
  viewport, peaking at 308px above (seed 2, t=1074), 302px (seed 1), 301px (seed 3), 251px
  (seed 0xC0FFEE)**.
- **A 60px strip below the drawn viewport where rooted MGs run their whole aim telegraph and
  rake you — the tell is spent entirely off-screen.** WHERE: `src/sim/sim_world.gd:20`
  (`VIEW_H := 360`), `:3523` (`if not e['alive'] or e['y'] > camera_top + 420 * F_ONE:` — the
  ONLY enemy cull), `:4556-4566` (`_step_mg_nest`'s fire gate, no range limit of any kind),
  `:219-222` (`MG_NEST_AIM_TICKS 30`, `BURST_ROUNDS 3`), `:4531-4540` (each round **RE-AIMS** at
  the current nearest player); `project.godot:27-28` (viewport **640x360**). The drawn viewport
  is exactly `[camera_top, camera_top+360]`; enemies are culled at `camera_top+420`. That is a
  **60 px band — one sixth of a screen height** — in which hostiles are fully alive, fully
  targeting, and completely undrawn. *(Same root as the entry above, filed by a second lens from
  the geometry side; fix once at the fire gate and both close.)*
- **The campaign has no failure ramp — it is free for 88% of the run, then instantly
  terminal.** WHERE: measured with `tools/probe_feel_g.gd` (8 seeds, campaign, repo bot);
  `last_stand` gating in `sim_world.gd:1060` and `_step_dead_player :1937-1938` ("Last Stand:
  dead is dead — no timer, no coin reader"), `_latch_wipe :1008-1027`, and the god-mode
  early-return at `:1015-1022`. With god mode **ON**, all 8 seeds finish: Last Stand is **12.2%
  of playtime (8584 of 70586 ticks)** and takes **16.7% of knockdowns (45 of 270)** — a **1.37×**
  rate, not a spike. With god mode **OFF** the picture inverts completely: **7 of 8 seeds
  reached Last Stand and ALL 7 died there** — **6510, 6127, 7016, 6559, 5843, 13759, 11891
  ticks, `gates_open=5` every time**, after having already been knocked down **14 to 44 times
  apiece** with zero c… *(report text truncated at source)*.
- **"Flank it" is not a real counter to the SHIELD past ~77px, and the manual lists it first.**
  WHERE: manual copy `src/view/menu.gd:5524` — "SHIELD — front eats bullets. Flank it, blast it,
  or use Rend."; `SHIELD_TURN_STEP := F_ONE/32` at `sim_world.gd:185`, `_shield_blocks` 120-degree
  cone at `:4375-4396`, `_turn_shield_toward :4399-4436`, stepper `:3605-3612`. The plate turns
  at a fixed tangent step of **1/32 per tick = 1.79 deg/tick**. A player orbiting at
  `PLAYER_SPEED` (**2.4 px/tick**) turns at **137.5/R deg/tick**, so the two are equal at
  **R = 76.8px** — beyond that the shieldman out-turns you and the front arc never opens.
  Measured with `tools/probe_feel_h.gd` (orbit at full player speed, firing inward, shield
  pinned so only the turn race is tested, 1200 ticks = 20 seconds): **r=30px best angle off …**
  *(report text truncated at source)*.
- **The War Chest stops being a decision by sector 3 unless you spam the wheel.** WHERE:
  `_supply_cost`'s own criterion, `sim_world.gd:2422` — "Test: end-of-sector chest should stay
  under ~3 affordable buys"; `_econ_scale :2355-2379`; buy edge gate `:1160-1161`; caps in
  `_supply_full :2436-2462`. Measured with `tools/probe_feel_b.gd`, 4 seeds, campaign, god mode,
  chest sampled at every `gate_open` against the cheapest wheel price. A bot that never buys
  ends **gate 1 with 7 affordable buys, gate 2 with 12–22, gate 3 with 40–51, gate 4 with
  50–67, gate 5 with 49–73** — **16 to 24 times the code's own stated ceiling** — peaking at a
  **5350-coin** chest. A bot pulsing the wheel every 2 ticks through all five kinds lands at
  **1–4 aff…** *(report text truncated at source)*.
- **The courier — a whole archetype with its own art, sting and 4x bounty — never appears in
  the campaign.** WHERE: `_spawn_courier sim_world.gd:4444-4456`; its ONE caller is
  `sim_world.gd:6229` inside `_start_wave` (`:6120`), which `step()` only reaches on the endless
  branch (`:1084`). Supporting content that exists anyway: `COURIER_SPEED :112`, the 4x bounty
  at `:3294`, the flee path and escape event `:3563-3578`, `ESCAPE_EVENT :120`, the "courier"
  sprite bake and draw at `src/main.gd:9920-9924`, the audio sting `"courier_escape"` at
  `src/main.gd:573`, and the hint card "COURIER — 4x BOUNTY, GUN IT DOWN" at `src/main.gd:388`.
  An event/roster census across all three modes (`tools/probe_feel_c.gd`, 24000 ticks each)
  shows **courier=510 enemy-ticks and courier_escape=3 in endless, and exactly zero couriers in
  ca…** *(report text truncated at source)*.
- **Endless fires the ghillie decloak cue 209 times per ghillie — and a cloaked ghillie is
  immune to everything, not just the blasts the hint names.** WHERE: the anti-stall forced
  reveal `src/sim/sim_world.gd:6058-6073` (`if all_cloaked: … e['submerged'] = false;
  e['surface_ticks'] = GHILLIE_REVEAL_TICKS; events.append({'t': 'frogman_surface', …})`), the
  ghillie's own cloak/recloak `:3989-3994` and `:4018-4023`, `GHILLIE_REVEAL_TICKS 26` /
  `GHILLIE_RECLOAK_TICKS 90` at `:200-201`; immunity sites `:3009` (bullets skip `submerged`),
  `:3189` (blasts), `:2233` (airstrike), `:4147` (mines), `:4219` (barrels); `src/main.gd:379`
  (the hint) and `:566`, `:2447-2448`, `:2835-2838` (the view turns **every** `frogman_surface`
  into a positional SFX + particle burst). Measured with `tools/probe_frog.gd`, 20,000 ticks per
  run: **endless seed 0xC0FFEE …** *(report text truncated at source)*.
- **A cloaked GHILLIE is immune to every weapon in the game and counted in HOSTILES — while the
  strictly milder FROGMAN got the chip that exists to explain exactly that.** WHERE:
  `src/view/hud.gd:1417-1418` (`if e["alive"] and e["kind"] == "frogman" and
  e.get("submerged", false): immune_lurker = true`) and the chip it drives at `:1441-1453`
  ("GRENADES ONLY"), against `src/sim/sim_world.gd:3009` (player bullets skip `submerged`),
  `:3189` (`_explode` explicitly exempts `e["kind"] == "ghillie" and e.get("submerged")` —
  grenades, claymores, mines and barrels **all** route through here), `:2235` (`_fire_mission`,
  the 100-coin airstrike, skips `submerged`), `:1133-1134` (`_enemy_strikeable` — contact and
  the empty-clip bash), and `:6086-6088` (`_wave_hostiles_cleared` skips only `pilot`). Drawing:
  `src/main.gd:10153-10157` — a submerged ghillie is **one 5px circle at alpha 0.10–0.16**.
  *(Note `d5c7931` "cloaked ghillie now immune to blast" made the blast immunity deliberate; the
  open half is the missing HUD chip and the HOSTILES count.)*
- **The claymore crate costs 6.7× a grenade crate per detonation for the identical explosion,
  plus arming delay and self-damage.** WHERE: `src/sim/sim_world.gd:451`
  (`SHOP_GRENADE_COST := 30`), `:455` (`SHOP_CLAYMORE_COST := 50`), `:464-466`
  (`CRATE_POOL` / `CRATE_POOL_BASE` — both crate slots, both scaled by the same `_econ_scale`),
  `:2247-2249` and `:2261` (`_apply_supply`: kind 1 grants **+4 grenades**, kind 8 grants **+1
  claymore, cap 3**), `:3173-3195` (`_explode` — the ONE blast function), `:4152-4158` (claymore
  detonation calls `_explode(m['x'], m['y'])` after hurting every exposed player in
  `GRENADE_RADIUS`), `:3160-3170` (grenade detonation calls the same `_explode`), `:58`
  (`CLAYMORE_ARM_TICKS 20`). Both resolve through the same `_explode` with the same
  `BLAST_KILL_RADIUS` — **no damage, radius, or frag-bonus difference**.
- **The operation brief names a zone whose signature hazard is one whole zone further north —
  FOUNDRY WORKS has zero heat vents.** WHERE: `src/sim/sim_world.gd:396-402` (`ZONE_INFO`),
  `:537` (`VENT_START_SEG := 4`), `:5117` (`if v_seg >= VENT_START_SEG`), `:533`
  (`MARSH_SEG := 2`), `:3094-3096` (`grenade_drift`'s `if g_band != MARSH_SEG … return 0`),
  `:977-982` (`zone_info`), `:936-975` (`jump_to_chapter`); `src/main.gd:4106-4112` (the
  gate-open zone banner); `src/view/menu.gd:1085` (CHAPTER SELECT blurb). Gates sit at
  **y = −1000·k** (measured, identical in all 4 seeds). `ZONE_INFO[k-1]` is "the zone
  culminating in gate k", so zone k occupies **y in (−1000(k−1), −1000k]**, i.e. band index
  `absi(y)/GATE_SPACING` = **k−1**. Every world/hazard system instead compares that **0-based**
  band index against constants authored as if it w… *(report text truncated at source)*.
- **STAGING GROUND promises two bunkers and fields four; BRIDGE GUNSHIP promises none and fields
  one.** WHERE: `src/sim/sim_world.gd:397` ("STAGING GROUND … Two bunkers, no surprises — learn
  the rules here"), `:398-399` ("BRIDGE GUNSHIP … no bunkers here, the boss IS the lock");
  bunker sources `:5771` (authored LZ bunker at y=−420), `:5049-5055` (streamed row every 1000px
  at odd 500-multiples: −500, −1500, −2500, …), `:5226-5229` (the gate-arena **PAIR**, stamped
  for every non-boss gate). Measured with `tools/probe_bunkers.gd`, attributing every bunker by
  its own y, 4 seeds — output **byte-identical on all four** (the layout is fully deterministic):
  **zone1 = 4 bunkers at y [−420, −500, −950, −950]** (brief: "Two bunkers") · **zone2 = 3 at
  [−1500, −1850, −1960]** · **zone3 = 1 at [−2500]** …
- **The endless clear-bar's denominator is the wave budget, but the courier is spawned outside
  it — 13 of 57 wave openings pin the gauge at empty.** WHERE: `src/view/hud.gd:1425-1435` —
  `remaining = alive + sim.wave_pending + boss` against
  `wave_total = WAVE_BASE_ENEMIES + WAVE_ENEMIES_PER_WAVE * (sim.wave - 1) + boss`, fed to
  `_mini_bar(…, 1.0 - remaining/wave_total, …)` — vs `src/sim/sim_world.gd:6123`
  (`wave_pending = WAVE_BASE_ENEMIES + WAVE_ENEMIES_PER_WAVE * (wave - 1)`, exactly the HUD's
  denominator) and `:6228-6229` (`if wave >= 3 and rng.range_i(0, 2) == 0: _spawn_courier()` —
  which appends straight to `enemies[]` at `:4454` and **never decrements `wave_pending`**).
  `_mini_bar` clamps the fraction to `[0,1]` at `hud.gd:2304`, so on any wave that fields a
  courier the wave opens with one more live non-pilot body than the bar's own denominator.
- **Pickups are NEVER swept — a passed-by crate or capsule keeps an objective diamond pointing
  at an unreachable spot forever (predates this run).** Verified by source enumeration on the
  `aaa-4` worktree, unchanged from HEAD: `pickups[]` has exactly **four** removal sites, all
  deliberate — `sim_world.gd:1932` (player collects), `:3639` (`drop_stolen`), `:5855` and
  `:5876` (shop pack-up when the intermission ends). There is **no camera-sweep counterpart** to
  the `enemies[]` sweep at `:3523`. Meanwhile `main.gd`'s `_draw_objective_markers` iterates
  `sim.pickups` (`main.gd:12366`) and marks priced crates and `kind >= 4` capsules. So in
  CAMPAIGN, where the camera ratchets north, any free capsule or priced crate the player walks
  past stays in `pickups[]` for the rest of the run and keeps an edge diamond pointing at a world
  position outside `_clamp_actor`'s reachable ban… *(report text truncated at source)*. Separate
  array, separate lifecycle, deliberately out of scope this cycle — **but it is the same shape of
  defect as the courier and nothing guards it.**

#### Checked and did NOT hold — recorded so the next cycle does not re-spend the budget

- **Off-screen shooters are fully covered.** Suspicion: enemies live from `camera_top-24` down to
  `camera_top+420` but are only DRAWN in `0..360` (`main.gd:9576` culls at `epos.y < -60`), and
  `_draw_threat_pips` (`main.gd:12995-13001`) lists only sniper/grenadier/ghillie/drone/
  technical/mg_nest — omitting rusher and elite, the two most common shooters. MEASURED
  (`.aaa/probe_feel.gd`, 8 runs): every shot fired from above the top edge, bucketed by kind and
  offset. **Rusher never exceeded 25px above, elite never exceeded 24px** — both inside the 180px
  ba… *(report text truncated at source)*. A second census over campaign, **3 seeds × 6,000
  ticks**, windup→0 edge-detected per enemy with its screen-y captured on the firing tick: shots
  fired from above the viewport were **sniper 2.5% (81 shots), mg_nest 1.9% (513), rusher 0.7%
  (538), elite 0.0% (143), grenadier 0.0% (7), technical 0.0% (11)**. The advancing camera pushes
  spawns into view before their first shot. **DOES NOT HOLD.** *(Note: this is the same geometry
  the mg_nest entries above DO confirm — the nest is the one tenant that genuinely abuses the
  band. Enumerate per-kind before generalising.)*
- **The pilot rescue objective is winnable; the instrument just never tries.** WHERE: pilot eject
  `sim_world.gd:6788-6797`, `PILOT_SPEED`/`PILOT_FLOOR :98-110`, the touch grab `:1538-1545`,
  `PILOT_PUNCHOUT_TICKS :124`. Across **16 real runs** (campaign + boss_rush, 8 seeds each, repo
  bot — `tools/probe_feel_d.gd`) **32 pilots ejected, 31 were lost to the top edge, 1 was gunned
  down, and ZERO were rescued — 0%**, against the sim's own documented target of "mid-arena catch
  rate should land 50-70%". That looked damning. It is not: replacing the bot's blind march with
  a homing chase from tick 0 succeeds up to **395px of initial separation**, against a **median
  observed eject separation of 178px and a maximum of 506px**. The objective is comfor…
  *(report text truncated at source)*. **DOES NOT HOLD — it is an instrument limit.**

### From the 2026-07-31 run, measured unless noted

- **2P ready-up is a unanimous party vote with no tally — holding E alone does nothing,
  forever, with zero on-screen explanation.** Where: rule at `src/sim/sim_world.gd:5405-5418`
  (`_ready_up` — "True while EVERY living player holds REVIVE and nobody is down"), counter at
  `:5439-5445` (`ready_hold` resets to 0 any tick the unanimity breaks; 20 ticks to deploy,
  `READY_HOLD_TICKS` at `:402`), hint at `src/main.gd:4913-4915` (`HOLD [%s] TO DEPLOY EARLY`).
  MEASURED: headless 2P endless probe — reached a real intermission (300t window), had P1 hold
  revive alone for 180 ticks: intermission ran 300→120, `ready_hold` never left 0 (P1's entire
  3-second hold was discarded every tick). Both players then holding: deployed in exactly 20
  ticks. And `ready_hold` has ZERO view reads (grep over `src/main.gd` + `src/view/hud.gd` —
  none). *(Report text truncated at source.)*
- **Daily Run teaches "one attempt" — but the lock only arms at the debrief, so QUIT TO TITLE /
  RESTART makes today's seed infinitely scoutable.** Where: taught rule at
  `src/view/menu.gd:5136` ("One shared seed a day, one attempt."); the lock's only write at
  `src/main.gd:4753-4758` (`_daily_done_seed = _current_seed` inside `_record_run`); the only
  caller chain is `_apply_score_verdict` (`src/main.gd:4709`) ← the debrief trigger at
  `src/main.gd:4928-4943`, which fires on `sim.victory or sim.wiped or last-stand-all-down`.
  The exit paths — pause menu "QUIT TO TITLE" (`src/view/menu.gd:3185-3188`) and "RESTART"
  (`:3183-3184`) — call `main._reset()` directly, which runs `_flush_bests()`
  (`src/main.gd:1855`) that touches only best/hint sections, never the daily lock.
  *(`d45132a` shipped the arm+demote behavior this run — owner decisions #13/#14. The lens
  still flags the scouting remainder; the open item is what survived `d45132a`.)*
- **DAILY RUN's "one attempt" is only enforced at the debrief — R/RESTART before the wipe
  retries the same seed, unlocked, forever.** Where: copy at `src/view/menu.gd:5136`; the lock
  write at `src/main.gd:4753-4759` (`_daily_done_seed` written ONLY in `_record_run`); the
  restart path at `src/main.gd:1434-1452` (`_reset()` → `_flush_bests()` persists only
  `best`/`seen` — the daily seed is untouched) and `:1770-1776` (R key → `_reset()`).
  MEASURED live against the real main scene headlessly: `start_daily()` → seed 1017050458,
  `daily_done()==false`; play 240 real ticks; call `_reset()` (the R-key path) → same seed
  1017050458, `daily_done()==false`, `_daily` still true — unlimited retries. *(Near-duplicate
  of the entry above from a second lens — kept because its measurement is independent.
  `d45132a` shipped; this is the flagged remainder.)*
- **NG+ HARD scores ~1.58x a normal campaign and lands on the same Hall of Fame and Steam
  leaderboard with no marker — the board flags *ASSIST and *DAILY but not the toggle that
  inflates score.** Where: `src/main.gd:1459` (`sim.hard = _hard and not _endless and ...` —
  campaign only, and `_hard` is a free RUN SETUP toggle at `src/view/menu.gd:3090-3092` with no
  unlock gate); the board entry at `src/main.gd:4726-4733` (`_record_run` tags `assist` and
  `daily` — no `hard` key); the Steam upload at `:4787+` (`_steam.upload_score(sim.mode,
  score)` — 'campaign' for both rulesets). MEASURED: same scripted bot, same 4 seeds, god mode,
  12,000 ticks each: normal campaign scores [131775, 104669, 142093, 151981] (mean ~132.6k,
  1136 kills) vs hard [265621, 172361, 206247, 194341] (mean ~209.6k, 1934 kills) — **+58%
  score, +70% kills**, because harder spawning is more income (elites pay 25c vs 10c).
  *(Report text truncated at source.)*
- **Grenade-family hits on bosses emit no `boss_hit` feedback event (bullets do).**
  `_explode`'s campaign-gate branch (`sim_world.gd:3002-3005`) and endless branch (`:3012-3016`)
  call `_damage_boss` without emitting `boss_hit`, while `_bullet_hits_boss` (~`:6300`) emits
  it — so grenade/barrel/mine hits on a boss produce none of the hit-flash/hit-stop feedback
  bullets get. Confirmed pre-existing by reading HEAD: the fly-in fix only added the `phase_t`
  conjunct and left the event asymmetry untouched (the plan's brief explicitly named it out of
  scope). Fix shape: emit the same `boss_hit` event from `_damage_boss`'s non-lethal arm, or
  from both `_explode` boss branches, and extend the fly-in test's post-arrival arm to assert
  the event. *(Reasoned from code, not driven.)*
- **A salvaged or expired tank hulk keeps burning and drawing as cover while bullets fly
  straight through it.** Where: sim cover predicate `src/sim/sim_world.gd:2750-2756` (player
  bullets) and `:6443-6449` (enemy bullets) — both `not hk["alive"] and hk["burn_ticks"] > 0`,
  lifetime `HULK_TICKS=1050` (17.5s) at `:445`, instant-strip at `:2405` (salvage sets
  `burn_ticks=0`). View: `_hulks` pool `src/main.gd:5409-5416` (appended on death, persists to
  an 8-cap eviction at `:5435`), wreck sprite + scorch drawn unconditionally at
  `:10702-10715`, and the big flame envelope at `:10531-10539` keyed on view-time `h["t"]`
  (~8s fade), which NOTHING in the sim touches. What happens: the game teaches "dead tanks are
  cover while they smolder" — but the visible fire runs on a view-side 8s clock, the sim's
  cover runs on a 17.5s sim clock, and … *(report text truncated at source)*
- **Salvaging a hulk at full grenades strips your cover for +0 ammo — the one supply path that
  still bills for a no-op.** Where: `src/sim/sim_world.gd:2397-2408` — `_try_salvage_hulk`
  clamps `p["grenade_ammo"]` to `GRENADE_AMMO_MAX` and unconditionally sets
  `tank["burn_ticks"] = 0` (ends the cover), even when the clamp grants +0; the view receipt at
  `src/main.gd:2793-2795` ("FULL UP — COVER STRIPPED"). The rule it breaks is written in the
  sim's own `_supply_full` docstring at `:2239-2241`: "shared by every path that hands out a
  supply so none of them can bill for a no-op". MEASURED: headless probe
  (`tools/probe_salvage.gd`) — player at 12/12 grenades interacts with a smoldering hulk:
  salvage returns true, grenades **12 → 12** (event grants n=0), hulk `burn_ticks` **100 → 0**.
  The cover cost is real: dead hulks block bullets both ways. *(Fix direction is owner decision
  #9.)*
- **The Colossus siege restocks grenades in total silence — the one fight balanced on grenade
  income never announces the drop.** Where: `src/sim/sim_world.gd:6131-6136` — the siege drop
  block in `_step_colossus` does a bare `pickups.append` (kind 1, no event, no `drop` field);
  compare the endless wave drop at `:5857-5861` which fires `supply_drop` → cargo chime
  (`src/main.gd:462`), "SUPPLY DROP — HOLD IT" toast + ground light (`:2845-2849`) and the
  parachute/TTL drawing (`:8315+`, keyed on the `drop` field the siege pack lacks). MEASURED
  headlessly (`tools/probe_colossus.gd`, 4 seeds, god_mode, arcade jump to `FINAL_GATE_INDEX`):
  the finale runs **663-899 ticks** with **3-5 downs** and **2 core windows** (healthy pressure
  — no tuning claim), and spawns **3-4 grenade packs per fight with ZERO announce**; the sim
  comment at `:6131` says these drops "keep the g…" *(report text truncated at source)*
- **The shop bills full price for air it partially delivers: a "+30 AMMO" buy at 90/99 grants 9
  rounds for the full 30 coins, "+4 GRENADES" at 10/12 grants 2 — and the label, the receipt
  floattext, and the token-drop callout all still print the full amount.** Where:
  `src/sim/sim_world.gd:2093-2095` (`_apply_supply` caps with `mini(MG_AMMO_MAX, +30)` /
  `mini(GRENADE_AMMO_MAX, +4)`), `:2239-2247` (`_supply_full` — the no-op guard shipped in
  `e57191b` — only returns true AT the cap, never near it), `:2300-2342` (`_try_buy` debits the
  full `_supply_cost` regardless of headroom), `:2262-2298` (`_try_token_drop` filters on the
  same hard-cap-only test); view side: static labels "AMMO +30" / "GRENADES +4" at
  `src/main.gd:419-421`, full-amount receipts `BUY_FLOAT` "+30 AMMO" / "+4 GRENADES" at
  `src/main.gd:426` printed on every buy (`:2384`) and token drop (`:2792`). MEASURED by
  stepping the sim headlessly: ammo buy at 90/99 → now 99 (delivered 9), charged 30; grenade
  buy at 10/12 → del… *(report text truncated at source)*
- **The revive's whole go-to-the-body grammar — body beacon, dashed tether, off-screen chevron
  "so the revive has a spatial target" — signposts a dangerous rescue run the sim does not
  require: E revives from ANY distance and teleports the partner to your row.** Where:
  `src/sim/sim_world.gd:1928-1962` (`_try_revive` — loops all dead players, checks only
  `war_chest >= cost`; no distance test anywhere; the revived player lands at `reviver["y"]`)
  vs the view's spatial rescue kit at `src/main.gd:10139-10148` (rising beacon "pulls their eye
  to the body"), `:10899-10915` (off-screen chevron whose comment says the cue exists "so the
  revive has a spatial target"), `:9815-9818` (off-screen partner chevron). MEASURED: 2P sim,
  killed P2, walked P1 300px north, called `_try_revive(0, p1)` — P2 `alive:true`, teleported
  **~284px** to P1's row, chest debited 50. The game invests three separate rendering systems
  in telling the player WHERE the body is and building the fi… *(report text truncated at
  source)*
- **A tank parked directly on a free supply crate collects nothing and says nothing — the
  biggest object on the field rolls over a glowing pickup with zero effect or feedback.**
  Where: `src/sim/sim_world.gd:1107-1109` (`_step_players`: the `in_tank` branch calls
  `_drive_tank` and `continue`s before `_collect_pickups` at `:1454-1456`, so riders and
  gunners can never collect), vs the gate-cache crate the sim plants dead-center in the only
  path north at `:4246-4248` (x = `SCREEN_CX`). MEASURED: boarded a tank directly onto a free
  grenade crate at 0 grenades, stepped 10 ticks — grenades still 0, crate still on the ground,
  no deny event, no cue. The tank's tread grammar already touches everything else it rolls over
  — it crushes infantry, flattens sandbags, detonates barrels, and even RESCUES the pilot on
  contact — so "drove over the crate, nothing happened" reads as a bu… *(report text truncated
  at source)*
- **Closed gates pin the camera — and the spawner keeps planting rooted MG nests 24px above
  the viewport, so 4-6 invisible, unflankable turrets fire lead-computed bursts into the game's
  longest fights (including the no-revive finale).** Where: `src/sim/sim_world.gd:3969-3971` —
  `_step_spawner` plants rooted units at `camera_top - 24 * F_ONE` (`_spawn_mg_nest` for
  `SECTOR_SPECIALS` sectors 3 and 6, `_spawn_broadcast` for sector 5). The player's northern
  clamp is `camera_top + 16` (`_clamp_actor`, `:1784`) and a closed gate pins the camera at
  `g["y"] - GATE_CAMERA_PAD` (`:4624`), so while any gate fight lasts, a rooted spawn sits 24px
  above the top edge and 40px above the furthest point the player can ever stand — for the
  whole fight. MEASURED (6 campaign seeds via `.aaa/probe_offscreen_nests.gd` +
  `.aaa/probe_offscreen_attr.gd`): peaks of **4-6 rooted nests/broadcasts** piled up above the
  pinned edge during stage-3 (gunship) gate … *(report text truncated at source)*
- **Endless 2P: a broke death respawns FREE after 5s whenever a partner is up — the mode's
  only death brake (the compounding revive price) is waived exactly when you can't pay, so
  spend-to-zero is the dominant strategy.** Where: `src/sim/sim_world.gd:1863-1870` —
  `_step_dead_player`'s broke-timer expiry calls `_respawn(p, _checkpoint_y())` (free) whenever
  `rally_is_free()` (`:1913-1921`), which is true in endless the moment any partner is alive;
  only a full-party down latches the wipe. MEASURED (`.aaa/probe_broke_respawn.gd`): endless
  2P, wave 10, `revive_cost` 900 vs chest 10 — the downed player respawns at exactly **tick
  300** with cost=0, a fresh 49-round clip and 4 grenades. Dying solvent costs the full
  compounding price (50 × deaths × (1+wave/5), uncapped — **4600 by wave 16** in the economy
  probe); dying broke costs 5 seconds and pays a partial restock worth **~45+ coins** at
  wave-10 shop prices. *(Report text truncated at source.)*
- **"WAVE CLEARED — SHOP OPEN" fires while a live Spotter is still shelling the shop window.**
  Where: `src/sim/sim_world.gd` — `_wave_hostiles_cleared` (`:5670`) iterates only `enemies`;
  the Mortar Observer is a separate top-level dict spawned on SPOTTER waves (`:5836`) and
  exempted from every despawn in endless ("the observer living until it is shot is the
  documented, intended pressure", `:6562-6566`); its strike loop (`:6575-6585`) runs every tick
  regardless of intermission; the wave-clear + Clean Wave bonus evaluate at `:5583-5600`;
  `deaths_this_wave` resets at `_start_wave` (`:5712`). View: "WAVE CLEARED — SHOP OPEN" banner
  (`src/main.gd:2946`). MEASURED (`.aaa/probe_c6_spotter.gd`, seed 7): wave 3 rolls SPOTTER,
  observer up; wave-clear fired with `observer_alive=true`; 276 shop ticks followed … *(report
  text truncated at source. `390c12d` shipped "the endless milestone shop window is a kill zone
  the game itself calls threat-free" this run — the lens still flags the Spotter remainder; the
  open item is what survived `390c12d`.)*
- **Miniboss fly-in airstrike window remains a partial whiff.** The endless intermission is now
  gated because `enemies` is provably empty for the whole 45t telegraph (`_step_waves`
  early-returns; strike resolves before `_start_wave`) — that half shipped in `8425bd7`. The
  wave-5+ miniboss fly-in is a second window where `_fire_mission` (`:2071`) spares bosses, but
  the trickle keeps spawning so it is NOT provably empty — the plan explicitly banked it. A
  strike bought during the fly-in still kills only trickle infantry. *(Reasoned, not driven —
  banked by the plan.)*
- **A tank driver's (or gunner's) revive key is a fully swallowed input the HUD is actively
  prompting — the arbitration mutes the cannon for a rescue the sim never performs.** Where:
  `src/sim/sim_world.gd:1114-1117` (`if p["in_tank"] >= 0: _drive_tank(...); continue`) — the
  `continue` skips the only alive-player revive read at `:1402` (`if inp.revive:
  _try_revive(i, p)`), and neither `_drive_tank` (`:2446`) nor `_ride_as_gunner` (`:2549`) ever
  reads `inp.revive`. The arbitration that sends the key there is `main.gd:5897-5909`
  (`revive_context` rule 3: "YOU ARE UP AND A PARTNER IS DOWN -> revive") and `main.gd:5983-5993`
  (`shared_e` mutes the grenade route when the context is live). MEASURED
  (`tools/probe_tank_revive.gd`, headless, steps the sim directly): 2P campaign, P1 boarded in
  a live tank, P2 downed, chest 500 vs cost 50 — `revive_…` *(report text truncated at source)*
- **Grenades and every blast kill the cloaked, bullet-immune ghillie — the sim's own "only the
  reveal window can kill it" rule, its HOWTO card, and the airstrike's submerged exemption all
  say otherwise.** Where: `src/sim/sim_world.gd:2961-2974` (`_explode`'s enemy scan: `if
  e["alive"] and e["kind"] != "pilot" and _dist_lte(..., BLAST_KILL_RADIUS)` — no `submerged`
  exemption), vs the same file's `_fire_mission` at `:2071-2087` which deliberately spares
  `e.get("submerged", false)` ("Spares the submerged (1986 rule)"), vs the archetype's own
  contract at `:3717-3722` ("Killing it during the reveal/paint window defuses the shot — and
  that window is the only time it can be killed at all"), vs the HOWTO card
  `src/view/menu.gd:5262` ("GHILLIE — hidden sniper; only its laser gives it away. Close in.").
  MEASURED (`tools/probe_ghillie_blast.gd`, headless): a cloaked (`submerged=true`) ghillie
  20px from the … *(report text truncated at source)*
- **The supply receipt lies on partial stocks: wheel buy and SUPPLY CALL print "+30 AMMO" /
  "+4 GRENADES" while the sim clamps the grant to as little as +1 — at full price.** Where:
  `src/sim/sim_world.gd:2098-2101` (`_apply_supply` clamps: `mg_ammo = mini(99, +30)`,
  `grenade_ammo = mini(12, +4)`), `:2310-2360` (`_try_buy` charges the FULL `_supply_cost` and
  emits `{"t":"buy","kind":kind}` with no granted amount), `:2283-2309` (`_try_token_drop`
  spends the Commendation and emits the same amount-less `token_drop` event), `src/main.gd:429`
  (`BUY_FLOAT = ["+30 AMMO", "+4 GRENADES", ...]`), `src/main.gd:2419-2421` (the buy floattext
  prints `BUY_FLOAT[kind]` verbatim), `src/main.gd:2828-2830` (SUPPLY CALL prints
  `"SUPPLY CALL — " + BUY_FLOAT[kind]`). The `_supply_full` guard only denies at the hard cap
  (99 / 12), so the whole partial window is live: ammo 70-98, gre… *(report text truncated at
  source. Near-duplicate of the full-price-partial-delivery entry above from a second lens —
  kept because it pins the receipt-lie half, the other pins the charge half.)*
- **Deep-endless veteran armor silently kills the empty-clip bash — the game's only free
  defense — exactly in the depth band that needs it.** Where: `src/sim/sim_world.gd:1335-1339`
  (the bash routes through `e["hp"]` exactly like a bullet: hp>1 bodies eat the swing as an
  `armor_block` chip) × `:5427-5436` (`_wave_armor` gives EVERY rusher/elite/special +1 hp from
  wave 13, +1 more every 6 waves) × `:1298-1299` (the bash's own contract: "running dry is a
  beat of danger, not pure helplessness"). MEASURED (controlled ring, tools probe stepping the
  sim: 12 identical rushers closing on a dry player holding fire, god mode, only hp varied):
  **hp=1 → 8 kills / 8 swings / 3 downs in 2400t; hp=2 → 8 kills / 16 swings / 5 downs; hp=3 →
  8 kills / 24 swings / 8 downs.** Swings-per-kill scales 1:1 with hp — the melee's lethality
  is 1/hp, i.e. a bullet's. *(`f6666b8` shipped the invisibility half this run — banner/chip
  for the armor term. The bash-consequence above is the open remainder.)*
- **Colossus closed core: MG tracers phase through the final boss with zero contact feedback
  for ~73% of the fight.** Where: `src/sim/sim_world.gd:2862-2867` — a player bullet only dies
  on the colossus while `core_open > 0`; the conjunct failing leaves `dead=false`, so the round
  flies on THROUGH the boss body and dies at range. Core timing (`:639-640`): 240t closed /
  90t open per 330t cycle = closed **~73%** of the finale. MEASURED (colossus stood up
  directly, player parked south firing north, god mode): closed core — **72 rounds fired, 0
  boss_hit, 0 armor_block, 59 rounds observed PAST the boss's position, hp unmoved**; open
  core — 27 fired, 18 boss_hit, hp 60 → 6 (the chip path itself works). The run-long grammar
  for armor is a VISIBLE ricochet — bunkers ping `armor_block`, shields ping it, wave-13
  veterans ping it … *(report text truncated at source)*
- **Endless miniboss is drawn and shootable for a 7s fly-in while bullets pass through it
  unanswered.** Where: sim guard at `src/sim/sim_world.gd:6446` (`endless_boss["phase_t"] >= 0`
  required for a bullet to register) + the visible presence kit at `src/main.gd:9176-9196` (the
  helicopter drawn on-screen, alpha-ramping 0.35→1.0 across the 420-tick approach). Measured:
  for **7 full seconds** the miniboss is on-screen, growing, with a real shadow — and player
  tracers pass clean through it with no spark, no ping, no `armor_block`, nothing (the bullet
  simply isn't dead). The sim comment says "unhittable and silent until arrival"; the view
  comment says the haze is meant to read "high-alt / not here yet". A visible target that eats
  a mag with zero feedback is the classic "my hits aren't regis…" *(report text truncated at
  source. `a512bee` shipped the grenade half this run — "fly-in is bullet-proof but
  grenade-soft". The bullet pass-through above is the open remainder.)*

### Carried from the 2026-07-29 snapshot — re-flagged 2026-07-31, still open

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
  measured — the rebind path was read, not driven. Teaching entry; filed here in 2026-07-29,
  belongs in §3 — moved there this pass.)* → **see §3.**
- ~~**Downed-pilot ransom is geometry-locked: he walks AWAY from every reachable position, and
  the game's own camera anchor puts him out of reach.**~~ **RESOLVED 2026-07-31** — `66e57e5`.
  (Was: eject floored at `camera_top+120`, walks north at `PILOT_SPEED` 1.4px/t, captured at
  `camera_top-30`; rescue = touch within 14px after the 36t grace; 120 strategy/offset/seed
  combinations measured; capture fuse after grace ~107 ticks.)
- ~~**The grenade landing telegraph lies on held throws: marker + kill circle draw the 99px
  full lob while a >=0.27s press airbursts at 51px — a 48px lie, bigger than the blast ring,
  taught nowhere.**~~ **RESOLVED 2026-07-31** — `1ea8d25` ("telegraph now tracks the real
  release trajectory"). (Was: tapped lob 99px every time; held pops airburst at 51px and throws
  exactly once in 400 ticks while 6 taps landed; apex trips at ~16 ticks (0.27s).)

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
  teaching gap — the HOWTO hides the 10x victory conversion; that half shipped 2026-07-31 as
  `7e3d174`.)*
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
  **RESOLVED 2026-07-29** — the loss beat now covers them. *(sha still not located — find it
  and inline it.)*
- **Crate-chasing rusher can move TWICE in one tick** — introduced by the wedge slide fix.
- **Two movement rules revert your step with no persistent visual at all**; the one-way ledge
  has literally zero lines of view code. *(Suspicion only partly held — frequency of player
  contact was not established. Measure before acting.)*
- **The airstrike is the one supply the shared no-op guard forgot.** Buy it twice inside its
  own telegraph and you pay 200 coins for one strike — and the second purchase pushes the first
  later. *(Note: `254b2a9` measured the airstrike's net score by screen density — break-even
  ~10-11 bodies — and left the double-buy untouched. `8425bd7` (2026-07-31) gated the
  intermission whiff window; the double-buy-during-telegraph above is a different window —
  re-verify against HEAD.)*
- **CHAPTER SELECT / ARCADE plays a de-fanged campaign**: three movement hazards, the whole
  rear-pressure system, and every price increase are silently switched off.
- **A quarter of all enemy gunfire in the campaign is fired by a shooter drawn off the top of
  the screen**, and one telegraph in six is drawn where the player cannot see it. *(Related:
  the 2026-07-31 camera-pin nests finding above adds measured peaks of 4-6 rooted turrets piled
  above the pinned edge during gate fights.)*
- **The Recon Drone is the only lethal archetype with no telegraph.**
- **The Colossus finale is the one stage no pacing table has ever covered.** *(2026-07-31:
  `probe_colossus.gd` now runs clean — seed 0xC0FFEE engage_t=288 fight_ticks=683 downs=3
  victory=true — so the finale is at least observable headlessly now.)*

---

## 3. Teaching / content honesty — the game says one thing, the sim does another

### New in the 2026-08-14 all-loops run

- **The WAR CHEST page's closing advice is exactly inverted in ENDLESS, the mode built for
  score.** WHERE: `src/view/menu.gd:5183`, closing clause "WIN, and what's left banks at %d× —
  plus a %s bonus. Nothing pays like the chest you carry home." vs `src/sim/sim_world.gd:6564`
  (`victory = true` — the ONLY assignment in the file, inside the Colossus death path) and
  `:1025` (`score += banked * WIPE_SCORE_MULT` in `_latch_wipe`). Endless has no Colossus and
  therefore no reachable victory branch, so the ONLY conversion an Endless chest can hit is
  `_latch_wipe`. MEASURED: endless sim, chest **5,000**, `_latch_wipe` → **+15,000 score = 3.0×
  per coin**, `wiped=true victory=false`. The same coin spent through the wheel pays **6.0×**.
  **Every coin you carry in Endless is worth exactly half a coin yo…** *(report text truncated at
  source)*. *(Note `35e24bb` rewrote the spend clause of this page for the revive rate; the
  Endless inversion in the closing clause is untouched — and per owner decision #26 the page now
  has zero vertical slack, so stating it costs another line.)*
- **The two constants that define the shop's central trade contradict each other, and the test
  both of them cite in prose has never been written.** WHERE: `src/sim/sim_world.gd:473-476`
  (`WIPE_SCORE_MULT`'s docstring: "Half of spend keeps spending strictly dominant — hoarding can
  never out-earn the shop.") vs `:478-479` (`VICTORY_SCORE_MULT`: "the richest rate in the
  economy") vs `:2538-2545` (`_try_buy`: "Starting value 6x; test: a hoard run should out-score
  an all-buy run on the same seed by 10-25%. If the gap exceeds 40% (nobody ever buys), raise to
  8."). `SPEND_SCORE_MULT` is **6** and `VICTORY_SCORE_MULT` is **10**, so on a WIN hoarding
  out-earns the shop by **67% per coin** — which is exactly what `_try_buy`'s comment says is
  INTENDED. `WIPE_SCORE_MULT`'s comment, five lines above, states the opposite as settled fact.
  One of these two is wrong… *(report text truncated at source)*.

### From the 2026-07-31 run

- **"PERFECT DODGE!" fires for bullets in the 7–11px band that could never have killed.**
  *(audit-lens finding, adversarially CONFIRMED 2026-07-31 — not from the loop's own lenses.)*
  Where: `src/main.gd:5192-5207` (`_check_near_miss` dodge scan — `_dist_lte(..., 11 * Fixed.ONE)`
  at `:5198` fires `show_banner("PERFECT DODGE!")` at `:5200`, pure distance check, no
  velocity/lethality filter; its own comment at `:5182-5185` claims such a bullet "would have
  killed them") vs `src/sim/sim_world.gd:709` (`ENEMY_BULLET_HIT_RADIUS := 7 * F_ONE`, the ONLY
  enemy-bullet kill test, `:6436-6438`). Arithmetic: bullets move 3px/tick, snipers 6px/tick —
  sampled kill distance ≥ geometric closest approach, so any path missing by >7px can never kill
  on any tick; the whole (7.6, 11] band during the 18-tick roll window provably credits
  non-saves. Rate: multiple times per firefight-heavy run. Cosmetic (banner + hitstop + sfx
  only, no score/currency) — but it hands out skill credit for dodges that never happened.
- **Riot shield's drawn plate is ~3-4× its sim blocking body — shots at the drawn edge read
  as blocked but the sim lets them through (or vice versa: the sim blocks air the art claims
  is open).** *(audit-lens finding, adversarially CONFIRMED 2026-07-31.)* Where:
  `src/view/art.gd:477` (`riot_shield` SCALE 1.1 — its "~half a p2 specialist's span" comment is
  false ~2×; the plate draws ~42px on a ~23px carrier) vs the sim's default 10px hit radius —
  the plate reaches ~32px from a soldier whose block body is 10px. The import-drift class
  inverted (bunker drew 14px while colliding at 48px; here the art OUTGROWS the body), and no
  `test_hitbox_fairness` row pins it. Rate: shield specialists field from campaign sector 2 /
  endless wave 3, so most runs past the early game show it.

- **HOW TO PLAY says "Bullets don't" crack "bosses" — measured real gunship kills get 20-87%
  of their damage from bullets, the weapon the page just told you to stop using.** Where:
  `src/view/menu.gd:5045` (`_howto_page_controls` verb line: "GRENADES crack armor — bunkers,
  bosses, the Colossus. Bullets don't."); sim truth at `src/sim/sim_world.gd:6280-6299`
  (`_bullet_hits_boss` — every MG round does 1 damage with a `boss_hit` event; the gunship has
  40 HP base). MEASURED on REAL campaigns (demo bot, god mode, 3 seeds): the gate-3 gunship
  died at 34.0s/40.8s/66.6s with bullets contributing **32/40, 8/40 and 35/40** of the kill
  damage (**20-87%**) — and the bot doesn't even deliberately aim at bosses. A human holding
  aim on the boss does **7.5 dmg/s** (1 dmg per 8-tick cadence), i.e. the MG is the gunship's
  PRIMARY weapon; grenades (8 dmg each, 12 carried = 96 max) are th… *(report text truncated at
  source)*
- **Rolling in water prints "NEED COINS" — a duplicate match arm silently kills the honest
  teaching branch.** Where: `src/main.gd:2256` (the single `match kind:` in `_consume_events`)
  contains TWO `"deny":` cases — the live one at `src/main.gd:2384` and a second, unreachable
  one at `src/main.gd:2771`. Sim side: `src/sim/sim_world.gd:1129` emits `{"t": "deny", "why":
  "water", ...}` when a wading player presses roll, with the comment "Refuse it out loud … so
  the player learns the RULE (no rolling in water), not just that it failed." Verified:
  GDScript silently accepts duplicate match patterns and the FIRST arm wins (ran a
  duplicate-pattern script: prints "FIRST branch wins", no error, no warning). So every deny
  event routes through `:2384`, whose reason table `{"cap","tank","board","token","fu…`
  *(report text truncated at source)*
- **Airstrike hint gates on the 100c base price, not the depth-creeped price.**
  `src/main.gd:4977` still gates the teaching hint on `sim.war_chest >=
  SimWorld.SHOP_AIRSTRIKE_COST` (base 100c), but the wheel charges the depth-creeped price —
  measured **150c at wave 6** in this cycle's own capture (c6-wheel-hold.png reads "AIRSTRIKE
  150 HOLD"), **125c at wave 3** per the goal's numbers. From wave 3 up the hint can fire while
  the strike is not actually affordable. Verified the line is unchanged by reading it after the
  diff. *(Reasoned from code + capture, not driven.)*

### Carried from the 2026-07-29 snapshot — re-flagged 2026-07-31, still open

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

### Resolved from this section

- ~~**WAR CHEST howto teaches spend-6x vs salvage-3x — and hides the 10x victory conversion
  the whole economy is built around.**~~ **RESOLVED 2026-07-31** — `7e3d174`. (Was: HOWTO
  printed 6x/3x and "That's the choice."; a WIN converts the unspent chest at **10x plus
  5000** — verified live: 137-coin chest at Colossus death produced `banked=137
  banked_score=1370`.)
- ~~**A duplicate TRIPLE SHOT capsule prints "CLAYMORES FULL" — the honest-receipt fix
  hardcoded the wrong item's name.**~~ **RESOLVED 2026-07-31** — `c957313`. (Was:
  `src/main.gd:2185-2192` one hardcoded string for every full-capsule pickup; verified live —
  triple-owning player + kind-6 pickup produced `pickup event: kind=6 full=true cost=0`.)
- ~~**TRIPLE SHOT hint says "PERMANENT" — the sim strips it on your very next death**~~
  **RESOLVED 2026-07-29** — `96d8928`.

### Carried from the 2026-07-26 snapshot — not re-verified this run

- **HOW TO PLAY mis-sells the Flak Vest** — says armor never stops a bullet; it stops one
  completely. That is a 60-coin purchase decision made on false information.
- **HOW TO PLAY names grenades as the thing that cracks the Colossus.** A full grenade carry
  delivers **40%** of its health, and the MG out-damages grenades **5.6×**. *(Compounded by
  this run's "Bullets don't crack bosses" entry above — same page, same shape of lie.)*
- **The taught threat model is wrong.** The campaign is **68% melee**, and the endless Mast
  pulse — taught nowhere — is **27% of every hit** on the waves it is armed.
- **Raw token string shown on world pickup UI.**

---

## 4. UI / visual polish

### New in the 2026-08-14 all-loops run

**Visual-reviewer findings (screenshot lens — reasoned from captures, not measured):**

- **Resolution-mismatched vector laser sights.** Combat targeting laser lines (Screenshots 10,
  20, 23) are drawn as razor-thin, infinitely crisp sub-pixel vector lines that cut diagonally
  across chunky, low-res pixel-art ground tiles and character sprites. Mixing smooth sub-pixel
  rendering with chunky pixel-art assets breaks art-style consistency, making weapon sights feel
  like modern overlay debug lines pasted on retro graphics. Top pixel-art shooters align laser
  sights to the pixel grid using pixel-dithered beam sprites, warm particle bloom, or custom
  pixel-snapped projection lines.
- **UI overlay clipping and layout misalignment.** Defeat and Victory summary screens: end-of-run
  casualty reports render over the active gameplay HUD banners, leaving half-hidden background
  text poking out beneath panel edges. Modal menus should fade out or disable the underlying
  gameplay HUD panels during active states.
- **Severe muddy sprite-to-ground visual contrast.** Desert combat zones throughout Sectors 1–4
  (Frames 1, 2, 4, 12, 18): player sprites, enemy infantry, dropped crates and debris share
  nearly identical muted tan, dull brown and dark olive hues as the desert floor and sandbags.
  Forcing players to isolate small brown enemy blobs against identical brown dirt hurts
  readability badly. Nuclear Throne / Enter the Gungeon use distinct silhouette outlines,
  high-contrast rim lighting and colour accents. *(Related: owner decisions #11/#12 in §1 on the
  `_LIGHT_RIM` separator — same problem, partially addressed for `m_soldier2` only.)*

**World-label arbiter — measured remainders after `4d493b7` / `35e24bb`:**

- **The world-label ladder's 13px plates on an 11px stride is still the root cause; only pickups
  got the fix.** `claim_label_slot`'s `LABEL_ROWS` strides **11px** while every
  `_label_plate_rect` is `size + 5` = **13px** tall, so adjacent rungs overlap by 2px and the
  13-rung ladder offers only **~7 usable rows**. `4d493b7` does NOT fix that — it makes pickup
  tags *droppable* so the overflow is suppressed instead of piled. Every OTHER persistent
  world-label producer still routes through the **non-droppable** claim at `src/main.gd:10499`
  (`_world_label`): fork signposts, LOW FUEL, SILENCE THE SPOTTER, RESCUE, HOLD FIRE, ESCAPING!,
  the reinforcement clock, the threat-overflow +N. On saturation those still keep-place and print
  anyway. **Nobody has measured them** — `tools/probe_maxed_pile.gd` only replays `_draw_pickups`'
  claim order.
- **Residual: ~7–13% of crate price tags still print >22px from their crate, max 66px.** The
  off-frame guard suppresses only plates ENTIRELY off the 640x360 frame; a plate clipping the top
  edge by 1px survives and is still hunted down the `LABEL_ROWS` ladder to the first legal rung.
  Measured with the guard active over **8 configs (campaign/arcade/endless/boss_rush × supplies
  capped/uncapped) × 3,700 ticks × 2 text scales**: **6.8% of drawn tags at 100% TEXT SIZE and
  12.9% at 200%** land **>22px (two rungs)** from their anchor, **max travel 66px** — down from
  **31.8%/30.8%** but not gone. The plan predicted max travel would fall to 44px; **it does not**.
  Worst case: campaign, supplies capped, **tick 850, "MAXED" wanted y=−20, drawn at y=46**. Fix
  direction: require the plate to be MAJORITY on-frame rather than merely intersecting, then
  re-measure — see owner decision #27. *(Fixing it means changing the ladder or the drop policy,
  which CLAUDE.md and `tests/test_main.gd:1841` both guard, so it is its own cycle.)*
- **Pickup tags now vanish silently, including on uncongested runs.** Measured with
  `tools/probe_maxed_pile.gd` on the fixed tree: campaign/arcade **seed 7 drops 4794 tags over
  5400 ticks (~2.7 per congested frame)**, but **seeds 11 and 23 drop 9 each even at only 4–5
  simultaneous labels**. A dropped tag is a crate whose price or MAXED state the player simply
  cannot see. Nearest-first ordering guarantees the crate that can actually debit you keeps its
  price (`PICKUP_RADIUS` is 12px), so this is the intended trade — but it is **new information
  loss that no test bounds**. A cap on drops-per-frame, or a fallback marker on the dropped tag,
  may be wanted.
- **Far capsule NAME tags are silently suppressed in dense loot fields.** Post-fix,
  campaign/arcade **seed 7 suppresses 3783 tag-frames over 5400 ticks (~2.7 per congested frame,
  all capsule NAME tags — 0 price tags)**. The capsule keeps its glow disc, ring and rising beam,
  so the pickup is still salient, but its **identity word is gone at range** until the player
  closes in and it re-ranks. Endless mode drops **0 across 3 seeds**. Worth an owner's eye if
  capsule identity at range turns out to matter.
- **A permanently-dead fork signpost still reserves its two label slots for the rest of the
  band's time on screen (pre-existing in kind).** `main.gd:9272-9274` appends `crect` and `brect`
  to `_label_slots` **unconditionally**, justified by the comment "an invisible-but-returning sign
  still owns its pixels". That justification is now **false** for the time cap
  (`anchored_sign_life` is monotone non-increasing and `born` is never re-stamped, so once
  `seen>=180` the sign can never return) — and it was already false for `fork_sign_relevance`,
  which is monotone once the camera passes **fy=210** while the band stays in the **−20..380**
  cull for another **170 px**. Effect: world-space transient text (kill toasts, crate prices)
  dodges two phantom rects, **96x20 px and 110x20 px**, at a fork the player is fighting in.
  Verified identical on HEAD by reading the same uncondit… *(report text truncated at source)*.
- **PERMANENT FORD's approach window is 75% behind the player.** `src/main.gd:8871`
  `band_sign_visible(band_pys, w["y"])` measures against the water band's **NORTH** edge while the
  band is `WATER_H = 80 px` tall (`src/sim/sim_world.gd:685`) and the player travels north.
  Measured window: visible from **py = w.y+120 (40 px / 0.28 s before the SOUTH bank)** through
  **py = w.y−120 (120 px after the crossing is finished)**. The label's job is to let you pick a
  crossing on approach; it currently appears at the water's edge. Fix by anchoring the reach to
  `w["y"] + SimWorld.WATER_H` or making it asymmetric, and extend the A4 sweep to assert the
  pre-bank half. *(See owner decision #23 — which reading is intended is unstated.)*
- **The PERMANENT FORD gate cuts live exposure by only 28%, and no test measures that.** Measured
  with a headless probe on this tree (real `SimWorld 0xC0FFEE`, 1P, campaign, god_mode, shipped
  `demo_input` bot, 20,000 ticks): bands with a permanent second ford are **band_idx 2 and 5**;
  the band is on screen for **591 ticks** total, and with `band_sign_visible` the label still
  draws for **423 of them (71.6%)**. So the plate goes **591 → 423** ticks — a real improvement on
  the long approach, but far short of the "the plate learns to shut up" framing in the comment at
  `main.gd:8865-8871`, because the player lingers at the crossing and stays inside the 120 px
  reach. A4 only sweeps the pure function and greps the call site; **nothing asserts a live
  exposure number, so this can silently regress to 100%**.
- **`anchored_sign_seen` stamps `born` at cull entry (fy = −20), not at legibility (fy >= 14).**
  The plate rect top is `fy - (SIGN_FONT-2)` = **fy−14**, so up to **34 px of camera travel
  (0.24 s at PLAYER_SPEED 144)** of the 180-tick budget is spent with the plate entirely above the
  viewport. Measured: it does **not** bite today (**171 fully-on-screen ticks at peak alpha 1.00**
  in the pinned-from-cull worst case, seeds `0xC0FFEE`/1P and `42`/1P), but a future change that
  slows camera catch-up or raises the cull margin would silently start eating the readable window.
  Born-at-legibility (stamp when `crect.position.y >= 0`, or when `fork_sign_relevance >= 1.0`)
  is the same one-line cost and immune to that.
- **The 100% default CONTROLS page drifts 3–9px, contradicting the in-file "pixel-identical"
  contract.** `src/view/menu.gd` `_next_verb_y` returns `maxf(y + VERB_PITCH, bottom + 4.0)`. At
  defaults (keyboard, `MainScript.BIND_DEFAULTS`, `Art.use_pad=false`) the AIM, GRENADES and ROLL
  rows each already wrap to two lines, so `bottom` is `base+26` and `bottom+4` (`base+30`) beats
  the authored **27px** pitch on every one of them — cumulatively. Measured by instrumenting
  `_next_verb_y` with a print and running `SUITE=menu_layout`: verb baselines go
  **124/151/178/205/232/259 (HEAD) → 124/151/181/211/241/268**; page return **285 → 294**; lowest
  ink **274 → 283** against a BACK plate top of **297**. Per-row drift **0/0/+3/+6/+9/+9**.
  `menu.gd:5088` states the 100% pages exist so "the default presentation stays pixel-identic…"
  *(report text truncated at source)*.

### From the 2026-07-31 run

- **Repetitive Grid-Based Ground Tile Seams.** Where: Sector 1 and river crossing stretches
  (Screens 1, 4, 6, 20). The desert ground exhibits obvious repeating grid patterns, featuring
  harsh rectangular transitions where land tiles meet water channels or road strips without
  visual edge smoothing, foliage overhangs, or organic blending. Visible tile repetition and
  abrupt straight-line terrain boundaries give the environment an unpolished tilemap-editor
  look rather than an immersive battlefield feel. AAA version: rich autotiling transition sets,
  layered foliage fringes, ground decals, and subtle noise variation to mask the grid.
  *(Visual-lens entry — reasoned from screenshots, not measured.)*
- **Floattext down-stack can overprint the commander bark row at the bottom rail**
  (pre-existing, not from this diff). Visible in both HEAD (6-plate) and fixed (4-plate)
  captures: the floattext stacking block bumps toasts DOWN from the anchor, and at the bottom
  rail the lowest plate overprints the COMMANDER bark row. Verified by capture
  (`/tmp/cic_shots/shot1_BEFORE.png` vs `shot1_AFTER.png`: HEAD stacks 6 plates into the bark,
  the fix stacks 4 and the top edge of the lowest still touches the bark plate). The cap
  strictly reduces the pile but the downward-bump rule has no rail guard against the bark zone.
  Right answer is a bottom-rail reservation the way `_band_floor()` reserves the top; measured:
  **4 plates × 11px** can still reach the bark row when the anchor is the player standing …
  *(report text truncated at source)*
- **Intrusive Knockdown Screen Smear Obscuring Gameplay.** Where: knockdown and revive
  sequence transitions (Screenshots 5, 13, 14). When the player is knocked down, a violent
  horizontal motion-blur glitch filter and heavy crimson tint flood 100% of the viewable
  screen; enemy positions, incoming bullets, and terrain obstacles blur into near-complete
  illegibility. Sacrificing gameplay clarity during critical rescue/revival moments for heavy
  post-processing undermines player feedback and co-op tactical awareness. AAA version:
  localized feedback — peripheral vignette darkening, subtle screen shake, distinct audio
  ducking — while … *(report text truncated at source. Visual-lens entry.)*
- **Unmasked Overlay UI Clipping.** Where: end-of-run Victory report screen (Image 23).
  Targeting reticle icons and UI crosshairs on the bottom-left render directly over and under
  the border of the modal Victory card popup, clipping through the frame instead of being
  hidden or properly layered behind a full-screen menu mask. Modal report cards should cleanly
  freeze and isolate world-space UI; active targeting cursors bleeding through modal menu cards
  reads as an unpolished camera/UI rendering pass. AAA version: isolate modal report screens
  onto a clean UI render pass that suppresses, hides, or darkens all active world-spa… *(report
  text truncated at source. Visual-lens entry.)*
- **Vertical-only label dodge + deck gunner has no player exclusion.** `claim_label_slot`
  dodges vertically only (x is clamped, never moved), and the player-label reservation added
  this cycle skips any player with `in_tank >= 0` — but a non-driver tank occupant (deck
  gunner) is drawn standing on the field at `_to_screen + (0,-7)` (`main.gd:9866-9868`) and
  gets no exclusion rect, so labels can still ink over the deck gunner. Both limitations are
  named in the plan as banked; verified the gunner draw path is unchanged.
- **Four entity-anchored world marks bypass the label arbiter.** The "!" mark (`:7850`), ford
  label (`:8048`), gate numeral (`:8169`), and "?" (`:8882`) remain drawn outside the
  `claim_label_slot` arbiter. Small entity-anchored marks, none part of this cycle's tell;
  banked by the plan and still unarbitrated in the diff.

### Carried from the 2026-07-29 snapshot — still open

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
  fix shipped — "full screen low pass distortion blurring the hud" is on the shipped list, sha
  not located (`5cfea32` covered menus only). As above: the open item is the remainder.)*
- **Unaligned Leaderboard Column Formatting.** Hall of Fame table screen (Screenshot 16): the
  leaderboard table header ('# RANK SCORE MODE REACHED STREAK') features uneven horizontal
  spacing where column titles crowd together irregularly, above plain, unadorned sub-panel
  framing. AAA arcade menus use pixel-precise grid alignments, crisp column dividers, distinct
  visual hierarchy between headers and entries, and glowing selector states. *(`2bedaf1`
  shipped a fix titled exactly this; the lens still flags a remainder. Verify against HEAD
  before acting.)*
- **Raw Blocky Text World Signage.** Images 3, 15, and 17 (Bounty and Cache screen markers):
  huge, flat cyan and yellow pixel-font text strings reading 'BOUNTY >' and '< CACHE' sit drawn
  flat across the lower playfield directly over rocks, sandbags, and active combat sprites
  without depth or diegetic framing. Rendering massive raw text overlays flat across
  environmental art looks like developer debug flags rather than polished UI navigational
  signposting. AAA version: anchor directional markers to screen edges or render them as
  diegetic, styled UI badges with subtle floating animations and drop shadows. *(A fix titled
  "raw blocky text world signage" shipped — sha not located. The open item is the remainder.)*
- **Static Scanline Overlay Obscuring Menu Typography.** Options menu and Control Rebind
  sub-menus (Images 18, 19): a heavy, dark horizontal scanline filter is drawn over the entire
  menu container, cutting directly across fine pixel letters and rendering small button
  callouts and option labels dim and grainy. AAA version: top-tier retro-styled titles place UI
  text overlays on an unfiltered canvas or fine-tune scanline strength so interface typography
  remains sharp, bright, and effortlessly readable. *(Re-flagged 2026-07-31, unchanged.)*

### Resolved from this section

- ~~**Floattext spawn punch can poke ~4.5px above `band_floor` for ~2 frames**~~ **RESOLVED
  2026-07-31** — `1ea6508`. (Was: `fpivot.y` clamped to `band_floor + fsz` but the 1.5x spawn
  punch scales the ascent about the pivot, reaching `band_floor - 4.5px` for fsz=9 during the
  first ~2 frames; self-correcting because the band draws after `_draw_fx`. The down-stack bark
  overprint above is the remaining floattext-rail gap.)
- ~~**Screen-cluttering world-space text overlays**~~ **RESOLVED** — `f255cab` part 2
  (`claim_label_slot()` body written to spec AND wired: `_draw()` clears the claim list each
  frame, `_world_label` routes every world-space string through the arbiter, plate and ink move
  together; ratchet: **15,320 colliding pairs and 361 off-frame escapes → 0 and 0**).

### Carried from the 2026-07-26 snapshot — not re-verified this run

- Inconsistent pixel typography and menu padding (How To Play, Options).
- Generic box-border menu framing — reads as prototype chrome. *(`6ecbf0d` "programmer-style UI
  modals and plain menu framing" is on this run's shipped list — likely this entry; verify
  before striking.)*
- WARN and LABEL wheel plates overlap by 2px, leaving a double-blended dark band.
- HALL recency band collides with the filter tab row *(introduced by the cycle-1 diff)*.
- MODES tab row pitch is too tight for the new 2-line tips.
- HOWTO "N / 5" tab counter crowds the ENDLESS tab label.
- Wheel text is the only view text that ignores the accessibility text scale (pre-existing).

---

## 5. Test & tooling debt

### New in the 2026-08-14 all-loops run

**Ratchets that can go green while wrong — highest value first:**

- **The war-chest ratchet's forward guard is a NO-OP: crediting revives at 6× keeps the suite
  green with the copy still saying "REVIVING scores nothing".**
  `tests/test_view_honesty.gd::test_the_war_chest_page_prices_every_way_a_coin_leaves_the_chest`
  splits the drawn corpus on `"."` only. The shipped copy is one sentence — "BUYING scores 6× per
  coin — REVIVING scores nothing" — so the `_try_revive` lookup (segment must contain "REVIVING"
  and the measured-rate token) is satisfied by the BUYING clause's "6×" as soon as the measured
  revive rate becomes 6.0. MEASURED in this worktree: insert `score += cost * SPEND_SCORE_MULT`
  after `war_chest -= cost` in `_try_revive` (`src/sim/sim_world.gd:2053`) and
  `SUITE=view_honesty tools/run_tests.sh` reports **"PASS — 73 test methods, 3943 assertions, 0
  failures"** — while the rendered page still tells the player revivi… *(report text truncated at
  source)*.
- **A4's reach assertion is self-referential — the PERMANENT FORD gate's magnitude is unpinned.**
  `tests/test_view_honesty.gd::test_band_anchored_signage_speaks_only_on_approach` sweeps `off` in
  **−400..400** and asserts `Main.band_sign_visible(pys, 0) == (absf(float(off)) <
  Main.BAND_SIGN_REACH)`. The expectation is computed **FROM the const under test**, so raising
  `BAND_SIGN_REACH` from **120.0 to 450.0** makes every expectation true, `band_sign_visible`
  returns true for every sampled offset, and the suite stays green **with the always-on plate
  fully restored**. This is the repo's own documented "green but wrong" pattern. The sibling A3
  does it correctly with a literal (`if t >= 180: Runner.T.eq(v, 0.0, …)`). **Fix: assert against
  a literal 120.0.**
- **The chest-exit census is spacing-sensitive and misses static funcs / second debits.** The
  census in `tests/test_view_honesty.gd` matches
  `line.strip_edges().begins_with("war_chest -=")`. A fourth exit written `war_chest-= cost` (no
  space), or with the debit on a continuation line, is **not counted** — the census silently
  passes and the new exit ships unpriced, the exact failure mode it exists to prevent. It also
  attributes each `war_chest -=` line to the last line beginning with `func ` and dedupes by
  function name, so **a second, differently-rated debit added INSIDE `_try_buy` /
  `_collect_pickups` / `_try_revive` adds no new name and still passes**, and lines beginning
  `static func ` are not matched (such an exit would be misattributed to the previous non-static
  func). Neither hole is exploitable today (verified: exactly **3** `war_chest -=` sites at
  `sim_world.gd:1917, :2053, :2536`, all in plain funcs, all canonical spacing), and a static func
  cannot mutate instance state. **One-line fix: strip all spaces before the `begins_with` check.**
- **Live-run courier assertion is `>=` where it should be `==`.** `tests/test_mechanics.gd`,
  `Runner.T.ok(resolved >= spawned - seen.size(), …)`. A double-resolution (both a kill and an
  escape for one courier) would pass. Every path was traced and double-resolution is currently
  impossible — the north escape sets `alive=false` before the sweep, the sweep emit is guarded on
  `e["alive"]`, and `_rescue_pilot` (`sim_world.gd:3499`) sets `alive=false` first — so this is
  hygiene rather than a live hole, but `==` is the honest assertion.
- **No test asserts the VIEW turns `courier_escape`/`pilot_lost` into their float and sting.** The
  sim half is now ratcheted three ways, but nothing in `tests/` asserts that `main.gd:3268` emits
  the "GOT AWAY!" floattext or that `main.gd:573` plays the deny sting —
  `grep -rn 'GOT AWAY' tests/ src/` returns only the sim-side assertion message and the `main.gd`
  literal. **Deleting the `courier_escape` case from `_consume_events` would leave the whole suite
  green.** The gap was closed for this cycle by capture, not by test:
  `.aaa/shots/gotaway_05.png` and `gotaway_12.png` show the plated toast rendering in the right
  place. A `test_view_honesty`-style cell asserting the event produces an `_fx` entry would make it
  permanent.
- **A1's fork sweep is 3 cells, not the 10 the plan specified.** The plan called for seeds
  `[0xC0FFEE, 1, 7, 42, 99] × [1P, 2P] × 20,000 ticks`.
  `tests/test_view_honesty.gd::test_one_fork_band_draws_one_lane_orientation` ships
  `[[0xC0FFEE,1,5000],[0xC0FFEE,2,4200],[42,1,700]]`. It still goes red at HEAD (**10 failing
  assertions**), so the ratchet works, but **seeds 1, 7 and 99 are never exercised** and the 42
  cell only reaches one band in 700 ticks. Since the bait is gated on `fmix % 4 == 0` with
  run-state-dependent `fmix`, a wider sweep is what would catch a producer that only misbehaves on
  an unswept seed.
- **Assert B in the new pickup-tag test has only 2.1pp of headroom at 200% TEXT SIZE.**
  `tests/test_main.gd::test_pickup_tags_are_never_drawn_for_an_off_frame_anchor` asserts
  far-travelled tags stay **<= 15.0%** of drawn tags. HEAD measures **31.8% / 30.8%** (100% /
  200% scale) so it is genuinely red-on-HEAD, but the post-fix values are **6.8% / 12.9%** — the
  200% case sits **2.1pp** under the bar. Deterministic (`SimWorld` seed 7, `demo_input` bot) so
  it will not flake, but any future change that adds a few more on-frame-anchor collisions trips
  it **and the failure message will accuse the wrong thing**. Either widen to ~20% with the
  measured values in the comment, or split the assertion per scale with its own budget.

**Comments and docstrings that state numbers the tree cannot reproduce:**

- **`src/main.gd`'s guard comment ships measurements its own adjacent test disproves.**
  `src/main.gd ~:10500-10503` claims "103,496 pickup tags: 28,229 (27.3%) had an entirely
  off-frame plate and 24,340 drawn tags (23.5%) landed >22px …; after this guard, 18 (0.017%) and
  max travel 66px -> 44px." Measured by flipping the shipped guard to `false and` and running
  `SUITE=main` in this worktree: **29,278 off-frame tags DRAWN of 100,713 off-frame wants**,
  far-travelled **31.8% at 100% TEXT SIZE and 30.8% at 200%**. With the guard restored and the
  threshold temporarily tightened to 0.0 so the assertion printed its real values: **off_frame_drawn
  0, far-travelled 6.8% / 12.9%, max travel STILL 66px** (worst: campaign capped **t850, "MAXED"
  wanted y=−20, drawn y=46**). So **"18 (0.017%)" and "66px → 44px"** are both wrong in the
  shipped comment.
- **`test_every_courier_in_a_live_endless_run_resolves` docstring numbers do not reproduce.**
  `tests/test_mechanics.gd` claims "278 ticks over 6 endless seeds × 12,000 ticks: 28 spawned, 7
  killed, 21 escaped, 0 unresolved". Re-measured on this worktree with the same harness
  (`SimWorld.new(seed,1,'endless')`, `god_mode=true`, `main.gd::demo_input`, 12,000 ticks,
  couriers tracked by reference), seeds `[0xC0FFEE,1,2,3,4,5]`: **3/0/3, 1/0/1, 3/0/3, 1/0/1,
  3/0/3, 2/0/2 = TOTAL 13 spawned / 0 killed / 13 escaped / 0 unresolved, longest single-courier
  life 218 ticks**. The asserted invariant holds; the cited figures do not. The bot kills **0 of
  13** post-fix (it killed **1 of 5** on HEAD) because the courier now runs away from where the
  bot stands — an instrument limit worth stating, not a bug.
- **`claim_pickup_labels`' "nearest always keeps its tag" is true only under saturation, and the
  docstring/test name say it absolutely.** `src/main.gd claim_pickup_labels`' docstring asserts
  "the crate that can actually charge you is always rank 0 and always keeps its price", and
  `tests/test_main.gd` asserts "…the NEAREST pickup's tag is never the one dropped". Measured with
  a throwaway probe (**5400 ticks × seeds 7/11/23 × campaign/arcade/endless**, replaying the
  shipped `pickup_label_requests` + `claim_pickup_labels` every tick): the rank-0 request is
  suppressed **8–9 times per campaign/arcade run** — including on seeds 11 and 23 whose max
  simultaneous tag count is **5 and 2**, i.e. where the ~7-row ladder **CANNOT** saturate. Every
  one is the off-frame-top case: a pickup at screen y in roughly **[−40,−26]** has `want.y` around
  **−73..−59**, and even the ladd… *(report text truncated at source)*.
- **`_spawn_courier`'s comment still justifies +300 with a campaign-only constant.**
  `src/sim/sim_world.gd:4445-4448` reads "+300 (was +240): with the c2 camera lead at 260, +240
  would pop it IN FRONT of the anchored player". `CAMERA_LEAD` (`sim_world.gd:273`) is the
  **campaign** camera lead; `_spawn_courier`'s only caller is `_start_wave`, reachable only through
  `_step_waves` gated `if mode == "endless"` (`sim_world.gd:1078`), where `camera_top` is fixed.
  The 260 match was arithmetic coincidence with the old 40px north bias, which `696db74` deleted —
  so the comment's premise is now **doubly dead**.
- **`test_localization.gd`'s stated HEAD count is 2, measured 3.** The comment above
  `test_no_caption_line_ends_on_a_dangling_dash` says "MEASURED at HEAD: 2 hits, both `vo_airstrike`
  at cs 18 and cs 20". Reverting `Art.wrap_words` to `txt.split(" ", false)` on this tree and
  running `SUITE=localization` reports "no caption line may end on a bare dash — **3 found**, e.g.
  `vo_airstrike` cs20". The discrepancy is explainable (HEAD's `hud._wrap_caption` used
  `allow_empty=true`, the mutation control used `false`) but **the comment states a number the repo
  can no longer reproduce**.

**Gates that are red or flaky for reasons unrelated to any commit:**

- **`tools/i18n_check.py` exits 1 on pre-existing MISSING/STALE keys in all three locales.**
  Verified pre-existing by stashing the **whole** working tree and re-running: the output is
  **byte-identical** before and after. `ja` is missing **5** keys used in source (BROADCAST TOWER,
  FLASHBANG — DETONATES ON GRAB, NG+ HARD, SPOTTER: "Friendly strike inbound", TALL GRASS HIDES
  YOU) and carries **3** stale ones (FLASHBANG — INFANTRY STUNNED, the old NG+ HARD string,
  SPOTTER: "Airstrike inbound"); `es` and `fr` carry the same shape. So **the translation gate is
  currently red for reasons unrelated to any recent cycle** and will stay red until someone drains
  it — which means **it cannot catch a NEW translation gap**. *(`f70a5c7` wired this checker into
  the lint job, so the drain is now load-bearing.)*
- **`test_perf` boss_rush spike ceiling is flaky at 20000us on this machine.** One `SUITE=perf` run
  on the fixed tree reported **boss_rush worst=31971us** against the **20000us** ceiling; two
  immediate re-runs gave **5721us** and **4219us**, and HEAD gave **6965us**. The sim counters were
  identical across all runs (**live 3600/3600, wave 0, 0 enemies, 22 sandbags**), so nothing about
  the diff moved it. It is opt-in and advisory in CI, but a spike ceiling that trips **~1 run in
  3** on an idle box is a ceiling nobody will read. Either raise it or **measure the p99 instead of
  the max**.
- **Full-suite assertion count is not reproducible run-to-run (29595 vs 29596).** Two full
  `tools/run_tests.sh` runs on the IDENTICAL tree reported **"PASS — 1117 test methods, 29595
  assertions"** and **"PASS — 1117 test methods, 29596 assertions"**. Method count is stable,
  assertion count is not, so some suite loops until a condition or samples something
  non-deterministic. Not isolated; **not** one of the three tests added by this run (their
  assertion counts are fixed by their loop bounds). Likely pre-existing — the HEAD baseline run
  (whole diff stashed) gave **26664** but was sampled only once, so that cannot be stated as
  verified. Worth a `SUITE=` bisection: run each suite twice and diff the counts.

**Cost and hygiene:**

- **Full suite wall time is up 25–56% from ONE test method.** Two independent measurements, same
  cause: (a) serially, no other Godot process — **HEAD 40.5s (PASS 1117 methods / 29602
  assertions) → with the diff 50.7s (PASS 1120 / 29619)**, the **+10.2s** all being
  `test_pickup_tags_are_never_drawn_for_an_off_frame_anchor`: **8 configs × 3,700 ticks × 2 text
  scales = 59,200 ticks** with the full label-claim pipeline per tick; (b) `tools/run_tests.sh`
  went from **~32s to 50.3s** wall (`time`, single Godot process, 99% CPU, no contention) for the
  same method (**4 modes × 2 supply states × 2 text scales × 3,700 ticks**). The plan budgeted
  **~12s**. **CLAUDE.md still advertises ~23s and the real figure is now over 50s** — budget the
  next drive-based ratchet against that.
- **`tests/test_view_honesty.gd::_drive` leaks a `_NullSfx` Node per cell.** `_NullSfx extends
  Sfx`, which extends `Node` (`src/view/sfx.gd:2`). `_drive` assigns `main._sfx = _NullSfx.new()`
  without `add_child`, and `main.free()` frees only children, so **each of the 4 `_drive` calls
  leaks one Sfx instance plus its state**. Measured contribution: exit-time ObjectDB leaks went
  **5191 → 5482** and CanvasItem RIDs **265 → 275** between HEAD and this tree. Harmless today (the
  engine-error gate ignores exit-time WARNINGs) but it grows with every cell added.
- **Seven untracked probe tools left in the worktree from an earlier cycle.**
  `tools/probe_bunkers.gd`, `probe_census.gd`, `probe_frog.gd`, `probe_marsh.gd`,
  `probe_offscreen.gd`, `probe_vents.gd`, `probe_zones.gd` — untracked, mtimes **12:10–12:44**
  (before this attempt's 13:51+ edits), all created after HEAD (HEAD commit 11:59), unrelated to
  either tell in the plan, none referenced by any test, and **none carrying the `.gd.uid` sidecar**
  that all 30 tracked `tools/*.gd` have. All seven were run via
  `tools/run_tests.sh -s res://tools/<name>.gd`: **every one executes cleanly** and its output is
  consistent with the green suite (bunker zone census, event census, frogman surfacing, marsh
  drift, off-screen shooter attribution, foundry vents, per-sector spawn census), so they are NOT
  blocking. They should be **committed deliberately with sidecars, or deleted** — not swept in by
  `git add -A`.
- **`tools/probe_fan_value.gd` carries a dead loop.** Lines ~20–21: `for rk in radii:` / `pass` — a
  no-op left from an earlier draft, immediately superseded by the explicit
  `for rk in ["fodder", "elite", "mg_nest", "colossus"]` below it. Cosmetic only; the probe's
  numbers are correct and match `tests/test_gameplay.gd`'s ratchet. Verified by reading the file
  and running it (`tools/run_tests.sh -s res://tools/probe_fan_value.gd`).

### Carried from earlier snapshots

- **Engine shutdown leak ERRORs on every suite run** (pre-existing, identical on HEAD;
  re-flagged 2026-07-31). Every suite run prints `ERROR: 3 resources still in use at exit`
  plus `WARNING: 4383 ObjectDB instances leaked at exit`, after the PASS line. Verified
  pre-existing: stashed the entire diff (tracked + untracked), re-ran the suite on HEAD, and
  got the identical leak counts (4383 ObjectDB, 3 resources). Not from the new CanvasLayer.
  These fall outside the engine-error gate's window (the gate reads the log up to its own
  marker; these print at shutdown), so they never fail anything — but they are ERROR lines
  every run trains people to ignore, which is exactly how a real one gets missed.
- **NEW 2026-07-31 — `tools/screenshots.gd` victory pose fakes the WAR CHEST row.**
  `_shot_victoly`/`_dress_victoly` never sets `_victory_banked`/`_victory_banked_score`, so the
  harness's `06-victoly.png` renders "0¢ WAR CHEST BANKED → +0" — the narrowest possible
  version of the card's widest row. Confirmed in this cycle's own capture
  (`/tmp/cic-cycle5/06-victoly.png`). This is the exact "harness lying about the game" pattern
  `_dress_victoly`'s own comment guards against for kills/streak, and it means the signature
  victory shot can never exercise the row the trophy used to cover. The plan listed this as
  optional hardening ("take it or leave it") and the implementer left it. Pre-existing,
  verified by capture. Two lines in `_dress_victoly` would fix it.
- **NEW 2026-07-31 — Toast-string scrape's `_coin_pop` branch is dead code — coin toasts
  (BOUNTY/RANSOM/+¢) never captured.** `tests/test_main.gd::_shipped_floattext_strings`: for
  lines containing `_coin_pop(`, `line.find("\"", at)` lands on the quote in `ev["x"]` (the
  first argument), producing `fmt="x"`, which the `fmt.length() < 2` filter then drops — so
  the line is consumed without ever reaching the actual text literal. Verified by simulating
  the scrape in Python against `src/main.gd`: **21 strings captured, all from the "rate"
  branch; BOUNTY +%d¢, RANSOM +%d¢, +%d¢ absent.** The helper's docstring ("the _coin_pop text
  arg") overclaims. Not blocking: coverage is still wide (21 shipped strings incl. wider ones
  than BOUNTY's 94.5px — "PILOT DOWN — REACH HIM" is 247.5px at scale 1.0) and the size>=4
  guard plus the drops>0 a… *(report text truncated at source)*
- **`tools/probe_concussion_hud.gd` is gated nowhere** — see Owner decision #1; the tooling
  half is that the probe exists and nothing runs it. *(Also: `tools/probe_salvage.gd` and
  `tools/probe_colossus.gd` are untracked orphans in the tree — they produced this run's
  measurements, so either commit them or delete them; don't leave them to rot.)*
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
  obvious answer and is not built. *(2026-07-31 was a drain-flavoured run: 10 shipped, 31 new
  banked — the ratio moved the wrong way anyway. **2026-08-14: 8 shipped, 58 new banked plus 16
  owner decisions — the worst ratio yet, and roughly a third of the new entries are remainders of
  the same run's own fixes.**)*
- **NEW 2026-08-14 — Parallel `overnight/2026-08-14-aaa-*` worktrees make shipped-sha attribution
  unreliable.** Two of this run's eight titled fixes ("tutorial UI text truncation and panel
  clipping", "truncated tutorial body text in manual UI") shipped on sibling branches that are not
  reachable from this one, so §8 records them with **no sha**. `git log --all` on this worktree
  sees only the branches this checkout knows about. If the run wants an accurate ledger, the
  merge step must collect shas from every sibling before the backlog is written — or the backlog
  must be written after the merge, not before it.

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
- **Miniboss fly-in airstrike window is a partial whiff — banked by the plan.** The
  intermission half is provably empty and shipped in `8425bd7`; the fly-in half is not provably
  empty (the trickle keeps spawning) and `_fire_mission` spares bosses, so a strike bought
  during the fly-in still kills only trickle infantry. **Blocked on: a design call on whether
  fly-in strikes should hit the boss.** (Mirrored in §2 because the lens keeps re-flagging it.)

---

## 8. Shipped — resolved, kept for the record

### Shipped in the 2026-08-14 all-loops run

| Finding | Commit |
|---|---|
| The COURIER bounty deletes itself off the bottom of the screen — the "GOT AWAY!" sting has never once fired | `696db74` — remainders open: catchability is owner decision #15, `marked` elites/drones #17, the never-in-campaign defect and the unswept `pickups[]` in §2, four test/comment remainders in §5 |
| TRIPLE SHOT is a 2× ammo tax that buys zero extra damage, and only death removes it | `4d493b7` — remainders open: the undeclinable 120-coin auto-purchase and missing drop verb #18, the free 5-fan #19, the unreplaced ammo sink #20 |
| Stacked / overlapping world-space upgrade tags | `4d493b7` (pickup tags now claimed droppable, nearest-first) — remainders open: silent tag loss and far-capsule suppression in §4, the 13px-on-11px ladder #21 |
| Intrusive blocky world-space directional banners | `7d26648` — remainders open: the hard 3.0 s fork-sign life #22, `BAND_SIGN_REACH` symmetry #23, the 2.85 s read budget #24, no fallback after dissolve #25, plus four §4/§5 remainders |
| "Spend it — 6× score" is one sentence covering two rules, and the revive half pays 0.0× | `35e24bb` — remainders open: should a revive score at all #28, the 200% line break #29, the WAR CHEST page's zero slack #26 |
| Intrusive HUD and world-space label occlusion | `35e24bb` (`claim_label_slot` suppresses entirely-off-frame droppable plates; **29,278 off-frame tags drawn → 0**, far-travelled **31.8%/30.8% → 6.8%/12.9%**) — remainders open: drawn-vs-suppressed is owner decision #27, the 66px residual in §4, the permanent floattext suppression #30 |
| Tutorial UI text truncation and panel clipping | sha not resolvable from this worktree — shipped on a sibling `overnight/2026-08-14-aaa-*` branch not merged into `main` at the time of writing. Remainder open: the 100% CONTROLS page 3–9px drift (§4) |
| Truncated tutorial body text in manual UI | sha not resolvable from this worktree — same sibling-branch caveat. Remainder open: the 100% manual pages never translate (owner decision #16) |

*Run-window context (this branch, `390c12d..35e24bb`): the all-loops rounds 1–10 also landed
`505a048` `c62c4fe` `34dd43f` `38a1d94` `cc5afed` `639cd5d` `fbc40cd` `0270b57` `34a4037`, plus
the audio, VO-provenance, i18n-gate and tooling packs. Only the eight titled findings above are
tracked as backlog resolutions.*

### Shipped in the 2026-07-31 window (`2bedaf1..390c12d`)

| Finding | Commit |
|---|---|
| Downed-pilot ransom is geometry-locked | `66e57e5` |
| Endless miniboss's 7s fly-in — grenade-soft half | `a512bee` — bullet pass-through remainder open (§2) |
| Grenade landing telegraph lies on held throws | `1ea8d25` — telegraph now tracks the real release trajectory |
| Endless's unbounded difficulty term invisible from wave 13 | `f6666b8` — banner/chip shipped; empty-clip-bash consequence open (§2) |
| Floattext spawn punch pokes ~4.5px above band_floor | `1ea6508` — down-stack bark overprint remainder open (§4) |
| Endless shop sells a 100¢ airstrike in the window it cannot hit + token-roll whiff | `8425bd7` — fly-in whiff (§2/§7) and hint-gate (§3) remainders open; pre-call trade is owner decision #10 |
| WAR CHEST howto hides the 10x victory conversion | `7e3d174` |
| DAILY RUN one-attempt refunded by R / RESTART / QUIT TO TITLE | `d45132a` — scouting remainders still flagged (§2); banked-quit and same-board calls are owner decisions #13/#14 |
| Duplicate TRIPLE SHOT capsule prints "CLAYMORES FULL" | `c957313` |
| Endless milestone shop window is a kill zone | `390c12d` — Spotter-shelling remainder open (§2) |

Also on this run's shipped list — titled fixes whose commits predate the 2026-07-29 snapshot
(the run's diff window was wider than the last backlog's):

| Finding | Commit |
|---|---|
| Copy-pasted barricade tiling | `5bbfff1` ("vary barricade tile stacking to kill repetitive sandbag look") |
| Generic modal frames for menus and victory cards | `6ecbf0d` ("programmer-style UI modals and plain menu framing") |
| UI text banner stacking / UI label stacking / overlapping HUD text popups | `f255cab` + `b439779` (label arbiter + band arbiter) |
| Menu UI bounds truncation and clipping | `82373e7` (likely — "the price, the recovery word and the recency band all stayed in the box") |
| Unlit and floating heavy equipment sprites | `f29d7ca` (likely — gunship ground shadow + technical deny pip) |
| Muddy low-contrast unit silhouette readability | this run's `m_soldier2` rim fix — sha not located this pass (see owner decision #11 for the ghillie/sapper deferral) |
| Flat unintegrated world UI banners | sha not located this pass (`b18c889` "back the in-world callouts" is adjacent) |
| Overbearing in-world objective UI labels | sha not located this pass |

### Shipped 2026-07-29 (previous snapshot)

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
| Dying silently deletes an earned Commendation and every carried claymore | sha not located — still not located 2026-07-31 |
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
- **The backlog grows faster than it drains** (~4 banked vs ~1 fixed per cycle; the 2026-07-31
  drain-flavoured run shipped 10 and banked 31). That is what an honest audit of a real
  codebase looks like — but it means this file is a **triage queue, not a work queue**, and it
  will not converge on its own.
- **NEW 2026-08-14 — near-duplicate handed-in entries were MERGED, not dropped.** The
  2026-08-14 run handed in 23 owner-decision items that collapsed to 16: courier catchability
  (2 items), `marked` bounty escapes (2), TRIPLE SHOT's shop/drop-verb pair (3), the fork-sign
  time cap (2), `BAND_SIGN_REACH` (2), the pickup-tag ladder (2). Each merged entry keeps **both**
  measurement sets verbatim. Likewise in §2/§4/§5, entries that two lenses filed from opposite
  ends of the same defect (the mg_nest off-screen band; the unswept `pickups[]`; the suite
  wall-time regression; the `i18n_check` red gate) are one entry carrying both measurements, with
  the second lens's angle called out inline. **Nothing was discarded for being a duplicate.**
- **NEW 2026-08-14 — "Checked and did NOT hold" entries are load-bearing.** §2 ends with two
  negative results (off-screen shooters, pilot rescue) whose measurements killed a plausible
  finding. They stay in the file so the next cycle does not re-spend the budget on them — and the
  off-screen one is instructive: the *general* claim is false, but the mg_nest specifically DOES
  abuse the band. Enumerate per-kind before generalising.
- **Where an entry has no measured number, it says so.** Treat those as suspicions, not
  findings — this project has repeatedly had a real smell reported with the consequence wrong
  by a whole severity class.
- **Several report bodies arrived truncated at source** (marked "report text truncated at
  source"). The surviving measurements are verbatim; the missing tails were reasoning, not
  numbers.
- **Held, checked, no finding (2026-07-31):** a full pass over the remaining roster —
  `src/sim/sim_world.gd` steppers (elite/sniper/ghillie/drone/technical/mg_nest/grenadier/
  observer/colossus/gunship) plus the view telegraph paths (`src/main.gd:8708` telegraph_dir,
  `:11920-11981` off-screen threat pips and strike wedges) — found **no concealed-difficulty or
  telegraph lies**: every lethal windup is >= the 24t reaction floor, aim-locked shooters fire
  down the drawn vector (the elite's re-aim cheat is already fixed at
  `src/sim/sim_world.gd:3474-3479`), the mg_nest's drawn lane is computed through the sim's own
  lead function so the painted lane is the lane the round takes, `predict_grenade_landing`
  (`:2898-2928`) replays `_step_grenades`' exact integrator including the marsh drift and
  fuse-hand airburst, and off-… *(report text truncated at source)*. Recorded so the next lens
  doesn't re-audit the same roster cold.
- The 2026-07-26 snapshot this file's ancestor replaced was already marked STALE against
  [`FINDINGS.md`](FINDINGS.md) (62 of 115 entries already fixed at re-triage on 2026-07-28).
  Carried entries above are marked "not re-verified this run" for the same reason: trust the
  measurement, re-verify the predicate before fixing.
