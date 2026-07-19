# KK3 — Project Ikari: Consolidated Adversarial Review

**Date:** 2026-07-19 · **Method:** 10 parallel adversarial reviewers, each owning one lane (sim core, netcode/replay, view/shaders, feel/HUD/menu, design/balance, testing/QA, build/export, assets/legal, repo hygiene, architecture). 100 raw items → **47 distinct defects after dedupe**: 5 P0, 18 P1, 24 P2. Every item below was verified against file:line evidence by at least one reviewer; items found independently by multiple lanes are marked Ⓜ.

**P0 = fix before anyone else touches a build. P1 = fix now, this cycle. P2 = real, schedule it.**

---

## 🔴 P0 — Stop-ship

### P0-1. The CI pipeline has never run — it's committed to `tools/ci.yml`, not `.github/workflows/` Ⓜ (QA, Build, Hygiene)
A complete cross-arch (x86_64 + arm64) determinism CI exists at `tools/ci.yml:1-22` — GitHub only reads `.github/workflows/`, and there is no `.github` in the repo. Meanwhile `tests/test_determinism.gd:5-6` and `src/sim/sim_world.gd:4844-4845` claim in comments that "CI runners are the cross-arch determinism proof," and `README.md:18` ships a "bit-identical x86_64⇄arm64" badge while `README.md:30` admits there's no CI. Goldens have been **re-recorded 47 times**, each on one machine, with zero automated cross-arch verification. The flagship claim the lockstep netcode is built on is enforced by nothing.
**Fix:** `git mv tools/ci.yml .github/workflows/ci.yml`, gate merges on both-arch agreement, correct the comments/badge until green.

### P0-2. The shipping builds are unsigned — macOS ad-hoc/unnotarized, Windows fully unsigned
`export_presets.cfg:11-18,44-45` has zero signing config. Verified on the artifacts: `build/ShoeMoney Soldier.app` is `flags=0x2(adhoc)`, no Team ID; `ShoeMoneySoldier-windows.exe` "is not signed at all." Gatekeeper blocks the Mac build ("damaged"), SmartScreen blocks the exe. **Every build currently in `build/` is undistributable.**
**Fix:** Developer ID + hardened runtime + `notarytool` for macOS; Authenticode cert (+ `signtool`/`osslsigncode`) for Windows, wired into presets.

### P0-3. "AI生成" watermark scrubbed from the shipping soldier sprites — while the README claims no gen-AI art ships
Commit `9744e6f` documents deliberately scrubbing a burned-in "AI生成" watermark from the purchased infantry set pack — the hero and all enemy infantry sprites (`src/view/art.gd:30-45`) — yet `README.md:292-294` declares "No generative-AI *art* ships… VO is the one sanctioned exception." Scrubbing provenance watermarks can itself violate vendor license terms, and the public claim is factually false for the most visible sprites in the game.
**Fix:** Get written license confirmation covering watermark removal/AI-derived content, correct the README, drop the license text into `assets/soldiers/`.

### P0-4. Proprietary legacy art assets are baked into git history and into the extractable pck Ⓜ (Assets, Build)
`assets/legacy-art/` = 448 files across 42 commits; `.git` is 414 MB. README says "clear before going public" — but deleting at HEAD doesn't clear history; every clone redistributes them. They also ship in the pck (`export_filter="all_resources"`, `export_presets.cfg:6`) with **no license file anywhere in the tree**. Repo is private *today*; one visibility flip or shared zip is a EULA violation.
**Fix:** Decide now: private-forever as documented policy, or history rewrite (filter-repo/BFG) + LFS/submodule split. Add license text; plan pck encryption or strip legacy art sources before any public demo.

### P0-5. (None — the sim itself held. The deterministic core survived its adversarial read with zero P0s.)

---

## 🟠 P1 — Fix now

### Economy & design

**P1-1. The death economy is regressive — "stay broke, die free" is the dominant strategy** `sim_world.gd:1236-1300, 1504, 4456`
Dying broke = free checkpoint respawn **with full MG 99 + 12 grenades restocked**; dying rich = forced 25–150¢ payment for the identical respawn — no "wait for free" option. Buys are score-neutral vs banking. Optimal play: dump the chest, stay under `revive_cost`, die free forever. Pillar 4 ("Death is a transaction", PLAN.md:22) never occurs for a score-chaser.
**Fix:** Always arm `broke_timer`; free path = 5s checkpoint *without* restock (or restock at score cost).

**P1-2. Rich deaths can't end or be recorded — endless & co-op revive traps** `sim_world.gd:1242-1253, 1280-1300`
`wiped` (only run-ender + only path to the Hall record) requires `broke_timer`, armed only on poverty. Die rich in endless and never press E: no wipe, no debrief, no record — skilled players must *engineer poverty to bank a run*. In co-op, self-revive is hard-blocked while a partner lives: dead player + AFK/griefing partner + rich chest = permanent spectate; rich double-down never wipes.
**Fix:** Concede/bleed-out path that still records; no-questions revive timeout (~10s); double-down latches `wiped` on a timer.

**P1-3. Enemy-stepped mines mint full player coin — the exploit barrels explicitly guard** `sim_world.gd:2713-2715` vs `:2766,2776`
Barrels pass `no_coin=true` ("enemy-suicide farm" guard); the mine path was left paying full War Chest coin/score/streak. Sappers seed up to 40 mines in endless = passive zero-agency income on the leaderboard mode. One-argument fix (`not m.get("friendly", false)`), complicated only by player claymores sharing the `mines[]` array.

**P1-4. Sandbag field cap counts untagged world bags — endless's own shop slot is dead from tick 0** `sim_world.gd:1484-1488, 559-564`
Endless plants 16 pre-placed bags with no `"world"` marker; `player_bags = 16 ≥ SANDBAG_FIELD_CAP 6`, so the 40-coin sandbag buy — the mode's documented rebuild loop — is denied "cap" until 11 bags are destroyed. Campaign boss/fork/vault bags erode it too.

**P1-5. Finale exploit pair: Colossus is cheese-able by a guaranteed tank, and Last Stand is the best score farm in the game** `sim_world.gd:4426-4429, 4672-4677, 571, 3724-3726, 2117-2120, 681-682`
Everything the Colossus does skips tanked players (bullets, crush); a tank spawns 250px from the arena with 1200t fuel → 11s zero-risk kill, voiding the "grenades only, no revives, one-hit tension" contract. Meanwhile `last_stand` pays 2× score while the field spawner keeps pouring adds every 24t with no enrage/timer/cap — Hall-of-Fame optimal play is "park the finale forever."
**Fix:** Colossus damage ejects/damages occupants (or bar tanks from the final segment); stop the spawner or the 2× bonus once `last_stand` latches; add a soft enrage.

### Determinism & netcode

**P1-6. Replay/run identity is incomplete — replays silently play the wrong run; lockstep peers desync from tick 0** Ⓜ (Sim, Net, QA, Arch) `replay.gd:27-29,71-78; main.gd:863-867, 835-840; replay.gd:12`
Assist mode (vest every life) and NG+ hard (spawn curve, 1.5× boss HP) change the sim from tick 0 — and are in neither the replay header nor any lockstep config. "Watch Last Run" after toggling assist = different run, zero warning. Additionally the replay format has **no sim/build version** (`IKARI_REPLAY_1` versions the container only): a replay from build N misplays silently on build N+1 — fatal to the documented bug-report-repro, audited-trailer, and PLAN.md:127 anti-cheat uses.
**Fix:** Put `assist/hard`/starting vests/`sim_version` into the replay header + `SimWorld._init` identity; refuse or warn loudly on mismatch.

**P1-7. Replay files and lockstep payloads are validated at the envelope only — crafted input = crash or OOM** Ⓜ (4 lanes) `replay.gd:52-64; sim_input.gd:34-46; lockstep.gd:62-63`
`load_from` checks top-level keys then copies `frames` blind (its own comment claims full validation); `SimInput.decode` indexes `data[0..4]` unguarded — short/corrupt frames error every physics frame of the watch loop; `"players": 99999999` OOM-hangs `Replay.play()`. Same blind path for live wire packets. PLAN.md:127's replay-resim anti-cheat service is exactly where a hostile file lands.
**Fix:** Recursive validation in `load_from` + ingress validation in `receive_remote_input` (clamp players 1..2, whitelist mode, every frame = N×5 ints); malformed-frame tests.

**P1-8. No lockstep session handshake — mismatched delay/flags = guaranteed desync + deadlock** `lockstep.gd:32-43, 62-86`
Nothing exchanges seed/mode/players/`input_delay`/assist/hard/build before tick 1. delay 3 vs delay 5: one peer steps empty ticks while the other stalls forever — certain divergence plus a half-locked session, first signaled at tick 60 with no diagnosis.
**Fix:** Pre-start handshake `{seed, mode, players, delay, assist, hard, sim/build hash}`; refuse to arm on mismatch.

**P1-9. Packet loss = permanent silent wedge; latency only ratchets up; desync machinery is inert** `lockstep.gd:49-59, 71-77, 99-108`
No stall timeout/disconnect/resync (`stalled_ticks` is read only by tests; the docstring's "host-snapshot resync" exists nowhere). `submit_local_input` schedules inputs unboundedly far ahead — after any stall, input latency is permanently inflated. On checksum mismatch the only consequence is a sticky boolean — both divergent worlds keep stepping. Companion traps: `checksum_at()` returns 0 for unreached ticks (false-desync), duplicate/retransmitted packets leak buffer memory.
**Fix:** Back-pressure cap on `_next_local_tick - sim.tick_count`; stall watchdog; gate advancement on `desynced`; sentinel for unknown-tick checksums; implement or delete the resync promise.

**P1-10. The desync detector is half-blind, and its tripwire only catches added — not deleted — feeds** Ⓜ (Sim, QA) `sim_world.gd:4842-4972; tests/test_checksum_coverage.gd:17-73`
`checksum()` omits aim, grenade cd, roll dir, bullet velocities, boss/colossus cadence timers; conditional feeds mean `{P1.cd=5,P2.cd=0}` and `{P1=0,P2=5}` hash *equal*. The coverage test never records which fields are HASHED vs EXCLUDED — deleting a feed for a torture-inert field (`vest_buys`, `flush_cd`, `smoke_ticks`) moves no golden and no tripwire. Golden runs never exercise assist/hard/shop buys/vents/colossus/endless boss/**solo at all** — same-machine A==B tests can't catch a cross-arch float.
**Fix:** Unconditional constant-length feeds; HASHED/EXCLUDED split with static feed verification; goldens for assist-ON, hard-ON, forced-buy, staged colossus window, 1P.

### Player-facing

**P1-11. The view lies about sim geometry in three places — in a one-hit-death game** Ⓜ (View, root cause also Architecture) `main.gd:4856-4907, 507, 3975-3990; sim_world.gd:3219-3226, 1112-1130`
(a) The collapsing bridge/ford is closed ~70% of the time on band ≥2 — the view draws sand, deck, and a reassuring "FORD" label unconditionally: invisible slow + sideways shove. (b) The water shader's ford hole is cut at the untightened 32px constant while the sim tightens to 16px — margins show "dry" grass that sims as deep river. (c) Choke rubble draws only the first of two dog-leg bites, anchored south of the real bite. Root cause: the view **hand-mirrors sim collision formulas** under a "keep in sync" comment with no parity guard (`main.gd:4847-4851`).
**Fix:** One authoritative geometry/phase helper shared by sim and view; parity test walking bands.

**P1-12. Per-tick VO duck silently stomps the player's SFX volume to full — and persists the lie** `sfx.gd:203-210; main.gd:2546-2553; menu.gd:1004-1005`
`duck_sfx_under_vo(false)` lerps the bus toward hardcoded `0.0` dB every tick; any user setting below 10 is ramped to full, OPTIONS then shows "SFX: 10", and the next settings save persists it. A level-3 user gets audio *boosted* during VO. Silently breaks a shipped comfort setting and rewrites the user's config.
**Fix:** Duck relative to the configured level (`base_db − 6`), restore to `base_db`.

**P1-13. Run-reset state leaks: dead HUD pulses and phantom tank engines** `hud.gd:61-66,134-152; sfx.gd:364-386; main.gd:847-942`
`_prev_score/_prev_chest` survive `_reset` — after a big run, the kill-mints-coin gold flash (the economy's core feedback) stays dead all next run and the chest counter visibly rolls *down*. `_sfx._engines` is never flushed — PAUSE → RESTART while riding a tank leaves the engine growling through the debrief into the next run.
**Fix:** Snap baselines on sim-instance change (the `_shop_sim_id` pattern already exists two functions away); `Sfx.stop_all_engines()` in `_reset`.

**P1-14. The crash-safe save chain destroys its own backup** `main.gd:2406-2438`
`_persist` ignores the `cf.load(SAVE_PATH)` result — a corrupt file merges from empty and rewrites only the current sections, silently wiping `[best]/[hall]/[seen]`; `_save_cfg` then copies the corrupt file over the *good* `.bak`, so the `.bak` fallback can never fire. `copy_absolute`/`rename_absolute` return codes unchecked — a Windows AV lock drops the save silently. This is the game's only persistent progress.

### Engineering & QA

**P1-15. The test runner counts crashed tests as green; sim-purity lint and boot smoke are orphaned; the lint never scans `src/net`** `tests/run_tests.gd:57,63-71; tools/lint_sim.gd:16; tools/ci.yml:87`
A runtime error in a test method records zero failures and prints PASS (README admits it: "watch for SCRIPT ERROR lines") — and dormant CI greps only for `"FAIL"`. `lint_sim.gd` (catches `randf`/`Time.` in sim) and `smoke.gd` (the only thing that ever boots `main.tscn`) run only if a human remembers; `src/net/lockstep.gd` — determinism-critical — is outside the lint's scan dir.
**Fix:** Runner fails non-zero on engine errors; invoke lint+smoke from the runner or a hook; extend lint to `src/net`.

**P1-16. Exported pck ships the internal review harness, dev bridge, media, and skills** Ⓜ (Build, Assets, Hygiene, Arch) `export_presets.cfg:6-8,25-27,39-41`
`exclude_filter="tests/*,docs/*,tools/*"` only — `reviewer/`, `reviews/` (the LLM judge pipeline incl. verdict JSONs), `media/` (12 MB), `skills/goals/`, `tmp/`, `CLAUDE.md`, and `addons/godot_mcp/` (a 2,432-line remote game-driving bridge, autoloaded, inert only via debugger checks) all pack into the trivially-extractable pck. Builds are already being produced.
**Fix:** Allowlist `include_filter`, or extend excludes to `reviews/*,reviewer/*,skills/*,tmp/*,media/*,addons/godot_mcp/*,*.md`; strip the autoload behind an editor-only feature tag.

**P1-17. Version identity doesn't exist** `export_presets.cfg:16-17; project.godot (absent); tools/ (no build script)`
The only version string lives twice in the macOS preset; Windows/Linux have none; `project.godot` has no `application/config/version`; nothing in-game displays one. With lockstep coming, version mismatch = silent desync; the two hand-built artifacts can't even be told apart.
**Fix:** `application/config/version` as single source of truth; presets/tooling read it; git-tag releases. (No release pipeline exists at all — add `tools/export.sh` running `--export-release` for all three presets + manifest with hashes; Linux preset has never produced a build.)

**P1-18. `main.gd` is an 8,121-line god object fused to both neighbors — and lockstep has no seam to land on** Ⓜ (Arch; corroborated by View) `main.gd` whole; `main.gd:339-342, 1237, 4089-4101, 4334-4360; menu.gd (68 main._ accesses), hud.gd (17)`
169 functions owning sim driving, input, replay, persistence, audio, and the entire immediate-mode renderer; one scene, two nodes. The view calls underscore-private sim internals at 25+ sites *and re-implements `_in_water`* as a hand mirror; menu/HUD mutate main's private fields back through raw `main = self` references (85 sites; the test suite needs a duck-typed main stub). Every change carries an 8k-line blast radius with zero CI.
**Fix:** Extract collaborators (renderer, feel director, persistence, replay controller) behind narrow APIs; promote shared sim queries to public API; start with the self-contained 4,400-line `_draw_*` block.

---

## 🟡 P2 — Real, schedule it (24)

| # | Item | Where | One-liner |
|---|---|---|---|
| 1 | Boss phase thresholds ignore HP scaling — Colossus thirds mis-timed at 2P/hard; gunship cracks keyed to a maxhp recomputed at damage time (shifts on player death) | `sim_world.gd:4344, 4253-4262, 4608-4610` | Store spawn max HP on the boss dict; derive thirds from it |
| 2 | `_mix` overflows int64 for ~19% of `randi()` seeds — cross-arch claim rests on signed-wrap UB; `Fixed.div` truncates toward zero (left/up bias) | `sim_world.gd:969-971; fixed.gd:26-27` | Mask seed to 31 bits; floor-consistent div (or pin truncation in tests) |
| 3 | Tank-burn death bypasses the vest funnel — the only lethal path that ignores Flak Vest, hitting assist-mode players hardest | `sim_world.gd:1767-1769` vs `:1330-1341` | Route through `_hurt_player` |
| 4 | Buying a vest while vested silently charges the chest + bumps team price creep (the token path was fixed for exactly this; the coin paths weren't) | `sim_world.gd:1478-1508` | Deny loudly when `p["vest"]` |
| 5 | Commendation tokens are a shared pool — a partner's death burns your earned token; anyone spends the pair | `sim_world.gd:541-543, 1349-1353, 1454-1475` | Track per player |
| 6 | No friendly-fire flag despite PLAN promising "FF OFF by default" — barrels/claymores/tank-ignition one-shot partners; the shared chest pays the revive | `PLAN.md:61; sim_world.gd:2693-2697, 2075-2078, 2040-2042` | Gate player-sourced damage behind an FF flag |
| 7 | Doc-vs-ship mismatches: README says Technical dies to one shot (`TECHNICAL_HP := 3`); PLAN promises 6 zones/50–70 min + zone-scoped revive decay (shipped: 5 gates, flat ramp) | `README.md:141; PLAN.md:59,65-70; sim_world.gd:79, 614-622` | Correct the docs or the sims; track the gap |
| 8 | Replay write is non-atomic — crash mid-write truncates `last_run.replay` (the tmp/bak/rename pattern exists 100 lines away and wasn't reused) | `replay.gd:36-44` vs `main.gd:2419-2431` | Write tmp + rename |
| 9 | Replay suite is self-referential — zero committed replay fixtures despite PLAN mandating "every fixed bug adds a replay" | `tests/test_replay.gd:30-49; PLAN.md:123` | Commit one replay + checksums per past bug |
| 10 | Event-coverage tripwire only witnesses a 600-tick early window — `wiped/buy/gate_open/colossus_engage/victory/endless_boss` can never fire in it; tab-exact parser evadable by reindenting | `tests/test_event_coverage.gd:18, 32-33` | Staged late-game runs; function-boundary parser |
| 11 | Lockstep edge semantics untested (unknown-tick auto-accept, duplicate overwrite) | `lockstep.gd:89-90, 103-104, 62-63` | Pin intended behavior in `test_lockstep.gd` |
| 12 | Stringly-typed event payloads — the coverage test guards event kinds, not fields; a `"cost"→"price"` rename silently plays the free-pip jingle for paid pickups; no `_:` default arm in the handler match | `sim_world.gd` (131 emit sites); `main.gd:1265-1876, 1334` | Typed events / required-key asserts per kind |
| 13 | Zero invariant checks in the 5.2k-line deterministic core — `step` silently pads short input arrays; the only two asserts in src/ are stripped in release | `src/sim`, `src/net` (grep = 0); `sim_world.gd:701-702` | Debug-only `_assert_invariants()` + `push_error` on input-count mismatch |
| 14 | `_update_feel` polls raw `Input` behind the input abstraction — and fires "NO TARGET" floaters during attract/replay playback | `main.gd:2938-2951, 1174, 1208` | Route through `_gather_inputs` edge state; gate to live play |
| 15 | Silent asset/audio failure paths — missing VO/sfx keys never warn; fossilized typo `vo_victoly` kept consistent across three files | `sfx.gd:98-102, 190-191, 227-228; main.gd:1875` | `push_warning` once per missing key; boot-time key check |
| 16 | Per-frame heap churn across the draw path (5×3 species table allocated per frame to read one row; dirt cards/threat dicts/submerged_pos rebuilt per frame) | `main.gd:4087-4088, 550, 7196-7198, 5244, 6108` | Const tables; reuse flat member buffers |
| 17 | Master grade pass never sleeps — permanent fullscreen `hint_screen_texture` backbuffer copy, even paused/menus (the concussion shader's own hide-when-idle discipline is documented but not applied) | `main.gd:387-393, 692-701` | Hide when identity; dirty-cadence param pushes |
| 18 | No cross-archetype y-sort (tanks < enemies < players always) + dead/off-screen slots sorted and drawn at full costume | `main.gd:3803-3815, 5251-5275` | One keyed actor sort; alive+on-screen filter before sorting |
| 19 | HUD re-plans its two-pass measure+draw layout every tick with no dirty check | `main.gd:8120-8121; hud.gd:284, 649-733` | Cache plan keyed on inputs |
| 20 | `_grade_breather` uses raw per-frame lerp — runs ~2× fast on 120/144 Hz (the exact bug two sibling files already documented and fixed) | `main.gd:700` vs `hud.gd:117-119, menu.gd:183-184` | `1.0 - exp(-k*delta)` idiom |
| 21 | Menu UX cluster: Hall-of-Fame wheel cycles filter instead of paging (runs vanish); volume rows are a one-way ratchet (no wrap on Enter/click); ambience beds ride the MUSIC bus (muting "music" kills wind/river/foundry); pause verb taught nowhere; back nav silent while destructive confirms play the *purchase* jingle; seed-arm has a hidden 2.5s timeout; held volume keys write the settings file ~8×/sec | `menu.gd:693-698, 672-676, 380-382, 405, 1560-1578, 704-708, 1016, 139-143, 175-182, 1004-1005` | Wheel→paging; wrap 10→0; Ambience bus; legend entry; neutral back tick + non-reward destructive timbre; visible countdown; debounced save |
| 22 | Asset waste cluster: md5-identical texture pairs loaded twice (VRAM ×2); ~40 dead/retired files still ship (legacy Kenney, retired insurgents); `mipmaps/generate=true` on 133/263 imports for a fixed 640×360 view; 2048² source PNGs imported at 128–512 caps (~4.5 MB of the 13 MB legacy-art tree) | `art.gd:102-175; test_assets.gd:24; *.import` | Dedup + delete dead set + standardize mip=false + bake at target res; extend `test_assets.gd` |
| 23 | Repo hygiene cluster: 410 MB `.git` (~7 revs of the same GIF, no LFS); `tmp/` not ignored (`tmp_*` pattern doesn't match; `tmp/mcp_smoke.py` is tracked); `__pycache__/*.pyc` tracked (in a dir whose script reads model gateway env); `.claude/` and private mode-700 `.remember/` unignored — one `git add -A` from a leak; personal `skills/goals/` staged in the game repo; naming split-brain ("Project Ikari" vs "ShoeMoney Soldier" in window title/exports/bundle-id); README/CLAUDE test counts 3× stale (159 → actual 472); PLAN references dead `/tmp` archive paths | `.gitignore:4,9; reviews/__pycache__/; skills/goals/; project.godot:13; README.md:17,213; PLAN.md:6,191` | LFS + history rewrite; fix ignore patterns; `git rm --cached`; move personal tooling out; pick one name; stop hardcoding counts; commit or delete the archive refs |
| 24 | Build/release cluster: builds are debug exports (169 MB unstripped binary, full symbols); stock Godot icon + empty copyright; CI verifies the Godot download hash on Linux only (macOS fetch unverified); no Linux artifact has ever been produced; no checksum manifest | `export_presets.cfg:5,24,38; tools/versions.lock:6-7; build/` | Release-template exports; icon+copyright; verify both runners; scripted pipeline with manifest |

---

## Suggested kill order (first 3 commits)

1. **`git mv tools/ci.yml .github/workflows/ci.yml`** + fix runner-green-on-crash + extend lint to `src/net` — every other fix lands blind until the gate exists. (P0-1, P1-15)
2. **Economy trap pack**: broke-respawn restock removal + rich-death concede path + mine `no_coin` + sandbag world-tag — four one-area fixes that repair the game's signature decision loop. (P1-1…P1-4)
3. **Ship-surface pack**: export exclude filter + replay identity header + payload validation + save-chain backup fix — stops leaking internals and makes replays/saves trustworthy. (P1-16, P1-6, P1-7, P1-14)

Then the P0 legal/build items (signing, legacy art/soldiers license resolution) before any external build, and the P1-18 architecture extraction before lockstep work begins.

*Raw lane reports: 100 items with full file:line evidence — session swarm output, 2026-07-19. Distilled by dedupe; multi-lane finds marked Ⓜ.*
