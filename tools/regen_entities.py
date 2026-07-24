#!/usr/bin/env python3
"""Regenerate entity sprites from their own art as the reference image.

Why this exists: assets/art/{mil2,decor,p2,cast2} are legacy art-derived bakes and are
the public-release blocker (see OPEN_SOURCE_CHECKLIST.md). This regenerates them
as owned generative-AI art, feeding the EXISTING sprite in as the reference image
so silhouette / orientation / scale carry over and the game keeps reading the same.

It deliberately reuses generate_desert_assets.py's post-processing (trim /
fit_square / import-sidecar rewrite / lossless assert) rather than reinventing it --
that pipeline is already proven and test-pinned.

    python3 tools/regen_entities.py --category vehicle          # whole batch
    python3 tools/regen_entities.py --only technical            # one sprite
    python3 tools/regen_entities.py --category vehicle --dry-run

Output lands beside the original as <name>.regen.png for REVIEW; nothing is
installed over the shipped sprite until you pass --install (so a bad roll can
never silently overwrite working art).
"""
from __future__ import annotations

import argparse
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
from generate_desert_assets import (  # noqa: E402  (reuse the proven pipeline)
    PROJECT_ROOT,
    assert_lossless_art_import,
    check_key_quality,
    chroma_key,
    fit_square,
    fix_import_settings,
    resolve_godot,
    run_godot_import,
    trim,
)

GENERATE = Path.home() / ".claude/skills/image-toolkit/scripts/generate.py"

# --- Prompt templates, one per category -------------------------------------
# These are NOT interchangeable. The 2026-07-24 pilot established that the model
# defaults to a heroic FRONT portrait for humans and to PHOTOREALISM for props --
# both wrong for a 96px top-down sprite -- so each category needs its own
# corrective language. Vehicles were the only category that worked unprompted.
STYLE = ("Flat low-poly STYLIZED GAME ASSET art (NOT photorealistic): simple flat colour "
         "fills, minimal shading, bold readable shapes that stay legible when scaled down "
         "to a {size}-pixel sprite. NO photographic texture, NO fine grain, NO text. "
         "Desert-war palette: dusty tan, olive-drab and weathered steel. "
         # Asking for a transparent background does NOT work -- the 2026-07-24 vehicle
         # batch came back 0% transparent on all 9 (opaque white) despite asking. Match
         # generate_desert_assets.py: demand a flat magenta matte and chroma-key it out.
         "Solid flat magenta background #FF00FF (NOT transparent, NOT white), no ground, "
         "no shadow, no border, subject centred and filling the frame.")

TEMPLATES = {
    # Vehicles read naturally from overhead, BUT the 2026-07-24 in-game parade (rendered
    # through the real _spr at real Art.SCALE) graded the reference-faithful batch a C+:
    # every identifying feature -- radar dish, mounted MG, rocket rack -- washed out at the
    # real 57-79px on-screen size, and the olive Art.tint multiply flattened the mid-tones
    # into mush. Arcade sprites need EXAGGERATION, not fidelity, so the template now leads
    # with the on-screen budget and the hero feature.
    "vehicle": ("Top-down orthographic sprite of {subject}, viewed from directly overhead at a "
                "strict 90-degree bird's-eye angle, matching the ORIENTATION of the reference "
                "image (same nose direction).\n"
                "CRITICAL — this sprite is displayed at only about {onscreen} PIXELS on screen, so "
                "design for that size, not for a close-up:\n"
                "- {hero} MUST be OVERSIZED and unmistakable, occupying roughly a third of the "
                "sprite. Exaggerate it far beyond realistic scale.\n"
                "- Build a DISTINCT OUTER SILHOUETTE that could not be confused with any other "
                "military vehicle when shrunk to a thumbnail.\n"
                "- Use STRONG VALUE CONTRAST: near-black shadowed recesses against bright sunlit "
                "top surfaces. Avoid flat mid-tone fills -- they turn to mush.\n"
                "- Chunky bold shapes, thick forms, NO thin lines or fine detail (they vanish).\n"
                + STYLE),
    # Props drift photoreal without the explicit style clamp (pilot: the barrel came
    # back as a rusted photo, and drifted blue out of the desert palette).
    "prop": ("Top-down orthographic sprite of {subject}, seen from directly overhead at a strict "
             "90-degree bird's-eye angle. Match the silhouette and proportions of the reference "
             "image. " + STYLE),
    # Characters are the hard case: the model wants to draw a portrait. The camera has
    # to be described as a physical ceiling camera, and the occlusion spelled out.
    "character": ("A video-game sprite viewed from a CEILING CAMERA looking straight DOWN at the "
                  "ground. Subject: {subject}, seen from directly above. Because the camera is "
                  "directly overhead you can ONLY see the TOP of the head, the tops of the "
                  "shoulders, the upper arms angled outward, and any weapon held flat across the "
                  "chest. The FACE IS NOT VISIBLE. The legs are largely HIDDEN beneath the torso "
                  "and shoulders. This is a strict overhead floor-plan view, NOT a portrait, NOT "
                  "a front view, NOT three-quarter. " + STYLE),
}

# --- The batch manifest ------------------------------------------------------
# subject = what to draw. Keep it concrete; the reference image carries the pose.
# subject / hero / onscreen. `onscreen` is the REAL drawn size (source px * Art.SCALE),
# and `hero` is the one feature that has to survive at that size -- both are interpolated
# into the prompt so the model designs to the actual pixel budget.
VEHICLES = {
    # NOTE: technical.png is shared by the LIVE m_technical AND wreck_technical, so it must
    # stay a live vehicle -- do not prompt it as burnt/destroyed like apc/light_tank.
    "mil2/technical": (
        "an armed militia pickup truck (a 'technical'): open rear cargo bed with a soldier's "
        "heavy machine gun mounted on a big circular turret ring",
        "the machine gun assembly in the rear bed, drawn as a huge near-black gun barrel on a "
        "bold dark ring that fills the whole cargo bed and clearly overhangs the tailgate -- it "
        "must be the first thing the eye catches, far larger than realistic", 58),
    "mil2/apc": (
        "a boxy armoured personnel carrier, seen as a burnt-out WRECK: blackened, hollowed, hull breached",
        "the charred blast hole torn open in the hull roof, ringed with black scorching", 31),
    "mil2/light_tank": (
        "a light battle tank, seen as a destroyed WRECK: blackened hull, turret blown askew",
        "the long main gun barrel jutting out at a broken angle from a scorched turret", 27),
    "mil2/radar_tank": (
        "a tracked military radar vehicle",
        "an enormous circular dish antenna dominating the hull, drawn as a bold ringed disc", 75),
    "mil2/rocket_truck": (
        "a military multiple-rocket-launcher truck",
        "a massive block of rocket tubes drawn as a bold dark honeycomb grid of circles", 75),
    "mil2/heli_attack2": (
        "a lean predatory attack helicopter, narrow fuselage, stub weapon wings bristling with rockets",
        "the four long rotor blades as thick bold bars plus the sharply pointed narrow nose", 75),
    "mil2/heli_transport": (
        "a fat heavy-lift transport helicopter with a wide slab-sided cargo body, clearly BULKIER and rounder than an attack helicopter",
        "the very wide rounded cargo hull with a broad rotor disc -- read as FAT, not sleek", 76),
    "mil2/jet": (
        "a swept-wing military fighter jet",
        "the sharp arrowhead wing sweep and pointed nose", 79),
    "mil2/drone": (
        "a small quadcopter reconnaissance drone",
        "four thick rotor arms forming a bold unmistakable X, with chunky dark rotor discs at each tip", 16),
}
CATEGORIES = {"vehicle": VEHICLES}


def target_size(png: Path) -> int:
    with Image.open(png) as im:
        w, h = im.size
    if w != h:
        raise ValueError(f"{png}: expected a square canvas, got {w}x{h}")
    return w


def generate_one(key: str, spec: tuple, category: str, dry_run: bool) -> tuple[str, bool, str]:
    src = PROJECT_ROOT / "assets/art" / f"{key}.png"
    if not src.exists():
        return key, False, f"missing source sprite {src}"
    size = target_size(src)
    out = src.with_suffix(".regen.png")
    subject, hero, onscreen = spec
    prompt = TEMPLATES[category].format(subject=subject, hero=hero,
                                       onscreen=onscreen, size=size)

    if dry_run:
        return key, True, f"[dry-run] {size}px <- {prompt[:70]}..."

    proc = subprocess.run(
        [sys.executable, str(GENERATE), prompt, "-i", str(src), "-o", str(out)],
        capture_output=True, text=True, timeout=600,
    )
    if proc.returncode != 0 or not out.exists():
        return key, False, (proc.stderr or proc.stdout or "generate.py failed").strip()[-200:]

    # Post-process, same order as the desert pipeline: key the magenta matte out,
    # verify no halo survived, then crop to the alpha bbox and refit the ORIGINAL
    # canvas exactly -- main.gd's draw scales are tuned per-sprite, so the on-screen
    # footprint must not move.
    with Image.open(out) as raw:
        keyed, key_color = chroma_key(raw.convert("RGBA"))
    im = fit_square(trim(keyed, pad=2), size)
    if im.getbbox() is None:
        out.unlink(missing_ok=True)
        return key, False, "chroma-key ate the whole subject (backdrop too close to the art?)"
    try:
        check_key_quality(im, key_color, out)
    except ValueError as exc:
        out.unlink(missing_ok=True)
        return key, False, str(exc)[-160:]
    im.save(out)
    opaque = sum(1 for v in im.getchannel("A").tobytes() if v > 15) / (size * size)
    return key, True, f"{size}x{size} ({opaque:.0%} opaque) -> {out.relative_to(PROJECT_ROOT)}"


def install(key: str, godot_bin: str) -> str:
    """Promote <name>.regen.png over the shipped sprite, then repair its import
    sidecar to the project's lossless convention and assert it stuck."""
    src = PROJECT_ROOT / "assets/art" / f"{key}.png"
    regen = src.with_suffix(".regen.png")
    if not regen.exists():
        return f"{key}: no .regen.png to install"
    regen.replace(src)
    # Godot will have already imported the .regen.png while it sat in the tree, leaving a
    # <name>.regen.png.import sidecar behind once the PNG itself moves. That orphan keeps
    # DEFAULT settings (compress/mode=2 + detect_3d), which is exactly what
    # test_a1_art_bakes_are_lossless forbids -- it failed the suite until this cleanup.
    regen.with_name(regen.name + ".import").unlink(missing_ok=True)
    run_godot_import(godot_bin)
    fix_import_settings(src)
    assert_lossless_art_import(src)
    return f"{key}: installed + import repaired"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--category", choices=sorted(CATEGORIES), help="regenerate a whole batch")
    ap.add_argument("--only", help="regenerate a single sprite key (e.g. mil2/technical)")
    ap.add_argument("--dry-run", action="store_true", help="print what would run, call no API")
    ap.add_argument("--install", action="store_true",
                    help="promote existing .regen.png files over the shipped sprites")
    ap.add_argument("--godot", default="godot", help="godot binary (for --install)")
    ap.add_argument("--jobs", type=int, default=4, help="parallel generations")
    args = ap.parse_args()

    if not args.category and not args.only:
        ap.error("pass --category or --only")

    if args.only:
        cat = next((c for c, m in CATEGORIES.items() if args.only in m), None)
        if cat is None:
            ap.error(f"unknown sprite key {args.only!r}")
        batch, category = {args.only: CATEGORIES[cat][args.only]}, cat
    else:
        batch, category = CATEGORIES[args.category], args.category

    if args.install:
        godot = resolve_godot(args.godot)
        for key in batch:
            print(" ", install(key, godot))
        return 0

    print(f"regenerating {len(batch)} {category} sprite(s)"
          f"{' [dry-run]' if args.dry_run else ''}\n")
    failures = []
    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        futs = [pool.submit(generate_one, k, spec, category, args.dry_run)
                for k, spec in sorted(batch.items())]
        for f in futs:
            key, ok, msg = f.result()
            print(f"  {'ok  ' if ok else 'FAIL'} {key}: {msg}")
            if not ok:
                failures.append(key)

    print(f"\n{len(batch) - len(failures)}/{len(batch)} generated.")
    if not args.dry_run and not failures:
        print("Review the .regen.png files, then re-run with --install to promote them.")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
