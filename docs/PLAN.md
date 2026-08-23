# COMMANDER IN CHIEF — Game-Focused Master Build Plan
*A modern remake of Ikari Warriors (SNK, 1986): vertical scrolling, grenades-and-guys, power-ups, tanks, co-op — modern graphics, Steam-ready.*

## Context

You asked for a complete, end-to-end, step-by-step plan to build a modern Ikari Warriors remake and told me to focus **on the game itself** — you have IP/legal, market, and awards handled. This plan was produced by a 14-agent research workflow (8 parallel deep-research agents on the original game, engines, asset pipelines, and Steam; 3 synthesis agents; 2 adversarial critics; 1 reconciliation pass — 781k tokens, all contradictions resolved). Full research briefs were written to a scratchpad under `/tmp/` (`wf-result-*.md`, master plan in `wf-result-13.md`) — **they are not in this repo and that temp directory is long gone**, so this file is the only surviving copy of the plan.

**Scope note:** since you own IP strategy, this plan is written IP-agnostic — every mechanic works whether you ship licensed (*Ikari Warriors: Rage Reborn*) or as a spiritual successor. Where a decision depends on the license (names, 1986 Mode, original OST arrangement), it's flagged `[IP-dependent — your call]`.

---

## 1. The Hook & Design Pillars

> **The run-and-gun where the arcade quarter became the game: two players share one WAR CHEST — every kill mints coin; every revive, requisition drop, and airstrike spends it — across one unbroken vertical warzone with no loading screen.**

This modernizes the original's most legendary quirk: feeding coins to revive your buddy mid-fight. The War Chest is fully diegetic — shared on-screen counter, price tags on revives, hold-to-confirm spend wheel both players see.

**Pillars (dispute-settling order):**
1. **The loop lever, perfected** — twin-stick is the modern LS-30 rotary joystick; the gun must be the best-feeling in the genre.
2. **One continuous warzone** — a single unbroken scroll, no loading screens.
3. **Co-op is the design** — not a bolt-on. 1–2 players, everywhere, always (4P permanently out of scope).
4. **Death is a transaction** — one-hit kills stay; the War Chest makes death an economy, not a punishment.

---

## 2. Faithful Feature Inventory (what we honor from 1986)

Verified against the arcade original and NES port:

- **LS-30 rotary loop lever**: move in 8 directions, aim independently via 12-position rotary twist → modern twin-stick.
- **One continuous vertical map** through 3–4 terrain families (jungle/river → ruins/village → industrial → fortress).
- **Ammo economy**: machine gun capped 99; grenades are the *only* answer to armor, gates, bunkers, and submerged frogmen; fuel (GAS) pickups; death restores ammo but strips upgrades.
- **Power-up grammar**: red elite enemies drop upgrades — long range, speed shot, piercing red bullets, blast grenades, screen-clear fire mission.
- **Enterable tanks**: fuel timer, cannon draws from grenade stock, bail-out-before-explosion tension (we keep the death, fix the unfair timing).
- **Enemy families**: riflemen, red elites, flamers, frogmen, mines, light/heavy tanks, fixed turrets, infinite-spawn bunkers (until sealed), enemy helicopters, mortars.
- **The coin-feed revive** → becomes the War Chest.
- **No continues in the final stretch** → the Last Stand rule (§3): past the final gate, revives disabled, remaining coin converts to score.
- **The finale**: fight to the enemy HQ, bizarre final boss, rescue the general.
- **Water rules**: wading slows you; only grenades work against submerged threats.

---

## 3. Game Design

### Controls — four schemes, all at launch
- **Gamepad default**: LS move, RS 360° free aim with aim-persist, RT fire, RB grenade, B dodge-roll, Y interact.
- **Gamepad Classic**: 12-way stepped aim with detent haptics (the authentic rotary feel).
- **KBM**: WASD + mouse reticle.
- **Single-stick auto-aim** (accessibility).
- Steam Input action sets + full native remap; 3 aim-assist tiers. Fallback if free aim hurts readability: 24-way stepped with interpolated rotation.

### Moment-to-moment
- Walk speed +35% over 1986; water halves it; dodge roll (0.3s i-frames, 1.2s cooldown, disabled in water and Arcade Mode).
- MG cap 99, grenade cap 12; grenades arc over cover; at 0 MG → infinite combat knife.
- **One-hit death stays** (default). Frustration is attacked instead of lethality: roll, sub-second paid respawn, one-hit Flak Vest pickup with loud visual state, 1.5s post-spawn i-frames, edge-of-screen threat telegraphs, all spawns flagged 0.4s ahead. Assist Mode: permanent 2-hit vest. The default never ships an HP bar.

### The War Chest (the twist)
- Every kill mints coin to a shared pool; style bonuses (multi-kills, grenade-only kills, hostage rescues).
- Spends: on-the-spot revive (price rises per death per zone, decays over time; broke = respawn at last gate), requisition drops (ammo, Vest, one airstrike per zone), Endless War shop.
- Downed-not-dead 3s crawl window; partner pick-up at half price. Solo play halves prices.
- Friendly fire OFF by default; "Warrior's Honor" opt-in modifier grants a score multiplier.
- **Last Stand rule**: no revives past the final gate — coin converts to score.
- **Must be proven, not asserted**: G1 gate requires recorded playtests showing unprompted arguments between players over spends.

### Campaign — 6 zones, one unbroken scroll
Landing Jungle → River Crossing → Bridgehead → Ruins → Industrial Approach → Fortress.
- Gates between zones are mini-boss arenas that become checkpoints + music shifts.
- Camera: player-pushed ratchet (never auto-scroll); the **Mortar Observer** (visible spotter calling tracking fire on stallers; killable to cancel) is the pacing whip.
- Bosses: Bridge Gunship (Z2), Super-Tank Column (Z5), **Foundry Colossus** finale (mobile fortress-crawler, 3 phases, inverts the scroll direction as it advances on the players).
- Chapter Select per gate after first clear. First clear 50–70 min; median time-to-credits 2.5–4h at default difficulty.

### Vehicles
Tank only (helicopter permanently cut). Hold-interact to board; bullet-immune; crushes infantry; cannon draws from grenade ammo; fuel timer; on fuel-out/critical-hit: smoke + klaxon + guaranteed 3.0s bail window with speed boost. **Kamikaze verb**: drive a burning tank into a bunker to detonate it.

### Bestiary (each: unique silhouette + audio telegraph — Metal Slug readability doctrine)
Rifleman · red elite (drops) · sapper · flamer · kamikaze (telegraphed scream) · frogman · land/water mines · sensor post · light/heavy/super tanks · enemy attack helicopter (strafing runs over any terrain) · fixed turrets · dynamite turret · bunkers (sealed by grenading doors) · destructible rock faces · Mortar Observer.

### Power-ups (pictogram icons)
Ammo Cache, Grenade Crate, Fuel, Long Range, Speed Shot, Piercing Rounds, Blast Grenades, Fire Mission (screen clear, spares submerged), Heart (keep upgrades through one death), Flak Vest, Triple Shot (exclusive with Piercing), Hostage (±score). Death drops your upgrades on the ground for 10s, recoverable — feeds "cover my corpse" co-op play.

### Modes (all in MVP)
- **Campaign** (solo/2P)
- **Endless War** — roguelite survival: procedurally sequenced zone chunks, weekly rotating modifiers, between-wave War Chest shop. This is the content-length + retention + streamer answer.
- **Boss Rush**
- **Arcade Mode** — 3 lives, limited continues, 12-way stepped aim, no roll/Vest/War Chest, power-ups lost on death. `[IP-dependent: with license, a full 1986 Mode — original walk speed, A-B-B-A continue, CRT pillarbox, OST arrangement — replaces/joins it.]`
- Difficulties: Recruit / Soldier / Ikari.
- **Never**: procedural campaign, default HP bars, 4P, melee pivot.

### Onboarding, scoring, accessibility
- ~~First boot: 30s skippable control test range.~~ **Cut, shipped differently.** The firing-range tutorial was built and then deliberately deleted (`51726d2`, "de-checklist the firing-range tutorial"); `src/view/onboarding.gd` no longer exists. What ships instead: the landing zone *is* the tutorial (`SimWorld._author_lz()` — seawall → grenade box → armored bunker, authored on the player's walking line in the order the verbs are needed), plus `main.gd::_hint()` just-in-time cues that fire once ever and persist as seen, and a paged HOW TO PLAY menu screen (`GameMenu.HOWTO_TABS` — CONTROLS / WAR CHEST / MODES / ENEMIES / ENDLESS). Nothing unskippable.
- Zone 1 beach = diegetic tutorial (aim-persist strafing → first bunker teaches grenades-vs-armor → scripted elite drop teaches pickups → first death triggers one-time slow-mo War Chest explainer). *(The bunker/grenade-box half of this shipped; the slow-mo War Chest explainer is still aspirational — the War Chest teaches through `_hint()` text.)*
- Scoring: chain multipliers, hostage ±, no-death zone bonuses. Per-zone + full-run Steam leaderboards (filters: solo/co-op, difficulty, assists, mode). Built-in speedrun timer with load-removal + per-gate splits. Sanctioned skip-tech (tank-boost jumps, grenade-boosting) tuned in, never patched out.
- Accessibility (MVP): full remap incl. single-stick; hold/toggle everything; aim-assist tiers; per-toggle assists (2-hit vest, 75% speed, infinite revives) flagged on leaderboards, never locked out; colorblind-safe shape-coded palettes; shake/flash sliders; subtitles + visual indicators for off-screen audio telegraphs; photosensitivity pass.

---

## 4. Technical Architecture

**Engine: Godot 4.x, GDScript only.** All-text project surface (`project.godot`, `.tscn`, `.tres`) is ideal for agent-driven development; `--headless` import/test/export runs on GPU-less CI; GodotSteam for Steamworks without recompiling; native Linux export for Steam Deck; MIT license. A P0 validation spike picks the current stable 4.x; binary hash locked in `tools/versions.lock` with the matching GodotSteam release; upgrades only at phase boundaries after the replay-regression suite passes. Runner-up: Bevy (Rust) — documented switch trigger only if engine determinism fails.

**Architecture spine — sim/view split (lands first; load-bearing for netcode, testing, perf):**
- `src/sim/` = deterministic, render-free gameplay core at fixed 60 Hz — 16.16 fixed-point math, seeded xoshiro RNG, own AABB/circle collision vs LDtk IntGrid data.
- Scene tree is a *view* that interpolates sim state.
- CI lint forbids floats/engine-RNG/`Time.*`/node queries in sim code. ✅ **shipped** — `tools/lint_sim.gd`, run by the `lint` job in `.github/workflows/ci.yml` alongside `tools/lint_assets.gd`.
- **P0 hard requirement: 4-week determinism spike** — cross-platform (Win/Linux/Proton) replay-checksum agreement over 100k ticks with 300+ live projectiles. This is a G1 exit criterion; prove it month 2, not month 14.

**Entities & AI:** composition over inheritance — actors are thin `.tscn` views over SimEntity state; shared components (`Health`, `AmmoPool`, `Boardable`, `LootDrop`); a new enemy = one scene + one stats `.tres`. AI = hierarchical state machines as pure deterministic functions (5 templates: rusher, strafer, emplacement, kamikaze, submerged); bespoke boss scripts; no behavior-tree framework. Spawn Director = authored LDtk trigger-lines (backbone) + seeded token-bucket intensity controller (64-enemy cap) owning mortar call-for-fire.

**Levels:** LDtk single-world `campaign.ldtk`, ~30 stacked chunk levels, pre-baked to `.tres` by a headless import tool; 3 chunks live at runtime; ratchet camera frees memory below; gates hard-block scroll and double as chunk-load breathing points.

**Collision grammar in physics-layer masks**: bullets-vs-infantry, grenades-only-vs-armor/submerged; pierce = one mask-bit flip; grenades are scripted fake-Z parabolas, not physics bodies.

**Netcode — one story:**
- **Launch ships:** local 2P co-op + Remote Play Together (free via Local Co-Op flag). The only launch co-op promise.
- **Online 2P ships as a free update ~day-60**: deterministic lockstep, 3-tick input delay, Steam Networking Messages (SDR relay), ~400-line loop, per-second checksums, desync auto-report + host-snapshot resync. The fixed-point sim makes it deterministic by construction.
- **Rollback is the fallback**: if lockstep fails structured 150ms+ latency playtests, the snopek godot-rollback-netcode port slots in — the sim already meets its requirements.

**Netcode: shipped state (P3).** Local 2P co-op works. Online does not exist: `src/net/lockstep.gd` is ~260 lines with **zero production callers** (nothing constructs a `LockstepSession` outside `tests/`) and no Steam Networking transport is written. `test_lockstep.gd` drives it over an in-memory `FakeWire` that is deliberately hostile — deterministic latency/jitter plus scheduled packet loss and duplication, with tests covering reordering, corruption/desync detection, malformed input, and a stall-without-remote-input path — but it is still a loopback proof, not a network. The value delivered so far is the *determinism proof* the design depends on, not the netplay. No structured latency playtest has been run, so the lockstep-vs-rollback decision above is still untested.

**Feel systems:** ratchet free-scroll camera; co-op leash with bottom-edge mortar anti-troll; trauma-based screen shake on a rig offset node; 50–80ms hit-stop on explosions only; 1-frame white damage flash. **Weekly feel ritual from P0**: 90 minutes controller-in-hand against a feel checklist, director signs off — headless CI can't evaluate feel; humans on hardware do, weekly.

**Rendering:** 640×360 internal virtual resolution, nearest filtering; UI on full-res CanvasLayer; MSDF fonts (Latin/Cyrillic) + dynamic TTF (Noto Sans CJK) for JP/KO/zh; native 16:9/16:10 with optional integer-scaled "Arcade Crop" pillarbox SubViewport; per-frame normal maps on hero sprites; one sun light + pooled point lights; GPU particle pools; 12-occluder budget.

**Performance:** 60fps floor on Steam Deck LCD at worst case (2P, 64 enemies, 300 bullets, 8 lights). CI perf gate fails >4ms average sim tick. Weekly automated 3-hour soak test (scripted input, full campaign ×3) asserting a flat memory ceiling — a no-loading 50-minute game lives or dies on leaks.

**Testing & CI:** unit tests on sim (**shipped without GUT** — `tests/run_tests.gd` is a zero-dependency runner; suites are plain `RefCounted` classes with `test_*` methods); headless integration runs with injected input streams; **replay regression suite** (seed + inputs + per-second checksums; every fixed bug adds a replay); export smoke tests both platforms; nightly Proton smoke; godot-ci image; every PR runs the full ladder. Depot upload via `steamcmd` from CI on tags.

**Steamworks** — shipped as `src/steam/steam_bridge.gd`, a view-side facade instantiated by `main.gd` (*not* an autoload as written below). It is graceful-no-op by design and **none of it has ever run against real Steam**: `Engine.has_singleton("Steam")` is false in every dev/CI environment, GodotSteam is not vendored, and the exact API surface is unpinned (`docs/godotsteam_api_version.md`). **Priority order:** Local Co-Op flag/RPT → Steam Input action manifest + glyphs → leaderboards → achievements → Auto-Cloud saves → Rich Presence → lobbies/Networking Messages for the online update.

**Leaderboard anti-cheat:** every score attaches its deterministic input replay (Steam UGC attachment); a headless validation service (the shipping sim on a ~$25/mo VPS) re-simulates the top 100 nightly; mismatch = purge. Determinism does triple duty: netcode + regression testing + score validation.

**Current (P3) implementation vs. the plan above:** `Replay.verify_score()` / `_apply_score_verdict()` in `src/main.gd` gate the *local* Hall of Fame bank and Steam score upload on a synchronous re-simulation of the run's own recorded inputs, and `tools/validate_replay.gd` runs the same check offline against a submitted replay file. This closes the easy exploit (a hex-edited save or a memory-poked `sim.score` that never touches the recorded inputs) but is **not** the full anti-cheat plan above: there is no server-side replay storage or per-account signed submission yet, so (1) a crafted/bot-perfect input sequence still replays and verifies -- it earned its score legitimately, it is just inhuman, and (2) nothing yet stops one player from submitting another player's legitimately-recorded replay as their own. Closing both needs the headless validation service + signed submissions described above; until that ships, treat replay verification as "can't fake a number," not "can't cheat."

**Saves:** per-Steam-user versioned JSON, atomic write, CRC + last-good backup, Auto-Cloud. **Crash/analytics:** Sentry GDExtension + death-heatmap telemetry, both opt-IN (GDPR); Windows builds code-signed.

---

## 5. Asset Pipeline

**Art direction:** high-density pixel art at **Iron Meat / Blazing Chrome class** (honest, achievable, award-viable) — muted military palette earning its drabness through 2D lighting and reactive feedback; zones shift hue toward cold industrial gray at the finale. Fidelity budget: hero duo + vehicles get 16-direction torsos / 8-direction legs with normal maps; infantry are single-body 8-direction sprites.

**Staffing:** 1 full-time pixel artist (from P1) + contract art director (25%, style bible + keyframe approval). Humans draw everything that ships.

**AI-agent policy:** agents are fully unleashed on code, tools, tests, CI, level-JSON drafting, AND asset generation — generative-AI output is allowed to ship in game files (the earlier no-generative-AI restriction was dropped).

**Pipeline:** Aseprite (`.ase` sources, CLI export) → Blender headless for vehicle/explosion pre-renders + normal passes → LDtk for levels. `assets_src/` is truth, `assets/` is generated + committed; fully reproducible headless.

**Audio:** Godot-native buses (no FMOD — single toolchain, Deck-clean); ~300-line MusicDirector doing vertical layering keyed to Director intensity, bar-boundary transitions, gate resets. Contract composer (all rights): modern hybrid score with original motifs `[IP-dependent: license adds Theme of Ikari arrangement rights for 1986 Mode]`. Signature scream-layer SFX newly recorded as homage to the Y8950-era samples. ±10% pitch randomization, 32-voice stealing.

---

## 6. Step-by-Step Build Phases

> ⚠️ **What "P3" means in this repo vs in this plan.** README/CLAUDE.md label the repo **P3**, meaning *playable start→finish with all modes in*. It does **not** mean the plan's P3 exit criteria were met. Built by one owner plus agents, not the 4-person team costed below, so everything human-in-the-loop below is unstarted: no external playtests, no hired artist or art director, no contract composer, no Steam page/Playtest, no external QA or compat matrix, no LQA. Localization is 3 languages (`locale/strings.{es,fr,ja}.po`), not the 12-language freeze. Treat the phase table as the plan it is; the code is the source of truth for what exists.

Monthly external playtests from P1 (10–20 testers); one-hit-death churn and War Chest pricing get monthly telemetry checkpoints. Durations assume a 4-person core (director, lead engineer, engineer #3 from P2, pixel artist) + contractors, heavily agent-assisted on code/tools/CI.

**P0 — Preproduction (3 mo).**
Parallel workstreams: greybox prototype + **determinism spike** (eng) ∥ GDD v2 + weekly feel ritual starts (director) ∥ artist hiring ∥ repo/CI scaffold (godot-ci, replay suite skeleton, headless export).
**Exit = G1:** greybox at 60fps; War Chest proven (≥7/10 external testers would wishlist; recorded unprompted spend arguments); cross-platform determinism spike green; artist signed. Fail → pivot the twist or kill (~$70k sunk).

**P1 — Vertical Slice (5 mo).**
Zone 1 at ship quality (artist + AD) ∥ full feel stack (roll, hit-stop, shake, telegraphs) ∥ local 2P + War Chest v1 ∥ Bridge Gunship boss ∥ composer style tests ∥ tutorialized beach ∥ monthly playtests begin.
**Exit:** the slice is the internal quality bar; onboarding tested on genre-naive players.

**P2 — Production (10 mo).**
Zones 2–6 ∥ engineer #3 starts ∥ Endless War buildout ∥ lockstep netcode in nightly internal use by month ~15 (not launch-blocking) ∥ Arcade Mode ∥ Steam page live (~10 months pre-launch) ∥ announce trailer.
**Exit = G3:** all 6 zones playable start-to-finish; Endless War playable; **scope lock** (new ideas → post-launch backlog only).

**P3 — Content-Complete Alpha (3 mo).**
All assets/modes in (Boss Rush, difficulties, leaderboards + timer + splits + replay-validation service, full accessibility suite) ∥ localization kit freeze (~8k words, 12 languages) ∥ Steam Playtest opens with telemetry ∥ external QA pass #1.
**Exit:** content-complete; crash-free >99%.

**P4 — Beta/Polish (3 mo).**
QA passes #2–3 on the compat matrix (Win10/11; NVIDIA/AMD/Intel iGPU; Deck LCD+OLED; Xbox/DualSense/DS4/Switch Pro/8BitDo pads) ∥ min-spec published ∥ localization + LQA ∥ **Deck Verified build submitted to Valve's queue (3+ months lead)** ∥ demo branch (Zone 1 + 10-wave Endless War taste) → Next Fest ∥ weekly soak/leak tests.
**Exit = G4 (launch go/no-go):** wishlist floor met; Playtest median session >25 min; crash-free >99.5%; Deck review submitted; LQA done. Any miss → pre-authorized slip plan.

**P5 — Launch Prep (2 mo).** Build + page through Valve review with 2-week buffer; press/streamer keys (RPT = 1 key entertains 2); day-1 patch candidate frozen; review-response playbook (24h SLA).

**P6 — Launch.**

**P7 — Post-Launch (12 mo, funded).** Day-30 patch (Endless War expansion) ∥ **online co-op update: beta month 1, ships ~day-60 as its own beat** ∥ day-90 patch ∥ console ports via Godot-specialized porting partner (W4 Games / Pineapple Works class; Switch + PS5 + Xbox, months 6–10; local co-op only on console v1) ∥ speedrun.com board seeded week 1.

**Permanent cuts (already taken — scope discipline):** helicopter vehicle, War Dog, Magnum, ghost replays, ~~Daily Op~~, zones 7–8, 4P.
*(Correction: the Daily cut was reversed in code — a seed-of-the-day **Daily Run** mode ships, and Hall of Fame entries carry a `*DAILY` tag. The other six cuts still hold; run recording ships as "Watch Last Run" replay playback, which is not the cut ghost-replay feature.)*

---

## 7. Verification (how we know each step actually works)

- **Determinism:** P0 spike = cross-platform replay-checksum agreement over 100k ticks / 300 projectiles; CI replay canary on every PR thereafter.
- **Feel (Pillar #1):** weekly controller-in-hand ritual with a written checklist; director sign-off is the gate.
- **The twist:** recorded external playtests at G1 must show unprompted spend arguments; monthly telemetry on revive pricing and death churn.
- **Performance:** CI fails >4ms avg sim tick; weekly 3-hour scripted soak asserts flat memory.
- **Correctness:** GUT unit suite on sim; headless integration with injected inputs; every fixed bug adds a regression replay; export smoke + nightly Proton smoke.
- **Ship quality:** Steam Playtest telemetry from P3; crash-free ≥99.5% at G4; compat-matrix QA passes; leaderboard replay-validation service live before launch.

## Out of scope here (you're handling)
IP/licensing strategy, legal clean-room details, marketing calendar, wishlist/pricing strategy, awards campaign, budget/funding. All fully worked out in the archived master plan (`wf-result-13.md`, §3, §8–§11) whenever you want them.
