#!/usr/bin/env python3
"""Fan out the nano-banana (Gemini image) renders for the Iran-desert reskin
and post-process them into drop-in, Godot-import-ready legacy art-style sprites.

Reproduces the generate-desert-assets pass documented in
assets/legacy-art/desert_assets_source.md end to end:
  0. jobs are organized into asset GROUPS (cacti, scrub, dead -- see
     GROUPS below); dispatch_groups() fans out one subprocess PER GROUP,
     each one this same script re-invoked with `--group <name>` -- a real
     independent worker process, not just a loop -- and every job in a
     group gets that group's consistency note appended to its prompt so
     siblings render as one matching material family instead of
     independent rolls. Each group subprocess in turn fans out its own
     jobs as background image-toolkit processes, launched together and
     waited on together. Two levels of fan-out: groups, then jobs within
     a group.
  1. each render chroma-keyed to transparent, trimmed to its content, and
     letterboxed onto a square canvas matching the sprite it stands in for
  2. `godot --headless --import` to generate a first-pass .import (which
     lands on the project's default VRAM/BC-compressed texture preset) --
     run once by the top-level process after every group finishes, not
     per group (concurrent `--import` calls would race on the shared
     .godot/imported/ cache)
  3. each new *.png.import hand-corrected back to the existing legacy art-bake
     lossless convention (compress/mode=0, detect_3d/compress_to=0,
     vram_texture=false) and re-imported, so the BC compressor never mushes
     the low-poly outline silhouettes -- see
     tests/test_assets.gd::test_a1_legacy-art_bakes_are_lossless()

Usage:
    python3 tools/generate_desert_assets.py [--out-dir DIR] [--godot-bin PATH]
    python3 tools/generate_desert_assets.py --group cacti   # regen one group only
    python3 tools/generate_desert_assets.py --dry-run --skip-import \
        --out-dir /tmp/scratch                              # exercise the
        # group-dispatch wiring with synthetic placeholders, no API key,
        # no image-toolkit skill, and nothing under assets/ touched

Requires ~/.claude/skills/image-toolkit/scripts/generate.py and its usual
OPENROUTER_API_KEY (read from ~/.keys by that script) unless --dry-run.
Writes the final sprites straight into their assets/legacy-art/... homes --
rerun any time to regenerate a fresh batch (e.g. to restyle) before
committing.
"""
import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image, ImageDraw

DEFAULT_GENERATE_PY = (os.environ.get("IMAGE_TOOLKIT_GENERATE_PY")
                        or str(Path.home() / ".claude/skills/image-toolkit/scripts/generate.py"))
DEFAULT_GODOT = (shutil.which("godot")
                  or os.environ.get("GODOT_BIN")
                  or os.environ.get("GODOT")
                  or "/Applications/Godot.app/Contents/MacOS/Godot")
# Pinned so a reroll can't silently drift onto whatever generate.py's own
# default happens to be later -- every job in this file was prompted and
# tuned against this exact model.
IMAGE_MODEL = "google/gemini-3-pro-image-preview"
PROJECT_ROOT = Path(__file__).resolve().parent.parent

# The project's existing lossless legacy art-bake convention (no VRAM/BC
# compression, no detect_3d auto-recompress) is read live from a real
# checked-in import rather than duplicated into a hand-maintained template,
# so fix_import_settings() can never drift out of sync with the convention
# it's supposed to enforce.
REFERENCE_IMPORT = PROJECT_ROOT / "assets/legacy-art/tree_large.png.import"

RESAMPLE_LANCZOS = getattr(getattr(Image, "Resampling", Image), "LANCZOS")

STYLE = (
    "legacy 3D pack style low-poly 3D game asset render, faceted flat-shaded "
    "geometry, isometric top-down camera angle looking slightly downward, "
    "prop centered and fully in frame with generous margin, pure solid "
    "magenta background #FF00FF (not transparent, not white), no ground "
    "plane, no shadow, no text, no watermark"
)

# Jobs are fanned out per ASSET GROUP, not as one flat pile of 8: every job
# in a group appends the same GROUPS[group]["consistency"] note to the
# shared STYLE suffix, so e.g. the two cacti renders share explicit
# cross-references to each other's material instead of two independent
# rolls of the dice that happen to both say "sage-green". Groups are still
# launched together (fan-out concurrency is unchanged -- see main()); the
# grouping is a prompt-consistency and reporting axis, not a serialization
# one. A future group (e.g. a "tile" ground-texture group) drops in the
# same way: add a GROUPS entry, no other code changes.
GROUPS = {
    "cacti": {
        "consistency": "Match the same dusty sage-green low-poly cactus "
                        "material as the rest of the cacti group.",
        "jobs": [
            ("cactus_large", "A tall saguaro-style desert cactus cluster "
             "with two upright arms, dusty sage-green faceted low-poly "
             "surface with darker green shading crevices.",
             "cactus_large.png", 120),
            ("cactus_small", "A small cluster of round barrel cacti and "
             "prickly pear paddles, dusty sage-green faceted low-poly "
             "surface.", "cactus_small.png", 96),
        ],
    },
    "scrub": {
        "consistency": "Match the same sun-bleached dry-brush low-poly "
                        "material as the rest of the scrub group.",
        "jobs": [
            ("scrub", "A small sparse dry desert scrub bush with a few "
             "thin spiky low-poly branches, dusty olive-brown faceted "
             "surface.", "scrub.png", 72),
            ("tumbleweed", "A round classic tumbleweed, a tangled ball of "
             "dry dead brush and thorny twigs, faceted low-poly spherical "
             "silhouette, straw-tan and dry-brown coloring.",
             "decor/tumbleweed.png", 200),
            ("dry_shrub", "A row of four stacked rounded dry desert scrub "
             "mounds forming a long hedge-shaped bush line, sun-bleached "
             "olive-tan faceted low-poly surface, dense enough a soldier "
             "could crouch and hide behind it.", "decor/dry_shrub.png", 220),
        ],
    },
    "dead": {
        "consistency": "Match the same sooty black and ash-grey charred "
                        "low-poly material as the rest of the dead group.",
        "jobs": [
            ("cactus_dead1", "A charred blackened dead cactus husk, "
             "scorched and burnt, low-poly faceted surface, sooty black "
             "and ash-grey coloring, one broken stub arm.",
             "p2/cactus_dead1.png", 120),
            ("cactus_dead2", "A charred blackened dead cactus husk lying "
             "tilted, scorched and burnt, low-poly faceted surface, sooty "
             "black and ash-grey coloring, cracked surface.",
             "p2/cactus_dead2.png", 120),
            ("cactus_dead3", "A charred blackened dead tumbleweed husk, "
             "scorched and burnt tangled dry brush ball, low-poly faceted "
             "surface, sooty black and ash-grey coloring.",
             "p2/cactus_dead3.png", 120),
        ],
    },
}

# Flat (name, subject, dest, size, group) view derived from GROUPS -- the
# post-processing/import passes below don't care about grouping, only
# generation-time prompting and progress reporting do.
JOBS = [(name, subject, dest, size, group)
        for group, spec in GROUPS.items()
        for name, subject, dest, size in spec["jobs"]]


def chroma_key(im: Image.Image, thresh: int = 60) -> tuple[Image.Image, tuple[float, float, float]]:
    """Make the magenta backdrop transparent, sampling the key color from
    the corners since the raw render is a noisy matte, not a flat fill.
    Returns the keyed image plus the sampled key color, so callers can run
    a post-key sanity check against the same reference."""
    im = im.convert("RGBA")
    px = im.load()
    w, h = im.size
    corners = [px[0, 0], px[w - 1, 0], px[0, h - 1], px[w - 1, h - 1]]
    br, bg, bb = (sum(c[i] for c in corners) / 4 for i in range(3))
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            dist = ((r - br) ** 2 + (g - bg) ** 2 + (b - bb) ** 2) ** 0.5
            if dist < thresh:
                px[x, y] = (r, g, b, 0)
    return im, (br, bg, bb)


def check_key_quality(im: Image.Image, key_color: tuple[float, float, float],
                       dest_path: Path, fringe_thresh: int = 90, max_fringe_frac: float = 0.02) -> None:
    """Catch a bad chroma-key threshold before it ships: count opaque pixels
    still close to the sampled magenta key (a halo the key missed) rather
    than trusting the threshold blindly."""
    px = im.load()
    w, h = im.size
    br, bg, bb = key_color
    opaque = fringe = 0
    for y in range(h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            opaque += 1
            dist = ((r - br) ** 2 + (g - bg) ** 2 + (b - bb) ** 2) ** 0.5
            if dist < fringe_thresh:
                fringe += 1
    if opaque == 0:
        raise ValueError(f"{dest_path}: chroma-key left no opaque pixels at all")
    frac = fringe / opaque
    if frac > max_fringe_frac:
        raise ValueError(
            f"{dest_path}: {fringe}/{opaque} opaque pixels ({frac:.1%}) still near the "
            f"magenta key color -- chroma-key threshold likely too low, leftover fringe would ship")


def trim(im: Image.Image, pad: int = 6) -> Image.Image:
    bbox = im.getbbox()
    if not bbox:
        return im
    x0, y0, x1, y1 = bbox
    x0 = max(0, x0 - pad)
    y0 = max(0, y0 - pad)
    x1 = min(im.width, x1 + pad)
    y1 = min(im.height, y1 + pad)
    return im.crop((x0, y0, x1, y1))


def fit_square(im: Image.Image, size: int) -> Image.Image:
    im = im.copy()
    im.thumbnail((size, size), RESAMPLE_LANCZOS)
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    canvas.paste(im, ((size - im.width) // 2, (size - im.height) // 2), im)
    return canvas


def validate(im: Image.Image, dest_path: Path, size: int) -> None:
    if im.size != (size, size):
        raise ValueError(f"{dest_path}: expected {size}x{size}, got {im.size}")
    if im.getbbox() is None:
        raise ValueError(f"{dest_path}: fully transparent -- chroma-key ate the subject")


def fix_import_settings(png_path: Path) -> None:
    """Rewrite a freshly-`--import`-ed *.png.import back to the project's
    existing legacy art-bake convention. Takes REFERENCE_IMPORT (a real,
    already-correct checked-in import) and substitutes in only the two
    values Godot assigns itself for THIS file (uid, content hash, source
    path) -- so every other param, including ones nobody thought to add a
    check for, tracks the reference file exactly, forever."""
    imp_path = png_path.with_name(png_path.name + ".import")
    text = imp_path.read_text()

    uid_m = re.search(r'^uid="(uid://\w+)"$', text, re.M)
    hash_m = re.search(r'res://\.godot/imported/([\w.]+)-([0-9a-f]{16,})\.\w*\.?ctex', text)
    if not uid_m or not hash_m:
        raise ValueError(f"{imp_path}: couldn't find uid/hash in the default import")
    fname, h = hash_m.group(1), hash_m.group(2)

    for stale in (PROJECT_ROOT / ".godot/imported").glob(f"{fname}-{h}.*ctex"):
        stale.unlink()

    rel = png_path.resolve().relative_to((PROJECT_ROOT / "assets/legacy-art").resolve())
    ref = REFERENCE_IMPORT.read_text()
    ref = re.sub(r'^uid="uid://\w+"$', f'uid="{uid_m.group(1)}"', ref, count=1, flags=re.M)
    ref = re.sub(r'res://\.godot/imported/[\w.]+-[0-9a-f]{16,}\.ctex',
                 f'res://.godot/imported/{fname}-{h}.ctex', ref)
    ref = re.sub(r'source_file="res://assets/legacy-art/[^"]*"',
                 f'source_file="res://assets/legacy-art/{rel.as_posix()}"', ref, count=1)
    imp_path.write_text(ref)


def assert_lossless_legacy-art_import(png_path: Path) -> None:
    """The same check test_a1_legacy-art_bakes_are_lossless() runs, applied to
    just this file, so a bad rewrite fails loudly here instead of at the
    next full test run."""
    text = png_path.with_name(png_path.name + ".import").read_text()
    required = "compress/mode=0"
    forbidden = ("compress/mode=2", "detect_3d/compress_to=1", "vram_texture=true")
    if required not in text:
        raise ValueError(f"{png_path}.import: missing {required!r} after fix_import_settings()")
    bad = [cond for cond in forbidden if cond in text]
    if bad:
        raise ValueError(f"{png_path}.import still has {bad} after fix_import_settings()")


def resolve_godot(godot_bin: str) -> str:
    found = shutil.which(godot_bin)
    if found:
        return found
    p = Path(godot_bin)
    if p.exists() and os.access(p, os.X_OK):
        return str(p)
    raise SystemExit(f"error: Godot binary not found or not executable: {godot_bin!r}. "
                      "Pass --godot-bin, put `godot` on PATH, or set $GODOT.")


def run_godot_import(godot_bin: str) -> None:
    subprocess.run([godot_bin, "--headless", "--path", str(PROJECT_ROOT), "--import"],
                    check=True, capture_output=True, text=True)


def synth_dry_run_render(dest: Path) -> None:
    """--dry-run stand-in for a real nano-banana render: a small magenta
    square with an off-key rectangle in the middle -- enough real content
    for chroma_key/trim/fit_square/validate to run for real, so --dry-run
    proves the per-group dispatch/wait wiring end to end without an API
    key or the image-toolkit skill installed."""
    im = Image.new("RGB", (64, 64), (255, 0, 255))
    ImageDraw.Draw(im).rectangle([16, 16, 47, 47], fill=(120, 140, 90))
    im.save(dest)


def run_group(group: str, args: argparse.Namespace, raw_dir: Path,
              out_root: Path, generate_py: Path) -> int:
    """Run one asset group's full generate + post-process pipeline. This is
    the per-group subagent unit of work: dispatch_groups() below re-invokes
    this same script with `--group <name>` as an independent subprocess per
    group, so each group is its own OS-process worker running in parallel
    with its siblings; this function is also what that child process runs.
    Godot import is intentionally NOT done here -- it's a single shared
    step the top-level orchestrator runs once after every group finishes,
    since concurrent `godot --import` calls would race on the same
    .godot/imported/ cache."""
    jobs = [(name, subject, dest, size, group) for name, subject, dest, size in GROUPS[group]["jobs"]]
    print(f"[{group}] fanning out {len(jobs)} sprite render(s)"
          f"{' (dry-run)' if args.dry_run else ''}...")

    procs = []
    for name, subject, _dest, _size, grp in jobs:
        raw_path = raw_dir / f"{name}.png"
        if args.dry_run:
            synth_dry_run_render(raw_path)
            procs.append((name, raw_path, None))
            continue
        prompt = f"{subject} {GROUPS[grp]['consistency']} {STYLE}"
        cmd = [sys.executable, str(generate_py), prompt, "-o", str(raw_path), "--model", args.model]
        procs.append((name, raw_path, subprocess.Popen(
            cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)))

    failed = []
    for name, raw_path, proc in procs:
        if proc is None:  # dry-run: rendered synchronously above
            continue
        out, _ = proc.communicate()
        if proc.returncode != 0 or not raw_path.exists():
            failed.append(name)
            print(f"--- [{group}] generation failed: {name} (exit {proc.returncode}) ---", file=sys.stderr)
            print(out, file=sys.stderr)
    if failed:
        print(f"[{group}] generation failed for: {failed}", file=sys.stderr)
        return 1

    print(f"[{group}] post-processing (chroma-key -> trim -> letterbox -> validate)...")
    for name, _subject, dest, size, _grp in jobs:
        raw_path = raw_dir / f"{name}.png"
        im, key_color = chroma_key(Image.open(raw_path))
        check_key_quality(im, key_color, dest)
        im = fit_square(trim(im), size)
        validate(im, dest, size)
        dest_path = out_root / dest
        dest_path.parent.mkdir(parents=True, exist_ok=True)
        im.save(dest_path)
        print(f"  [{group}] {dest_path} ({im.width}x{im.height})")
    return 0


def dispatch_groups(args: argparse.Namespace, raw_dir: Path, out_root: Path,
                     generate_py: Path) -> tuple[int, list[Path]]:
    """Fan out one subprocess per asset group -- this script re-invoked
    with `--group <name>`, all launched together and waited on together.
    This is the literal "subagents per asset group" the goal asks for:
    each group is dispatched, runs, and reports back as an independent
    worker, not a single process looping over a flat job list."""
    self_path = str(Path(__file__).resolve())
    procs = []
    for group in GROUPS:
        cmd = [sys.executable, self_path, "--group", group,
               "--out-dir", str(out_root), "--raw-dir", str(raw_dir),
               "--generate-py", str(generate_py), "--model", args.model,
               "--skip-import"]
        if args.dry_run:
            cmd.append("--dry-run")
        procs.append((group, subprocess.Popen(
            cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)))

    failed = []
    for group, proc in procs:
        out, _ = proc.communicate()
        if out:
            print(out, end="" if out.endswith("\n") else "\n")
        if proc.returncode != 0:
            failed.append(group)
    if failed:
        print(f"group dispatch failed for: {failed}", file=sys.stderr)
        return 1, []

    dest_paths = [out_root / dest for spec in GROUPS.values()
                  for _name, _subject, dest, _size in spec["jobs"]]
    missing = [p for p in dest_paths if not p.exists()]
    if missing:
        print(f"expected outputs missing after group dispatch: {missing}", file=sys.stderr)
        return 1, []
    return 0, dest_paths


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out-dir", default=str(PROJECT_ROOT / "assets/legacy-art"),
                     help="assets/legacy-art root to write finished sprites into")
    ap.add_argument("--raw-dir", default=None,
                     help="scratch dir for the raw nano-banana renders "
                          "(default: a throwaway temp dir, never under the repo)")
    ap.add_argument("--godot-bin", default=DEFAULT_GODOT,
                     help="Godot headless binary used to bake .import sidecars "
                          "(default: `godot` on PATH, then $GODOT, then the "
                          "usual macOS app-bundle path)")
    ap.add_argument("--skip-import", action="store_true",
                     help="only generate + post-process; skip the two "
                          "godot --import passes (e.g. Godot isn't installed here)")
    ap.add_argument("--generate-py", default=DEFAULT_GENERATE_PY,
                     help="path to the image-toolkit skill's generate.py "
                          "(default: $IMAGE_TOOLKIT_GENERATE_PY, else "
                          "~/.claude/skills/image-toolkit/scripts/generate.py)")
    ap.add_argument("--model", default=IMAGE_MODEL,
                     help=f"image model slug passed to generate.py --model "
                          f"(default: {IMAGE_MODEL}, pinned so a reroll can't "
                          f"silently drift onto a different model)")
    ap.add_argument("--keep-raw", action="store_true",
                     help="keep the raw pre-chroma-key renders instead of "
                          "deleting the throwaway raw-dir on success")
    ap.add_argument("--group", choices=sorted(GROUPS), default=None,
                     help="internal: run only this one asset group's "
                          "generate+post-process pipeline and exit. This is "
                          "what dispatch_groups() invokes as each group's "
                          "subprocess; pass it yourself to regenerate a "
                          "single group without touching the others.")
    ap.add_argument("--dry-run", action="store_true",
                     help="skip the real nano-banana render and synthesize a "
                          "placeholder instead, so the per-group dispatch/"
                          "wait wiring can be exercised without an API key "
                          "or the image-toolkit skill. Requires --out-dir to "
                          "point outside assets/ (refuses the default) and "
                          "always implies --skip-import, so synthetic "
                          "placeholder pixels can never overwrite a "
                          "committed sprite or get baked into a real .import")
    args = ap.parse_args()

    out_root = Path(args.out_dir)
    generate_py = Path(args.generate_py)
    raw_dir = Path(args.raw_dir) if args.raw_dir else Path(tempfile.mkdtemp(prefix="nano_banana_raw_"))
    raw_dir.mkdir(parents=True, exist_ok=True)
    is_temp_raw_dir = args.raw_dir is None

    if args.dry_run:
        assets_root = (PROJECT_ROOT / "assets").resolve()
        out_resolved = out_root.resolve()
        under_assets = out_resolved == assets_root or assets_root in out_resolved.parents
        if under_assets:
            print(f"--dry-run refuses to write into {out_root} (inside the real "
                  f"assets/ tree) -- pass a scratch --out-dir so synthetic "
                  f"placeholder pixels can never overwrite a committed sprite.",
                  file=sys.stderr)
            return 1
        if not args.skip_import:
            print("--dry-run implies --skip-import (a synthetic placeholder must "
                  "never get baked into a real .import); forcing it.", file=sys.stderr)
            args.skip_import = True

    if not args.dry_run and not generate_py.exists():
        print(f"missing {generate_py} -- is the image-toolkit skill installed? "
              f"(pass --generate-py or set $IMAGE_TOOLKIT_GENERATE_PY)", file=sys.stderr)
        return 1

    if args.group:
        return run_group(args.group, args, raw_dir, out_root, generate_py)

    godot_bin = None
    if not args.skip_import:
        godot_bin = resolve_godot(args.godot_bin)  # fail fast, before spending API calls

    print(f"dispatching {len(GROUPS)} asset-group subagents "
          f"({', '.join(GROUPS)}) in parallel -- {len(JOBS)} sprites total "
          f"-- into {raw_dir} ...")
    rc, dest_paths = dispatch_groups(args, raw_dir, out_root, generate_py)
    if rc:
        return rc

    if is_temp_raw_dir and not args.keep_raw:
        shutil.rmtree(raw_dir, ignore_errors=True)

    if args.skip_import:
        print("skipping godot --import (--skip-import) -- run it yourself, "
              "then fix_import_settings() won't have run either.")
        return 0

    print(f"running {godot_bin} --import (pass 1: bake default .import)...")
    run_godot_import(godot_bin)

    print("correcting .import settings to the lossless legacy art-bake convention...")
    for dest_path in dest_paths:
        fix_import_settings(dest_path)
        assert_lossless_legacy-art_import(dest_path)

    print(f"running {godot_bin} --import (pass 2: bake corrected settings)...")
    run_godot_import(godot_bin)

    print("done. Run `godot --headless --path . -s res://tests/run_tests.gd` "
          "to confirm test_a1_legacy-art_bakes_are_lossless() agrees.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
