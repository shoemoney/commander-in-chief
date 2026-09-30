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
| Ground base card — `assets/art/ground/sand_base.png` | 1 | Procedurally generated — `tools/gen_ground.py` (periodic value-noise fBm, isotropic, seamless by construction) | Project-owned (MIT alongside the code) |
| `assets/cc0/` | 26 drawn | Kenney game assets | **CC0** — `assets/cc0/LICENSE-CC0.txt` |

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

<!-- BEGIN generated: assets/cc0_extra (tools/fetch_cc0.py) -->

## `assets/cc0_extra/` — CC0 candidate library (appended 2026-09-29, generated by `tools/fetch_cc0.py`)

**108 files, 1,323,696 bytes** — 99 asset files (1,317,031 bytes) plus 9 licence-text files. Retrieved from CC0 (public domain) sources only and re-derived by `tools/fetch_cc0.py`; run `python3 tools/fetch_cc0.py --check` to verify every hash, every licence attribution and every ground-tile seam. Machine-readable claim set: `assets/cc0_extra/MANIFEST.json`.

> **None of this is wired into the game.** It is a candidate library. The live ground base (`assets/cc0/sand.png`) is untouched, and the ground tiles below are *candidates* — `src/main.gd`'s `_ground_stops()` / `GROUND_SHADE` are load-bearing across four test files and are being changed by another workstream. Integration is a separate, explicit decision.

**Sources are CC0 and nothing else.** No CraftPix material is present or permitted: its licence bars redistributing source files (§1.1.3) and bars AI use (§3.1), and this repository is public. See [`assets/cc0_extra/QUARANTINED.md`](assets/cc0_extra/QUARANTINED.md) for the two OpenGameArt archives excluded for want of a licence file, and for the CraftPix citation.

### Licence verification — what was actually read

| Source | Licence | Verified how |
|---|---|---|
| Crosshair Pack (1.1) | CC0 1.0 — Kenney `Crosshair Pack (1.1)` `License.txt`: “License: (Creative Commons Zero, CC0) / http://creativecommons.org/publicdomain/zero/1.0/” | `License.txt` read **out of** `kenney_crosshair-pack.zip` at fetch time; the run aborts if the markers are absent. Verbatim copy: `assets/cc0_extra/licenses/source-licence-crosshair.txt` |
| UI Pack (2.0) | CC0 1.0 — Kenney `UI Pack (2.0)` `License.txt`: “License: (Creative Commons Zero, CC0) / http://creativecommons.org/publicdomain/zero/1.0/” | `License.txt` read **out of** `kenney_ui-pack.zip` at fetch time; the run aborts if the markers are absent. Verbatim copy: `assets/cc0_extra/licenses/source-licence-ui.txt` |
| Tower Defense (top-down) Pack | CC0 1.0 — Kenney `Tower Defense (top-down) Pack` `License.txt`: “License (Creative Commons Zero, CC0) / http://creativecommons.org/publicdomain/zero/1.0/” | `License.txt` read **out of** `kenney_tower-defense-top-down.zip` at fetch time; the run aborts if the markers are absent. Verbatim copy: `assets/cc0_extra/licenses/source-licence-td_ground.txt` |
| UI SFX Set | CC0 1.0 — Kenney `UI SFX Set` `License.txt`: “License (Creative Commons Zero, CC0) / http://creativecommons.org/publicdomain/zero/1.0/” | `License.txt` read **out of** `kenney_ui-audio.zip` at fetch time; the run aborts if the markers are absent. Verbatim copy: `assets/cc0_extra/licenses/source-licence-sfx_ui.txt` |
| Impact Sounds (1.0) | CC0 1.0 — Kenney `Impact Sounds (1.0)` `License.txt`: “License: (Creative Commons Zero, CC0) / http://creativecommons.org/publicdomain/zero/1.0/” | `License.txt` read **out of** `impact.zip` at fetch time; the run aborts if the markers are absent. Verbatim copy: `assets/cc0_extra/licenses/source-licence-sfx_impact.txt` |
| Sci-Fi Sounds (1.0) | CC0 1.0 — Kenney `Sci-Fi Sounds (1.0)` `License.txt`: “License: (Creative Commons Zero, CC0) / http://creativecommons.org/publicdomain/zero/1.0/” | `License.txt` read **out of** `sci-fi.zip` at fetch time; the run aborts if the markers are absent. Verbatim copy: `assets/cc0_extra/licenses/source-licence-sfx_scifi.txt` |
| RailGun_Fire1 (freesound) | CC0 1.0 — author's own sidecar `railgun-LICENSE.txt`: “RailGun_Fire1 by BaggoNotes, Creative Commons Zero (CC0). Source page: https://freesound.org/people/BaggoNotes/sounds/785380/ . License verified September 28, 2026: https://creativecommons.org/publicdomain/zero/1.0/” | author's own sidecar, verbatim copy at `assets/cc0_extra/licenses/source-licence-railgun.txt` |
| ambientCG (6 ground materials) | CC0 1.0 — ambientCG licensing FAQ: “All assets are released under the Creative Commons CC0 license, making them free to use without attribution - even in commercial circumstances.” | scraped from the live <https://ambientcg.com/index.php?language=en> on every run; the run aborts if the statement is not present |

Deed: <https://creativecommons.org/publicdomain/zero/1.0/> · Legal code: <https://creativecommons.org/publicdomain/zero/1.0/legalcode>. Attribution is not required by either licence; Kenney and BaggoNotes are credited here anyway.

### Reticles — Kenney Crosshair Pack (1.1)

| Path | What it is | Bytes | Source | Licence | Retrieved |
|---|---|---:|---|---|---|
| `assets/cc0_extra/crosshair/crosshair-006.png` | 128-ish reticle frame — circular reticle with four quadrant ticks | 1,003 | https://kenney.nl/assets/crosshair-pack | Kenney `Crosshair Pack (1.1)` `License.txt`: “License: (Creative Commons Zero, CC0) / http://creativecommons.org/publicdomain/zero/1.0/” | 2026-09-29 |
| `assets/cc0_extra/crosshair/crosshair-009.png` | 128-ish reticle frame — double-ring reticle, crosshair through a centre dot | 1,198 | https://kenney.nl/assets/crosshair-pack | Kenney `Crosshair Pack (1.1)` `License.txt`: “License: (Creative Commons Zero, CC0) / http://creativecommons.org/publicdomain/zero/1.0/” | 2026-09-29 |
| `assets/cc0_extra/crosshair/crosshair-026.png` | 128-ish reticle frame — clean circle-and-cross reticle, open centre | 1,003 | https://kenney.nl/assets/crosshair-pack | Kenney `Crosshair Pack (1.1)` `License.txt`: “License: (Creative Commons Zero, CC0) / http://creativecommons.org/publicdomain/zero/1.0/” | 2026-09-29 |
| `assets/cc0_extra/crosshair/crosshair-033.png` | 128-ish reticle frame — circle with opposing arc brackets (aim-lock framing) | 1,281 | https://kenney.nl/assets/crosshair-pack | Kenney `Crosshair Pack (1.1)` `License.txt`: “License: (Creative Commons Zero, CC0) / http://creativecommons.org/publicdomain/zero/1.0/” | 2026-09-29 |
| `assets/cc0_extra/crosshair/crosshair-038.png` | 128-ish reticle frame — four angled ticks, open centre (hit-marker silhouette) | 470 | https://kenney.nl/assets/crosshair-pack | Kenney `Crosshair Pack (1.1)` `License.txt`: “License: (Creative Commons Zero, CC0) / http://creativecommons.org/publicdomain/zero/1.0/” | 2026-09-29 |
| `assets/cc0_extra/crosshair/crosshair-046.png` | 128-ish reticle frame — minimal circle with four short ticks | 983 | https://kenney.nl/assets/crosshair-pack | Kenney `Crosshair Pack (1.1)` `License.txt`: “License: (Creative Commons Zero, CC0) / http://creativecommons.org/publicdomain/zero/1.0/” | 2026-09-29 |
| `assets/cc0_extra/crosshair/crosshair-066.png` | 128-ish reticle frame — circle-and-cross reticle, longer horizontal axis | 1,005 | https://kenney.nl/assets/crosshair-pack | Kenney `Crosshair Pack (1.1)` `License.txt`: “License: (Creative Commons Zero, CC0) / http://creativecommons.org/publicdomain/zero/1.0/” | 2026-09-29 |
| `assets/cc0_extra/crosshair/crosshair-080.png` | 128-ish reticle frame — open square bracket, full frame | 360 | https://kenney.nl/assets/crosshair-pack | Kenney `Crosshair Pack (1.1)` `License.txt`: “License: (Creative Commons Zero, CC0) / http://creativecommons.org/publicdomain/zero/1.0/” | 2026-09-29 |
| `assets/cc0_extra/crosshair/crosshair-081.png` | 128-ish reticle frame — open square bracket, heavy corner ticks | 360 | https://kenney.nl/assets/crosshair-pack | Kenney `Crosshair Pack (1.1)` `License.txt`: “License: (Creative Commons Zero, CC0) / http://creativecommons.org/publicdomain/zero/1.0/” | 2026-09-29 |
| `assets/cc0_extra/crosshair/crosshair-082.png` | 128-ish reticle frame — open square bracket with a centre plus | 395 | https://kenney.nl/assets/crosshair-pack | Kenney `Crosshair Pack (1.1)` `License.txt`: “License: (Creative Commons Zero, CC0) / http://creativecommons.org/publicdomain/zero/1.0/” | 2026-09-29 |
| `assets/cc0_extra/crosshair/crosshair-092.png` | 128-ish reticle frame — plain thin circle (minimal scope ring) | 798 | https://kenney.nl/assets/crosshair-pack | Kenney `Crosshair Pack (1.1)` `License.txt`: “License: (Creative Commons Zero, CC0) / http://creativecommons.org/publicdomain/zero/1.0/” | 2026-09-29 |
| `assets/cc0_extra/crosshair/crosshair-100.png` | 128-ish reticle frame — tactical corner-bracket reticle with a centre square | 450 | https://kenney.nl/assets/crosshair-pack | Kenney `Crosshair Pack (1.1)` `License.txt`: “License: (Creative Commons Zero, CC0) / http://creativecommons.org/publicdomain/zero/1.0/” | 2026-09-29 |
| `assets/cc0_extra/crosshair/crosshair-102.png` | 128-ish reticle frame — closed square bracket with a centre cross | 421 | https://kenney.nl/assets/crosshair-pack | Kenney `Crosshair Pack (1.1)` `License.txt`: “License: (Creative Commons Zero, CC0) / http://creativecommons.org/publicdomain/zero/1.0/” | 2026-09-29 |
| `assets/cc0_extra/crosshair/crosshair-105.png` | 128-ish reticle frame — square bracket with a centre ring | 671 | https://kenney.nl/assets/crosshair-pack | Kenney `Crosshair Pack (1.1)` `License.txt`: “License: (Creative Commons Zero, CC0) / http://creativecommons.org/publicdomain/zero/1.0/” | 2026-09-29 |
| `assets/cc0_extra/crosshair/crosshair-134.png` | 128-ish reticle frame — gapped crosshair, four detached ticks | 221 | https://kenney.nl/assets/crosshair-pack | Kenney `Crosshair Pack (1.1)` `License.txt`: “License: (Creative Commons Zero, CC0) / http://creativecommons.org/publicdomain/zero/1.0/” | 2026-09-29 |
| `assets/cc0_extra/crosshair/crosshair-146.png` | 128-ish reticle frame — X-shaped reticle, four diagonal ticks | 471 | https://kenney.nl/assets/crosshair-pack | Kenney `Crosshair Pack (1.1)` `License.txt`: “License: (Creative Commons Zero, CC0) / http://creativecommons.org/publicdomain/zero/1.0/” | 2026-09-29 |

### UI frames and glyphs — Kenney UI Pack (2.0)

| Path | What it is | Bytes | Source | Licence | Retrieved |
|---|---|---:|---|---|---|
| `assets/cc0_extra/ui/button_rectangle_depth_border.png` | UI frame/glyph — rectangular button frame, bevelled depth + border | 408 | https://kenney.nl/assets/ui-pack | Kenney `UI Pack (2.0)` `License.txt`: “License: (Creative Commons Zero, CC0) / http://creativecommons.org/publicdomain/zero/1.0/” | 2026-09-29 |
| `assets/cc0_extra/ui/button_rectangle_line.png` | UI frame/glyph — rectangular button frame, hairline | 335 | https://kenney.nl/assets/ui-pack | Kenney `UI Pack (2.0)` `License.txt`: “License: (Creative Commons Zero, CC0) / http://creativecommons.org/publicdomain/zero/1.0/” | 2026-09-29 |
| `assets/cc0_extra/ui/button_round_depth_border.png` | UI frame/glyph — round button frame, bevelled depth + border | 1,580 | https://kenney.nl/assets/ui-pack | Kenney `UI Pack (2.0)` `License.txt`: “License: (Creative Commons Zero, CC0) / http://creativecommons.org/publicdomain/zero/1.0/” | 2026-09-29 |
| `assets/cc0_extra/ui/button_square_depth_border.png` | UI frame/glyph — square button frame, bevelled depth + border | 373 | https://kenney.nl/assets/ui-pack | Kenney `UI Pack (2.0)` `License.txt`: “License: (Creative Commons Zero, CC0) / http://creativecommons.org/publicdomain/zero/1.0/” | 2026-09-29 |
| `assets/cc0_extra/ui/check_round_grey.png` | UI frame/glyph — unchecked circle, grey | 579 | https://kenney.nl/assets/ui-pack | Kenney `UI Pack (2.0)` `License.txt`: “License: (Creative Commons Zero, CC0) / http://creativecommons.org/publicdomain/zero/1.0/” | 2026-09-29 |
| `assets/cc0_extra/ui/check_square_grey.png` | UI frame/glyph — unchecked box, grey | 280 | https://kenney.nl/assets/ui-pack | Kenney `UI Pack (2.0)` `License.txt`: “License: (Creative Commons Zero, CC0) / http://creativecommons.org/publicdomain/zero/1.0/” | 2026-09-29 |
| `assets/cc0_extra/ui/check_square_grey_checkmark.png` | UI frame/glyph — checked box with a tick, grey | 556 | https://kenney.nl/assets/ui-pack | Kenney `UI Pack (2.0)` `License.txt`: “License: (Creative Commons Zero, CC0) / http://creativecommons.org/publicdomain/zero/1.0/” | 2026-09-29 |
| `assets/cc0_extra/ui/divider.png` | UI frame/glyph — thin horizontal rule | 89 | https://kenney.nl/assets/ui-pack | Kenney `UI Pack (2.0)` `License.txt`: “License: (Creative Commons Zero, CC0) / http://creativecommons.org/publicdomain/zero/1.0/” | 2026-09-29 |
| `assets/cc0_extra/ui/divider_edges.png` | UI frame/glyph — horizontal rule with capped ends | 121 | https://kenney.nl/assets/ui-pack | Kenney `UI Pack (2.0)` `License.txt`: “License: (Creative Commons Zero, CC0) / http://creativecommons.org/publicdomain/zero/1.0/” | 2026-09-29 |
| `assets/cc0_extra/ui/icon_outline_checkmark.png` | UI frame/glyph — outlined tick glyph | 377 | https://kenney.nl/assets/ui-pack | Kenney `UI Pack (2.0)` `License.txt`: “License: (Creative Commons Zero, CC0) / http://creativecommons.org/publicdomain/zero/1.0/” | 2026-09-29 |
| `assets/cc0_extra/ui/icon_outline_circle.png` | UI frame/glyph — outlined circle glyph | 313 | https://kenney.nl/assets/ui-pack | Kenney `UI Pack (2.0)` `License.txt`: “License: (Creative Commons Zero, CC0) / http://creativecommons.org/publicdomain/zero/1.0/” | 2026-09-29 |
| `assets/cc0_extra/ui/icon_outline_cross.png` | UI frame/glyph — outlined cross glyph | 350 | https://kenney.nl/assets/ui-pack | Kenney `UI Pack (2.0)` `License.txt`: “License: (Creative Commons Zero, CC0) / http://creativecommons.org/publicdomain/zero/1.0/” | 2026-09-29 |
| `assets/cc0_extra/ui/icon_outline_square.png` | UI frame/glyph — outlined square glyph | 135 | https://kenney.nl/assets/ui-pack | Kenney `UI Pack (2.0)` `License.txt`: “License: (Creative Commons Zero, CC0) / http://creativecommons.org/publicdomain/zero/1.0/” | 2026-09-29 |
| `assets/cc0_extra/ui/input_outline_rectangle.png` | UI frame/glyph — text-field plate, outline only | 344 | https://kenney.nl/assets/ui-pack | Kenney `UI Pack (2.0)` `License.txt`: “License: (Creative Commons Zero, CC0) / http://creativecommons.org/publicdomain/zero/1.0/” | 2026-09-29 |
| `assets/cc0_extra/ui/input_outline_square.png` | UI frame/glyph — square text-field plate, outline only | 316 | https://kenney.nl/assets/ui-pack | Kenney `UI Pack (2.0)` `License.txt`: “License: (Creative Commons Zero, CC0) / http://creativecommons.org/publicdomain/zero/1.0/” | 2026-09-29 |
| `assets/cc0_extra/ui/input_rectangle.png` | UI frame/glyph — text-field plate (filled interior, no border) | 355 | https://kenney.nl/assets/ui-pack | Kenney `UI Pack (2.0)` `License.txt`: “License: (Creative Commons Zero, CC0) / http://creativecommons.org/publicdomain/zero/1.0/” | 2026-09-29 |
| `assets/cc0_extra/ui/input_square.png` | UI frame/glyph — square text-field plate (filled interior, no border) | 319 | https://kenney.nl/assets/ui-pack | Kenney `UI Pack (2.0)` `License.txt`: “License: (Creative Commons Zero, CC0) / http://creativecommons.org/publicdomain/zero/1.0/” | 2026-09-29 |
| `assets/cc0_extra/ui/slide_horizontal_grey.png` | UI frame/glyph — horizontal bar trough (grey, desaturated) | 383 | https://kenney.nl/assets/ui-pack | Kenney `UI Pack (2.0)` `License.txt`: “License: (Creative Commons Zero, CC0) / http://creativecommons.org/publicdomain/zero/1.0/” | 2026-09-29 |
| `assets/cc0_extra/ui/slide_horizontal_grey_section.png` | UI frame/glyph — horizontal bar fill segment | 321 | https://kenney.nl/assets/ui-pack | Kenney `UI Pack (2.0)` `License.txt`: “License: (Creative Commons Zero, CC0) / http://creativecommons.org/publicdomain/zero/1.0/” | 2026-09-29 |
| `assets/cc0_extra/ui/slide_horizontal_grey_section_wide.png` | UI frame/glyph — horizontal bar fill segment, wide variant | 336 | https://kenney.nl/assets/ui-pack | Kenney `UI Pack (2.0)` `License.txt`: “License: (Creative Commons Zero, CC0) / http://creativecommons.org/publicdomain/zero/1.0/” | 2026-09-29 |
| `assets/cc0_extra/ui/slide_vertical_grey.png` | UI frame/glyph — vertical bar trough (grey, desaturated) | 379 | https://kenney.nl/assets/ui-pack | Kenney `UI Pack (2.0)` `License.txt`: “License: (Creative Commons Zero, CC0) / http://creativecommons.org/publicdomain/zero/1.0/” | 2026-09-29 |

### Top-down ground tiles — Kenney Tower Defense (top-down) Pack

| Path | What it is | Bytes | Source | Licence | Retrieved |
|---|---|---:|---|---|---|
| `assets/cc0_extra/td_ground/dirt_emplacement_065.png` | top-down ground tile — dirt pad with a faint studded outline | 2,840 | https://kenney.nl/assets/tower-defense-top-down | Kenney `Tower Defense (top-down) Pack` `License.txt`: “License (Creative Commons Zero, CC0) / http://creativecommons.org/publicdomain/zero/1.0/” | 2026-09-29 |
| `assets/cc0_extra/td_ground/dirt_emplacement_cross_067.png` | top-down ground tile — dirt pad with an inlaid X mark | 3,030 | https://kenney.nl/assets/tower-defense-top-down | Kenney `Tower Defense (top-down) Pack` `License.txt`: “License (Creative Commons Zero, CC0) / http://creativecommons.org/publicdomain/zero/1.0/” | 2026-09-29 |
| `assets/cc0_extra/td_ground/dirt_emplacement_target_068.png` | top-down ground tile — dirt pad with an inlaid target mark | 3,334 | https://kenney.nl/assets/tower-defense-top-down | Kenney `Tower Defense (top-down) Pack` `License.txt`: “License (Creative Commons Zero, CC0) / http://creativecommons.org/publicdomain/zero/1.0/” | 2026-09-29 |
| `assets/cc0_extra/td_ground/dirt_emplacement_wrench_066.png` | top-down ground tile — dirt pad with an inlaid wrench mark | 3,233 | https://kenney.nl/assets/tower-defense-top-down | Kenney `Tower Defense (top-down) Pack` `License.txt`: “License (Creative Commons Zero, CC0) / http://creativecommons.org/publicdomain/zero/1.0/” | 2026-09-29 |
| `assets/cc0_extra/td_ground/dirt_flat_005.png` | top-down ground tile — flat brown dirt fill (no grass/water edge) | 1,495 | https://kenney.nl/assets/tower-defense-top-down | Kenney `Tower Defense (top-down) Pack` `License.txt`: “License (Creative Commons Zero, CC0) / http://creativecommons.org/publicdomain/zero/1.0/” | 2026-09-29 |
| `assets/cc0_extra/td_ground/dirt_flat_047.png` | top-down ground tile — flat brown dirt fill, straight edge | 2,251 | https://kenney.nl/assets/tower-defense-top-down | Kenney `Tower Defense (top-down) Pack` `License.txt`: “License (Creative Commons Zero, CC0) / http://creativecommons.org/publicdomain/zero/1.0/” | 2026-09-29 |
| `assets/cc0_extra/td_ground/dirt_flat_055.png` | top-down ground tile — flat brown dirt fill, straight edge | 1,056 | https://kenney.nl/assets/tower-defense-top-down | Kenney `Tower Defense (top-down) Pack` `License.txt`: “License (Creative Commons Zero, CC0) / http://creativecommons.org/publicdomain/zero/1.0/” | 2026-09-29 |
| `assets/cc0_extra/td_ground/dirt_flat_060.png` | top-down ground tile — flat brown dirt fill, straight edge | 1,056 | https://kenney.nl/assets/tower-defense-top-down | Kenney `Tower Defense (top-down) Pack` `License.txt`: “License (Creative Commons Zero, CC0) / http://creativecommons.org/publicdomain/zero/1.0/” | 2026-09-29 |
| `assets/cc0_extra/td_ground/dirt_stone_092.png` | top-down ground tile — brown dirt with stone speckle | 2,405 | https://kenney.nl/assets/tower-defense-top-down | Kenney `Tower Defense (top-down) Pack` `License.txt`: “License (Creative Commons Zero, CC0) / http://creativecommons.org/publicdomain/zero/1.0/” | 2026-09-29 |
| `assets/cc0_extra/td_ground/dirt_stone_097.png` | top-down ground tile — brown dirt with stone speckle, straighter edge | 2,535 | https://kenney.nl/assets/tower-defense-top-down | Kenney `Tower Defense (top-down) Pack` `License.txt`: “License (Creative Commons Zero, CC0) / http://creativecommons.org/publicdomain/zero/1.0/” | 2026-09-29 |
| `assets/cc0_extra/td_ground/dirt_stone_150.png` | top-down ground tile — brown dirt with stone speckle | 1,614 | https://kenney.nl/assets/tower-defense-top-down | Kenney `Tower Defense (top-down) Pack` `License.txt`: “License (Creative Commons Zero, CC0) / http://creativecommons.org/publicdomain/zero/1.0/” | 2026-09-29 |
| `assets/cc0_extra/td_ground/dirt_stone_158.png` | top-down ground tile — brown dirt with stone speckle, heavier grit | 3,065 | https://kenney.nl/assets/tower-defense-top-down | Kenney `Tower Defense (top-down) Pack` `License.txt`: “License (Creative Commons Zero, CC0) / http://creativecommons.org/publicdomain/zero/1.0/” | 2026-09-29 |
| `assets/cc0_extra/td_ground/sand_dirt_edge_144.png` | top-down ground tile — tan sand meeting a brown dirt patch | 2,179 | https://kenney.nl/assets/tower-defense-top-down | Kenney `Tower Defense (top-down) Pack` `License.txt`: “License (Creative Commons Zero, CC0) / http://creativecommons.org/publicdomain/zero/1.0/” | 2026-09-29 |
| `assets/cc0_extra/td_ground/sand_dirt_edge_146.png` | top-down ground tile — tan sand meeting a brown dirt patch | 3,095 | https://kenney.nl/assets/tower-defense-top-down | Kenney `Tower Defense (top-down) Pack` `License.txt`: “License (Creative Commons Zero, CC0) / http://creativecommons.org/publicdomain/zero/1.0/” | 2026-09-29 |
| `assets/cc0_extra/td_ground/sand_dirt_edge_147.png` | top-down ground tile — tan sand meeting a brown dirt patch | 3,402 | https://kenney.nl/assets/tower-defense-top-down | Kenney `Tower Defense (top-down) Pack` `License.txt`: “License (Creative Commons Zero, CC0) / http://creativecommons.org/publicdomain/zero/1.0/” | 2026-09-29 |

### UI sound — Kenney UI SFX Set

| Path | What it is | Bytes | Source | Licence | Retrieved |
|---|---|---:|---|---|---|
| `assets/cc0_extra/sfx_ui/click1.ogg` | UI sound — UI click, variant 1 | 4,983 | https://kenney.nl/assets/ui-audio | Kenney `UI SFX Set` `License.txt`: “License (Creative Commons Zero, CC0) / http://creativecommons.org/publicdomain/zero/1.0/” | 2026-09-29 |
| `assets/cc0_extra/sfx_ui/click2.ogg` | UI sound — UI click, variant 2 | 4,656 | https://kenney.nl/assets/ui-audio | Kenney `UI SFX Set` `License.txt`: “License (Creative Commons Zero, CC0) / http://creativecommons.org/publicdomain/zero/1.0/” | 2026-09-29 |
| `assets/cc0_extra/sfx_ui/click3.ogg` | UI sound — UI click, variant 3 | 4,880 | https://kenney.nl/assets/ui-audio | Kenney `UI SFX Set` `License.txt`: “License (Creative Commons Zero, CC0) / http://creativecommons.org/publicdomain/zero/1.0/” | 2026-09-29 |
| `assets/cc0_extra/sfx_ui/click5.ogg` | UI sound — UI click, variant 5 | 4,532 | https://kenney.nl/assets/ui-audio | Kenney `UI SFX Set` `License.txt`: “License (Creative Commons Zero, CC0) / http://creativecommons.org/publicdomain/zero/1.0/” | 2026-09-29 |
| `assets/cc0_extra/sfx_ui/mouseclick1.ogg` | UI sound — mouse-button click | 4,686 | https://kenney.nl/assets/ui-audio | Kenney `UI SFX Set` `License.txt`: “License (Creative Commons Zero, CC0) / http://creativecommons.org/publicdomain/zero/1.0/” | 2026-09-29 |
| `assets/cc0_extra/sfx_ui/rollover3.ogg` | UI sound — menu hover tick | 4,778 | https://kenney.nl/assets/ui-audio | Kenney `UI SFX Set` `License.txt`: “License (Creative Commons Zero, CC0) / http://creativecommons.org/publicdomain/zero/1.0/” | 2026-09-29 |
| `assets/cc0_extra/sfx_ui/switch1.ogg` | UI sound — toggle/switch on-off, variant 1 | 6,104 | https://kenney.nl/assets/ui-audio | Kenney `UI SFX Set` `License.txt`: “License (Creative Commons Zero, CC0) / http://creativecommons.org/publicdomain/zero/1.0/” | 2026-09-29 |
| `assets/cc0_extra/sfx_ui/switch10.ogg` | UI sound — toggle/switch on-off, variant 10 | 6,456 | https://kenney.nl/assets/ui-audio | Kenney `UI SFX Set` `License.txt`: “License (Creative Commons Zero, CC0) / http://creativecommons.org/publicdomain/zero/1.0/” | 2026-09-29 |
| `assets/cc0_extra/sfx_ui/switch17.ogg` | UI sound — toggle/switch on-off, variant 17 | 6,686 | https://kenney.nl/assets/ui-audio | Kenney `UI SFX Set` `License.txt`: “License (Creative Commons Zero, CC0) / http://creativecommons.org/publicdomain/zero/1.0/” | 2026-09-29 |
| `assets/cc0_extra/sfx_ui/switch25.ogg` | UI sound — toggle/switch on-off, variant 25 | 7,130 | https://kenney.nl/assets/ui-audio | Kenney `UI SFX Set` `License.txt`: “License (Creative Commons Zero, CC0) / http://creativecommons.org/publicdomain/zero/1.0/” | 2026-09-29 |
| `assets/cc0_extra/sfx_ui/switch5.ogg` | UI sound — toggle/switch on-off, variant 5 | 6,181 | https://kenney.nl/assets/ui-audio | Kenney `UI SFX Set` `License.txt`: “License (Creative Commons Zero, CC0) / http://creativecommons.org/publicdomain/zero/1.0/” | 2026-09-29 |

### Impact sound — Kenney Impact Sounds (1.0)

| Path | What it is | Bytes | Source | Licence | Retrieved |
|---|---|---:|---|---|---|
| `assets/cc0_extra/sfx_impact/footstep_concrete_000.ogg` | impact sound — footstep on concrete | 5,808 | https://kenney.nl/assets/impact-sounds | Kenney `Impact Sounds (1.0)` `License.txt`: “License: (Creative Commons Zero, CC0) / http://creativecommons.org/publicdomain/zero/1.0/” | 2026-09-29 |
| `assets/cc0_extra/sfx_impact/impactBell_heavy_000.ogg` | impact sound — heavy bell/metal-body impact | 13,915 | https://kenney.nl/assets/impact-sounds | Kenney `Impact Sounds (1.0)` `License.txt`: “License: (Creative Commons Zero, CC0) / http://creativecommons.org/publicdomain/zero/1.0/” | 2026-09-29 |
| `assets/cc0_extra/sfx_impact/impactGlass_heavy_000.ogg` | impact sound — heavy glass shatter | 7,403 | https://kenney.nl/assets/impact-sounds | Kenney `Impact Sounds (1.0)` `License.txt`: “License: (Creative Commons Zero, CC0) / http://creativecommons.org/publicdomain/zero/1.0/” | 2026-09-29 |
| `assets/cc0_extra/sfx_impact/impactMetal_medium_000.ogg` | impact sound — medium metal impact, variant 0 | 7,117 | https://kenney.nl/assets/impact-sounds | Kenney `Impact Sounds (1.0)` `License.txt`: “License: (Creative Commons Zero, CC0) / http://creativecommons.org/publicdomain/zero/1.0/” | 2026-09-29 |
| `assets/cc0_extra/sfx_impact/impactMetal_medium_002.ogg` | impact sound — medium metal impact, variant 2 | 5,857 | https://kenney.nl/assets/impact-sounds | Kenney `Impact Sounds (1.0)` `License.txt`: “License: (Creative Commons Zero, CC0) / http://creativecommons.org/publicdomain/zero/1.0/” | 2026-09-29 |
| `assets/cc0_extra/sfx_impact/impactMining_000.ogg` | impact sound — pick-strike / mining impact | 12,035 | https://kenney.nl/assets/impact-sounds | Kenney `Impact Sounds (1.0)` `License.txt`: “License: (Creative Commons Zero, CC0) / http://creativecommons.org/publicdomain/zero/1.0/” | 2026-09-29 |
| `assets/cc0_extra/sfx_impact/impactPlate_heavy_000.ogg` | impact sound — heavy steel-plate impact | 10,032 | https://kenney.nl/assets/impact-sounds | Kenney `Impact Sounds (1.0)` `License.txt`: “License: (Creative Commons Zero, CC0) / http://creativecommons.org/publicdomain/zero/1.0/” | 2026-09-29 |
| `assets/cc0_extra/sfx_impact/impactPlate_medium_000.ogg` | impact sound — medium steel-plate impact | 10,921 | https://kenney.nl/assets/impact-sounds | Kenney `Impact Sounds (1.0)` `License.txt`: “License: (Creative Commons Zero, CC0) / http://creativecommons.org/publicdomain/zero/1.0/” | 2026-09-29 |
| `assets/cc0_extra/sfx_impact/impactPunch_heavy_000.ogg` | impact sound — heavy punch/body hit | 11,617 | https://kenney.nl/assets/impact-sounds | Kenney `Impact Sounds (1.0)` `License.txt`: “License: (Creative Commons Zero, CC0) / http://creativecommons.org/publicdomain/zero/1.0/” | 2026-09-29 |
| `assets/cc0_extra/sfx_impact/impactSoft_heavy_000.ogg` | impact sound — heavy soft-body thud (flesh/padding) | 6,570 | https://kenney.nl/assets/impact-sounds | Kenney `Impact Sounds (1.0)` `License.txt`: “License: (Creative Commons Zero, CC0) / http://creativecommons.org/publicdomain/zero/1.0/” | 2026-09-29 |
| `assets/cc0_extra/sfx_impact/impactTin_medium_000.ogg` | impact sound — medium tin/can impact | 6,509 | https://kenney.nl/assets/impact-sounds | Kenney `Impact Sounds (1.0)` `License.txt`: “License: (Creative Commons Zero, CC0) / http://creativecommons.org/publicdomain/zero/1.0/” | 2026-09-29 |
| `assets/cc0_extra/sfx_impact/impactWood_heavy_000.ogg` | impact sound — heavy wood knock | 6,233 | https://kenney.nl/assets/impact-sounds | Kenney `Impact Sounds (1.0)` `License.txt`: “License: (Creative Commons Zero, CC0) / http://creativecommons.org/publicdomain/zero/1.0/” | 2026-09-29 |

### Sci-fi sound — Kenney Sci-Fi Sounds (1.0)

| Path | What it is | Bytes | Source | Licence | Retrieved |
|---|---|---:|---|---|---|
| `assets/cc0_extra/sfx_scifi/computerNoise_000.ogg` | sci-fi sound — computer/console noise bed | 119,024 | https://kenney.nl/assets/sci-fi-sounds | Kenney `Sci-Fi Sounds (1.0)` `License.txt`: “License: (Creative Commons Zero, CC0) / http://creativecommons.org/publicdomain/zero/1.0/” | 2026-09-29 |
| `assets/cc0_extra/sfx_scifi/engineCircular_000.ogg` | sci-fi sound — circular engine loop | 177,470 | https://kenney.nl/assets/sci-fi-sounds | Kenney `Sci-Fi Sounds (1.0)` `License.txt`: “License: (Creative Commons Zero, CC0) / http://creativecommons.org/publicdomain/zero/1.0/” | 2026-09-29 |
| `assets/cc0_extra/sfx_scifi/explosionCrunch_000.ogg` | sci-fi sound — crunchy explosion, variant 0 | 28,274 | https://kenney.nl/assets/sci-fi-sounds | Kenney `Sci-Fi Sounds (1.0)` `License.txt`: “License: (Creative Commons Zero, CC0) / http://creativecommons.org/publicdomain/zero/1.0/” | 2026-09-29 |
| `assets/cc0_extra/sfx_scifi/explosionCrunch_003.ogg` | sci-fi sound — crunchy explosion, variant 3 | 54,824 | https://kenney.nl/assets/sci-fi-sounds | Kenney `Sci-Fi Sounds (1.0)` `License.txt`: “License: (Creative Commons Zero, CC0) / http://creativecommons.org/publicdomain/zero/1.0/” | 2026-09-29 |
| `assets/cc0_extra/sfx_scifi/forceField_000.ogg` | sci-fi sound — force-field shimmer | 25,672 | https://kenney.nl/assets/sci-fi-sounds | Kenney `Sci-Fi Sounds (1.0)` `License.txt`: “License: (Creative Commons Zero, CC0) / http://creativecommons.org/publicdomain/zero/1.0/” | 2026-09-29 |
| `assets/cc0_extra/sfx_scifi/impactMetal_000.ogg` | sci-fi sound — sci-fi metal impact | 15,491 | https://kenney.nl/assets/sci-fi-sounds | Kenney `Sci-Fi Sounds (1.0)` `License.txt`: “License: (Creative Commons Zero, CC0) / http://creativecommons.org/publicdomain/zero/1.0/” | 2026-09-29 |
| `assets/cc0_extra/sfx_scifi/laserLarge_000.ogg` | sci-fi sound — large/heavy laser shot | 25,566 | https://kenney.nl/assets/sci-fi-sounds | Kenney `Sci-Fi Sounds (1.0)` `License.txt`: “License: (Creative Commons Zero, CC0) / http://creativecommons.org/publicdomain/zero/1.0/” | 2026-09-29 |
| `assets/cc0_extra/sfx_scifi/laserRetro_000.ogg` | sci-fi sound — retro synth laser | 12,588 | https://kenney.nl/assets/sci-fi-sounds | Kenney `Sci-Fi Sounds (1.0)` `License.txt`: “License: (Creative Commons Zero, CC0) / http://creativecommons.org/publicdomain/zero/1.0/” | 2026-09-29 |
| `assets/cc0_extra/sfx_scifi/laserSmall_000.ogg` | sci-fi sound — small laser shot, variant 0 | 7,286 | https://kenney.nl/assets/sci-fi-sounds | Kenney `Sci-Fi Sounds (1.0)` `License.txt`: “License: (Creative Commons Zero, CC0) / http://creativecommons.org/publicdomain/zero/1.0/” | 2026-09-29 |
| `assets/cc0_extra/sfx_scifi/laserSmall_003.ogg` | sci-fi sound — small laser shot, variant 3 | 8,179 | https://kenney.nl/assets/sci-fi-sounds | Kenney `Sci-Fi Sounds (1.0)` `License.txt`: “License: (Creative Commons Zero, CC0) / http://creativecommons.org/publicdomain/zero/1.0/” | 2026-09-29 |
| `assets/cc0_extra/sfx_scifi/lowFrequency_explosion_000.ogg` | sci-fi sound — low-frequency explosion boom | 14,317 | https://kenney.nl/assets/sci-fi-sounds | Kenney `Sci-Fi Sounds (1.0)` `License.txt`: “License: (Creative Commons Zero, CC0) / http://creativecommons.org/publicdomain/zero/1.0/” | 2026-09-29 |
| `assets/cc0_extra/sfx_scifi/spaceEngineSmall_000.ogg` | sci-fi sound — small spacecraft engine loop | 116,880 | https://kenney.nl/assets/sci-fi-sounds | Kenney `Sci-Fi Sounds (1.0)` `License.txt`: “License: (Creative Commons Zero, CC0) / http://creativecommons.org/publicdomain/zero/1.0/” | 2026-09-29 |
| `assets/cc0_extra/sfx_scifi/thrusterFire_000.ogg` | sci-fi sound — thruster/rocket ignition | 201,216 | https://kenney.nl/assets/sci-fi-sounds | Kenney `Sci-Fi Sounds (1.0)` `License.txt`: “License: (Creative Commons Zero, CC0) / http://creativecommons.org/publicdomain/zero/1.0/” | 2026-09-29 |

### Railgun — freesound (CC0 by the author)

| Path | What it is | Bytes | Source | Licence | Retrieved |
|---|---|---:|---|---|---|
| `assets/cc0_extra/sfx_railgun/railgun_fire_baggonotes.mp3` | railgun fire, HQ MP3 preview as published by the author | 22,021 | https://freesound.org/people/BaggoNotes/sounds/785380/ | author's own sidecar `railgun-LICENSE.txt`: “RailGun_Fire1 by BaggoNotes, Creative Commons Zero (CC0). Source page: https://freesound.org/people/BaggoNotes/sounds/785380/ . License verified September 28, 2026: https://creativecommons.org/publicdomain/zero/1.0/” | 2026-09-29 |

### Ground material candidates — ambientCG (128x128, seamless)

| Path | What it is | Bytes | Source | Licence | Retrieved |
|---|---|---:|---|---|---|
| `assets/cc0_extra/ground/grass-001-deep-forest-floor.png` | 128x128 seamless ground tile candidate — Grass 001 (deep forest floor); luma mean 0.3084, std 0.0197 | 26,974 | ambientCG `Grass001` — https://ambientcg.com/view?id=Grass001 | ambientCG licensing FAQ: “All assets are released under the Creative Commons CC0 license, making them free to use without attribution - even in commercial circumstances.” | 2026-09-29 |
| `assets/cc0_extra/ground/grass-005-lush-dense-turf.png` | 128x128 seamless ground tile candidate — Grass 005 (lush dense turf); luma mean 0.4423, std 0.0202 | 27,421 | ambientCG `Grass005` — https://ambientcg.com/view?id=Grass005 | ambientCG licensing FAQ: “All assets are released under the Creative Commons CC0 license, making them free to use without attribution - even in commercial circumstances.” | 2026-09-29 |
| `assets/cc0_extra/ground/ground-037-mossy-grass-mix.png` | 128x128 seamless ground tile candidate — Ground 037 (mossy grass mix); luma mean 0.5509, std 0.0308 | 30,932 | ambientCG `Ground037` — https://ambientcg.com/view?id=Ground037 | ambientCG licensing FAQ: “All assets are released under the Creative Commons CC0 license, making them free to use without attribution - even in commercial circumstances.” | 2026-09-29 |
| `assets/cc0_extra/ground/ground-039-scorched-ash.png` | 128x128 seamless ground tile candidate — Ground 039 (scorched ash); luma mean 0.49, std 0.0196 | 26,700 | ambientCG `Ground039` — https://ambientcg.com/view?id=Ground039 | ambientCG licensing FAQ: “All assets are released under the Creative Commons CC0 license, making them free to use without attribution - even in commercial circumstances.” | 2026-09-29 |
| `assets/cc0_extra/ground/ground-062l-warm-tan-sand.png` | 128x128 seamless ground tile candidate — Ground 062 L (warm tan sand); luma mean 0.5627, std 0.0304 | 31,187 | ambientCG `Ground062L` — https://ambientcg.com/view?id=Ground062L | ambientCG licensing FAQ: “All assets are released under the Creative Commons CC0 license, making them free to use without attribution - even in commercial circumstances.” | 2026-09-29 |
| `assets/cc0_extra/ground/ground-062s-gritty-dirt-track.png` | 128x128 seamless ground tile candidate — Ground 062 S (gritty dirt track); luma mean 0.5639, std 0.0403 | 33,604 | ambientCG `Ground062S` — https://ambientcg.com/view?id=Ground062S | ambientCG licensing FAQ: “All assets are released under the Creative Commons CC0 license, making them free to use without attribution - even in commercial circumstances.” | 2026-09-29 |
| `assets/cc0_extra/ground/ground-079l-fine-pale-sand.png` | 128x128 seamless ground tile candidate — Ground 079 L (fine pale sand); luma mean 0.6154, std 0.0223 | 28,326 | ambientCG `Ground079L` — https://ambientcg.com/view?id=Ground079L | ambientCG licensing FAQ: “All assets are released under the Creative Commons CC0 license, making them free to use without attribution - even in commercial circumstances.” | 2026-09-29 |
| `assets/cc0_extra/ground/ground-095a-dry-cracked-earth.png` | 128x128 seamless ground tile candidate — Ground 095 A (dry cracked earth); luma mean 0.4707, std 0.0085 | 15,066 | ambientCG `Ground095A` — https://ambientcg.com/view?id=Ground095A | ambientCG licensing FAQ: “All assets are released under the Creative Commons CC0 license, making them free to use without attribution - even in commercial circumstances.” | 2026-09-29 |
| `assets/cc0_extra/ground/ground-098-dune-ripple-sand.png` | 128x128 seamless ground tile candidate — Ground 098 (dune-ripple sand); luma mean 0.6429, std 0.0088 | 14,111 | ambientCG `Ground098` — https://ambientcg.com/view?id=Ground098 | ambientCG licensing FAQ: “All assets are released under the Creative Commons CC0 license, making them free to use without attribution - even in commercial circumstances.” | 2026-09-29 |
| `assets/cc0_extra/ground/ground-106-wet-mud.png` | 128x128 seamless ground tile candidate — Ground 106 (wet mud); luma mean 0.392, std 0.0569 | 32,884 | ambientCG `Ground106` — https://ambientcg.com/view?id=Ground106 | ambientCG licensing FAQ: “All assets are released under the Creative Commons CC0 license, making them free to use without attribution - even in commercial circumstances.” | 2026-09-29 |

### Licence texts

| Path | What it is | Bytes | Source | Licence | Retrieved |
|---|---|---:|---|---|---|
| `assets/cc0_extra/licenses/LICENSE-CC0-ambientcg.txt` | licence text captured verbatim from the source artefact | 1,451 | — | the licence text itself, copied verbatim out of the source artefact | 2026-09-29 |
| `assets/cc0_extra/licenses/LICENSE-CC0-kenney.txt` | licence text captured verbatim from the source artefact | 1,657 | — | the licence text itself, copied verbatim out of the source artefact | 2026-09-29 |
| `assets/cc0_extra/licenses/source-licence-crosshair.txt` | licence text captured verbatim from the source artefact | 571 | — | the licence text itself, copied verbatim out of the source artefact | 2026-09-29 |
| `assets/cc0_extra/licenses/source-licence-railgun.txt` | licence text captured verbatim from the source artefact | 265 | — | the licence text itself, copied verbatim out of the source artefact | 2026-09-29 |
| `assets/cc0_extra/licenses/source-licence-sfx_impact.txt` | licence text captured verbatim from the source artefact | 608 | — | the licence text itself, copied verbatim out of the source artefact | 2026-09-29 |
| `assets/cc0_extra/licenses/source-licence-sfx_scifi.txt` | licence text captured verbatim from the source artefact | 571 | — | the licence text itself, copied verbatim out of the source artefact | 2026-09-29 |
| `assets/cc0_extra/licenses/source-licence-sfx_ui.txt` | licence text captured verbatim from the source artefact | 479 | — | the licence text itself, copied verbatim out of the source artefact | 2026-09-29 |
| `assets/cc0_extra/licenses/source-licence-td_ground.txt` | licence text captured verbatim from the source artefact | 498 | — | the licence text itself, copied verbatim out of the source artefact | 2026-09-29 |
| `assets/cc0_extra/licenses/source-licence-ui.txt` | licence text captured verbatim from the source artefact | 565 | — | the licence text itself, copied verbatim out of the source artefact | 2026-09-29 |

### Ground tile candidates — measurements

A band of ground is exactly one whole tile tall, so a candidate must tile seamlessly in **both** axes at 128px or a band edge shows. Seam ratio = wrap-edge discontinuity ÷ mean interior neighbour step, the same quantity `tests/test_assets.gd::test_ground_tile_is_seamless` asserts on the live `sand.png` at a **≤ 1.5x** bar. Measured on luma in both axes (the shipped test reads the V channel on X only).

| Tile | assetId | Seam x | Seam y | Worst | Bar | Luma mean / std |
|---|---|---:|---:|---:|---:|---|
| `grass-001-deep-forest-floor.png` | `Grass001` | 1.191 | 1.064 | **1.191** | 1.5 | 0.3084 / 0.0197 |
| `grass-005-lush-dense-turf.png` | `Grass005` | 1.194 | 1.269 | **1.269** | 1.5 | 0.4423 / 0.0202 |
| `ground-037-mossy-grass-mix.png` | `Ground037` | 1.024 | 1.037 | **1.037** | 1.5 | 0.5509 / 0.0308 |
| `ground-039-scorched-ash.png` | `Ground039` | 1.231 | 1.305 | **1.305** | 1.5 | 0.49 / 0.0196 |
| `ground-062l-warm-tan-sand.png` | `Ground062L` | 1.32 | 1.217 | **1.32** | 1.5 | 0.5627 / 0.0304 |
| `ground-062s-gritty-dirt-track.png` | `Ground062S` | 1.127 | 1.382 | **1.382** | 1.5 | 0.5639 / 0.0403 |
| `ground-079l-fine-pale-sand.png` | `Ground079L` | 1.34 | 1.155 | **1.34** | 1.5 | 0.6154 / 0.0223 |
| `ground-095a-dry-cracked-earth.png` | `Ground095A` | 1.254 | 1.233 | **1.254** | 1.5 | 0.4707 / 0.0085 |
| `ground-098-dune-ripple-sand.png` | `Ground098` | 1.349 | 1.433 | **1.433** | 1.5 | 0.6429 / 0.0088 |
| `ground-106-wet-mud.png` | `Ground106` | 0.991 | 1.164 | **1.164** | 1.5 | 0.392 / 0.0569 |

The ratio is *relative*, so a very flat texture reports a high ratio with a sub-1-level absolute step. The absolute luma steps (0–255) are in `MANIFEST.json` under `ground_tiles[].luma_steps_0_255` — for example `ground-098-dune-ripple-sand.png` reads 0.96/1.887 across the wrap against 0.712/1.317 of interior step, i.e. under one 8-bit level. For reference, the live `assets/cc0/sand.png` scores **1.178 / 0.832** and the live `dirt.png` **0.439 / 0.137** on the same metric.

**Contrast, not just seamlessness, is what decides a swap.** The live `assets/cc0/sand.png` is luma std **0.0362** of *pure fine grain* — `src/main.gd` notes only 2.4% of its power below `|k|=2`, so it has almost no mid-frequency structure. The ambientCG candidates carry photographic mid-frequency structure that a 3x3 tile render shows as visible grit. By luma std the closest tonal match is `ground-062s-gritty-dirt-track` (0.0403); `ground-095a-dry-cracked-earth` (0.0085) and `ground-098-dune-ripple-sand` (0.0088) are much flatter than the tile they would replace, and would need their contrast lifted before they read as the same material. **No candidate is a drop-in replacement and none has been evaluated in-engine.**

### Why each candidate was chosen

- **`grass-001-deep-forest-floor.png`** (`Grass001`, Grass 001) — Darker, cooler green than Grass005 with a soft mottle -- the jungle's SHADOW sibling. Where Grass005 is the open clearing, this is the ground under the canopy, and it is dark enough to hold the player's drop shadow and the units' contact shadows without them disappearing into the turf.
- **`grass-005-lush-dense-turf.png`** (`Grass005`, Grass 005) — The JUNGLE biome's identity card. Bright, saturated, densely-turfed green -- the only genuinely lush material in the set, and the one thing the desert-only shortlist was missing. Every advisory review of the jungle-named zone said the ground read as arid sand: the file is named jungle-firefight but the floor was a flat muddy noise field, which looks like a prototype or a palette swap. This is the material that makes zone 1 look tropical instead of desert.
- **`ground-037-mossy-grass-mix.png`** (`Ground037`, Ground 037) — The transition material between jungle floor and bare earth: a mottled moss-and-grass mix that reads as the churned-up edge of a path. Gives the jungle biome a third value so it is not a two-tone green field, and its low-frequency blotching survives the 1K->128 downsample as variation rather than dissolving into flat colour.
- **`ground-039-scorched-ash.png`** (`Ground039`, Ground 039) — The scorched/ash candidate: near-neutral dark grey with no vegetation. Reads as a burnt-out blast zone and is the tonal floor of the set, so it can carry scorched-earth decals under a light ground ramp.
- **`ground-062l-warm-tan-sand.png`** (`Ground062L`, Ground 062 L) — Warm mid-tan fine sand with only sparse grit. The best candidate for a second base-floor card, where the dihedral-variant scheme (GROUND_BASE_VARIANTS) needs a sibling that is visibly different in hue but identical in grain scale.
- **`ground-062s-gritty-dirt-track.png`** (`Ground062S`, Ground 062 S) — The coarse sibling of Ground062L -- visibly peppered with grit. Reads as a trafficked dirt track rather than open desert, which is what the desert biome's vehicle lanes want.
- **`ground-079l-fine-pale-sand.png`** (`Ground079L`, Ground 079 L) — Finest, palest sand of the set -- lowest high-frequency energy, so it survives a 1024->128 downsample as grain rather than dissolving into flat colour. Closest match to the live sand.png's std ~0.036 character.
- **`ground-095a-dry-cracked-earth.png`** (`Ground095A`, Ground 095 A) — Dark brown desiccation polygons. The only genuinely 'dry cracked' material in the shortlist; the polygon scale is a few hundred pixels in the 1K source, so 2-3 cracks survive the downsample intact.
- **`ground-098-dune-ripple-sand.png`** (`Ground098`, Ground 098) — Soft wind-ripple relief in warm tan. The ripple is low enough in spatial frequency to still read as directional texture at 128px instead of aliasing into a crosshatch.
- **`ground-106-wet-mud.png`** (`Ground106`, Ground 106) — The jungle's mud: dark, wet, tracked earth with scattered grit. This is the material for the rain-soaked ground under the treeline, and its strong value contrast against Grass005 is what makes the two read as different surfaces rather than the same green tinted darker.

Also evaluated and **not** imported: `Ground062S`'s siblings 
`Ground093A/B/C`, `Ground096A/B/C` (paler, near-duplicates of 079L/062L); `Ground108` / `Ground110` / `Gravel023` (rubble and dark gravel — high spatial frequency that aliases badly at 128px, and a grey palette that fights the desert biome); `Ground047` and `Ground074` (mossy green, not desert); `Ground031` (urban asphalt); `Ground111` (saturated red rock).

### Reproduction

```sh
python3 tools/fetch_cc0.py             # re-derive everything, then verify
python3 tools/fetch_cc0.py --check     # verify only; exit 1 on any drift
```

Kenney members are copied byte-for-byte from the archives in the shared library (`$GAMEASSETS_LIBRARY`, default `~/gameassets`). Ground tiles are re-derived from ambientCG's public JSON API: 1K-JPG archive → **colour map only** → centre-crop to 512 → half-offset wrap-blend (so both axes tile) → LANCZOS to 128 → PNG. No normal, roughness, displacement, AO, HDRI or USD data is ever downloaded.

<!-- END generated: assets/cc0_extra -->
