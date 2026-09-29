# Actual gameplay screenshot handoff

Prepared September 7, 2026. Locally inspected draft, not uploaded or approved.

## Current replacement set

The current five PNGs and capture evidence are in
`build/steam-current.pKhThM/handoff/` (repository-relative). This replaces the
older `build/steam-gameplay.6jrjaB/handoff/` selection without deleting it.
The new takes use the source after the character, ground, streak, HUD visibility
and title-clarity repairs. `manifest.json` maps each selected image to its exact
source frame, hash, recorded simulation state and evidence folder.

Downloadable archive: `build/steam-current.pKhThM/CommanderInChief-gameplay-screenshots.zip`.
SHA256: `6ffed542e6a05ff2e18dd7bd310c9bc3f5c37a40ab359c23b58eaa9104681ac2`.
Its compressed-data integrity check passes. The included `handoff/index.html`
is a local review gallery; it is not itself a Steam upload asset.

The selection is gate combat, river approach, crossfire, explosions and last
stand. All five selected raw images were opened and inspected. The presentation
images are exact nearest-filtered 3× copies, verified pixel by pixel and copied
unchanged into the handoff. No marketing copy, cropping or retouching was added.

Four main takes retain twenty frame pairs each. A separate six-frame early
river take was checked but not selected: it added no useful river view and
contained early deaths. Its output is preserved beside the handoff, not packaged
as store imagery. The river approach selection instead comes from the continuous
chapter-1 take as it enters sector 3. All 86 frame pairs pass integrity and
exact-presentation checks; all five renderer processes exited cleanly with
verified replay scores, per-capture simulation checksums and source stability.

The capture tool now disables OS gameplay input, while the normal bot continues
to supply simulation inputs. It aborts if the simulation instance is replaced.
New handoffs require that isolation receipt and matching source-file fingerprints,
engine version and renderer across all selected takes. Eight screenshot contract
tests and eleven trailer contract tests pass. The older non-isolated selection
was explicitly rejected before creating a handoff directory; its original
evidence remains readable by the standalone verifier. No production game code
or assets changed in this refresh.

Current selection: `docs/steam-store/gameplay-selection.json`. Reproduce into a
new directory with `tools/assemble_store_gameplay.py`. Verify copied evidence:

```sh
rtk proxy python3 tools/verify_store_gameplay.py \
  build/steam-current.pKhThM/handoff/evidence/sector1 \
  build/steam-current.pKhThM/handoff/evidence/sector3 \
  build/steam-current.pKhThM/handoff/evidence/sector5 \
  build/steam-current.pKhThM/handoff/evidence/sector6
```

The methods and limitations below remain applicable. The historical verification
counts and original take names describe the earlier set, not this replacement.

## Original capture method and historical evidence

## What was captured

`tools/capture_store_gameplay.gd` runs the production main scene with its normal
autoplay bot, Arcade chapter selection and deterministic seed 3. It does not
stage enemies, inject inventory, enable invulnerability or hide gameplay UI.
Boot splash and focus-based auto-pause are suppressed only for capture.
Fresh, isolated profiles avoid modifying the owner's saved progress.

The original game canvas is 640×360. Godot renders each captured canvas into
a 1920×1080 nearest-filtered presentation, exactly 3× integer scaling, and saves
both. This preserves the game's existing postprocessing; it does not create
native HD artwork, crop the frame, add copy or retouch the image. Pixel checks
confirmed every presentation equals its raw source repeated 3× in each axis.

Four takes, starting at chapters 1, 3, 5 and 6, each retain twenty captures,
including rejected death/end-screen frames. The chapter-1 take advances into
sector 2 through normal play. The five selected frames all have a living player,
no active menu, no wipe/debrief and no god mode. This is automated play, not a
human playtest or a claim about difficulty balance.

Each take saves a complete input replay. Before reporting success, the capture
script reloads that replay, recomputes its final score, and independently
re-simulates it to match the checksum at every captured input-frame index.
Fingerprints cover `src/`, `assets/` (excluding generated `.import` sidecars),
`project.godot`, the capture scripts and teardown helper. Those existing files
were checked unchanged at the end of each take. The source is dirty `cf23387`,
not a claim that the bare commit reproduces these images. Fingerprints identify
files but are not a bundled source backup or a check of imported cache contents.

## Verification

- All four renderer runs exited successfully without reported script or leak
  errors. Final replay scores, all captured simulation checksums and source-file
  stability checks passed.
- All eighty frame pairs passed file-hash and exact presentation-pixel checks.
- The five selected raw images were actually viewed; the corresponding large
  images were checked for exact pixel equivalence, not merely file presence.
- Assembly copied the images without alteration, retained the complete evidence
  takes and verified the copied hashes and evidence again.
- Six verifier tests passed, including modified-pixel, modified-replay,
  missing-verification, god-mode and path-escape rejection checks.
- gda reported the new capture script valid in the correct project. No production
  game script or asset was changed in this screenshot pass; the earlier full
  game-suite results in `release-readiness.md` are not claimed as a fresh run.

To verify an evidence folder:

```sh
python3 tools/verify_store_gameplay.py build/steam-gameplay.6jrjaB/handoff/evidence/store-gameplay-sector1.Xx2tgk
python3 -m unittest discover -s tools -p test_verify_store_gameplay.py -v
```

The Python verifier checks files, pixels and recorded successful attestations;
it does not itself execute Godot, authenticate an adversarially fabricated
receipt, or establish licensing or Steam acceptance. The engine run is the
replay/simulation proof. For a fresh take, create a new output directory, set
`SHOT_DIR`, `CAPTURE_SEED`, `CAPTURE_REVISION`, `GIF_CHAPTER`, `GIF_SKIP`,
`GIF_FRAMES` and `GIF_EVERY`, then launch `tools/playtest_newcomer.sh` with
`--rendering-method gl_compatibility --fixed-fps 60 -s
res://tools/capture_store_gameplay.gd`. Do not use a headless renderer.
Use a sufficiently short take to fit the capture's 120-second deadline.

`docs/steam-store/gameplay-selection.json` records the inspected selection.
`tools/assemble_store_gameplay.py` can reproduce the handoff into a **new**
directory; it refuses overwriting an existing destination.

## Store and quality limits

Rechecked against the official guidance during this refresh: Steam requires at
least five gameplay screenshots, specifies 1920×1080 minimum
and 16:9, and separates screenshot age suitability from upload. These images
show combat; none is asserted suitable for all ages. Owner review must address
that designation, rights, content disclosures and account-side previews.
[Steam screenshot guidance](https://partner.steamgames.com/doc/store/assets/standard).

This meets the local preparation target, not the complete launch target.
Regenerate the selection after material game/art changes. Final trailer, broader
mode/co-op coverage, localization and Steam review remain open.

The live images also expose remaining quality work: overlapping score bursts,
objective text, captions and control hints can dominate combat; several sectors
share a similar ochre palette, limiting immediate visual distinction. These are
visual-review findings, not measured human-comprehension results. Do not claim
10/10 quality or external player approval from successful capture tests.
