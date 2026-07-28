# Commander In Chief - Style Bible

Ground truth for "does this read as one game." Every value below is a real,
named constant already live in `src/view/art.gd` / `src/view/grade.gdshader`
- referenced here by NAME, not line number, so this doc cannot silently drift
out of sync the moment someone reorders the file. If you change one of these
constants, update this doc in the same commit.

## The problem this solves

The view draws from 4 disjoint art sources with no shared native shading:

| Source | Where | Native look |
|---|---|---|
| Retired 3D entity bakes | `assets/art/*.png` (bakers retired — see git history) | lit 3D render, top-down orthographic |
| CC0 tiles | `assets/cc0/*.png` | flat vector fill |
| Authored soldier sprites | `assets/troops/*.png` | hand-drawn, own keyline |
| Generated boss/vehicle art | `assets/art/*.png` (fal.ai/Replicate, nt-02/nt-03) | photoreal-leaning render |

Nothing at import time unifies these. Unification happens in two layers,
draw-time first, full-frame second. Skipping either layer is the "collage of
stock art" failure mode this doc exists to prevent.

## Layer 1: draw-time (per-sprite, in `src/view/art.gd`)

Every sprite draw in `main._spr()` runs its texture through `Art.tint()` and
(if flagged) `Art.outlined()` before it ever hits the screen. This is source
of truth for family membership - a new asset joins ONE of these, it never
ships with its native color untouched.

- **Threats read warm-bright, always** (the `TINT` dictionary). Rushers,
  elites, enemy_* infantry, specialists (ghillie/courier/sapper),
  frogman/observer - every hostile actor gets `r > g > b`, value lifted
  above 1.0, regardless of which of the 4 sources it came from. Example:
  `"rusher": Color(2.1, 1.7, 1.15)` (entity bake) sits in the exact same
  family as `"ghillie": Color(1.7, 1.5, 1.05)` (authored). This is the rule
  that keeps a CC0 tile enemy and a legacy bake enemy legible as the same
  kind of threat.
- **Vehicles are olive-drab, apex bosses break to gunmetal.**
  `Art.OLIVE_VEH` is the disposable-tank family (tank/mil2 vehicles).
  `Art.BOSS_VEH` is the desaturated apex family (gunship/colossus) so the
  bosses read as a tier jump, not a reskinned jeep - this is the family a
  future generated-vehicle asset must slot into, not invent a fifth hue.
- **Decor/litter recedes.** `Art.DECOR_ASH` is the one muted family every
  rock/wreck/hulk/corpse/crate lerps toward as the run progresses
  (`foliage_march`), so scenery never competes with the warm-bright threats
  for the eye.
- **Foliage runs one desert->ash ramp**: `Art.DESERT_FOLIAGE` /
  `Art.FOLIAGE_ASH`, independent of ground-tile source.
- **One shared dark ink for every rim and HUD backing:** `Art.PRINT_INK`
  (a near-black warm-neutral, not pure 0,0,0). The 1.1-2.2px outline rim
  `main._spr()` draws under every flagged sprite (`Art.outlined()`, ~80
  sprite keys spanning all 4 sources) and the dark backing behind every HUD
  metal-plate label (`main._metal_plate()`) are the SAME constant, not two
  independently-chosen literals - a battlefield silhouette and a HUD label
  are printed with the same ink.
- **One shared HUD steel midtone:** `Art.PLATE_STEEL` tints the two accent
  rules `main._metal_plate()` draws along the top/bottom of its soft-edged
  `fx_softspot` ribbon - the second half of that same HUD-chrome pass, named
  for the same reason as `Art.PRINT_INK` above (a test in `tests/test_assets.gd`
  asserts neither literal is ever re-inlined by hand instead of read from
  these constants).

## Layer 2: full-frame (`src/view/grade.gdshader`, always on)

Layer 1 gets every sprite into the right family; the grade shader is the
"one print" pass laid on top of the finished frame (world + HUD):

1. Filmic highlight shoulder (soft-clips hot whites, 30% mix).
2. Shared shadow warmth: a small warm RGB lift weighted by `(1 - luma)` -
   one warm key light across every biome's darks.
3. 6% desaturation toward luma - pulls hue-islands toward one film without
   flattening biome contrast.
4. Shop/intermission "breather" calm variant (a4-15).
5. Procedural film grain, luma-shaded so it's near-zero in highlights,
   rides Reduce Motion + the DISPLAY 0/25/50/75/100% stepper.

Grain (stage 5) is the *last* pass over an already-unified frame - Layer 1 is
what makes that grain read as "one graded print" instead of static laid over
a collage. Shipping stage 5 alone, without Layer 1's family rules, is exactly
the failure mode this bible exists to prevent.

## Known remaining gap, investigated (not fixable by a re-bake alone)

`"courier"` (SUPPLY COURIER, in `Art.OUTLINE`) is the one enemy-infantry
sprite that still reads visibly softer/blurrier than its siblings
(ghillie/sapper/m_bombsuit/m_pilot) at the same on-screen size, even though
Layer 1 already places it correctly in the warm-threat palette family.

This attempt actually ran the re-bake to check whether it was a missed
pipeline step: reproduced `tools/bake_sprites_p2_mil.gd`'s documented recipe
(that script has since been retired to git history)
against the vendor legacy project (own copy under `/tmp`, vendor left
read-only) and re-rendered `courier.png` fresh. The output was BYTE-IDENTICAL
(same md5) to the PNG already committed at `assets/art/p2/courier.png`.
So courier is NOT an un-re-baked leftover - it already goes through the
exact same 64px bake pipeline, camera rig, and lighting as ghillie/sapper.
The softness is inherent to the source legacy model
(`SM_Chr_Insurgent_Male_01`) at that resolution, not a missed pipeline step.
Fixing it for real needs either a higher source mesh/texture substitute for
that specific model or a downstream per-sprite sharpen pass - a genuine
asset-acquisition or -processing job, out of scope for this item, and now
correctly diagnosed instead of guessed at.
