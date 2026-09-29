#!/usr/bin/env bash
# Each launch gets an untouched profile; preserve it for replay and diagnosis.
set -eu
PLAYTEST_ROOT=$(cd "$(dirname "$0")/.." && pwd)
PLAYTEST_PROFILE=$(mktemp -d "${TMPDIR:-/tmp}/cic-newcomer.XXXXXX")
PLAYTEST_PROFILE=$(cd "$PLAYTEST_PROFILE" && pwd -P)
PLAYTEST_GODOT=${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}
# Release templates reject --path. Standalone mode runs only the executable's
# own packaged project, while retaining the same isolated save profile.
if [ "${1:-}" = "--standalone" ]; then
  shift
else
  set -- --path "$PLAYTEST_ROOT" "$@"
fi
printf 'Newcomer profile and logs: %s\n' "$PLAYTEST_PROFILE"
git -C "$PLAYTEST_ROOT" rev-parse HEAD
git -C "$PLAYTEST_ROOT" diff --stat
env -u XDG_DATA_HOME -u XDG_CONFIG_HOME -u XDG_CACHE_HOME "HOME=$PLAYTEST_PROFILE" \
  "$PLAYTEST_GODOT" "$@"
