# Title-menu clarity

## Observed problem

The freshly exported macOS app displayed the attract demo's `GATE SECURED`
receipt above the game logo. A matched, staged real-renderer capture reproduced
the same problem. The demo's combat progress appeared to be part of the menu,
even though the user had not started a run.

## Change

The live title demo still renders its battlefield, units, projectiles and world
effects. Its screen-anchored combat overlay pass is skipped while the menu is
in `TITLE` mode, and the invisible combat message band no longer reserves space.
Actual gameplay and pause retain their existing presentation. No queued events
are deleted; no simulation, controls, difficulty, rewards, assets or voices changed.

This deliberately does not hide every battlefield label or alter submenus. It
removes the specific combat overlay layer competing with the title. The prior
native candidate and trailer remain historical artifacts; the candidate predates
this title-only source change.

## Skill-guided design decision

- Clarity: title navigation belongs to the user; demo combat results do not.
- Motivation: preserve the moving gameplay preview without implying earned progress.
- Response: all menu controls and input timing remain unchanged.
- Satisfaction: retain combat effects and existing menu sounds; add no new effect channel.
- Fit: preserve the arcade attract screen and the existing visual identity.

The game-design priority of clarity before balance tuning guided this change.
The game-feel guidance on excessive feedback favored removing competing overlay
information over adding more animation or flashes. This is a presentation gate,
not a player-state transition. It enters only at `TITLE`, exits on leaving that
mode and consumes no resource. There are no new numerical tuning values.

Assumption: players should distinguish the title menu from an active run without
needing to interpret combat messages. If that remains unclear, test menu copy and
background treatment before changing the combat simulation.

## Evidence

- `tests/test_view_honesty.gd::test_title_demo_does_not_claim_gameplay_message_space`
  failed two assertions before the repair: checkpoint and airstrike rows both
  appeared in title mode. After repair the focused suite passes, including
  preservation of queued events, the simulation checksum and gameplay/pause text.
- Staged baseline: `build/title-before.seYt9K/01-title.png` and `02-gameplay.png`.
- Staged repaired pair: `build/title-after.xF812z/01-title.png` and `02-gameplay.png`.
- Both pairs were rendered through the real scene. The before/after title images
  were opened and inspected; the checkpoint text no longer appears above the logo.
  The repaired gameplay image was also opened, with the checkpoint message present.
- `cmp` confirms that the before/after gameplay PNGs are byte-identical.
  Shared SHA256: `de24f6fc417242ef0b4cc5b95892dcd23b8911d50954c7361bd2f59ab8c62ce1`.
- Capture logs report two nonblank, unique images and clean exit for each pair.
- The real-scene menu/input E2E passes all 80 checks, including title-to-campaign,
  title-to-endless, setup/submenus, pause/resume, two-press quit-to-title and a
  subsequent gameplay drive. No script errors or shutdown leaks appeared.
- The final full suite passes 1,215 methods and 38,447 assertions, with zero
  failures and a clean shutdown gate (`build/title-after.xF812z/full-suite-final.log`).
  The first full run failed only its two README live-count checks; the README
  count was updated and the entire suite rerun successfully.

These are staged QA images, not storefront gameplay screenshots or proof of
human comprehension.

## Human acceptance still required

From a fresh profile, leave the title open through a demo checkpoint and a boss
encounter. Ask a newcomer whether a run has started and how to begin. Start
Campaign, then pause and resume during a warning. Confirm that the player can
explain the active warning and that it returns on resume. Stress repeated
title/start/pause transitions and submenu navigation. Fail if demo receipts
compete with the logo, gameplay alerts disappear, or navigation changes the run.
No input, resource or progress advantage should arise from opening a menu.
