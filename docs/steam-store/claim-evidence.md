# Store claim evidence

These are implementation references, not third-party endorsements or platform
certification. Paths below are repository-relative. Recheck against the final
release revision; line numbers are intentionally avoided because this tree is dirty.

| Supplied claim | Current source evidence | Qualification |
|---|---|---|
| Top-down vertical shooter | `project.godot` description; `src/main.gd` rendering; `src/sim/sim_world.gd` camera and combat | Actual game genre, not a licensed remake claim |
| Fictional political-satire setting | `ASSETS.md` owner-decision record; `assets/vo/README.md`; `src/main.gd::_draw_one_gunship` and Colossus faction-banner rendering | Describes the game's framing; no assertion about real military events or endorsement |
| Shared War Chest buys supplies and revives | `SimWorld._try_buy`, `_try_revive`, `supply_price`, `standups_exhausted`, `last_stand` | Revives have mode/budget limits; never described as unlimited |
| Six-sector campaign and no-revive finale | `SimWorld.FINAL_GATE_INDEX = 6`, campaign gate construction, `_try_revive` last-stand guard | No invented campaign duration |
| Independent aim and automatic MG | `Main._gather_inputs`, `SimWorld._step_players` | Cannon is a separate, edge-triggered grenade action |
| Tank driver and gunner | `SimWorld._drive_tank`, `_ride_as_gunner`, `_try_board_tank`; `tests/test_tank.gd` | Local seat behavior; physical-device acceptance remains open |
| Endless and Veteran Perks | `Main.start_game(true)`; menu `perks` activation; `tests/test_endless_meta.gd` | No paid progression or monetization claim |
| Arcade, chapter select, Boss Rush | `Main.start_arcade`, `start_boss_rush`; menu `_activate` | Playable menu paths also exercised by `tools/e2e_playthrough.gd` |
| Daily challenge | `Main.start_daily`, `_daily_seed`, `_daily_locked`, `_reset` | System-local date and profile; not a globally synchronized or tamper-proof competition |
| Local two-player co-op | `Main._two_players`, `_gather_inputs`; menu `coop` setting | Player two is controller-based; no online co-op |
| Local Hall and last-run replay | menu `watch` / `_watch_last_run`, `Main._record_run`, `src/net/replay.gd` | Last recorded run, not a replay library or full video capture |
| Presentation/control options | menu `_settings_rows`, rebind views; `Main._set_text_scale`; `Sfx.active_caption` | Captions are supported cues, not independently verified verbatim subtitles for every randomized recording |
| Blood, bodies and combat audio | `Main._ev_kill`, corpse/blood-pool rendering and blood-wash path; `assets/audio/*/README.md` | Full-build listening/content review remains required |
| Pre-generated artwork and speech | `ASSETS.md`; troop generation note; voice folder records; `docs/steam-hero-validation.md` | AI disclosure is required for this content; rights status is a separate review |

## Claims deliberately held

- Steam achievements, leaderboards, Cloud, Input and presence: source/native API
  checks exist, but intended-AppID live acceptance is unproven.
- Full controller support, Steam Deck/Proton certification, cross-platform minimum
  specs: not established by local source tests or export success.
- Spanish, French and Japanese store support: translation resources exist;
  completeness, voice language coverage and localization QA are not established.
- A licensed remake, wholly original/owned assets, permission to imitate a voice:
  no blanket clearance established by the inspected provenance records.
- Online co-op and the production plan's later features: planned, not shipped.
- Awards, a 10/10 rating, viral reach, sales and audience statistics: no evidence.

## Recorded verification baseline

The prior gameplay pass completed 1,211 test methods / 38,355 assertions and the
80-check real-scene E2E. See `docs/cannon-feedback.md`. This document does not
reinterpret those checks as external player acceptance or launch approval.
`docs/PLAN.md` explicitly distinguishes implemented modes from its unfinished
human, platform and localization acceptance requirements.
