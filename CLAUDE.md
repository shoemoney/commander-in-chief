# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Project Ikari is a deterministic twin-stick vertical run-and-gun (modern *Ikari Warriors* remake) on **Godot 4.7 / GDScript**. The repo is currently at the **P3 greybox** milestone; `docs/PLAN.md` is the full P0–P7 production plan (much of it aspirational). **The sim code is the source of truth for what actually exists** — don't assume a feature described in the plan or README is implemented.

## Commands

Godot lives at `/Applications/Godot.app/Contents/MacOS/Godot` (universal binary, native on Apple Silicon). All commands run headless except the editor and screenshots.

```sh
# Run the game in the editor
/Applications/Godot.app/Contents/MacOS/Godot --path .

# Import assets — REQUIRED once after cloning, and after pulling ANY new
# class_name script (Godot's global class cache must re-scan). CI does this.
godot --headless --path . --import

# Full test suite (60 methods / 725 assertions, ~seconds)
godot --headless --path . -s res://tests/run_tests.gd

# Signature-moment screenshots (dev tool; needs a GL context — X or Xvfb)
SHOT_DIR=/abs/path godot --path . --rendering-method gl_compatibility \
    -s res://tools/screenshots.gd
```

**Running a single test suite:** the runner has no filter flag — it iterates the `TEST_SCRIPTS` array in `tests/run_tests.gd`. To run one suite, temporarily narrow that array. Each suite is a plain `RefCounted` whose `test_*` methods assert via the `Runner.T.ok/eq` helpers (no GUT addon).

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
- **Assets** in `assets/kenney/` are CC0 (Kenney) interim greybox art; no generative-AI assets ship (per plan policy). `.import` files are generated on `--import`.
- The README/PLAN reference a CI pipeline (float/RNG lint, cross-arch runners). There is currently **no `.github/workflows` in the repo** — the determinism guarantee is carried by `test_determinism.gd`, which you should run locally.
