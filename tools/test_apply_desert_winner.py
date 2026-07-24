#!/usr/bin/env python3
"""Minimal self-check for apply_desert_winner.py -- run directly:

    python3 tools/test_apply_desert_winner.py

Both checks drive main() itself (not just its plumbing) against a scratch
manifest + candidate tree, with apply_desert_winner.PROJECT_ROOT monkeypatched
to a temp dir so nothing under the real assets/art/ is ever touched:

  1. Winner-indexed copy: winner=2 copies variant_2.png (not variant_1.png)
     over the "replaces" path; winner=None (unset) leaves its dest
     untouched; an out-of-range winner is skipped rather than crashing.
  2. .import re-bake hand-off: resolve_godot/run_godot_import/
     fix_import_settings/assert_lossless_art_import are monkeypatched (no
     real Godot binary needed) so main()'s documented call order -- import
     pass 1, then fix+assert per applied asset, then import pass 2 -- is
     asserted directly, once each.
  3. Winner-install validation: a same-size RGBA winner installs cleanly;
     a size-mismatched, alpha-less, corrupt, or fully-transparent winner
     aborts main() BEFORE any import pass runs (and before the bad file
     ever lands on the live dest), so a bad drop-in can't reach the
     (expensive) godot --import step or the on-disk .import sidecar.
     Validation runs even under --dry-run, so a bad winner is surfaced
     without needing a real apply first.
  4. New-asset dimension guard: installing over a sprite with no prior
     file (nothing to size-check against) prints a visible warning instead
     of silently skipping the guard, and still completes the install.
  5. --dry-run validation: a size-mismatched winner raises under --dry-run
     too (not just on a real apply), proving validate_winner_install() runs
     before the dry-run early return rather than being skipped by it.
"""
import contextlib
import io
import json
import shutil
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import apply_desert_winner as adw  # noqa: E402
from generate_desert_assets import Image  # noqa: E402

# Distinct opaque-alpha colors so a copied file can be identified by pixel,
# not by comparing raw (variable-length, encoder-dependent) PNG bytes.
_ORIGINAL = (10, 10, 10, 255)
_VARIANT_1 = (255, 0, 0, 255)
_VARIANT_2 = (0, 255, 0, 255)
_VARIANT_3 = (0, 0, 255, 255)


def _write_manifest(candidates_root: Path, manifest: dict) -> Path:
    path = candidates_root / "manifest.json"
    path.write_text(json.dumps(manifest))
    return path


def _png(path: Path, color=(120, 140, 90, 255), size: tuple[int, int] = (8, 8)) -> None:
    mode = "RGBA" if len(color) == 4 else "RGB"
    Image.new(mode, size, color).save(path)


def _pixel(path: Path) -> tuple:
    return Image.open(path).convert("RGBA").getpixel((0, 0))


def _run_main(argv: list[str]) -> int:
    real_argv = sys.argv
    sys.argv = ["apply_desert_winner.py", *argv]
    try:
        return adw.main()
    finally:
        sys.argv = real_argv


def check_winner_indexed_copy() -> None:
    tmp_root = Path(tempfile.mkdtemp(prefix="apply_desert_winner_copy_selftest_"))
    real_project_root = adw.PROJECT_ROOT
    try:
        candidates_root = tmp_root / "candidates"
        (candidates_root / "cactus_large").mkdir(parents=True)
        (candidates_root / "cactus_small").mkdir(parents=True)
        _png(candidates_root / "cactus_large" / "variant_1.png", _VARIANT_1)
        _png(candidates_root / "cactus_large" / "variant_2.png", _VARIANT_2)
        _png(candidates_root / "cactus_large" / "variant_3.png", _VARIANT_3)
        _png(candidates_root / "cactus_small" / "variant_1.png", _VARIANT_1)

        art_dir = tmp_root / "assets" / "art"
        art_dir.mkdir(parents=True)
        _png(art_dir / "cactus_large.png", _ORIGINAL)
        _png(art_dir / "cactus_small.png", _ORIGINAL)
        _png(art_dir / "cactus_dead1.png", _ORIGINAL)

        manifest = {
            "cactus_large": {
                "replaces": "assets/art/cactus_large.png",
                "variants": [{"path": f"cactus_large/variant_{n}.png", "backend": "openrouter"} for n in (1, 2, 3)],
                "winner": 2,
            },
            "cactus_small": {
                "replaces": "assets/art/cactus_small.png",
                "variants": [{"path": "cactus_small/variant_1.png", "backend": "openrouter"}],
                "winner": None,
            },
            "cactus_dead1": {
                "replaces": "assets/art/cactus_dead1.png",
                "variants": [{"path": "cactus_dead1/variant_1.png", "backend": "openrouter"}],
                "winner": 5,  # out of range for a 1-variant entry -- must be skipped, not crash
            },
            "backend_legend": {"or": "openrouter"},
        }
        manifest_path = _write_manifest(candidates_root, manifest)

        adw.PROJECT_ROOT = tmp_root
        rc = _run_main(["--manifest", str(manifest_path), "--skip-import"])
        assert rc == 0, f"main() should exit 0 for a valid (partial) winner set, got {rc}"

        assert _pixel(art_dir / "cactus_large.png") == _VARIANT_2, (
            "winner=2 should copy variant_2.png (not variant_1.png), "
            f"got pixel {_pixel(art_dir / 'cactus_large.png')!r}")
        assert _pixel(art_dir / "cactus_small.png") == _ORIGINAL, (
            "winner=None (unset) should leave its dest untouched")
        assert _pixel(art_dir / "cactus_dead1.png") == _ORIGINAL, (
            "an out-of-range winner should be skipped, not crash or copy garbage")
    finally:
        adw.PROJECT_ROOT = real_project_root
        shutil.rmtree(tmp_root, ignore_errors=True)

    print("OK: winner-indexed copy (correct variant_<n>.png picked; unset/out-of-range winners left untouched)")


def check_import_rebake_sequence() -> None:
    tmp_root = Path(tempfile.mkdtemp(prefix="apply_desert_winner_import_selftest_"))
    real_project_root = adw.PROJECT_ROOT
    real_resolve_godot = adw.resolve_godot
    real_run_godot_import = adw.run_godot_import
    real_fix_import_settings = adw.fix_import_settings
    real_assert_lossless = adw.assert_lossless_art_import
    try:
        candidates_root = tmp_root / "candidates"
        (candidates_root / "cactus_large").mkdir(parents=True)
        _png(candidates_root / "cactus_large" / "variant_1.png", _VARIANT_1)

        art_dir = tmp_root / "assets" / "art"
        art_dir.mkdir(parents=True)
        dest = art_dir / "cactus_large.png"
        _png(dest, _ORIGINAL)

        manifest = {
            "cactus_large": {
                "replaces": "assets/art/cactus_large.png",
                "variants": [{"path": "cactus_large/variant_1.png", "backend": "openrouter"}],
                "winner": 1,
            },
            "backend_legend": {"or": "openrouter"},
        }
        manifest_path = _write_manifest(candidates_root, manifest)

        calls = []
        adw.PROJECT_ROOT = tmp_root
        adw.resolve_godot = lambda godot_bin: "fake-godot"
        adw.run_godot_import = lambda godot_bin: calls.append(("import", godot_bin))
        adw.fix_import_settings = lambda p: calls.append(("fix", p))
        adw.assert_lossless_art_import = lambda p: calls.append(("assert", p))

        rc = _run_main(["--manifest", str(manifest_path)])
        assert rc == 0, f"main() should exit 0, got {rc}"

        assert _pixel(dest) == _VARIANT_1, "the winning variant should be copied before any import pass"
        assert calls == [
            ("import", "fake-godot"),
            ("fix", dest),
            ("assert", dest),
            ("import", "fake-godot"),
        ], f"expected import -> fix+assert(per applied asset) -> import, got {calls}"
    finally:
        adw.PROJECT_ROOT = real_project_root
        adw.resolve_godot = real_resolve_godot
        adw.run_godot_import = real_run_godot_import
        adw.fix_import_settings = real_fix_import_settings
        adw.assert_lossless_art_import = real_assert_lossless
        shutil.rmtree(tmp_root, ignore_errors=True)

    print("OK: .import re-bake hand-off (import pass 1 -> fix+assert per applied asset -> import pass 2, "
          "no real Godot binary needed)")


def check_bad_winner_install_aborts_before_import() -> None:
    tmp_root = Path(tempfile.mkdtemp(prefix="apply_desert_winner_validate_selftest_"))
    real_project_root = adw.PROJECT_ROOT
    real_run_godot_import = adw.run_godot_import
    try:
        adw.PROJECT_ROOT = tmp_root
        import_calls = []
        adw.run_godot_import = lambda godot_bin: import_calls.append(godot_bin)

        # name -> (variant color-or-None, variant size) vs. a fixed 8x8 RGBA original.
        # color=None means "write a corrupt/truncated file instead of a real PNG".
        cases = {
            "size_mismatch": (_VARIANT_1, (16, 16)),
            "no_alpha": ((255, 0, 0), (8, 8)),
            "corrupt": (None, (8, 8)),
            "fully_transparent": ((10, 10, 10, 0), (8, 8)),
        }
        for name, (color, size) in cases.items():
            candidates_root = tmp_root / f"candidates_{name}"
            (candidates_root / name).mkdir(parents=True)
            variant_path = candidates_root / name / "variant_1.png"
            if color is None:
                variant_path.write_bytes(b"not a real png, truncated garbage")
            else:
                _png(variant_path, color, size)

            art_dir = tmp_root / "assets" / "art"
            art_dir.mkdir(parents=True, exist_ok=True)
            dest = art_dir / f"{name}.png"
            _png(dest, _ORIGINAL, (8, 8))

            manifest = {
                name: {
                    "replaces": f"assets/art/{name}.png",
                    "variants": [{"path": f"{name}/variant_1.png", "backend": "openrouter"}],
                    "winner": 1,
                },
                "backend_legend": {"or": "openrouter"},
            }
            manifest_path = _write_manifest(candidates_root, manifest)

            raised = False
            try:
                _run_main(["--manifest", str(manifest_path)])
            except ValueError:
                raised = True
            assert raised, f"{name}: a bad winner install should raise, not exit cleanly"
            assert _pixel(dest) == _ORIGINAL, (
                f"{name}: dest must NOT be left holding the bad winner after validation fails")

        assert import_calls == [], "a validation failure must abort before ANY godot --import pass runs"
    finally:
        adw.PROJECT_ROOT = real_project_root
        adw.run_godot_import = real_run_godot_import
        shutil.rmtree(tmp_root, ignore_errors=True)

    print("OK: bad winner install (size mismatch / no alpha / corrupt / fully transparent) "
          "raises and aborts before any --import pass")


def check_new_asset_skips_dimension_guard_with_a_visible_warning() -> None:
    tmp_root = Path(tempfile.mkdtemp(prefix="apply_desert_winner_newasset_selftest_"))
    real_project_root = adw.PROJECT_ROOT
    try:
        candidates_root = tmp_root / "candidates"
        (candidates_root / "new_prop").mkdir(parents=True)
        _png(candidates_root / "new_prop" / "variant_1.png", _VARIANT_1, (32, 32))

        # No pre-existing assets/art/new_prop.png -- this is a first-time install.
        manifest = {
            "new_prop": {
                "replaces": "assets/art/new_prop.png",
                "variants": [{"path": "new_prop/variant_1.png", "backend": "openrouter"}],
                "winner": 1,
            },
            "backend_legend": {"or": "openrouter"},
        }
        manifest_path = _write_manifest(candidates_root, manifest)

        adw.PROJECT_ROOT = tmp_root
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            rc = _run_main(["--manifest", str(manifest_path), "--skip-import"])
        out = buf.getvalue()
        assert rc == 0, f"a valid first-time install should exit 0, got {rc}"
        assert "no existing sprite to size-check against" in out, (
            f"a new-asset install must print a visible dimension-guard-skip warning, got:\n{out}")
        dest = tmp_root / "assets" / "art" / "new_prop.png"
        assert dest.exists() and _pixel(dest) == _VARIANT_1, (
            "the warning must not block the install -- a new asset with no size to compare against still copies")
    finally:
        adw.PROJECT_ROOT = real_project_root
        shutil.rmtree(tmp_root, ignore_errors=True)

    print("OK: a first-time (no prior sprite) install prints the dimension-guard-skip warning and still copies")


def check_dry_run_surfaces_bad_winner() -> None:
    """--dry-run must run validate_winner_install() too, not just report the
    copy it would skip -- a corrupt/opaque/transparent/size-mismatched
    winner should raise under --dry-run exactly like a real run, before
    ever touching the live dest."""
    tmp_root = Path(tempfile.mkdtemp(prefix="apply_desert_winner_dryrun_selftest_"))
    real_project_root = adw.PROJECT_ROOT
    try:
        adw.PROJECT_ROOT = tmp_root
        candidates_root = tmp_root / "candidates"
        (candidates_root / "cactus_large").mkdir(parents=True)
        _png(candidates_root / "cactus_large" / "variant_1.png", _VARIANT_1, (16, 16))

        art_dir = tmp_root / "assets" / "art"
        art_dir.mkdir(parents=True)
        dest = art_dir / "cactus_large.png"
        _png(dest, _ORIGINAL, (8, 8))  # size-mismatched winner: 16x16 vs 8x8

        manifest = {
            "cactus_large": {
                "replaces": "assets/art/cactus_large.png",
                "variants": [{"path": "cactus_large/variant_1.png", "backend": "openrouter"}],
                "winner": 1,
            },
            "backend_legend": {"or": "openrouter"},
        }
        manifest_path = _write_manifest(candidates_root, manifest)

        raised = False
        try:
            _run_main(["--manifest", str(manifest_path), "--dry-run"])
        except ValueError:
            raised = True
        assert raised, "a size-mismatched winner must raise under --dry-run too, not just on a real apply"
        assert _pixel(dest) == _ORIGINAL, "dest must be untouched -- --dry-run never copies anyway"
    finally:
        adw.PROJECT_ROOT = real_project_root
        shutil.rmtree(tmp_root, ignore_errors=True)

    print("OK: --dry-run runs validate_winner_install() too, surfacing a bad winner without a real apply")


def main() -> int:
    check_winner_indexed_copy()
    check_import_rebake_sequence()
    check_bad_winner_install_aborts_before_import()
    check_new_asset_skips_dimension_guard_with_a_visible_warning()
    check_dry_run_surfaces_bad_winner()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
