# GodotSteam API version this bridge targets

`src/steam/steam_bridge.gd` is written against no specific vendored
GodotSteam build -- this repo does not currently ship the GodotSteam
GDExtension binary itself (see the SCOPE NOTES in
`.shoop/specs/steamworks-and-steam-input.txt`; a real `.framework`/`.so`/
`.dll` is a multi-hundred-MB per-platform binary artifact that doesn't belong
committed to this repo sight-unseen). Every call to the `Steam` engine
singleton goes through `SteamBridge._call()`, which checks `has_method()`
first and `push_warning()`s the exact missing name instead of throwing an
untested "Invalid call" -- so a version mismatch fails loudly and
diagnosably instead of silently.

**What IS exercised today:** `tests/mock_steam_singleton.gd` is a hand-rolled
GDScript stand-in that implements this exact method surface (see the list
below) and gets registered as the real `Engine` "Steam" singleton for the
duration of a handful of `tests/test_steam_bridge.gd` cases. That runs the
REAL `steam_bridge.gd` code paths -- `_init()`'s init/connect/manifest-stage
sequence, the `current_stats_received` -> achievement-reconcile flow, the
`find_or_create_leaderboard` -> `leaderboard_find_result` ->
`upload_leaderboard_score` -> `leaderboard_score_uploaded` round trip, and
both players' action-handle button/trigger reads -- instead of only ever
hitting the `_steam == null` early-return every other test in that file
covers. It is NOT the real GodotSteam binding: it proves `steam_bridge.gd`'s
own call sequencing and callback wiring are internally consistent, not that
the method names/signal shapes below match a specific real GodotSteam
release. That last mile still needs the real GDExtension installed once.

**When vendoring the real GodotSteam GDExtension**, record the exact version
here (release tag + godotsteam.com docs link) and diff `steam_bridge.gd`'s
method names against that version's actual API surface before shipping:
`steamInitEx`, `request_current_stats`, `get_achievement`, `set_achievement`,
`store_stats`, `find_or_create_leaderboard`, `upload_leaderboard_score`,
`set_rich_presence`, `set_input_action_manifest_file_path`,
`get_connected_controllers`, `get_action_set_handle`, `activate_action_set`,
`get_analog_action_handle`, `get_analog_action_data`,
`get_digital_action_handle`, `get_digital_action_data`, `run_callbacks`.
`_call()`'s warnings will also flag any that don't match the moment the game
runs with Steam present -- and `tests/mock_steam_singleton.gd` should get its
method signatures corrected to match at the same time, so the mock stays a
useful regression harness instead of quietly drifting from reality.

**Signal handler arg counts** (`_on_stats_received`, `_on_leaderboard_found`,
`_on_leaderboard_uploaded`) are documented individually above each handler
in `steam_bridge.gd`, along with why every param defaults so a leaner
emitted-arg-count from a real vendored build can't error the callback pump.
Re-check those doc comments against the vendored build's actual signal
signatures at the same time.

**Steam Input status:** both players' `fire` (AnalogTrigger) and all five
Button actions (`grenade`/`roll`/`interact`/`revive`/`buy`) now read through
the action-handle API in `main.gd`'s `_gather_inputs()`, ORed with the
existing raw `Input`/`pad_pressed()` reads so nothing regresses when Steam
Input isn't active. `move`/`aim` stay on raw joystick axes -- they're
`StickPadGyro` motion actions in `actions.vdf` and don't need the handle API
to satisfy Deck Verified (gyro aim would be the reason to migrate them,
and nothing in this game uses gyro). Both P1 and P2 controller handles are
resolved in `_refresh_action_handles()`. None of this blocks Deck Verified
today since the *manifest* is staged and active (glyphs + rebinding already
work through Steam's own overlay/config) even before a real binary is
vendored.

**`assets/input/actions.vdf` validation:** without the Steamworks SDK (or a
vendored GodotSteam binary that can load it), `test_steam_bridge.gd`'s
`test_actions_vdf_is_well_formed_keyvalues()` runs a small hand-rolled
KeyValues/VDF balance-checker (matched quotes, matched braces) over the file
and confirms every action name `steam_bridge.gd`/`main.gd` expect is actually
declared in it. That is NOT the real Steam manifest parser and won't catch
every rule the Big Picture / Deck overlay enforces (e.g. localization-token
resolution, per-controller-type glyph mapping) -- run the manifest through
the actual Steamworks SDK controller config tester once a Steamworks app ID
and the SDK are available.
