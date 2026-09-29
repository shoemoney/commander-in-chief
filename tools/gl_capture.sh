#!/usr/bin/env bash
# Render the signature shots on a machine whose windowed Godot cannot.
#
# WHY THIS EXISTS. tools/screenshots.gd needs a real framebuffer: it awaits
# RenderingServer.frame_post_draw, and under --headless that never fires (the
# tool detects and refuses that case, correctly). On macOS, a windowed Godot run
# from a non-interactive shell HANGS on every path tried — foreground, --write-
# movie, and LaunchServices `open -n` with a genuine Aqua session present.
# Verified, not assumed: even `godot --quit-after 5` with no tool at all hangs,
# so this is the environment, not the harness.
#
# CI already had the answer: .github/workflows/ci.yml installs xvfb on Linux and
# renders a GL capture there. So this script does the same thing LOCALLY, in a
# container, instead of fighting the window server.
#
# It is deliberately arm64-native: the macOS host is arm64, so the linux/arm64
# Godot build runs under emulation-free Docker. Do NOT switch this to
# linux/amd64 "because that is what CI uses" — that reintroduces the QEMU
# cross-compile trap for no benefit (there is no compile here, just a few
# seconds of rendering, but the arm64 image is a straight pull either way).
#
# The engine is the SAME build the suite is verified on: the pin comes from
# tools/versions.lock, and the Linux arm64 zip reports the identical commit
# short-hash as the local app (4.7.2.stable.official.ed1daf0bf).
#
# USAGE
#   tools/gl_capture.sh [OUT_DIR]
# Defaults to $HOME/godot-gl/shots. Prints the shot list and fails non-zero if
# the harness did not report "ALL SHOTS DONE".
#
# FIRST RUN fetches the engine into $HOME/godot-gl/godot and builds the image.
# Both caches are outside the repo on purpose — see the two path notes below.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CACHE="${HOME}/godot-gl"
OUT="${1:-$CACHE/shots}"
GODOT_VERSION="$(sed -n 's/^godot_version=//p' "$REPO/tools/versions.lock")"
# Normalise "4.7.2-stable" to the release tag "4.7.2-stable" (same string) and
# the asset name "Godot_v4.7.2-stable_linux.arm64.zip".
ASSET="Godot_v${GODOT_VERSION}_linux.arm64.zip"
# The release TAG is "4.7.2-stable" — there is no "-official" suffix on it, only
# on the ASSET filename. Getting that backwards yields a 404 page saved as a
# .zip, and unzip then reports a corrupt archive rather than a bad URL, which is
# a genuinely misleading failure.
URL="https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}/${ASSET}"

# Two macOS-Docker path traps this script exists partly to remember:
#   1. /var/folders and /tmp are NOT shared with the Docker VM. A bind mount
#      sourced from either silently becomes an empty DIRECTORY, and the tool
#      then reports success having written nothing. So the engine cache and the
#      output dir both live under $HOME, which IS shared.
#   2. Call the engine by ABSOLUTE path. xvfb-run resets PATH, and a bare
#      `godot` inside it fails with "godot: not found" while the same binary at
#      /godot works.
mkdir -p "$CACHE" "$OUT"

if [ ! -x "$CACHE/godot" ]; then
	echo "fetching $ASSET ..."
	curl -sL -o "$CACHE/godot.zip" "$URL" || { echo "download failed"; exit 1; }
	# A 404 body is a few hundred bytes; the real engine is ~73MB. Check before
	# unzip so a bad URL says "bad URL" instead of "corrupt archive".
	if [ "$(wc -c < "$CACHE/godot.zip" | tr -d ' ')" -lt 20000000 ]; then
		echo "download too small — bad URL: $URL" >&2
		exit 1
	fi
	unzip -o -q "$CACHE/godot.zip" -d "$CACHE" || { echo "unzip failed"; exit 1; }
	mv "$CACHE/Godot_v${GODOT_VERSION}_linux.arm64" "$CACHE/godot"
	chmod +x "$CACHE/godot"
fi

if ! docker image inspect godotgl:local >/dev/null 2>&1; then
	echo "building the gl image (first run only) ..."
	cat > "$CACHE/Dockerfile" <<'DOCKERFILE'
FROM ubuntu:24.04
# libxcursor1/libxinerama1/libxrandr2/libxi6/libxkbcommon0: without these Godot
# falls back x11 -> wayland -> "all display drivers failed" under Xvfb. The
# error names only the FIRST missing lib, so the fix is the whole X set.
RUN apt-get update && apt-get install -y --no-install-recommends \
      xvfb libfontconfig1 fonts-dejavu-core libgl1 libglx-mesa0 libegl1 libgles2 \
      libx11-6 libxext6 libxrender1 libxcursor1 libxinerama1 libxrandr2 libxi6 \
      libxkbcommon0 libxkbcommon-x11-0 libxfixes3 libxss1 libpulse0 \
 && rm -rf /var/lib/apt/lists/*
DOCKERFILE
	docker build -q -t godotgl:local "$CACHE" >/dev/null || { echo "image build failed"; exit 1; }
fi

rm -f "$OUT"/*.png 2>/dev/null
echo "rendering to $OUT ..."
LOG=$(docker run --rm --platform linux/arm64 \
	-v "$REPO:/repo" \
	-v "$CACHE/godot:/godot:ro" \
	-v "$OUT:/shots" \
	-e SHOT_DIR=/shots -e HOME=/tmp \
	godotgl:local \
	sh -c 'xvfb-run -a --server-args="-screen 0 1280x720x24" /godot --path /repo --rendering-method gl_compatibility -s res://tools/screenshots.gd' 2>&1)
echo "$LOG" | grep -E "SAVED|ALL SHOTS|UNUSABLE|ERROR" | tail -20

# The harness self-checks (dead frames, byte-identical frames) and refuses to
# report success on a bad run, so its own line is the gate. Do not trust the
# file count alone — a stale directory looks exactly like a good run.
if ! echo "$LOG" | grep -q "ALL SHOTS DONE"; then
	echo "CAPTURE FAILED — the harness did not report ALL SHOTS DONE" >&2
	exit 1
fi
n=$(ls -1 "$OUT"/*.png 2>/dev/null | wc -l | tr -d ' ')
echo "ok: $n shots in $OUT"
