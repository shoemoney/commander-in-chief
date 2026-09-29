# Solo ready-up feedback

## Player goal and rules

After an Endless wave, the player can shop or hold REVIVE to deploy early.
Co-op already displayed a vote/progress panel, but `_draw_ready_tally` rejected
every solo run before drawing. The existing solo hold therefore had no progress
acknowledgment. This pass extends the panel to solo play; no simulation, timing,
prices, balance, progression or input bindings changed.

The production drawing function now consumes `_ready_tally_state()`. Solo shows
“READY — DEPLOYING”, “RELEASE TO KEEP SHOPPING” and the actual `sim.ready_hold`
fraction. Co-op retains the split-vote/missing-seat explanation. The state is
empty outside an intermission, without complete input data, after release, or
when anyone is down. There is no view-side timer and no new resource cost.

Existing state transitions remain authoritative: living solo or unanimous
living co-op enters the hold; release cancels it; a downed partner restores
rescue priority; completion or natural shop expiry starts the next wave and
resets the hold. The existing deployment banner and sound still acknowledge
completion. Pausing does not advance simulation time or the displayed fraction.

## Design evaluation

The game-design skill prioritizes response and clarity before balance tuning.
Here, the defect was missing feedback, not a demonstrated timing problem:

- **Clarity:** show that the held action is deployment and explain cancellation.
- **Motivation:** keep the existing choice between buying and returning to combat.
- **Response:** acknowledge solo input during the hold; remove it on release.
- **Satisfaction:** retain the existing visual/audio deployment completion cue.
- **Fit:** reuse the established co-op panel and world-label placement system.

The game-feel skill informed the decision to reuse restrained, transient feedback
instead of adding shake, flashes or another input lock. No new numerical gameplay
values are proposed. Human comprehension and perceived pacing remain unproven.

## Evidence

- Baseline actual-renderer pose:
  `build/ready-before.gveymc/01-solo-holding.png`; the soldier is holding at half
  progress but no ready panel is visible.
- Regression before repair: `build/ready-before.gveymc/regression-red.log` fails
  solo feedback and every pre-completion progress sample, exit 1.
- Focused pass: `build/ready-before.gveymc/regression-green.log`, 105 methods,
  1,921 assertions, zero failures and clean shutdown.
- Actual renderer after repair: `build/ready-after.75NNFw/`, five distinct live
  frames, all inspected: solo held, solo released, co-op split, both holding at
  doubled text size, and a downed partner requiring rescue. Capture exits cleanly.
- Full suite: `build/ready-after.75NNFw/full-suite.log`, 1,217 methods,
  38,516 assertions, zero failures and clean shutdown. Real-scene end-to-end
  checks: `e2e.log`, 80 checks, zero failures and clean shutdown.
- The translation sync check then caught one obsolete revival-tip key from the
  earlier recovery repair. Removed that unused entry from the Spanish, French
  and Japanese catalogs; the active-source key check passes. This limited
  extractor does not establish complete localization of all on-screen copy.

These are **staged QA screenshots**, not unmodified playthrough/store screenshots.
Reproduce using an existing writable output directory:

```sh
rtk proxy env SHOT_DIR=/absolute/output bash tools/playtest_newcomer.sh --rendering-method gl_compatibility --fixed-fps 60 -s res://tools/capture_ready_feedback.gd
rtk proxy env SUITE=view_honesty bash tools/run_tests.sh
```

The regression drives the existing wave state machine through each hold tick,
release, restart and completion, and checks checksum invariance when reading
presentation state. Co-op checks split/unanimous inputs, a downed partner,
missing input data and non-Endless mode. No determinism goldens were changed.

## Human acceptance still required

Use the fresh-profile newcomer protocol in `ten-item-acceptance.md`:

- Newcomer: ask the player to return to combat early without explaining the bind.
- Stress: repeatedly press/release; the bar must never retain canceled progress.
- Skill: buy deliberately, then skip the remaining wait without losing control.
- Abuse: one co-op seat must not deploy the other; rescue must not skip the shop.
- Readability: ask an observer what the bar means and how to cancel it; repeat
  at doubled text size and with the player's chosen input device.

If observed confusion remains, revise the cue before changing hold duration.
Bot checks and screenshots do not establish human acceptance or exceptional fun.
The Steam candidates under `build/steam-native.DjatEv/` predate this source repair.
A subsequent refresh under `build/steam-ready.jqZpJ9/candidates/` includes it and
passes the packed hold/release behavior check; see `steam-candidate-validation.md`.
