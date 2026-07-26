#!/usr/bin/env bash
# Run a headless Godot script (the test suite by default) with a PRIVATE `user://`,
# so parallel worktrees / concurrent sessions cannot clobber each other.
#
# WHY: `user://` is keyed on the project NAME, not the checkout path, so every
# worktree of this project shares one
#   ~/Library/Application Support/Godot/app_userdata/Commander In Chief/
# Two symptoms, both seen repeatedly:
#   1. run_tests.gd's engine-error gate reads its own log back out of user://logs.
#      A sibling Godot rotates that log away -> "no log carried this run's marker"
#      -> a clean diff fails.
#   2. test_robustness.gd / test_menu_layout.gd stash and restore the REAL
#      ikari_best.cfg, so concurrent runs corrupt each other's fixtures.
# There is no CLI override: the path derives from the project name and
# use_custom_user_dir, both PROJECT settings. Per the docs it always hangs off the
# home dir (macOS `~/Library/Application Support/...`, Linux `$XDG_DATA_HOME` or
# `~/.local/share/...`), so a per-run HOME (with XDG_* cleared) is the only lever.
#
#   tools/run_tests.sh                            # full suite
#   SUITE=mechanics tools/run_tests.sh             # one suite
#   tools/run_tests.sh -s res://tools/smoke.gd     # any other headless script
#   GODOT=/path/to/godot tools/run_tests.sh        # non-default binary
#
# ponytail: a wrapper, not a runner change — the documented plain
# `godot --headless --path . -s res://tests/run_tests.gd` still works unchanged.
set -u

GODOT=${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}
ROOT=$(cd "$(dirname "$0")/.." && pwd)

# `pwd -P` is load-bearing, not tidiness: macOS $TMPDIR ends in a slash, so a raw
# mktemp path carries a `//`, and Godot's DirAccess rejects a `user://` open whose
# root path is not byte-identical to the realpath it gets back — DirAccess.open()
# then silently returns the PROJECT dir instead of user://. That makes the
# engine-error gate read the wrong files and report "no log carried this run's
# marker" — i.e. the exact failure this script exists to remove.
RUN_HOME=$(cd "$(mktemp -d "${TMPDIR:-/tmp}/cic-home.XXXXXX")" && pwd -P)
trap 'rm -rf "$RUN_HOME"' EXIT

[ $# -gt 0 ] || set -- -s res://tests/run_tests.gd

env -u XDG_DATA_HOME -u XDG_CONFIG_HOME -u XDG_CACHE_HOME "HOME=$RUN_HOME" \
	"$GODOT" --headless --path "$ROOT" "$@"
status=$?

# Fail CLOSED: if the redirect silently stopped working we would be back on the
# shared dir with nothing to show for it. Every debug run writes user://logs
# (debug/file_logging in project.godot), so an empty private HOME means the
# isolation did not happen — and a green run under that condition is worthless.
if [ -z "$(find "$RUN_HOME" -type d -name logs -print -quit 2>/dev/null)" ]; then
	echo "run_tests.sh: FAILED to isolate user:// — no logs under the private HOME ($RUN_HOME)." >&2
	echo "run_tests.sh: the run used the SHARED user:// dir; treat its result as void." >&2
	exit 1
fi

exit $status
