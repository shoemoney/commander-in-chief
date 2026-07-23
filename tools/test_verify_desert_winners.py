#!/usr/bin/env python3
"""Minimal self-check for verify_desert_winners.py -- run directly:

    python3 tools/test_verify_desert_winners.py

Drives check_winners() against a scratch manifest + candidate tree (no
real assets/legacy-art/ touched):

  1. Match path: a winner whose variant bytes equal the live sprite bytes
     reports match=True and no mismatch.
  2. Mismatch path: a winner whose variant bytes differ from the live
     sprite (drifted after a hand-edit, or a bumped "winner" that was
     never applied) reports match=False and shows up in mismatches, so
     main() would exit non-zero for it.
  3. Unset winner (None) is skipped entirely -- neither a row nor a
     mismatch -- matching apply_desert_winner.py's own "nothing to do yet"
     semantics for that asset.
  4. Out-of-range winner is reported as a mismatch, not a crash.
  5. A winner variant file that doesn't exist on disk is a clean
     mismatch message, not an unhandled FileNotFoundError from md5().
  6. --markdown prints the exact rows check_winners() computed.
  7. --write-winners splices that same table into a scratch winners.md
     between its AUDIT_TABLE markers, in place, leaving the rest of the
     file untouched.
"""
import contextlib
import io
import json
import shutil
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import verify_desert_winners as vdw  # noqa: E402


def _write(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)


def _run_scratch_manifest_and_get_rows():
    tmp_root = Path(tempfile.mkdtemp(prefix="verify_desert_winners_selftest_"))
    try:
        candidates_root = tmp_root / "candidates"
        _write(candidates_root / "cactus_large" / "variant_1.png", b"AAAA")
        _write(candidates_root / "cactus_large" / "variant_2.png", b"BBBB")
        _write(candidates_root / "scrub" / "variant_1.png", b"CCCC")
        _write(candidates_root / "tumbleweed" / "variant_1.png", b"DDDD")

        # cactus_large: winner=1 and the live sprite genuinely IS variant_1's bytes -- match.
        _write(tmp_root / "assets" / "legacy-art" / "cactus_large.png", b"AAAA")
        # scrub: winner=1 but the live sprite holds something else -- drift, must be flagged.
        _write(tmp_root / "assets" / "legacy-art" / "scrub.png", b"DRIFTED")
        # tumbleweed: winner=1, live sprite missing entirely.
        # (no file written -- exercises the "dest does not exist" branch)

        manifest = {
            "cactus_large": {
                "replaces": "assets/legacy-art/cactus_large.png",
                "variants": [{"path": "cactus_large/variant_1.png", "backend": "fal"},
                             {"path": "cactus_large/variant_2.png", "backend": "openrouter"}],
                "winner": 1,
            },
            "scrub": {
                "replaces": "assets/legacy-art/scrub.png",
                "variants": [{"path": "scrub/variant_1.png", "backend": "fal"}],
                "winner": 1,
            },
            "tumbleweed": {
                "replaces": "assets/legacy-art/decor/tumbleweed.png",
                "variants": [{"path": "tumbleweed/variant_1.png", "backend": "fal"}],
                "winner": 1,
            },
            "dry_shrub": {
                "replaces": "assets/legacy-art/decor/dry_shrub.png",
                "variants": [{"path": "dry_shrub/variant_1.png", "backend": "fal"}],
                "winner": None,  # not picked yet -- must be skipped, not a mismatch
            },
            "cactus_dead1": {
                "replaces": "assets/legacy-art/p2/cactus_dead1.png",
                "variants": [{"path": "cactus_dead1/variant_1.png", "backend": "fal"}],
                "winner": 9,  # out of range for a 1-variant entry
            },
            "cactus_dead2": {
                "replaces": "assets/legacy-art/p2/cactus_dead2.png",
                # winner variant file is never written to disk below --
                # exercises the "recorded winner variant does not exist" guard.
                "variants": [{"path": "cactus_dead2/variant_1.png", "backend": "fal"}],
                "winner": 1,
            },
            "backend_legend": {"fa": "fal", "or": "openrouter"},
        }
        manifest_path = candidates_root / "manifest.json"
        manifest_path.write_text(json.dumps(manifest))

        rows, mismatches = vdw.check_winners(manifest_path, tmp_root)

        by_name = {r[0]: r for r in rows}
        assert by_name["cactus_large"][4] is True, "cactus_large's winner bytes equal the live sprite -- must match"
        assert by_name["scrub"][4] is False, "scrub's live sprite drifted from its recorded winner -- must NOT match"
        assert "dry_shrub" not in by_name, "an unset (None) winner must not appear as a row at all"
        assert "tumbleweed" not in by_name, "a missing live sprite must not appear as a row at all"
        assert "cactus_dead1" not in by_name, "an out-of-range winner must not appear as a row at all"
        assert "cactus_dead2" not in by_name, "a missing winner variant source file must not appear as a row (nor raise)"

        mismatch_text = "\n".join(mismatches)
        assert "scrub" in mismatch_text, "the drifted asset must be reported in mismatches"
        assert "tumbleweed" in mismatch_text, "the missing-dest asset must be reported in mismatches"
        assert "cactus_dead1" in mismatch_text, "the out-of-range winner must be reported in mismatches"
        assert "cactus_dead2" in mismatch_text, "the missing-source-variant asset must be reported in mismatches, not crash"
        assert "cactus_large" not in mismatch_text, "a genuine match must not be reported as a mismatch"
        assert "dry_shrub" not in mismatch_text, "an unset winner must not be reported as a mismatch"
        return rows
    finally:
        shutil.rmtree(tmp_root, ignore_errors=True)


def check_match_and_mismatch_paths():
    rows = _run_scratch_manifest_and_get_rows()
    print("OK: verify_desert_winners match/mismatch/unset/missing/out-of-range/missing-source paths all report correctly")
    return rows


def check_markdown_and_write_winners_cli() -> None:
    """--markdown prints the computed rows; --write-winners splices that
    same table into a scratch winners.md between its AUDIT_TABLE markers,
    leaving everything outside the markers untouched. Drives main(argv=[...])
    directly with --manifest/--project-root flags -- no sys.argv or module
    global monkeypatching needed."""
    tmp_root = Path(tempfile.mkdtemp(prefix="verify_desert_winners_cli_selftest_"))
    try:
        candidates_root = tmp_root / "candidates"
        _write(candidates_root / "cactus_large" / "variant_1.png", b"AAAA")
        _write(tmp_root / "assets" / "legacy-art" / "cactus_large.png", b"AAAA")
        manifest = {
            "cactus_large": {
                "replaces": "assets/legacy-art/cactus_large.png",
                "variants": [{"path": "cactus_large/variant_1.png", "backend": "fal"}],
                "winner": 1,
            },
            "backend_legend": {"fa": "fal"},
        }
        manifest_path = candidates_root / "manifest.json"
        manifest_path.write_text(json.dumps(manifest))

        rows, _mismatches = vdw.check_winners(manifest_path, tmp_root)
        expected_table = vdw.render_markdown_table(rows)
        common_argv = ["--manifest", str(manifest_path), "--project-root", str(tmp_root)]

        # --markdown: prints exactly render_markdown_table()'s output.
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            rc = vdw.main([*common_argv, "--markdown"])
        assert rc == 0, f"--markdown on an all-matching manifest should exit 0, got {rc}"
        assert expected_table in buf.getvalue(), (
            f"--markdown output didn't contain the expected table.\nexpected:\n{expected_table}\ngot:\n{buf.getvalue()}")

        # --write-winners: splices that table into a scratch winners.md, preserving the rest of the file.
        # main()'s --write-winners derives this exact path from --project-root: <root>/art_reviews/desert_reskin/winners.md.
        winners_md = tmp_root / "art_reviews" / "desert_reskin" / "winners.md"
        winners_md.parent.mkdir(parents=True)
        winners_md.write_text(
            "# Title\n\nsome prose before\n\n"
            f"{vdw.AUDIT_START}\nstale old content\n{vdw.AUDIT_END}\n\n"
            "some prose after\n")
        with contextlib.redirect_stdout(io.StringIO()):
            rc = vdw.main([*common_argv, "--write-winners"])
        assert rc == 0, f"--write-winners on an all-matching manifest should exit 0, got {rc}"
        new_text = winners_md.read_text()
        assert "some prose before" in new_text and "some prose after" in new_text, (
            "--write-winners must not disturb content outside the AUDIT_TABLE markers")
        assert "stale old content" not in new_text, "--write-winners must replace the old table, not append to it"
        assert expected_table in new_text, "--write-winners must splice in the freshly-measured table"
    finally:
        shutil.rmtree(tmp_root, ignore_errors=True)

    print("OK: --markdown and --write-winners CLI paths (via main(argv=...) + --project-root, "
          "no monkeypatching) print/splice the same table check_winners() computed")


def main() -> int:
    check_match_and_mismatch_paths()
    check_markdown_and_write_winners_cli()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
