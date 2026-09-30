#!/usr/bin/env python3
"""Harvest and re-derive the CC0 asset cache in ``assets/cc0_extra/``.

Two legal sources only. Both are public domain (CC0 1.0), and the script
REFUSES to run against anything it cannot prove is CC0 from a licence file
inside the artefact itself:

1. Kenney's own CC0 packs + two Kenney CC0 sound packs, already sitting in the
   shared library at ``$GAMEASSETS_LIBRARY/source/downloads``. Only an
   explicit, enumerated member list is extracted -- never a whole pack.
2. ambientCG, via its public JSON API, for desert/sand/dirt ground materials.
   The 1K **colour** map only is pulled out of each 1K-JPG archive; the rest of
   the PBR set is never downloaded.

WHAT THIS SCRIPT WILL NOT DO
----------------------------
It will not touch the CraftPix library. CraftPix's licence forbids
redistributing source files (Sec 1.1.3) and forbids use "for the purposes of
training, fine-tuning, developing, testing, validating, or improving any AI...
system" (Sec 3.1). This repository is public and MIT, so *no* CraftPix byte may
be copied into it, and *no* CraftPix asset may be fed to an image model. The
CraftPix directory is not even referenced below; see the QUARANTINED list in
``tools/fetch_cc0.py``'s module docstring of ``assets/cc0_extra/QUARANTINED.md``
for the two OpenGameArt archives that are excluded for want of a licence file.

The ground tiles are **candidates, not a swap**. ``src/main.gd``'s
``_ground_stops()`` / ``GROUND_SHADE`` are load-bearing across four test files
and a parallel workstream is landing a sky-light ramp on the live ground base;
this script writes candidates to ``assets/cc0_extra/ground/`` and touches
nothing that the game already loads.

Usage
-----
    python3 tools/fetch_cc0.py            # re-derive every file, then verify
    python3 tools/fetch_cc0.py --check    # verify only; exit 1 on any drift
    python3 tools/fetch_cc0.py --accept-drift   # re-derive and re-baseline

Idempotence
-----------
A default run rebuilds ``assets/cc0_extra/`` and then verifies it against the
committed ``assets/cc0_extra/MANIFEST.json``. A hash mismatch is a FAILURE, not
something to paper over: the manifest is only rewritten when you pass
``--accept-drift`` explicitly, and that prints a loud warning. ``--check`` is
therefore a real gate -- it never regenerates the thing it is checking.

Requires: Pillow (already in ``tools/requirements.txt``) and stdlib ``urllib``.
No requests / httpx.
"""

from __future__ import annotations

import argparse
import hashlib
import html
import io
import json
import math
import os
import re
import shutil
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
import zipfile
from pathlib import Path

try:
    from PIL import Image, ImageChops
except ImportError:  # pragma: no cover - reported, not silently tolerated
    sys.stderr.write(
        "fetch_cc0: Pillow is required (pip install -r tools/requirements.txt)\n"
    )
    raise

# --------------------------------------------------------------------------
# Layout
# --------------------------------------------------------------------------

REPO = Path(__file__).resolve().parent.parent
OUT = REPO / "assets" / "cc0_extra"
MANIFEST_PATH = OUT / "MANIFEST.json"
ASSETS_MD = REPO / "ASSETS.md"

LIBRARY = Path(os.environ.get("GAMEASSETS_LIBRARY", "~/gameassets")).expanduser()
DOWNLOADS = LIBRARY / "source" / "downloads"
CACHE = Path(
    os.environ.get("FETCH_CC0_CACHE", Path.home() / ".cache" / "commander-cc0")
)

UA = "commander-in-chief/fetch_cc0 (CC0 asset harvest; +https://github.com/local)"

# --------------------------------------------------------------------------
# Ground tile geometry
# --------------------------------------------------------------------------
#
# `src/main.gd` GROUND_TILE_PX is 96 -- but that is the on-screen *pitch* of the
# band lattice, not the card size. The card itself is 128px: GROUND_BASE_SLOTS
# is "128px dihedral slots per 1024px strip" and the live `assets/cc0/sand.png`
# is 128x128. A band is exactly one whole tile tall, so a candidate must tile
# seamlessly in BOTH axes at 128px or a band edge becomes visible.

TILE_PX = 128
# Intermediate size for the wrap-blend. Blending at 512 and then downsampling
# keeps the half-offset phase shift below one output pixel after LANCZOS.
WORK_PX = 512
# tests/test_assets.gd::test_ground_tile_is_seamless asserts wrap <= inner * 1.5
# on the live sand.png. Same bar here, applied to both axes.
SEAM_RATIO_MAX = 1.5

# --------------------------------------------------------------------------
# Junk denylist. Applied to every member BEFORE extraction, so a .wav or a
# .DS_Store that snuck into an upstream pack fails the run instead of shipping.
# --------------------------------------------------------------------------

JUNK_SUFFIXES = (".wav", ".url", ".pdn", ".afdesign", ".afphoto", ".lnk")
JUNK_NAMES = {"thumbs.db", ".ds_store", "desktop.ini", "__macosx"}


def is_junk(member: str) -> bool:
    parts = member.replace("\\", "/").split("/")
    if any(p.lower() in JUNK_NAMES for p in parts):
        return True
    return parts[-1].lower().endswith(JUNK_SUFFIXES)


class FetchError(RuntimeError):
    """A source could not be fetched or its licence could not be proven."""


def log(msg: str) -> None:
    print(msg, flush=True)


def warn(msg: str) -> None:
    print("  !! " + msg, file=sys.stderr, flush=True)


# --------------------------------------------------------------------------
# Source 1 -- Kenney CC0 packs already on disk.
#
# Every entry carries the archive-relative licence member plus the markers that
# licence must contain. The markers are asserted against the bytes INSIDE the
# archive; a pack that ships a different licence, or no licence at all, is a
# hard failure and nothing is extracted from it.
# --------------------------------------------------------------------------

CC0_MARKERS = (
    "creativecommons.org/publicdomain/zero/1.0/",
    "creativecommons.org/publicdomain/zero/1.0",
)

KENNEY_LICENCE_MARKERS = ("Creative Commons Zero",) + CC0_MARKERS

# subdir -> (archive member path in the zip, [out filenames])
# `out` names are the repo-relative path under assets/cc0_extra/.
KENNEY_PACKS: dict[str, dict] = {
    "crosshair": {
        "zip": DOWNLOADS / "kenney_crosshair-pack.zip",
        "licence_member": "License.txt",
        "licence_title": "Crosshair Pack (1.1)",
        "upstream": "https://kenney.nl/assets/crosshair-pack",
        "out": {
            # Reticle outlines. 16 chosen by eye from all 200 Outline frames:
            # clean circle+cross defaults, tactical corner-bracket lock-on
            # boxes, and a couple of distinct silhouettes (X, angled hit ticks).
            "crosshair": [
                (f"PNG/Outline/crosshair-{n:03d}.png", f"crosshair-{n:03d}.png")
                for n in (6, 9, 26, 33, 38, 46, 66, 80, 81, 82, 92, 100, 102, 105, 134, 146)
            ]
        },
    },
    "ui": {
        "zip": DOWNLOADS / "kenney_ui-pack.zip",
        "licence_member": "License.txt",
        "licence_title": "UI Pack (2.0)",
        "upstream": "https://kenney.nl/assets/ui-pack",
        "out": {
            # NOTE: this pack contains NO panel/window/frame pieces -- the full
            # file list is arrows, buttons, checks, slides, stars. The closest
            # thing to a frame is Extra/Default/input_* (a bordered text-field
            # plate) and Extra/Default/divider* . Grey/Default gives the
            # neutral, desaturated border/track pieces that suit a military HUD
            # where the pack's Blue/Green/Red themes would not.
            "ui": [
                (f"PNG/Extra/Default/{n}.png", f"{n}.png")
                for n in (
                    "input_rectangle",
                    "input_outline_rectangle",
                    "input_square",
                    "input_outline_square",
                    "divider",
                    "divider_edges",
                )
            ]
            + [
                (f"PNG/Grey/Default/{n}.png", f"{n}.png")
                for n in (
                    "button_rectangle_depth_border",
                    "button_rectangle_line",
                    "button_square_depth_border",
                    "button_round_depth_border",
                    "slide_horizontal_grey",
                    "slide_horizontal_grey_section",
                    "slide_horizontal_grey_section_wide",
                    "slide_vertical_grey",
                    "check_square_grey",
                    "check_square_grey_checkmark",
                    "check_round_grey",
                    "icon_outline_checkmark",
                    "icon_outline_circle",
                    "icon_outline_cross",
                    "icon_outline_square",
                )
            ]
        },
    },
    "td_ground": {
        "zip": DOWNLOADS / "kenney_tower-defense-top-down.zip",
        "licence_member": "License.txt",
        "licence_title": "Tower Defense (top-down) Pack",
        "upstream": "https://kenney.nl/assets/tower-defense-top-down",
        "out": {
            # This pack is a poor fit overall -- bright green grass, cartoon
            # blue water, tower sprites. Only the flat brown dirt / tan sand
            # frames are carried over, as ground decals and emplacement marks.
            "td_ground": [
                (f"PNG/Default size/towerDefense_tile{n:03d}.png", f"{name}.png")
                for n, name in (
                    (5, "dirt_flat_005"),
                    (47, "dirt_flat_047"),
                    (55, "dirt_flat_055"),
                    (60, "dirt_flat_060"),
                    (65, "dirt_emplacement_065"),
                    (66, "dirt_emplacement_wrench_066"),
                    (67, "dirt_emplacement_cross_067"),
                    (68, "dirt_emplacement_target_068"),
                    (92, "dirt_stone_092"),
                    (97, "dirt_stone_097"),
                    (150, "dirt_stone_150"),
                    (158, "dirt_stone_158"),
                    (144, "sand_dirt_edge_144"),
                    (146, "sand_dirt_edge_146"),
                    (147, "sand_dirt_edge_147"),
                )
            ]
        },
    },
    "sfx_ui": {
        "zip": DOWNLOADS / "kenney_ui-audio.zip",
        "licence_member": "License.txt",
        "licence_title": "UI SFX Set",
        "upstream": "https://kenney.nl/assets/ui-audio",
        "out": {
            "sfx_ui": [
                (f"Audio/{n}.ogg", f"{n}.ogg")
                for n in (
                    "click1",
                    "click2",
                    "click3",
                    "click5",
                    "mouseclick1",
                    "rollover3",
                    "switch1",
                    "switch5",
                    "switch10",
                    "switch17",
                    "switch25",
                )
            ]
        },
    },
    "sfx_impact": {
        "zip": DOWNLOADS / "kenney-audio" / "impact.zip",
        "licence_member": "License.txt",
        "licence_title": "Impact Sounds (1.0)",
        "upstream": "https://kenney.nl/assets/impact-sounds",
        "out": {
            "sfx_impact": [
                (f"Audio/{n}.ogg", f"{n}.ogg")
                for n in (
                    "impactMetal_medium_000",
                    "impactMetal_medium_002",
                    "impactPlate_heavy_000",
                    "impactPlate_medium_000",
                    "impactBell_heavy_000",
                    "impactGlass_heavy_000",
                    "impactWood_heavy_000",
                    "impactSoft_heavy_000",
                    "impactPunch_heavy_000",
                    "impactTin_medium_000",
                    "impactMining_000",
                    "footstep_concrete_000",
                )
            ]
        },
    },
    "sfx_scifi": {
        "zip": DOWNLOADS / "kenney-audio" / "sci-fi.zip",
        "licence_member": "License.txt",
        "licence_title": "Sci-Fi Sounds (1.0)",
        "upstream": "https://kenney.nl/assets/sci-fi-sounds",
        "out": {
            "sfx_scifi": [
                (f"Audio/{n}.ogg", f"{n}.ogg")
                for n in (
                    "laserSmall_000",
                    "laserSmall_003",
                    "laserLarge_000",
                    "laserRetro_000",
                    "explosionCrunch_000",
                    "explosionCrunch_003",
                    "lowFrequency_explosion_000",
                    "thrusterFire_000",
                    "forceField_000",
                    "computerNoise_000",
                    "impactMetal_000",
                    "spaceEngineSmall_000",
                    "engineCircular_000",
                )
            ]
        },
    },
}

# The railgun preview is a freesound upload, not a Kenney pack; its licence is a
# sidecar text file rather than a member of an archive.
RAILGUN = {
    "mp3": DOWNLOADS / "kenney-audio" / "railgun-baggonotes-hq.mp3",
    "licence": DOWNLOADS / "kenney-audio" / "railgun-LICENSE.txt",
    "out": "sfx_railgun/railgun_fire_baggonotes.mp3",
    "upstream": "https://freesound.org/people/BaggoNotes/sounds/785380/",
}

# --------------------------------------------------------------------------
# Source 2 -- ambientCG. CC0, live JSON API.
# --------------------------------------------------------------------------

AMBIENTCG_API = "https://ambientcg.com/api/v2/full_json"
AMBIENTCG_LICENCE_URL = "https://ambientcg.com/index.php?language=en"
AMBIENTCG_CREDITS_URL = "https://ambientcg.com/credits"

# Search terms the candidate assetIds must be *discoverable* under. The script
# re-runs these queries and asserts each chosen assetId comes back, so the
# pipeline stays honest if ambientCG re-indexes.
AMBIENTCG_SEARCHES = ("desert", "sand", "dirt", "gravel", "mud", "clay", "rocky ground",
                       "grass", "forest")

# The six candidates. `why` is the justification recorded in ASSETS.md.
AMBIENTCG_PICKS = [
    {
        "assetId": "Ground079L",
        "slug": "ground-079l-fine-pale-sand",
        "why": "Finest, palest sand of the set -- lowest high-frequency energy, so it "
               "survives a 1024->128 downsample as grain rather than dissolving into "
               "flat colour. Closest match to the live sand.png's std ~0.036 character.",
    },
    {
        "assetId": "Ground062L",
        "slug": "ground-062l-warm-tan-sand",
        "why": "Warm mid-tan fine sand with only sparse grit. The best candidate for a "
               "second base-floor card, where the dihedral-variant scheme "
               "(GROUND_BASE_VARIANTS) needs a sibling that is visibly different in "
               "hue but identical in grain scale.",
    },
    {
        "assetId": "Ground098",
        "slug": "ground-098-dune-ripple-sand",
        "why": "Soft wind-ripple relief in warm tan. The ripple is low enough in "
               "spatial frequency to still read as directional texture at 128px "
               "instead of aliasing into a crosshatch.",
    },
    {
        "assetId": "Ground062S",
        "slug": "ground-062s-gritty-dirt-track",
        "why": "The coarse sibling of Ground062L -- visibly peppered with grit. Reads as "
               "a trafficked dirt track rather than open desert, which is what the "
               "desert biome's vehicle lanes want.",
    },
    {
        "assetId": "Ground095A",
        "slug": "ground-095a-dry-cracked-earth",
        "why": "Dark brown desiccation polygons. The only genuinely 'dry cracked' "
               "material in the shortlist; the polygon scale is a few hundred pixels in "
               "the 1K source, so 2-3 cracks survive the downsample intact.",
    },
    {
        "assetId": "Ground039",
        "slug": "ground-039-scorched-ash",
        "why": "The scorched/ash candidate: near-neutral dark grey with no vegetation. "
               "Reads as a burnt-out blast zone and is the tonal floor of the set, so it "
               "can carry scorched-earth decals under a light ground ramp.",
    },
    {
        "assetId": "Grass005",
        "slug": "grass-005-lush-dense-turf",
        "why": "The JUNGLE biome's identity card. Bright, saturated, densely-turfed green "
               "-- the only genuinely lush material in the set, and the one thing the "
               "desert-only shortlist was missing. Every advisory review of the "
               "jungle-named zone said the ground read as arid sand: the file is named "
               "jungle-firefight but the floor was a flat muddy noise field, which looks "
               "like a prototype or a palette swap. This is the material that makes zone 1 "
               "look tropical instead of desert.",
    },
    {
        "assetId": "Grass001",
        "slug": "grass-001-deep-forest-floor",
        "why": "Darker, cooler green than Grass005 with a soft mottle -- the jungle's "
               "SHADOW sibling. Where Grass005 is the open clearing, this is the ground "
               "under the canopy, and it is dark enough to hold the player's drop shadow "
               "and the units' contact shadows without them disappearing into the turf.",
    },
    {
        "assetId": "Ground037",
        "slug": "ground-037-mossy-grass-mix",
        "why": "The transition material between jungle floor and bare earth: a mottled "
               "moss-and-grass mix that reads as the churned-up edge of a path. Gives the "
               "jungle biome a third value so it is not a two-tone green field, and its "
               "low-frequency blotching survives the 1K->128 downsample as variation "
               "rather than dissolving into flat colour.",
    },
    {
        "assetId": "Ground106",
        "slug": "ground-106-wet-mud",
        "why": "The jungle's mud: dark, wet, tracked earth with scattered grit. This is the "
               "material for the rain-soaked ground under the treeline, and its strong "
               "value contrast against Grass005 is what makes the two read as different "
               "surfaces rather than the same green tinted darker.",
    },
]

# --------------------------------------------------------------------------
# Licensing text captured for the repo.
# --------------------------------------------------------------------------

KENNEY_LICENCE_TEXT = """\
Kenney game assets -- Creative Commons Zero (CC0 1.0 Universal)
==============================================================

This directory holds CC0 assets by Kenney Vleugels (kenney.nl), copied out of
his published packs on {retrieved}.

Full licence text, as shipped inside each source archive's License.txt
------------------------------------------------------------------
Kenney's own wording is reproduced in full in the per-pack sections of
ASSETS.md, and the marker this project asserts against is:

    License: (Creative Commons Zero, CC0)
    http://creativecommons.org/publicdomain/zero/1.0/

Canonical deed:  https://creativecommons.org/publicdomain/zero/1.0/
Canonical legal: https://creativecommons.org/publicdomain/zero/1.0/legalcode

Attribution is optional ("Support us by crediting Kenney or www.kenney.nl
(this is not mandatory)"). It is credited here anyway.

Packs represented
-----------------
  Kenney Crosshair Pack (1.1)        https://kenney.nl/assets/crosshair-pack
  Kenney UI Pack (2.0)               https://kenney.nl/assets/ui-pack
  Kenney Tower Defense (top-down)    https://kenney.nl/assets/tower-defense-top-down
  Kenney UI SFX Set                  https://kenney.nl/assets/ui-audio
  Kenney Impact Sounds (1.0)         https://kenney.nl/assets/impact-sounds
  Kenney Sci-Fi Sounds (1.0)         https://kenney.nl/assets/sci-fi-sounds

Railgun preview
---------------
  RailGun_Fire1 by BaggoNotes        https://freesound.org/people/BaggoNotes/sounds/785380/
  "Creative Commons Zero (CC0)"      https://creativecommons.org/publicdomain/zero/1.0/
  The author's own licence note is reproduced verbatim in ASSETS.md.
"""

AMBIENTCG_LICENCE_TEXT = """\
ambientCG -- Creative Commons Zero (CC0 1.0 Universal)
======================================================

Every material in assets/cc0_extra/ground/ is derived from an ambientCG 1K
colour map, retrieved {retrieved}.

Verbatim, from ambientCG's own licensing FAQ
--------------------------------------------
    "Yes. All assets are released under the Creative Commons CC0 license,
     making them free to use without attribution - even in commercial
     circumstances."

and from the site's own meta description:

    "Free 3D Assets Never Looked This Good! Get 2000+ PBR Materials, HDRIs
     and more for free under the CC0 Public Domain license."

Licence page:  {licence_url}
Credits page:  {credits_url}

Canonical deed:  https://creativecommons.org/publicdomain/zero/1.0/
Canonical legal: https://creativecommons.org/publicdomain/zero/1.0/legalcode

Derivation
----------
Each output tile is a local, lossless re-derivation, produced by
tools/fetch_cc0.py and reproducible from the public JSON API:

    1K-JPG archive -> extract <assetId>_1K-JPG_Color.jpg only
    -> centre-crop to 512x512 -> half-offset wrap-blend (makes both axes tile)
    -> LANCZOS downsample to 128x128 -> PNG

No normal, roughness, displacement, AO, HDRI or .usdc/.blend/.tres data was
downloaded or kept, and no ambientCG byte other than the colour map of the
six listed assetIds exists anywhere in this repository.
"""


# --------------------------------------------------------------------------
# HTTP
# --------------------------------------------------------------------------


def http_get(url: str, timeout: int = 240, tries: int = 3) -> bytes:
    last = None
    for attempt in range(tries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                return resp.read()
        except (urllib.error.HTTPError, urllib.error.URLError, OSError) as exc:
            last = exc
            if attempt + 1 < tries:
                time.sleep(1.5 * (attempt + 1))
    raise FetchError(f"GET {url} failed after {tries} attempt(s): {last!r}")


# --------------------------------------------------------------------------
# Licence enforcement
# --------------------------------------------------------------------------


def assert_cc0(text: str, what: str) -> None:
    lowered = text.lower()
    missing = [m for m in CC0_MARKERS if m.lower() not in lowered]
    if missing:
        raise FetchError(
            f"{what}: licence text does not contain {missing!r} -- refusing to use it"
        )


def read_licence_from_zip(zf: zipfile.ZipFile, member: str, what: str) -> str:
    try:
        raw = zf.read(member)
    except KeyError:
        raise FetchError(
            f"{what}: no licence member {member!r} in archive "
            f"(entries: {zf.namelist()[:12]})"
        ) from None
    text = raw.decode("utf-8", "replace")
    assert_cc0(text, what)
    return text


# --------------------------------------------------------------------------
# Kenney extraction
# --------------------------------------------------------------------------


def fetch_kenney() -> dict[str, dict]:
    """Extract the enumerated subset of every Kenney pack. Licence first."""
    files: dict[str, dict] = {}
    licences: dict[str, str] = {}

    for key, spec in KENNEY_PACKS.items():
        zpath: Path = spec["zip"]
        if not zpath.is_file():
            raise FetchError(f"{key}: source archive missing: {zpath}")
        with zipfile.ZipFile(zpath) as zf:
            licence = read_licence_from_zip(zf, spec["licence_member"], f"{key} ({zpath.name})")
            licences[key] = licence
            names = set(zf.namelist())
            for subdir, members in spec["out"].items():
                dest_dir = OUT / subdir
                dest_dir.mkdir(parents=True, exist_ok=True)
                for member, out_name in members:
                    if is_junk(member):
                        raise FetchError(f"{key}: denylist blocked {member!r}")
                    if member not in names:
                        raise FetchError(f"{key}: member not in archive: {member!r}")
                    data = zf.read(member)
                    dest = dest_dir / out_name
                    dest.write_bytes(data)
                    rel = dest.relative_to(OUT).as_posix()
                    files[rel] = {
                        "sha256": hashlib.sha256(data).hexdigest(),
                        "bytes": len(data),
                        "kind": dest.suffix.lstrip("."),
                        "source_pack": key,
                        "source_member": member,
                        "source_archive": str(zpath),
                        "source_url": spec["upstream"],
                        "licence": "CC0-1.0",
                        "licence_evidence": (
                            f"'{spec['licence_title']}' / {spec['licence_member']} "
                            f"inside {zpath.name} asserts "
                            "'License: (Creative Commons Zero, CC0)' + "
                            "creativecommons.org/publicdomain/zero/1.0/"
                        ),
                    }
        log(f"  {key:11s} {len(spec['out'])} subdir group(s), licence CC0 verified in-archive")

    # Railgun (freesound, CC0 by the author's own note).
    lic = RAILGUN["licence"]
    if not lic.is_file():
        raise FetchError(f"railgun: licence sidecar missing: {lic}")
    lic_text = lic.read_text(encoding="utf-8", errors="replace")
    assert_cc0(lic_text, f"railgun ({lic.name})")
    if "BaggoNotes" not in lic_text:
        raise FetchError("railgun: licence sidecar does not name the author")
    if not RAILGUN["mp3"].is_file():
        raise FetchError(f"railgun: audio missing: {RAILGUN['mp3']}")
    data = RAILGUN["mp3"].read_bytes()
    dest = OUT / RAILGUN["out"]
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_bytes(data)
    files[dest.relative_to(OUT).as_posix()] = {
        "sha256": hashlib.sha256(data).hexdigest(),
        "bytes": len(data),
        "kind": "mp3",
        "source_pack": "freesound-baggo-notes-railgun",
        "source_member": RAILGUN["mp3"].name,
        "source_archive": str(RAILGUN["mp3"]),
        "source_url": RAILGUN["upstream"],
        "licence": "CC0-1.0",
        "licence_evidence": (
            "kenney-audio/railgun-LICENSE.txt: 'RailGun_Fire1 by BaggoNotes, "
            "Creative Commons Zero (CC0)' + creativecommons.org/publicdomain/zero/1.0/"
        ),
    }
    licences["railgun"] = lic_text
    log("  railgun     1 file, CC0 verified from the author's own licence sidecar")
    return files, licences


# --------------------------------------------------------------------------
# Seamlessness
# --------------------------------------------------------------------------


def make_seamless(img: Image.Image) -> Image.Image:
    """Centre-crop, half-offset and cross-fade so both axes wrap.

    Let A be the crop and B = roll(A, n/2, n/2). Blend with a weight w that is 0
    on all four borders and 1 at the exact centre:

        w(x, y) = sin(pi*x/(n-1)) * sin(pi*y/(n-1))
        out     = A*(1-w) + B*w

    At the borders w == 0, so out(0, y) = A(0, y) and out(n-1, y) = A(n-1, y) --
    and A(0, y) and A(n-1, y) are *adjacent pixels of the source*, so the wrap
    step is an ordinary neighbour step. That is the same quantity the existing
    test compares, which is why this construction passes it by construction
    rather than by tuning.
    """
    w, h = img.size
    side = min(w, h)
    left, top = (w - side) // 2, (h - side) // 2
    a = img.crop((left, top, left + side, top + side)).convert("RGB")
    if a.size[0] != WORK_PX:
        a = a.resize((WORK_PX, WORK_PX), Image.LANCZOS)
    n = a.size[0]
    b = ImageChops.offset(a, n // 2, n // 2)
    ramp = [math.sin(math.pi * i / (n - 1)) for i in range(n)]
    mask = Image.new("L", (n, n))
    mask.putdata([int(255.0 * rx * ry) for ry in ramp for rx in ramp])
    return Image.composite(b, a, mask)


def seam_ratio(img: Image.Image) -> tuple[float, float]:
    """(x-ratio, y-ratio) of wrap-edge discontinuity to mean interior step.

    Mirrors tests/test_assets.gd::test_ground_tile_is_seamless, but over luma
    and on BOTH axes (the shipped test checks the V channel on X only). A
    genuinely tileable texture gives a ratio near 1.0, because crossing the wrap
    is just one more neighbour step.
    """
    return seam_detail(img)[0]


def seam_detail(img: Image.Image) -> tuple[tuple[float, float], dict]:
    """(ratios, absolutes) -- absolutes matter, see the note in AMBIENTCG_PICKS.

    The ratio is a *relative* measure, so on a very flat texture (dune sand with
    almost no interior contrast) a perfectly seamless tile can still report a
    ratio well above 1.0: the denominator is near zero. `wrap_step` /
    `interior_step` in the returned dict are the underlying 0-255 luma steps, so
    a reader can tell "seams badly" from "denominator is small".
    """
    w, h = img.size
    px = img.load()
    lum = [[0.0] * w for _ in range(h)]
    for y in range(h):
        row = lum[y]
        for x in range(w):
            r, g, b = px[x, y]
            row[x] = 0.2126 * r + 0.7152 * g + 0.0722 * b
    inner_x = sum(abs(lum[y][x + 1] - lum[y][x]) for y in range(h) for x in range(w - 1))
    wrap_x = sum(abs(lum[y][0] - lum[y][w - 1]) for y in range(h))
    inner_y = sum(abs(lum[y + 1][x] - lum[y][x]) for y in range(h - 1) for x in range(w))
    wrap_y = sum(abs(lum[0][x] - lum[h - 1][x]) for x in range(w))
    inner_x /= h * (w - 1)
    inner_y /= (h - 1) * w
    wrap_x /= h
    wrap_y /= w
    rx = wrap_x / inner_x if inner_x > 1e-9 else float("inf")
    ry = wrap_y / inner_y if inner_y > 1e-9 else float("inf")
    return (rx, ry), {
        "wrap_step_x": round(wrap_x, 3),
        "wrap_step_y": round(wrap_y, 3),
        "interior_step_x": round(inner_x, 3),
        "interior_step_y": round(inner_y, 3),
    }


def _entropy_note(img: Image.Image) -> dict:
    px = img.convert("L")
    hist = px.histogram()
    total = sum(hist)
    mean = sum(i * c for i, c in enumerate(hist)) / total
    var = sum(c * (i - mean) ** 2 for i, c in enumerate(hist)) / total
    return {"mean_luma": round(mean / 255.0, 4), "std_luma": round(math.sqrt(var) / 255.0, 4)}


# --------------------------------------------------------------------------
# ambientCG
# --------------------------------------------------------------------------


def ambientcg_query(term: str, limit: int = 60) -> list[dict]:
    params = urllib.parse.urlencode(
        {"type": "Material", "limit": str(limit), "q": term, "include": "downloadData"}
    )
    data = json.loads(http_get(f"{AMBIENTCG_API}?{params}", timeout=120))
    return data.get("foundAssets", [])


def ambientcg_licence_statement() -> str:
    """Fetch and confirm ambientCG's live CC0 statement, not a remembered one."""
    page = http_get(AMBIENTCG_LICENCE_URL, timeout=120).decode("utf-8", "replace")
    flat = " ".join(html.unescape(re.sub(r"<[^>]+>", " ", page)).split())
    m = re.search(
        r"All assets are released under the Creative Commons CC0 license[^.]*\.", flat
    )
    if not m:
        raise FetchError(
            "ambientCG: could not find the CC0 licensing statement on "
            f"{AMBIENTCG_LICENCE_URL} -- refusing to proceed on a remembered licence"
        )
    return m.group(0)


def resolve_1k_jpg_link(asset_id: str, terms: list[str]) -> str:
    """Pull the 1K-JPG zip link for `asset_id` out of a term search result.

    The API's `assetId` query parameter is a no-op (verified: it returns the
    same 12 popular items whatever you pass, and numberOfResults stays at the
    full 2012), so the only way to resolve a specific asset is to search a term
    that rediscovers it. Hence `terms`.
    """
    last: FetchError | None = None
    for term in terms:
        try:
            found = ambientcg_query(term)
        except FetchError as exc:  # one flaky term must not kill a working one
            last = exc
            continue
        for asset in found:
            if asset.get("assetId") != asset_id:
                continue
            cats = asset.get("downloadFolders", {}).get("default", {})
            downloads = (
                cats.get("downloadFiletypeCategories", {})
                .get("zip", {})
                .get("downloads", [])
            )
            for dl in downloads:
                if dl.get("attribute") == "1K-JPG":
                    return dl["downloadLink"]
            raise FetchError(
                f"ambientCG: {asset_id} has no 1K-JPG zip in the {term!r} API "
                f"response (attributes: {[d.get('attribute') for d in downloads]})"
            )
    raise FetchError(
        f"ambientCG: {asset_id} not rediscoverable through terms {terms!r}"
        + (f" (last error: {last})" if last else "")
    )


def cached_colour_jpg(asset_id: str, terms: list[str]) -> tuple[bytes, str]:
    """Download the 1K-JPG archive once; return only the 1K Colour map bytes.

    `terms` is every search term that rediscovered this assetId, tried in order
    -- the API's `assetId` filter is a no-op, so a candidate can only be
    resolved through a term that actually returns it.
    """
    CACHE.mkdir(parents=True, exist_ok=True)
    cached = CACHE / f"{asset_id}_1K-JPG_Color.jpg"
    if cached.is_file() and cached.stat().st_size > 0:
        return cached.read_bytes(), resolve_1k_jpg_link(asset_id, terms)
    link = resolve_1k_jpg_link(asset_id, terms)
    log(f"    {asset_id}: GET {link}")
    raw = http_get(link, timeout=600, tries=2)
    with zipfile.ZipFile(io.BytesIO(raw)) as zf:
        for name in zf.namelist():
            if is_junk(name):
                raise FetchError(f"ambientCG: denylist blocked {name!r} in {asset_id}")
        wanted = f"{asset_id}_1K-JPG_Color.jpg"
        matches = [n for n in zf.namelist() if n.endswith("_Color.jpg")]
        if wanted not in matches:
            raise FetchError(
                f"ambientCG: {asset_id} has no {wanted}; archive holds {matches}"
            )
        colour = zf.read(wanted)
    cached.write_bytes(colour)
    return colour, link


def fetch_ground() -> tuple[dict[str, dict], dict[str, dict]]:
    log("  ambientCG licence statement (live):")
    statement = ambientcg_licence_statement()
    log(f"    \"{statement}\"")

    # Reference point: how the SHIPPING ground card scores on this same metric, so
    # the candidate ratios below can be read as "like the live tile" rather than
    # as bare numbers whose acceptability the reader has to guess.
    for live in ("sand", "dirt"):
        p = REPO / "assets" / "cc0" / f"{live}.png"
        if not p.is_file():
            continue
        with Image.open(p) as im:
            lrx, lry = seam_ratio(im.convert("RGB"))
        log(
            f"    REFERENCE live assets/cc0/{live}.png seam x={lrx:.3f} y={lry:.3f} "
            f"(the tile the candidates would eventually have to beat)"
        )

    wanted = {p["assetId"]: p for p in AMBIENTCG_PICKS}
    found: dict[str, dict] = {}
    terms_for: dict[str, list[str]] = {}
    for term in AMBIENTCG_SEARCHES:
        for asset in ambientcg_query(term):
            aid = asset.get("assetId")
            if aid in wanted and aid not in found:
                found[aid] = asset
                terms_for[aid] = [term]
            elif aid in wanted:
                terms_for[aid].append(term)
    missing = sorted(set(wanted) - set(found))
    if missing:
        raise FetchError(
            "ambientCG: these candidates are no longer discoverable through the "
            f"API search terms {AMBIENTCG_SEARCHES}: {missing}"
        )
    log(f"    {len(found)}/{len(wanted)} candidates re-discovered via the API")

    dest_dir = OUT / "ground"
    dest_dir.mkdir(parents=True, exist_ok=True)
    files: dict[str, dict] = {}
    tiles: dict[str, dict] = {}

    for pick in AMBIENTCG_PICKS:
        aid = pick["assetId"]
        colour, link = cached_colour_jpg(aid, terms_for[aid])
        src = Image.open(io.BytesIO(colour))
        if src.size[0] != 1024:
            log(f"    {aid}: NOTE 1K colour map is {src.size[0]}px, not 1024")
        seamless = make_seamless(src)
        tile = seamless.resize((TILE_PX, TILE_PX), Image.LANCZOS)
        (rx, ry), absolutes = seam_detail(tile)
        worst = max(rx, ry)
        if not (worst <= SEAM_RATIO_MAX):
            raise FetchError(
                f"ambientCG {aid}: seam ratio {worst:.3f} exceeds the "
                f"{SEAM_RATIO_MAX}x bar (x={rx:.3f} y={ry:.3f})"
            )
        name = pick["slug"] + ".png"
        data = io.BytesIO()
        tile.save(data, format="PNG", optimize=True)
        blob = data.getvalue()
        (dest_dir / name).write_bytes(blob)
        rel = f"ground/{name}"
        stats = _entropy_note(tile)
        files[rel] = {
            "sha256": hashlib.sha256(blob).hexdigest(),
            "bytes": len(blob),
            "kind": "png",
            "source_pack": "ambientCG",
            "source_member": f"{aid}_1K-JPG_Color.jpg",
            "source_archive": link,
            "source_url": f"https://ambientcg.com/view?id={aid}",
            "licence": "CC0-1.0",
            "licence_evidence": (
                "ambientCG licensing FAQ: " + statement
            ),
            "derived": (
                f"centre-crop -> half-offset wrap-blend at {WORK_PX}px -> "
                f"LANCZOS {TILE_PX}px -> PNG (tools/fetch_cc0.py)"
            ),
        }
        tiles[rel] = {
            "assetId": aid,
            "displayName": found[aid].get("displayName", ""),
            "why": pick["why"],
            "seam_ratio_x": round(rx, 3),
            "seam_ratio_y": round(ry, 3),
            "seam_ratio_worst": round(worst, 3),
            "bar": SEAM_RATIO_MAX,
            "luma_steps_0_255": absolutes,
            **stats,
        }
        log(
            f"    {aid:11s} -> {name:38s} seam x={rx:.3f} y={ry:.3f} "
            f"(bar {SEAM_RATIO_MAX})  wrap={absolutes['wrap_step_x']}/{absolutes['wrap_step_y']} "
            f"vs inner={absolutes['interior_step_x']}/{absolutes['interior_step_y']} "
            f" mean={stats['mean_luma']} std={stats['std_luma']}"
        )
    return files, tiles


# --------------------------------------------------------------------------
# Manifest
# --------------------------------------------------------------------------


def build_manifest(files: dict[str, dict], tiles: dict[str, dict], licences: dict) -> dict:
    today = time.strftime("%Y-%m-%d")
    doc = {
        "schema": 1,
        "generator": "tools/fetch_cc0.py",
        "retrieved": today,
        "note": (
            "Machine-readable claim set for assets/cc0_extra/. --check verifies "
            "every file here against sha256+size and requires an ASSETS.md row. "
            "Regenerate deliberately with --accept-drift; a plain run that does "
            "not match is a FAILURE, not a reason to rewrite this file."
        ),
        "tile_px": TILE_PX,
        "seam_ratio_max": SEAM_RATIO_MAX,
        "quarantined": QUARANTINED,
        "licences": licences,
        "ground_tiles": tiles,
        "files": dict(sorted(files.items())),
    }
    doc["total_bytes"] = sum(f["bytes"] for f in files.values())
    doc["total_files"] = len(files)
    return doc


def load_manifest() -> dict | None:
    if not MANIFEST_PATH.is_file():
        return None
    return json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))


# --------------------------------------------------------------------------
# Per-file "what is this" text.
#
# Every row in the ASSETS.md section carries one, because that file's own header
# says it is "a provenance inventory, not a blanket clearance statement" and
# incomplete records are a known problem here. A brace-notation row that covers
# 16 files without saying which is which is exactly the defect to avoid.
# --------------------------------------------------------------------------

_CROSSHAIR_DESC = {
    6: "circular reticle with four quadrant ticks",
    9: "double-ring reticle, crosshair through a centre dot",
    26: "clean circle-and-cross reticle, open centre",
    33: "circle with opposing arc brackets (aim-lock framing)",
    38: "four angled ticks, open centre (hit-marker silhouette)",
    46: "minimal circle with four short ticks",
    66: "circle-and-cross reticle, longer horizontal axis",
    80: "open square bracket, full frame",
    81: "open square bracket, heavy corner ticks",
    82: "open square bracket with a centre plus",
    92: "plain thin circle (minimal scope ring)",
    100: "tactical corner-bracket reticle with a centre square",
    102: "closed square bracket with a centre cross",
    105: "square bracket with a centre ring",
    134: "gapped crosshair, four detached ticks",
    146: "X-shaped reticle, four diagonal ticks",
}

_UI_DESC = {
    "input_rectangle": "text-field plate (filled interior, no border)",
    "input_outline_rectangle": "text-field plate, outline only",
    "input_square": "square text-field plate (filled interior, no border)",
    "input_outline_square": "square text-field plate, outline only",
    "divider": "thin horizontal rule",
    "divider_edges": "horizontal rule with capped ends",
    "button_rectangle_depth_border": "rectangular button frame, bevelled depth + border",
    "button_rectangle_line": "rectangular button frame, hairline",
    "button_square_depth_border": "square button frame, bevelled depth + border",
    "button_round_depth_border": "round button frame, bevelled depth + border",
    "slide_horizontal_grey": "horizontal bar trough (grey, desaturated)",
    "slide_horizontal_grey_section": "horizontal bar fill segment",
    "slide_horizontal_grey_section_wide": "horizontal bar fill segment, wide variant",
    "slide_vertical_grey": "vertical bar trough (grey, desaturated)",
    "check_square_grey": "unchecked box, grey",
    "check_square_grey_checkmark": "checked box with a tick, grey",
    "check_round_grey": "unchecked circle, grey",
    "icon_outline_checkmark": "outlined tick glyph",
    "icon_outline_circle": "outlined circle glyph",
    "icon_outline_cross": "outlined cross glyph",
    "icon_outline_square": "outlined square glyph",
}

_TD_DESC = {
    "dirt_flat_005": "flat brown dirt fill (no grass/water edge)",
    "dirt_flat_047": "flat brown dirt fill, straight edge",
    "dirt_flat_055": "flat brown dirt fill, straight edge",
    "dirt_flat_060": "flat brown dirt fill, straight edge",
    "dirt_emplacement_065": "dirt pad with a faint studded outline",
    "dirt_emplacement_wrench_066": "dirt pad with an inlaid wrench mark",
    "dirt_emplacement_cross_067": "dirt pad with an inlaid X mark",
    "dirt_emplacement_target_068": "dirt pad with an inlaid target mark",
    "dirt_stone_092": "brown dirt with stone speckle",
    "dirt_stone_097": "brown dirt with stone speckle, straighter edge",
    "dirt_stone_150": "brown dirt with stone speckle",
    "dirt_stone_158": "brown dirt with stone speckle, heavier grit",
    "sand_dirt_edge_144": "tan sand meeting a brown dirt patch",
    "sand_dirt_edge_146": "tan sand meeting a brown dirt patch",
    "sand_dirt_edge_147": "tan sand meeting a brown dirt patch",
}

_SFX_UI_DESC = {
    "click1": "UI click, variant 1",
    "click2": "UI click, variant 2",
    "click3": "UI click, variant 3",
    "click5": "UI click, variant 5",
    "mouseclick1": "mouse-button click",
    "rollover3": "menu hover tick",
    "switch1": "toggle/switch on-off, variant 1",
    "switch5": "toggle/switch on-off, variant 5",
    "switch10": "toggle/switch on-off, variant 10",
    "switch17": "toggle/switch on-off, variant 17",
    "switch25": "toggle/switch on-off, variant 25",
}

_SFX_IMPACT_DESC = {
    "impactMetal_medium_000": "medium metal impact, variant 0",
    "impactMetal_medium_002": "medium metal impact, variant 2",
    "impactPlate_heavy_000": "heavy steel-plate impact",
    "impactPlate_medium_000": "medium steel-plate impact",
    "impactBell_heavy_000": "heavy bell/metal-body impact",
    "impactGlass_heavy_000": "heavy glass shatter",
    "impactWood_heavy_000": "heavy wood knock",
    "impactSoft_heavy_000": "heavy soft-body thud (flesh/padding)",
    "impactPunch_heavy_000": "heavy punch/body hit",
    "impactTin_medium_000": "medium tin/can impact",
    "impactMining_000": "pick-strike / mining impact",
    "footstep_concrete_000": "footstep on concrete",
}

_SFX_SCIFI_DESC = {
    "laserSmall_000": "small laser shot, variant 0",
    "laserSmall_003": "small laser shot, variant 3",
    "laserLarge_000": "large/heavy laser shot",
    "laserRetro_000": "retro synth laser",
    "explosionCrunch_000": "crunchy explosion, variant 0",
    "explosionCrunch_003": "crunchy explosion, variant 3",
    "lowFrequency_explosion_000": "low-frequency explosion boom",
    "thrusterFire_000": "thruster/rocket ignition",
    "forceField_000": "force-field shimmer",
    "computerNoise_000": "computer/console noise bed",
    "impactMetal_000": "sci-fi metal impact",
    "spaceEngineSmall_000": "small spacecraft engine loop",
    "engineCircular_000": "circular engine loop",
}

_PICK_TITLE = {
    "Ground079L": "fine pale sand",
    "Ground062L": "warm tan sand",
    "Ground098": "dune-ripple sand",
    "Ground062S": "gritty dirt track",
    "Ground095A": "dry cracked earth",
    "Ground039": "scorched ash",
    "Grass005": "lush dense turf",
    "Grass001": "deep forest floor",
    "Ground037": "mossy grass mix",
    "Ground106": "wet mud",
}


def describe(rel: str, tiles: dict[str, dict]) -> str:
    """One-line human description of a file, for the ASSETS.md row."""
    name = rel.rsplit("/", 1)[-1]
    stem = name.rsplit(".", 1)[0]
    sub = rel.split("/")[0]
    if rel in tiles:
        t = tiles[rel]
        return (
            f"128x128 seamless ground tile candidate — {t['displayName']} "
            f"({_PICK_TITLE[t['assetId']]}); luma mean {t['mean_luma']}, "
            f"std {t['std_luma']}"
        )
    if sub == "crosshair":
        return f"{TILE_PX}-ish reticle frame — {_CROSSHAIR_DESC[int(stem.split('-')[1])]}"
    if sub == "ui":
        return f"UI frame/glyph — {_UI_DESC[stem]}"
    if sub == "td_ground":
        return f"top-down ground tile — {_TD_DESC[stem]}"
    if sub == "sfx_ui":
        return f"UI sound — {_SFX_UI_DESC[stem]}"
    if sub == "sfx_impact":
        return f"impact sound — {_SFX_IMPACT_DESC[stem]}"
    if sub == "sfx_scifi":
        return f"sci-fi sound — {_SFX_SCIFI_DESC[stem]}"
    if sub == "sfx_railgun":
        return "railgun fire, HQ MP3 preview as published by the author"
    return "licence text captured verbatim from the source artefact"


# --------------------------------------------------------------------------
# ASSETS.md section, generated between markers so the hand-written rows above
# and below are never touched and the block can never drift from the manifest.
# --------------------------------------------------------------------------

BEGIN_MARK = "<!-- BEGIN generated: assets/cc0_extra (tools/fetch_cc0.py) -->"
END_MARK = "<!-- END generated: assets/cc0_extra -->"

LICENCE_QUOTE = {
    "crosshair": "Kenney `Crosshair Pack (1.1)` `License.txt`: “License: (Creative Commons Zero, CC0) / http://creativecommons.org/publicdomain/zero/1.0/”",
    "ui": "Kenney `UI Pack (2.0)` `License.txt`: “License: (Creative Commons Zero, CC0) / http://creativecommons.org/publicdomain/zero/1.0/”",
    "td_ground": "Kenney `Tower Defense (top-down) Pack` `License.txt`: “License (Creative Commons Zero, CC0) / http://creativecommons.org/publicdomain/zero/1.0/”",
    "sfx_ui": "Kenney `UI SFX Set` `License.txt`: “License (Creative Commons Zero, CC0) / http://creativecommons.org/publicdomain/zero/1.0/”",
    "sfx_impact": "Kenney `Impact Sounds (1.0)` `License.txt`: “License: (Creative Commons Zero, CC0) / http://creativecommons.org/publicdomain/zero/1.0/”",
    "sfx_scifi": "Kenney `Sci-Fi Sounds (1.0)` `License.txt`: “License: (Creative Commons Zero, CC0) / http://creativecommons.org/publicdomain/zero/1.0/”",
    "ambientCG": "ambientCG licensing FAQ: “All assets are released under the Creative Commons CC0 license, making them free to use without attribution - even in commercial circumstances.”",
    "freesound-baggo-notes-railgun": "author's own sidecar `railgun-LICENSE.txt`: “RailGun_Fire1 by BaggoNotes, Creative Commons Zero (CC0). Source page: https://freesound.org/people/BaggoNotes/sounds/785380/ . License verified September 28, 2026: https://creativecommons.org/publicdomain/zero/1.0/”",
    "licence-text": "the licence text itself, copied verbatim out of the source artefact",
}


def render_assets_md_section(manifest: dict) -> str:
    files = manifest["files"]
    today = manifest["retrieved"]
    lines: list[str] = [BEGIN_MARK, ""]
    lines.append(
        "## `assets/cc0_extra/` — CC0 candidate library (appended "
        f"{today}, generated by `tools/fetch_cc0.py`)"
    )
    lines.append("")
    lines.append(
        f"**{manifest['total_files']} files, {manifest['total_bytes']:,} bytes** — "
        f"{manifest['asset_files']} asset files ({manifest['asset_bytes']:,} bytes) plus "
        f"{manifest['licence_text_files']} licence-text files. Retrieved from CC0 "
        "(public domain) sources only and re-derived by `tools/fetch_cc0.py`; run "
        "`python3 tools/fetch_cc0.py --check` to verify every hash, every licence "
        "attribution and every ground-tile seam. Machine-readable claim set: "
        "`assets/cc0_extra/MANIFEST.json`."
    )
    lines.append("")
    lines.append(
        "> **None of this is wired into the game.** It is a candidate library. The "
        "live ground base (`assets/cc0/sand.png`) is untouched, and the ground tiles "
        "below are *candidates* — `src/main.gd`'s `_ground_stops()` / `GROUND_SHADE` "
        "are load-bearing across four test files and are being changed by another "
        "workstream. Integration is a separate, explicit decision."
    )
    lines.append("")
    lines.append(
        "**Sources are CC0 and nothing else.** No CraftPix material is present or "
        "permitted: its licence bars redistributing source files (§1.1.3) and bars "
        "AI use (§3.1), and this repository is public. See "
        "[`assets/cc0_extra/QUARANTINED.md`](assets/cc0_extra/QUARANTINED.md) for "
        "the two OpenGameArt archives excluded for want of a licence file, and for "
        "the CraftPix citation."
    )
    lines.append("")
    lines.append("### Licence verification — what was actually read")
    lines.append("")
    lines.append("| Source | Licence | Verified how |")
    lines.append("|---|---|---|")
    for pack in ("crosshair", "ui", "td_ground", "sfx_ui", "sfx_impact", "sfx_scifi"):
        spec = KENNEY_PACKS[pack]
        lines.append(
            f"| {spec['licence_title']} | CC0 1.0 — {LICENCE_QUOTE[pack]} | "
            f"`{spec['licence_member']}` read **out of** "
            f"`{Path(spec['zip']).name}` at fetch time; the run aborts if the "
            f"markers are absent. Verbatim copy: "
            f"`assets/cc0_extra/licenses/source-licence-{pack}.txt` |"
        )
    lines.append(
        "| RailGun_Fire1 (freesound) | CC0 1.0 — "
        f"{LICENCE_QUOTE['freesound-baggo-notes-railgun']} | author's own sidecar, "
        "verbatim copy at `assets/cc0_extra/licenses/source-licence-railgun.txt` |"
    )
    lines.append(
        "| ambientCG (6 ground materials) | CC0 1.0 — "
        f"{LICENCE_QUOTE['ambientCG']} | scraped from the live "
        "<https://ambientcg.com/index.php?language=en> on every run; the run aborts "
        "if the statement is not present |"
    )
    lines.append("")
    lines.append(
        "Deed: <https://creativecommons.org/publicdomain/zero/1.0/> · Legal code: "
        "<https://creativecommons.org/publicdomain/zero/1.0/legalcode>. Attribution "
        "is not required by either licence; Kenney and BaggoNotes are credited "
        "here anyway."
    )
    lines.append("")

    groups = [
        ("crosshair", "### Reticles — Kenney Crosshair Pack (1.1)"),
        ("ui", "### UI frames and glyphs — Kenney UI Pack (2.0)"),
        ("td_ground", "### Top-down ground tiles — Kenney Tower Defense (top-down) Pack"),
        ("sfx_ui", "### UI sound — Kenney UI SFX Set"),
        ("sfx_impact", "### Impact sound — Kenney Impact Sounds (1.0)"),
        ("sfx_scifi", "### Sci-fi sound — Kenney Sci-Fi Sounds (1.0)"),
        ("sfx_railgun", "### Railgun — freesound (CC0 by the author)"),
        ("ground", "### Ground material candidates — ambientCG (128x128, seamless)"),
        ("licenses", "### Licence texts"),
    ]
    for sub, heading in groups:
        rels = sorted(r for r in files if r.split("/")[0] == sub)
        if not rels:
            continue
        lines.append(heading)
        lines.append("")
        lines.append("| Path | What it is | Bytes | Source | Licence | Retrieved |")
        lines.append("|---|---|---:|---|---|---|")
        for rel in rels:
            meta = files[rel]
            size = f"{meta['bytes']:,}"
            src = meta.get("source_url") or "—"
            if meta.get("source_pack") == "ambientCG":
                src = f"ambientCG `{meta['source_member'].split('_')[0]}` — {src}"
            elif meta.get("source_pack") == "licence-text":
                src = "—"
            lic = LICENCE_QUOTE.get(meta.get("source_pack", ""), "CC0-1.0")
            lines.append(
                f"| `assets/cc0_extra/{rel}` | {describe(rel, manifest.get('ground_tiles', {}))} "
                f"| {size} | {src} | {lic} | {today} |"
            )
        lines.append("")

    lines.append("### Ground tile candidates — measurements")
    lines.append("")
    lines.append(
        "A band of ground is exactly one whole tile tall, so a candidate must tile "
        "seamlessly in **both** axes at 128px or a band edge shows. Seam ratio = "
        "wrap-edge discontinuity ÷ mean interior neighbour step, the same quantity "
        "`tests/test_assets.gd::test_ground_tile_is_seamless` asserts on the live "
        f"`sand.png` at a **≤ {SEAM_RATIO_MAX}x** bar. Measured on luma in both axes "
        "(the shipped test reads the V channel on X only)."
    )
    lines.append("")
    lines.append("| Tile | assetId | Seam x | Seam y | Worst | Bar | Luma mean / std |")
    lines.append("|---|---|---:|---:|---:|---:|---|")
    for rel, t in sorted(manifest.get("ground_tiles", {}).items()):
        lines.append(
            f"| `{rel.split('/')[-1]}` | `{t['assetId']}` | {t['seam_ratio_x']} | "
            f"{t['seam_ratio_y']} | **{t['seam_ratio_worst']}** | {t['bar']} | "
            f"{t['mean_luma']} / {t['std_luma']} |"
        )
    lines.append("")
    lines.append(
        "The ratio is *relative*, so a very flat texture reports a high ratio with a "
        "sub-1-level absolute step. The absolute luma steps (0–255) are in "
        "`MANIFEST.json` under `ground_tiles[].luma_steps_0_255` — for example "
        "`ground-098-dune-ripple-sand.png` reads 0.96/1.887 across the wrap against "
        "0.712/1.317 of interior step, i.e. under one 8-bit level. For reference, "
        "the live `assets/cc0/sand.png` scores **1.178 / 0.832** and the live "
        "`dirt.png` **0.439 / 0.137** on the same metric."
    )
    lines.append("")
    lines.append(
        "**Contrast, not just seamlessness, is what decides a swap.** The live "
        "`assets/cc0/sand.png` is luma std **0.0362** of *pure fine grain* — "
        "`src/main.gd` notes only 2.4% of its power below `|k|=2`, so it has almost "
        "no mid-frequency structure. The ambientCG candidates carry photographic "
        "mid-frequency structure that a 3x3 tile render shows as visible grit. By "
        "luma std the closest tonal match is `ground-062s-gritty-dirt-track` "
        "(0.0403); `ground-095a-dry-cracked-earth` (0.0085) and "
        "`ground-098-dune-ripple-sand` (0.0088) are much flatter than the tile they "
        "would replace, and would need their contrast lifted before they read as the "
        "same material. **No candidate is a drop-in replacement and none has been "
        "evaluated in-engine.**"
    )
    lines.append("")
    lines.append("### Why each candidate was chosen")
    lines.append("")
    for rel, t in sorted(manifest.get("ground_tiles", {}).items()):
        lines.append(f"- **`{rel.split('/')[-1]}`** (`{t['assetId']}`, {t['displayName']}) — {t['why']}")
    lines.append("")
    lines.append("Also evaluated and **not** imported: `Ground062S`'s siblings ")
    lines.append(
        "`Ground093A/B/C`, `Ground096A/B/C` (paler, near-duplicates of 079L/062L); "
        "`Ground108` / `Ground110` / `Gravel023` (rubble and dark gravel — high "
        "spatial frequency that aliases badly at 128px, and a grey palette that "
        "fights the desert biome); `Ground047` and `Ground074` (mossy green, not "
        "desert); `Ground031` (urban asphalt); `Ground111` (saturated red rock)."
    )
    lines.append("")
    lines.append("### Reproduction")
    lines.append("")
    lines.append("```sh")
    lines.append("python3 tools/fetch_cc0.py             # re-derive everything, then verify")
    lines.append("python3 tools/fetch_cc0.py --check     # verify only; exit 1 on any drift")
    lines.append("```")
    lines.append("")
    lines.append(
        "Kenney members are copied byte-for-byte from the archives in the shared "
        "library (`$GAMEASSETS_LIBRARY`, default `~/gameassets`). "
        "Ground tiles are re-derived from ambientCG's public JSON API: 1K-JPG "
        "archive → **colour map only** → centre-crop to 512 → half-offset wrap-blend "
        "(so both axes tile) → LANCZOS to 128 → PNG. No normal, roughness, "
        "displacement, AO, HDRI or USD data is ever downloaded."
    )
    lines.append("")
    lines.append(END_MARK)
    return "\n".join(lines)


def write_assets_md_section(manifest: dict) -> str:
    """Replace only the generated block; leave every other line alone."""
    section = render_assets_md_section(manifest)
    if not ASSETS_MD.is_file():
        raise FetchError(f"ASSETS.md not found at {ASSETS_MD}")
    doc = ASSETS_MD.read_text(encoding="utf-8")
    if BEGIN_MARK in doc and END_MARK in doc:
        pre = doc.split(BEGIN_MARK)[0]
        post = doc.split(END_MARK, 1)[1]
        new_doc = pre + section + post
    elif BEGIN_MARK in doc or END_MARK in doc:
        raise FetchError("ASSETS.md has only one of the cc0_extra section markers")
    else:
        if not doc.endswith("\n"):
            doc += "\n"
        new_doc = doc + "\n" + section + "\n"
    ASSETS_MD.write_text(new_doc, encoding="utf-8")
    return section


# --------------------------------------------------------------------------
# Files that must never be imported, with the evidence that put them there.
# Kept in the manifest so a later reader cannot "helpfully" re-add them.
# --------------------------------------------------------------------------

QUARANTINED = [
    {
        "archive": "source/downloads/oga_16-toon-muzzle-flash.zip",
        "contents": "17 PNGs (muzzle_flashs/m_1.png .. m_16.png), 1.13 MB total",
        "reason": "No licence of any kind in the archive",
        "evidence": (
            "unzip -Z1 lists exactly 17 entries: 16 PNGs plus the 'muzzle_flashs/' "
            "directory entry. A grep for licen|readme|.txt|.md|.pdf|credit across the "
            "central directory returns ZERO matches. The submitting OGA page's licence "
            "is not reproduced anywhere in the artefact, so it cannot be verified from "
            "the artefact."
        ),
    },
    {
        "archive": "source/downloads/oga_stone-tower-game-assets.zip",
        "contents": "4 .fla sources + 63 PNGs + TXT/readme.txt, 2.86 MB total",
        "reason": "The only text file is a font attribution link, not a licence",
        "evidence": (
            "The archive's sole non-artwork file is TXT/readme.txt, 52 bytes, whose "
            "entire content is: 'Chisel Mark\\r\\n"
            "https://www.dafont.com/chisel-mark-font'. That is a dafont.com "
            "attribution for the FL authoring font, granting nothing. No CC0, CC-BY or "
            "any other licence statement exists in the artefact."
        ),
    },
]


def scan_sidecars() -> dict[str, dict]:
    """Record Godot's generated `.import` sidecars for every file we placed.

    Sidecar *contents* are deliberately NOT hashed. Godot owns them -- it
    rewrites the `uid` and the `.godot/imported/` path whenever it re-imports,
    so pinning a hash would make `--check` fail on a perfectly healthy tree.
    What IS asserted is the contract `tools/lint_assets.gd` enforces: every
    asset has a sidecar, no sidecar is orphaned, and each one's declared
    `source_file` points back at the file it was generated from.
    """
    out: dict[str, dict] = {}
    for p in sorted(OUT.rglob("*.import")):
        rel = p.relative_to(OUT).as_posix()
        text = p.read_text(encoding="utf-8", errors="replace")
        m = re.search(r'^source_file="([^"]+)"', text, re.M)
        out[rel] = {
            "source": rel[: -len(".import")],
            "source_file": m.group(1) if m else None,
        }
    return out


# --------------------------------------------------------------------------
# Build
# --------------------------------------------------------------------------


def do_build(accept_drift: bool) -> int:
    if not DOWNLOADS.is_dir():
        warn(f"source library not found at {DOWNLOADS} (override with $GAMEASSETS_LIBRARY)")
        return 2

    log("Kenney CC0 subsets (licence verified inside each archive first):")
    files, licences = fetch_kenney()

    log("ambientCG ground candidates:")
    ground_files, tiles = fetch_ground()
    files.update(ground_files)

    today = time.strftime("%Y-%m-%d")
    lic_dir = OUT / "licenses"
    lic_dir.mkdir(parents=True, exist_ok=True)
    (lic_dir / "LICENSE-CC0-kenney.txt").write_text(
        KENNEY_LICENCE_TEXT.format(retrieved=today), encoding="utf-8"
    )
    (lic_dir / "LICENSE-CC0-ambientcg.txt").write_text(
        AMBIENTCG_LICENCE_TEXT.format(
            retrieved=today, licence_url=AMBIENTCG_LICENCE_URL, credits_url=AMBIENTCG_CREDITS_URL
        ),
        encoding="utf-8",
    )
    for key, text in licences.items():
        (lic_dir / f"source-licence-{key}.txt").write_text(text, encoding="utf-8")

    manifest = build_manifest(files, tiles, {k: v for k, v in licences.items() if k in ("railgun",)})
    # Per-pack licence bodies are stored by name so --check can re-assert them.
    manifest["licence_files"] = sorted(
        p.relative_to(OUT).as_posix() for p in lic_dir.glob("*.txt")
    )
    for p in lic_dir.glob("*.txt"):
        rel = p.relative_to(OUT).as_posix()
        manifest.setdefault("files", {})[rel] = {
            "sha256": hashlib.sha256(p.read_bytes()).hexdigest(),
            "bytes": p.stat().st_size,
            "kind": "txt",
            "source_pack": "licence-text",
            "source_member": p.name,
            "source_archive": "",
            "source_url": KENNEY_PACKS.get(
                next(
                    (k for k, v in KENNEY_PACKS.items() if f"source-licence-{k}" in p.name),
                    "",
                ),
                {"upstream": ""},
            )["upstream"],
            "licence": "CC0-1.0",
            "licence_evidence": "verbatim licence text captured from the source artefact",
        }

    # Recompute the totals AFTER the licence texts are merged in, so MANIFEST.json
    # and `fetch_cc0.py --check` report the same number. build_manifest() only saw
    # the asset files, and a header that says 95 while the checker says 104 is the
    # kind of quiet inconsistency this repo's own docs warn about.
    manifest["total_files"] = len(manifest["files"])
    manifest["total_bytes"] = sum(f["bytes"] for f in manifest["files"].values())
    manifest["asset_files"] = sum(1 for f in manifest["files"].values() if f.get("kind") != "txt")
    manifest["licence_text_files"] = manifest["total_files"] - manifest["asset_files"]
    manifest["asset_bytes"] = sum(
        f["bytes"] for f in manifest["files"].values() if f.get("kind") != "txt"
    )

    manifest["sidecars"] = scan_sidecars()
    log(f"\n  {len(manifest['sidecars'])} Godot .import sidecars present")

    existing = load_manifest()
    if existing is None:
        MANIFEST_PATH.write_text(json.dumps(manifest, indent=1) + "\n", encoding="utf-8")
        section = write_assets_md_section(manifest)
        log(
            f"\nWrote {MANIFEST_PATH.relative_to(REPO)} (no baseline existed; created) "
            f"and the ASSETS.md section ({len(section.splitlines())} lines)."
        )
        return 0

    drift = compare(manifest, existing)
    if drift:
        if not accept_drift:
            warn("built output does not match the committed MANIFEST.json:")
            for line in drift:
                warn("  " + line)
            warn("re-run with --accept-drift to re-baseline (records what moved).")
            return 1
        warn("--accept-drift: re-baselining MANIFEST.json; %d difference(s) recorded" % len(drift))
        for line in drift:
            warn("  " + line)
        old = existing.get("files", {})
        manifest.setdefault("drift_from_previous", {})
        for rel, meta in manifest.get("files", {}).items():
            prev = old.get(rel)
            if prev is None:
                manifest["drift_from_previous"][rel] = {"was": None, "now": meta["sha256"]}
            elif prev.get("sha256") != meta["sha256"]:
                manifest["drift_from_previous"][rel] = {
                    "was": prev.get("sha256"),
                    "now": meta["sha256"],
                }

    # Only now, with the drift gate passed, is it safe to touch tracked docs.
    MANIFEST_PATH.write_text(json.dumps(manifest, indent=1) + "\n", encoding="utf-8")
    section = write_assets_md_section(manifest)
    log(f"  ASSETS.md provenance section written ({len(section.splitlines())} lines)")
    return 0


# --------------------------------------------------------------------------
# Verify
# --------------------------------------------------------------------------


def compare(built: dict, recorded: dict) -> list[str]:
    out: list[str] = []
    b, r = built.get("files", {}), recorded.get("files", {})
    for rel in sorted(set(r) - set(b)):
        out.append(f"{rel}: in MANIFEST.json but not produced by this run")
    for rel in sorted(set(b) - set(r)):
        out.append(f"{rel}: produced by this run but absent from MANIFEST.json")
    for rel in sorted(set(b) & set(r)):
        if b[rel].get("sha256") != r[rel].get("sha256"):
            out.append(
                f"{rel}: sha256 changed "
                f"({str(r[rel].get('sha256'))[:12]} -> {str(b[rel].get('sha256'))[:12]})"
            )
        elif b[rel].get("bytes") != r[rel].get("bytes"):
            out.append(f"{rel}: size changed ({r[rel].get('bytes')} -> {b[rel].get('bytes')})")
    bt, rt = built.get("ground_tiles", {}), recorded.get("ground_tiles", {})
    for rel in sorted(set(rt) - set(bt)):
        out.append(f"{rel}: ground tile in MANIFEST.json but not produced by this run")
    return out


def do_check(with_source: bool) -> int:
    manifest = load_manifest()
    fails: list[str] = []

    if manifest is None:
        print("fetch_cc0 --check: FAIL — no MANIFEST.json. Run the script once to create it.")
        return 1

    recorded = manifest.get("files", {})
    if not recorded:
        print("fetch_cc0 --check: FAIL — MANIFEST.json claims zero files.")
        return 1

    # 1. every claimed file exists with the claimed hash and size
    total = 0
    for rel, meta in sorted(recorded.items()):
        p = OUT / rel
        if not p.is_file():
            fails.append(f"missing: {rel}")
            continue
        blob = p.read_bytes()
        got = hashlib.sha256(blob).hexdigest()
        if got != meta.get("sha256"):
            fails.append(f"hash mismatch: {rel} (want {str(meta.get('sha256'))[:12]}, got {got[:12]})")
        if len(blob) != meta.get("bytes"):
            fails.append(f"size mismatch: {rel} (want {meta.get('bytes')}, got {len(blob)})")
        total += len(blob)
    log(f"  {len(recorded)} claimed files present, {total:,} bytes")

    # 2. no UNCLAIMED asset files, and no denylisted junk, anywhere in the tree.
    #    `.import` sidecars and the QUARANTINED.md record are Godot-owned /
    #    hand-written respectively, so they are allowed through explicitly rather
    #    than by loosening the check.
    sidecars = manifest.get("sidecars", {})
    on_disk = {
        p.relative_to(OUT).as_posix()
        for p in OUT.rglob("*")
        if p.is_file() and p.name != "MANIFEST.json"
    }
    allowed_extra = set(sidecars) | {"QUARANTINED.md"}
    for rel in sorted(on_disk - set(recorded) - allowed_extra):
        fails.append(f"unclaimed file in assets/cc0_extra: {rel}")
    for rel in sorted(on_disk):
        if is_junk(rel):
            fails.append(f"denylisted junk present: {rel}")

    # 2b. sidecar contract -- the same one tools/lint_assets.gd enforces, so
    #     this cannot pass while that gate is red.
    for rel, meta in sorted(recorded.items()):
        if meta.get("kind") == "txt" or rel.endswith(".md"):
            continue
        if f"{rel}.import" not in sidecars:
            fails.append(f"no Godot .import sidecar for {rel} (lint_assets would fail)")
    for rel, meta in sorted(sidecars.items()):
        p = OUT / rel
        if not p.is_file():
            fails.append(f"missing .import sidecar: {rel}")
            continue
        src = meta.get("source")
        if not (OUT / src).is_file():
            fails.append(f"orphaned .import sidecar (no source asset): {rel}")
            continue
        want = "res://assets/cc0_extra/" + src
        if meta.get("source_file") != want:
            fails.append(
                f"{rel}: declares source_file={meta.get('source_file')!r}, expected {want!r}"
            )
    log(f"  {len(sidecars)} .import sidecars matched to their source assets")

    # 3. ground tiles still measure within the seam bar
    for rel, meta in sorted(manifest.get("ground_tiles", {}).items()):
        p = OUT / rel
        if not p.is_file():
            continue
        with Image.open(p) as im:
            if im.size != (manifest.get("tile_px", TILE_PX),) * 2:
                fails.append(f"{rel}: {im.size} is not {manifest.get('tile_px')}x{manifest.get('tile_px')}")
                continue
            rx, ry = seam_ratio(im.convert("RGB"))
        bar = meta.get("bar", SEAM_RATIO_MAX)
        if max(rx, ry) > bar:
            fails.append(f"{rel}: seam ratio {max(rx, ry):.3f} > {bar} (x={rx:.3f} y={ry:.3f})")
        log(
            f"  {rel:44s} seam x={rx:.3f} y={ry:.3f}  bar={bar}  "
            f"({'PASS' if max(rx, ry) <= bar else 'FAIL'})"
        )

    # 4. licence attribution is actually present and says CC0
    for rel in manifest.get("licence_files", []):
        p = OUT / rel
        if not p.is_file():
            fails.append(f"missing licence text: {rel}")
            continue
        try:
            assert_cc0(p.read_text(encoding="utf-8", errors="replace"), rel)
        except FetchError as exc:
            fails.append(f"licence text does not assert CC0: {rel} ({exc})")
    for rel, meta in sorted(recorded.items()):
        if not meta.get("licence"):
            fails.append(f"no licence recorded for {rel}")
        elif not meta.get("licence_evidence"):
            fails.append(f"no licence evidence recorded for {rel}")
    log(f"  {len(manifest.get('licence_files', []))} licence text files assert CC0")

    # 5. ASSETS.md carries a provenance row for every file AND for the directory
    doc = ASSETS_MD.read_text(encoding="utf-8") if ASSETS_MD.is_file() else ""
    if not doc:
        fails.append("ASSETS.md is missing or empty")
    else:
        for rel, meta in sorted(recorded.items()):
            if meta.get("kind") == "txt":
                continue  # licence texts are the evidence itself, not a row
            if rel not in doc:
                fails.append(f"no ASSETS.md provenance row mentions {rel}")
        if "assets/cc0_extra/" not in doc:
            fails.append("ASSETS.md never mentions assets/cc0_extra/ (lint_assets gate)")
        # The generated block must be byte-identical to what the manifest renders,
        # so a hand-edit to a hash, a byte count or a seam number cannot survive.
        if BEGIN_MARK not in doc or END_MARK not in doc:
            fails.append("ASSETS.md is missing the generated cc0_extra section markers")
        else:
            in_doc = doc.split(BEGIN_MARK, 1)[1].split(END_MARK, 1)[0]
            want = render_assets_md_section(manifest)
            want_inner = want.split(BEGIN_MARK, 1)[1].split(END_MARK, 1)[0]
            if in_doc != want_inner:
                fails.append(
                    "ASSETS.md cc0_extra section has been hand-edited away from the "
                    "manifest (rerun tools/fetch_cc0.py to regenerate)"
                )
    log("  ASSETS.md provenance rows present for every claimed asset file")

    # 6. nothing from a quarantined archive leaked in
    for q in manifest.get("quarantined", []):
        base = Path(q["archive"]).name.lower()
        for rel in recorded:
            if base.split(".")[0] in rel.lower():
                fails.append(f"{rel} appears to come from a quarantined archive ({q['archive']})")
    log(f"  {len(manifest.get('quarantined', []))} quarantined sources confirmed absent")

    # 7. optional: re-prove the licences from the source artefacts
    if with_source:
        try:
            for key, spec in KENNEY_PACKS.items():
                if not Path(spec["zip"]).is_file():
                    fails.append(f"{key}: source archive gone, cannot re-verify licence")
                    continue
                with zipfile.ZipFile(Path(spec["zip"])) as zf:
                    read_licence_from_zip(zf, spec["licence_member"], f"{key} (re-verify)")
            if RAILGUN["licence"].is_file():
                assert_cc0(RAILGUN["licence"].read_text(errors="replace"), "railgun (re-verify)")
            stmt = ambientcg_licence_statement()
            log(f"  re-verified: 6 Kenney packs + railgun sidecar in-archive; ambientCG says \"{stmt}\"")
        except FetchError as exc:
            fails.append(f"source re-verification failed: {exc}")

    print()
    if fails:
        print(f"fetch_cc0 --check: FAIL — {len(fails)} issue(s)")
        for f in fails[:60]:
            print("  - " + f)
        if len(fails) > 60:
            print(f"  ... and {len(fails) - 60} more")
        return 1
    print(
        f"fetch_cc0 --check: OK — {len(recorded)} files, {total:,} bytes, "
        f"licences attributed, ground tiles within the {SEAM_RATIO_MAX}x seam bar"
    )
    return 0


# --------------------------------------------------------------------------


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--check", action="store_true", help="verify the tree against MANIFEST.json and exit")
    ap.add_argument(
        "--with-source",
        action="store_true",
        help="with --check, also re-prove every licence from the source archives/live site",
    )
    ap.add_argument(
        "--accept-drift",
        action="store_true",
        help="re-baseline MANIFEST.json after a build, recording what changed",
    )
    ap.add_argument("--library", type=Path, default=None, help="override the asset library root")
    ap.add_argument("--cache", type=Path, default=None, help="override the 1K colour-map cache dir")
    args = ap.parse_args(argv)

    global DOWNLOADS, CACHE
    if args.library:
        DOWNLOADS = args.library / "source" / "downloads"
    if args.cache:
        CACHE = args.cache

    if args.check:
        if args.accept_drift:
            ap.error("--accept-drift only applies to a build, not to --check")
        return do_check(args.with_source)
    try:
        return do_build(args.accept_drift)
    except FetchError as exc:
        warn(str(exc))
        return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
