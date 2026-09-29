# Ten-item implementation and acceptance

This checklist follows the August review's ten implementation items. September's
checkout already contains substantial fixes; existing work is preserved. A completed
automated check is not evidence of a successful human playtest.

1. **Reachable threats:** retain `_rooted_spawn_y` placement and the camera-held
   Observer guard. Run spawn-cover, observer, and view-honesty suites. Verify rooted
   units in campaign gate arenas and Endless, including blocked spawn positions.
2. **Tank revives:** retain revive handling before the tank early return. Run controls,
   combat, and tank suites for driver/gunner, affordability, self/partner, and Last Stand.
3. **Remote rally:** show `RALLY Pn HERE price` at the reviver and remove the connecting
   path and directional rescue arrow. The neutral casualty marker identifies the absent
   partner. Preserve the existing rescue placement, exhausted-budget denial and self-revive.
4. **Honest purchases:** `supply_price(player, kind, catalogue=-1)` quotes the actual
   refill fraction. Round the coin debit upward to prevent splitting purchases for a
   discount. Wheel, crate display and debit use this helper. Full stocks still refuse,
   free crates stay free, non-quantity goods keep their price, and score uses actual spend.
   Existing event quantities drive receipts; capped salvage still preserves the hulk.
5. **Ready vote:** retain unanimous held input. Display the missing seat and progress
   from the simulation's actual `ready_hold`; resetting the hold resets the bar. Reserve
   the whole panel through the world-label arbiter. A downed player restores revive meaning.
6. **Safe shop:** retain the existing Observer intermission guard and strike cleanup.
   Verify a Spotter wave followed by an entire intermission and the return to combat.
7. **Finale feedback:** retain closed-core armor feedback, grenade boss-hit events,
   and siege-supply announcements. Verify visible and audible cues and damage consistency.
8. **Tank decisions:** retain slower travel, grenade-funded cannon, fuel lost on bullet
   impact and crew fuel tax. `probe_tank_choices.gd` compares paired seeds with boarding
   allowed/suppressed and reports survival, knockdowns, kills and occupied time. The
   current paired results do not establish universal dominance. No additional numeric
   nerf is justified by this instrument. Bot outcomes do not establish human difficulty.
9. **Text and controls:** retain centered measured labels, large-text manual paging and
   live-binding teaching prompts. Run menu-layout/localization/view-honesty checks and
   inspect screenshots at normal and doubled text size with a rebound revive key.
10. **Newcomer gate:** use the protocol below. Recruitment and observed results remain
    human work; do not mark this item passed using simulation or fabricated participants.

## Newcomer session

Launch `bash tools/playtest_newcomer.sh` for each participant. It creates and preserves
a fresh profile without touching the owner's settings, tutorial history or replays.
Record the printed profile location, revision and any dirty diff with each observation.
Use the same build for the whole cohort, normal campaign difficulty, and the participant's
preferred keyboard or controller. Explain only: “Start a campaign and advance.”

Watch without coaching until the first seawall encounter concludes. Record whether the
player can find their soldier, move and aim, identify a painted enemy shot, reach the
seawall and use a supply interaction. After each death, ask “What happened, and what
would you do differently?” Accept a specific accurate explanation, not merely “I died.”
Record confusion, replay/time marker, input device, assist/text settings and any help given.

Starting acceptance target: at least eight of ten unfamiliar players reach the seawall,
identify the rifleman's lane, complete the supply interaction and explain their deaths
without coaching. Record each criterion separately as well as the combined result.
If this fails, classify the observed failure first: missing cue, unclear input, or timing.
Repair cue/input problems before changing damage. For a demonstrated reaction-time
failure, trial an additional 30 opening grace ticks, then repeat with a fresh cohort.

Follow with paired co-op trials: one seat holds ready, both hold, one releases, then
revive from a tank and from across the field. Ask each player who must act and where the
revived player will land. Exercise a partial refill and capped salvage; ask what they paid
and received. Capture the Colossus closed/open core and supply arrival for observer recall.

Results template (one row per participant; leave unobserved fields blank):

```csv
participant,revision,profile,device,settings,seawall,lane_understood,supply_used,deaths_explained,coaching,combined_pass,replay_marker,notes
```

## Release verification

Run `tools/run_tests.sh`, both existing lint scripts, the real-scene E2E harness,
and GL screenshots. Require the complete pass line, no parse/runtime failures and the
repository's zero-leak exit gate. Determinism changes must be explained and reproduced;
do not replace golden hashes merely to clear a failure. Existing uncommitted knockdown
budget work belongs to its author and must stay intact. Human acceptance remains open
until the results above exist.

### Implementation verification (September 7)

- Full automated suite passed; focused economy, view-honesty and HUD checks passed.
- Real-scene E2E passed, including input, menus, restart and gameplay progression.
- Determinism and asset lints passed; no golden hashes were changed by this work.
- Fresh-profile launcher passed a headless boot smoke test. This is not a playtest.
- `capture_ten_items.gd` produced distinct, nonblank GL captures of split/both ready
  votes, a partial refill, remote rally and the doubled-size manual. Inspected each
  rendered case. Reproduce with an existing writable output directory:

  ```sh
  SHOT_DIR=/absolute/output/directory godot --path . --rendering-method gl_compatibility --fixed-fps 60 -s res://tools/capture_ten_items.gd
  ```

Verification also exposed a duplicate HUD CanvasItem allocation and a retained
custom cursor at shutdown. Both now release correctly; the screenshot harness
uses the shared quiet teardown, and the shell leak gate catches singular
“was leaked” diagnostics as well as plural ones. Final GL and E2E runs exit cleanly.
Human newcomer and co-op acceptance remains explicitly pending.
