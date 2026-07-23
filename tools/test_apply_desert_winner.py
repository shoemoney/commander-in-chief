#!/usr/bin/env python3
"""Minimal self-check for apply_desert_winner.py -- run directly:

    python3 tools/test_apply_desert_winner.py

Both checks drive main() itself (not just its plumbing) against a scratch
manifest + candidate tree, with apply_desert_winner.PROJECT_ROOT monkeypatched
to a temp dir so nothing under the real assets/legacy-art/ is ever touched:

  1. Winner-indexed copy: winner=2 copies variant_2.png (not variant_1.png)
     over the "replaces" path; winner=None (unset) leaves its dest
     untouched; an out-of-range winner is skipped rather than crashing.
  2. .import re-bake hand-off: resolve_godot/run_godot_import/
     fix_import_settings/assert_lossless_legacy-art_import are monkeypatched (no
     real Godot binary needed) so main()'s documented call order -- import
     pass 1, then fix+assert per applied asset, then import pass 2 -- is
     asserted directly, once each.
"""
import json
import shutil
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import apply_desert_winner as adw  # noqa: E402


def _write_manifest(candidates_root: Path, manifest: dict) -> Path:
    path = candidates_root / "manifest.json"
    path.write_text(json.dumps(manifest))
    return path


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
        (candidates_root / "cactus_large" / "variant_1.png").write_bytes(b"V1")
        (candidates_root / "cactus_large" / "variant_2.png").write_bytes(b"V2")
        (candidates_root / "cactus_large" / "variant_3.png").write_bytes(b"V3")
        (candidates_root / "cactus_small" / "variant_1.png").write_bytes(b"S1")

        legacy-art_dir = tmp_root / "assets" / "legacy-art"
        legacy-art_dir.mkdir(parents=True)
        (legacy-art_dir / "cactus_large.png").write_bytes(b"ORIGINAL_L")
        (legacy-art_dir / "cactus_small.png").write_bytes(b"ORIGINAL_S")
        (legacy-art_dir / "cactus_dead1.png").write_bytes(b"ORIGINAL_D")

        manifest = {
            "cactus_large": {
                "replaces": "assets/legacy-art/cactus_large.png",
                "variants": [{"path": f"cactus_large/variant_{n}.png", "backend": "openrouter"} for n in (1, 2, 3)],
                "winner": 2,
            },
            "cactus_small": {
                "replaces": "assets/legacy-art/cactus_small.png",
                "variants": [{"path": "cactus_small/variant_1.png", "backend": "openrouter"}],
                "winner": None,
            },
            "cactus_dead1": {
                "replaces": "assets/legacy-art/cactus_dead1.png",
                "variants": [{"path": "cactus_dead1/variant_1.png", "backend": "openrouter"}],
                "winner": 5,  # out of range for a 1-variant entry -- must be skipped, not crash
            },
            "backend_legend": {"or": "openrouter"},
        }
        manifest_path = _write_manifest(candidates_root, manifest)

        adw.PROJECT_ROOT = tmp_root
        rc = _run_main(["--manifest", str(manifest_path), "--skip-import"])
        assert rc == 0, f"main() should exit 0 for a valid (partial) winner set, got {rc}"

        assert (legacy-art_dir / "cactus_large.png").read_bytes() == b"V2", (
            "winner=2 should copy variant_2.png (not variant_1.png), "
            f"got {(legacy-art_dir / 'cactus_large.png').read_bytes()!r}")
        assert (legacy-art_dir / "cactus_small.png").read_bytes() == b"ORIGINAL_S", (
            "winner=None (unset) should leave its dest untouched")
        assert (legacy-art_dir / "cactus_dead1.png").read_bytes() == b"ORIGINAL_D", (
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
    real_assert_lossless = adw.assert_lossless_legacy-art_import
    try:
        candidates_root = tmp_root / "candidates"
        (candidates_root / "cactus_large").mkdir(parents=True)
        (candidates_root / "cactus_large" / "variant_1.png").write_bytes(b"V1")

        legacy-art_dir = tmp_root / "assets" / "legacy-art"
        legacy-art_dir.mkdir(parents=True)
        dest = legacy-art_dir / "cactus_large.png"
        dest.write_bytes(b"ORIGINAL_L")

        manifest = {
            "cactus_large": {
                "replaces": "assets/legacy-art/cactus_large.png",
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
        adw.assert_lossless_legacy-art_import = lambda p: calls.append(("assert", p))

        rc = _run_main(["--manifest", str(manifest_path)])
        assert rc == 0, f"main() should exit 0, got {rc}"

        assert dest.read_bytes() == b"V1", "the winning variant should be copied before any import pass"
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
        adw.assert_lossless_legacy-art_import = real_assert_lossless
        shutil.rmtree(tmp_root, ignore_errors=True)

    print("OK: .import re-bake hand-off (import pass 1 -> fix+assert per applied asset -> import pass 2, "
          "no real Godot binary needed)")


def main() -> int:
    check_winner_indexed_copy()
    check_import_rebake_sequence()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
