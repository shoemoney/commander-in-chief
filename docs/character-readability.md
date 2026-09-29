# Character readability pass

Applied the newly installed Godot animation and camera guidance to the existing
top-down character assets. This is a view-layer integration pass, not new artwork,
new voices, a balance change, or a change to the deterministic simulation.

## Changes

- Corrected the north-facing troop artwork to follow the game's +X-zero aim
  convention. Tank barrels, projectiles, and scenery retain their own conventions.
- Separated locomotion sampling from dust emission. Redrawing the same simulation
  tick now preserves a moving pose; stopping, restarting, and replacing an enemy
  in a compacted slot reseed correctly.
- Tied stepping and breathing to simulation time, including pause/hitstop and
  reduced-motion behavior. Tank gunners use their actual aim and action pose.
- Kept shooting infantry pointed along their committed attack lane during windup
  and recoil, even when the target moves sideways.
- Left the existing forward-scrolling camera rules intact; their regression tests
  remain part of the full suite.

## Verification

- Full suite: 1,191 methods, 38,241 assertions, zero failures; clean exit gate.
- Whole-game menu/input playthrough: 80 checks, zero failures; clean exit.
- Eight staged real-renderer QA images: cardinal aim and both forward/backward
  step poses. All nonblank and unique; visually inspected.
- A separate bot-driven live capture exercises real gameplay, not staged state.
  The short MP4 is silent because it is encoded from framebuffer images.
- Headless framebuffer capture fails explicitly instead of claiming blank output.
- Generated build/marketing artifacts are excluded from Godot source imports by
  `build/.gdignore`; the marker is tracked while build outputs remain ignored.

The staged images live under `build/skills-pass/characters/`. Do not present them
as screenshots from an ordinary playthrough. The live movie is
`build/skills-pass/character-gameplay.mp4`.

## Repeat the visual checks

Run from the project root with Godot 4.7.2 and an actual graphics context:

```sh
rtk proxy mkdir -p build/skills-pass/characters build/skills-pass/live
rtk proxy env SHOT_DIR="$PWD/build/skills-pass/characters" \
  bash tools/playtest_newcomer.sh --rendering-method gl_compatibility \
  --resolution 640x360 -s res://tools/capture_character_readability.gd
rtk proxy env SHOT_DIR="$PWD/build/skills-pass/live" GIF_SKIP=240 \
  GIF_FRAMES=240 GIF_EVERY=2 bash tools/playtest_newcomer.sh \
  --rendering-method gl_compatibility --fixed-fps 60 --resolution 640x360 \
  -s res://tools/gif_capture.gd
```

The live capture drives rendering explicitly because an occluded macOS window
can stop automatic frame draws while game logic keeps advancing. This affects
the capture tool only, not the production game loop. It uses Godot's documented
[RenderingServer.force_draw](https://docs.godotengine.org/en/stable/classes/class_renderingserver.html#class-renderingserver-method-force-draw)
on the main thread, after deferred scene work, and has a bounded deadline.

The suite and these captures establish regression coverage, not a human
playtest, hardware compatibility certification, or commercial release readiness.
