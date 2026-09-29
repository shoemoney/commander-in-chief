# Steam library hero — composition and export verification

## Contract and result

This is illustrated game artwork, not a real-world image or gameplay screenshot.
The deliverable is an opaque, text-free 3840×1240 PNG and its packed Blender
source. The title remains a separate transparent logo. The format and layering
follow the [Steam library asset specifications](https://partner.steamgames.com/doc/store/assets/libraryassets),
checked September 7, 2026. Local crop simulations do not establish Steam client
preview behavior or platform acceptance.

The earlier hero cropped the hair at its top edge. Two subsequent Blender-only
layout trials were rejected after opening the results: one stretched scenery,
the other left a rectangular backdrop transition. Their evidence remains in
`build/steam-hero.pTumWz/` and `build/steam-hero.ZXgUfe/`; neither is in the handoff.

A dedicated panoramic edit was then generated with the built-in image tool from
`build/steam-media/generated/keyart-fal-v2.png`. Its project-local output is
`build/steam-media/generated/library-hero-v3.png` (2172×724). Blender uniformly
scales that source and crops a small amount vertically to produce the required
size. This is an upscaled export, not a claim of native 3840-pixel source detail.

Source SHA256: `7ed9980740cb2bc3eb16c0f25100f504eba29e3a6cb800e48a5b98f67ab035ed`.
Final PNG SHA256: `74eb713cb4535e9bd7f7b2b625ac608d07e73a191b36c40f74bdca38267fc29d`.

## Verification

- Blender 5.2.1 LTS, build `9e2066aef7ef`; Cycles CPU, 16 samples,
  denoising off, Standard/None, exposure 0, gamma 1, 8-bit RGBA PNG, still frame 1.
  Final render reported 4.256 seconds; fresh reproduction reported 4.442 seconds.
- The source reopens in a clean Blender process and renders solely from its
  packed image after its external image path is invalidated in memory.
- Fresh render pixels match the reference exactly. All alpha pixels are opaque;
  the artwork mesh fills the canvas, with no visible font objects.
- The manually inspected source hair/face box is tied to the packed image hash.
  The verifier projects that box through the actual mesh UV mapping and camera,
  checks uniform scaling, and requires it inside the conservative 860×380 center
  of the full-size export. This is not automatic face recognition.
- The final image, fresh process report, wide/narrow logo previews and protected
  center crop were inspected. The hair and chin remain visible in the protected
  crop; the separate lower-left logo does not cover the face in the two previews.
- Five contract tests pass, including rejection of camera displacement,
  nonuniform scaling, a changed source hash and missing source annotations.

Final evidence: `build/steam-hero.KRzhYW/` (`deliverables/`, `fresh/`, `previews/`).
No GLB, rig or multiview geometry contract applies to these flat PNG print assets.

## Art handoff

`build/steam-hero.KRzhYW/steam-art-handoff/` gathers eight named PNGs, their packed
Blender sources and a checksummed `manifest.json`. It uses the corrected hero
and the previously validated capsule/logo files. The library header is an
explicit byte-identical copy of the store header, rather than an implicit fallback.

This is an art handoff, not a complete release package. Gameplay screenshot
selection, final store writeups/disclosures, rights review, actual Steam account
preview/review, production Steam-enabled builds and broader playtesting remain
open. No store upload, publication, commit or push was performed.

## Reproduce

Use a fresh output root; the builder refuses to overwrite an existing deliverables
directory. It accepts `--layout` to rerender only the affected layout.

```sh
rtk proxy /Applications/Blender.app/Contents/MacOS/Blender \
  --background --factory-startup --python-exit-code 1 \
  --python tools/build_steam_media.py -- --project . --output build/hero-repeat \
  --generated-root build/steam-media/generated --layout library_hero
```

Then run `tools/verify_steam_media.py` and `tools/test_steam_hero_contract.py`
inside Blender, using the source and reference paths from that output.
`tools/preview_steam_hero.py` renders the independent logo/crop simulations.
`tools/assemble_steam_art.py` creates a new handoff without overwriting previous art.

## Generation record

Built-in image-tool edit; no CLI fallback. Original generated output:
`/Users/shoemoney/.codex/generated_images/019fba02-29e5-7f82-b341-a3e82f1cc0ab/exec-26b7e879-d188-4938-bba6-fb045ce4fc1f.png`.
The selected image was copied into the project before being referenced by Blender.

Prompt:

> Use case: compositing. Edit target: the supplied existing illustrated game artwork. Technical asset task: recompose it as a seamless 3:1 panoramic background, without text, lettering, logo, border or letterboxing. Preserve the same illustrated character identity, facial expression, blond swept hair, olive vest, red necktie, clothing, rifle and painted line-art style. Do not add people, flags, symbols, slogans, new combat, injuries or political messaging. Change framing and surrounding desert scenery only. The character must be considerably smaller and centered: his COMPLETE hair, face, ears and chin must fit inside a box spanning x=43% to 57% and y=37% to 63% of the entire image. The exact image center is the middle of his face. Show the upper body beneath this, naturally cropped by the bottom of the panorama; maintain all proportions. Extend the same desert canyon and muted ochre sky across the FULL panorama with natural perspective, not stretched pixels, not a pasted rectangle, not blur-fill. Retain quiet dark negative space on the far left for a separate UI logo. This is text-free artwork only, not a screenshot or real-world depiction. No endorsement, claim, accolade, or typography. The key correction is a centered, fully uncropped small head with seamless surrounding scenery, suitable for responsive center crops.
