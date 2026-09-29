# Cannon response and contextual controls

September 7, 2026. Local source verification on `cf23387` plus the existing dirty
tree. This pass does not establish a 10/10 rating, human playtest acceptance or
Steam launch readiness.

## Player-facing defects and repair

A driver pressing the grenade/cannon button with no shells or during reload
received no immediate feedback. The on-foot dry-throw feedback explicitly
excluded riders. The HUD showed stock and cooldown passively, but never
acknowledged the failed tank input.

The simulation now emits a presentation-only `cannon_deny` event for an actual
refused driver press. The view plays a short click and highlights that driver's
shell count. Empty and reload clicks have different pitches. Purchases, seat
selection and bailout resolve before this event, so a same-tick refill followed
by a successful shot cannot produce a false empty warning. Held buttons do not
generate new attempts. Weapon timing, ammo cost, movement and damage are unchanged.

The first rendered QA pass also exposed on-foot ROLL/GRENADE reminders while
driving. The transient reminder now names CANNON on the existing grenade binding
for the driver, omits roll and cannon for the gunner, and yields during burning
or downed states. On-foot reminders return on dismount only if still untaught;
seat changes do not reset the teaching timer or saved mastery. The reminder and
its reserved rectangle use the same contextual segment list.

README controls now distinguish automatic MG fire from the manually triggered
cannon. The ghillie entry also names its actual close-range/laser counter window
instead of suggesting a grenade flush against a cloaked, blast-immune enemy.

## Game-design skill evaluation

- Clarity: tell a driver whether a rejected attempt means empty stock or reload;
  label the actual vehicle verb, not an unavailable hand throw or roll.
- Response: acknowledge a real input edge without adding lockout or changing the
  existing unbuffered cannon rule. Dismount retains priority over firing.
- Satisfaction: brief sound plus a visible stock highlight. Successful shots
  keep their existing recoil, projectile and sound without refusal feedback.
- Fit: reuse the game's existing empty/early grenade click grammar. No new
  dialogue or intrusive center-screen banner.
- Motivation: preserve shell conservation and refill choices; no economy tuning.

Starting presentation values reuse the existing on-foot grammar: 14-frame
per-seat audio throttle; empty/reload highlights last 12/8 frames respectively.
The highlight is steady while active, including with Reduce Motion enabled.
Human test: repeated taps should be acknowledged without masking incoming-shot
audio; empty and reloading should be distinguishable from successful firing.
If missed, increase highlight duration first. If the click masks threats, reduce
its volume before altering weapon rules. These remain starting values, not
validated human-comprehension thresholds.

## Verification and reproduction

Before implementation, tank tests reproduced both missing denial events and the
view test reproduced missing audio/flash. The repaired focused tank, main and
HUD suites pass. Tests cover empty stock, the final reload tick, held input,
successful fire, same-tick buying, gunner input, bailout priority, independent
seat feedback, duplicate throttling, reminder geometry and dismount/death states.

Final verification: the full suite passed **1,211 methods / 38,355 assertions**,
zero failures, with the isolated wrapper's clean-shutdown gate. The real-scene
E2E passed all 80 checks. gda reported `valid: true` with no diagnostics for all
seven changed/new scripts. Determinism and asset lints passed; golden checksums
were not changed by this pass. `git diff --check` passed. An intermediate full
run failed only the two stale README method-count checks, now updated and green.

Actual-renderer captures (staged QA setups, **not store gameplay screenshots**):

- Earlier `build/cannon-feedback.Id1VQF/` preserves the incorrect on-foot reminder.
- Corrected `build/cannon-feedback.ypqQQ4/01-cannon-empty.png` shows red empty stock.
- `02-cannon-reloading.png` shows the amber stock acknowledgment and reload ring.
- `03-cannon-ready.png` shows the successful shell with no refusal flash.

All three corrected images were opened and inspected. Each setup submits a real
grenade input to `SimWorld.step`, then consumes its actual event through Main;
no fabricated denial event is injected by the capture harness. Captures ran with
Reduce Motion and an isolated profile, and exited cleanly. Sound dispatch and
pitch distinction are tested with a spy; in-combat human listening is still open.

Reproduce with `tools/capture_cannon_feedback.gd` through
`tools/playtest_newcomer.sh`, using a new writable `SHOT_DIR`, the compatibility
renderer and fixed 60 FPS. Use `tools/run_tests.sh` for the full regression suite,
`SUITE=tank`, `SUITE=main` or `SUITE=hud` for focused tests.

## Remaining acceptance

Observe a newcomer boarding, identifying the cannon control, attempting an early
shot, refilling and firing successfully. Repeat with both local seats, alternate
bindings, sound off and Reduce Motion. Ask what prevented the failed shot without
coaching. The automated checks and staged renders do not substitute for this.
Fresh platform exports and live Steam checks are still required; earlier native
candidates do not include this source change.
