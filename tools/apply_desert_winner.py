#!/usr/bin/env python3
"""Apply the winner picked from generate_desert_variants.py's contact
sheets: copy each asset's chosen variant_<n>.png over its live
assets/art/ sprite and re-bake the .import sidecar.

This is the deliberately-deferred other half of the winner-selection
handoff generate_desert_variants.py prints at the end of a run -- reads
manifest.json, and for every asset whose "winner" field has been hand-set
to a variant number (1-based, matching the contact sheet), copies that
variant PNG over the "replaces" path and re-imports. Assets whose winner is
still null (the default -- nobody has picked one yet) are skipped, so
running this before any winners are chosen is a safe no-op.

Usage:
    # after eyeballing art_candidates/desert_reskin/*/contact_sheet.png and
    # editing manifest.json's "winner": null -> "winner": 2 for each asset
    # you've picked:
    python3 tools/apply_desert_winner.py

    python3 tools/apply_desert_winner.py --dry-run   # show what WOULD be copied
    python3 tools/apply_desert_winner.py --skip-import  # copy only, bake .import yourself
"""
import argparse
import json
import shutil
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from generate_desert_assets import (  # noqa: E402
    DEFAULT_GODOT,
    PROJECT_ROOT,
    Image,
    assert_lossless_art_import,
    fix_import_settings,
    resolve_godot,
    run_godot_import,
    validate_winner_install,
)

DEFAULT_MANIFEST = PROJECT_ROOT / "art_candidates" / "desert_reskin" / "manifest.json"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--manifest", default=str(DEFAULT_MANIFEST),
                     help=f"manifest.json written by generate_desert_variants.py "
                          f"(default: {DEFAULT_MANIFEST})")
    ap.add_argument("--dry-run", action="store_true",
                     help="print what would be copied without touching assets/art/")
    ap.add_argument("--skip-import", action="store_true",
                     help="copy the winning PNGs but skip the godot --import re-bake pass")
    ap.add_argument("--godot-bin", default=DEFAULT_GODOT, help="Godot headless binary")
    args = ap.parse_args()

    manifest_path = Path(args.manifest)
    if not manifest_path.exists():
        print(f"missing {manifest_path} -- run generate_desert_variants.py first", file=sys.stderr)
        return 1
    manifest = json.loads(manifest_path.read_text())
    candidates_root = manifest_path.parent

    picked = []  # (asset_name, src_path, dest_path)
    for name, entry in manifest.items():
        if name == "backend_legend":
            continue
        winner = entry.get("winner")
        if winner is None:
            continue
        variants = entry["variants"]
        if not (1 <= winner <= len(variants)):
            print(f"{name}: winner={winner!r} is out of range for {len(variants)} variant(s) -- skipping", file=sys.stderr)
            continue
        src = candidates_root / variants[winner - 1]["path"]
        dest = PROJECT_ROOT / entry["replaces"]
        picked.append((name, src, dest))

    if not picked:
        print("no asset has a winner set yet -- nothing to do "
              "(edit manifest.json's \"winner\": null -> a variant number for each asset you've picked)")
        return 0

    for name, src, dest in picked:
        orig_size = None
        if dest.exists():
            orig_size = Image.open(dest).size
        else:
            print(f"  warning: {dest} has no existing sprite to size-check against "
                  f"(new asset) -- skipping the dimension guard for {name}")
        # Validate on every run, dry or not -- a --dry-run should surface a corrupt/opaque/
        # transparent/size-mismatched winner too, not just report the copy it would skip.
        validate_winner_install(src, orig_size)
        print(f"{'[dry-run] would copy' if args.dry_run else 'copying'} {src} -> {dest}")
        if not args.dry_run:
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(src, dest)

    if args.dry_run:
        print(f"{len(picked)} asset(s) would be updated. Rerun without --dry-run to apply.")
        return 0

    if args.skip_import:
        print(f"{len(picked)} asset(s) updated. Skipping godot --import (--skip-import) -- run it yourself.")
        return 0

    godot_bin = resolve_godot(args.godot_bin)
    print(f"running {godot_bin} --import (pass 1: bake default .import)...")
    run_godot_import(godot_bin)
    print("correcting .import settings to the lossless legacy art-bake convention...")
    for _name, _src, dest in picked:
        fix_import_settings(dest)
        assert_lossless_art_import(dest)
    print(f"running {godot_bin} --import (pass 2: bake corrected settings)...")
    run_godot_import(godot_bin)

    print(f"done. {len(picked)} asset(s) updated: {[n for n, _s, _d in picked]}. "
          f"Run `godot --headless --path . -s res://tests/run_tests.gd` to confirm "
          f"test_a1_art_bakes_are_lossless() agrees.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
