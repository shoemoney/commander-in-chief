# Recovery clarity pass

## Finding and repair

The actual Mac opening displayed `FEED THE WAR CHEST TO REVIVE` with an empty
chest. The simulation instead grants a free checkpoint rally in campaign while
reinforcements remain. The same unconditional hint also advertised payment in
the finale, after the reinforcement budget was spent, and after recovery.

The existing first-time recovery hint now reads current simulation rules at
display time. It names the free checkpoint rally, the actual paid revive price
and live binding, the terminal last-breath state, or the finale's no-revive rule.
It disappears after recovery, victory or wipe, releasing the objective's display
slot. Co-op chest changes and partner deaths update the same visible hint.
No simulation values, economy, damage, controls or difficulty were changed.

## Game-design skill evaluation

- Clarity: explain the available recovery, not an unconditional paid action.
- Motivation: retain the existing money-versus-position decision; do not create
  new rewards or penalties.
- Response: preserve input handling and remove obsolete teaching immediately.
- Satisfaction: retain existing death/revive sounds and body/HUD feedback; this
  change adds no extra effects or overlapping notification channel.
- Fit: keep the existing compact arcade vocabulary and first-time teaching slot.

Presentation enters through the real `player_down` event and the existing hint
queue. Its existing lifetime and threat priority are unchanged. Rendering
re-evaluates affordability and recovery rules; no downed player means no recovery
message. Last Stand, exhausted reinforcements, solo endless, a surviving co-op
partner and a subsequent partner death have explicit coverage. There is no
additional resource cost or gameplay state transition.

Assumption: the existing detailed HUD/body countdowns remain available beneath
the short teaching cue. If players still cannot explain the recovery outcome,
review the naming and placement before changing prices or wait times. No new
numeric tuning values are proposed.

## Evidence and acceptance

Three new regression methods reproduced ten failed assertions before the fix.
They inspect the text selected by the real band layout, including changes while
visible, the rebound key and objective-slot release. An existing source-text
test was narrowed to its full persistent-finale banner string so it does not
mistake the new shorter teaching message for that banner.

`tools/capture_recovery_clarity.gd` produced three distinct, nonblank real-renderer
captures in `build/recovery-clarity/`; all were opened and inspected. These are
staged QA states, not unscripted gameplay or storefront screenshots. Text fits
the screen and matches each HUD/body countdown or price at the default text size.

Human acceptance remains open: from a fresh profile, let a first-time player
lose a life with an empty chest, then with enough money. Ask what happens next
and what action is available. Repeat with a partner, then in endless and the
finale. Pass only when the explanation matches the actual recovery; do not count
prompt presence or automated tests as human comprehension. Stress shared-chest
spending/earning while downed; verify no stale price, rescue promise or control.

Final full regression run: **1,206 methods, 38,323 assertions, zero failures**;
the isolated wrapper's shutdown-leak gate passed. Additional checks prove a
resolved hint releases queued teaching and that recovery completed before
delivery does not consume the profile's first-time hint. gda validates the main
script and capture tool with no diagnostics.

The native candidate in `native-quit.RiCCuf` predates this later wording repair.
Do not treat that archive as containing these new messages.
