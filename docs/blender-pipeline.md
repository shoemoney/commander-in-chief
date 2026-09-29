# Blender vehicle/boss sprite pipeline

`tools/blender_vehicles.py` renders the six heavy-unit sprites — `tank_{body,barrel}`,
`gunship_{body,barrel}`, `colossus_{body,barrel}` — as **orthographic top-down
Cycles renders of procedural geometry built entirely inside the script**, and grades
its own output against the size the player actually sees.

It replaces six generative-AI bakes that had no recorded pipeline (`ASSETS.md` row
24, "service/model/date unrecorded"). Nothing is downloaded, no HDRI is fetched, no
external model or image is read: every vertex is a literal in this repository, and a
re-run reproduces the committed PNGs byte for byte.

Output lands in `assets/art/vehicles/`. **Nothing is wired into the game** — swapping
`Art.TEX` to point at these is a separate change, and the canvases are deliberately
identical to the originals so that change is a path edit, not a re-tune.

---

## Running it

```sh
blender -b --factory-startup --python tools/blender_vehicles.py
blender -b --factory-startup --python tools/blender_vehicles.py -- --only tank_body
blender -b --factory-startup --python tools/blender_vehicles.py -- --outdir /tmp/v --samples 48
blender -b --factory-startup --python tools/blender_vehicles.py -- --ss 2      # fast look pass
```

| flag | default | meaning |
|---|---|---|
| `--outdir` | `assets/art/vehicles` | flat output directory; `<name>.png` |
| `--only NAME` | all six | render one sprite; repeatable |
| `--samples` | `96` | Cycles samples (48 is fine for a look pass) |
| `--ss` | `4` | supersample factor; output is always the fixed canvas size |

Exit codes: `0` all gates passed · `1` a quality gate failed · `2` bad arguments.
The full six-sprite run is **under 10 seconds** on this box at `--ss 4 --samples 96`;
the box is shared, so keep samples modest rather than pushing toward a noise-free
reference that nobody can re-run in ten seconds.

`--ss` below 2 is rejected: the render is downsampled onto the fixed canvas, and a
1:1 render is exactly the soft edge the pipeline exists to avoid.

---

## What it draws

Each vehicle is modelled in a world box exactly **one canvas wide**, with the muzzle
toward **+Y**. Nothing exceeds `|x|,|y| <= 0.44`, which is what buys the ≥2 px clear
margin on every side that the gate enforces.

| sprite | canvas | drawn | design |
|---|---|---|---|
| `tank_body` | 104² | **46.4 px** | two track runs with link pattern and end rollers, tapered hull, raised glacis wedge, louvred engine deck, flank stowage, faceted 8-gon turret with ring gap and mantlet |
| `tank_barrel` | 72² | **30.8 px** | breech block, lit collar, tapered tube, fume extractor, slotted muzzle brake |
| `gunship_body` | 112² | **97.6 px** | swept wings in three tones, wingtip pods, canted fins, twin rotor nacelles with discs and 4-blade hubs, dark canopy, tailplane |
| `gunship_barrel` | 48² | **31.2 px** | compact chin cannon: mount, mantlet, shrouded tube with lit cap and dark band, slotted brake |
| `colossus_body` | 128² | **143.5 px** | eight segmented skirt plates with bolts over a dark base, stepped three-tier deck, side armour panels, prow + ramp, rear grille banks, ribs, emissive core housing, four track pods |
| `colossus_barrel` | 72² | **56.2 px** | twin siege tubes, lit cross-brace, sleeve bands, twin slotted brakes |

**Distinctness is a measured gate, not a claim.** The tank is rectangle-plus-circle,
the colossus is a wide square, and only the gunship is a cross — so pairwise alpha
IoU at drawn size has to stay under 0.75. Measured: **0.076** (tank/colossus),
**0.263** (tank/gunship), **0.272** (gunship/colossus).

---

## Lighting

The value structure is produced by **lighting real volumes**, not by painting stacked
polygons — which is why it survives a 0.44 downscale.

```
key   SUN   dir (+0.38, -0.60, -1.00)   energy 8.5    angle 0.030 rad   (1.0, 0.972, 0.930)
fill  AREA  dir (-0.52, +0.70, -0.55)   energy 7.0    size 2.4 m         (0.52, 0.66, 1.0)
world        (0.020, 0.020, 0.025)      strength 1.0
```

- **Key travels toward `+X, -Y, -Z`, so it comes from the north-west and above.**
  That single choice produces the game's "RAISED, north-lit crown" convention (the
  `_bag()` vocabulary in `tools/gen_entities.py`) for free: a 45° north-west bevel
  has normal `(0, .71, .71)` and reads `cos ≈ 0.96`, a flat top face reads `0.85`,
  and a south-east bevel reads `≈ 0`. Every raised element therefore gets a hard
  bright edge on its north-west and a dark one opposite, for free and consistently.
- **Cool fill from the south-east**, low and wide. It keeps shadow sides readable and
  tinted instead of black, which is what stops a 46 px tank from collapsing into a
  silhouette. Its lamp position is *derived* from its direction
  (`-FILL_DIR * 2.2`) — an earlier revision placed it by hand and aimed it by hand
  and shipped aimed 130° away from the subject, contributing nothing to any render.
- **Metallic is capped at ~0.30 on everything.** From directly above, a metallic
  surface reflects the world, and the world is nearly black — high-metallic gunmetal
  rendered as near-black holes in the first pass.
- **Emissive only on the colossus core** (`emit (255, 96, 24)`, strength 0.70),
  tuned so the core is an orange with a hot centre rather than a clipped
  pale-yellow sticker.

## Materials

Principled BSDF only — base colour, roughness, metallic, and emission for the core.
Colour is written as an **sRGB 0–255 triple** (the house convention in
`gen_entities.py`) and converted to linear internally. Every sprite carries an
explicit five-rung value ladder so that after downscale the alpha still shows at
least five distinct steps:

| tier | role |
|---|---|
| 5 | bright top faces — glacis, turret roof, track-link crowns, prow, core housing |
| 4 | lit upper hull / outer wing panels / tube caps |
| 3 | mid hull, fuselage, mantlets |
| 2 | dark recess — turret ring gap, louvre slots, spine seams, brake slots |
| 1 | near-black skirt, track rubber, canopy |

---

## Determinism

Two full runs at `--ss 4 --samples 96` produce **byte-identical** PNGs. Verified by
SHA-256 on all six files, before and after the metric changes that followed.

Guaranteed by, in the script:

- `cycles.device = "CPU"` — GPU kernels differ between machines and backends.
- `cycles.seed = 20260929`, `cycles.use_animated_seed = False`.
- `render.dither_intensity = 0.0` — dithering is itself a seeded noise source.
- `view_transform = "Standard"`, `look = "None"`, no curve mapping — no filmic toe
  to shift where a value step lands.
- No motion blur, no DOF, no caustics; bounce counts fixed (4 total / 3 diffuse / 2 glossy).
- `bpy.ops.wm.read_factory_settings(use_empty=True)` per sprite — no leftover state.
- The PNG is written by a **local zlib+struct encoder**, not Blender's. Blender's
  writer is free to change its chunk set between builds; this one does not. (There is
  also a local PNG *decoder*, because Blender's Python has numpy but no Pillow.)
- All jitter comes from a fixed integer hash (`_j`), never from `random`.

**Not guaranteed across Blender versions**: Cycles' sample pattern and OIDN are
version-dependent. The byte-for-byte claim is for *this* build — Blender 5.2.2 LTS.
Changing Blender may re-roll the noise floor; the committed PNGs are the reference.

---

## Alpha and downsampling

`film_transparent = True`, straight (unpremultiplied) RGBA8.

The render is supersampled 4× and box-downsampled **in premultiplied space**, then
un-premultiplied:

```python
alpha  = src[..., 3:4] / 255.0
premul = concat([src[..., :3] * alpha, alpha])      # RGB 0..255, alpha 0..1
blocks = premul.reshape(canvas, ss, canvas, ss, 4).mean(axis=(1, 3))
rgb    = blocks[..., :3] / blocks[..., 3:4]          # straight alpha out
```

Averaging in premultiplied space is what keeps the transparent background from
smearing black into every edge pixel. Mixing the two scales — premultiplying by a
0..1 alpha and then dividing by a 0..255 alpha — is a 255× brightness bug that
renders a perfectly lit vehicle as **solid black**; that is exactly what the first
run of this pipeline did, and it is why the scale discipline is commented in place.

Verified straight: an edge pixel at alpha 93 carries RGB `(139, 149, 105)` — full
value, not a darkened version — and compositing over white and over black gives a
clean gradient with no dark fringe.

---

## Orientation

**Muzzle north (+Y = up in the PNG).**

`main.gd` draws these with `PI` (bosses, so the guns point down-screen at the
players) and with `barrel_angle + PI/2` (tank turret) — the same `+PI/2` that
`Art.facing_rotation` applies to troops authored muzzle-up. Being *drawn* at `PI`
means the authored art faces `+Y`, not `-Y`.

The camera sits at `(0, 0, 8)` with **zero rotation**, so world `+Y` lands at the top
of the PNG with no transform fudge. The intermediate render is read back in file
order and **not** re-flipped: Blender's internal buffer is bottom-up but
`save_render` un-flips it on the way to disk, so a second flip turns the vehicle
around. That was the second bug the first run shipped, and it is invisible in a
single-sprite review — the tank simply drove south.

### The orientation gate

`measure()` returns the **ink centroid** as a fraction of the alpha bbox height,
measured from the north edge. A muzzle-north vehicle is all mass *behind* its
muzzle, so it must be `>= 0.49`; flip the geometry 180° and it inverts.

The gate is non-vacuous on real data, not just in theory: the shipped
`gunship_barrel` bake measures **0.443** and would fail it, because that sprite is
authored muzzle-*down*. Measured on the new art: `tank_barrel 0.558`,
`gunship_barrel 0.531`, `colossus_barrel 0.528`, `gunship_body 0.596`,
`tank_body 0.505`, `colossus_body 0.496`.

---

## Verification

Every sprite is re-read from disk after writing and measured **at drawn size**
(`canvas × Art.SCALE × call_scale`), because a 104 px canvas drawn at 46 px and a
128 px canvas drawn at 143 px are two different pictures and only one of them is
what the player sees. The same `measure()` grades the old bakes for the before
column, so the comparison is like-for-like.

| gate | bar |
|---|---|
| canvas dimensions | exactly the contract, e.g. `tank_body` 104×104 |
| non-empty alpha | opaque area in `[6 %, 90 %]` of the canvas |
| **value steps** | ≥ 5 luma buckets (8-level quantisation) holding ≥ 2 % of the opaque area |
| **top-1 colour** | ≤ 25 % of the opaque area in any one 8×8×8 RGB quantised bin |
| luma stddev | ≥ 30 |
| edge margin | ≥ 2 px clear on **every** side, muzzle side included |
| ink centroid | ≥ 0.49 of bbox height from the north edge |
| body distinctness | pairwise alpha IoU ≤ 0.75 at drawn size |

### Measured, before → after

| sprite | canvas | drawn | steps | top-1 % | luma σ | ink (N) |
|---|---|---|---|---|---|---|
| `tank_body` | 104² | 46.4 px | 5 → **7** | 26.6 → **17.9** | 42.2 → **50.6** | 0.492 → **0.505** |
| `tank_barrel` | 72² | 30.8 px | 6 → **6** | **69.2 → 22.5** | 42.5 → **46.9** | 0.560 → **0.558** |
| `gunship_body` | 112² | 97.6 px | 6 → **7** | 21.3 → **15.9** | 49.9 → **47.0** | 0.529 → **0.596** |
| `gunship_barrel` | 48² | 31.2 px | 7 → **7** | 18.5 → **21.8** | 44.9 → **46.9** | **0.443** → 0.531 |
| `colossus_body` | 128² | 143.5 px | **4 → 8** | **33.9 → 21.5** | **21.8 → 52.3** | 0.510 → **0.496** |
| `colossus_barrel` | 72² | 56.2 px | 5 → **7** | 19.3 → **12.4** | 34.8 → **55.9** | 0.597 → **0.528** |

Pairwise body IoU: **0.076** / 0.263 / 0.272 (bar 0.75).

Two before-numbers are worth calling out, because they are the whole point of the
job:

- **`colossus_body` had 4 value steps and a luma σ of 21.8.** Everything on that
  143 px sprite sat inside a 32-value-wide luminance band. It now has 8 steps and
  σ 52.3 — more than double the contrast, and it is the finale boss drawn *larger*
  than its own canvas, so this is the sprite with the most pixels on screen.
- **`tank_barrel` was 69.2 % one quantised colour.** Four pixels wide at 31 px drawn,
  it was a grey stick. It is now 22.5 %.

One regression, stated plainly: `gunship_barrel` top-1 went **18.5 → 21.8 %**. It
was already well under the bar and still is; the old gatling-cluster sprite happened
to carry a lot of incidental per-pixel colour that a clean render does not. Its step
count, stddev and orientation all improved.

### Two failures the top-1 gate actually caught

Both were found by the gate, not by eye, and both are the kind of thing that looks
fine in isolation:

1. **The gunship's wings shared the fuselage base colour.** Fuselage and wing tops
   landed in one quantised bin and the sprite measured **35.3 %** top-1. More panel
   lines did not help — the panels were the same tone. Fixed by giving the wings
   their own three-tone scale (dark spar bay / mid inboard / bright outboard).
2. **The colossus's armour skirt was one continuous octagonal ring** rendering at a
   single flat value: **26.7 %** of the sprite, one polygon. Segmented into eight
   separate plates over a dark base — which also bought the panel-line detail the
   143 px size can carry — it dropped to 21.5 %.

---

## What this pipeline does not do

- It does not wire the sprites into the game. `src/view/art.gd` still points at
  `assets/art/*.png`; those six originals are untouched.
- It draws no shadows onto the ground. `main.gd` already draws a footprint-derived
  contact shadow per heavy unit (`VEHICLE_CONTACT`), and baking one in would double
  it. The dark undersides here come from Cycles occlusion between the hull and the
  tracks, which is what makes the vehicle sit rather than float.
- It does not chase the last 1 % of top-1 on every sprite by flattening materials.
  The tank's 17.9 % and the colossus's 21.5 % come from geometry tiers, which is
  where they should come from.

---

## `ASSETS.md` provenance text

The row currently reads:

> | Vehicles + bosses — `tank_{body,barrel}`, `gunship_{body,barrel}`,
> `colossus_{body,barrel}` | 6 | Generative AI, **service/model/date unrecorded**.
> No generator produces these and `desert_assets_source.md` does not cover them —
> regenerate with a recorded pipeline before relying on the ownership claim |
> Project-owned **unverified** |

Suggested replacement (this is text to paste; `ASSETS.md` was not edited here):

> | Vehicles + bosses — `assets/art/vehicles/{tank,gunship,colossus}_{body,barrel}.png`
> | 6 | Procedurally modelled and rendered — `tools/blender_vehicles.py`
> (Blender 5.2.2 LTS, Cycles CPU, orthographic top-down, pure procedural geometry,
> no external assets); pipeline and determinism notes in
> `docs/blender-pipeline.md`. Supersedes the earlier generative-AI bakes, which had
> no recorded service/model/date. | Project-owned (MIT alongside the code) |

If the sprites are adopted as the live ones rather than parked in
`assets/art/vehicles/`, drop the directory prefix and name the script only.
