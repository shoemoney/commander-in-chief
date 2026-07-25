# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Commander In Chief is a deterministic twin-stick vertical run-and-gun (modern *Ikari Warriors* remake) on **Godot 4.7 / GDScript**. The repo is currently at the **P3** milestone — playable start→finish, and past greybox: the art is owned procedural sprites (`tools/gen_*.py`) plus bespoke generated boss/vehicle/desert pieces over a Kenney-CC0 FX base (see `assets/art/`, `assets/kenney/`). The legacy art bakes it used to ship are gone from the tree — but still in git history, which is the last open-source blocker (`OPEN_SOURCE_CHECKLIST.md`). `docs/PLAN.md` is the full P0–P7 production plan (much of it aspirational). **The sim code is the source of truth for what actually exists** — don't assume a feature described in the plan or README is implemented.

## Commands

Godot lives at `/Applications/Godot.app/Contents/MacOS/Godot` (universal binary, native on Apple Silicon). All commands run headless except the editor and screenshots.

```sh
# Run the game in the editor
/Applications/Godot.app/Contents/MacOS/Godot --path .

# Import assets — REQUIRED once after cloning, and after pulling ANY new
# class_name script (Godot's global class cache must re-scan). CI does this.
godot --headless --path . --import

# Full test suite (~10 s; count grows constantly — 693 methods / ~14.7k assertions as of
# 2026-07-25. Methods are countable without running Godot:
#   grep -hcE '^func test_' tests/test_*.gd   minus test_perf.gd, which is opt-in)
godot --headless --path . -s res://tests/run_tests.gd

# Single suite: filter by substring of the script filename
SUITE=mechanics godot --headless --path . -s res://tests/run_tests.gd

# Signature-moment screenshots (dev tool; needs a GL context — X or Xvfb)
SHOT_DIR=/abs/path godot --path . --rendering-method gl_compatibility \
    -s res://tools/screenshots.gd
```

**Running a single test suite:** set the `SUITE` env var to a substring of the suite filename (e.g. `SUITE=mechanics`) — the runner filters its `TEST_SCRIPTS` array on it. Each suite is a plain `RefCounted` whose `test_*` methods assert via the `Runner.T.ok/eq` helpers (no GUT addon). ⚠️ A runtime error mid-method silently aborts that method's remaining assertions without failing the run — grep the output for `SCRIPT ERROR`, and hold dict references across `sim.step()` (dead entities are swept from the sim arrays).

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

`src/net/lockstep.gd` (`LockstepSession`) is transport-agnostic deterministic lockstep: both peers run the same `SimWorld`, only encoded `SimInput` crosses the wire (`input_delay`-ticks ahead), the sim advances only when both players' inputs for the next tick are present, and checksums are exchanged every 60 ticks for desync detection. A real transport (Steam Networking Messages) is *meant* to plug into `on_send` / `receive_remote_input` without touching the loop.

⚠️ **It is a design sketch, not shipped netplay.** 108 lines, **zero production callers** — nothing in `src/main.gd` or the menus ever constructs a `LockstepSession`, and no transport exists. `test_lockstep.gd`'s `FakeWire` is an in-memory queue with latency jitter only: no packet loss, no duplication, no disconnect/timeout path (its one "corruption" case hand-flips a payload byte to prove the checksum exchange notices). So the suite shows the sim is deterministic enough for lockstep and that the loop's stall/catch-up/desync-flag logic is self-consistent — it says nothing about a real lossy network. Don't describe online co-op as working.

## Conventions & gotchas

- **Modes**: `SimWorld._init(seed, player_count, mode)` where mode is `"campaign"` or `"endless"`. `main.gd` hard-codes seed `0xC0FFEE`; F2 toggles 2P, F3 toggles Endless War, R restarts.
- **Fixed-point**: multiply/divide via `Fixed.mul`/`Fixed.div`, never `*`/`/` on two fixed values directly. Constants suffixed `_TICKS`/`_RAW` are not fixed-point; everything else in the sim is.
- **`.gd.uid` files** are Godot 4.x script-UID sidecars — committed, machine-generated, don't hand-edit.
- **Assets**: `assets/kenney/` is CC0 (Kenney), now mostly the FX base rather than stand-in greybox; `assets/art/` is owned art — procedural sprites regenerable from `tools/gen_entities.py` · `gen_ui_chrome.py` · `gen_ui_icons.py` · `gen_ui_glyphs.py` · `gen_fx_cards.py`, **plus** ~14 generative-AI files (tank/gunship/colossus bodies+barrels, cacti, scrub, tumbleweed). The folder was renamed from `assets/legacy-art/`; the legacy art bakes it once held were all replaced, so edit the generator and re-run it rather than hand-painting a PNG. `OPEN_SOURCE_CHECKLIST.md` carries the per-subfolder provenance table. `.import` files are generated on `--import`. (Generative-AI assets are allowed — the earlier no-AI policy was dropped.)
- **A "hanging" test suite is almost always CPU contention, not a slow test.** The full suite runs in **~10 s** (693 methods / ~14.7k assertions). If it appears to stall — output freezing mid-run, a suite that never prints its `PASS —` line — check `ps aux | grep -c '[G]odot'` first: parallel sessions/worktrees each running Godot starve each other, and a starved run sits at <1% CPU making no progress. `pkill -f Godot` and run ONE. Verified 2026-07-24: a "stall" blamed on `test_localization.gd::test_shipped_font_has_real_cjk_glyph_coverage` was pure contention — that test measures at **21 ms**, and localization/hud/perf/soak are 0.7/0.5/1.5/0.4 s each.
- **A fresh worktree stalls on a COLD IMPORT, and it looks exactly like the contention stall above — but `pkill` is the wrong fix.** A new `git worktree` has no `.godot/`, so the first Godot run does a full asset import: zero output, <1% CPU, several minutes, then either a wall of `Identifier "SimWorld"/"Fixed" not declared` parse errors or nothing at all. Six independent agents hit this on 2026-07-25 and several reached for `pkill -f Godot` (the remedy for the *other* stall) before finding it. **Run `godot --headless --path <worktree> --import` once before the first test run** — or `cp -R <main>/.godot <worktree>/` to start warm. Tell them apart by CPU: contention = many Godot processes each starved; cold import = one process, machine otherwise idle.
- **Parallel worktrees SHARE `user://` — it is keyed on project name, not on path.** Every worktree of this project reads and writes the same `~/Library/Application Support/Godot/app_userdata/Commander In Chief/` (the folder is `config/name` from project.godot, verbatim — spaces and all; the pre-rename `Project Ikari/` dir is still sitting next to it), so concurrent runs fight over one `ikari_best.cfg`; the save/settings tests (`test_robustness.gd`, `test_menu_layout.gd`) stash and restore the real file and will interfere with each other. Confirmed against the Godot docs: the path derives from the project name and `application/config/use_custom_user_dir` — both *project settings*, so there is no per-run CLI override (`--help` has no `--user-data-dir`). The only per-process lever on macOS is overriding `HOME`. Copying the Godot binary does **not** help — the binary is not the shared state, and extra copies only add page-cache pressure.
- **Dev-only autoloads must never ship.** The godot-mcp editor plugin re-adds an `[autoload] MCPGameBridge` entry to `project.godot` whenever the editor runs with the plugin enabled. It targets untracked `addons/godot_mcp/`, so exported builds spam "Failed to instantiate an autoload". It has regressed once already; `test_assets.gd::test_no_dev_addon_references_in_project_godot` now fails on **any** line of `project.godot` referencing `addons/`, in any section — the earlier `[autoload]`-only version let the plugin's `[editor_plugins] enabled=…` line through. Don't commit the re-addition.
- **CI is live**: `.github/workflows/ci.yml` runs a 3-OS matrix (Linux · macOS-arm64 · Windows) that imports, boot-smokes (`tools/smoke.gd`), and runs the full golden-checksum suite, failing on any `SCRIPT ERROR` or a missing `PASS` line. A separate `lint` job runs `tools/lint_sim.gd` (the no-floats/no-RNG/no-`Time`/no-scene-tree gate) and `tools/lint_assets.gd`. The Godot version is pinned in `tools/versions.lock`. Still run the suite locally before pushing — CI is the backstop, not the first check.
- **The blocking test gate is timing-free.** `test_perf.gd` asserts wall-clock microseconds per tick and is therefore in `run_tests.gd`'s `OPT_IN_SUITES` — skipped by the default full run, run explicitly via `SUITE=perf` (CI does that in an advisory `continue-on-error` job). Noisy shared runners made it fail for reasons unrelated to the commit, and a randomly-red gate stops being read.
- **Boot-smoke's exit code proves nothing on its own.** With `src/main.gd` failing to *parse*, `main.tscn` still instantiates and `tools/smoke.gd` still prints `SMOKE OK` and exits 0 — CI greps the log for both the sentinel *and* `SCRIPT ERROR` for exactly this reason.
