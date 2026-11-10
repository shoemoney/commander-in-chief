#!/usr/bin/env bash
# Run the BLOCKING jobs of .github/workflows/ci.yml locally, on one machine.
#
#   tools/ci_local.sh              # lint + test + gl-capture
#   tools/ci_local.sh lint test    # a subset (any of: lint test gl)
#   CI_LOCAL_LOGS=/abs tools/ci_local.sh   # keep the logs somewhere specific
#
# WHY this exists: hosted CI is a backstop, and a backstop that is not running is not
# one. On 2026-11-10 every job on `main` failed in 3 seconds with zero steps executed
# (the runner never started the job: an account-level problem on the hosting side) —
# nothing about the code, and nothing a push could fix. This is the same gate list,
# mirrored step for step, so "green" still means something while that is true.
#
# It mirrors ci.yml; it does not replace it. What it CANNOT tell you is the one thing
# the hosted matrix exists for: that the determinism goldens are bit-identical on
# macOS-arm64 and Windows as well as on the box you ran this on. It also skips the
# export-smoke job (needs export templates) and the advisory perf/soak jobs.
#
# Every Godot process gets a private HOME, so this is safe to run beside other
# sessions — same reason as tools/run_tests.sh, which it uses wherever that fits.
set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
GODOT=${GODOT:-/Applications/Godot.app/Contents/MacOS/Godot}
if [ ! -x "$GODOT" ] && command -v godot >/dev/null 2>&1; then
	GODOT=$(command -v godot)
fi
export GODOT
LOGS=${CI_LOCAL_LOGS:-$(mktemp -d "${TMPDIR:-/tmp}/cic-ci.XXXXXX")}
mkdir -p "$LOGS"
LOGS=$(cd "$LOGS" && pwd -P)
LEAK_RE='were leaked|resources still in use at exit|leaked [0-9]+ bytes'
FAILED=()
cd "$ROOT" || exit 2

# Raw Godot under a private HOME (the steps below need their own stdout checks, so
# they cannot go through run_tests.sh, which owns a different set of gates).
gd() {
	local home
	home=$(cd "$(mktemp -d "${TMPDIR:-/tmp}/cic-ci-home.XXXXXX")" && pwd -P)
	env -u XDG_DATA_HOME -u XDG_CONFIG_HOME -u XDG_CACHE_HOME "HOME=$home" "$@"
	local rc=$?
	rm -rf "$home"
	return $rc
}

step() { # step <name> <command...>  — the command is the whole gate; non-zero = red
	local name=$1; shift
	printf '  %-34s ' "$name"
	if "$@" >"$LOGS/$name.out" 2>&1; then echo ok; else echo "FAIL  (see $LOGS/$name.out)"; FAILED+=("$name"); fi
}

smoke() {
	gd "$GODOT" --headless --path . -s res://tools/smoke.gd >"$LOGS/smoke.log" 2>&1
	python3 tools/verify_runtime_log.py "$LOGS/smoke.log" --require "SMOKE OK" || return 1
	grep -q "SMOKE OK" "$LOGS/smoke.log" || return 1
	! grep -q "SCRIPT ERROR" "$LOGS/smoke.log" || return 1
	! grep -qE "$LEAK_RE" "$LOGS/smoke.log"
}
quiesce() {
	gd "$GODOT" --headless --path . --fixed-fps 60 -s res://tools/verify_quiesce.gd >"$LOGS/quiesce.log" 2>&1
	grep -q 'QUIESCE PASS frozen=false' "$LOGS/quiesce.log" || return 1
	grep -q 'QUIESCE PASS frozen=true' "$LOGS/quiesce.log" || return 1
	! grep -qE "^ERROR:|SCRIPT ERROR|was leaked|$LEAK_RE" "$LOGS/quiesce.log"
}
quit_routes() {
	local route
	for route in menu window paused-window; do
		QUIT_PROBE_ROUTE="$route" gd "$GODOT" --headless --path . -s res://tools/verify_game_quit.gd >"$LOGS/quit-$route.log" 2>&1
		grep -q "QUIT DRAIN OBSERVED" "$LOGS/quit-$route.log" || { echo "route $route: no drain"; return 1; }
		! grep -qE "^ERROR:|SCRIPT ERROR|was leaked|$LEAK_RE" "$LOGS/quit-$route.log" || { echo "route $route: error/leak"; return 1; }
	done
}
e2e() {
	gd "$GODOT" --headless --path . -s res://tools/e2e_playthrough.gd >"$LOGS/e2e.log" 2>&1
	python3 tools/verify_runtime_log.py "$LOGS/e2e.log" --require "0 FAIL ===" || return 1
	grep -qE '^\[E2E\] === [1-9][0-9]* checks, 0 FAIL ===$' "$LOGS/e2e.log"
}
speech() {
	gd "$GODOT" --headless --path . -s res://tools/verify_run_speech.gd >"$LOGS/speech.log" 2>&1
	python3 tools/verify_runtime_log.py "$LOGS/speech.log" --require "RUN SPEECH PASS: 16 checks, 0 failures"
}
suite() {
	tools/run_tests.sh >"$LOGS/test_output.log" 2>&1 || { tail -5 "$LOGS/test_output.log"; return 1; }
	grep -qE "^PASS —" "$LOGS/test_output.log" || return 1
	! grep -q "SCRIPT ERROR" "$LOGS/test_output.log"
}
gl_probe() {
	command -v xvfb-run >/dev/null 2>&1 || { echo "xvfb-run not installed"; return 1; }
	# --audio-driver Dummy is the one deliberate difference from ci.yml: a headless box
	# with no sound card makes ALSA fail to open a device, Godot prints an engine
	# `ERROR: ... ERR_CANT_OPEN` and falls back to the dummy driver anyway — and
	# verify_runtime_log.py (correctly) fails any log carrying an ERROR line. Asking for
	# the dummy driver up front removes the machine-specific noise without touching
	# anything the probe measures, which is pixels.
	gd xvfb-run -a "$GODOT" --path . --rendering-method gl_compatibility --fixed-fps 60 \
		--audio-driver Dummy -s res://tools/probe_concussion_hud.gd >"$LOGS/probe.log" 2>&1
	grep -q "PROBE OK" "$LOGS/probe.log" || return 1
	! grep -q "SCRIPT ERROR" "$LOGS/probe.log" || return 1
	python3 tools/verify_runtime_log.py "$LOGS/probe.log" --require "PROBE OK" || return 1
	python3 - "$LOGS/probe.log" <<'PY'
import re, sys
keeps = re.findall(r"centre \d+->\d+ \(keep ([0-9.]+)", open(sys.argv[1]).read())
if not keeps:
    sys.exit("no centre keep ratios found in probe.log")
bad = [k for k in keeps if float(k) <= 0.75]
if bad:
    sys.exit(f"centre-retention {bad} <= 0.75 — concussion warp smeared the player")
print(f"centre-retention ok: {keeps}")
PY
}

job_lint() {
	echo "lint:"
	step import          gd "$GODOT" --headless --path . --import
	step lint_sim        tools/run_tests.sh -s res://tools/lint_sim.gd
	step lint_assets     tools/run_tests.sh -s res://tools/lint_assets.gd
	step i18n            python3 tools/i18n_check.py
	step review_selftest python3 tools/loop_review.py selftest
	local t
	for t in test_build_steam_candidates test_verify_runtime_log test_verify_native_export \
			test_package_attribution test_verify_export_content; do
		step "py_$t" python3 -m unittest discover -s tools -p "$t.py"
	done
	step export_content  python3 tools/verify_export_content.py --godot "$GODOT"
}
job_test() {
	echo "test:"
	[ -d .godot ] || step import gd "$GODOT" --headless --path . --import
	step smoke        smoke
	step quiesce      quiesce
	step quit_routes  quit_routes
	step e2e          e2e
	step speech       speech
	step suite        suite
}
job_gl() {
	echo "gl-capture:"
	step gl_probe gl_probe
}

[ $# -gt 0 ] || set -- lint test gl
for job in "$@"; do
	case "$job" in
		lint) job_lint ;;
		test) job_test ;;
		gl) job_gl ;;
		*) echo "ci_local.sh: unknown job '$job' (lint | test | gl)" >&2; exit 2 ;;
	esac
done

echo
if [ ${#FAILED[@]} -eq 0 ]; then
	echo "CI LOCAL: PASS  (logs: $LOGS)"
	[ -n "${CI_LOCAL_LOGS:-}" ] || rm -rf "$LOGS"
	exit 0
fi
echo "CI LOCAL: FAIL — ${FAILED[*]}  (logs: $LOGS)"
exit 1
