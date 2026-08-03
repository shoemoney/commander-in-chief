# Backlog

Open defects, design calls and debt for Commander In Chief, as of **2026-08-03** (branch
`main` @ `34dd43f`, retriage against 21-commit window 390c12d..HEAD including critical `6fa0aaa`).

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

**Counts this snapshot:** 31 new open from the run (2026-07-31) **+ 2 audit-lens findings
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

---

## 2. Sim / gameplay defects — player-facing

### New this run (2026-07-31), measured unless noted

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
- ~~**Daily Run teaches "one attempt" — but the lock only arms at the debrief, so QUIT TO TITLE /
  RESTART makes today's seed infinitely scoutable.**~~ **RESOLVED 2026-07-31** — `d45132a`. 
  Verified `src/main.gd:_reset()` (~1487-1527): daily lock now arms at DEAL time via `_daily_done_seed = seed_v` written to disk before any play, and a reset while spent re-deals the SAME board demoted to unranked practice (`_daily = false`). Fully proven by `tests/test_menu_layout.gd:637` `test_daily_attempt_spent_on_any_abandon_path` (checks disk-persistence, demotion, Hall non-tagging, and TITLE row lock — all 4 assertions pass).
- ~~**DAILY RUN's "one attempt" is only enforced at the debrief — R/RESTART before the wipe
  retries the same seed, unlocked, forever.**~~ **RESOLVED 2026-07-31** — `d45132a` (same commit as above).
  Verified: `_reset()` path no longer bypasses the daily lock because the lock is now armed BEFORE play (at `_start_run()` for new daily, or at `_reset()` for a spent one seeking re-deal). The measurement "seed 1017050458" from `start_daily()` → `_reset()` → same seed now correctly resolves to the DEMOTED practice board — the redealt board is the same because the spent seed stays in `_daily_done_seed`, and demotion (`_daily = false`) is the only escape. Fully resolved, all 4 paths (quit/restart/wipe/victory) tested.
- **NG+ HARD scores ~1.58x a normal campaign and lands on the same Hall of Fame and Steam
  leaderboard with no marker — the board flags *ASSIST and *DAILY but not the toggle that
  inflates score.** STILL OPEN — verified unchanged 2026-08-03.
  `_record_run`'s board tag dict (`src/main.gd:15` area) is `{"streak":..., "won":..., "daily": _daily, "assist": _assist}` — no `"hard"` key. Measured +58% score, +70% kills vs normal campaign (elites pay 25c vs 10c, so harder = more income). Leaderboard remains untagged.
- **Grenade-family hits on bosses emit no `boss_hit` feedback event (bullets do).** 
  Confirmed still true: `_damage_boss` (`src/sim/sim_world.gd:6713`) has no `boss_hit` emit on its non-lethal arm; grenade call sites at `:3226`/`:3235` in `_explode`. OPEN. 
  **REJECTED FIX:** `6fa0aaa`'s own message explicitly evaluated and REJECTED a naive fix here ("the proposed grenade feedback would have made `_explode`'s five callers lie") — the underlying asymmetry is real and open, but a blind `boss_hit` add to `_damage_boss` would create five false-positives in non-boss contexts. Needs a differently-shaped fix (a distinct event, not blind `boss_hit` adoption).
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
- **The shop bills full price for air it partially delivers.** Receipt lie half is **RESOLVED 2026-07-23** — `6fa0aaa`. 
  The charge-fairness half remains **OPEN**: `src/sim/sim_world.gd:_try_buy` (~2493-2521) still charges the FULL `_supply_cost` regardless of how little `_apply_supply` actually delivers; `_supply_full` (denies at hard cap) is the only guard. Where: `_apply_supply` caps with `mini(MG_AMMO_MAX, +30)` / `mini(GRENADE_AMMO_MAX, +4)` (`:2093-2095`), `_supply_full` only returns true AT cap (`:2239-2247`), `_try_buy` debits full cost (`:2300-2342`). Verify receipt fix in §3; this entry tracks billing fairness only.
- **The revive's whole go-to-the-body grammar — body beacon, dashed tether, off-screen chevron
  "so the revive has a spatial target" — signposts a dangerous rescue run the sim does not
  require: E revives from ANY distance and teleports the partner to your side.** CORE DEFECT UNCHANGED. 
  However, `34dd43f` improved the snap: `_try_revive` (~2016-2060) now snaps BOTH x and y to the reviver ("At their side" is BOTH axes; previously only y snapped, x stayed at death location). This fixed the worse sub-case (landing beside your own killer) but NOT the "no distance check" complaint itself — the instant-revive-from-anywhere remains true. The entry's original measurement "~284px to P1's row" is now stale (X no longer stays put) — new snap is bidimensional. Underlying asymmetry (no distance check) is still open and requires a differently-shaped fix than a distance test (the endgame revive-cost scaling makes distance-scaled cost more honest).
- **A tank parked directly on a free supply crate collects nothing and says nothing.** 
  Confirmed still true: `src/sim/sim_world.gd:1171` `if p["in_tank"] >= 0: ...; continue` still runs before `_collect_pickups` (called at `:1543`). OPEN.
  NOTE: `6fa0aaa` fixed the revive-key swallow on this same `continue` line but did NOT touch the pickup-collection swallow — different consequence of the same line, still open. The tank's tread grammar touches everything else (crushes infantry, flattens sandbags, detonates barrels, rescues pilot on contact) so this reads as an oversight not a design choice.
- ~~**Closed gates pin the camera — and the spawner keeps planting rooted MG nests 24px above
  the viewport, so 4-6 invisible, unflankable turrets fire lead-computed bursts into the game's
  longest fights (including the no-revive finale).**~~ **RESOLVED 2026-07-23** — `6fa0aaa` 
  ("Fix: closed gates pin camera, rooted MG nests hidden").
  New `_rooted_spawn_y()` helper + `ROOTED_KINDS` list used by both `_step_spawner` and endless `_step_waves` (previously only endless had the fix); grep `_rooted_spawn_y` in sim_world.gd to confirm both call sites. Measured peaks of 4-6 invisible turrets are now clamped to visible spawn height.
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
- ~~**"WAVE CLEARED — SHOP OPEN" fires while a live Spotter is still shelling the shop window.**~~ **RESOLVED 2026-07-23** — `6fa0aaa` 
  ("Fix: Spotter fires through shop intermission").
  Observer now sleeps through the intermission (reuses the `_step_mast_hazard` idiom) instead of exempting itself from every despawn; grep for the observer sleep state near `_step_mast_hazard`/`observer` in sim_world.gd to cite the exact lines in the edit.
- **Miniboss fly-in airstrike window remains a partial whiff.** The endless intermission is now
  gated because `enemies` is provably empty for the whole 45t telegraph (`_step_waves`
  early-returns; strike resolves before `_start_wave`) — that half shipped in `8425bd7`. The
  wave-5+ miniboss fly-in is a second window where `_fire_mission` (`:2071`) spares bosses, but
  the trickle keeps spawning so it is NOT provably empty — the plan explicitly banked it. A
  strike bought during the fly-in still kills only trickle infantry. *(Reasoned, not driven —
  banked by the plan.)*
- ~~**A tank driver's (or gunner's) revive key is a fully swallowed input the HUD is actively
  prompting — the arbitration mutes the cannon for a rescue the sim never performs.**~~ **RESOLVED 2026-07-23** — `6fa0aaa` 
  ("Fix: tank driver revive key swallow").
  Verified `src/sim/sim_world.gd:1171-1184`: the `in_tank >= 0` branch now checks `if inp.revive: _try_revive(i, p)` BEFORE `_drive_tank(...); continue`. Commit cites `tools/probe_tank_revive.gd` before/after (`revived=false`→`revived=true`).
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
- ~~**The supply receipt lies on partial stocks: wheel buy and SUPPLY CALL print "+30 AMMO" /
  "+4 GRENADES" while the sim clamps the grant to as little as +1 — at full price.**~~ **RESOLVED 2026-07-23** — `6fa0aaa` 
  (receipt half only).
  Verified `src/main.gd:8849-8856` `buy_float_text(kind, n)`: prints the sim-delivered `n`, not the catalogue amount, with a doc comment describing the exact old bug ("a top-up at 11/12 grenades delivers 1 and used to be announced with the catalogue 4"). `BUY_FLOAT` is now format strings (`"+%d AMMO"`) not fixed text (`src/main.gd:458`). The charge-fairness half (billing full price for partial delivery) remains open; see the entry above.
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

- ~~**Five teaching hints stamp hardcoded key letters (E/F/Q) into verbs the rebind system can
  move — including the one that fires while you're bleeding out.**~~ **RESOLVED 2026-07-23** — `6fa0aaa` + `c62c4fe`.
  Verified live in `src/main.gd`: claymore hint (~2365-2366), revive/war-chest hint (~2870), supply-wheel hint (~5272), deploy-early hint (~5277), airstrike-wheel hint (~5282) — all now read `Art.pad_button_label(pad_bind_for_glyph(...))` / `GameMenu.key_label(bind(...))` / `bind_for_glyph(...)` instead of a stamped letter. Line numbers in backlog are stale (file has grown) but the fix is real; landed across `6fa0aaa` (item 9, partial) and `c62c4fe` (round 2, "gamepad rebinds are finally visible to every prompt").
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
  this actually is — the worse way to play. FLAGGED FOR RE-MEASURE: `6fa0aaa`'s commit message claims "item 8 (tank rebalance): already fixed in `03cb32f`", but `03cb32f` is an ANCESTOR of `390c12d` (the backlog snapshot) — meaning it already existed when the backlog was written with explicit skepticism ("Cycle 2's first fix attempt made the metric move the WRONG way and was rejected at closeness 56"). `6fa0aaa`'s claim likely refers to the SAME commit the backlog already distrusts. Do not mark resolved on this prose contradiction — re-measure the tank safety/lethality metrics before trusting any fix claim.
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
  sim's own clamp forbids. **46–58% of every campaign** measured as camera-pinned. FLAGGED FOR RE-VERIFY: `6fa0aaa` states items 1b/1c ("`camera_held()` already gates the stall accumulator... two ratchet tests") were found ALREADY IMPLEMENTED during its own investigation, meaning this may already be non-reproducible. Not independently re-verified this pass — recommend grep `camera_held()` call sites in the stall-accumulator logic (`sim_world.gd`) and re-run the entry's original measurement before striking; flag as "likely stale, re-verify before either resolving or keeping."
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

### New this run (2026-07-31)

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
- ~~**Rolling in water prints "NEED COINS" — a duplicate match arm silently kills the honest
  teaching branch.**~~ **RESOLVED 2026-07-23** — `6fa0aaa` 
  ("Fix: water-roll deny message lost to match collision").
  Verified only ONE `"deny":` match arm now exists in `src/main.gd` (line 2592), with `"water": "NO ROLL IN WATER"` and an inline comment describing the exact old bug it replaced (2598).
- **Airstrike hint gates on the 100c base price, not the depth-creeped price.**
  `src/main.gd:4977` still gates the teaching hint on `sim.war_chest >=
  SimWorld.SHOP_AIRSTRIKE_COST` (base 100c), but the wheel charges the depth-creeped price —
  measured **150c at wave 6** in this cycle's own capture (c6-wheel-hold.png reads "AIRSTRIKE
  150 HOLD"), **125c at wave 3** per the goal's numbers. From wave 3 up the hint can fire while
  the strike is not actually affordable. Verified the line is unchanged by reading it after the
  diff. *(Reasoned from code + capture, not driven.)*

### Carried from the 2026-07-29 snapshot — re-flagged 2026-07-31, still open

- ~~**Five teaching hints stamp hardcoded key letters (E/F/Q) into verbs the rebind system can
  move — including the one that fires while you're bleeding out.**~~ **RESOLVED 2026-07-23** — `6fa0aaa` + `c62c4fe`.
  Verified live in `src/main.gd`: claymore hint (~2365-2366), revive/war-chest hint (~2870), supply-wheel hint (~5272), deploy-early hint (~5277), airstrike-wheel hint (~5282) — all now read dynamic bind labels instead of stamped letters. Landed across `6fa0aaa` (item 9, partial) and `c62c4fe` (round 2, "gamepad rebinds are finally visible to every prompt").
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

### New this run (2026-07-31)

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
  hidden or properly layered behind a full-screen menu mask. FLAGGED FOR RE-RENDER: `c62c4fe`'s round-2 verification pass found an architecturally identical claim (world markers leak through modal cards) IMPOSSIBLE BY CONSTRUCTION (menus are `Control` children of `$HUD` `CanvasLayer` layer 2; world draw pass is z=0; world-space labels cannot paint over menu cards). This is strong circumstantial evidence the Victory-card entry is also UNREAL, but it targets a different specific screenshot/claim. Do not mark UNREAL from architecture alone — re-render the actual Victory-card screenshot and check the CanvasLayer ordering for THIS claim specifically before striking.
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
  banked — the ratio moved the wrong way anyway.)*

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
