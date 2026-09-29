# Pinned GodotSteam API and verification scope

The bridge targets **GodotSteam 4.22.1 / Steamworks 1.65**. Its method names,
argument types, and signal shapes were checked against the real Steam singleton
in the official Godot 4.7.2 macOS module build, not just the hand-written mock.

## Pin and primary evidence

- [Official release](https://codeberg.org/godotsteam/godotsteam/releases/tag/v4.22.1)
- [Pinned binding source](https://codeberg.org/godotsteam/godotsteam/src/commit/5853a7741d174cfa37edee1ca44a11581a989d0b/godotsteam.cpp)
- [Official macOS archive](https://github.com/GodotSteam/GodotSteam/releases/download/v4.22.1/macos-g472-s165-gs4221-editor.tar.xz)
- Verified archive SHA-256:
  `ea4cfd17e3b6afe5e8e7fbc0fb49f92a871256a45d7751cfa114847f525b9c86`

The downloaded engine lives under ignored `build/godotsteam-4.22.1/`; it did not
replace the installed editor, modify project autoloads, or become a vendored
runtime dependency. The probe does **not** initialize Steam, request account
data, upload scores, set achievements, or change the Steam client.

## Repaired mismatches

The original real-binding probe failed on fifteen method names and
`current_stats_received`. Most methods in this release are camelCase
(`getAchievement`, `storeStats`, `getConnectedControllers`, etc.);
`run_callbacks` remains snake_case.

- The bridge uses `requestUserStats(getSteamID())` and
  `user_stats_received(game_id, result, user_id)` for its explicit offline-cache
  reconciliation refresh. Only EResult OK (1) for the requested account permits
  reconciliation. Failed and other-user responses do not.
- `requestCurrentStats` is no longer exposed by this binding. Valve documents
  it as deprecated because current-user stats are preloaded before launch.
  Our explicit refresh is bridge policy, not a Steam initialization requirement.
  See [ISteamUserStats](https://partner.steamgames.com/doc/api/ISteamUserStats#RequestCurrentStats).
- Steam Input is explicitly initialized. Failed manifest staging or input
  initialization leaves the existing raw-input fallback active.
- Digital action dictionaries use `state` and `active`; analog actions also
  report `active`. Inactive actions cannot trigger firing or button presses.
- `uploadLeaderboardScore` receives `PackedInt32Array` details. Its callback
  consumes all three native arguments: success, handle, and result dictionary.

The mock matches the pinned names and typed argument surface, but still
simulates callbacks and controllers. It is not a network or hardware test.

## Repeat the real-binding check

Use the official module engine in an isolated profile. Plain Godot must fail
this probe because it has no real Steam singleton.

```sh
rtk proxy env \
  GDA_GODOT="$PWD/build/godotsteam-4.22.1/GodotSteam.app/Contents/MacOS/Godot" \
  GDA_PROJECT="$PWD" \
  STEAM_API_REPORT="$PWD/build/godotsteam-4.22.1/api-after.json" \
  gda --user-data-root "$PWD/build/godotsteam-4.22.1/probe-profile" \
  script run res://tools/verify_godotsteam_api.gd --strict --json
```

Require `GODOTSTEAM API PASS missing=[]`, zero exit status, and no runtime
errors. The report contains native method/signal metadata. The probe compares
the mock's method argument counts/types and connected signal counts/types
with the real engine. This is a surface check, not a full semantic validator.

## Remaining release gates

- Matching module templates are now installed separately and used by explicit
  Steam macOS/Linux/Windows presets. See `steam-candidate-validation.md` for
  archive/file pins, the sidecar-copying builder and actual candidate evidence.
  The exact exported Mac release binary passes a separate names/signals probe;
  this is not full game execution or live account validation. Windows/Linux
  runtime execution and native argument/type inspection remain open.
- Exercise initialization, stats/achievement persistence, uploads and presence
  against the intended app/account. No live account was used in this pass.
- Validate `actions.vdf` with the actual Steam Input configuration/parser;
  the existing quote/brace checker cannot prove acceptance.
- Verify physical controller ordering, reconnect, rebinding, glyphs, raw-input
  coexistence, and both-player behavior. Automatic device-callback refresh now
  has mock regression coverage: late connections, stale-input removal,
  replacement handles, stable surviving seats and batched duplicate events.
  This proves the bridge/pump wiring, not physical hardware behavior or the
  raw-device mapping. Move/aim still use raw axes.
- Achievement-cache separation and fresh-process persistence now have local
  regression coverage (see `steam_cloud_paths.md`). Verify live account behavior,
  Cloud conflicts and the remaining OS-profile-scoped bests/settings/replays.
- Test native builds on Windows, macOS, Linux, Proton and Steam Deck.

No Steam Deck certification, store approval, upload, or publication is claimed.
