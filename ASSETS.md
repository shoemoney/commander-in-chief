# Asset provenance & licensing

`LICENSE` (MIT) covers **source code only**. Every bundled asset is listed below
with where it came from and what you may do with it. If an asset is not on this
list, treat it as unlicensed until it is.

Everything here is owned by the project or CC0, in the working tree **and** in
git history.

## ✅ Images — all owned or CC0

| Path | Files | Source | License |
|---|---|---|---|
| `assets/art/ui/` `hud/` `icons/` | 128 | Procedurally generated — `tools/gen_ui_chrome.py`, `gen_ui_icons.py`, `gen_ui_glyphs.py`, `gen_fx_cards.py` | Project-owned (MIT alongside the code) |
| `assets/art/fx/` | 21 | Procedurally generated — `tools/gen_fx_cards.py` | Project-owned |
| `assets/art/{decor,p2,mil2,cast2}` + 7 top-level | 87 | Procedurally generated — `tools/gen_entities.py` | Project-owned |
| `assets/troops/` | 9 | Procedurally generated — `tools/gen_entities.py` | Project-owned |
| Bosses, player tank, desert flora (14 files) | 14 | Generative AI — fal.ai · Replicate · `nano-banana`. Pipeline: `tools/generate_desert_assets.py`, provenance: `assets/art/desert_assets_source.md` | Project-owned (verify each service's output-ownership terms) |
| `assets/ui/intro/` | 2 | Generative AI (intro cinematic key art) | Project-owned |
| `assets/cc0/` | 27 | Kenney game assets | **CC0** — `assets/cc0/LICENSE-CC0.txt` |

Every procedurally generated sprite is reproducible: each generator's `SIZES`
dict is its manifest, and re-running the tool overwrites the PNGs. Original
canvas sizes and `.import` `size_limit`s are preserved so no draw site moves.


## ✅ Fonts

| Path | Source | License |
|---|---|---|
| `assets/fonts/PixelOperator8.ttf` | Jayvee Enaguas (HarvettFox96) | **CC0** — `assets/fonts/LICENSE-CC0.txt` |

## ✅ Audio — owned, synthesized in-house

| Path | Files | Source | Status |
|---|---|---|---|
| `assets/vo/cmd/` | 56 mp3 | Synthesized speech — commander barks + intro narration | ✅ owned |
| `assets/audio/{enemy_death,enemy_spawn}/` | 88 mp3 | Synthesized speech (see each folder's `README.md`) | ✅ owned |
| `assets/audio/ya_chants/` | 30 mp3 | The **audition reel** the death bank was cast from — 15 voices, multilingual model, no delivery direction. `enemy_death/` re-cut the 6 approved voices with agony tags, so these are source material, not spare content. `.gdignore`d: kept for provenance, **excluded from the build** | ✅ owned |

These 174 files were regenerated in-house and are owned by the project, so an
MIT/CC0 grant may sublicense them onward to everyone who clones the repo.

> ### 🎭 Owner decision (2026-07-27): ship it, as satire
>
> `assets/vo/` synthesises the voice of an identifiable living public figure.
> **Publicity and likeness rights belong to that person** and are not the project's
> to grant — remaking the audio in-house does not change that, because it was never
> a licensing question.
>
> The owner has considered this and **decided to ship**: the work is satire, in a
> game named *Commander in Chief*, and the exposure is knowingly accepted. This is
> recorded as a deliberate call, not an oversight — the alternatives weighed and
> declined were dropping `assets/vo/` from the build, or re-synthesising the 56
> commander barks with an original non-identifiable voice.

## 📋 Non-asset files

| Path | Note |
|---|---|
| `assets/input/actions.vdf`, `assets/steam/*.vdf` | Project-authored Steam config |
| `docs/media/`, `media/` | Screenshots and video **rendered from the game**; they inherit whatever the depicted assets carry. Re-capture after any asset swap. |

## Reproducing the art

Every procedurally generated sprite is reproducible: each generator's `SIZES`
dict is its manifest, and re-running the tool overwrites the PNGs. Original
canvas sizes and `.import` `size_limit`s are preserved so no draw site moves —
edit the generator and re-run it rather than hand-painting a PNG.
