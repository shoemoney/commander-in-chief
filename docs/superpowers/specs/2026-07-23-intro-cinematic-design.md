# Intro Cinematic — Design Spec

**Date:** 2026-07-23
**Feature:** A cinematic studio-presents + trailer-crawl + title + hero intro that plays when the game boots, folding in the existing shield-stamp beat. Trump-voiced narration over the crawl.
**Layer:** View-only (extends `main.gd`'s `_draw_splash` overlay). No sim/state change → determinism goldens untouched.

## Goal
Replace the current bare 6s shield splash with a 5-beat cinematic intro, keeping the shield stamp as one beat (user chose "fold the shield beat in"). Fully skippable.

## Beats (~15.5s total, skippable at any point)
| # | Beat | Duration | Content |
|---|------|:--------:|---------|
| 1 | Studio card | 3.0s | Animated `bigit.gif` (spritesheet) fades in centered; "BIG IT GAME STUDIOS PRESENTS" fades in below; hold; fade out. |
| 2 | The crawl | 7.5s | Black. Text scrolls bottom→top, fading in: *"When tragedy strikes the United States fighting force… there is only one man who can go in and win the war for the USA."* **Trump-voiced VO narrates it** (measured 7.36s → beat sized to match). Scroll speed keyed to the VO length so text and voice finish together. |
| 3 | Title + shield | 2.5s | "THE COMMANDER IN CHIEF" fades in large; the existing shield emblem stamps in (back-ease overshoot) with the white impact flash. |
| 4 | Hero KEY-ART reveal | 3.0s | The generated **CommanderInChief key-art poster** (Rambo-style Commander on the Iran battlefield, "COMMANDER IN CHIEF" banner) fades in ~full-frame with a slow push-in; the built-in title banner IS the title. (Supersedes the raw `flag.jpg` idea — user approved 2026-07-23. flag.jpg stays available as a fallback.) |
| 5 | Dissolve | 0.5s | Melts into the existing title/menu. |

## Assets
- **`bigit.gif`** (~/Desktop, 480×480, 124 frames, 4.5MB) → BAKED to spritesheet `assets/ui/bigit_sheet.png` = **31 frames @ 200px, 6×6 grid (1200×1200)** (every 4th gif frame). Godot 4.7 can't play GIFs natively, so play via a frame index in `_draw_splash`: `frame = int(elapsed*fps) % 31`, draw the sub-rect `(200*(frame%6), 200*(frame/6), 200, 200)`, ~12fps. Import lossless, detect_3d off.
- **`flag.jpg`** (~/Desktop, 1782×2148) → BAKED `assets/ui/flag_hero.png` = **597×720** (resized to 720 tall), import lossless (compress/mode=0, detect_3d/compress_to=0 — the legacy art-bake rule test_assets.gd enforces on any bake; apply to these UI images too to be safe).
- **VO:** one clip `assets/vo/intro_crawl.mp3` — the crawl line in the Trump voice (fleet VoiceStudio on .4), **measured 7.36s**. Played on the dry UI/VO bus at the start of beat 2, ducking any music.
- All three assets are BAKED and staged in `<scratchpad>/intro/`; they get copied into `assets/` at implementation time (after shoop lands).

## Implementation sketch (main.gd)
- New constants for the 5 beat boundaries (replace/extend `SPLASH_DUR=6.0`, `SPLASH_STUDIO_END`, `SPLASH_FADE_OUT`). Total ~12.5s.
- `_draw_splash()` gains a beat dispatch on `elapsed = SPLASH_DUR - _splash_t`: beat 1 gif+studio, beat 2 crawl, beat 3 title+shield (reuse existing `_splash_back`/stamp), beat 4 flag photo, beat 5 crossfade.
- Preload `_bigit_sheet`, `_flag_hero` textures alongside `_splash_icon`.
- Fire `intro_crawl` VO once when beat 2 starts (latch).
- Keep the existing trailer-capture bypass (`_splash_layer.visible=false`).
- Skip: existing splash-skip input dismisses the whole overlay.

## Non-goals
- No sim changes, no new gameplay. No GIF runtime decoder (bake to sheet instead). No parallax/3D — flat 2D draw.

## Testing / gates
- `--import` clean; full suite green; determinism goldens unchanged (view-only).
- Screenshot each beat via the headless GL path (may be black — fall back to compositing a mock if so).

## Notes
- Built AFTER the running shoop (`wvv60b8ww`) lands, to avoid tree collisions.
- Spec authored in scratchpad; move to `docs/superpowers/specs/2026-07-23-intro-cinematic-design.md` + commit once the tree is free.
