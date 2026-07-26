# Asset provenance & licensing

`LICENSE` (MIT) covers **source code only**. Every bundled asset is listed below
with where it came from and what you may do with it. If an asset is not on this
list, treat it as unlicensed until it is.

Release status is tracked in [`OPEN_SOURCE_CHECKLIST.md`](OPEN_SOURCE_CHECKLIST.md).

> ⚠️ **One step remains before public release.** Every image is owned or CC0 and
> the audio is cleared — but the removed proprietary art still exists in **git
> history**. See "Outstanding" below.

## ✅ Images — all owned or CC0

| Path | Files | Source | License |
|---|---|---|---|
| `assets/art/ui/` `hud/` `icons/` | 128 | Procedurally generated — `tools/gen_ui_chrome.py`, `gen_ui_icons.py`, `gen_ui_glyphs.py`, `gen_fx_cards.py` | Project-owned (MIT alongside the code) |
| `assets/art/fx/` | 21 | Procedurally generated — `tools/gen_fx_cards.py` | Project-owned |
| `assets/art/{decor,p2,mil2,cast2}` + 7 top-level | 87 | Procedurally generated — `tools/gen_entities.py` | Project-owned |
| `assets/soldiers/` | 9 | Procedurally generated — `tools/gen_entities.py` | Project-owned |
| Bosses, player tank, desert flora (14 files) | 14 | Generative AI — fal.ai · Replicate · `nano-banana`. Pipeline: `tools/generate_desert_assets.py`, provenance: `assets/art/desert_assets_source.md` | Project-owned (verify each service's output-ownership terms) |
| `assets/ui/intro/` | 2 | Generative AI (intro cinematic key art) | Project-owned |
| `assets/kenney/` | 27 | Kenney game assets | **CC0** — `assets/kenney/LICENSE-CC0.txt` |

Every procedurally generated sprite is reproducible: each generator's `SIZES`
dict is its manifest, and re-running the tool overwrites the PNGs. Original
canvas sizes and `.import` `size_limit`s are preserved so no draw site moves.

**Historical note.** Earlier revisions bundled art from legacy 3D pack/INTERFACE
packs and from a purchased `infantry set` pack. Both are proprietary and
non-redistributable. All of it has been replaced — but it survives in git history; see "Outstanding".

## ✅ Fonts

| Path | Source | License |
|---|---|---|
| `assets/fonts/PixelOperator8.ttf` | Jayvee Enaguas (HarvettFox96) | **CC0** — `assets/fonts/LICENSE-CC0.txt` |

## ✅ Audio — speech synthesis redistribution cleared

| Path | Files | Source | Status |
|---|---|---|---|
| `assets/vo/cmd/` | 56 mp3 | speech synthesis TTS — commander barks + intro narration | ✅ cleared with speech synthesis |
| `assets/audio/{enemy_death,enemy_spawn}/` | 88 mp3 | speech synthesis TTS, stock voices (see each folder's `README.md`) | ✅ cleared with speech synthesis |
| `assets/audio/ya_chants/` | 30 mp3 | The **audition reel** the death bank was cast from — 15 voices, `multilingual-v2`, no delivery direction. `enemy_death/` re-cut the 6 approved voices in `synth-v3` with agony tags, so these are source material, not spare content. `.gdignore`d: kept for provenance, **excluded from the build** | ✅ cleared with speech synthesis |

The open question on these 174 files was whether speech synthesis' terms permit
**redistributing** the output onward — an MIT/CC0 grant sublicenses it to
everyone who clones the repo, which is more than a licence to *use* it. The
owner raised this directly with speech synthesis and confirmed it is permitted
(2026-07-24).

> ℹ️ One thing that clearance does not cover, noted for the record rather than
> as a blocker: `assets/vo/` synthesises the voice of an identifiable living
> public figure. Publicity/likeness rights belong to that person, not to
> speech synthesis, so they are not speech synthesis' to grant. The owner has been told and
> it is their call.

## 📋 Non-asset files

| Path | Note |
|---|---|
| `assets/input/actions.vdf`, `assets/steam/*.vdf` | Project-authored Steam config |
| `docs/media/`, `media/` | Screenshots and video **rendered from the game**; they inherit whatever the depicted assets carry. Re-capture after any asset swap. |

## Outstanding before publishing

1. **Git history** — the proprietary art was removed from the working tree but
   remains in every historical commit, recoverable with `git checkout <old-sha>`.
   The folder was renamed `assets/legacy-art/` → `assets/art/`, so a purge must cover
   **both** paths plus `assets/soldiers/`. Working-tree deletion is not enough.
   Run `tools/purge_history.sh` (dry-run first). This is the last blocker.
2. **Promo media** (cosmetic, not a blocker) — `docs/media/` and `media/` still
   show the replaced art and should be re-captured.
