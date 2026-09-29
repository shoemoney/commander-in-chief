# Gameplay trailer draft

Prepared locally; not uploaded, rights-cleared or approved for release.

## Deliverable

`build/trailer-current.YSYUiS/draft/CommanderInChief-gameplay-draft.mp4`

The video is 23 seconds, 1920x1080 at 60 fps, H.264 with stereo 48kHz AAC.
It opens directly on gameplay and retains the actual HUD. Three continuous
live-play windows run for 8, 8 and 5 seconds, followed by the existing title logo
for 2 seconds. There are no extra marketing overlays, camera crops, synthetic
gameplay, time-speed changes or newly generated speech. Gameplay scales exactly
3x with nearest filtering before ordinary lossy video encoding. The audio is
the captured game mix with 60ms edge fades at cuts.

SHA-256: `fe0c6c48c64160bae68f23f9ae4f15635fa3a73c19c95a2c2ee3246d172e73cc`

This revision includes the HUD player-visibility repair. The earlier video at
`build/trailer-assembly.CgKxAr/draft-v2/` remains archived with its original
manifest and cut list; it is superseded for the current game build.

Companions in the same directory: `poster.png`, `cut-list.json`, `manifest.json`
and intermediate clip encodes. The poster is an unmodified decoded frame from
the trailer, not separate artwork. Original captures remain in the project paths
below; this is a project-local draft, not a self-contained source archive.

Steam recommends primarily gameplay for the first trailer, often with the HUD
visible, and supports 1080p at 60 fps with H.264/AAC. Its guidance specifies
that a custom poster must come from the video itself. Local encoding does not
establish account-side processing or approval. [Steam trailer guidance](https://partner.steamgames.com/doc/store/trailer).

## Source and cut evidence

The durable cut list is `docs/steam-store/trailer-cut-list.json`.

- `build/trailer-current.YSYUiS/field/`: chapter 1, source frames 300–779.
- `build/trailer-current.YSYUiS/rust/`: chapter 4, source frames 420–899.
- `build/trailer-current.YSYUiS/finale/`: chapter 6, source frames 90–389.

All use seed 3 and real bot-driven `start_arcade` gameplay, with no god mode or
staged entities. Each take includes Movie Maker PNG frames and synchronized WAV,
the full input replay, source fingerprints, per-frame simulation checksums and
RGBA pixel hashes. All takes completed with verified replay score/checksums,
unchanged sources and clean stdout. The selected live windows do not claim a
victory or completed run. All three takes and the endless QA take have identical
game, asset, and capture-script fingerprints. OS gameplay input was disabled;
the bot still uses ordinary simulation inputs.

The 1,260 selected gameplay frames matched their capture-time pixel hashes.
The source-window gate rejects missing/duplicate frames, changed pixels, changed
replays, failed attestations, non-live frames and audio/frame-duration mismatch.
Its eleven positive/negative fixture tests passed. These checks consume the
engine's recorded replay results; the Python assembler does not independently
run Godot or authenticate arbitrary fabricated receipts.

The first encoding had 1,381 frames because concatenated AAC priming timestamps
caused a duplicated video frame. That older draft remains in the prior assembly
directory and is superseded.
The corrected assembler resets each decoded stream's timestamps and validates
the exact final frame count. The current draft has 1,380 frames and both tracks are
exactly 23.000 seconds. Full decoding completed without error. The measured
sample peak was -0.3 dBFS and mean volume -18.6 dBFS; these are not a listening
review or true-peak loudness certification.

Eight decoded frames were opened: the first/last frame of each gameplay cut and
the first/last end-card frame. Evidence is at
`build/trailer-current.YSYUiS/decoded/`. Full playback has not been audibly
reviewed; cuts through speech and general mix quality remain listening gates.

## Blender evidence and excluded take

The logo was reopened from its packed `.blend` in a fresh Blender 5.2.1 process
and rerendered with no source-machine font fallback. Pixel comparison was exact;
the render and report were opened. Evidence:
`build/trailer-logo-fresh-20260907/`. The Blender asset-validation skill supplied
the packed-dependency and fresh-export check. This is flat 2D title art, so rig,
animation, GLB and multiview geometry checks do not apply.

`build/trailer-current.YSYUiS/endless/` is QA evidence, not part of this cut.
All 660 frames passed pixel, audio-timing and replay checks. Frames 480 and 600
were opened to verify the player is visible through the top HUD during the shop
and wave-two combat. No gameplay source was modified during this media pass.

The [capture validation notes](movie-capture-validation.md) explain the explicit
draw repair, movie indexing, input isolation, external watchdog, overwrite refusal,
and why incomplete earlier recordings remain excluded.

## Reproduce

From the repository root, preserving previous draft folders:

```sh
rtk proxy python3 -m unittest discover -s tools -p test_gameplay_trailer.py -v
rtk proxy python3 tools/assemble_gameplay_trailer.py \
  docs/steam-store/trailer-cut-list.json build/trailer-new-draft
```

To record another take, use `tools/capture_gameplay_movie.py` with a new or empty
output directory, `--chapter 1` (or `--mode endless`) and `--frames 900`.
The wrapper supplies a private profile, fixed 60 fps, bounded process lifetime,
and full completion validation. The 120-frame / two-second probe checked every
frame's exact movie-file index; it was not a gameplay performance benchmark.

## Remaining release gates

- Listen to the full cut; review speech boundaries, mix, pacing and sound-off comprehension.
- Confirm asset/font/audio rights and the existing cloned-voice permissions.
  No new voices were generated in this pass, and technical checks do not clear rights.
- Review mature-content/AI disclosures, store preview and intended-account upload/transcode.
- Re-capture after relevant gameplay or asset changes. Existing source fingerprints
  describe this snapshot, not future release builds.
- Complete human playtesting and platform/controller acceptance. This artifact
  provides no evidence of audience reception, awards or launch readiness.
