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
import re
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
    # Props drift photoreal without the explicit style clamp (pilot: the barrel came back
    # as a rusted photo, and drifted blue out of the desert palette). They are also the
    # SMALLEST things on screen -- most decor lands at 16-40px -- so the outer silhouette
    # carries the entire read and interior detail is wasted pixels.
    "prop": ("Top-down orthographic sprite of {subject}, seen from directly overhead at a strict "
             "90-degree bird's-eye angle, matching the ORIENTATION of the reference image.\n"
             "CRITICAL — this prop is displayed at only about {onscreen} PIXELS on screen:\n"
             "- {hero}\n"
             "- The OUTER SILHOUETTE carries the whole read. Make the outline shape instantly "
             "recognisable in one glance; interior detail is wasted at this size.\n"
             "- Use STRONG VALUE CONTRAST: near-black shadow against bright sunlit top faces, so "
             "the shape separates from the tan desert ground it sits on.\n"
             "- Chunky bold forms, NO thin lines, NO fine texture, NO small text or markings.\n"
             + STYLE),
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

# Decor props. NOTE: decor/dry_shrub + decor/tumbleweed are already OUR OWN nano-banana
# desert art -- they are deliberately absent here. decor/flag_iran is also absent: it is
# the one non-square canvas (306x600, which fit_square cannot handle) and it is the
# reputational call the checklist parks for a human.
DECOR = {
    "decor/landmine":        ("a round anti-tank landmine half-buried in sand, its pressure plate exposed",
                              "a bold dark ring around a raised central pressure plate, like a target", 160),
    "decor/bridge_mid":      ("a straight section of a military pontoon bridge deck spanning water",
                              "hard parallel plank lines running across the deck, with dark edge rails", 97),
    "decor/bridge_ramp":     ("the sloped approach ramp section of a military pontoon bridge",
                              "a clear wedge taper from wide to narrow so it reads as a ramp, not a flat deck", 97),
    "decor/skyline_mast":    ("a tall industrial radio mast seen from above, foreshortened to its footprint",
                              "a bold X of guy-wires anchoring a chunky central mast block", 80),
    # "overlapping craters" produced a regular honeycomb/flower lattice -- say scattered
    # and irregular, and explicitly forbid the pattern reading.
    "decor/crater_field":    ("a patch of desert ground scarred by three or four SCATTERED bomb craters of "
                              "DIFFERENT sizes at irregular random positions",
                              "each crater a dark shadowed pit with a bright sand rim. The craters must be "
                              "IRREGULAR and RANDOMLY placed -- absolutely NOT a honeycomb, NOT a repeating "
                              "grid, NOT a flower or cellular pattern, NOT evenly spaced", 72),
    "decor/crater_water":    ("a large explosion crater that has filled with murky water",
                              "a dark still water pool filling the pit, ringed by a bright blasted sand rim", 72),
    "decor/wreck_halftrack": ("a burnt-out armoured halftrack, destroyed and blackened",
                              "a charred hollow hull with the track units still visible as dark bars", 72),
    "decor/skyline_chimney": ("a squat industrial smokestack seen from directly above",
                              "a bold dark circular flue mouth inside a thick ring of brickwork", 64),
    # "long dark slot" came back as a decorative squiggle -- demand a straight channel.
    "decor/trench":          ("a STRAIGHT infantry trench channel dug into desert ground, running edge to edge",
                              "a wide near-black rectangular trough of shadow running straight across the "
                              "sprite, flanked by bright heaped spoil banks on both long sides. It must read "
                              "as a dug channel in the ground -- NOT a winding ribbon, NOT a squiggle, NOT a "
                              "rope or snake shape", 52),
    "decor/tent":            ("an olive military field tent",
                              "a strong ridge line down the middle splitting two bright sloped roof panels", 49),
    "decor/crater":          ("a single explosion crater blasted into desert ground",
                              "a dark elliptical pit with a bright raised rim of thrown sand", 48),
    "decor/watchtower":      ("a wooden guard watchtower seen from above",
                              "a square railed platform sitting on a bold X of support legs", 42),
    "decor/radio_tower":     ("a lattice radio antenna tower seen from above",
                              "a bold triangular lattice footprint with a bright antenna hub at the centre", 40),
    "decor/wreck":           ("a generic burnt-out vehicle wreck, blackened and hollowed",
                              "a charred hollow shell shape, clearly gutted rather than intact", 37),
    "decor/rock2":           ("a large desert boulder",
                              "a chunky angular rock mass, bright sunlit top faces against deep shadow sides", 36),
    "decor/fallen_merc":     ("the body of a fallen soldier lying face-down on the ground",
                              "a clear sprawled human silhouette with arms and legs splayed outward", 36),
    "decor/barbedwire":      ("a coil of barbed razor wire strung between short stakes",
                              "a bold zig-zag coil of wire loops between two dark stake posts", 35),
    "decor/flak_gun":        ("an emplaced anti-aircraft flak gun on a wheeled carriage",
                              "twin long barrels angled outward from a chunky round base", 35),
    "decor/flag_marker":     ("a small marker flag on a pole planted in the ground",
                              "a bright triangular pennant reading clearly off a thin dark pole", 32),
    "decor/barricade":       ("a wooden and sandbag barricade wall segment",
                              "a solid horizontal bar of stacked sandbags with a bright top edge", 30),
    "decor/barrier":         ("a concrete road barrier block",
                              "a heavy trapezoid concrete slab with bright top face and dark base shadow", 29),
    "decor/crate_stack":     ("a stack of military supply crates",
                              "two or three overlapping bright square crate lids with dark seams between them", 29),
    "decor/rock1":           ("a small desert boulder",
                              "a compact angular rock lump with a bright sunlit crown and dark shadow side", 29),
    "decor/tank_trap":       ("a steel anti-tank hedgehog obstacle",
                              "three thick steel beams crossing in a bold six-pointed star", 28),
    "decor/mg_tripod":       ("a machine gun mounted on a tripod",
                              "a dark barrel line over a bold three-legged tripod splay", 19),
    "decor/barrel":          ("a weathered steel oil barrel standing upright",
                              "a bold ringed circular lid, dark rim against a bright top", 18),
    "decor/dropped_shield":  ("a riot shield dropped flat on the ground",
                              "a bright rounded rectangle plate with a dark grip bar across it", 17),
    "decor/ammobox":         ("a metal ammunition box",
                              "a bright rectangular lid with a bold dark carry handle across it", 16),
}


# Characters. NOTE the real on-screen budget is TINY: these sources are 1024px but their
# .import caps them at 128px, and the draw then applies SCALE (0.5) * the call-site
# spr_scale (~0.5), so a soldier lands around 32-35px. At that size a face is 2 pixels --
# the read is entirely silhouette + the shoulder/weapon shape.
# ⚠️ THE CHARACTER TEMPLATE IS NOT SHIP-READY. The 2026-07-24 pilot regenerated the three
# below, installed them, and rendered them through the real _spr at their real ~32px budget:
# the results graded C+/B- and were a REGRESSION on what they replace. The existing legacy art
# bakes are TRUE 90-degree overhead (you see the helmet crown from directly above; the
# ghillie is a shaggy prone strip). Every generated attempt -- across three prompt revisions
# -- came back a 3/4 STANDING figure, because the model strongly resists a true overhead
# human. The art was reverted; only the pipeline fixes were kept.
# Before running this category for real, solve the angle problem first (candidate approaches:
# feed a true-overhead reference that is not a tiny dark blob, or render posed 3D and bake).
CHARACTERS = {
    "mil2/soldier2":  ("an enemy grenadier soldier standing, lobbing arm cocked, seen from straight above",
                       "the dark helmet crown centred in a broad shoulder mass, with one arm swung out "
                       "wide holding a grenade so the pose reads as THROWING", 33),
    "p2/ghillie":     ("an enemy sniper in a shaggy ghillie suit lying prone, seen from straight above",
                       "a ragged shaggy-edged blob with a long dark rifle barrel projecting from one end -- "
                       "the frayed outline plus the protruding barrel are the whole read", 32),
    "p2/sapper":      ("an enemy combat engineer carrying a satchel charge, seen from straight above",
                       "the helmet crown and shoulders with a bulky square satchel pack clearly overhanging "
                       "one side of the silhouette", 32),
}

CATEGORIES = {"vehicle": VEHICLES, "prop": DECOR, "character": CHARACTERS}


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
    # ORDER MATTERS: gate on the RAW keyed image first. despill() nudges pixels away from
    # pure magenta, so running it before this check let a bad key slip through -- that is
    # exactly how bridge_ramp (9.3% magenta) and tent (8.7%) shipped fringe on 2026-07-24.
    try:
        check_key_quality(im, key_color, out)
    except ValueError as exc:
        out.unlink(missing_ok=True)
        return key, False, str(exc)[-160:]
    im = despill(im)
    # Hard backstop: after despill NOTHING may still read as magenta or cyan tinted. despill
    # only lowers R/B toward G, so a cyan result means the source art really is teal.
    px = im.load()
    mag = op = 0
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if a < 16:
                continue
            op += 1
            if r > g + 30 and b > g + 30:
                mag += 1
    if op and mag / op > 0.01:
        out.unlink(missing_ok=True)
        return key, False, f"{mag / op:.1%} of opaque pixels still read magenta after despill"
    im.save(out)
    opaque = sum(1 for v in im.getchannel("A").tobytes() if v > 15) / (size * size)
    return key, True, f"{size}x{size} ({opaque:.0%} opaque) -> {out.relative_to(PROJECT_ROOT)}"


def despill(im: Image.Image) -> Image.Image:
    """Suppress magenta spill on the surviving opaque pixels.

    chroma_key() only zeroes pixels CLOSE to the key colour; a thin bright edge
    (a flag pennant, a gun barrel) antialiases into the matte and lands as a pinkish
    pixel that is too far from pure magenta to be keyed but close enough to trip
    check_key_quality -- which is exactly how flag_marker/flak_gun failed twice.
    Standard fix: magenta is high R+B / low G, so clamp R and B toward G on any pixel
    where both exceed it. Neutral on art that has no spill.
    """
    im = im.copy()
    px = im.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            if r > g and b > g:
                lim = int(g + 0.25 * (max(r, b) - g))
                px[x, y] = (min(r, lim), g, min(b, lim), a)
    return im


def install(key: str, godot_bin: str) -> str:
    """Promote <name>.regen.png over the shipped sprite, then repair its import
    sidecar to the project's lossless convention and assert it stuck."""
    src = PROJECT_ROOT / "assets/art" / f"{key}.png"
    regen = src.with_suffix(".regen.png")
    if not regen.exists():
        return f"{key}: no .regen.png to install"
    # fix_import_settings() rewrites the sidecar from ONE reference file, which carries
    # process/size_limit=0. Sprites whose own sidecar caps them (the 1024px characters use
    # size_limit=128) would silently import at full resolution and draw ~20x too large --
    # exactly what the 2026-07-24 character pilot rendered. Capture the ORIGINAL cap here
    # and restore it after the rewrite.
    imp = src.with_name(src.name + ".import")
    prior = imp.read_text() if imp.exists() else ""
    m = re.search(r"^process/size_limit=(\d+)$", prior, re.M)
    orig_limit = m.group(1) if m else None
    regen.replace(src)
    # Godot will have already imported the .regen.png while it sat in the tree, leaving a
    # <name>.regen.png.import sidecar behind once the PNG itself moves. That orphan keeps
    # DEFAULT settings (compress/mode=2 + detect_3d), which is exactly what
    # test_a1_art_bakes_are_lossless forbids -- it failed the suite until this cleanup.
    regen.with_name(regen.name + ".import").unlink(missing_ok=True)
    run_godot_import(godot_bin)
    fix_import_settings(src)
    if orig_limit and orig_limit != "0":
        txt = imp.read_text()
        txt = re.sub(r"^process/size_limit=\d+$", f"process/size_limit={orig_limit}", txt, count=1, flags=re.M)
        imp.write_text(txt)
    assert_lossless_art_import(src)
    # Hard guard: the cap must survive the rewrite, or the sprite silently draws oversized.
    now = re.search(r"^process/size_limit=(\d+)$", imp.read_text(), re.M)
    if orig_limit and (now is None or now.group(1) != orig_limit):
        raise ValueError(f"{src}: size_limit {orig_limit} was lost by the import rewrite")
    cap = f" (size_limit {orig_limit} preserved)" if orig_limit and orig_limit != "0" else ""
    return f"{key}: installed + import repaired{cap}"


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
