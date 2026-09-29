# Asset provenance & licensing

`LICENSE` (MIT) covers **source code only**. Every bundled asset is listed below
with where it came from and what you may do with it. If an asset is not on this
list, treat it as unlicensed until it is.

This is a provenance inventory, not a blanket clearance statement. Some entries
have incomplete generation or permission records. Historical cleanup statements
do not establish rights to every current asset; see the per-row qualifications
and `docs/steam-store/owner-review.md` before release or redistribution.

## Images — recorded sources and unresolved entries

| Path | Files | Source | License |
|---|---|---|---|
| `assets/art/ui/` `hud/` `icons/` | 105 | Procedurally generated — `tools/gen_ui_chrome.py`, `gen_ui_icons.py`, `gen_ui_glyphs.py`, `gen_fx_cards.py` | Project-owned (MIT alongside the code) |
| `assets/art/ui/title_logo.png` | 1 | Generative AI, **service/model/date unrecorded** | Project-owned **unverified** |
| `assets/art/fx/` | 21 | Procedurally generated — `tools/gen_fx_cards.py` | Project-owned |
| `assets/art/{decor,p2,mil2,cast2}` + 7 top-level | 87 | Procedurally generated — `tools/gen_entities.py` | Project-owned |
| `assets/troops/` — player + five enemy soldiers and action frames | 58 | Generative AI — OpenAI built-in image generation, locally chroma-keyed, sliced and normalized; prompts/provenance in `assets/troops/GENERATED_ASSET_SOURCE.md` | Project-owned (verify service output-ownership terms) |
| `assets/projectiles/` — friendly, piercing, hostile, sniper rounds | 4 | Generative AI — OpenAI built-in image generation, locally chroma-keyed, sliced and normalized; prompts/provenance in `assets/troops/GENERATED_ASSET_SOURCE.md` | Project-owned (verify service output-ownership terms) |
| `assets/troops/` — frogmen + muzzle flash | 3 | Procedurally generated — `tools/gen_entities.py` | Project-owned |
| Desert flora — `cactus_{large,small}`, `scrub`, `decor/{tumbleweed,dry_shrub}`, `p2/cactus_dead1-3` | 8 | Generative AI — OpenRouter `google/gemini-3-pro-image-preview` ("nano-banana"). Pipeline: `tools/generate_desert_assets.py`, provenance: `assets/art/desert_assets_source.md` | Project-owned (verify service output-ownership terms) |
| Vehicles + bosses — `tank_{body,barrel}`, `gunship_{body,barrel}`, `colossus_{body,barrel}` | 6 | Generative AI, **service/model/date unrecorded**. No generator produces these and `desert_assets_source.md` does not cover them — regenerate with a recorded pipeline before relying on the ownership claim | Project-owned **unverified** |
| `assets/ui/intro/` — `keyart.png` (boot-splash key art) + `bigit_sheet.png` | 2 | Generative AI, **service/model/date unrecorded** | Project-owned **unverified**; `keyart.png` also carries the likeness question — see the owner-decision box below |
| `assets/cc0/` | 27 | Kenney game assets | **CC0** — `assets/cc0/LICENSE-CC0.txt` |

Every procedurally generated sprite is reproducible: each generator's `SIZES`
dict is its manifest, and re-running the tool overwrites those PNGs. AI-assisted
sprites carry a separate source note and final prompt. Original canvas sizes and
`.import` `size_limit`s are preserved so no draw site moves.


## ✅ Fonts

| Path | Source | License |
|---|---|---|
| `assets/fonts/PixelOperator8.ttf` | Jayvee Enaguas (HarvettFox96) | **CC0** — `assets/fonts/LICENSE-CC0.txt` |

## Audio — synthesized recordings and provenance status

| Path | Files | Source | Status |
|---|---|---|---|
| `assets/vo/vo_*.mp3` | 14 mp3 | Radio/pilot speech. Voice names recorded in commit `b4f12b6`; ElevenLabs is inferred, not confirmed by an API log | Verify service/account records and terms; role/caption discrepancy remains in the folder README |
| `assets/vo/cmd/` | 41 mp3 | Commander voice clone. Commit `becbc9e4d09e277b2bffe8927c268e9bb22131f8` records fleet VoiceStudio; **not ElevenLabs stock-voice output** | Source/model/permission review required; see historical owner decision below |
| `assets/vo/intro_crawl.mp3` | 1 mp3 | Commit `024ea55` identifies the character voice but not the service; matching commander-bark format does not confirm the pipeline | Generation pipeline and permissions unconfirmed |
| `assets/audio/{enemy_death,enemy_spawn}/` | 88 mp3 | Synthesized speech — ElevenLabs hosted TTS, stock voice roster (see each folder's `README.md`) | ✅ owned (verify service terms) |
| `assets/audio/ya_chants/` | 30 mp3 | The **audition reel** the death bank was cast from — 15 stock voices, ElevenLabs multilingual model (`language_code=ar`), no delivery direction. `enemy_death/` re-cut the 6 approved voices with agony tags, so these are source material, not spare content. `.gdignore`d: kept for provenance, **excluded from the build** | ✅ owned (verify service terms) |

The current inventory is 144 game-intended recordings plus 30 development-only
audition recordings, not 174 shipping voice lines. Confirm the actual uploaded
pack's contents. The audio does not share one verified generation pipeline:
`assets/vo/README.md` distinguishes radio TTS, commander cloning and the
unconfirmed intro. Records under `assets/audio/` infer a hosted TTS service from
voice names and parameters. Commissioning a recording is not evidence that all
permissions or redistribution terms have been verified. The code's MIT license
does not supply missing asset permissions.

September 7 audit note: the historical owner decision below is preserved as a
record of intent, not a verified clearance document. Its grouping of all 56
`assets/vo/` files under one identifiable voice is superseded by the three-group
inventory above and the detailed folder README.

> ### 🎭 Owner decision (2026-07-27): ship it, as satire
>
> The likeness of an identifiable living public figure appears in **two** shipped
> places: `assets/vo/` synthesises that person's voice, and
> `assets/ui/intro/keyart.png` is a painted caricature of that person's face, drawn
> full-canvas on the boot splash every launch (`docs/media/keyart_hero.png` is a
> sibling render of the same art). The `assets/troops/` player sprites were also
> prompted toward the same hair and silhouette — see
> `assets/troops/GENERATED_ASSET_SOURCE.md` — though at 32px they are far less
> recognisable.
>
> **Publicity and likeness rights belong to that person** and are not the project's
> to grant — commissioning the audio and the art ourselves does not change that,
> because it was never a licensing question.
>
> The owner has considered this and **decided to ship**: the work is satire, in a
> game named *Commander in Chief*, and the exposure is knowingly accepted. This is
> recorded as a deliberate call, not an oversight — the alternatives weighed and
> declined were dropping `assets/vo/` and `assets/ui/intro/keyart.png` from the
> build, or re-synthesising the 56 commander barks with an original
> non-identifiable voice.
>
> Redistributors inherit that question. `src/main.gd` guards both loads with
> `ResourceLoader.exists`, so deleting either file is safe — the splash skips the
> missing beat. See [`NOTICE.md`](NOTICE.md).

## 📋 Non-asset files

| Path | Note |
|---|---|
| `assets/input/actions.vdf`, `assets/steam/*.vdf` | Project-authored Steam config |
| `docs/media/`, `media/` | Screenshots and video **rendered from the game**; they inherit whatever the depicted assets carry. Re-capture after any asset swap. Exception: `docs/media/keyart_hero.png` is not a capture — it is a higher-resolution sibling render of `assets/ui/intro/keyart.png` and carries the same likeness question. |

## Reproducing the art

Every procedurally generated sprite is reproducible: each generator's `SIZES`
dict is its manifest, and re-running the tool overwrites those PNGs. Original
canvas sizes and `.import` `size_limit`s are preserved so no draw site moves.
For the six AI-assisted soldier sprites, use the prompt and normalization record
in `assets/troops/GENERATED_ASSET_SOURCE.md`; do not regenerate them through
`tools/gen_entities.py`.
