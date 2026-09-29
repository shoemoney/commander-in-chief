#!/usr/bin/env bash
# Render two git refs and report, per signature shot, how many pixels moved.
#
# WHY. tools/gl_capture.sh made the game visible for the first time. Looking at
# two images and forming an opinion is the weak version of that: it is easy to
# convince yourself a change did something, and equally easy to miss that it
# did nothing. This iteration is the cautionary case — a hostile-sprite tint was
# changed on a measured clipping defect, the test suite went green, and the
# re-render moved 337 pixels of 230,400 and looked identical. A green test
# agreeing with a change that has NO effect is the worst outcome available, and
# only a pixel count caught it.
#
# So: A and B are both rendered by the same harness (deterministic — the tool
# seeds the engine RNG and renders at a fixed phase), then differenced. The
# number is the claim; the eye is only ever asked to explain it.
#
# USAGE
#   tools/gl_ab.sh <refA> [refB]
# Defaults to A = HEAD, B = the working tree. Prints one line per shot with the
# changed-pixel count and the max per-channel delta, then a verdict.
#
# A changed count near ZERO is the interesting result, not a boring one: it
# means the change under test is not reaching the screen, and the gate that
# "passed" proved nothing.
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CACHE="${HOME}/godot-gl"
A="${1:-HEAD}"
B="${2:-WORKTREE}"
cd "$REPO"

if [ -z "$(git status --porcelain)" ] && [ "$B" = "WORKTREE" ]; then
	echo "working tree is clean — B would render identically to A. Stash or edit something." >&2
	exit 1
fi

render () { # $1 = out dir
	mkdir -p "$1"
	SHOT_DIR="$1" tools/gl_capture.sh "$1" >/dev/null 2>&1
}

# Render A by stashing the tree and checking out the ref in a TEMP WORKTREE.
# A worktree, not a checkout: this must never move the caller's HEAD or discard
# uncommitted work, and a killed mid-render run must not leave the tree on a
# detached ref.
WT="$CACHE/ab"
rm -rf "$WT"
git worktree add --detach "$WT" "$A" >/dev/null 2>&1 || { echo "worktree add failed"; exit 1; }
render "$CACHE/shots_A"
( cd "$WT" && SHOT_DIR="$CACHE/shots_A" tools/gl_capture.sh "$CACHE/shots_A" >/dev/null 2>&1 )
git worktree remove --force "$WT" >/dev/null 2>&1

render "$CACHE/shots_B"

python3 - "$CACHE/shots_A" "$CACHE/shots_B" <<'PY'
import os, sys
try:
    from PIL import Image
except ImportError:
    print("PIL missing"); sys.exit(1)
A, B = sys.argv[1], sys.argv[2]
names = sorted(f for f in os.listdir(A) if f.endswith(".png"))
print("%-34s %10s %8s" % ("shot", "changed", "maxdelta"))
worst = 0.0
for n in names:
    pa, pb = os.path.join(A, n), os.path.join(B, n)
    if not os.path.exists(pb):
        print("%-34s %10s" % (n, "MISSING")); continue
    a = Image.open(pa).convert("RGB"); b = Image.open(pb).convert("RGB")
    if a.size != b.size:
        print("%-34s  size changed %s -> %s" % (n, a.size, b.size)); continue
    d = [abs(x - y) for x, y in zip(a.tobytes(), b.tobytes())]
    changed = sum(1 for v in d if v)
    mx = max(d)
    print("%-34s %10d %8d" % (n, changed, mx))
    worst = max(worst, changed)
print()
print("max changed pixels in any shot: %d" % worst)
if worst == 0:
    print("VERDICT: IDENTICAL — the change under test does not reach the screen.")
    print("         A green test for it is not evidence of anything.")
PY
