# COMMANDER IN CHIEF — Game of the Year Plan

> A modern remake of *Ikari Warriors* (SNK, 1986) — twin-stick vertical run-and-gun.
> **v1.3.0 · Godot 4.7.2 · GDScript · 640×360 · MIT (code only).**
>
> This document is a **work order**, not a wish list. Every item names the file it
> lands in, the constant it moves, and the test that proves it. Recon was done by
> 4 parallel read-only agents that read the actual render pipeline; the findings
> below are measured, not remembered.

---

## 0. The state of the thing, honestly

**The game is mechanically excellent and visually unfinished.** That is a rare and
very fixable position.

### What's already world-class (do not touch the design)

| System | Evidence |
|---|---|
| Deterministic sim | Fixed-point 16.16, seeded xoshiro128\*\*, golden-checksum gate, bit-identical x86_64 ↔ arm64 |
| Test rigour | **1,218 methods / 38,625 assertions / 0 failures**, 3-OS CI, engine-error gate, shutdown-leak gate |
| Accessibility | Colorblind palette with shape-doubled channels, WCAG `CALLOUT_INK_FLOOR`, real text scaling, reduce-motion honoured nearly everywhere, 3 full input-device glyph families |
| Feel infrastructure | Hitstop + envelope-hold + input-latch + shader-clock freeze, **already built and proven** |
| UI arbitration | `band_rows()` / `claim_label_slot()` — ratcheted to 13,653-claim sweeps; beat the modern indie bar |
| Content | 6 sectors, 3 bosses, War Chest economy, 4 modes, co-op, Steam-shipped |

### The five things that make it read as "bad" — measured

1. **The ground is unlit.** No `Light2D`, no `CanvasModulate`, no normal maps — verified zero. The base strip modulates to **one flat constant per 96px band** (`GROUND_SHADE=0.522`), and `sand.png` is 128×128 at **std 8.46/255** — a near-uniform grain field that carries no macro structure at all. The only vertical shading in the entire game is 1-in-19 ridge mounds and three *darkening* cloud blobs. **→ flat brown mud.**

2. **The big sprites are the flattest things on screen.** `wreck_halftrack` is the largest litter sprite at **52×63px drawn — 5.9× the player's area** — carrying **3 value steps with 43% of pixels in one colour**, and it is additionally darkened at the call site. Its alpha **IoU is 0.93 vs `wreck`, 0.92 vs `wreck_apc`, 0.83 vs `wreck_light_tank`**: the player cannot tell a halftrack from an APC from a burnt crate. Root cause is one function — `_burnt()` at `gen_entities.py:318`.

3. **The fire loop has no impact.** A normal infantry kill gets **zero hitstop**. The player pulls the trigger 8×/sec for 30 seconds and the world never once acknowledges a round landing. Worse: **`victory` sets trauma 1.0, flash 0.6, punch 0.18 — and no freeze at all**, while a mid-run boss death gets 10 frames. The run's one win-state has the second-shortest freeze in the game. And the `pickup` event has **no visual response whatsoever** — sound only, in a game about a shared coin economy.

4. **The HUD is a wall of English words.** 17+ readouts arbitrate for one 632px row via a priority table, a two-pass fit planner and a `+N` chip. Roughly **half the row-0 pixel budget is redundant with the icon already drawn to its left.** There is **no player vitals readout anywhere** — no health, no vest, no armour — in a one-hit-death game. Nine `ICON_Map_*` sprites ship and are drawn nowhere.

5. **Typography has no scale.** One bitmap face at **12 distinct sizes**, three of which are annotated as *badly quantized stems* worked around in three separate files. Hierarchy is carried entirely by colour.

### Assets: the hard constraint

`~/gameassets` holds **1,596 archives / 775 CraftPix packs / 38 GB**. The recon read the actual licence:

> **§1.1.3 "Distribution of source files is NOT permitted."**
> **§1.1.4 "You can sell and distribute games with our assets."**
> **§3.1 FORBIDDEN: assets may not be used "for the purposes of training, fine-tuning, developing, testing, validating, or improving any AI… system."**

This repo is **public + MIT** and shipped a full history rewrite on 2026-07-27 to purge third-party art. So:

| Source | Verdict | Why |
|---|---|---|
| **CraftPix ×775** | 🚫 **Cannot ship** | §1.1.3 forbids source distribution into a public repo. §3.1 additionally forbids feeding them to an image model — the `regen_entities.py` path is **blocked**, not merely discouraged. This is the single most important licensing finding in the project. |
| **Kenney CC0 ×5** | ✅ Already in use | `assets/cc0/` is live. Crosshair, UI-pack, TD-top-down are **unused and CC0** — free. |
| **Kenney audio (CC0)** | ✅ Unused | sci-fi + impact + railgun, verified CC0 in `SOURCES.md` |
| **ambientCG (CC0)** | ✅ **New — 2,012 PBR materials** | Confirmed live API. The real answer to "download new ones". |
| **OGA 16-toon muzzle** | ⚠️ Unverified | No licence file in the archive. Blocked until proven. |

**Consequence: the 38 GB library is a trap, not a resource.** The winning move is *not* importing packs — it is **generating art we own at a much higher standard**, using the library only for the handful of CC0 pieces that are genuinely free.

---

## 1. The thesis

> **The game does not need more features. It needs a light.**

One directional light, applied honestly, plus the four systems that are already 80% built and switched off, transforms this from "programmer art with excellent mechanics" into a competitor. Every phase below is either **light**, **juice**, or **signal** — never content.

---

## 2. Milestones

### 🟢 M1 — **MAKE IT LIT** · the ground and the units
*The difference between "a game" and "a screenshot of a game."*

- [x] **M1.1 Ground sky-light ramp** — ✅ *already in the working tree, green.* Two tent-ramped overlay cards (warm sky lift top, cooled floor shade bottom) that cross alpha 0 at mid-frame so the play area centre is **provably untouched**. Lands under water and under every unit.
- [ ] **M1.2 Rim light on the lit side of every entity.** `_spr` already draws a 1.1px `PRINT_INK` rim on two diagonals only. Add a **warm key-side rim** (`Color(1.0,0.94,0.82)`) on the sun-facing diagonal and a cool bounce on the opposite. This is the 2D lighting equivalent of a key/fill split and it costs 2 extra draws per sprite.
- [ ] **M1.3 Re-bake the wreck family.** Fix `_burnt()` (`gen_entities.py:318`) and re-bake `o_wreck_halftrack`, `o_wreck`, `o_apc`, `o_light_tank`, `o_tank_hulk`, `o_heli` — **six sprites from one ~15-line edit**, each keeping its canvas size so no `Art.SCALE` row moves. Target: ≥5 value steps, top-1 colour ≤25%, alpha IoU ≤0.75 pairwise.
- [ ] **M1.4 Distinguish the corpses.** `corpse_soldier1`/`corpse_soldier2`/`fallen_merc` currently measure **alpha IoU 1.00 and 0.95** — one drawing with three palettes. Three litter slots, one sprite.
- [ ] **M1.5 Fix `rock1` vs `rock2`** (IoU **0.98** — one polygon at two radii). One becomes a boulder, one becomes a slab.
- [ ] **M1.6 Blender-render the vehicle family.** `tank_body`, `gunship_body`, `colossus_body` are AI bakes with **4 value steps on the largest sprite in the game (143×143)**. Blender 5.2.2 LTS renders these orthographic-top-down with real bevels and an HDRI — a legitimately better *and* fully-owned result.

**Gate:** `tools/run_tests.sh` green · `tools/screenshots.gd` shows a lit floor with visible light direction · no new lattice power at lag 64/96 (`tools/ground_profile.py`, `tools/ground_lag.py`).

---

### 🟡 M2 — **MAKE IT HIT** · the fire feedback loop
*The game already has the machinery. It is switched off.*

- [ ] **M2.1 Hitstop on the player's own landed hits.** One line at `main.gd:3722` where the HP edge-detect already fires. **1 frame (16.7 ms)** — below conscious perception as duration, unmistakable as weight. Every downstream system (envelope hold, CRT scanline surge, water clock, input latch) is *already built to respond*. The victory card gets 2.
- [ ] **M2.2 Fix the `victory` freeze bug.** It out-hits on trauma/flash/punch and silently skips the one axis that carries weight. Give it the game's only 12-frame freeze.
- [ ] **M2.3 Wire the 11 dead events.** `pickup` first — an ammo crate with **zero visual response** in a coin-economy game is a real hole. Then `vent_jet`/`vent_warn` (a flame hazard with no world-space marker) and the four windup telegraphs. All reuse the already-proven `bullet_dirt` grammar.
- [ ] **M2.4 Blood decals on kills.** `_scorch` exists for explosions; kills leave a clean corpse with no pool. Extend the decal system with a blood variant spawned in `_ev_kill`.
- [ ] **M2.5 Hit-flash for one-shot infantry.** `_enemy_flash` (`main.gd:3722`) only fires for the 3 kinds that track `hp` — ordinary infantry get nothing. Give them a 2-frame flash off the death event.
- [ ] **M2.6 Explosion screen flash + directional light.** No explosion sets `_flash_alpha`. Add a proximity-scaled flash and an angle-consistent key light so blasts agree with the M1.2 sun.
- [ ] **M2.7 Kill-tier camera.** `_kill_tier` scales gibs and radius beautifully but gates camera on `coin >= 25`. A tier-2 `mg_nest` should out-hit a tier-0 rifleman.

**Gate:** full suite green · screenshots show hit-flash on infantry · a screenshot diff shows blood on the ground after a firefight.

---

### 🔵 M3 — **MAKE IT READ** · HUD as equipment
*Metal Slug, not a spreadsheet.*

- [ ] **M3.1 Player vitals cluster.** The largest information gap in the game: **no health, no vest, no armour, anywhere** — in a one-hit-death game. Discrete pips per player row (not a bar), reusing the `Art.arc` drain-ring idiom already used four times. Reclaims width by demoting `SECTOR`/`36m`/`BEST` to PAUSE, where they already live.
- [ ] **M3.2 De-word row 0.** Every chip becomes icon + count. `hud_flag`+`WAVE 12` → flag+`12`. `hud_gunshop`+`SHOP OPEN 4s` → gunshop+4s radial. Cut `SECTOR 1/6 36m` and `BEST 143095`. The icons are **already loaded and drawn**; the words are the redundancy.
- [ ] **M3.3 Bevelled plate.** `_draw_plate` draws a flat 65%-alpha rect with a 1px hairline. `plate_metal_l/c/r.png` (three-way 9-slice) and `SPR_HUD_Frame_Lrg` ship **unused**. Swap in a 9-slice with corner brackets, a top highlight rail and rivets. ⚠️ *Must route through the same `_emit_plate_rect` seam or the `hud_visibility.gdshader` aperture stops punching holes.*
- [ ] **M3.4 Kill feedback as an event.** The streak ring is a 5.5px arc inside the top-left row. A 20-kill streak should scale-punch and bloom.
- [ ] **M3.5 Type scale.** Collapse 12 arbitrary sizes to the **8/10/16/24/32** grid (the only clean multiples of PixelOperator8's em) and add a weight channel.

**Gate:** full suite green · screenshot diff shows a materially shorter row 0 · localization suite green.

---

### 🟣 M4 — **MAKE IT DENSE** · CC0 assets + Blender pipeline
*The honest asset answer: 2,012 CC0 PBR materials beat 775 packs you cannot ship.*

- [ ] **M4.1 Harvest ambientCG CC0 ground materials.** Desert/scorched-earth/ash PBR → bake to seamless 128px albedo, matched to the existing biome stops. API is live and confirmed.
- [ ] **M4.2 Blender ground-bake pipeline.** `tools/blender_bake.py` — headless Blender, procedural displacement → albedo + normal. Replaces the std-8.46 flat grain with real macro structure.
- [ ] **M4.3 Enable the unused CC0 inventory.** `kenney_crosshair-pack`, `kenney_ui-pack`, `kenney_tower-defense-top-down`, `kenney_ui-audio`, `kenney-audio/{impact,sci-fi,railgun}` — all CC0, all sitting there, all currently unused.
- [ ] **M4.4 Draw the nine unused `ICON_Map_*` icons** into the M3 minimap/objective rail.
- [ ] **M4.5 Verify or quarantine the OGA muzzle pack.** No licence in the archive → quarantined until proven.

**Gate:** `ASSETS.md` updated per row with source + licence · `tools/lint_assets.gd` green · every new file traceable to a recorded pipeline.

---

### ⚪ M5 — **MAKE IT PROVABLE** · the review gauntlet
*A screenshot is a claim. A ratchet is a proof.*

- [ ] **M5.1** Capture signature moments before/after every phase.
- [ ] **M5.2** Adversarial multi-model visual review (`/tripple-a-game`): a consumer-grade critic *sees* the captures and names the biggest giveaways for the genre.
- [ ] **M5.3** Judge-to-10 ratchet per change (`/adversarial-code-judge`).
- [ ] **M5.4** Full suite + CI + export smoke on 3 OSes.

---

## 3. Phase order & why

```
M1 (lit)  →  M2 (hit)  →  M3 (read)  →  M4 (dense)  →  M5 (prove)
  art          feel         UI            assets         verify
```

**M1 before M2** because rim light is what makes the hit-flash read. **M2 before M3** because the HUD changes are the most test-fragile and should sit on a stable feel stack. **M4 late** because ambientCG/Blender output is a *replacement* for art, not an addition — doing it before M1 would mean lighting art we're about to throw away.

## 4. Risk register

| Risk | Mitigation |
|---|---|
| Anti-lattice ratchets (`test_ground_base_*`, `test_ground_dressing_*`) | M1.1 is continuous-in-y and constant-in-x → adds no period. Run `tools/ground_lag.py` + `tools/ground_profile.py` after every ground edit. |
| `GROUND_SHADE × _ground_stops[0]` is a **load-bearing constant in 4 test files** | Never touch either. All ramps multiply on top. |
| HUD edits break `test_hud.gd` width assertions + the localization suite | That is the *good* red. Fix forward. |
| Parallel agents colliding in one checkout | Per-agent file territories, no two agents on `main.gd` at once. |
| Killing the engine-error gate | Every phase ends with the full suite green. |

## 5. Fan-out map

| Wave | Agents | Territory | Model |
|---|---|---|---|
| 1 | 6 | M1.2 rim · M1.3 wreck · M1.4/5 corpse+rock · M1.6 vehicles · M3.1/2 HUD · M4.1 assets | Sonnet |
| 2 | 4 | M2.1–2.2 hitstop · M2.3 dead events · M2.4–5 decals · M2.6–7 camera | Sonnet |
| 3 | 1 | M3.3–5 plate + type scale | Sonnet |
| 4 | 1 | M4.2 Blender pipeline | Sonnet |
| 5 | 1 | **Adversarial review of the whole diff** | **Opus** |

**Sonnet implements. Opus reviews. Haiku does the fetching. Never a fan-out of Opus.**

---

## 6. Definition of done

- [ ] Ground has a **measurable** light direction (the ratchet asserts it; the screenshot shows it)
- [ ] The wreck family reads as **four different vehicles** (alpha IoU ≤0.75 pairwise)
- [ ] A landed hit **stops the world for 1 frame**
- [ ] The victory card holds the screen harder than a boss death
- [ ] `pickup` has a visual response
- [ ] The player can see **their own vitals**
- [ ] Row 0 is **icons, not sentences**
- [ ] Every asset traces to `ASSETS.md` with a recorded licence
- [ ] **1,218+ methods, 0 failures**, 3-OS CI green
- [ ] An adversarial reviewer, *looking at the screenshots*, cannot name the top-3 things that give away that this isn't GOTY
