# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Commander In Chief is a deterministic twin-stick vertical run-and-gun (modern *Ikari Warriors* remake) on **Godot 4.7 / GDScript**. The repo is currently at the **P3** milestone — playable start→finish, and past greybox: the art is legacy 3D pack bakes plus bespoke generated boss/vehicle/desert pieces over a Kenney-CC0 FX base (see `assets/art/`, `assets/kenney/`). `docs/PLAN.md` is the full P0–P7 production plan (much of it aspirational). **The sim code is the source of truth for what actually exists** — don't assume a feature described in the plan or README is implemented.

## Commands

Godot lives at `/Applications/Godot.app/Contents/MacOS/Godot` (universal binary, native on Apple Silicon). All commands run headless except the editor and screenshots.

```sh
# Run the game in the editor
/Applications/Godot.app/Contents/MacOS/Godot --path .

# Import assets — REQUIRED once after cloning, and after pulling ANY new
# class_name script (Godot's global class cache must re-scan). CI does this.
godot --headless --path . --import

# Full test suite (~seconds; count grows constantly — 679 methods / 14,360 assertions as of 2026-07-25)
godot --headless --path . -s res://tests/run_tests.gd

# Single suite: filter by substring of the script filename
SUITE=mechanics godot --headless --path . -s res://tests/run_tests.gd

# Signature-moment screenshots (dev tool; needs a GL context — X or Xvfb)
SHOT_DIR=/abs/path godot --path . --rendering-method gl_compatibility \
    -s res://tools/screenshots.gd
```

**Running a single test suite:** set the `SUITE` env var to a substring of the suite filename (e.g. `SUITE=mechanics`) — the runner filters its `TEST_SCRIPTS` array on it. Each suite is a plain `RefCounted` whose `test_*` methods assert via the `Runner.T.ok/eq` helpers (no GUT addon). ⚠️ A runtime error mid-method silently aborts that method's remaining assertions without failing the run — hold dict references across `sim.step()` (dead entities are swept from the sim arrays).

**Two ratchets guard the "green but wrong" failure mode — don't neuter either:**
- **Engine-error gate** (`run_tests.gd::_gate_engine_errors`). Godot's own `ERROR:` lines fail nothing on their own, and the suite was printing ~400 of them while reporting PASS. The runner now reads its own engine log back (`user://logs`, enabled by `debug/file_logging` in `project.godot`, debug builds only) and fails on any un-allowlisted `ERROR:`. `ERROR_ALLOW` is deliberately empty — fix the cause, and only add an entry with a written justification. If the gate reports "no log carried this run's marker", that's parallel Godot processes rotating the log away: run ONE.
- **Stub parity** (`tests/test_stub_parity.gd`). Every `main.<x>` / `main.get("<x>")` that `src/view/menu.gd` and `src/view/hud.gd` execute must exist on every hand-written `main` stub the headless tests hand them. A missing field aborts the reading call, the row measures as ABSENT, and every assertion still passes — which is exactly how the c4-18 `last_run_score` gap shipped. Add a `main.` read to a view script and you add the field to the stubs, or the suite goes red.

## Architecture: the sim/view split

This is the one thing you must internalize before touching code. Everything the game *is* lives in a deterministic, render-free core; the scene tree is only a view over it.

- **`src/sim/`** — the deterministic core. `SimWorld.step(inputs)` advances the entire game exactly one 60 Hz tick, calling its subsystem steppers in a fixed order (players → tanks → projectiles → enemies → bunkers → spawner/boss/colossus/gates/camera/observer). State is plain `Array[Dictionary]` (no node objects). `Fixed` is 16.16 fixed-point math; `SimRng` is a seeded xoshiro128**. **No floats, no engine RNG (`randi`/`randf`), no `Time.*`, no scene-tree access may enter `src/sim`** — that is what makes the sim bit-identical across x86_64 and Apple Silicon arm64.
- **`src/main.gd`** (+ `src/view/art.gd`) — the *only* view. It owns all floats, reads sim state, and draws. `_physics_process` calls `sim.step(_gather_inputs())`. The float→int boundary is `_quantize_axis` → `SimInput` axes clamped to `[-256, 256]`; the sim never sees a raw float.
- **`SimWorld.events`** — transient per-tick view triggers (`explosion`/`kill`/`gate_open`/`vest_break`/`victory`/…), rebuilt every `step()` and **excluded from the checksum**. This is the decoupling seam: the sim emits events, `main._consume_events()` turns them into screen shake / hit-stop / flash / particles. The sim never knows feel exists.

### Determinism is enforced by a golden-checksum test — read this before editing the sim

`SimWorld.checksum()` is an FNV-1a hash over the full ordered sim state. `tests/test_determinism.gd` runs a scripted 60 s 2P torture input and asserts the sampled checksums equal committed `GOLDEN` values.

**Any change to sim logic, state fields, or the order state is hashed/stepped will change these checksums and fail `test_determinism.gd` — by design.** When the change is intentional, re-record: set `GOLDEN` to `[]` to make the test print the new values, run it, paste them back, and note *why* in the comment (see the existing P3 re-record note). Do not re-record to make a red test go green without understanding what moved. Per the plan, behavior changes only at phase boundaries.

The same discipline applies to `checksum()` itself: if you add a sim field that affects gameplay, add it to the checksum (and expect to re-record goldens).

### Netcode

`src/net/lockstep.gd` (`LockstepSession`) is transport-agnostic deterministic lockstep: both peers run the same `SimWorld`, only encoded `SimInput` crosses the wire (`input_delay`-ticks ahead), the sim advances only when both players' inputs for the next tick are present, and checksums are exchanged every 60 ticks for desync detection. A real transport (Steam Networking Messages) plugs into `on_send` / `receive_remote_input` without touching the loop. `test_lockstep.gd` proves it via a two-sim loopback.

## Conventions & gotchas

- **Modes**: `SimWorld._init(seed, player_count, mode)` where mode is `"campaign"` or `"endless"`. `main.gd` hard-codes seed `0xC0FFEE`; F2 toggles 2P, F3 toggles Endless War, R restarts.
- **Fixed-point**: multiply/divide via `Fixed.mul`/`Fixed.div`, never `*`/`/` on two fixed values directly. Constants suffixed `_TICKS`/`_RAW` are not fixed-point; everything else in the sim is.
- **`.gd.uid` files** are Godot 4.x script-UID sidecars — committed, machine-generated, don't hand-edit.
- **Assets**: `assets/kenney/` is CC0 (Kenney), now mostly the FX base rather than stand-in greybox; `assets/art/` holds the legacy 3D pack bakes **and** ~14 files of our own generative-AI art (tank/gunship/colossus bodies+barrels, cacti, scrub, tumbleweed) — the folder was renamed from `assets/legacy-art/` because that name mis-described its contents. `OPEN_SOURCE_CHECKLIST.md` carries the per-subfolder provenance table. `.import` files are generated on `--import`. (Generative-AI assets are allowed — the earlier no-AI policy was dropped.)
- **A "hanging" test suite is almost always CPU contention, not a slow test.** The full suite runs in **~10 s** (660 methods / 12,343 assertions). If it appears to stall — output freezing mid-run, a suite that never prints its `PASS —` line — check `ps aux | grep -c '[G]odot'` first: parallel sessions/worktrees each running Godot starve each other, and a starved run sits at <1% CPU making no progress. `pkill -f Godot` and run ONE. Verified 2026-07-24: a "stall" blamed on `test_localization.gd::test_shipped_font_has_real_cjk_glyph_coverage` was pure contention — that test measures at **21 ms**, and localization/hud/perf/soak are 0.7/0.5/1.5/0.4 s each.
- **Dev-only autoloads must never ship.** The godot-mcp editor plugin re-adds an `[autoload] MCPGameBridge` entry to `project.godot` whenever the editor runs with the plugin enabled. It targets untracked `addons/godot_mcp/`, so exported builds spam "Failed to instantiate an autoload". It has regressed once already; `test_assets.gd::test_no_dev_addon_autoloads_in_project_godot` now fails on any `[autoload]` pointing into `addons/`. Don't commit the re-addition.
- **CI is live**: `.github/workflows/ci.yml` runs a 3-OS matrix (Linux · macOS-arm64 · Windows) that imports, boot-smokes (`tools/smoke.gd`), and runs the full golden-checksum suite, failing on any `SCRIPT ERROR` or a missing `PASS` line. The Godot version is pinned in `tools/versions.lock`. Still run the suite locally before pushing — CI is the backstop, not the first check.
