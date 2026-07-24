#!/usr/bin/env python3
"""Generate several candidate VARIANTS per desert target asset, so a winner
can be picked by eye before anything overwrites the live sprite.

This is the A/B contact-sheet sibling of generate_desert_assets.py, which
generates exactly one render per asset and writes straight into
assets/art/. This script generates N (default 4, clamp 3-6) renders per
asset instead of one, runs each candidate through the SAME chroma-key/trim/
letterbox/validate pipeline (imported from generate_desert_assets.py, not
duplicated) so every candidate already matches the exact canvas size and
transparency the live sprite needs, and writes them to a scratch
art_candidates/ tree -- never into assets/art/. Picking a winner and
copying it into assets/art/ is a separate, later step (this script only
produces the contact sheet).

The 8 desert target assets are read straight from generate_desert_assets.py
JOBS -- the exact same (name, subject prompt, dest path, canvas size, group)
tuples that already produce the shipped sprites -- so this can never drift
out of sync with the real canvas/SCALE constraints those sprites are baked
against.

Neither a bad chroma-key roll (a render whose edges keyed with too much
magenta fringe) nor a single failed API call (e.g. "no image returned by
model") aborts the whole batch: each asset retries in waves, launching
enough fresh renders to cover its shortfall, up to --max-attempts (default
3x its target variant count). If it's STILL short after that (its normal
budget exhausted) and no custom --fringe-tolerance was set, one bounded
rescue wave re-tries the shortfall with a loosened tolerance before giving
up -- generating several candidates per asset is specifically meant to
tolerate exactly this kind of bad roll.

Backends (--backend): assets can be generated through more than one image
tool, tagged per-variant in the manifest (manifest["backend_legend"] spells
out the abbreviated contact-sheet tags) so the contact sheet is a real
cross-tool A/B, not just N rolls of one model:
  - fal (default): nano-banana served straight from fal.ai (fal-ai/nano-banana)
    via a plain stdlib HTTP POST to fal.run -- no fal-client dependency.
    Reads $FAL_KEY, falling back to a FAL_KEY= line in ~/.keys (same
    file/format generate.py's own key loader uses). No key provisioned ->
    that one attempt is skipped with a clear "FAL_KEY not provisioned, vault
    one with the add-key skill" message (same skip-and-retry machinery as a
    bad chroma-key roll) instead of aborting the whole run.
  - replicate-enhance: the same fal.ai nano-banana render, then run through
    Replicate topazlabs/image-upscale (CGI model) via
    ~/.claude/skills/image-toolkit/scripts/upscale.py -- a real second
    service call using the REPLICATE_API_TOKEN (resolved by upscale.py from
    model gateway then the environment).
  - mix: cycles fal / replicate-enhance per attempt (1st, 2nd, 3rd, 4th
    attempt = fal again, ...), so one run covers both tools the user asked
    to compare ("nano fal and Replicate") without two separate invocations.

Usage:
    python3 tools/generate_desert_variants.py                      # all 8 assets, 4 variants each, fal only
    python3 tools/generate_desert_variants.py --backend replicate-enhance  # fal base + Replicate topaz-CGI upscale
    python3 tools/generate_desert_variants.py --backend mix        # cycle fal / replicate-enhance
    python3 tools/generate_desert_variants.py --variants 6         # 6 variants each
    python3 tools/generate_desert_variants.py --group cacti        # just the cacti group
    python3 tools/generate_desert_variants.py --dry-run --variants 3
        # exercise the fan-out/post-process wiring with synthetic
        # placeholders, no API key or image-toolkit skill needed

Writes, per asset:
    art_candidates/desert_reskin/<asset_name>/variant_<n>.png   (1..k, renumbered
        sequentially in discovery order -- no gaps even after retries)
    art_candidates/desert_reskin/<asset_name>/contact_sheet.png (all k candidates
        side by side on a checkerboard, numbered -- the actual A/B compare)
    art_candidates/desert_reskin/manifest.json
"""
import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from generate_desert_assets import (  # noqa: E402  (sys.path insert must run first)
    DEFAULT_GENERATE_PY,
    GROUPS,
    IMAGE_MODEL,
    JOBS,
    PROJECT_ROOT,
    STYLE,
    check_key_quality,
    chroma_key,
    fit_square,
    trim,
    validate,
)

from PIL import Image, ImageDraw  # noqa: E402

CANDIDATES_ROOT = PROJECT_ROOT / "art_candidates" / "desert_reskin"
MIN_VARIANTS, MAX_VARIANTS = 3, 6
# Per-asset retry budget: give a flaky subject (bad chroma-key rolls, a
# dropped API call) this many tries per variant it needs before giving up.
ATTEMPT_BUDGET_MULT = 3
# One bounded rescue wave, loosened to this fringe tolerance, for whatever's
# still short after the normal budget -- see check_key_quality()'s default
# 2% gate. Chosen from the real scrub failures on record (2-12% typical,
# with one 48% outlier that should still fail): loose enough to rescue a
# legitimately-fine thin silhouette, tight enough to still reject a real
# bad key.
RESCUE_FRINGE_TOLERANCE = 0.15

BACKEND_CHOICES = ("fal", "replicate-enhance", "mix")
BACKEND_LEGEND = {"fa": "fal", "re": "replicate-enhance"}  # contact-sheet tag -> full name
DEFAULT_UPSCALE_PY = Path.home() / ".claude/skills/image-toolkit/scripts/upscale.py"
FAL_KEYS_FILE = Path.home() / ".keys"  # same file/format generate.py's load_keys() reads
FAL_API_URL = "https://fal.run/fal-ai/nano-banana"

# Distinct fill colors so even --dry-run placeholders visibly differ variant
# to variant -- proves the contact sheet actually holds N different images,
# not the same placeholder copy-pasted N times.
_DRY_RUN_FILLS = [
    (120, 140, 90), (150, 130, 80), (100, 150, 110),
    (140, 110, 130), (90, 130, 150), (160, 150, 100),
]


_MIX_CYCLE = ("fal", "replicate-enhance")


def backend_for_attempt(backend: str, attempt_idx: int) -> str:
    """Resolve the CLI --backend choice to the concrete tool used for one
    attempt. 'mix' cycles through both real tools (fal, replicate-enhance) so
    a single run covers the exact comparison the user asked for -- "nano fal
    and Replicate"."""
    if backend == "mix":
        return _MIX_CYCLE[(attempt_idx - 1) % len(_MIX_CYCLE)]
    return backend


def synth_variant_placeholder(dest: Path, attempt_idx: int) -> None:
    im = Image.new("RGB", (64, 64), (255, 0, 255))
    fill = _DRY_RUN_FILLS[(attempt_idx - 1) % len(_DRY_RUN_FILLS)]
    ImageDraw.Draw(im).rectangle([16, 16, 47, 47], fill=fill)
    im.save(dest)


def _load_fal_key() -> str | None:
    """$FAL_KEY, falling back to a FAL_KEY= line in ~/.keys -- the same
    file/format generate.py's own key loader reads, so vaulting one key file
    (via the add-key skill) covers the fal backend here."""
    key = os.environ.get("FAL_KEY")
    if key:
        return key
    if not FAL_KEYS_FILE.exists():
        return None
    for line in FAL_KEYS_FILE.read_text().splitlines():
        line = line.strip()
        if line.startswith("FAL_KEY="):
            return line.split("=", 1)[1].strip().strip('"').strip("'")
    return None


def fal_generate(prompt: str, dest: Path) -> str | None:
    """POST prompt to fal.ai's nano-banana (Gemini image) endpoint and save
    the first returned image to dest. Returns an error string on failure,
    None on success -- same (error_or_None) contract every other backend
    branch in run_attempt() uses, so a fal failure is skipped-and-retried
    exactly like a bad chroma-key roll rather than aborting the batch.
    Plain stdlib urllib, no fal-client dependency -- fal.ai's synchronous
    REST API for this model is one POST."""
    key = _load_fal_key()
    if not key:
        return ("FAL_KEY not provisioned -- vault one with the add-key skill "
                 "(`fal`) or set $FAL_KEY, then retry --backend fal")
    req = urllib.request.Request(
        FAL_API_URL,
        data=json.dumps({"prompt": prompt}).encode("utf-8"),
        headers={"Authorization": f"Key {key}", "Content-Type": "application/json"},
        method="POST")
    try:
        with urllib.request.urlopen(req, timeout=300) as resp:
            body = json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        return f"fal.ai HTTP {e.code}: {e.read().decode('utf-8', errors='replace')[:500]}"
    except urllib.error.URLError as e:
        return f"fal.ai request failed: {e}"
    images = body.get("images") or []
    url = images[0].get("url") if images else None
    if not url:
        return f"fal.ai returned no image: {json.dumps(body)[:500]}"
    try:
        with urllib.request.urlopen(url, timeout=120) as resp:
            dest.write_bytes(resp.read())
    except urllib.error.URLError as e:
        return f"failed to download fal.ai image: {e}"
    return None


def run_attempt(name: str, prompt: str, attempt_idx: int, backend: str, raw_dir: Path,
                 generate_py: Path, upscale_py: Path, model: str, dry_run: bool):
    """Blocking: runs one attempt's full backend pipeline. The base render
    always comes from fal.ai's nano-banana; 'replicate-enhance' then pipes it
    through a Replicate topaz-CGI upscale pass. Returns (attempt_idx,
    raw_path_or_None, backend, error_or_None). Meant to run inside a thread
    pool so several attempts -- even multi-stage ones -- proceed concurrently.
    generate_py/model are vestigial (an earlier subprocess base render used
    them); # ponytail: left in the signature so the caller plumbing stays a
    no-op diff, drop them if this ever needs a real cleanup."""
    raw_path = raw_dir / f"{name}_a{attempt_idx}.png"
    if dry_run:
        synth_variant_placeholder(raw_path, attempt_idx)
        return attempt_idx, raw_path, backend, None

    err = fal_generate(prompt, raw_path)
    if err is not None:
        return attempt_idx, None, backend, err

    if backend == "replicate-enhance":
        enhanced_path = raw_dir / f"{name}_a{attempt_idx}_enh.png"
        cmd2 = [sys.executable, str(upscale_py), str(raw_path), "-o", str(enhanced_path),
                "--format", "png", "--model", "CGI", "--factor", "2x"]
        r2 = subprocess.run(cmd2, capture_output=True, text=True)
        if r2.returncode != 0 or not enhanced_path.exists():
            return attempt_idx, None, backend, f"replicate enhance failed (exit {r2.returncode}): {(r2.stdout or r2.stderr or '')[-500:]}"
        raw_path = enhanced_path

    return attempt_idx, raw_path, backend, None


def post_process(raw_path: Path, size: int, fringe_tolerance: float | None = None) -> Image.Image:
    """Run one raw render through chroma-key -> QC -> trim -> letterbox ->
    validate. Raises ValueError on a bad roll -- callers decide whether to
    retry, never let one bad roll kill the batch. fringe_tolerance overrides
    check_key_quality()'s default 2% max-fringe-fraction gate for subjects
    (e.g. thin, wispy silhouettes) whose anti-aliased edges legitimately
    read as magenta-adjacent without a bad key -- default None keeps the
    strict upstream gate."""
    im, key_color = chroma_key(Image.open(raw_path))
    if fringe_tolerance is None:
        check_key_quality(im, key_color, raw_path)
    else:
        check_key_quality(im, key_color, raw_path, max_fringe_frac=fringe_tolerance)
    im = fit_square(trim(im), size)
    validate(im, raw_path, size)
    return im


def save_contact_sheet(images_backends: list[tuple[Image.Image, str]], dest: Path) -> None:
    """One horizontal strip per asset, each candidate on a light/dark
    checkerboard (so transparency reads) with its variant number AND
    generating backend labeled underneath -- the actual A/B comparison a
    reviewer needs instead of opening N separate PNGs by hand."""
    if not images_backends:
        return
    images = [im for im, _b in images_backends]
    cell = max(im.width for im in images)
    label_h = 18
    pad = 6
    sheet = Image.new("RGB", (len(images) * (cell + pad) + pad, cell + label_h + 2 * pad), (40, 40, 40))
    draw = ImageDraw.Draw(sheet)
    for i, (im, backend) in enumerate(images_backends):
        x0 = pad + i * (cell + pad)
        y0 = pad
        # checkerboard so alpha=0 vs a white/grey subject are distinguishable
        sq = 8
        for cy in range(0, cell, sq):
            for cx in range(0, cell, sq):
                shade = (210, 210, 210) if (cx // sq + cy // sq) % 2 == 0 else (170, 170, 170)
                draw.rectangle([x0 + cx, y0 + cy, x0 + cx + sq - 1, y0 + cy + sq - 1], fill=shade)
        ox = x0 + (cell - im.width) // 2
        oy = y0 + (cell - im.height) // 2
        sheet.paste(im, (ox, oy), im)
        # Abbreviated tag ("fa"/"re") -- the full backend name overflows
        # into the neighboring cell on the narrowest (72px) canvases.
        draw.text((x0 + 2, y0 + cell + 2), f"{i + 1} {backend[:2]}", fill=(255, 255, 0))
    sheet.save(dest)


class AssetState:
    """Per-asset retry bookkeeping for one wave-based generate loop: how many
    QC-passed survivors it has, how many attempts it's burned, and the next
    fresh attempt index to render into (never reused, so a failed raw render
    from an earlier wave can't collide with a later retry)."""

    def __init__(self, name, subject, dest, size, group, target, max_attempts):
        self.name, self.subject, self.dest, self.size, self.group = name, subject, dest, size, group
        self.target = target
        self.max_attempts = max_attempts
        self.attempts = 0
        self.next_attempt_idx = 1
        # attempt_idx -> (image, backend), insertion order = discovery order
        self.survivors: dict[int, tuple[Image.Image, str]] = {}
        self.rescued = False
        self.skips: list[dict] = []  # {"attempt", "backend", "reason"} for every failed attempt

    @property
    def deficit(self) -> int:
        return max(0, self.target - len(self.survivors))

    @property
    def attempts_left(self) -> int:
        return max(0, self.max_attempts - self.attempts)

    def wave_size(self) -> int:
        return min(self.deficit, self.attempts_left)


def _run_wave(states, requested_backend, raw_dir, generate_py, upscale_py, model, dry_run,
              fringe_tolerance, per_state_take) -> None:
    """Launch per_state_take[state] attempts for each given state concurrently
    (a thread pool, since a replicate-enhance attempt is itself two
    sequential subprocess calls), post-process each as it completes, and
    record survivors straight onto the state. Mutates states in place."""
    jobs = []  # (state, attempt_idx, resolved_backend)
    for state in states:
        take = per_state_take[state.name]
        for _ in range(take):
            idx = state.next_attempt_idx
            state.next_attempt_idx += 1
            state.attempts += 1
            jobs.append((state, idx, backend_for_attempt(requested_backend, idx)))
    if not jobs:
        return
    print(f"  launching {len(jobs)} render(s): "
          f"{', '.join(sorted(f'{s.name}/{b}' for s, _i, b in jobs))}...")
    with ThreadPoolExecutor(max_workers=max(1, len(jobs))) as pool:
        futures = [pool.submit(run_attempt, state.name,
                                f"{state.subject} {GROUPS[state.group]['consistency']} {STYLE}",
                                idx, resolved, raw_dir, generate_py, upscale_py, model, dry_run)
                   for state, idx, resolved in jobs]
        # jobs[i] and futures[i] correspond positionally (both built from the
        # same ordered iteration) -- zip rather than a (idx, backend) dict
        # key, since attempt_idx is only unique WITHIN one asset and two
        # different assets in the same wave can both be on attempt 1.
        results = [f.result() for f in futures]
    for (state, idx, resolved), (r_idx, raw_path, r_backend, err) in zip(jobs, results):
        assert idx == r_idx and resolved == r_backend  # positional correspondence held
        if err is not None:
            print(f"  SKIPPED {state.name} attempt {idx} [{resolved}]: {err}", file=sys.stderr)
            state.skips.append({"attempt": idx, "backend": resolved, "reason": str(err)[:300]})
            continue
        try:
            im = post_process(raw_path, state.size, fringe_tolerance)
        except ValueError as exc:
            print(f"  SKIPPED {state.name} attempt {idx} [{resolved}]: {exc}", file=sys.stderr)
            state.skips.append({"attempt": idx, "backend": resolved, "reason": str(exc)[:300]})
            continue
        state.survivors[idx] = (im, resolved)
        print(f"  {state.name} attempt {idx} [{resolved}]: OK ({im.width}x{im.height})")


def run_generation(jobs, n_variants, max_attempts, raw_dir, out_root,
                    generate_py, model, dry_run, fringe_tolerance=None,
                    backend="fal", upscale_py=None) -> dict:
    upscale_py = upscale_py or DEFAULT_UPSCALE_PY
    states = {name: AssetState(name, subject, dest, size, group, n_variants, max_attempts)
              for name, subject, dest, size, group in jobs}

    wave_num = 0
    while True:
        pending = [s for s in states.values() if s.wave_size() > 0]
        if not pending:
            break
        wave_num += 1
        print(f"wave {wave_num}:")
        _run_wave(pending, backend, raw_dir, generate_py, upscale_py, model, dry_run,
                  fringe_tolerance, {s.name: s.wave_size() for s in pending})

    # One bounded rescue wave for whatever's still short, with a loosened
    # fringe tolerance -- but only if the caller didn't already pass a
    # custom tolerance (that already applied to every attempt above).
    if fringe_tolerance is None:
        short = [s for s in states.values() if s.deficit > 0]
        if short:
            print(f"rescue wave (fringe-tolerance={RESCUE_FRINGE_TOLERANCE}) for: "
                  f"{', '.join(s.name for s in short)}")
            for s in short:
                s.rescued = True
            _run_wave(short, backend, raw_dir, generate_py, upscale_py, model, dry_run,
                      RESCUE_FRINGE_TOLERANCE, {s.name: s.deficit for s in short})

    manifest = {}
    for state in states.values():
        # Renumber survivors 1..k in discovery order -- reviewers get a clean
        # variant_1.png, variant_2.png, ... contact sheet, not gappy raw
        # attempt indices (a retried asset might have survived on attempts
        # 4, 7, 8).
        images_backends = list(state.survivors.values())
        variant_entries = []
        for n, (im, backend_used) in enumerate(images_backends, start=1):
            dest_path = out_root / state.name / f"variant_{n}.png"
            dest_path.parent.mkdir(parents=True, exist_ok=True)
            im.save(dest_path)
            variant_entries.append({"path": str(dest_path.relative_to(out_root)), "backend": backend_used})
        contact_sheet_rel = None
        if images_backends:
            sheet_path = out_root / state.name / "contact_sheet.png"
            save_contact_sheet(images_backends, sheet_path)
            contact_sheet_rel = str(sheet_path.relative_to(out_root))
        entry = {
            "replaces": f"assets/art/{state.dest}",
            "canvas_size": state.size,
            "group": state.group,
            "prompt": f"{state.subject} {GROUPS[state.group]['consistency']} {STYLE}",
            "variants": variant_entries,
            "contact_sheet": contact_sheet_rel,
            "attempts_used": state.attempts,
            "skips": state.skips,
            "winner": None,
        }
        if len(variant_entries) < state.target:
            entry["note"] = (f"only {len(variant_entries)}/{state.target} candidates survived "
                              f"after {state.attempts} attempt(s), including a "
                              f"{RESCUE_FRINGE_TOLERANCE}-fringe-tolerance rescue wave -- "
                              f"see stderr for the per-attempt skip reasons, or rerun this one "
                              f"asset with an even looser --fringe-tolerance if it's a "
                              f"thin/wispy silhouette")
        elif state.rescued:
            entry["note"] = (f"reached its target only via the {RESCUE_FRINGE_TOLERANCE}-"
                              f"fringe-tolerance rescue wave -- some variants here have looser "
                              f"edge QC than the strict 2% default")
        manifest[state.name] = entry
    # Top-level, not per-asset -- BACKEND_LEGEND spells out the abbreviated
    # contact-sheet tags ("fa"/"re") so a reviewer doesn't need to read the
    # script to know what they mean.
    manifest["backend_legend"] = BACKEND_LEGEND
    return manifest


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out-dir", default=str(CANDIDATES_ROOT),
                     help="candidate root to write variant PNGs + manifest.json into "
                          "(default: art_candidates/desert_reskin, never assets/art)")
    ap.add_argument("--raw-dir", default=None,
                     help="scratch dir for raw pre-chroma-key renders (default: a throwaway temp dir)")
    ap.add_argument("--variants", type=int, default=4,
                     help=f"candidates per asset, clamped to [{MIN_VARIANTS}, {MAX_VARIANTS}] (default: 4)")
    ap.add_argument("--max-attempts", type=int, default=None,
                     help=f"NORMAL retry budget per asset before the automatic rescue wave kicks "
                          f"in (default: variants x {ATTEMPT_BUDGET_MULT}) -- not a hard ceiling: "
                          f"an asset still short after this many attempts gets one more bounded "
                          f"rescue wave (see --fringe-tolerance), so attempts_used in the "
                          f"manifest can exceed this number by up to --variants")
    ap.add_argument("--fringe-tolerance", type=float, default=None,
                     help="override check_key_quality()'s default 2%% max-magenta-fringe gate "
                          "for every attempt (e.g. 0.12); default None keeps the strict gate "
                          "and lets the automatic rescue wave (see RESCUE_FRINGE_TOLERANCE) "
                          "handle a shortfall instead")
    ap.add_argument("--backend", choices=BACKEND_CHOICES, default="fal",
                     help="image tool(s) to generate through (default: fal/nano-banana "
                          "only). 'fal' calls fal.ai's nano-banana endpoint directly (needs "
                          "$FAL_KEY or a FAL_KEY= line in ~/.keys -- errors clearly per-attempt "
                          "if missing, see module docstring). 'replicate-enhance' takes the fal "
                          "base render and pipes it through a Replicate topaz-CGI upscale pass. "
                          "'mix' cycles fal and replicate-enhance per attempt so the contact "
                          "sheet is a real 2-tool A/B")
    ap.add_argument("--group", choices=sorted(GROUPS), default=None,
                     help="only generate variants for this one asset group (default: all)")
    ap.add_argument("--generate-py", default=None,
                     help="path to the image-toolkit skill's generate.py "
                          "(default: $IMAGE_TOOLKIT_GENERATE_PY if set, else "
                          "~/.claude/skills/image-toolkit/scripts/generate.py)")
    ap.add_argument("--upscale-py", default=str(DEFAULT_UPSCALE_PY),
                     help="path to the image-toolkit skill's upscale.py, used by "
                          "--backend replicate-enhance/mix")
    ap.add_argument("--model", default=IMAGE_MODEL,
                     help=f"image model slug (default: {IMAGE_MODEL}). # ponytail: vestigial "
                          f"since the base render is now the hardcoded fal-ai/nano-banana "
                          f"endpoint; kept so the CLI stays stable")
    ap.add_argument("--keep-raw", action="store_true",
                     help="keep the raw pre-chroma-key renders instead of deleting the throwaway raw-dir")
    ap.add_argument("--dry-run", action="store_true",
                     help="synthesize placeholders instead of real renders; no API key needed")
    args = ap.parse_args()

    n_variants = max(MIN_VARIANTS, min(MAX_VARIANTS, args.variants))
    max_attempts = args.max_attempts or n_variants * ATTEMPT_BUDGET_MULT

    out_root = Path(args.out_dir)
    # Explicit env-var honor here (not just via the imported default), so
    # $IMAGE_TOOLKIT_GENERATE_PY works whether or not generate_desert_assets
    # happened to resolve it first.
    generate_py = Path(args.generate_py or os.environ.get("IMAGE_TOOLKIT_GENERATE_PY") or DEFAULT_GENERATE_PY)
    upscale_py = Path(args.upscale_py)
    raw_dir = Path(args.raw_dir) if args.raw_dir else Path(tempfile.mkdtemp(prefix="desert_variants_raw_"))
    raw_dir.mkdir(parents=True, exist_ok=True)
    is_temp_raw_dir = args.raw_dir is None

    # ponytail: no generate.py existence check any more -- every backend's base
    # render comes from fal.ai directly, generate.py is no longer invoked here.
    if not args.dry_run and args.backend in ("replicate-enhance", "mix") and not upscale_py.exists():
        print(f"missing {upscale_py} -- is the image-toolkit skill installed? "
              f"(pass --upscale-py)", file=sys.stderr)
        return 1

    jobs = [j for j in JOBS if args.group is None or j[4] == args.group]
    print(f"generating up to {n_variants} candidate variant(s) each (max {max_attempts} attempts/asset, "
          f"backend={args.backend}) for {len(jobs)} desert asset(s) ({', '.join(j[0] for j in jobs)})"
          f"{' (dry-run)' if args.dry_run else ''}...")

    manifest = run_generation(jobs, n_variants, max_attempts, raw_dir, out_root,
                               generate_py, args.model, args.dry_run,
                               fringe_tolerance=args.fringe_tolerance,
                               backend=args.backend, upscale_py=upscale_py)

    short = {name: e for name, e in manifest.items()
             if name != "backend_legend" and len(e["variants"]) < n_variants}
    if short:
        print(f"{len(short)}/{len(jobs)} asset(s) fell short of {n_variants} candidates even after "
              f"the retry + rescue budget: {list(short)}", file=sys.stderr)

    manifest_path = out_root / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"wrote {manifest_path}")

    if is_temp_raw_dir and not args.keep_raw:
        shutil.rmtree(raw_dir, ignore_errors=True)

    print(f"done. Review the variants per asset under {out_root}, "
          f"set manifest.json's \"winner\" for each, then copy the chosen "
          f"variant_<n>.png over its \"replaces\" path in assets/art/ and re-run "
          f"`godot --headless --path . --import`.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
