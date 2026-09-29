# Chapter environment repair

Status: source repair and local rendered verification, not a release approval.

Chapter Select moved the simulation's stream cursor past skipped gates, but the
view counted only gates actually opened. Later chapters therefore inherited the
opening environment. The retained ground canvas also kept the previous world's
palette until enough terrain had scrolled through the screen.

## Changes

- `src/main.gd` now uses the simulation's current sector for campaign/arcade
  environment progress, including the pre-stream Chapter Select state.
- The retained ground cache tracks its owning simulation. A fresh run receives
  its own treatment immediately; an ordinary gate crossing still brings new
  ground in from the top without repainting visible ground under the player.
- `tests/test_view_honesty.gd` exercises real chapter jumps before and after
  streaming, unchanged simulation checksums, a normal gate crossing, and
  replacement runs at the same camera position.
- Capture receipts now include current, cached and retained environment progress.

The level-design skill's material/readability guidance informed this repair:
restore the existing authored progression before adding more scenery. This does
not add new biomes, geometry, art assets or simulation rules. The gda validation
and Godot headless-verification skills supplied the compile, regression, real
renderer and teardown checks; headless boot alone was not treated as visual proof.

## Rendered evidence

All paths below are repository-relative. Each take uses actual autoplay through
`start_arcade(chapter)`, seed 3, no god mode, a fresh profile, 45 settling frames,
120 capture frames and one image per 30 capture frames.

- Chapter 1: `build/environment-ch1.nDZz9r/`
- Chapter 2: `build/environment-ch2.XycevT/`
- Chapter 3: `build/environment-ch3.l8pLQG/`
- Chapter 4: `build/environment-ch4.GZzmeQ/`
- Chapter 5: `build/environment-ch5.qG7OJM/`
- Chapter 6: `build/environment-ch6.NEgjb3/`

The first raw frame of every chapter was visually inspected. Ground shifts
from ochre desert through darker badlands and scorched rust/ash treatments;
props and scenery change with the existing sector progression. This repairs a
visible mismatch, but the chapters still share many silhouettes and need more
art-direction and human-playtest work before being called exceptional.

All 24 raw/display pairs passed the integrity verifier, with full input replay,
replayed-score checks, per-frame simulation checksums and stable source hashes.
Current/cached/retained progress agreed throughout each take: 0.0, 0.2, 0.4,
0.6, 0.8 and 1.0 respectively. Chapter 3's bot died after the first selected
frame; the later frames are not eligible active-play store screenshots.

These are QA takes, not a replacement approved Steam screenshot selection.
Earlier store handoffs and native exports predate this repair.

## Capture teardown regression

The initial chapter 2 and 6 takes emitted two leaked-object warnings at exit.
A repeat with verbose output in `build/environment-shutdown.dgDVDQ/stdout.log`
identified both as `AudioStreamPlaybackPolyphonic`, not terrain/world nodes.

`tools/quiesce.gd` intended to wait half a real second, but used a simulation
timer. The new `tools/verify_quiesce.gd` reproduced a 5ms drain under accelerated
fixed-FPS execution and failed before the repair. Teardown now uses a monotonic
elapsed-time deadline with asynchronous polling. Godot documents its elapsed
tick methods as monotonic in the [Time reference](https://docs.godotengine.org/en/stable/classes/class_time.html).

The regression passes both accelerated and paused/zero-time-scale cases, each
observed at 500ms, and verifies that the owned node was freed. CI now requires
both completion markers, a successful process exit and no error/leak diagnostics.
This changes the verification tool's cleanup; it does not change gameplay timing.

Fresh repeats after the repair:

- Chapter 2: `build/environment-clean.14MOu9/`
- Chapter 6: `build/environment-clean-ch6.i5c8LG/`

Both repeats completed with clean verbose stdout, verified replay/checksums and
four integrity-checked raw/display pairs each. The original warnings remain in
the evidence rather than being ignored or relabeled clean.

## Checks

- Full source suite after the environment repair: 1,213 methods, 38,427 assertions,
  zero failures and clean shutdown. The full suite was repeated after the audio
  teardown repair with the same result; stdout is retained at
  `build/environment-clean.14MOu9/full-suite.log`.
- Focused view-honesty repeat: 102 methods, 1,847 assertions, zero failures.
- Real-scene end-to-end repeat after the teardown repair: 80 checks, zero failures
  and clean shutdown; separate boot smoke also passed with clean shutdown.
- gda validated all changed GDScript files with `valid: true` and no diagnostics.
- Gameplay integrity verifier's six positive/negative contract tests passed.
- Local whitespace/error checks passed. Remote CI was not run or claimed.
  The updated CI workflow also parsed successfully with the new teardown step.

Human comprehension, extended play, controllers/platform acceptance, refreshed
release builds and final store review remain open. Test success does not establish
Game of the Year quality, a 10/10 rating, awards or audience reception.
