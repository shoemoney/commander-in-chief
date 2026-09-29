# Steam module candidate validation — 2026-09-07

These are local Steam-enabled candidates, not uploaded or approved releases.
They were exported from `cf23387` plus the existing uncommitted gameplay work,
including the title-clarity repair. No gameplay source or art was changed in this
export pass. The ordinary offline presets remain available and unchanged.

## Current refresh: solo ready-up included

The current candidates are under `build/steam-ready.jqZpJ9/candidates/`. They
replace the original candidates described below and include the subsequent solo
ready-up feedback and removal of an unused revival-tip translation entry.

- Mac ZIP SHA-256:
  `ff5ee4d3d3689cbbb4608ee379e8cbc061faf2bc1293746cb4cf6d3ed57434f5`
- All three game packs have identical SHA-256:
  `63fb2c14dd1ffa2f2103fba4b25ef315bc767994a1b5395d0948f6a10e74d108`.
- The new Mac executable SHA-256 is
  `6ab7dab1d329269a247a90d6e6724bcdf2bd659b954434f1a9502c34ec2e2a3d`;
  its copied executable passes the same separate native names/signals probe
  (`native-binding.log`). The unchanged Steam library and inspection-pack hashes
  still match those recorded below. No Steam initialization was performed.
- Actual exports and all three preset resource-content gates pass. Mac strict
  ad-hoc signature verification passes. Complete output hashes are in the new
  `candidates/manifest.json`; this still is not distribution signing or approval.
- The Linux game pack was inspected using the plain Godot editor, an empty
  project directory and isolated save profile. It passes resource loading,
  Campaign advancement, HUD shader attachment and the new solo hold/release
  behavior check (`packed-runtime-fixed.log`). Identical pack hashes establish
  the same packed bytes across targets, not native platform execution.

The strengthened external inspector prints `EXPORT READY PASS` only after the
packed game itself produces positive solo progress and clears it on release.
The earlier `steam-native.DjatEv` pack fails that check, exit 1. This detects the
specific missing behavior; it is not a generic source-freshness detector.
An initial inspector run failed because it assigned an untyped external array
to the packed script's typed `Array[SimInput]`; the inspector now preserves that
array and appends the correctly loaded input instance. The failed log is retained
as `packed-runtime.log`, not counted as passing evidence.

The inspector also rejects an engine with a native Steam singleton before loading
the game. Its negative-control run with the pinned module editor exits 1 with
`use plain Godot for this offline pack inspector` (`steam-guard-negative.log`).
This prevents the offline test from accidentally becoming a live account test.
All live-account, native-platform, hardware, rights and human acceptance gates
below remain open. No current candidate has been uploaded or published.

## Pinned templates

GodotSteam **4.22.1**, Godot **4.7.2**, Steamworks **1.65**:

- [Official release](https://codeberg.org/godotsteam/godotsteam/releases/tag/v4.22.1)
- [Official overflow template archive](https://github.com/GodotSteam/GodotSteam/releases/download/v4.22.1/godotsteam-g472-s165-gs4221-templates.tar.xz)
- Download: `build/steam-templates.ZTbRUX/templates.tar.xz`
- Archive SHA-256, matching the release asset digest:
  `ae0b83d87b4877bf2b1ed0bd19286d2c145796fad8d155e93a2ae6e055484ef9`

The archive also contains older engine-version executables; only the 4.7.2
templates were selected. Extract these members into
`build/godotsteam-4.22.1/templates/`, preserving their relative paths:

```text
macos/macos.zip
linux64/godotsteam.472.template.x86_64
linux64/godotsteam.472.debug.template.x86_64
linux64/libsteam_api.so
win64/godotsteam.472.template.win64.exe
win64/godotsteam.472.debug.template.win64.exe
win64/steam_api64.dll
```

The installed standard editor/templates were not replaced. Release input-file
checksums are recorded in `tools/build_steam_candidates.py` and the candidate
manifest. Debug templates are configured for convenience but were not exported
or independently checked in this pass.

## Reproducible builder and checks

Use a **new**, nonexistent output directory under an existing parent:

```sh
rtk proxy python3 tools/build_steam_candidates.py build/steam-candidates-next
rtk proxy python3 -m unittest discover -s tools -p test_build_steam_candidates.py -v
rtk proxy python3 tools/verify_export_content.py --godot /Applications/Godot.app/Contents/MacOS/Godot --preset 'Steam macOS universal' --preset 'Steam Linux x86_64' --preset 'Steam Windows x86_64'
```

Repeat `--platform macos|linux|windows` to restrict the builder. It checks pinned
input bytes before exporting, rejects existing output folders, requires artifacts
and clean logs, checks the Mac ZIP, copies pinned Windows/Linux runtime sidecars,
and writes actual output hashes. **Direct Windows/Linux preset export alone is
not the complete distribution:** the Steam shared library must accompany the
executable and game pack. The builder does that extra step.

Eight offline fixture tests pass, covering successful sidecar/hash receipts,
preservation of an existing destination, altered templates, missing libraries,
nonzero exits, error text with a zero exit, missing game packs and a Mac archive
without its runtime. They are wired into the existing CI packaging step; remote
CI has not been run for these uncommitted changes. Fixtures do not test Godot's
exporter or a real Steam connection.

## Actual artifacts and observed evidence

Candidate root: `build/steam-native.DjatEv/candidates/`.

- `macos/CommanderInChief-macos.zip` SHA-256:
  `5ce79e61ee2e126d3ab93edfb64a4602b3aa3df81c82d539fa9a23bae7997320`
- `linux/`: release executable, `.pck`, `libsteam_api.so`.
- `windows/`: release executable, `.pck`, `steam_api64.dll`.
- `manifest.json`: complete output/template checksums.

All three actual release exports completed with clean logs. The resource-selection
gate also passed all three presets (`content.log`). Mac archive integrity and
strict ad-hoc signature verification passed; both universal executable slices
link to the adjacent `libsteam_api.dylib`. This is **not** Developer ID signing,
notarization or a Gatekeeper distribution test.

All three exported game packs have the same SHA-256:
`31ad213cedb1315fdd992f72a767a3ec3b2fb168c034c22ef7a782cc6e42fa87`.
The Mac copy was booted from an empty folder under the plain Godot editor using
an isolated save profile and the external `verify_export_runtime.gd` inspector.
It loaded all 56 character/projectile textures, attached the HUD shader, read the
input manifest, booted the packed main scene and advanced Campaign. Its explicit
`EXPORT RUNTIME PASS` marker and clean exit are in `packed-runtime.log`.
This is a **game-pack test under plain Godot**, not native Steam game execution.

## Exact Mac release binary binding probe

The exported executable and its Steam library were copied unchanged into
`build/steam-native.DjatEv/probe-runtime/`, beside a separate tiny inspection
pack. Their hashes match the files inside the extracted candidate:

- Executable: `3cb741b2ee9de17acb86b44dc98db5a091b025f347acf34970769399f996d15a`
- Library: `ac6aca01a62b9ddfb8240fcc4ebdefab3d6b97da1ba3bbc87ff89b03369cc870`
- Inspection pack: `4663f33b1137651c82ff5e13502fe4df6e1c24c8db8442d7dd9ece7260b65419`

`tools/steam_template_probe/` contains the tiny project's source. To reproduce,
copy its four files into a new scratch project and copy the current bridge as
`bridge.txt`. Export that scratch project's `Probe` pack as `SteamProbe.pck`.
Copy the candidate Mac executable as `SteamProbe` beside it, with the adjacent
`libsteam_api.dylib`, then launch through `tools/playtest_newcomer.sh` using
`GODOT=<absolute copied executable>` and `--standalone --headless`.
Never overwrite or substitute the candidate's actual game pack.

The inspection project explicitly disables module auto-initialization and
embedded callbacks. It only reflects on the singleton; it never instantiates
the bridge or game, calls operational Steam methods, initializes Steam, pumps
callbacks or requests account data. It reads a copy of the current bridge as
text; that copy matched source SHA-256
`85e5862cf9bf7fbd689adc280dac8a028a0ad2da4e815347809eaf23d74d1227`.

Actual result, exit 0 and no runtime/shutdown diagnostics:

```text
STEAM TEMPLATE PASS methods=22 signals=5 missing=[] initialized_steam=false engine=4.7.2- (custom_build)
```

Log: `build/steam-native.DjatEv/native-binding.log`.
A separate plain-Godot release executable with the **same inspection pack**
fails with `STEAM TEMPLATE FAIL: native singleton missing`, exit 1
(`native-binding-negative.log`). Neither probe runs the actual game.

This release probe verifies method/signal **names**, not argument types or
semantics. The earlier editor-module probe checks native argument/signal shapes
against the mock; see `godotsteam_api_version.md`. Do not conflate either check
with real account behavior.

## Still open

- Full Steam-enabled game execution against the intended App ID/account,
  including achievements, Input, leaderboards, presence and Cloud behavior.
- Native Windows/Linux execution, Mac Intel, Proton/Deck, physical controllers,
  reconnect, suspend/resume, co-op and long-session performance.
- Distribution signing, final voice/asset permissions, owner metadata,
  human gameplay acceptance and Steam review/upload/publication.

No account data was requested or changed; no Steam upload was performed. Passing
these packaging checks is not evidence of a 10/10 game or audience reception.
