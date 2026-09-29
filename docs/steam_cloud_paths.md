# Local persistence paths and Steam Cloud review

These are paths written by the game under Godot's `user://`. They are not
evidence that Steam Cloud is configured, enabled, or tested on the intended app.

| Path | Local purpose and ownership |
|---|---|
| `ikari_best.cfg` and `.bak` | Bests, Hall of Fame, bindings, settings and daily-run lock; currently shared within the OS game profile |
| `last_run.replay` | Last-run recording; currently shared within the OS game profile |
| `steam_achievements.cfg` and `.bak` | Anonymous/legacy achievement history; never automatically assigned to a Steam account |
| `steam_accounts/<SteamID>/achievements.cfg` and `.bak` | Achievements belonging to the identified Steam account |
| `steam_input/actions.vdf` | Regenerable staged input manifest, not player progress |

Achievement saves are now schema version 1 with a stored account identifier.
The ownerless legacy format is accepted only at the anonymous path. Signing in
does not copy, delete, or upload that unattributed history. Each account loads
its own cache before requesting its stats refresh; successful replies from a
different account cannot trigger reconciliation.

Writes use a flushed temporary file and replacement rename, retaining a prior
valid backup. On malformed primary data, the backup can restore the previous
snapshot; this does not recover progress newer than that snapshot. A corrupt
primary is never copied over the backup during recovery. Newer schemas or
mismatched owners are preserved without loading or overwriting them.

Do not apply the old broad `*.cfg` recommendation without reviewing the Cloud
configuration. Account-specific paths require a deliberately scoped configuration
and tests with separate accounts/devices; temporary files and the staged manifest
are not Cloud save content. No Steamworks settings were changed by this repair.

## Verified locally

- A regression test reproduced cross-account achievement transfer before repair.
- Account separation, legacy preservation, schema/owner rejection and backup
  recovery pass against controlled filesystem fixtures.
- `tools/verify_achievement_persistence.gd` saves in one Godot process, then
  separately launches another-account, original-account and anonymous reads.
  Run it through `tools/run_tests.sh` to give every child one private test profile.
  It uses mock identities, not live Steam accounts.

## Still unverified

Live Steam account switching, offline-client behavior, remote sync/conflicts,
and the intended app's Cloud rules require actual service/hardware testing.
Bests/settings/replay ownership remains OS-profile-scoped; do not describe all
player saves as account-isolated because the achievement cache now is.
