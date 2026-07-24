# Steam Cloud file whitelist

Commander In Chief needs no code to use Steam Cloud: everything the game
persists already lives under Godot's `user://` (see `SAVE_PATH`/`SAVE_TMP`/
`SAVE_BAK` in `src/main.gd`, `REPLAY_PATH` in `src/view/menu.gd`, and
`ACHIEVEMENTS_CACHE` in `src/steam/steam_bridge.gd`). Steam Cloud syncs
whatever paths are whitelisted in **Steamworks > App Admin > Cloud** against
the app's `steamsettings.vdf` / Auto-Cloud "root" + pattern config — no
`ISteamRemoteStorage` calls needed for a save this small.

On the platforms this project ships (`godot --path .` desktop targets),
`user://` resolves under the game's Cloud root to:

| File | Purpose |
|---|---|
| `ikari_best.cfg` (+ `.tmp` / `.bak`) | Bests, Hall of Fame, binds, settings, daily-run lock |
| `last_run.replay` | Last-run recording (WATCH LAST RUN) |
| `steam_achievements.cfg` | Offline achievement-unlock cache (see steam_bridge.gd) |

Whitelist pattern for the App Admin Cloud config: `*.cfg` and `*.replay` at
the Cloud root covers all three without listing them individually, and
without pulling in anything else (the game writes nothing else to `user://`).
