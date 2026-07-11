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

## Controls (P1 greybox)

| Action | Keyboard (P1) | Gamepad |
|---|---|---|
| Move | WASD | Left stick |
| Aim (decoupled) | Arrow keys | Right stick |
| Fire / tank cannon | Space | RT / R1 |
| Grenade | Shift | L1 |
| Dodge roll (i-frames) | C | B |
| Interact (board/exit tank) | F | X |
| Revive (spend War Chest) | E | Y |
| Toggle 2-player local | F2 | — |
| Restart | R | — |

P1 systems: enterable tank (fuel clock, grenade-ammo cannon, crush, burning
bail window, kamikaze-a-bunker), the Mortar Observer who shells you for
stalling (kill him or push forward), zone gates every 1000 units that open
when their arena bunkers fall and become your broke-respawn checkpoint, and
a view-side feel stack (trauma shake, explosion hit-stop, kill flash).

P2 systems: rivers with dry fords (wading halves speed, no rolling, tanks
walled out) hiding submerged frogmen that only grenades can kill until they
surface to lunge; the **Bridge Gunship** mini-boss holding every 3rd gate
(strafe sprays + mortar volleys; bullets chip it, grenades chunk it); and
`src/net/lockstep.gd` — the transport-agnostic deterministic lockstep core
(3-tick input delay, per-second checksum exchange, desync detection) proven
by a two-sim loopback test over a jittery fake wire. Steam Networking
Messages plugs into it later without touching the loop.

P3 systems: the campaign now ENDS — gate 5 is the **Foundry Colossus**, a
fortress-crawler that inverts the scroll and advances down the map through
three phases (turret spray → mortar volleys → enraged + sappers); it's pure
armor (grenades only), engaging it triggers the **Last Stand rule** (the
coin reader dies — no revives), and killing it converts the remaining War
Chest to score. **VICTOLY!** Also: the **Flak Vest** (absorbs exactly one
hit) and **Fire Mission** screen-clear (spares the submerged) power-ups, and
**Endless War mode** (F3) — escalating waves with a between-wave War Chest
shop selling ammo, vests, and airstrikes.

## Headless test suite

```sh
godot --headless --path . --import      # first time only
godot --headless --path . -s res://tests/run_tests.gd
```

60 test methods / 725 assertions: fixed-point math, seeded RNG streams, the 1986
mechanic grammar (grenades-vs-armor, one-hit death + ammo restore, ratchet camera,
elite drops), the War Chest economy (escalating revives, solo pricing, broke fallback),
the tank (board/crush/shells/fuel/bail/kamikaze), the Mortar Observer (stall spawn,
tracked strikes, roll i-frames, cancel-on-kill), zone gates (block, open, checkpoint),
water rules (half speed, no roll, tank walls, frogman submersion), the Bridge Gunship
(chip/chunk damage, patterns, gate key), lockstep netcode (loopback identity, stall
semantics, desync detection), Endless War (waves, shop economics, vest, fire mission),
the Foundry Colossus (world end, Last Stand, phases, armor rules, victory payout),
and replay determinism against committed golden checksums.

Note: after pulling new `class_name` scripts, run `--import` once before the test
suite — Godot's global class cache must pick them up (CI already does this).

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

## Art

Units, vehicles, bosses, structures and foliage (`assets/legacy-art/`) are **top-down
renders of legacy 3D pack Military** 3D models, baked to sprites by
`tools/bake_sprites.gd` (orthographic overhead camera; characters posed out of
the T-pose; hero-vehicle turrets split from hulls so they rotate). The
desert→jungle look is a per-sprite olive/green tint plus a 1px readability
outline applied in the view (`src/view/art.gd` → `main._spr()`), not baked in.
Ground tiles, projectiles and FX stay **Kenney** CC0 (`assets/kenney/`) — legacy art
ships no seamless 2D tilesets.

> ⚠️ The legacy art-derived sprites are proprietary (from a purchased legacy art license),
> **not** CC0 — clear them before making this repo public. Final art per the
> master plan is still a commissioned pixel-art pass; these are the readability
> layer until then. No generative-AI assets are used.
