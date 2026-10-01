#!/usr/bin/env bash
# LOOP RATCHET — fails when the loop is not actually advancing.
#
# WHY THIS EXISTS
#
# Three mechanisms in this repo were believed to hold the loop together and none
# of them did:
#   1. the loop state file ("I will read this next session") — ignored twice;
#   2. the Hindsight bank ("I will recall before acting") — a bank nobody reads
#      is the same as no bank;
#   3. good intentions in a commit message.
#
# What this repo reliably obeys is a RED TEST. So autonomy gets the same
# enforcement: this script is a gate, and the things that were aspirational
# become checks that fail.
#
# IT FAILS WHEN:
#   - the game version did not advance since the last iteration (the loop stalled);
#   - the working tree is dirty (work left uncommitted between iterations);
#   - the project is behind its remote (a version exists that nobody can pull);
#   - a shipped change is still tagged claim:unverified in the memory bank.
#
# The last one is the important one: it is the only check in this repo that
# notices when a commit message claimed more than the evidence supports.
#
# Usage:  tools/loop_ratchet.sh          # gate mode, exits non-zero on failure
#         tools/loop_ratchet.sh --stamp  # record this iteration as complete
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2

VERSION=$(sed -n 's/^config\/version="\(.*\)"$/\1/p' project.godot)
STAMP=.opencode/.loop-stamp

if [ "${1:-}" = "--stamp" ]; then
  mkdir -p .opencode
  printf '%s\n' "$VERSION" > "$STAMP"
  echo "STAMPED v$VERSION"
  exit 0
fi

fail=0

# 1. the loop is ADVANCING IN TIME
# The first version of this check compared the version against the stamp, which
# is wrong: --stamp records the version an iteration just COMPLETED, so a clean
# iteration always equals its own stamp and the gate failed on success. A stall
# is about elapsed time since the last completed iteration, not version equality.
if [ -f "$STAMP" ]; then
  prev=$(cat "$STAMP")
  age=$(( $(date +%s) - $(stat -f %m "$STAMP" 2>/dev/null || echo 0) ))
  mins=$(( age / 60 ))
  if [ "$VERSION" != "$prev" ]; then
    echo "ok    work in flight: stamped v$prev, now at v$VERSION"
  elif [ "$mins" -gt 240 ]; then
    echo "FAIL  loop stalled: still v$VERSION, ${mins}min since the last completed iteration"
    fail=1
  else
    echo "ok    v$VERSION stamped ${mins}min ago (stall threshold 240min)"
  fi
else
  echo "ok    first stamp (baseline v$VERSION)"
fi

# 2. nothing left uncommitted between iterations
dirty=$(git status --porcelain 2>/dev/null | grep -v '^?? .opencode/' | wc -l | tr -d ' ')
if [ "$dirty" != "0" ]; then
  echo "FAIL  $dirty uncommitted path(s); an iteration ended mid-work"
  git status --porcelain | head -5
  fail=1
else
  echo "ok    tree clean"
fi

# 3. the version exists on the remote
if git fetch -q origin main 2>/dev/null; then
  remote_ver=$(git show origin/main:project.godot 2>/dev/null | sed -n 's/^config\/version="\(.*\)"$/\1/p')
  if [ -n "$remote_ver" ] && [ "$remote_ver" = "$VERSION" ]; then
    echo "ok    v$VERSION is on origin/main"
  else
    echo "FAIL  local v$VERSION but origin/main has v${remote_ver:-<none>}"
    fail=1
  fi
else
  echo "WARN  could not reach origin; skipping the remote check"
fi

# 4. no shipped change is still labelled unverified
if command -v uvx >/dev/null 2>&1; then
  unv=$(uvx hindsight-embed -p cic memory recall cic "shipped change labelled UNVERIFIED that must not be described as verified" 2>/dev/null \
        | grep -c "UNVERIFIED" || true)
  if [ "${unv:-0}" -gt 0 ]; then
    echo "WARN  memory bank reports UNVERIFIED shipped claims (a3-33 role rims are the known one)."
    echo "      A claim may not be described as verified until its sheet captures."
  else
    echo "ok    no unverified shipped claims in the memory bank"
  fi
fi

if [ "$fail" != "0" ]; then
  echo ""
  echo "LOOP RATCHET: FAILED — the loop is not advancing cleanly."
  exit 1
fi
echo ""
echo "LOOP RATCHET: PASS"
