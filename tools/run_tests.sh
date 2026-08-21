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

RUN_LOG="$RUN_HOME/stdout.log"

env -u XDG_DATA_HOME -u XDG_CONFIG_HOME -u XDG_CACHE_HOME "HOME=$RUN_HOME" \
	"$GODOT" --headless --path "$ROOT" "$@" 2>&1 | tee "$RUN_LOG"
status=${PIPESTATUS[0]}

# Fail CLOSED: if the redirect silently stopped working we would be back on the
# shared dir with nothing to show for it. Every debug run writes user://logs
# (debug/file_logging in project.godot), so an empty private HOME means the
# isolation did not happen — and a green run under that condition is worthless.
if [ -z "$(find "$RUN_HOME" -type d -name logs -print -quit 2>/dev/null)" ]; then
	echo "run_tests.sh: FAILED to isolate user:// — no logs under the private HOME ($RUN_HOME)." >&2
	echo "run_tests.sh: the run used the SHARED user:// dir; treat its result as void." >&2
	exit 1
fi

# Shutdown leak gate. Godot prints these AFTER the file logger is torn down, so
# they exist only on the process's stdout -- run_tests.gd::_gate_engine_errors
# reads user://logs and structurally CANNOT see them (its log's last line is the
# PASS line). This wrapper and ci.yml are the only two places that own stdout.
#
# Gated at ZERO, with no floor and no exemption -- measured, not assumed. Two
# distinct causes produce these identical lines, and the message below names both
# because the count alone does not tell them apart:
#
#   1. ORPHANED NODE MEMBERS. A Node subclass that allocates Node members at
#      DECLARATION and only add_child()s them in _ready() orphans every one of them
#      when freed without ever entering a SceneTree -- exactly what a headless test
#      does. Baseline on 7bed222 was 265 RIDs / 5192 ObjectDB / 8 resources.
#   2. AUDIO STILL PLAYING AT EXIT. Godot destroys the AudioServer after
#      ObjectDB::cleanup, so a tool that boots src/main.tscn and quits mid-cue
#      reports its live streams as leaks (e2e_playthrough: 30 ObjectDB + a retained
#      cmd_levelstart_6.mp3, on a run with 0 failing checks). That is a teardown
#      artifact, NOT a defect -- but it is indistinguishable here, so the headless
#      tools that boot the real scene (smoke, e2e_playthrough, perf_probe) tear down
#      through tools/quiesce.gd instead of this gate carrying an exception for them.
#      Each reaches zero on 6-of-6 runs; before quiesce, smoke sat at 2 and
#      e2e_playthrough at 30.
#
# Godot words RID leaks two different ways ('N RIDs of type "X" were leaked' from
# ObjectDB, 'N RID allocations of type ...' from RID_Owner) and reports GL texture
# leaks in bytes, so the pattern matches the shared substrings, not one sentence.
# Window: greps the ENTIRE run output (~1300 lines / ~31 s); the defect prints
# exactly 3 lines, once, at exit. Window strictly exceeds the defect.
if grep -qE 'were leaked|resources still in use at exit|leaked [0-9]+ bytes' "$RUN_LOG"; then
	echo "run_tests.sh: shutdown leak diagnostics on stdout -- objects outlived the run." >&2
	grep -E 'were leaked|resources still in use at exit|leaked [0-9]+ bytes' "$RUN_LOG" >&2
	echo "run_tests.sh: two causes print these same lines -- rule them out in this order:" >&2
	echo "run_tests.sh:   1. a Node allocated at DECLARATION and only add_child()'d in _ready()" >&2
	echo "run_tests.sh:      orphans every member when freed outside a SceneTree. Free them, or" >&2
	echo "run_tests.sh:      free the stub. Run again with --verbose to name the classes." >&2
	echo "run_tests.sh:   2. audio still playing at quit(): the AudioServer is torn down AFTER" >&2
	echo "run_tests.sh:      ObjectDB, so live streams count as leaks. If --verbose names only" >&2
	echo "run_tests.sh:      AudioStream* classes, this tool boots src/main.tscn and needs" >&2
	echo "run_tests.sh:      'await Quiesce.teardown(self, main)' before quit() -- see tools/quiesce.gd." >&2
	exit 1
fi

exit $status
