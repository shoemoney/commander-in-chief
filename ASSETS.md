# Asset provenance & licensing

`LICENSE` (MIT) covers **source code only**. Every bundled asset is listed below
with where it came from and what you may do with it. If an asset is not on this
list, treat it as unlicensed until it is.

Release status is tracked in [`OPEN_SOURCE_CHECKLIST.md`](OPEN_SOURCE_CHECKLIST.md).

> ⚠️ **This repository is not yet cleared for public release.** Every image is
> owned or CC0, but the bundled **audio** is not resolved and the removed
> proprietary art still exists in **git history**. See "Outstanding" below.

## ✅ Images — all owned or CC0

| Path | Files | Source | License |
|---|---|---|---|
| `assets/art/ui/` `hud/` `icons/` | 128 | Procedurally generated — `tools/gen_ui_chrome.py`, `gen_ui_icons.py`, `gen_ui_glyphs.py`, `gen_fx_cards.py` | Project-owned (MIT alongside the code) |
| `assets/art/fx/` | 21 | Procedurally generated — `tools/gen_fx_cards.py` | Project-owned |
| `assets/art/{decor,p2,mil2,cast2}` + 7 top-level | 85 | Procedurally generated — `tools/gen_entities.py` | Project-owned |
| `assets/soldiers/` | 9 | Procedurally generated — `tools/gen_entities.py` | Project-owned |
| Bosses, player tank, desert flora (14 files) | 14 | Generative AI — fal.ai · Replicate · `nano-banana`. Pipeline: `tools/generate_desert_assets.py`, provenance: `assets/art/desert_assets_source.md` | Project-owned (verify each service's output-ownership terms) |
| `assets/ui/intro/` | 2 | Generative AI (intro cinematic key art) | Project-owned |
| `assets/kenney/` | 27 | Kenney game assets | **CC0** — `assets/kenney/LICENSE-CC0.txt` |

Every procedurally generated sprite is reproducible: each generator's `SIZES`
dict is its manifest, and re-running the tool overwrites the PNGs. Original
canvas sizes and `.import` `size_limit`s are preserved so no draw site moves.

**Historical note.** Earlier revisions bundled art from legacy 3D pack/INTERFACE
packs and from a purchased `infantry set` pack. Both are proprietary and
non-redistributable. All of it has been replaced — but see "Outstanding".

## ✅ Fonts

| Path | Source | License |
|---|---|---|
| `assets/fonts/PixelOperator8.ttf` | Jayvee Enaguas (HarvettFox96) | **CC0** — `assets/fonts/LICENSE-CC0.txt` |

## 🔴 Audio — NOT cleared

| Path | Files | Source | Status |
|---|---|---|---|
| `assets/vo/cmd/` | 56 mp3 | speech synthesis TTS — commander barks + intro narration | 🔴 **blocked** |
| `assets/audio/{enemy_death,enemy_spawn,ya_chants}/` | 118 mp3 | speech synthesis TTS, stock voices (see each folder's `README.md`) | 🔴 **unresolved** |

Two separate problems:

1. **`assets/vo/` synthesises an identifiable living public figure**
   (`src/view/sfx.gd` describes the pools as Trump-voiced). That is a
   right-of-publicity question independent of any license, and speech synthesis'
   terms separately prohibit voice clones of real people without consent.
2. **All 174 mp3 are speech synthesis output.** Their terms grant the account holder a
   license to *use* the output. Whether that extends to **sublicensing it onward**
   to everyone who clones a public repo — which is what an MIT/CC0 grant does —
   is a different question and is not settled by having paid for a plan.

Neither is a code problem, and neither can be fixed by regenerating art. Options:
strip the audio, regenerate with a non-impersonating voice under terms that
permit redistribution, or ship the audio as a separate non-MIT asset pack.

## 📋 Non-asset files

| Path | Note |
|---|---|
| `assets/input/actions.vdf`, `assets/steam/*.vdf` | Project-authored Steam config |
| `docs/media/`, `media/` | Screenshots and video **rendered from the game**; they inherit whatever the depicted assets carry. Re-capture after any asset swap. |

## Outstanding before publishing

1. **Audio** — resolve the two problems above.
2. **Git history** — the proprietary art was removed from the working tree but
   remains in every historical commit, recoverable with `git checkout <old-sha>`.
   The folder was renamed `assets/legacy-art/` → `assets/art/`, so a purge must cover
   **both** paths plus `assets/soldiers/`. Working-tree deletion is not enough.
3. **Promo media** — `docs/media/` and `media/` still show the replaced art.
