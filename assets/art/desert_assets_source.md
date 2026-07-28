# Desert asset source (nano-banana pipeline)

How `cactus_large.png`, `cactus_small.png`, `scrub.png`,
`decor/tumbleweed.png`, `decor/dry_shrub.png`, and `p2/cactus_dead1-3.png`
were produced. `tools/generate_desert_assets.py` runs the whole pipeline
below end to end -- `python3 tools/generate_desert_assets.py` -- if these
sprites ever need to be regenerated (restyle, retry a bad render, etc).

## 1. Generate (parallel, fanned out per asset group)

Each sprite was rendered with `~/.claude/skills/image-toolkit/scripts/generate.py`
(OpenRouter `google/gemini-3-pro-image-preview`, aka "nano-banana"), all 8
launched as background jobs and `wait`-ed on together. The 8 jobs are not
one flat pile -- `tools/generate_desert_assets.py::GROUPS` organizes them
into three asset groups so siblings read as one matching material instead
of 8 independent rolls of the dice:

| group | jobs | shared consistency note appended to every prompt in the group |
|---|---|---|
| cacti | cactus_large, cactus_small | "Match the same dusty sage-green low-poly cactus material as the rest of the cacti group." |
| scrub | scrub, tumbleweed, dry_shrub | "Match the same sun-bleached dry-brush low-poly material as the rest of the scrub group." |
| dead | cactus_dead1, cactus_dead2, cactus_dead3 | "Match the same sooty black and ash-grey charred low-poly material as the rest of the dead group." |

The fan-out is two levels deep and both levels are real subprocesses, not
just loops: `dispatch_groups()` re-invokes this same script once per group
with `--group <name>`, so each group runs as its own independent OS
process in parallel with its siblings; each of those group processes then
fans its own jobs out as background `image-toolkit` renders, launched
together and `wait`-ed on together. Grouping changes prompting (the
consistency note) and reporting, not total render concurrency -- all 8
jobs still run in parallel either way.

`--dry-run` exercises this exact dispatch/wait wiring (real subprocesses,
real chroma-key/trim/letterbox/validate, synthetic placeholder pixels
instead of a real render) without an API key, the image-toolkit skill, or
Godot -- point `--out-dir` at a scratch directory and it fans out and
reports per-group just like a real run. It always implies `--skip-import`
and refuses to run at all if `--out-dir` resolves inside the real `assets/`
tree (including the default), so a synthetic placeholder can never
overwrite a committed sprite or get baked into a real `.import`:

```sh
python3 tools/generate_desert_assets.py --dry-run --out-dir /tmp/scratch
```

`GROUPS` is already the per-group unit of work, so swapping
`dispatch_groups()`'s `subprocess.Popen` re-invocation for real Claude Code
Task-tool subagent dispatch (one subagent per group, each handed that
group's job list + consistency note) would only touch that one function,
not the job data, the post-process pipeline, or the import step. Adding a
new group (e.g. a desert ground-tile group, if one is ever generated via
this pipeline rather than reusing the existing Kenney sand tile) is a new
`GROUPS` entry, no other code changes. Shared style suffix (appended after
the per-group consistency note):

```
low-poly 3D style low-poly 3D game asset render, faceted flat-shaded
geometry, isometric top-down camera angle looking slightly downward, prop
centered and fully in frame with generous margin, pure solid magenta
background #FF00FF (not transparent, not white), no ground plane, no
shadow, no text, no watermark
```

Per-sprite subject prompts:

| output | subject prompt |
|---|---|
| cactus_large.png | A tall saguaro-style desert cactus cluster with two upright arms, dusty sage-green faceted low-poly surface with darker green shading crevices. |
| cactus_small.png | A small cluster of round barrel cacti and prickly pear paddles, dusty sage-green faceted low-poly surface. |
| scrub.png | A small sparse dry desert scrub bush with a few thin spiky low-poly branches, dusty olive-brown faceted surface. |
| decor/tumbleweed.png | A round classic tumbleweed, a tangled ball of dry dead brush and thorny twigs, faceted low-poly spherical silhouette, straw-tan and dry-brown coloring. |
| decor/dry_shrub.png | A row of four stacked rounded dry desert scrub mounds forming a long hedge-shaped bush line, sun-bleached olive-tan faceted low-poly surface, dense enough a soldier could crouch and hide behind it. |
| p2/cactus_dead1.png | A charred blackened dead cactus husk, scorched and burnt, low-poly faceted surface, sooty black and ash-grey coloring, one broken stub arm. |
| p2/cactus_dead2.png | A charred blackened dead cactus husk lying tilted, scorched and burnt, low-poly faceted surface, sooty black and ash-grey coloring, cracked surface. |
| p2/cactus_dead3.png | A charred blackened dead tumbleweed husk, scorched and burnt tangled dry brush ball, low-poly faceted surface, sooty black and ash-grey coloring. |

`decor/dry_shrub.png` is intentionally a dry BUSH, not a cactus -- it
replaces `decor/hedge.png`, which is `kind == 1` pass-through concealment
cover in `main.gd::_draw_rocks()`. A cactus silhouette there would read as
hard-blocking cover it isn't.

## 2. Post-process (chroma-key -> trim -> fit)

The raw renders land on an imperfect, slightly noisy magenta backdrop, not
a clean matte, so the key color is sampled from the four corners of each
image rather than hardcoded, then every pixel within a Euclidean RGB
distance of that sample is made transparent:

```python
from PIL import Image

def chroma_key(im, thresh=60):
    im = im.convert("RGBA")
    px = im.load()
    w, h = im.size
    corners = [px[0, 0], px[w-1, 0], px[0, h-1], px[w-1, h-1]]
    br, bg, bb = (sum(c[i] for c in corners) / 4 for i in range(3))
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if ((r-br)**2 + (g-bg)**2 + (b-bb)**2) ** 0.5 < thresh:
                px[x, y] = (r, g, b, 0)
    return im
```

Each keyed image is then trimmed to `getbbox()` with a 6px pad, and
`Image.thumbnail()` + centered paste onto a transparent square canvas sized
to match the sprite it stands in for (`cactus_large`/`cactus_dead1-3` ->
120px, `cactus_small` -> 96px, `scrub` -> 72px, `tumbleweed` -> 200px,
`dry_shrub` -> 220px) -- these are the exact canvas sizes of
`tree_large.png`, `tree_small.png`, `fern.png`, `fern2.png`, and
`hedge.png` respectively, so a future swap item is a same-size drop-in.

## 3. Import settings

`--headless --path . --import` initially reimports new PNGs against the
project's default `[importer_defaults] texture { compress/mode: 2 }`
(VRAM/BC compressed), which `tests/test_assets.gd::test_a1_entity_bakes_are_lossless()`
forbids for anything under `assets/art/` -- BC mushes the low-poly
outline silhouettes. Each new `.png.import` was hand-edited to match the
existing entity bake convention (`compress/mode=0`, `detect_3d/compress_to=0`,
`vram_texture=false`, single non-suffixed `path`/`dest_files`, mirroring
`tree_large.png.import`), the stale `.godot/imported/*.ctex` cache entries
were deleted, and `--import` was re-run to bake the corrected settings.

---

## SUPERSEDED — swapped to Kenney Desert Shooter Pack (CC0)

The nano-banana sprites above were **replaced** with art from the
**Kenney Desert Shooter Pack** (https://kenney.nl/assets/desert-shooter-pack),
license **CC0 1.0** (public domain, no attribution required). The pipeline
above still works if you ever want to regenerate the AI art instead.

Each 16×16 pixel-art tile was upscaled (nearest-neighbor, `magick -filter point`)
to the existing sprite's exact dimensions, so the whole view pipeline
(`Art` SCALE / DESERT_FOLIAGE tint / ash-char ramp) keeps working with **zero
code change** — only the PNG bytes changed. Tile → sprite mapping (source
`PNG/Tiles/Tiles/tile_XXXX.png`):

| sprite | Kenney tile | subject |
|---|---|---|
| `cactus_large.png` | tile_0063 | tall saguaro cactus |
| `cactus_small.png` | tile_0081 | small round cactus |
| `scrub.png` | tile_0044 | grass/sprout tuft |
| `decor/tumbleweed.png` | tile_0082 | tan dry bush |
| `decor/dry_shrub.png` | tile_0083 | tan dry bush (variant) |
| `p2/cactus_dead1.png` | tile_0085 | animal skeleton (charred by ash ramp) |
| `p2/cactus_dead2.png` | tile_0084 | skull/bones |
| `p2/cactus_dead3.png` | tile_0062 | pine husk (charred by ash ramp) |

`kenney/sand.png` (the ground tile): the pack's interior sand tiles carry a
dark AO edge that grids visibly when tiled full-screen, so the ground is a
**seamless** sand tile synthesized in the pack's palette
(wrap-blurred noise, `rgb(205,158,110)`→`rgb(238,208,168)`) instead.
