# Movie capture validation

The recording harness now disables automatic rendering and requests one deferred
draw per process iteration. Movie Maker still owns PNG and synchronized WAV
writing. The receipt indexes files using `Engine.get_process_frames()` before
the current frame is written, not the automatic-draw counter.

Godot's main loop gates automatic drawing on drawable windows, but invokes the
movie writer separately. Its PNG writer advances a separate sequential file
counter. This explains why automatic-draw counts cannot safely name movie files
when drawing is suppressed. Sources:
[main loop](https://github.com/godotengine/godot/blob/master/main/main.cpp),
[PNG/WAV writer](https://github.com/godotengine/godot/blob/master/servers/movie_writer/movie_writer_pngwav.cpp),
[RenderingServer](https://docs.godotengine.org/en/stable/classes/class_renderingserver.html).
Upstream source informed the fix; local captured pixels and timing verify it on
Godot 4.7.2 / macOS / Compatibility rendering.

The native movie summary reports zero automatic draws in this mode. That is not
the movie length. The wrapper verifies actual PNG files, decoded RGBA hashes,
consecutive frame indices, and exact WAV sample count instead of trusting that
summary or the process exit code.

## Safeguards

- Automated capture disables viewport input. Bot inputs still enter the ordinary
  game simulation. `tools/verify_movie_input.gd` proves an injected restart key
  is ignored during isolation and resets normally when isolation is removed.
- A changed simulation instance, skipped index, or duplicate index fails the take.
  A prior failed endless take reset at movie frame 9; its final score replay
  passed, but its per-frame replay check failed. It is not usable footage.
- `tools/capture_gameplay_movie.py` refuses nonempty output directories before
  starting Godot; Movie Maker itself may overwrite existing numbered files.
- The wrapper requires both a completion marker and a full verified receipt.
  A process exiting zero partway through a take is still a failure.
- An independent wall-clock watchdog terminates only the process group it
  launched. A one-second timeout test exited nonzero and left no matching Godot
  process. Incomplete output is retained for diagnosis.
- Whole-take verification permits deaths, since a real recorded run may end.
  Trailer selection continues to reject every non-live frame.

## Evidence

- Short fixed-draw probe: `build/movie-repair.rqAS4d/`, 120 consecutive frames,
  every recorded pixel checked against the saved PNG, exact audio timing, and
  verified replay score/checksums. Reusing that directory was refused, and the
  existing take verified again afterward.
- Current capture set: `build/trailer-current.YSYUiS/`. Each completed take has
  `stdout.log`, `movie.json`, `take.replay`, PNG sequence, and `take.wav`.
  Opening and later-terrain takes have 900 checked frames each, final chapter
  420, and endless 660. All four completed with matching source fingerprints,
  verified replay score/checksums, exact PNG pixels/audio timing, and clean exit.
- Watchdog negative test: `build/trailer-current.YSYUiS/watchdog-check/`.
- Source gate: 11 positive/negative tests in `tools/test_gameplay_trailer.py`.
  Tests cover shifted/gapped indices, altered pixels/replay, incomplete counts,
  dead/menu selection, failed attestations, and audio/frame timing mismatch.

## Reproduce

From the project root, use a new output directory:

```sh
rtk proxy python3 tools/capture_gameplay_movie.py build/new-opening-take --chapter 1 --frames 900
rtk proxy python3 tools/capture_gameplay_movie.py build/new-arena-take --mode endless --frames 660
rtk proxy bash tools/run_tests.sh --script res://tools/verify_movie_input.gd
rtk proxy python3 tools/test_gameplay_trailer.py
```

The wrapper defaults to seed 3 and 60 fps. These checks verify the recording
pipeline, not human playtesting, audible mix quality, commercial permissions,
Steam account approval, or audience response.
