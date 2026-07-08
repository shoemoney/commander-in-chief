# Project Ikari — P0 Greybox Prototype

A modern remake of the classic vertical-scrolling run-and-gun (*Ikari Warriors*, SNK 1986):
twin-stick move/aim, grenades-vs-armor, one-hit deaths, red-elite power-up drops,
infinite-spawn bunkers, a ratchet scroll camera, and the **War Chest** — a shared
coin economy where every kill mints and every revive spends.

Built on **Godot 4.6.3 / GDScript** around a deterministic, render-free simulation core
(`src/sim/`, fixed 60 Hz, 16.16 fixed-point integer math, seeded RNG). The scene tree
(`src/main.gd`) is only a view. Determinism is enforced by CI lint and replay-checksum
golden tests, and does triple duty per the master plan: lockstep netcode, regression
testing, and leaderboard anti-cheat.

The full production plan is in [`docs/PLAN.md`](docs/PLAN.md).

## Running on a Mac (M4 / any Apple Silicon)

1. Download **Godot 4.6.3 (stable)** — the standard build, `macos.universal.zip` — from
   <https://godotengine.org/download/archive/4.6.3-stable/>. The `.app` is a universal
   binary and runs **natively on Apple Silicon (M1–M4)**.
2. Unzip, then either:
   - Open Godot, click **Import**, and select this folder's `project.godot`, then press **⌘R**; or
   - From a terminal:
     ```sh
     /Applications/Godot.app/Contents/MacOS/Godot --path /path/to/project-ikari
     ```
3. First launch: if macOS Gatekeeper complains about the unsigned editor, right-click →
   Open once (or `xattr -dr com.apple.quarantine Godot.app`).

Determinism on Apple Silicon is not assumed — it is **asserted in CI**: the
`test-macos-apple-silicon` job runs the identical test suite on an arm64 M-series
runner and must reproduce the same golden checksums as Linux x86_64
(`tests/test_determinism.gd`). The sim is pure 64-bit integer math, so results are
bit-identical across architectures by construction.

## Controls (P0 greybox)

| Action | Keyboard (P1) | Gamepad |
|---|---|---|
| Move | WASD | Left stick |
| Aim (decoupled) | Arrow keys | Right stick |
| Fire | Space | RT / R1 |
| Grenade | Shift | L1 |
| Revive (spend War Chest) | E | Y |
| Toggle 2-player local | F2 | — |
| Restart | R | — |

## Headless test suite

```sh
godot --headless --path . --import      # first time only
godot --headless --path . -s res://tests/run_tests.gd
```

20 test methods / 560+ assertions: fixed-point math, seeded RNG streams, the 1986
mechanic grammar (grenades-vs-armor, one-hit death + ammo restore, ratchet camera,
elite drops), the War Chest economy (escalating revives, solo pricing, broke fallback),
and replay determinism against committed golden checksums.

## Layout

```
project.godot        Godot 4.6.3 project (640×360 virtual res, 60 Hz physics)
src/sim/             Deterministic core — int-only; floats/engine RNG banned by CI lint
src/main.gd|.tscn    Greybox view + input quantization boundary
tests/               Headless runner + suites (incl. determinism goldens)
tools/versions.lock  Pinned engine version + SHA-256
export_presets.cfg   macOS universal (Apple Silicon native) / Linux / Windows
docs/PLAN.md         The master build plan (P0–P7)
```
