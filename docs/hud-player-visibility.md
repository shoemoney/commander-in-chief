# Player visibility beneath the HUD

The fixed-camera endless arena permits a player center 16 pixels below the top
edge. The top HUD previously covered valid player positions. Staged renderer
checks reproduce this at y=16 and y=42, including two-player positions. The demo
bot's unconditional northward travel makes the overlap particularly frequent;
this change does not alter the bot, movement bounds, camera, hitboxes, or replay.

The HUD now shares a small screen-space transparency aperture across its drawn
readouts, backing canvas item, and nested panel controls. Each player has an
independent aperture, including downed bodies. It affects only the top panel;
captions and bottom controls are untouched. Positions are rounded exactly like
the world-to-screen projection. Material parameters update only when changed,
avoiding a redraw loop discovered and fixed during rendered verification.

## Evidence

- Before: `build/hud-before.qiCe44/`, four staged edge-case images.
- Final staged render: `build/hud-staged-final.37vGBd/`, the same four states.
  These are QA fixtures, not marketing gameplay screenshots.
- Earlier comparison `build/hud-final.OfetY9/04-clear-of-hud.png` is byte-identical
  to the baseline. Differences in that comparison's other fixtures are confined
  to the player's local top-HUD area. The final revision moves material updates
  out of the draw callback into normal processing; the frozen QA fixture explicitly
  synchronizes its posed state before rendering.
- Regression coverage in `tests/test_hud.gd` checks solo/co-op positions, downed
  bodies, shader parameter delivery, nested material inheritance, restoration
  after movement, and simulation checksum preservation.
- Full suite: **1,214 methods, 38,441 assertions, zero failures**, clean exit.
  Log: `build/hud-verify.X78qZf/full-suite.log`. The previous run correctly failed
  on two stale README method-count claims, which have been updated.
- Regular gameplay capture: `build/hud-gameplay.Vwj50k/`, completed cleanly with
  six captured frames over 660 render iterations. Saved replay score, every sampled
  simulation checksum, and unchanged source fingerprints all verified. All PNG
  hashes and exact nearest-filtered 3x presentations independently checked.
  Frames 5 and 6 were visually inspected: the player is visible through the top
  HUD during intermission and wave-two combat, respectively.

## Movie capture follow-up

Movie Maker wrote images while the capture coroutine stalled. Neither changing
its heartbeat to a signal connection nor changing how shader uniforms were set
resolved it. Those experiments were reverted; no causal claim is supported.
Incomplete movie attempts (`hud-live.AEhT3F`, `hud-verify.X78qZf`,
`hud-live-final.sBtiwz`, `hud-live-checked.z42wC0`, and `hud-rs.1MiQ61`) were
stopped and are not valid gameplay receipts. Regular rendered gameplay uses the
existing force-draw capture path to distinguish recording from runtime behavior.

The subsequent [movie capture validation](movie-capture-validation.md) resolves
the automatic-draw stall with a single explicit draw per process iteration,
correct file indexing, input isolation, and an independent completion watchdog.
New recordings are kept separately from these incomplete attempts.

## Limits

Readouts directly over a player deliberately lose contrast so the actor wins
that small region; the rest of the panel remains normal. This does not make
offscreen sprite pixels visible: the existing 16-pixel movement margin remains.
The HUD layout itself still merits a broader usability pass. This is a local
readability repair, not evidence of launch readiness or an overall quality rating.
