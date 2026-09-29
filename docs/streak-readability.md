# Combat reward readability

September 7, 2026. Source changes, not a new exported release.

## Changes

The game-feel skill's importance/lifetime guidance informed this pass: retain
the existing audio, local light and ring, but give each streak milestone one
compact message containing its tier and bonus. Previously a milestone spawned
two separate plates, including a delayed oversized percentage. A rapid tier
upgrade now replaces only the older streak receipt, identified by a semantic
role; unrelated rewards, loss messages and warnings are untouched.

The floating-message budget now ignores suppressed, expired and future-start
messages. Those effects could previously occupy slots despite drawing nothing.
The existing four-message cap, world-label collision checks, player exclusion,
HUD reservations and droppable-reward behavior remain in force. This is not a
guarantee that every reward message is visible in a crowded fight.

A related bug was reproduced through real simulation kill events: multiple
kills in one step could cross a milestone without ending exactly on it. The
view receives the completed step's streak, so an equality check skipped the
reward presentation. The consumer now recognizes the highest crossed tier and
emits it once. No payout, difficulty, collision or simulation rules changed.

## Evidence

- Two added test methods cover receipt coalescing, valid tiers, unrelated-message
  preservation, unchanged simulation checksum and the drawable-only budget.
  A positive control starts a delayed headline and confirms it then gets a slot.
- Batched real kills crossing each tier reproduced six failed assertions before
  the threshold repair; the same test passed afterward. The focused main suite
  passed 91 methods / 1,130 assertions with clean shutdown.
- The real-scene end-to-end run passed 80 checks with clean shutdown.
- Final full regression: 1,213 methods / 38,387 assertions, zero failures and
  clean shutdown. The earlier full attempt failed only the README's stale test
  counts; those counts were updated before the final run.
- QA captures: `build/streak-readability.aUcVZ2/` (repository-relative).
  Three milestone cases, settled presentation and expiry were rendered. The
  tier-5, tier-20, settled and expired frames were opened and inspected. Tier-10
  passed the capture's liveness/uniqueness check but was not separately viewed.
  The QA setup uses actual simulation kill/payout and the production event
  consumer; it stages the prior streak/timer and is **not store media**.
- The first QA attempt, `build/streak-readability.5mpkB5/`, is rejected: its
  setup omitted the streak timer, causing the next kill to reset the streak.
  Files and a zero exit code did not override the assertion errors. The corrected
  tool now explicitly exits unsuccessfully if its receipt expectation fails.
- Actual bot-driven gameplay: `build/streak-live.Qhe7IF/`. All 33 frame pairs
  passed file integrity and exact 3× presentation checks. The saved replay's
  final result and every captured simulation checksum verified, with captured
  source files unchanged during the run. Several frames were visually inspected.
  These busy samples still suppressed the nonessential streak plate through the
  existing world-label arbiter; the staged QA, not those samples, establishes
  the combined message's visible typography and expiry.

Reproduce focused checks with `SUITE=main bash tools/run_tests.sh`. The QA tool
is `tools/capture_streak_readability.gd`; run it through
`tools/playtest_newcomer.sh` with a fresh `SHOT_DIR`, a real compatibility
renderer and `--fixed-fps 60`. Verify the live take using
`python3 tools/verify_store_gameplay.py build/streak-live.Qhe7IF`.

## Remaining work

This is a targeted reduction in reward clutter, not proof of human comprehension
or complete visual polish. Longer compound encounters, co-op, text scaling,
sector distinction and observed newcomer sessions remain part of acceptance.
Existing Steam screenshot drafts and native candidates predate this presentation
repair; retain them as historical evidence and refresh final media/builds after
the visual work stabilizes. No Steam publication or rights approval is implied.
