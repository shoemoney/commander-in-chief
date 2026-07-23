#!/usr/bin/env python3
"""Minimal self-check for generate_desert_variants.py. Not a framework
suite -- run directly:

    python3 tools/test_generate_desert_variants.py

Four checks:
  1. CLI smoke test: a real --dry-run subprocess call, asserting the
     manifest schema (incl. the backend_legend), variant counts, and that
     contact_sheet.png landed.
  2. Retry-path check: imports the module directly and monkeypatches
     post_process() to simulate a flaky renderer (fails N times, then
     succeeds; or always fails) so the wave/retry loop AND rescue wave in
     run_generation() are exercised without a real API key or Godot.
  3. Mix-backend check: --dry-run --backend mix, asserting per-variant
     backend tags actually cycle openrouter/replicate-enhance/fal (not just
     that the default single-backend path works).
  4. Replicate-enhance pipeline check: monkeypatches subprocess.run to fake
     two successful stage calls and asserts run_attempt() for
     backend="replicate-enhance" actually invokes generate.py THEN
     upscale.py in sequence and returns the enhanced output -- covers the
     two-stage pipeline structurally without spending a real API call.
  5. fal backend check: monkeypatches _load_fal_key()/fal_generate() and
     asserts (a) a missing FAL_KEY produces a clear, actionable error
     instead of a confusing network failure, and (b) a provisioned key
     calls fal_generate() directly and never falls through to the
     openrouter subprocess pipeline the other backends use.
"""
import json
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import generate_desert_variants as gdv  # noqa: E402

SCRIPT = Path(__file__).resolve().parent / "generate_desert_variants.py"


def check_cli_smoke() -> None:
    out_dir = Path(tempfile.mkdtemp(prefix="desert_variants_selftest_"))
    try:
        result = subprocess.run(
            [sys.executable, str(SCRIPT), "--dry-run", "--variants", "3",
             "--group", "cacti", "--out-dir", str(out_dir)],
            capture_output=True, text=True)
        assert result.returncode == 0, f"script exited {result.returncode}:\n{result.stdout}\n{result.stderr}"

        manifest_path = out_dir / "manifest.json"
        assert manifest_path.exists(), f"manifest.json missing under {out_dir}"
        manifest = json.loads(manifest_path.read_text())

        assert manifest.get("backend_legend") == gdv.BACKEND_LEGEND, (
            f"manifest should carry the backend_legend so abbreviated tags are self-explanatory, "
            f"got {manifest.get('backend_legend')}")
        asset_names = {k for k in manifest if k != "backend_legend"}
        assert asset_names == {"cactus_large", "cactus_small"}, (
            f"--group cacti should only manifest cacti assets, got {asset_names}")

        for name in asset_names:
            entry = manifest[name]
            for key in ("replaces", "canvas_size", "group", "prompt", "variants",
                        "contact_sheet", "attempts_used", "skips", "winner"):
                assert key in entry, f"{name}: manifest entry missing {key!r} key"
            assert entry["winner"] is None, f"{name}: winner should start unset"
            assert entry["skips"] == [], f"{name}: a clean dry-run should have no skips, got {entry['skips']}"
            assert len(entry["variants"]) == 3, (
                f"{name}: --variants 3 dry-run (always QC-clean) should yield exactly 3 candidates, "
                f"got {len(entry['variants'])}")
            paths = [v["path"] for v in entry["variants"]]
            assert paths == [f"{name}/variant_1.png", f"{name}/variant_2.png", f"{name}/variant_3.png"], (
                f"{name}: variants should be sequentially renumbered 1..3, got {paths}")
            for v in entry["variants"]:
                assert v["backend"] == "openrouter", (
                    f"{name}: default --backend run should tag every variant 'openrouter', got {v}")
            assert entry["contact_sheet"] == f"{name}/contact_sheet.png", (
                f"{name}: unexpected contact_sheet path {entry['contact_sheet']!r}")
            for rel in paths + [entry["contact_sheet"]]:
                variant_path = out_dir / rel
                assert variant_path.exists(), f"{name}: manifest lists {rel} but file is missing"

        print(f"OK: CLI smoke test (manifest schema + backend_legend + variant renumbering + "
              f"contact sheets, {len(asset_names)} assets, 3 variants each)")
    finally:
        shutil.rmtree(out_dir, ignore_errors=True)


def check_mix_backend_dry_run() -> None:
    out_dir = Path(tempfile.mkdtemp(prefix="desert_variants_mix_selftest_"))
    try:
        result = subprocess.run(
            [sys.executable, str(SCRIPT), "--dry-run", "--variants", "4",
             "--group", "cacti", "--backend", "mix", "--out-dir", str(out_dir)],
            capture_output=True, text=True)
        assert result.returncode == 0, f"script exited {result.returncode}:\n{result.stdout}\n{result.stderr}"
        manifest = json.loads((out_dir / "manifest.json").read_text())
        backends = [v["backend"] for v in manifest["cactus_large"]["variants"]]
        assert backends == ["openrouter", "replicate-enhance", "fal", "openrouter"], (
            f"--backend mix should cycle openrouter/replicate-enhance/fal per attempt, got {backends}")
        print("OK: --backend mix dry-run (per-variant backend tags actually cycle all three tools)")
    finally:
        shutil.rmtree(out_dir, ignore_errors=True)


def check_retry_path() -> None:
    out_dir = Path(tempfile.mkdtemp(prefix="desert_variants_retry_selftest_"))
    raw_dir = Path(tempfile.mkdtemp(prefix="desert_variants_retry_raw_"))
    real_post_process = gdv.post_process
    # flaky_asset fails its first 2 attempts then succeeds every attempt
    # after -- the wave loop should still land it at the full target.
    # dead_asset never succeeds -- the wave loop must stop at max_attempts,
    # not spin forever, and the manifest must say so.
    fail_budget = {"flaky_asset": 2}

    def fake_post_process(raw_path, size, fringe_tolerance=None):
        name = raw_path.stem.rsplit("_a", 1)[0]
        if name == "dead_asset":
            raise ValueError("simulated permanent bad roll")
        if name == "flaky_asset" and fail_budget["flaky_asset"] > 0:
            fail_budget["flaky_asset"] -= 1
            raise ValueError("simulated transient bad roll")
        from PIL import Image
        return Image.new("RGBA", (size, size), (0, 128, 0, 255))

    jobs = [
        ("flaky_asset", "subject", "flaky_asset.png", 32, "cacti"),
        ("dead_asset", "subject", "dead_asset.png", 32, "cacti"),
    ]
    gdv.post_process = fake_post_process
    try:
        manifest = gdv.run_generation(jobs, n_variants=3, max_attempts=9,
                                       raw_dir=raw_dir, out_root=out_dir,
                                       generate_py=Path("/nonexistent"), model="x", dry_run=True)
    finally:
        gdv.post_process = real_post_process
        shutil.rmtree(raw_dir, ignore_errors=True)
        shutil.rmtree(out_dir, ignore_errors=True)

    flaky = manifest["flaky_asset"]
    assert len(flaky["variants"]) == 3, (
        f"flaky_asset should recover to its full target via retries, got {flaky['variants']}")
    assert flaky["attempts_used"] == 5, (  # 2 failures + 3 successes
        f"flaky_asset should burn exactly 5 attempts (2 failed + 3 succeeded), got {flaky['attempts_used']}")
    assert len(flaky["skips"]) == 2, f"flaky_asset should record its 2 skip reasons, got {flaky['skips']}"
    assert "note" not in flaky, "flaky_asset reached its target -- should carry no shortfall note"

    dead = manifest["dead_asset"]
    assert dead["variants"] == [], f"dead_asset should never recover, got {dead['variants']}"
    # 9 (normal retry budget) + 3 (bounded rescue wave, deficit-sized) = 12 -- the
    # rescue wave still can't save a permanently-failing subject, but proves it
    # ran and then correctly stopped rather than looping forever.
    assert dead["attempts_used"] == 12, f"dead_asset should exhaust budget + rescue wave (12), got {dead['attempts_used']}"
    assert len(dead["skips"]) == 12, f"dead_asset should record all 12 skip reasons, got {len(dead['skips'])}"
    assert "note" in dead, "dead_asset should carry a shortfall note explaining the 0 survivors"

    print("OK: retry-path check (flaky asset recovers via retries; permanently-failing "
          "asset stops after its attempt budget + rescue wave with a shortfall note + skip log, "
          "doesn't hang)")


def check_replicate_enhance_pipeline() -> None:
    """Doesn't spend a real Replicate call -- monkeypatches subprocess.run
    to fake two successful stage calls and asserts run_attempt() actually
    chains generate.py -> upscale.py in that order for backend=
    'replicate-enhance', rather than only exercising this path via the
    dry-run short-circuit (which skips both subprocess calls entirely)."""
    raw_dir = Path(tempfile.mkdtemp(prefix="desert_variants_enhance_selftest_"))
    calls = []
    real_run = subprocess.run

    def fake_run(cmd, **kwargs):
        calls.append(cmd)
        # cmd is [sys.executable, script_path, ...]; the output path is
        # whatever followed -o for both generate.py and upscale.py calls.
        out_path = Path(cmd[cmd.index("-o") + 1])
        out_path.write_bytes(b"\x89PNG\r\n\x1a\nfake")
        return subprocess.CompletedProcess(cmd, 0, stdout="", stderr="")

    gdv.subprocess.run = fake_run
    try:
        attempt_idx, raw_path, backend, err = gdv.run_attempt(
            "cactus_large", "a prompt", 1, "replicate-enhance", raw_dir,
            generate_py=Path("/fake/generate.py"), upscale_py=Path("/fake/upscale.py"),
            model="x", dry_run=False)
    finally:
        gdv.subprocess.run = real_run
        shutil.rmtree(raw_dir, ignore_errors=True)

    assert err is None, f"expected the faked two-stage pipeline to succeed, got error: {err}"
    assert backend == "replicate-enhance"
    assert len(calls) == 2, f"replicate-enhance should call generate.py THEN upscale.py (2 calls), got {len(calls)}"
    assert "generate.py" not in str(calls[0]) or "/fake/generate.py" in calls[0], calls[0]
    assert "/fake/generate.py" in calls[0], f"stage 1 should invoke generate.py, got {calls[0]}"
    assert "/fake/upscale.py" in calls[1], f"stage 2 should invoke upscale.py, got {calls[1]}"
    assert "--model" in calls[1] and "CGI" in calls[1], f"stage 2 should request the CGI enhance model, got {calls[1]}"
    assert raw_path.name.endswith("_enh.png"), f"final path should be the enhanced output, got {raw_path}"

    print("OK: replicate-enhance pipeline check (generate.py -> upscale.py chained correctly)")


def check_fal_backend() -> None:
    raw_dir = Path(tempfile.mkdtemp(prefix="desert_variants_fal_selftest_"))
    real_load_key = gdv._load_fal_key
    real_fal_generate = gdv.fal_generate
    try:
        # (a) no key provisioned -> a clear, actionable error (not a raw
        # network/HTTP exception), and no raw_path produced
        gdv._load_fal_key = lambda: None
        _idx, raw_path, backend, err = gdv.run_attempt(
            "cactus_large", "a prompt", 1, "fal", raw_dir,
            generate_py=Path("/fake/generate.py"), upscale_py=Path("/fake/upscale.py"),
            model="x", dry_run=False)
        assert raw_path is None and backend == "fal"
        assert err and "FAL_KEY" in err, f"expected a clear FAL_KEY error, got {err!r}"

        # (b) key present -> run_attempt() calls fal_generate() directly,
        # never the openrouter subprocess pipeline the other backends use
        gdv._load_fal_key = lambda: "fake-key"
        calls = []

        def fake_fal_generate(prompt, dest):
            calls.append((prompt, dest))
            dest.write_bytes(b"\x89PNG\r\n\x1a\nfake")
            return None

        gdv.fal_generate = fake_fal_generate
        _idx, raw_path, backend, err = gdv.run_attempt(
            "cactus_large", "a prompt", 2, "fal", raw_dir,
            generate_py=Path("/fake/generate.py"), upscale_py=Path("/fake/upscale.py"),
            model="x", dry_run=False)
        assert err is None and raw_path is not None and raw_path.exists(), (err, raw_path)
        assert len(calls) == 1, f"fal backend should call fal_generate() exactly once, got {calls}"
    finally:
        gdv._load_fal_key = real_load_key
        gdv.fal_generate = real_fal_generate
        shutil.rmtree(raw_dir, ignore_errors=True)

    print("OK: --backend fal (missing-FAL_KEY gives a clear error; provisioned-key path "
          "calls fal_generate() directly, never the openrouter subprocess pipeline)")


def main() -> int:
    check_cli_smoke()
    check_mix_backend_dry_run()
    check_retry_path()
    check_replicate_enhance_pipeline()
    check_fal_backend()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
