# Audio Residue Triage — 2026-08-03

Five findings were addressed in commits 13406bb, 10be0a4, and 372cef2. The remaining 11 have been re-verified at HEAD.

| Finding | File | Verdict | Evidence | Still Worth Doing? |
|---------|------|---------|----------|-------------------|
| R3-main #1: Combat drums under debrief | src/main.gd | FIXED | Line 5921: `if sim.wiped or sim.victory or _debrief: intensity = 0.0` — the run-ender guard now silences drums | No — resolved |
| R3-main #2: `kill` bulk event no gate (5 blips on one frame) | src/main.gd | FIXED | Lines 2310-2311 initialize `_kill_blip_pitch = 0.0` and `_kill_yells = 0` per tick; blip deferred to 3247-3248 at final pitch; yells gated at 3806 to `< 2` per tick | No — resolved |
| R3-main #3: Campaign victory never stops fight | src/sim/sim_world.gd | OPEN | Line 1034: still only `if wiped: return` — no victory counterpart. Spawner keeps feeding, enemies keep firing behind victory card | Yes — enemy sim still steps post-victory |
| R3-main #4: Victory voice captions hidden | src/view/hud.gd | OPEN | Line 1735: `_result_card_up()` returns true when `s.victory` is true, suppressing strip. Captions armed at src/main.gd:3245-3246 but never painted | Yes — deaf/HoH player gets no victory callout |
| R3-main #5: Last-stand heartbeat on defeat card | src/main.gd | FIXED | Line 5952: `var want := 1.0 if sim.last_stand and not sim.victory and not sim.wiped and not _debrief else 0.0` — heartbeat now fades on wipe | No — resolved |
| R3-main #6: 12 sandbag_break clips at once | src/main.gd | FIXED | Line 2303: `var bag_broke := false` initialized; line 2405-2410: `if kind != "sandbag_break" or not bag_broke:` gates sound, then `bag_broke = bag_broke or kind == "sandbag_break"`. FX still per-bag (12 puffs read as crumble) | No — resolved |
| R3-main #7: main._vo stamps throttle before Sfx.play_vo drops | src/main.gd + src/view/sfx.gd | OPEN | Line 3375-3376: `_vo_last[key] = now` still stamped before calling `play_vo()`; play_vo has four silent-drop paths (sfx.gd:449, 461, 465) but no return value to signal drops. Last-Stand and pilot plea one-shots burned out | Yes — core VO line silent-locked under barks |
| R3-main #8: Pause leaves tank engine loops | src/main.gd | FIXED | Lines 2175-2176 in pause branch: `for ti in sim.tanks.size(): _sfx.engine_at(ti, Vector2.ZERO, false)` — engines faded on pause | No — resolved |
| R3-sfx #1: `if _cmd.playing: return` priority-blind | src/view/sfx.gd | FIXED | Lines 499-502: `if _cmd.playing:` now checks `if priority >= 2:` and parks pending VO instead of dropping. Flavor/warning lines (0-1) still drop; one-shots (3) and denials (2) survive as pending | No — resolved |
| R3-sfx #2: caption_sfx arms during splash + title attract | src/view/sfx.gd | OPEN | Line 723 `caption_sfx()` has NO `_startup_audio_locked` gate. Called from main.gd:2428 under title-only guard but still fires behind splash. SFX_CAPTIONS lethal entries arm for muted demo audio (sfx.gd:738). Line 2363 guards with `_menu.mode == GameMenu.Mode.HIDDEN and _splash_t <= 0.0` but caption_sfx has no such check | Yes — lethal captions lie on splash |
| R3-sfx #3: Death yells no cooldown (cluster scream chorus) | src/main.gd | FIXED | Line 3806: `if not _METAL_KINDS.has(kkind) and kkind != "colossus" and kkind != "broadcast" and _kill_yells < 2:` — two per tick max. Line 3807 increments counter; counter reset at line 2311 per tick | No — resolved |
| R3-sfx #4: Caption queue only drains while strip painted | src/view/sfx.gd | PARTIAL | Line 711-720: `clear_captions()` exists and is called from main._reset() at 1490 — new runs don't inherit backlog. BUT: no "stale_after" mechanism; expired captions (paused for 5 minutes, whole session with captions OFF) still sit in queue until manually drained. Queue filling during paused/debrief/menu branches is addressed by clear_captions, but inter-run staleness is not | Conditional — clear_captions solves new-run leak; session-long stale entries still queue |
| R3-sfx #5: Interrupt doesn't retire caption | src/view/sfx.gd | FIXED | Lines 516-521 in play_vo interrupt path: `_drop_vo_captions()` called before preemption. Function defined at 579-590, blanks live caption and purges is_vo entries from queue | No — resolved |
| R3-sfx #6: VO mid-word replayed afterwards | src/view/sfx.gd | FIXED | Same `_drop_vo_captions()` call — interrupted VO caption is retired, not queued to return | No — resolved |
| R3-sfx #7: Splash caption unreadable on skip | src/view/sfx.gd | PARTIAL | Lines 238-239: play_startup_line now calls `_arm_caption(...)` — caption armed. BUT: comment at 233-237 labels this a "HALF A FIX" — hud._draw_caption returns early on `main._menu.is_active()` (hud.gd:1755), and _end_splash opens TITLE menu, so caption is armed but NOT PAINTED. Only SFX owns arming here; HUD exception needed | Yes — caption disabled during title on skip |

## Summary

- **Fully resolved (9):** main #1, #2, #5, #6, #8 + sfx #1, #3, #5, #6
- **Still open (5):** main #3, #4, #7 + sfx #2
- **Partially complete (2):** sfx #4 (clear_captions added but stale mechanism missing), sfx #7 (caption armed but not painted during title)

**Highest-confidence worth-doing:** main #3 (victory freeze), main #7 (VO throttle), sfx #2 (caption_sfx gate) — these are determinate bugs affecting core audio routing. Main #4 (victory captions) is a narrow fix (one line in _result_card_up) but affects accessibility. Sfx #4 and #7 are edge cases with existing partial mitigations.
