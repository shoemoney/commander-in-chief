# Backlog

Open defects, design calls and debt for Commander In Chief, as of **2026-08-21** (branch
`main` @ `9bb1cdb`).

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

**Counts this snapshot:** **96 open findings** and **37 owner-decision reports** handed over from
the 2026-08-01 → 2026-08-21 window (`390c12d..9bb1cdb`, 60 commits). The 37 reports consolidate
into **20 numbered decisions (#15–#34)** — five lenses filed the HUD-channel call and three filed
the deletable-miniboss call, so those entries keep **every** lens's measurement rather than
picking one. Of the 96 findings, **12 were measured against an in-flight diff and are already
RESOLVED on `9bb1cdb`**; each says how it was re-verified and stays in place rather than being
deleted. **~120 titled fixes** are on the run's shipped list — **29 mapped to shas in this
window**, and **13 that could NOT be corroborated in the code are listed as such in §8 and remain
open in their sections.** Older carried entries are marked per-section.

> ⚠️ **Second standing warning, new this snapshot: a finding measured against a work-in-progress
> diff is not a finding against HEAD.** Twelve entries below were filed by review lenses reading a
> branch mid-flight and were fixed before the commit landed. Every entry that claims a defect on
> HEAD in this snapshot says whether it was re-verified against `9bb1cdb` and by what command.
> Re-verify before you fix; the predicate may already be gone.

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

> ### ✅ OWNER RULINGS — 2026-08-21
> Four decisions answered by the owner directly. Do NOT re-open these in a later cycle; a
> reviewer re-reporting one of them should be dismissed with a pointer here.
>
> | # | Question | Ruling |
> |---|---|---|
> | §1.2 | Shop-wheel plate alpha vs. hazards reading through | **Keep the readable plate; PAUSE the hazards during the buy.** The lower alpha was the wrong lever — this is the fix the entry itself named. |
> | §1.9 | Hulk salvage at grenade cap | **Refuse when the strip would deliver 0; allow at >= 1.** ⚠️ Accepted consequence: players spawn AT `GRENADE_AMMO_MAX`, so a fresh player meets a hulk wall they cannot clear until they spend a grenade. The refusal is therefore required to be AUDIBLE (`deny{why:"salvage_full"}`) so the rule is readable rather than inferred. |
> | AAA-run | Off-frame world-label suppression | **Add a small negative-y tolerance** (~`Rect2(0,-24,640,384)`), so a subject just above the viewport keeps a clamped label. The 0%-overlap result (from 46.32%/47.01% across 14,400 frames) must NOT regress — measure it after. |
> | §1.10 | Flat airstrike deny removing the skilled pre-call | **Keep the deny.** The `pending_airstrike` freeze route is explicitly declined; the trade-off is now permanent by decision, not by omission. |


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

### New 2026-08-21 — from the `390c12d..9bb1cdb` window

Several lenses reported the same decision independently. Where that happened the entry keeps
**every** lens's measurement verbatim rather than picking one, because independent measurements
of the same number are the only evidence that the number is real.

15. **NEW 2026-08-21 — The HUD's stacked-chrome channel is now governed by one hand-picked
    number, and paying for it moved two shipped screens.** Shipped in `66d146a`. Five lenses
    reported this; all five measurements are kept.
    - `BOSS_BAR_TOP` moved **64.0 → 77.0**, pushing the whole top-center boss/mini HP-bar stack
      **13px DOWN** into the play field (slot-2 bar bottom moves **121 → 134**). That is a
      visible layout shift in every shipped screenshot and marketing frame, and it trades 13px
      of world visibility at the top of the screen for the 6px channel under the corner panel.
      The alternative — leaving the bar line at 64 and shrinking the corner panel or the label
      plate instead — was not costed. Measured: `panel_bottom()` maxes at **60** in
      1P-endless/2P-campaign/2P-endless, so the minimum `BOSS_BAR_TOP` that clears it by
      `MIN_HUD_CHANNEL=6` is **77**; anything less needs the panel to give ground instead.
    - `MIN_HUD_CHANNEL` was set to **6.0** and `BOTTOM_RESERVE_GAP` to `MIN_HUD_CHANNEL+2` =
      **8.0**, overturning a documented, deliberate `BOTTOM_RESERVE_GAP := 3.0` and its
      band-contract docblock. 6 and 8 are asserted as hard floors across **~12,700 pair
      checks**, so every future piece of HUD chrome is now bound by them. Measured basis: the
      true channel on HEAD was **1px** between two dark plates overlapping **225px**
      horizontally. Whether 6/8 is the right house minimum at 640x360 (vs 4, which would leave
      `BOSS_BAR_TOP` at **75**) is a taste call the reviewer cannot make.
    - Second lens on the same number: `MIN_HUD_CHANNEL` at 6.0 px is what moved the
      verb-chip/colossus channel from a measured **1 px** to a measured **8 px**. Nothing in the
      repo says what the intended channel is — 6 was chosen by the implementer. At 640x360
      upscaled 2x-3x this reads clean in my capture of `05-foundry-colossus-last-stand`, but it
      also pushed the whole bottom overlay cluster **up 7 px** (lift **48 → 55**) and the boss
      bars **down 13 px**, a visible layout change to two shipped screens. If the owner has a
      house number for HUD breathing room, set it once here and let everything derive.
    - Third lens: the measurement justifying `BOTTOM_RESERVE_GAP` 3.0 → 8.0 is sound (the true
      channel was 1px, not 3, because `COLOSSUS_BLOCK_TOP` was a **2px-optimistic** ascent
      mirror), and 8px is screenshot-confirmed as readable separation. But 6.0 was chosen **by
      eye, not against a legibility criterion**. Owner call: is 6px the house minimum, or should
      it be derived from the font's line box?
    - Fourth lens, on the boss bars specifically: `BOSS_BAR_TOP` 64.0 → 77.0 pushes the bars and
      their phase labels 13px down on **every boss encounter and in Boss Rush**. Re-captured
      `04-bridge-gunship.png` and confirmed the result is legible and clear of the corner panel
      (on HEAD the panel buried the top of the label) — but this is a shipped-layout change made
      to fix a defect **the reviewer never reported**. The alternative fix — shrinking the corner
      panel so `panel_bottom()` clears the existing block top — was not attempted. **Is 13px of
      play field the right currency to pay, or should the panel shrink instead?**
16. **NEW 2026-08-21 — `LAST_STAND_Y` moved 350 → 353, not the 352 the plan specified**,
    putting the banner plate at **341..358** with **2px** to the 360 viewport floor. The extra
    pixel buys `MIN_HUD_CHANNEL` **exactly** against `COLOSSUS_BLOCK_BOTTOM=335` rather than
    5px. Deliberate and documented in the constant's comment, but it is a 1px deviation from the
    approved plan on the element closest to the screen edge — worth a nod before it becomes the
    reference value. Second lens, same element: the LAST STAND banner plate now occupies
    **y 341..358 of a 360-px-tall viewport — 2 px from the floor**. That is deliberate (the
    comment says "still on the viewport floor") and no test complains, but it is the tightest
    margin on screen and **there is no constant expressing "how close to the floor is
    acceptable"**. Worth an explicit floor-clearance constant if the owner cares.
17. **NEW 2026-08-21 — Neither boss phase label is localized, and neither scales with TEXT
    SIZE.** Two separate exemptions on the two highest-stakes strings on screen, both banked
    deliberately by the implementer and both **re-verified open on `9bb1cdb`**
    (`grep -n 'GUNSHIP_PHASE_NAMES\|COLOSSUS_PHASE' src/main.gd` → `main.gd:11026` and
    `:11193` interpolate the bare consts; no `TranslationServer.translate()`, no `Art.fs()`):
    - **Localization:** `main.gd` draws the English literal at the gunship and colossus draw
      sites, so the localization suite cannot see them, and a longer translation would widen the
      plate past everything the new **12,700-pair** ratchet measures. The new test pins the
      related `Art.fs()` gap explicitly but deliberately does not pin this one. **Whether
      shipped locales are allowed to leave boss names in English is a product call.**
    - **Accessibility:** neither label calls `Art.fs()`, so the TEXT SIZE setting does not scale
      them — the new test asserts this as a known gap (label width **byte-identical at
      text_scale 1.0 and 2.0** while `Art.fs(10)` correctly returns **20**). Putting them on
      `Art.fs()` would widen the plates and require the ratchet to grow a text-scale arm.
      **Owner decides whether the two most important strings on screen are exempt from the
      accessibility setting.**
18. **NEW 2026-08-21 — The shutdown-leak gate is set at ZERO with no floor and no exemption,
    and every measurement behind it was taken on macOS/arm64 under the headless dummy renderer.**
    CI runs a 3-OS matrix (Linux · macOS-arm64 · Windows) and **those two other runners are
    unmeasured**. If Godot's Linux or Windows headless build reports even one
    environment-specific engine leak at exit, the gate goes red on a clean commit — and
    CLAUDE.md itself warns that a randomly-red gate stops being read (that is exactly why
    `test_perf.gd` was moved to `OPT_IN_SUITES`). **Owner call: push and find out, or soften the
    CI copy of the gate to a warning for one cycle while the other two OSes are characterised.**
19. **NEW 2026-08-21 — The plan named TWO probes for promotion into `tools/`; only one
    shipped.** `probe_rooted_cover.gd` (the census) shipped; `probe_rooted_trap.gd` (the offset
    x-position trap sweep) was folded into ratchet B
    (`test_rooted_unit_born_on_cover_is_killable_from_the_south`) and discarded. Defensible (the
    ratchet has no sampling window and the probe would) — but the repo now has **no standalone
    measuring tape for "is THIS unit at THIS position shootable"**, which is the question the
    next cover/hitbox change will want to ask. Owner call whether to ship it.
20. **NEW 2026-08-21 — `_spawn_clear_x` duplicates the endless spawn-x domain as a magic
    number.** It bounds its search to a literal `[24, 616] * F_ONE` (`sim_world.gd:4325`,
    `:4328`), mirroring the endless wave spawner's raw `rng.range_i(24, 616)` roll. There is no
    existing named constant for that domain — `ARENA_MARGIN` is `96 * F_ONE` and means something
    else (colossus/hazard corridor), and `SCREEN_W_FP` is the full 640. So the pair is a
    duplicated magic number that **will silently desync if the spawn-x roll is ever retuned**.
    Whether to introduce a shared `SPAWN_X_MIN/MAX` (and re-point the roll at it) is a design
    call the implementer did not make alone.
21. **NEW 2026-08-21 — The cover seam displaces MOVERS as well as rooted units, and that is
    what cost a golden re-record.** `_spawn_enemy` (rushers/elites) and every archetype
    `_spawn_special` birth now get shoved out of all four armor families, not just rooted ones.
    MEASURED: reverting **ONLY** `_spawn_enemy` reproduces **all six retired goldens
    byte-for-byte**, so the rooted calls are golden-inert and **the walker seam owns 100% of the
    churn**. A walker born in cover self-corrects in a few ticks (it moves), so the walker half
    is **prophylactic rather than a defect fix**, and it cost a golden re-record. If the house
    rule is "behavior changes only at phase boundaries", shipping a golden re-record for a
    prophylactic change is the owner's call.
22. **NEW 2026-08-21 — The wave-5 supply pod's rim rocks land 4px from the rooted spawn row and
    nothing in the tree pins that relationship.** Rim rocks at **y = -312**
    (`ARENA_L_SLOTS[5] = [320,-312]`) while `_rooted_spawn_y()` is pinned at
    `camera_top + 52 = -308` in endless. **Four pixels** is the whole margin between "legitimate
    cover" and "trap" for a **10px-reach ghillie**. Neither constant references the other and no
    test asserts the gap. Whether to make the rooted row derive from (or assert against) the
    arena slot geometry is a product/architecture call.
23. **NEW 2026-08-21 — The wave-5 miniboss can be destroyed before it ever lands, and nothing
    pins whether that is intended.** Shipped in `016b4cd` (the fly-in became damageable). Three
    lenses measured this independently; all three sets of numbers are kept, because they
    disagree in rate and agree in kind.
    - Lens A, shipped bot over **5 endless seeds**: killed mid-approach on **seeds 11
      (phase_t=-95)** and **99 (phase_t=-16)**; reduced to **hp 8/40** by arrival on seed 7;
      **31/40** on seed 42. The plan asked for a ratchet pinning "cannot be deleted before it
      lands"; the implementer correctly measured that claim as **false** and substituted a
      tracking-reward pin instead, which is the right call. Boss HP at wave 5 is **40**
      (`BOSS_HP`, `sim_world.gd:708`) against a **420-tick** window in which a perfectly-tracking
      1P shooter lands **~53 rounds**.
    - Lens B, `demo_input` bot, **god_mode, 7 seeds**, `SimWorld.new(seed, 1, 'endless')` driven
      to the miniboss: **3 of 7** seeds destroy it mid-approach (**seed 11 at phase_t -170, seed
      3 at -227, seed 23 at -33**); the 4 that land arrive at **8, 4, 32, 22 of 40 HP — median
      15/40**. The coder's own comment claims **2 of 6 and median 23/40** without god_mode;
      directionally the same. So roughly **40%** of the time the "GUNSHIP INBOUND" banner, alarm
      and `_trauma 0.4` announce a boss that dies before it is even clearly visible through the
      HUD panel.
    - Lens C, shipped `demo_input` bot, **7 seeds**, 6 field a miniboss: **2 of those 6** destroy
      it mid-approach (**seed 11 at phase_t -95, seed 99 at phase_t -16**) — the arrival beat,
      the strafing run and the whole engaged cycle never happen. Of the 4 that land, hp@arrival
      is **8 / 15 / 31 / 38 (median 23 of 40)**.
    - **Instrument limit, stated by two of the three lenses:** these are the shipped BOT's
      numbers with open-loop aim (`sector_probe.gd:12-20`), not a human's. A human tracking the
      hull is strictly faster, so **the real skip rate is higher** than 2-in-6.
    - **DECIDE:** is a deletable approach the intended skill payoff — in which case pin a
      **FLOOR** (e.g. the bot must not average better than N HP of damage during the window, so a
      later radius/HP edit cannot quietly make it free) — or must the gunship always land, in
      which case it needs damage resistance or a shorter/faster ramp during `phase_t < 0`? Right
      now it is pinned in **NEITHER** direction.
24. **NEW 2026-08-21 — The fly-in ground shadow is pinned to the LANDING PAD, not to the hull,
    and it is now the only thing left at a point the helicopter is not at.**
    `main.gd:10892` (re-verified on `9bb1cdb`): `_ground_shadow(ground + Vector2(0, 30),
    8.0 + eta_f * 18.0, 0.12 + eta_f * 0.30)` where `ground` is the arrival point — so at
    `phase_t -420` the shadow sits at screen **(320, 80)** while the hull is at **(470, -5)**,
    the same **159.8 px** the hitbox fix just closed. It grows **8→26px / 0.12→0.42 alpha** as
    the hull descends, which reads as a deliberate landing-zone telegraph. But it is now the only
    piece of the gunship still anchored to a point the helicopter is not at, up to 159.8 px from
    the caster. **Pinned telegraph or tracking caster-shadow — it cannot honestly be both now
    that the hitbox moved to the hull.** If it stays pinned it probably wants to stop *looking*
    like a shadow (a reticle/landing-ring reads as a telegraph; a soft ellipse reads as a shadow
    and lies). Not a defect either way; it needs intent.
25. **NEW 2026-08-21 — The fly-in is no longer a cinematic, and that overturns a stated intent
    on purpose.** `sim_world.gd:6303-6306`'s stated intent — "phase_t starts NEGATIVE: a 7s
    fly-in (8v ramp smoothing — the gunship no longer lands on top of the wave_start card)" — was
    overturned by `016b4cd`, and the diff does say so in its replacement comments. **Confirm you
    want that:** the smoothing beat survives (ramp, haze, scale and rotor spin are untouched),
    but the gunship is now a **live target for the entire 7 s** rather than a cinematic. If the
    original card-collision problem is still a concern, the fix for it is now the spawn-tick
    banner ordering, not invulnerability.
26. **NEW 2026-08-21 — Field Manual page-count vs page-density.** Entry-granular pagination adds
    a leaf at **125% WAR CHEST (2 → 3)**, **200% WAR CHEST (5 → 6)** and **200% SPECIALS
    (4 → 5)**, and leaves pages as sparse as **14%** and **34%** fill, in exchange for never
    breaking a sentence. The alternative — allow a mid-entry cut when the break lands on a comma
    or clause boundary — would keep pages full at the cost of the reviewer's original complaint
    recurring in a milder form. **No test currently pins either side**, so whichever way this
    goes it should get a ratchet.
27. **NEW 2026-08-21 — Should the broadcast mast get a visual arrival at all?** Its
    `broadcast_pulse` fires on its first stepped tick (measured campaign **n=20, min=max=1
    tick**) and `main.gd:3180-3186` already draws that as an **8→140 px** shockwave, so the plan
    called it covered and deliberately excluded the mast from the opacity ramp. But the mast is a
    **43px** `radio_tower` plus two **48px** base arcs and it is now the only rooted kind that
    appears at **100% opacity with no ramp** — a player watching one wave will see the mast pop
    while the nest beside it fades. The cycle goal's wording ("every turret, mast and hidden
    sniper") would read as covering the mast too. If the owner wants it to fade, its draw branch
    needs to read a ramp key that `_consume_events` currently and intentionally does not
    register. Only the owner can say whether the ring is enough of an arrival for that silhouette.
28. **NEW 2026-08-21 — Rooted arrival audio borrows the STRUCTURAL-breach channel.** The arrival
    cue is `alarm_low` at **-15 dB / 0.55 pitch**, sharing a sample with `flank_warn` (-11 dB),
    `flank_breach` (-6 dB) and `rear_warn` (-12 dB) — all of which the file's own **a1-13
    taxonomy comment reserves for STRUCTURAL breaches**. Up to **three rooted units land per
    endless wave**, so this adds a quiet structural rumble **~3x/wave** to a channel the taxonomy
    says means "the walls answer". Whether a grunt-tier emplacement belongs in that vocabulary at
    all, versus a dedicated dirt/thud sample, is a sound-design call.
29. **NEW 2026-08-21 — Rooted units can now be born as far south as screen row 287, i.e. BEHIND
    the player.** Measured on the god-mode bot in endless: **146 of 168 births (86.9%)** land
    south of the player, vs **93 of 115 (80.9%)** at HEAD — so it was already the norm, but **the
    southern tail is new**. In campaign the camera scrolls past them and `_step_enemies` culls at
    `camera_top + 420` (`sim_world.gd:3542`), so the off-screen-but-still-firing window is **60
    px of advance either way, identical to HEAD** — checked; it is not a regression. **The product
    call is whether a rooted MG that materialises behind the player is the fight you want**; a
    `y > player_y` exclusion (or a southern cap around row ~240) is the lever if not.
30. **NEW 2026-08-21 — How far is the ground repeat worth chasing?** Two lenses, same
    conclusion, different numbers; both kept.
    - Lens A: the residual 64px repeat measures **0.62–0.70 lag-64 autocorrelation** on real
      frames but only **~4.4% luminance amplitude** (**3.29 std on a 74.02 mean** at the sector-1
      stop), and **at 10x contrast boost I could see no lattice in the frame either before or
      after** this diff. Killing it properly means touching the BASE layer (a second seamless sand
      strip at 0.75 scale / 96px pitch at partial alpha, or a hashed per-row x phase on the
      existing tiled strip), which is a bigger visual risk than the tell it removes. **Ship the
      −5% and close the finding, or spend a cycle on the base layer?**
    - Lens B: the repeating signal is **~3.3 luminance units on a 74 mean (4.4%)**, and **at 6x
      high-pass contrast boost I could not see a grid in EITHER the before or the after frame**.
      Killing the residual 96px repeat costs a second source tile (art + `ASSETS.md` provenance)
      or a shader on the base strip. **If the owner's read is that the original reviewer
      over-claimed this tell — which the verification's own numbers support — then the shipped
      diff is already the right stopping point and this should be closed as won't-fix rather than
      worked.**
31. **NEW 2026-08-21 — The off-frame world-label gate deliberately overturns the documented
    keep-place rule: a label whose subject the player cannot see is now SUPPRESSED, not
    relocated.** Shipped in `9bb1cdb`. Four lenses reported the same trade; all four framings
    are kept because they photograph different casualties.
    - The gate can now suppress a label whose **SUBJECT is on-screen**. A ford/objective sign
      anchored ~20px above its subject, with that subject at screen **y < 20**, produces a
      want-rect entirely above y=0 and is dropped; previously it clamped to y=0 and printed
      (under the HUD panel). Net effect at the very top edge is **a brief label flicker as the
      world scrolls in**, traded against the **46%-of-frames** overprint the gate removes.
      Confirm the flicker is the trade you want, or add a small negative-y tolerance (e.g.
      intersect against `Rect2(0,-24,640,384)`) for anchored objective signage only.
    - Confirm the trade is what you want for **ALL 15 producers** (LOW FUEL, ESCAPING!, RESCUE
      +N, SILENCE THE SPOTTER, rally countdown, GET UP, REVIVE…), not just the crate labels the
      reviewer photographed — **an off-screen ESCAPING! prisoner now has only the chevron cue.**
    - It is right for a crate 40px above the frame, but a **subject 1px off the top edge loses
      its label entirely** with only the threat chevron as a cue. **Is suppression correct at the
      boundary, or should a subject within ~8px of the frame edge keep a clamped label?**
    - Measured payoff, so the trade is priceable: **0 label-on-label or label-on-player overlaps
      remain across 14,400 sampled bot frames, versus 46.32% / 47.01% at HEAD.** The casualty is
      that e.g. a downed partner just off the top edge no longer shows `REVIVE <cost>` at all,
      where HEAD clamped it to y=0. Routing those through the existing off-screen chevron /
      `CALLOUT_OVERFLOW` tail with an explicit indicator is the alternative.
32. **NEW 2026-08-21 — The repo now has TWO GL-only rendered-pixel probes with zero callers and
    no CI job that can run either.** `grep -rn ground_lag . --exclude-dir=.git` finds only the
    file itself and two test comments; `tools/ground_profile.py` has **zero** references anywhere
    (both re-verified on `9bb1cdb`). `.github/workflows/ci.yml` runs only `--import`, `lint_sim`,
    `lint_assets`, `i18n_check`, `smoke`, `run_tests` and the export/soak jobs — **no
    `gl_compatibility` job, no xvfb** (`grep -n 'gl_compatibility\|xvfb' .github/workflows/ci.yml`
    → no matches). GL **does** work on the dev box (14 signature shots in under 3 minutes), so the
    gap is specifically the Linux runner needing xvfb. **Owner call: wire a
    `--rendering-method gl_compatibility` + xvfb job that runs both at a fixed threshold, or
    accept that rendered-composite autocorrelation is permanently a manual developer-machine
    check on a 4.4%-amplitude signal.**
33. **NEW 2026-08-21 — Ground dressing now costs +25 draw calls/frame (+9.5%) as a standing
    price, and 8 base strips cost 4.00 MB of raw pixel data.** Two knobs, one budget question.
    - Draw budget: `tools/perf_probe.gd` on real GL, **121 frames**, driven by `demo_input`:
      `draw_calls_avg` **259.760 → 284.512**, `draw_calls_max` **272 → 309**, `cpu_ms_avg`
      **0.801 → 0.883**, `cpu_ms_max` **2.557 → 2.681**. Fine against a **16.7 ms** budget on the
      machine measured (0.88 ms of frame), but **the export targets include Windows/Linux boxes
      nobody here has profiled**, and `test_perf.gd` is sim-tick only and cannot see this at all.
    - Memory: `GROUND_BASE_VARIANTS = 8` costs **4.00 MB of raw pixel data** (measured; **~5.6 MB
      VRAM** per the diff's profiler note; `perf_probe` confirms **62.57 MB → 68.15 MB**) to
      attenuate a residual the diff itself measures at **+0.041 → +0.007** going from N=4 to N=8.
      A real but small win for 2 MB. **Nothing in the repo states a VRAM budget**, so whether that
      trade is right for the lowest-spec target is the owner's.
34. **NEW 2026-08-21 — The base sand pitch is now 96px while the dressing cell stays 64px, so a
    y-axis residual lives permanently at their lcm of 192.** Measured **+0.058 / +0.055**.
    Driving it out means picking a second non-commensurate dressing pitch or accepting it. The
    current choice trades a **4x reduction** for a surviving **192px** period; whether that is the
    right stopping point is the owner's.

---

## 2. Sim / gameplay defects — player-facing

### New this run (2026-08-21), measured unless noted

These come from the `390c12d..9bb1cdb` window. The behaviour lens drove the sim headlessly for
all of them; where an entry was reasoned from code instead, it says so.

- **The campaign has no fail state until its last 3%, then ends in under 5 seconds.** WHERE:
  `src/sim/sim_world.gd:1936` (`_step_dead_player`: `if last_stand: return` — no timer, no coin
  reader), `:1955-1961` (the broke fallback: campaign always calls `_respawn(p,
  _checkpoint_y())`, only endless latches the wipe), `:6433` (`last_stand = true` on colossus
  engage), `:2030` (`_try_revive` returns immediately under last_stand). MEASURED, **god_mode
  OFF, 4 seeds, `demo_input` driver**: seed 0xC0FFEE Last Stand began at **tick 6468 of a
  6510-tick run (99%)**, **19 knockdowns** before it, run over **42 ticks** later. Seed 1:
  **t=5957 of 6127 (97%)**, **20** before, dead in **170 ticks**. Seed 2: **t=6704 of 7016
  (96%)**, **21** before, dead in **312 ticks**.
- **Dying is the cheapest resupply in the game, and the gap TRIPLES as you go deeper.** WHERE:
  `src/sim/sim_world.gd:2117-2118` (`_respawn` hands back `MG_AMMO_MAX / 2` = **49 rounds** and
  **4 grenades**), `:997` (campaign `revive_cost = REVIVE_BASE_COST * mini(p["deaths"], 3)`,
  halved solo — **hard-capped, never scales with depth**), `:2369` (`_econ_scale`: every SHOP
  price is `base + base * _econ_depth() / 4`, **+25% per gate opened, explicitly uncapped**),
  `:2074-2078` (solo self-revive stands you up **where you FELL**, not at the checkpoint),
  `:2129` (plus `VEST_IFRAME_TICKS = 90` ticks of mercy). MEASURED by stepping a real campaign
  and printing both curves at every depth change: `depth 0 ammo 30 grenade 30 | …` *(report text
  truncated at source — the surviving figures are the constants and the depth-0 row.)*
- **Endless shoots you from off the top of the screen — 30% of ranged-enemy time is spent
  outside the drawn viewport.** WHERE: `src/sim/sim_world.gd:5929-5972` (every endless spawn
  lands at `camera_top - 24 * F_ONE`), `:1877-1885` (`_clamp_actor` pins the player's ceiling at
  `camera_top + 16`), `:5900-5906` comment ("endless never runs `_step_camera`, so `camera_top`
  is pinned at `-VIEW_H` forever"), and the standoff branches that then never fire: `:3665`
  (`if dlen > RIFLEMAN_STANDOFF`, **100px**), `:3727` (`ELITE_STANDOFF` **120px**), `:3758`
  (`GRENADIER_STANDOFF` **150px**), `:3785` (`SNIPER_STANDOFF` **240px**), `:3815`
  (`DRONE_STANDOFF` **130px**). WHAT HAPPENS: in Endless the camera is frozen and the spawn line
  sits **24px ABOVE** the viewport, while the player's own reachable ceiling is **16px BELOW**
  it. *(Report text truncated at source.)*
- **The Claymore is a strictly dominated 50-coin crate sitting next to a 30-coin crate that does
  the same thing four times.** WHERE: `src/sim/sim_world.gd:459-461` (`CRATE_POOL = [0,1,2,6,8]`,
  `CRATE_POOL_BASE = [30, 30, 60, 120, 50]` — the endless shop draws 3 of these 5 every
  intermission), `:450` (`SHOP_CLAYMORE_COST := 50`), `:446` (`SHOP_GRENADE_COST := 30`), `:2260`
  (`p["claymores"] = mini(CLAYMORE_CAP, p["claymores"] + 1)` — **ONE** charge), `:2247`
  (`p["grenade_ammo"] + 4` — **FOUR** grenades), `:4143-4147` (a tripped claymore calls
  `_explode(m["x"], m["y"])`), `:3157-3160` (a landed grenade calls the **SAME** `_explode`).
  Both items detonate through the identical `_explode` with the identical **`BLAST_KILL_RADIUS`
  of 30px** (`sim_world.gd:134`). *(Report text truncated at source at the "what differs" clause.)*
- **The kill streak stops paying at 20 and the counter keeps climbing to 121, so the chain has
  no tension to hold.** WHERE: `src/sim/sim_world.gd:3337-3360` (`_kill_enemy`'s streak block:
  tiers at **5 / 10 / 20** for **25% / 50% / 100%**, and `if kill_streak == 20` mints the
  Commendation and fires the surge), `:264` (`KILL_STREAK_WINDOW_TICKS = 90` — **1.5 seconds**),
  `:244` (`SPAWN_INTERVAL_TICKS = 45`). MEASURED, **4 seeds, god_mode on**: best campaign kill
  streak = **121**; best endless streak = **24**. The last tier is at **20**. So for **101
  consecutive kills** the HUD counted up while nothing about the reward changed. The window is
  the reason: **90 ticks against a field that spawns every 45** means the chain effectively
  cannot lapse during normal advance.
- **The BAIL OUT countdown is a race with no finish line — a tank cooking off on top of you does
  exactly nothing.** WHERE: `src/sim/sim_world.gd:2900-2909` (`_detonate_tank` → `_explode(tank["x"],
  tank["y"])`). `_explode` itself (`:3188`) scans enemies, sandbags, rocks, barrels, tanks,
  bunkers, the observer and every boss — **and has no player scan at all**. The crew ring at
  `:2863-2872` only hits players whose `in_tank == ti`. Compare `_detonate_barrel`
  (`:3296-3301`) and the claymore/mine trigger (`:4161-4166`), which both explicitly hurt every
  exposed player inside `GRENADE_RADIUS` *before* calling the same `_explode`. The prompt the
  player is reading while this resolves is `src/view/hud.gd:847`, `"BAIL OUT! %ds"`, over the
  `tank_ignite` alarm (`src/main.gd:517`). MEASURED directly (`.aaa/c4/blast.gd`) — a player
  standing on a cooking-off tank takes nothing.
- **The COURIER — the game's advertised 4x-bounty chase — runs off the BOTTOM of the arena in
  1.1 seconds and is deleted with no feedback at all.** Two lenses, kept together because the
  second measured it over more seeds. WHERE: `src/sim/sim_world.gd:4432-4438` (`_spawn_courier`),
  `:3556-3568` / `:3574-3586` (the flee step and the `courier_escape` event), `:3524-3526` /
  `:3542` (the silent sweep at `y > camera_top + 420`). Player-facing copy: `src/main.gd:390`
  `"COURIER — 4x BOUNTY, GUN IT DOWN"`. The lost-it sting is wired at `src/main.gd:575`
  (`"courier_escape": ["deny", -5.0, 0.7]`) and handled at `:3286`. WHAT HAPPENS: the flee vector
  is `fx = -dx; fy = -dy - 40 * F_ONE` — "run directly away from the nearest player, with a fixed
  **40px northward bias**". The escape line is **NORTH** (`y < camera_top - 30`). But the courier
  **spawns at `camera_top + 300`**, and couriers only exist in ENDLESS (measured: **0 spawns
  across 4 campaign seeds x 20,000 ticks**). MEASURED over **6 seeds** (`.aaa/c4/courier.gd`):
  **n=11 couriers, all in Endless**, all leave by the bottom sweep, which emits nothing.
- **The gold BOUNTY +N¢ fountain fires with a real number on three kill paths that bank exactly
  zero coins.** WHERE: `src/sim/sim_world.gd:3312` emits `{"t": "bounty_kill", ..., "coin": coin}`
  **unconditionally**; the actual payment is five lines later at `:3317`, gated behind `if not
  no_coin: war_chest += coin`. The view is `src/main.gd:2767-2770` — a five-coin gold fountain
  plus a distinct milestone fanfare, printing `"BOUNTY +%d¢"` straight off the event. Three kill
  paths pass `no_coin = true`: the airstrike screen-wipe (`_fire_mission`, `:2233`), the
  empty-magazine bash (`:1434`), and barrel/blast kills (`:3189`). All three still run the
  marked-target branch and still emit the toast with the full tripled figure. MEASURED on a
  marked elite killed three ways: the wipe printed **"BOUNTY +75¢"** for a **+0** chest.
- **The 100-coin airstrike also silently confiscates every bounty it kills — its true cost is
  more than double the sticker price, and nothing on screen says so.** WHERE:
  `src/sim/sim_world.gd:2231-2233` (`_fire_mission` calls `_kill_enemy` with `no_coin = true` for
  every enemy on screen). Player-facing surfaces: `src/main.gd:467` (wheel label "AIRSTRIKE",
  cost `SHOP_AIRSTRIKE_COST`), `:471` ("AIRSTRIKE INBOUND"), `:3337` (banner "AIRSTRIKE INBOUND —
  KEEP FIRING"), and the hint at `:5396`. **None of them mentions coin.** MEASURED against a
  **12-enemy screen — endless wave 10**, strike price after `_econ_scale` = **150¢**, chest delta
  after the wipe = **+0**, score delta = **+579**. Killing the same twelve by hand pays roughly
  **195¢** into the chest and **~1,950** score. So the real price of the button is **150 spent
  plus ~195 forfeited = ~345¢**, and it hands back about **30%** of the score.
- **The MG has no trigger, so the ammo counter is a 13-second stopwatch — and it runs out worst
  exactly where the game is hardest.** WHERE: `src/main.gd:6480` (`p1.fire = true`,
  unconditional) · `src/main.gd:6513` (the ONE refusal: an open supply wheel, which also hijacks
  your aim vector) · `src/sim/sim_world.gd:26` (`FIRE_COOLDOWN_TICKS := 8`) · `:242`
  (`MG_AMMO_MAX := 99`) · `:1445-1447` (the shot debits a round) · `:1383-1440` (the empty-clip
  bash) · `:30` (`BASH_RADIUS := 16`) · `:31` (`BASH_COOLDOWN_TICKS := 40`) ·
  `src/view/menu.gd:5358-5360` ("The weapon has no trigger — it fires on its own"). There is no
  fire key, no pad button, no trigger: `_gather_inputs` writes `p1.fire = true` every tick a run
  is live, so with ammo in the gun the sim runs a permanent **8-tick fire loop**. **99 rounds ÷ 8
  ticks = 13.2 s.** The only way to stop firing is to hold the supply wheel.
- **Endless's "threat-free" shop breather quietly spends half your magazine, and the shop sells
  it back to you.** WHERE: `src/sim/sim_world.gd:4769-4775` and `:6982` (the sim's own comments:
  "The intermission shop is sold as threat-free (the breather grade, the wheel scrim, the
  airstrike refusal all say so)" — and it sleeps the mast hazard and the Spotter to keep that
  promise) · `:5868-5872` (`_intermission_len`: **300 ticks at wave 1 down to a 120-tick floor**;
  the comment even says "a flat 5s of standing in an empty arena is just noise") · `:445`
  (`SHOP_AMMO_COST := 30`) · `:444` (`READY_HOLD_TICKS := 20`) · `src/main.gd:6480` (**nothing
  sleeps the player's trigger**) · `src/main.gd:8668` (view: "the shop is sold threat-free, so a
  warn ring drawn during the buy would lie"). The game goes to real trouble to make the window
  safe and then lets the permanent fire loop drain the magazine through it.
- **ARCADE's deepest chapter is a 4.8-second walk into a no-revive Last Stand with an empty War
  Chest — the mode's own menu copy promises a run.** WHERE: `src/view/menu.gd:5134`
  (`["mi_play", "ARCADE", "Choose a starting zone; play to the finale."]`) ·
  `src/sim/sim_world.gd:953-973` (`jump_to_chapter` — it moves the camera, the player and every
  streaming cursor, and touches **NOTHING the player carries**) · `:6495` (`last_stand = true`
  the instant the final gate scrolls into view) · `:2032-2033` (`_try_revive`: `if last_stand:
  return` — the coin reader is dead, **silently**) · `:1059` (all players down under last_stand
  latches `wiped`) · `:2418-2437` (`_supply_cost`: prices creep with `_econ_depth`, which a
  chapter jump correctly primes). CHAPTER SELECT relocates you to the mouth of the chosen zone
  with the **tick-0 loadout: 0¢ War Chest, 99 …** *(report text truncated at source.)*
- **An Endless wave can be held open forever by a ghillie that the game's own anti-stall has
  frozen into a target dummy.** WHERE: `src/sim/sim_world.gd:6140-6163` (the `all_cloaked`
  force-reveal in `_step_waves`), `:4028-4029` (`_step_ghillie`'s range re-cloak), `:6172`
  (`_wave_hostiles_cleared`), step order at `:1092-1094` (`_step_enemies` runs **BEFORE**
  `_step_waves`). A ghillie whose nearest player is beyond `GHILLIE_NOTICE_RADIUS` (**210px**)
  hits line 4029 and sets `submerged = true`. Later in the **SAME tick**, `_step_waves` sees that
  every remaining hostile is a cloaked ghillie and force-reveals it: `submerged = false`,
  `surface_ticks = GHILLIE_REVEAL_TICKS` (**26**). For the next 26 ticks `_step_ghillie` returns
  at its `surface_ticks > 0` early-out. *(Report text truncated at source.)*
- **Riflemen and elites shoot you from above the top edge with no committed-shot warning — the
  six other aimed archetypes all get one.** WHERE: `src/main.gd:13195` (`_draw_threat_pips()`);
  the kind filter at `:13208-13210` admits only `sniper`, `grenadier`, `ghillie`, `drone`,
  `technical`, `mg_nest`. **`rusher` and `elite` — the two most numerous shooters in the game —
  are excluded.** Their windups are emitted at `src/sim/sim_world.gd:3689`
  (`rifleman_windup`) and `:3751` (`elite_windup`); nothing clamps an enemy's y back into the
  visible band, and enemies spawn at `camera_top - 24` (`:4284`) while the player is clamped to
  `camera_top + 16` (`:1896`). A rifleman spawning 24px above the top edge, with the player
  hugging the band ceiling, is already inside `RIFLEMAN_STANDOFF` (**100px**).
- **The trench is tall grass without the anti-camp counter that was added because tall grass was
  too strong.** WHERE: `src/sim/sim_world.gd:1647-1655` `_concealed()` returns true for smoke OR
  `_in_grass()` OR `_in_trench()` — one predicate, three sources, hard-gating **every aimed
  shooter in the game** (call sites at `:3685` rifleman, `:3747` elite, `:3811` sniper, `:3906`
  technical charge, `:4031` ghillie paint, `:6589` colossus spray, `:6789` gunship).
  `:4776-4802` `_step_grass_flush()` is the counter — a telegraphed flush grenade every
  `FLUSH_CD_TICKS` (**600**) while an enemy is within `FLUSH_RADIUS` (**100px**) — and its guard
  at `:4785` is `not _in_grass(p)`. **The trench never enters it.** Trench geometry: `:4854-4869`,
  one hash-placed **120x48px** ditch per band from `COVER_VARIETY_SEG` (2) on.
- **Priced ground crates spend the shared War Chest on proximity — no button, no confirm, no way
  to decline.** WHERE: `src/sim/sim_world.gd:1903-1948` `_collect_pickups()`, called
  unconditionally from `_step_players` every tick. Line **1912** skips a crate only when the
  chest cannot afford it; line **1929** `war_chest -= cost` fires **on distance alone**
  (`PICKUP_RADIUS`, or `TANK_CRUSH_RADIUS` while riding). **There is no `interact` gate anywhere
  on the path.** The endless shop plants three of these at fixed **x 190/350/510** every
  intermission (`:6123-6127`). In 2P the chest is shared, so one player crossing a 150-coin vest
  crate spends the coin the other player was saving.
- **The endless revive price compounds on lifetime deaths while every other price creeps on
  depth — past a point, coin can only buy gear, and the advertised choice is gone.** WHERE:
  `src/sim/sim_world.gd:1000-1017` `revive_cost()` — endless is `REVIVE_BASE_COST * maxi(deaths,
  1) * (1 + wave / 5)`, **uncapped in BOTH factors**, halved solo. Supply prices scale on depth
  only, via `_econ_scale` (`:2371`) and `_supply_cost` (`:2430`), and the vest is explicitly
  capped at **120 base** (`:2447`). MEASURED (`.aaa/probe_economy.gd`, endless, solo, god mode so
  the run survives): seed 0xC0FFEE — **wave 12 chest 4,105 / revive 900**; **wave 15 chest 2,115
  / revive 2,200 (unaffordable)**; **wave 16 chest 3,165 / revive 4,400**. Seed 2 — **wave 16
  chest 2,385 / revive 4,700**; **wave 20 chest 7,520 / revive 7,250**, against an ammo price of
  **75** and a vest price of **150**.
- **`_cover_blocked` never checks enemies — arena drops can plant geometry on a LIVE rooted
  unit** *(pre-existing, plan-banked, latent not live)*. `src/sim/sim_world.gd:6137-6162`
  `_cover_blocked(bx, by, recycle)` — the 20px dedupe shared by the every-3rd-wave L-drop and the
  wave-5 supply pod — scans `sandbags` and `rocks` only. **It never looks at `enemies`.** The
  spawn seam `4d704cc` adds guards BIRTH; it cannot guard geometry arriving later. Verified by
  reading the function (identical on HEAD — the diff does not touch it). The plan measured the
  only `ARENA_L_SLOTS` cell that reaches the rooted row, **[320,-312]**, and a kind-0 rock centred
  at **y=-312** with a unit at **y=-308** is south-killable at **tick 33** — containment WITHOUT a
  trap. It becomes live the moment a slot, a rock kind, or the rooted row moves.
- **Player-built sandbag nests have no enemy check — a player can re-create the in-cover trap by
  hand.** `src/sim/sim_world.gd:2283-2309`, the supply-wheel nest plant: `sbx/sby` come straight
  off `p["x"/"y"] + CLAYMORE_PLANT_OFFSET * aim`, and the four `sandbags.append(...)` calls run
  **with no test against `enemies`**. A sandbag is `SANDBAG_HALF_W` = **18px** half-width —
  **WIDER than a kind-0 rock's 16** — against a ghillie's **10px** `BULLET_HIT_RADIUS` (`:224`,
  no `KIND_HIT_RADIUS` entry), which is exactly the arithmetic that makes the rock case a **13px
  trap window**. Verified by reading the plant path (identical on HEAD, untouched by `4d704cc`).
  **NOT measured for real-run reachability** — it needs the player to plant on a surfaced
  ghillie.
- **In ENDLESS `_step_camera` is never called, so `camera_top` is pinned for the whole run and
  NOTHING is ever culled by the `camera_top + 420` sweep.** Rooted units born at row **287**
  therefore persist at row 287 for the entire run. Fine today (287 < the 360 px drawn band), but
  it means `ROOTED_SPAWN_Y_SPAN` is load-bearing in a way the campaign path is not: **raise it
  past ~344 and endless gains permanent un-killable-because-off-screen turrets with no cull to
  save it.** Worth a one-line note or a static assert if the span is ever tuned. *(Reasoned from
  the step order plus the measured span; the ~344 threshold is arithmetic, not driven.)*

### Carried from the 2026-07-31 snapshot — not re-verified this run, measured unless noted

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

### New this run (2026-08-21)

- **The one card that teaches MG-nest counterplay promises a flank the nest has no facing to be
  flanked from.** WHERE: `src/main.gd:386` (`"mg_nest": "MG NEST — BREAK ITS LINE OR FLANK"`, in
  `_KIND_TEACH`, which `src/main.gd:9630-9636` calls out as "the ONLY place this game states
  counterplay"), against `src/sim/sim_world.gd:4510-4549` (`_step_mg_nest`). `_step_mg_nest` has
  **no facing field, no arc test and no range test**. Its arm condition is literally `if
  e["fire_cd"] == 0 and dlen > F_ONE and target["alive"]` (`:4543`) — **any distance, any
  bearing**. Worse for the promised verb, `:4515-4523` re-acquires `_nearest_alive_player` at the
  top of **EVERY round of the 3-round burst** and re-derives a fresh led-aim vector, so there is
  no stale bearing to get behind either. *(Report text truncated at source.)*
- **The HUD plays the "nest is cracking, keep shooting" ping and hint on a nest that provably
  takes zero damage.** WHERE: `src/main.gd:2513` (the `armor_block` event handler), `:2521-2530`
  (the `nest_hit` proximity test), `:2538` (`_hint("nest_crack", "THE NEST CRACKS UNDER FIRE —
  KEEP SHOOTING, OR GRENADE IT")`). The string is shipped and localized —
  `locale/strings.es.po:144`. The view decides a round "cracked the nest" by testing whether the
  `armor_block` event's **POSITION** is within **14px** of a live `mg_nest` — **not** by
  observing that the nest's hp changed. But `sim_world.gd:2966-2981` emits `armor_block` for a
  bullet eaten by a **ROCK** too, at the bullet's position. So when a nest is trapped inside a
  rock, every round that the rock eats fires the "it's cracking" ping.
- **The Technical's card teaches a dodge window that does not exist — the charge line is not
  chosen until the tick the truck launches down it.** WHERE: `src/sim/sim_world.gd:3880-3887`
  (`_step_technical`). The rev is `e["windup"] = TECHNICAL_REV_TICKS` (**24**) at `:3910`, but
  `e["aim_lx"] / e["aim_ly"]` are written **inside `if e["windup"] == 0`**, i.e. on the final tick
  of the rev, simultaneously with `e["lunge_ticks"] = TECHNICAL_CHARGE_TICKS`. The Field Manual
  card is `src/view/menu.gd:5522`: "TECHNICAL — revs, then charges a LOCKED line. Step off it."
  The constant's own comment at `:83` justifies 24 ticks as "the 24t reaction floor
  (REAR_WARN/VENT_WARN precedent)". MEASURED over **4 seeds × campaign + endless**
  (`.aaa/c4/tech.gd`): **117 revs, 113 resulting charges**. Distance from the player at the
  instant the line is actually locked: *(report text truncated at source)*.
- **The HOSTILES readout names the frogman's bullet immunity and stays silent about the
  ghillie's — the one that actually gates the wave.** WHERE: `src/view/hud.gd:1435-1436` sets
  `immune_lurker` **only** for `e["kind"] == "frogman" and e.get("submerged", false)`, which
  posts a "GRENADES ONLY" chip beside the HOSTILES counter (`hud.gd:1457-1470`). The sim gives
  the submerged ghillie the **identical** immunity: `src/sim/sim_world.gd:3023-3024` (bullets
  skip any submerged enemy) and `:3204` (blast **explicitly** skips a submerged ghillie — so it
  is **MORE** immune than the frogman, which grenades still kill). The player sees HOSTILES 1,
  fires at the shimmer, and every round passes through. For the frogman the HUD says why. For the
  ghillie it says nothing.
- **The Field Manual's one economic rate — "Spend it — 6× score" — sits directly under the
  paragraph that defines "spend" as revive-or-buy, and the revive half pays nothing.** WHERE:
  `src/view/menu.gd:5415-5417` ("Spend it to REVIVE yourself or a partner, or BUY supplies…")
  immediately followed by `:5424-5427` ("Spend it — 6× score. What's left when you fall salvages
  at only 3×. WIN, and what's left banks at 10× — plus a 5,000 bonus.") ·
  `src/sim/sim_world.gd:2548` (`score += cost * SPEND_SCORE_MULT` — **the ONLY place a chest
  debit credits score**, inside `_try_buy`) · `:1929` (the priced-crate twin, deliberately kept at
  parity) · `:2028-2090` (`_try_revive`: `war_chest -= cost` and **no score line anywhere in the
  function**). The page introduces two ways to spend the chest in one sentence, then attaches a
  single headline rate to "spend it" in the next.
- **Boss phase labels bypass `TranslationServer` and `Art.fs()`** — banked in the diff's own
  comments and **re-verified still true on `9bb1cdb`**. `src/main.gd:10628` / `:10778` (now
  `:11026` / `:11193`) draw the English literal directly rather than through
  `TranslationServer.translate()`, so the localization suite cannot see the two highest-stakes
  strings on screen and a longer translation would widen the plate past everything the new chrome
  matrix measures. Separately neither goes through `Art.fs()`, so the accessibility TEXT SIZE
  setting does not scale them — confirmed `Art.fs(10)` returns **20** at `text_scale 2.0` while
  `Art.tw(label, 10)` is **unchanged**. Correctly out of scope for that cycle; neither is fixed.
  **Fix direction is owner decision #17.**

### Carried from the 2026-07-31 snapshot — not re-verified this run

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

### New this run (2026-08-21)

**Regressions introduced by this window's own commits — fix these first.**

- **REGRESSION `9bb1cdb` — Ground band stack lost 32px of bottom overscan; a 1-4px grey strip
  can show at the frame's bottom edge under max shake.** Measured, not predicted.
  `ground_base_bands` (`src/main.gd:1139`) emits `int(ceil(360.0 / p)) + 1` = **5 bands x 96px =
  480px** of vertical coverage; HEAD painted **8 rows x 64px = 512px**. `_bg_root` is a child of
  `main` (`main.gd:965`) and `main.position` carries shake/kick/roll (`main.gd:6224`), so the
  ground rides the judder. Measured by rendering shot 0 in both trees (real GL, `screenshots.gd`,
  `gl_compatibility`) at forced camera offsets and finding the last warm-ground row: **dy=-120
  gives HEAD 359 vs working 335; dy=-200 gives 287 vs 255.** Reachability: band bottom =
  `floor(-fposmod(cam_y,96)) + 480`, spanning **384..480**, so the worst 1-in-96 camera phase puts
  it at 384+offset.
- **REGRESSION `9bb1cdb` — The off-subject label gate is wired into 3 of 15 call sites; 12
  offset-anchor callers can suppress a label whose subject IS visible.** (HEAD had no gate, so
  these always drew.) `main.gd:10827-10831` states the contract — offset callers pass `subject` —
  but only **9642** (capsule name), **9648** (MAXED) and the **9655** crate-price claim do. These
  pass an anchor **8-26px above** their subject with **no `subject`**, so
  `WORLD_LABEL_FRAME.has_point(pos)` suppresses on a VISIBLE subject in the top 8-26px:
  **9158 (-8), 9209 (-8), 9746 LOW FUEL (-26), 10219 RESCUE (-18), 10482 SILENCE THE SPOTTER
  (-20), 11531 REVIVE %d (-16), 11548 revive prompt (-16), 11691 AIM AWAY (-14), 11834 and 11850
  GET UP (-26)**. (9142 FORD OPEN is +10, below its subject, safe; 10215 ESCAPING! hand-clamps
  already; 12823 `CALLOUT_OVERFLOW` anchors at `y=40`/`band_bo…` *(truncated at source)*.)
- **REGRESSION-adjacent `9bb1cdb` — `ESCAPING!` is the one world label whose off-frame gate reads
  the TEXT's left edge, not its subject — and the ratchet exempts exactly that site.**
  `src/main.gd:10220` `_world_label_centered("ESCAPING!", epos.x, maxf(epos.y - 18.0,
  float(Art.fs(8)) + 2.0), pi_col)` is the **only** producer that passes no `subject`. Its gate
  point therefore becomes `Vector2(epos.x - Art.tw("ESCAPING!")/2, …)`, i.e. the **left edge of
  the plate**, so the red escape warning is suppressed whenever `epos.x < tw/2` — **29.5px at
  100% text size, 59px at 200%**. At HEAD it always drew. The ratchet does not cover it:
  `tests/test_main.gd`'s `_wl_anchor_dy` returns `INF` for any arg containing `maxf(`/`clampf(`,
  and the sweep `continue`s on INF. That exemption's stated justification ("a caller that clamps
  its own baseline into the frame is safe by construction") **is a Y-axis argument applied to an
  X-axis failure.**
- **A visible priced crate in the top ~21px of the frame now shows no price.** `src/main.gd:9566`
  gates on the label's want-rect (`Rect2(ppos.x-15, ppos.y-34, w, 13)`), so for `ppos.y <= 21` the
  rect is entirely above y=0 and the price is skipped **even though the crate itself is on
  screen**. Same shape at `main.gd:10733` for `_world_label`: the capsule name is suppressed for
  `ppos.y <= ~11`. Left of **x=262** that band is behind the HUD plate, but **the right half is
  bare playfield**. This is what the plan asked for verbatim, and it is strictly better than the
  old behaviour (which printed the price on the HUD), but **the gate should test the SUBJECT's
  position, not the plate's.**

**Ground / desert repetition — what actually survived `9bb1cdb`.**

- **The ground base still repeats verbatim — the peak MOVED 64px → 96px, it did not vanish.**
  Rendered on real GL (`gl_compatibility`, M4 Max) with `tools/ground_lag.py`, own before
  (`src/main.gd` stashed to HEAD) and after captures. **lag-96 excess over the neighbouring-lag
  floor: 01-jungle-firefight x +0.128 / y +0.117 (HEAD -0.002 / -0.010); 02-tank-assault x +0.136
  / y +0.138 (HEAD -0.007 / -0.001).** The old lag-64 peak was **+0.148/+0.144**, so **amplitude
  is essentially unchanged**. `src/main.gd:7191-7208` and `ground_lag.py`'s docstring both state
  this; nobody is lying about it, but the goal named ground-tile repetition and **6.7 verbatim
  repeats across the frame is still repetition**. Needs a second source card (hash-selected per
  world BAND, which is scroll-stable).
- **The earlier dressing-only pass moved the verbatim 64px repeat by −5%, not −43%.** Rendered
  before/after with `tools/screenshots.gd` under `--rendering-method gl_compatibility`.
  Ground-masked (`|lum - row median| < 10`, eroded 8px) and high-passed (subtract a 32px box blur)
  horizontal autocorrelation over rows 96..320: **lag-64 0.648→0.617 (01-jungle-firefight),
  0.733→0.696 (02-tank-assault), 0.672→0.637 (04-bridge-gunship); lag-128 0.598→0.570,
  0.702→0.656, 0.642→0.600.** Off-lags (48/56/60/68/72) sit at **−0.05..0.005** in both, so the
  lag-64 peak is unambiguous and **still 0.62–0.70** after the fix. **Median reduction 5.0%.** The
  plan's target was "below ~0.6 at the desert stop" from a modelled **0.436→0.247 (−43%)** — the
  model over-promised.
- **lag-192 y residual survives on the two desert shots** (the 64px dressing × 96px base lcm).
  `tools/ground_lag.py --lag 192`: **01-jungle-firefight y +0.058 (x -0.005), 02-tank-assault y
  +0.055 (x -0.013)**. HEAD was **01 y +0.248 / x +0.136** and **02 y +0.253 / x +0.132**, so this
  is **~4.3x better on the axis that still shows** and gone on x — but not gone. `ground_lag.py`'s
  header states this openly and attributes it to the two dressing lattices rather than the base,
  which matches: the base is flat at both 64 and 96. **Nothing gates it.** See owner decision #34.

**Boss / fly-in presentation.**

- **`_boss_flash` never reaches the fly-in hull — the body does not react to 32 HP of damage.**
  `src/main.gd:10535` vs `:2639` and `:10606`. `boss_hit` sets `_boss_flash = minf(1.0,
  _boss_flash + 0.35)` with the comment "the big body reacts, not just a spark", but the fly-in
  draw is a bare `_spr(body_tex, apos, PI, asc, Color(0.92, 0.94, 1.05, 0.35 + eta_f * 0.65))`
  and the arrived path's `hull_mod.lerp(Color(2.2, 2.2, 2.2), _boss_flash)` is at `:10606`, past
  the branch's `return` at `:10544`. MEASURED: **on seed 7 the shipped bot removes 32 of the
  boss's 40 HP during the 420-tick approach and the hull never flashes once.** Sparks
  (`fx_impactdark`), the hitmarker, `ping_shell` and the newly-drawn HP bar all do fire, so the
  reported "zero feedback" tell is genuinely gone — **this is the last missing beat.**
- **Hull scorch/smoke damage cues never appear during the approach.** `_boss_wounds(bpos, 1.0 -
  bfrac, 34.0)` is called **only** from the arrived path (`src/main.gd:10641`), after the fly-in
  branch's `return` at `:10555`. MEASURED on a driven run (`demo_input`, god_mode, seed 7): the
  bot takes the miniboss from **40 to 8 HP** during the approach — an **80% wound** — and the hull
  shows **zero scars, zero smoke, zero sputter**, because `BOSS_WOUND`'s `scar_start` threshold is
  only consulted in the arrived branch. **Only the bar drains.** Not a lie, but the window lets a
  boss be shot to near-death with no hull-read at all.
- **The whole approach renders behind the opaque top HUD panel** *(pre-existing framing, NOT a
  regression — verified identical on HEAD by reading the diff hunks; `BOSS_Y_OFFSET`, the
  `camera_top + 90` gate_y offset and the 150/55 ramp magnitudes are byte-identical, just renamed
  to `BOSS_FLYIN_DX/DY`)*. MEASURED from captures and the ramp: the hull's screen y runs from
  **-5 (phase_t -420) to 50 (arrival)**, while the HUD panel's bottom edge sits at about **y 57**.
  Combined with scale **0.5 → 1.3** and alpha **0.35 → 1.0**, the hull is dim and small AND
  occluded for the first several seconds — **at phase_t -420 I could not locate it in the 640x360
  frame at all**; it first becomes findable around **phase_t -180** as a rotor cross showing
  through the panel at **(384, 26)**. Caps how much of the fly-in fix a player can actually see.
- **The boss HP bar's max is learned from the first frame the view sees, so a boss first observed
  at partial HP shows a full bar** *(PRE-EXISTING; the line is carried over unchanged by the
  `_boss_bar` extraction)*. `main.gd`: `_boss_hpmax[bkey] = maxf(_boss_hpmax.get(bkey, 1.0),
  float(boss['hp']))`. Observed directly: a capture harness posed the miniboss at **hp 31/40** and
  the bar rendered as a **full bar**, because 31 became the learned max on the first drawn frame.
  Benign today (the first drawn frame is now the spawn tick at full HP); a latent trap for any
  future path that reveals a boss mid-fight (save/resume, spectator join, pre-damaged boss). The
  honest fix is to read `BOSS_HP` / the sim's own max.
- **Wreck hulk from a mid-approach kill is hard-coded to x = 320** *(pre-existing pattern, newly
  reachable; re-verified present on `9bb1cdb` at `src/main.gd:10511`)*. `_hulks.append({"x": 320 *
  Fixed.ONE, …})` with a rotating y. Before `016b4cd` the miniboss could only die at
  `x == SCREEN_CX == 320`, so the constant was **accidentally correct**. It can now die anywhere
  along the ramp up to screen **x 470** (measured: seeds 11 / 3 / 23 kill it at phase_t **-170 /
  -227 / -33**). Cosmetic only — the hulks are a stylised scar pattern, not a crash-site record —
  but **the constant is now a coincidence rather than a fact**.

**Rooted-unit arrival.**

- **`mg_nest` sandbag base draws at full opacity on its birth frame — 41% of the emplacement
  still pops.** `src/main.gd:10071`: `_spr("sandbag_beige", epos, 0.0, 0.5, Color(0.82 -
  n_dmg*0.13, 0.8 - n_dmg*0.15, 0.62 - n_dmg*0.12))` — **implicit alpha 1.0, never multiplied by
  `n_arr`**. Only `mg_stand` (`:10081`) and the 3 armour pips (`:10084-10087`) ramp. Measured via
  opaque-alpha bbox × art SCALE × call-site `spr_scale`: `sandbag.png` **80x40 opaque → 33.2x16.6
  px on screen, 325 px²**; `mg_stand.png` **80x118 opaque → 24.0x35.4 px, 477 px²**. So
  **325/802 = 41% of opaque area, and the widest element of the silhouette, appears from nothing
  at 100% opacity on frame 1.** Verified by capture: a single nest posed at screen (320,160)
  rendered at age -1 (solid) and age 0 — **the sandbag ring is unchanged between the two**.
- **`_rooted_arrive` is registered for the broadcast mast but nothing ever reads it.**
  `src/main.gd:3300` registers `_rooted_arrive["x,y"]` for every `rooted_spawn` event including
  `kind=="broadcast"`, but the broadcast draw branch (`:10047-10062`: `radio_tower` sprite, the
  two 48px base arcs, the `BROADCAST_HP` pips) **never calls `rooted_arrival_alpha`**. Verified by
  capture: the masts are **pixel-identical at ramp ages 0/6/12 and at no age**. The shipped test
  asserts "'broadcast' arrival registers its dig-in ramp under the unit's stable x,y key" and
  therefore **passes on write-only state**. Either stop registering the mast's key or make the
  branch read it. *(Design half is owner decision #27.)*
- **`_rooted_arrive` is not cleared on restart.** The dict is populated in `_consume_events` and
  aged in `_update_feel`, but **no restart/mode-change path clears it alongside `_fx.clear()`**.
  Entries evict themselves within `ROOTED_ARRIVE_FRAMES` (**24 frames, ~0.4 s**), so practical
  exposure is one stale ramp key on a run restarted mid-fade at a colliding fixed-point x,y.
  Small, but **unbounded by luck rather than by construction**.

**Field Manual layout.**

- **The 200% Field Manual now leaves a big void on leaf 1 — entry-granular packing never splits
  an entry that fits a leaf, even at a sentence boundary.** NEW, introduced by `7c16776`, visible
  in the release capture set. Re-rendered both sides through `tools/screenshots.gd` shot 10 (200%
  / CONTROLS): HEAD's leaf 1/4 is full (heading + 2 bullets, last line "gun fires on its own —");
  the fixed leaf 1/4 holds a 2-line heading + the single bullet "MOVE with W/A/S/D." and then
  **~150 px of empty black — roughly 42% fill of the 166 px capacity.** Measured fill ratios at
  200% over `_howto_large_pages`: **WAR CHEST 84/33/90/48/90/52% across SIX leaves (HEAD produced
  five), SPECIALS 80/48/63/97/97% across FIVE (HEAD produced four).** So **2 of the 20 (tab ×
  scale) combos gained a leaf, and four leaves sit under 50% full.** *(Density trade is owner
  decision #26.)*

**Visual-lens entries — reasoned from screenshots, not measured.**

- **Menu Header Overlapping Tab Bar Border.** Ordnance Rig / Controls Rebind screen: the section
  header text "CONTROLS" is positioned too high on the panel, **directly intersecting and
  double-exposing over the bottom border line of the tab navigation bar**. Text colliding into
  structural UI borders shows rigid absolute positioning that breaks visual hierarchy. AAA
  version: flexible layout containers with defined margins so headers and tab bars never overlap
  regardless of resolution.
- **Overlapping On-Screen Text Banners.** Upper-center screen space during active combat
  objectives (Image 10): the orange banner "GOD MODE — DEBUG ONLY — RUN CANNOT END" renders
  **directly over** the objective text "DESTROY THE GUNSHIP TO ADVANCE", creating a messy
  collision of overlapping pixel fonts. Static screen Y-coordinates for event text without a
  layout queue or stack manager cause notification prompts to collide whenever multiple
  conditions trigger at once. *(Note for the fixer: `band_rows()` is the existing arbiter — the
  god-mode banner is presumably drawn outside it. Enumerate its call sites first.)*
- **Inconsistent Player Health HUD Display.** Top-left player HUD strip, comparing frames 1-3 vs
  frames 4-5: the P1 health readout **constantly changes style between screens**. Frames 1 through
  3 display a clean, green segmented bar next to the player label, while frames **4, 5, 18 and 29**
  abruptly replace the bar with a cryptic row of ASCII text symbols (**"P1 E F"**). Switching core
  HUD elements back and forth between graphical bars and raw debug character strings breaks
  presentation standards and confuses vital player feedback.
- **Sparse and Unfinished How To Play Screen Layout.** Field Manual / How To Play modal, Controls
  tab (frame 19): the body card contains **only** a single header line "MOVE AND AIM FIRST — THE
  REST IS EXTRA:" and one line of text "MOVE with W/A/S/D.", leaving **over 80% of the screen as
  completely empty dark space**. Vast empty cards in help menus look like placeholder content
  caught mid-development. *(Same root as the 42%-fill measurement above — the two entries are the
  visual and the measured halves of one defect.)*
- **Unmasked Overlay UI Clipping.** End-of-run Victory report screen (Image 23): targeting reticle
  icons and UI crosshairs on the bottom-left render **directly over and under the border of the
  modal Victory card popup**, clipping through the frame instead of being hidden or properly
  layered behind a full-screen menu mask. Modal pause screens and post-game report cards should
  cleanly freeze and isolate world-space UI. *(Duplicate of the same-titled 2026-07-31 entry below
  — kept because it was re-observed on a later build.)*

### Carried from the 2026-07-31 snapshot — not re-verified this run

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

### New this run (2026-08-21)

**Tests that measure the wrong thing, or cannot fail.**

- **The R2 fly-in ratchet cannot see a sprite/hitbox divorce — it measures a test-local copy of
  the ramp, not the view.** `tests/test_view_honesty.gd:2960-2961` hard-codes `FLYIN_VIEW_DX :=
  150.0` / `FLYIN_VIEW_DY := -55.0` and `_flyin_drawn_px` (`:2978-2984`) computes the "drawn"
  point from **those**, never from `main.gd`. The source half only greps for `boss_flyin_offset`
  plus absence of the 150.0/55.0/420 literals. MEASURED: changing `src/main.gd:10532-10533` to
  `int(foff[0]) * 2` / `int(foff[1]) * 2` — which **re-creates a 159.8 px divorce at phase_t
  -420, the exact defect** — leaves `SUITE=view_honesty` at **PASS, 86 methods, 1584 assertions,
  0 failures, RC=0**. The plan's R2 promised a measured "<= 20 px at every sample"; the test as
  written **structurally cannot produce that number**.
- **…and the only thing that DOES catch the divorce is a whitespace-exact source pin.** Measured
  against the same mutation: exactly **ONE** assertion went red, and it was the character-exact
  substring pin on the `var apos := _to_screen(...)` expression. The "worst drawn-hull vs hit-disc
  separation" assertion stayed green. So the ratchet **is** fail-closed, but its protection rests
  entirely on a two-line string match that **a harmless reindent will break** (red on a correct
  tree). Two ways to harden it: derive the drawn point from `main.gd` itself, or capture the real
  draw call.
- **A test docstring ships a measurement its own seed refutes.**
  `tests/test_view_honesty.gd`, `test_flyin_rewards_tracking_not_the_arrival_point` docstring: "in
  the arena the sim actually builds, it lands 0 during the whole approach because cover eats the
  lane (`armor_block` from tick 7)". **REFUTED on the seed the file's own `_flyin_boss_sim` helper
  uses.** Driving `main.demo_input` on `SimWorld.new(7, 1, "endless")` from tick 0, the miniboss
  reaches `phase_t == 0` with **hp 8/40 — 32 damage landed during the approach** — and on **seeds
  11 and 99 it is destroyed mid-approach (phase_t -95 and -16)**. The assertions in the method are
  correct and load-bearing; **only the prose is false**, and it will mislead the next reader about
  the balance the fix creates.
- **`tests/test_event_coverage.gd` does NOT actually cover `rooted_spawn` — the plan's "free
  ratchet E" is not free.** The plan claimed adding a sim event without a `_consume_events` arm
  would go red automatically via `tests/test_event_coverage.gd:37`. MEASURED: with all three
  `events.append({"t": "rooted_spawn"…})` lines commented out (mutation B), `SUITE=event_coverage`
  stayed **GREEN (PASS — 1 test method, 17 assertions)**. That gate only sees event types the
  determinism torture actually emits, and **the torture produces zero rooted births**. The diff's
  own comment states this honestly, and `test_archetypes.gd::test_every_rooted_kind_announces_its_arrival`
  covers it instead — so nothing is unguarded. **Banked so nobody later leans on `event_coverage`
  for a type the torture never fields.**
- **Entry-granular pagination costs leaves and leaves sparse pages — no ratchet pins the
  density.** Measured with the real `GameMenu` (`Art.text_scale` swept 125/150/175/200), fill =
  summed row height / capacity per leaf. Regressions: **125% WAR CHEST 2 leaves (93%/93%) → 3
  leaves (73%/99%/14%); 200% WAR CHEST 5 (100/94/94/94/19) → 6 (85/34/90/49/90/52); 200% SPECIALS
  4 (95/98/98/98) → 5 (80/49/64/98/98).** Several others rebalance for the better (**175% MODES
  90/90/17 → 77/90/30; 125% ENEMIES 96/14 → 75/34**), and **200% CONTROLS holds at 4 leaves**. A
  defensible trade for readability, but **nothing in the suite pins leaf-count growth or a minimum
  fill**, so a future copy edit can quietly double the manual's page count.

**Test/tool comments that document numbers which do not reproduce.**

- **`tests/test_menu_layout.gd` c4-19 header: 26 offending leaves across 16 combos, not "20 of
  20".** The header above `test_manual_never_ends_a_leaf_mid_sentence` says "Measured at HEAD: 20
  of the 20 (tab × enlarged scale) combos, 20 offending leaves, across all 5 tabs." Reverting
  `_howto_large_pages` to the line-greedy loop (leaving `_ends_sentence` and the provenance keys
  in place, i.e. exactly HEAD's pager) and running `SUITE=menu_layout` reports **26 offenders
  spanning 16 combos** — 125% WAR CHEST/MODES/ENEMIES (3), 150% WAR CHEST(×2)/ENEMIES/SPECIALS (3
  combos), 175% all five tabs (2 leaves each), 200% all five tabs. **CONTROLS and SPECIALS are
  clean at 125%**, so "all 5 tabs" at every rung is not what HEAD does.
- **`tests/test_assets.gd:2632-2633` documents HEAD period-64 fundamentals that were never true of
  this code.** Header states "desert (march 0.0): fundamental **0.795** (x) / **0.798** (y)" and
  "foundry (march 1.0): **0.819** / **0.792**". Re-measured by mutating `src/main.gd`'s generator
  back to the `% 33` jitter with the 96px pass deleted and running the shipped test: **0.617/0.620
  (desert), 0.623/0.613 (foundry)** — printed by the test's own failure messages. `src/main.gd`'s
  inline comment on the same edit already carries the correct **0.617/0.620**, so **the two files
  disagree with each other**. The card-count consts (`_HEAD_DESERT_CARDS 3224`,
  `_HEAD_FOUNDRY_CARDS 7548`) **ARE** correct — only the fundamentals are wrong.
- **`tests/test_main.gd:2778` documents HEAD arbiter violation counts that do not reproduce.**
  Header states "MEASURED ON HEAD (7c16776): **1,260** violations at 100%, **1,534** at 200%".
  Restoring the old `return Rect2(x, clampf(rect.position.y, min_y, maxf(min_y, 360.0 - h)), w,
  h)` exhaustion path and running the shipped test gives **1,506 @100% and 1,742 @200%**.
  `src/main.gd`'s comment on the same fix already says **1,506/1,742**. The 1,260/1,534 figures
  came from the plan's scratchpad prototype, **not from this tree**.
- **`tests/test_assets.gd:2637-2639` banks "this environment has no GL context" — FALSE.** The
  comment states the rendered-composite autocorrelation "CANNOT be ratcheted here" because "this
  environment has no GL context". Running `SHOT_DIR=… /Applications/Godot.app/Contents/MacOS/Godot
  --path . --rendering-method gl_compatibility -s res://tools/screenshots.gd` in this exact
  working directory printed **"OpenGL API 4.1 Metal - 91.7 - Compatibility - Using Device: Apple -
  Apple M4 Max"** and saved **all 14 shots** (colors **949–5696**, stddev **22.5–54.6**, "ALL
  SHOTS DONE — 14 live, 14 unique"). `tools/perf_probe.gd` also rendered **121 frames** under
  `forward_plus`. The correct bank is **"CI's Linux runner would need xvfb"**, not "no GL here".
  As written it instructs the next cycle **not to look at the screen**.
- **`tools/ground_lag.py`'s documented BEFORE numbers are ~0.01 low against a true HEAD render.**
  Docstring: **01 +0.138/+0.128, 02 +0.147/+0.138, 04 +0.085/+0.094**. Re-measured with
  `src/main.gd` stashed back to `7c16776` and re-rendered: **01 +0.148/+0.144, 02 +0.155/+0.151,
  04 +0.094/+0.098**. The AFTER column is exact to the thousandth and 05-foundry is right, which
  suggests the BEFORE column was taken **with the dressing fix already applied** rather than at
  clean HEAD. The table is presented as the before/after of the pitch change alone.
- **`tools/ground_lag.py`'s docstring mislabels the lag-192 residual axes.** It reads "lag-192 …
  still carries **+0.058 x / +0.055 y** on 01". Measured: **01 is x=-0.004, y=+0.058** and **02 is
  x=-0.013, y=+0.055** — both quoted figures are **y-values from two DIFFERENT shots**, presented
  as an x/y pair for a single shot. The immediately preceding "down from HEAD's +0.136 / +0.247"
  **IS** a genuine x/y pair for 01 (measured **+0.136/+0.248**), so the sentence switches
  convention mid-clause. Every other figure in that docstring reproduced exactly on independent
  renders, which is what makes this one worth fixing rather than ignoring.
- **`tools/ground_lag.py`'s control lags are frozen at (52,56,72,76) regardless of `--lag`.**
  `CTRL_LAGS` is a module constant, so `--lag 96` and `--lag 192` measure their excess against a
  floor sampled near lag 64. Residual autocorrelation decays with lag, so the floor is slightly
  **HIGH** for lags above 64 and **the reported excess is understated** — conservative for every
  claim the diff makes (it makes the after-numbers look worse, not better), but the instrument
  does not track its own argument and a future reader will assume it does. Either derive the
  control lags from `lag` (e.g. `lag ± 8, 12`) or say so in the docstring.

**Uncalled, unwired or broken instruments.**

- **`tools/ground_lag.py` joins `tools/ground_profile.py` as a SECOND GL-only pixel probe with
  zero callers and no CI job.** Re-verified on `9bb1cdb`: `grep -rn ground_lag . --exclude-dir=.git`
  matches only the file itself and two test comments; `ground_profile` has **zero** references
  anywhere. `.github/workflows/ci.yml` runs only `--import`, `lint_sim`, `lint_assets`,
  `i18n_check`, `smoke`, `run_tests` and the export/soak jobs — **`grep -n 'gl_compatibility\|xvfb'
  .github/workflows/ci.yml` returns nothing.** Both are honest instruments whose numbers reproduced,
  but the repo now has **two uncalled rendered-pixel measuring tapes and no xvfb job to run
  either.** *(Owner decision #32.)*
- ~~`tools/probe_mg_lane.gd` is still committed and still broken~~ **RESOLVED**: deleted (with its
  `.gd.uid` sidecar). `tests/test_view_honesty.gd` already carries the correct, position-based
  attribution this probe was trying (and failing) to do via `enemy_bullets[-1]`, so it was a
  redundant instrument whose numbers a green test refuted — nothing referenced it outside its own
  history comment.
- **Three GL-only capture tools still print leak diagnostics and no gate sees them**
  *(PRE-EXISTING; CLAUDE.md's updated `run_tests.sh` bullet names it as a known gap rather than
  claiming it fixed — this is a bank, not a lie)*. Measured: `godot --path . --rendering-method
  gl_compatibility -s res://tools/screenshots.gd` prints **`ERROR: Texture with GL ID of 321:
  leaked 5460 bytes.`** and **`ERROR: 1 RID allocations of type 'N5GLES37TextureE' were leaked at
  exit.`**; the implementer's identical HEAD and post-fix runs both additionally show **`WARNING:
  2 ObjectDB instances were leaked at exit`** (one reviewer's run did not — it is **racy**).
  `tools/probe_concussion_hud.gd` prints the same two GL lines (verified alongside `PROBE OK`).
  `tools/biome_capture.gd` is unmeasured. Corroborated structurally: `grep -ln 'main.tscn'
  tools/*.gd` → biome_capture, e2e_playthrough, perf_probe, probe_concussion_hud, screenshots,
  smoke, quiesce; `grep -ln Quiesce tools/*.gd` → e2e_playthrough, perf_probe, smoke, quiesce.
  `screenshots.gd` / `biome_capture.gd` / `probe_concussion_hud.gd` contain **no `free()` or
  `queue_free()` at all** and quit holding their main. Neither is in CI (both need a GL context)
  and neither can be run through `tools/run_tests.sh` headless, **so no gate sees them.**
- **`tools/run_tests.sh` HANGS FOREVER (>10 min, no output, low CPU) on an incompatible
  method-override return type instead of erroring.** Hit while gate-proving a ratchet the
  prescribed way (stash the diff and run it): with `src/view/menu.gd` stashed to HEAD,
  `tests/test_menu_layout.gd`'s `_CtrlLayoutMenu._verb_line(segs, base_y, col) -> float` overrides
  a base `_verb_line(...) -> void`, and `SUITE=menu_layout tools/run_tests.sh` produced **ZERO
  output and had to be killed at the 10-minute timeout**. **NOT a defect of the shipped tree** —
  on the real tree that same suite runs in **1.3s** and PASSes **215 methods / 8,615 assertions**.
  But it is a live footgun: the symptom (one Godot process, no output, indefinite runtime) is
  **indistinguishable at a glance from the cold-import and CPU-contention stalls CLAUDE.md
  documents**. This is a **FOURTH** stall class and belongs in CLAUDE.md's stall triage list.

**Cosmetic / style.**

- **Single blank line between an extracted function and the next.** `src/main.gd:10690` —
  `_boss_bar` ends and `static func _boss_wound_scars` begins after **ONE** blank line; the file's
  convention throughout is **two**. Introduced by the `016b4cd` extraction. No parse or test
  impact.
- **`main.gd:10625` comment still says the boss bars sit "below the corner HUD panel's max height
  (~60px)".** The comment above `_draw_one_gunship`'s bar placement predates `66d146a` and
  describes the geometry the fix corrected. It is now **incidentally** true (`panel_bottom` max
  **60**, `BOSS_BLOCK_TOP` **66**) but **for the wrong reason** — it reasons about the BAR line
  clearing 60, which is exactly the mistake that let the panel bury 7px of the boss name. The next
  pass should rewrite it to reference `BOSS_BLOCK_TOP`. *(Not re-verified against `9bb1cdb` line
  numbers — the surrounding code moved.)*
- **CLAUDE.md's Commands block still advertises the ungated raw suite invocation.** The
  `run_tests.sh` bullet deep in Conventions describes the shutdown-leak gate, but the Commands
  block near the top still lists `godot --headless --path . -s res://tests/run_tests.gd` as **THE**
  "Full test suite" command, with `tools/run_tests.sh` presented only as the parallel-safe variant.
  A reader following the first command gets **the suite with no leak gate at all** — the same
  structural blindness the gate exists to remove, since `_gate_engine_errors` reads `user://logs`
  and the leak lines are emitted after the file logger is torn down. **One sentence in that block
  closes it.**

### Resolved in the `390c12d..9bb1cdb` window — kept with how they were re-verified

- ~~**`e2e_playthrough` leaks 30 ObjectDB / 1 resource at exit (PRE-EXISTING on HEAD) — and the
  new gate hard-fails it.**~~ **RESOLVED — `66d146a`.** (Was: 3 of 4 runs printed `WARNING: 30
  ObjectDB instances were leaked at exit` and `ERROR: 1 resources still in use at exit` AFTER
  `[E2E] === 80 checks, 0 FAIL ===`; verified pre-existing by stashing the whole diff and running
  HEAD 5× — all 5 printed the identical 30/1. `--verbose` named all 31: **16
  AudioStreamPlaybackWAV, 10 AudioStreamWAV, 2 AudioStreamPlaybackPolyphonic, 1 AudioStreamMP3, 1
  AudioStreamPlaybackMP3**, plus `Resource still in use:
  res://assets/vo/cmd/cmd_levelstart_6.mp3`.) The shipped fix is `tools/quiesce.gd`: measured
  **30 → 0, 6-of-6 runs**.
- ~~**`tools/run_tests.sh -s res://tools/smoke.gd` exits 1 on 5 of 6 runs without
  `LEAK_FLOOR=2`.**~~ **RESOLVED — `66d146a`.** (Was: 6 consecutive runs — run1 exit 0, runs 2-6
  exit 1 with `2 ObjectDB instances leaked at exit (floor 0)`; the 2 objects are a genuine engine
  artifact, reproduced 1-per-polyphonic-player in **14 lines of vanilla Godot 4.7.2 with no repo
  code**.) The shipped answer was not a floor but a teardown: `smoke.gd` routes through
  `Quiesce.teardown` and measures **2 → 0, 6-of-6**. Re-verified on `9bb1cdb`: **`LEAK_FLOOR`
  does not exist in `tools/run_tests.sh`** (`grep -n LEAK_FLOOR tools/run_tests.sh` → no match),
  so the escape hatch the finding named never shipped.
- ~~**CLAUDE.md not updated for the new `LEAK_FLOOR` lever.**~~ **RESOLVED — `66d146a`.**
  Re-verified: CLAUDE.md's `run_tests.sh` bullet now documents the shutdown-leak gate, both leak
  causes, the `--verbose` discriminator, `Quiesce.teardown`, and names the three ungated GL tools
  as a known gap. There is no `LEAK_FLOOR` to document.
- ~~**The new leak gate misses Godot's `RID_Owner` leak string and the GL byte-leak string.**~~
  **RESOLVED — `66d146a`.** (Was: all three copies matched only `RIDs of type .* were leaked`,
  missing `ERROR: 1 RID allocations of type 'N5GLES37TextureE' were leaked at exit.` and `ERROR:
  Texture with GL ID of 321: leaked 5460 bytes.`) Re-verified on `9bb1cdb`: `tools/run_tests.sh:86`
  matches `'were leaked|resources still in use at exit|leaked [0-9]+ bytes'`, and the header
  comment at `:81-83` states outright that "Godot words RID leaks two different ways … so the
  pattern matches the shared substrings, not one sentence."
- ~~**Vacuous assertion in the new `test_hud` ratchet — `x == x` cannot fail.**~~ **RESOLVED —
  `66d146a`.** (Was: `test_every_boss_plate_owns_its_reserved_band` asserted
  `Art.tw(label, SIZE) == Art.tw(label, SIZE)` at a single scale, so it passed on any
  implementation — including one where TEXT SIZE **does** reach the labels.) Re-verified by reading
  `tests/test_hud.gd:3513-3523`: it now captures `label_w1` at `text_scale 1.0`, `label_w2` at
  `2.0`, restores the scale **before** asserting, and asserts `eq(label_w2, label_w1)` alongside
  the live `Art.fs(10) == 20` arm.
- ~~**`hud.gd:1706` `# 38.0 in the finale` is now 55.0.**~~ **RESOLVED — `66d146a`.** (Was:
  `bottom_band_lift` measured **55.0** on that tree — `344 + 8 - (COLOSSUS_BLOCK_TOP 305 -
  BOTTOM_RESERVE_GAP 8) = 297 → 55.0` — while annotated `38.0`; it was **48.0** on HEAD, so the
  comment was already wrong by 10.) Re-verified: `grep -n 'in the finale' src/view/hud.gd` → **no
  match**.
- ~~**`main.gd:12390/12393` mirrors `LAST_STAND_Y` as a bare `350.0`.**~~ **RESOLVED —
  `66d146a`.** (Was: `var oy := 40.0 if is_top else minf(350.0, HudIcons.band_bottom(sim))` under
  a comment claiming "350 is LAST_STAND_Y", after `LAST_STAND_Y` moved to **353.0**. Blast radius
  measured as none: the `+N more` overflow label right-flushes near **x=606** while the LAST STAND
  plate is centered at **x 170..470**, so no rect intersection at either 350 or 353.) Re-verified:
  `grep -n 'minf(350.0' src/main.gd` → **no match**.
- ~~**`claim_label_slot`'s own docstring still documents the behaviour the fix removed.**~~
  **RESOLVED — `9bb1cdb`.** (Was: the leading `##` block still claimed "a PERSISTENT label … keeps
  its place, x-clamped, rather than being shoved off-screen" — exactly the return the fix 60 lines
  lower deletes.) Re-verified at `src/main.gd:10684`, which now reads `settle for the row of LEAST
  total overlap. It no longer "keeps its place, …`. **Still open:** `tests/test_main.gd:1969`
  repeats the stale claim inside `test_world_text_saturation_drops_instead_of_overprinting`'s
  docstring — that test still passes and is still non-vacuous (`drops > 0` asserted and green),
  **only its prose is wrong**.
- ~~**Dangling doc reference: `GROUND_BASE_SHUFFLE` does not exist.**~~ **RESOLVED — `9bb1cdb`.**
  (Was: `src/main.gd:1153` said "eight 128px slots, each a different dihedral transform of sand.png
  (see `GROUND_BASE_SHUFFLE`)" while the constant is `GROUND_BASE_SLOT_DIHEDRAL`.) Re-verified:
  `grep -rn GROUND_BASE_SHUFFLE . --exclude-dir=.git` → **no matches anywhere**.
- ~~**Stale doc: strip builder says "4 × 1024x128 blits", it is 64 blits across 8 variants.**~~
  **RESOLVED — `9bb1cdb`.** Re-verified at `src/main.gd:1156`, which now reads "Builds one
  1024x128 base strip: eight 128px slots, each a different dihedral…". The useful number from the
  original finding, kept: **the whole build measures 11.71 ms for 4.00 MB of raw pixels, once per
  process.**
- ~~**Fly-in boss bar names an act the sim refuses to perform.**~~ **RESOLVED — `016b4cd`.** (Was:
  `main.gd:10554` passed a NEGATIVE `phase_t` into `_boss_bar`; `:10668`'s `gphase := 1 if pt <
  SimWorld.BOSS_STRAFE_TICKS else 2` selected `GUNSHIP_PHASE_NAMES[0] == 'STRAFING RUN'` for the
  whole approach. MEASURED by posing `phase_t -420 / -300 / -180 / -60` through the real view
  (`main.tscn`, `gl_compatibility`, 12 settle frames) and reading the plate in all four PNGs: top
  center read **"GUNSHIP — STRAFING RUN" for the full 420 ticks = 7.00 s**, while `_step_one_boss`
  returns before any firing at negative `phase_t`.) Re-verified: `src/main.gd` now defines
  `const GUNSHIP_INBOUND_NAME := "INBOUND"` with a comment naming the exact defect.
- ~~**Mid-approach kill puts the explosion, coin toast and ejecting pilot on the landing pad
  instead of on the wreck.**~~ **RESOLVED — `016b4cd`.** (Was: `_damage_boss`'s death block
  computed `var by: int = boss["gate_y"] - BOSS_Y_OFFSET` and emitted `explosion`, `kill` and
  `pilot_down` at the ARRIVAL point with no `boss_flyin_offset`. MEASURED by direct `_damage_boss`
  probe across the window: **phase_t=-420 hull=(470.0,-365.0) explosion@(320.0,-310.0) d=159.8px,
  pilot d=214.3px; -300 → 114.1px; -158 → 60.1px; 0 → 0.0px**.) Re-verified at
  `src/sim/sim_world.gd:6910-6927`, which now computes `var doff: Array =
  boss_flyin_offset(boss.get("phase_t", 0))` and offsets `bx`/`by` before every emit.

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

- **NEW 2026-08-21 — The debug auto-restore refills ammo AND grenades to cap every 60 ticks, so
  every review pass this project has run has been blind to its most common failure state.**
  WHERE: `src/sim/sim_world.gd:1988-2004` (`_god_restore`: on every `tick_count %
  GOD_RESTORE_TICKS == 0` it clears `wiped`, respawns the down, and then **unconditionally** sets
  `p["mg_ammo"] = MG_AMMO_MAX` and `p["grenade_ammo"] = GRENADE_AMMO_MAX` for every player) ·
  `:257` (`GOD_RESTORE_TICKS := 60`). The flag's own docstring is careful about this — "Ammo is
  topped up on the same heartbeat and NOT continuously: between beats you still run dry and still
  hear the empty-mag click (the pressure stays observable)." Measured, that is not what a 60-tick
  heartbeat does against an **8-tick fire loop**: the gun burns **7.5 rounds** between refills and
  the refill returns the magazine to cap. **Consequence for this backlog: every `god_mode`
  measurement in it — and there are many — was taken in a world where the player never runs out of
  ammo.** Re-read the ammo-economy entries in §2 with that in mind, and prefer `god_mode OFF`
  drives for any economy or attrition claim.
- **NEW 2026-08-21 — A FOURTH headless-stall class exists and is not in CLAUDE.md.** An
  incompatible method-override return type makes `tools/run_tests.sh` hang **>10 min with zero
  output at low CPU**, indistinguishable at a glance from the three documented stalls (CPU
  contention, cold import, aborted `_init`). See §5 for the full measurement. CLAUDE.md's stall
  triage paragraph should grow a fourth bullet, because the wrong remedy (`pkill -f Godot`) is the
  documented answer to a different one.
- **NEW 2026-08-21 — 96 findings banked against ~20 shipped in this window. The ratio is still
  going the wrong way**, and this snapshot is the largest single merge the file has taken. The
  drain-mode proposal below is now three snapshots old and still not built.
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

- **The "in-rock rooted enemies stall endless waves for 30,000 ticks" causal claim is REFUTED —
  LEAVE THE STALL ALONE, the premise was wrong.** The `4d704cc` goal statement said in-rock rooted
  enemies are "what stalls endless waves for 30,000 ticks". MEASURED, **8 seeds × 30,000 ticks,
  endless, god_mode, `main.demo_input`**, longest single-wave duration per seed: **BEFORE (HEAD
  sim) median wave reached 10, WORST wave-duration 26,151 ticks; AFTER (fixed sim) median wave
  reached 10, WORST wave-duration 26,151 ticks.** Per-seed it is noise in both directions (**seed
  5: 3,893 → 19,963 worse; seed 0xC0FFEE: 13,785 → 4,692 better**) — **the distribution does not
  move.** Diagnosed the worst case directly: **seed 1 holds wave 7 open for 26,150 ticks with
  exactly two ghillies at (75,-308) and (142,-308)**, and on the FIXED tree both measure **CLEAR of
  all four cover families**. The in-rock defect was real and worth fixing on its own terms; **the
  stall it was blamed for is the BOT**, and the fix did not touch it. **Blocked on: a better bot,
  or a human playing deep endless.** *(This is the canonical example of the standing warning at the
  top of this file — a real smell, consequence wrong by a whole class.)*
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

### Shipped in the 2026-08-21 window (`390c12d..9bb1cdb`, 60 commits)

Shas below were located by `git log -S<identifier> 390c12d..HEAD` against the symbol each fix had
to touch. Where that returned nothing, the row says **sha not located** rather than guessing — and
where the predicate still reads unchanged on `9bb1cdb`, the row says so, because a title on a
run's shipped list is not evidence that the code moved.

| Finding | Commit |
|---|---|
| Engine shutdown leak ERRORs on every suite run (pre-existing, identical on HEAD) | `66d146a` — baseline was **265 RIDs / 5192 ObjectDB / 8 resources** on `7bed222`; gated at zero in `run_tests.sh` **and twice in `ci.yml`**. Owner decision #18 (3-OS exposure) open |
| Boss HUD overlap with control hints | `66d146a` — folded `BOSS_BLOCK_TOP`/`COLOSSUS_BLOCK_TOP`/`LAST_STAND_TOP` onto `label_plate_rect`; the hand-typed 9px ascent mirror was **2px optimistic and buried the top of the boss name in 3 of 4 configs**. Layout cost is owner decisions #15/#16 |
| Rooted enemies spawn inside rocks, become permanently bulletproof and keep shooting | `4d704cc` — **the "stalls endless waves for 30,000 ticks" half of the title is REFUTED, see §7** |
| Endless miniboss is drawn and shootable for a 7s fly-in while bullets pass through it | `016b4cd` — closes the 2026-07-31 remainder under `a512bee`. Deletable-approach balance is owner decision #23 |
| Every turret, mast and hidden sniper materialises inside the frame; in Endless the same pixel row every wave | `7c16776` — `ROOTED_SPAWN_Y_SPAN` + `rooted_arrival_alpha`. Mast exclusion is owner decision #27; sandbag-base pop is open (§4) |
| Truncated tutorial text in Field Manual | `7c16776` — `_howto_large_pages` entry-granular pager. Density cost is owner decision #26 |
| Truncated body copy in Controls manual | `7c16776` — same pager |
| Repetitive grid-based ground tile seams | `9bb1cdb` — **peak moved 64px → 96px at essentially unchanged amplitude, it did not vanish (§4)**. Chase-further call is owner decision #30 |
| Overlapping floating MAXED world labels | `9bb1cdb` — `WORLD_LABEL_FRAME` off-subject gate; **0 overlaps across 14,400 sampled bot frames vs 46.32%/47.01% at HEAD**. Suppression trade is owner decision #31; 12 unwired call sites are a live regression (§4) |
| CI lint red — two hint strings shipped without catalogue entries | `7bed222` |
| Trench Gun countdown hidden exactly when it matters; "same fan" wrong on Triple | `5c0f574` |
| Claymore sells "IT HURTS BOTH SIDES" but its blast spares players | `b5f7608` |
| Colossus closed core: MG tracers phase through with zero contact feedback | `27d47e9` |
| Deep-endless veteran armor silently kills the empty-clip bash | `3fd729c` — closes the 2026-07-31 remainder under `f6666b8` |
| Grenades and every blast kill the cloaked, bullet-immune ghillie | `d5c7931` |
| The revive's go-to-the-body grammar signposts a run the sim does not require | `34dd43f` ("a rescue finally lands at your side") |
| A tank driver's/gunner's revive key is a fully swallowed input | `6fa0aaa` ("a swallowed key") |
| The supply receipt lies on partial stocks (+30 AMMO / +4 GRENADES at the cap edge) | `6fa0aaa` (`BUY_FLOAT`) |
| Smoke hint says "BLINDS THEIR AIM" while the MG nest keeps firing aimed rounds | `1542b4b` |
| End-of-run modal card overlays leak active HUD elements (K.I.A. card leaking the boss bar) | `1542b4b` |
| NG+ HARD lands on the same board with no marker | `08ccda4` |
| A tank parked on a free supply crate collects nothing and says nothing | `08ccda4` |
| Grenade-family hits on bosses emit no `boss_hit` feedback event | `08ccda4` |
| Airstrike hint gates on the 100¢ base price, not the depth-creeped price | `08ccda4` (`SHOP_AIRSTRIKE_COST`) |
| SUPPLY CALL spends a Commendation on a hidden random table | `1ac09a6` ("first mint teaches spend") |
| Intrusive knockdown screen smear obscuring gameplay | `34a4037` ("concussion freezes") — likely; verify against the capture before striking |
| Closed gates pin the camera while rooted nests pile above the viewport | `7c16776` — likely (same spawn-row work); verify against a gate fight before striking |
| The Spanish commander got cut off mid-brag and CI never noticed | `dc0a4ac` |
| `.todo-worktrees` unignored — 316MB one `clean -fd` from deletion | `a71c367` (chore) |

**On this run's shipped list but NOT corroborated in the code — treat as still open until
someone finds the commit.** For each of these, the symbol the fix would have to touch is
unchanged since `390c12d` (`git log -S… 390c12d..HEAD` returns only the two docs commits):

| Title claimed shipped | Evidence against |
|---|---|
| 2P ready-up is a unanimous party vote with no tally | `ready_hold` unchanged since `390c12d`; **`grep -n 'ready_hold\|READY_HOLD' src/main.gd src/view/hud.gd` on `9bb1cdb` returns NOTHING** — still zero view reads. Entry stays open in §2 |
| Daily Run's one attempt refunded by R / QUIT TO TITLE (both phrasings) | `_daily_done_seed` unchanged in this window; `d45132a`'s arm+demote is visible at `main.gd:1724-1726`, so this is the **already-tabled 2026-07-31 fix re-listed**, not a new one. Remainders stay open |
| A salvaged or expired tank hulk keeps burning and drawing as cover | `HULK_TICKS` unchanged since `390c12d` |
| "WAVE CLEARED — SHOP OPEN" fires while a live Spotter is still shelling | `observer_alive` unchanged since `390c12d` |
| Endless 2P: a broke death respawns FREE after 5s | `rally_is_free` unchanged since `390c12d` |
| `screenshots.gd` victory pose fakes the WAR CHEST row | `_victory_banked_score` unchanged since `390c12d` |
| Toast-string scrape's `_coin_pop` branch is dead code | `_coin_pop` unchanged since `390c12d` |
| The Colossus siege restocks grenades in total silence | sha not located |
| Five teaching hints stamp hardcoded key letters (E/F/Q) | sha not located — `40087f6` ("rebind labels now show TAP vs HOLD for shared E key") is adjacent but is not this |
| Rolling in water prints "NEED COINS" (duplicate `match` arm) | sha not located |
| HUD keybind string clipping in downed state | sha not located |
| The shop bills full price for air it partially delivers (charge half) | sha not located — `6fa0aaa` fixed the **receipt** half only |
| Miniboss fly-in airstrike window remains a partial whiff | still open by the plan's own bank (§2/§7) |

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

- **A title on a run's "shipped" list is not evidence the code moved.** New this snapshot: of the
  ~120 titles handed over as shipped, **13 could not be corroborated** — the symbol each fix would
  have had to touch is unchanged since `390c12d`, and in one case (`ready_hold`) the defect's
  headline claim, "zero view reads", **still greps to nothing on `9bb1cdb`**. Those titles are
  tabled in §8 with the evidence against them and their entries stay OPEN. Locate the sha with
  `git log -S<identifier> <base>..HEAD` before striking anything off.
- **A finding measured against a work-in-progress diff is not a finding against HEAD.** Twelve
  entries this snapshot were filed by lenses reading a branch mid-flight and were fixed before the
  commit landed (vacuous `test_hud` assertion, the leak-gate regex, the `LAST_STAND_Y`/`38.0`
  comment mirrors, `GROUND_BASE_SHUFFLE`, the fly-in "STRAFING RUN" plate, the mid-approach death
  coords…). They are marked RESOLVED **with the command that re-verified them**, not deleted.
- **Independent measurements of the same number are the evidence that the number is real.** Where
  several lenses reported one decision, this file keeps all of their numbers side by side rather
  than picking the tidiest — see owner decisions #15, #23, #30, #31. Where they disagree (the
  miniboss skip rate: 2-of-5, 3-of-7 and 2-of-6 across three lenses), the disagreement is the
  finding.
- **`god_mode` measurements are blind to the ammo economy.** `_god_restore` refills the magazine
  AND grenades to cap every 60 ticks against an 8-tick fire loop (§6), so any attrition or economy
  claim in this file taken under god mode is measuring a world where you never run dry. Prefer
  `god_mode OFF` drives for those.
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
