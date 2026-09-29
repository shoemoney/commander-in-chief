"""Consolidate pinned local deliverables for review, never upload or launch them."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import zipfile

from verify_store_copy import validate as validate_copy

ROOT = Path(__file__).resolve().parents[1]
BUILDS = Path("build/steam-ready.jqZpJ9/candidates")
ART = Path("build/steam-hero.KRzhYW/steam-art-handoff")
SHOTS = Path("build/steam-current.pKhThM/handoff")
TRAILER = Path("build/trailer-current.YSYUiS/draft")


def sha(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def safe_member(base, name):
    relative = Path(name)
    path = base / relative
    if relative.is_absolute() or ".." in relative.parts or not path.resolve().is_relative_to(base.resolve()):
        raise ValueError(f"Unsafe artifact path: {name}")
    if not path.is_file() or path.is_symlink():
        raise ValueError(f"Missing/nonregular artifact: {path}")
    return path


def require_hash(path, expected):
    if sha(path) != expected:
        raise ValueError(f"Artifact checksum differs from its source receipt: {path}")


def verify(output):
    """Check copied files and ZIP bytes against the handoff manifest; no extraction."""
    manifest_path = output / "manifest.json"
    rows = json.loads(manifest_path.read_text())["files"]
    names = [row["file"] for row in rows]
    if len(names) != len(set(names)):
        raise ValueError("Duplicate manifest entries")
    expected = set(names) | {"manifest.json"}
    actual = {p.relative_to(output).as_posix() for p in output.rglob("*") if p.is_file()}
    if actual != expected:
        raise ValueError("Folder contents differ from manifest")
    with zipfile.ZipFile(output.with_suffix(".zip")) as archive:
        if len(archive.namelist()) != len(expected) or set(archive.namelist()) != expected:
            raise ValueError("Archive contents differ from manifest")
        if archive.read("manifest.json") != manifest_path.read_bytes():
            raise ValueError("Archived manifest differs from folder manifest")
        for row in rows:
            path = safe_member(output, row["file"])
            require_hash(path, row["sha256"])
            with archive.open(row["file"]) as stream:
                digest = hashlib.file_digest(stream, "sha256").hexdigest()
            if digest != row["sha256"] or path.stat().st_size != row["bytes"]:
                raise ValueError(f"Archive bytes/size mismatch: {row['file']}")
    print(f"RELEASE REVIEW VERIFIED: {len(rows)} receipted files; folder and ZIP bytes match")


def plan(root):
    """Validate recorded artifact bytes before creating any destination."""
    validate_copy(root / "docs/steam-store")
    selected = {}

    def add(path, destination):
        if destination in selected:
            raise ValueError(f"Duplicate destination: {destination}")
        selected[destination] = (path, sha(path))

    builds = json.loads((root / BUILDS / "manifest.json").read_text())
    if {r["platform"] for r in builds["exports"]} != {"macos", "linux", "windows"}:
        raise ValueError("Expected all three desktop candidate records")
    for record in builds["exports"]:
        for name, expected in record["files"].items():
            path = safe_member(root / BUILDS / record["platform"], name)
            require_hash(path, expected)
            add(path, f"builds/{record['platform']}/{name}")
    add(root / BUILDS / "manifest.json", "builds/source-manifest.json")

    art = json.loads((root / ART / "manifest.json").read_text())
    if len(art["assets"]) != 8:
        raise ValueError("Expected eight art assets")
    for record in art["assets"]:
        for field, hash_field in [("file", "sha256"), ("source_file", "source_sha256")]:
            path = safe_member(root / ART, record[field])
            require_hash(path, record[hash_field])
            add(path, "store-art/" + record[field])
    add(root / ART / "manifest.json", "store-art/source-manifest.json")

    shots = json.loads((root / SHOTS / "manifest.json").read_text())
    if len(shots["screenshots"]) != 5:
        raise ValueError("Expected five gameplay screenshots")
    for record in shots["screenshots"]:
        require_hash(safe_member(root / SHOTS, record["file"]), record["sha256"])
    # Preserve selected takes' complete raw/display frames and replay evidence.
    for path in sorted((root / SHOTS).rglob("*")):
        if path.is_file() and not any(p.startswith(".") for p in path.relative_to(root / SHOTS).parts):
            add(safe_member(root / SHOTS, path.relative_to(root / SHOTS)),
                "screenshots/" + path.relative_to(root / SHOTS).as_posix())

    trailer = json.loads((root / TRAILER / "manifest.json").read_text())
    require_hash(root / TRAILER / "CommanderInChief-gameplay-draft.mp4", trailer["sha256"])
    for name in ["CommanderInChief-gameplay-draft.mp4", "poster.png", "manifest.json", "cut-list.json"]:
        add(safe_member(root / TRAILER, name), "trailer/" + name)

    for path in sorted((root / "docs/steam-store").iterdir()):
        if path.is_file() and not path.name.startswith("."):
            add(path, "docs/steam-store/" + path.name)
    for name in ["release-readiness", "steam-candidate-validation", "steam-gameplay-screenshots",
                 "gameplay-trailer-draft", "movie-capture-validation", "steam-hero-validation",
                 "blender-media-validation", "godotsteam_api_version", "steam_cloud_paths",
                 "ten-item-acceptance", "ready-feedback"]:
        add(root / "docs" / (name + ".md"), "docs/" + name + ".md")
    for name in ["ASSETS.md", "NOTICE.md"]:
        add(root / name, name)
    return selected


def assemble(root, output):
    archive_path = output.with_suffix(".zip")
    if output.exists() or archive_path.exists():
        raise ValueError("Destination or archive already exists; choose a new destination")
    selected = plan(root)
    output.mkdir()
    records = []
    for destination, (source, expected) in selected.items():
        target = output / destination
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
        require_hash(target, expected)
        records.append({"file": destination, "source": source.relative_to(root).as_posix(),
                        "sha256": expected, "bytes": target.stat().st_size})
    start = """# Release review package — NOT approved for launch

This package collects current local deliverables; it does not launch a game,
initialize Steam, upload files, grant asset rights or establish platform approval.

## Files to review

- `builds/`: Steam module candidates for macOS, Windows and Linux. Keep each
  Windows/Linux executable, game pack and Steam library together.
- `store-art/`: eight store/library PNGs and their packed Blender source files.
- `screenshots/`: five actual-gameplay PNGs; `index.html` previews them. The
  evidence folder retains the selected takes' raw/display frames and replays.
- `trailer/`: the current gameplay draft, poster, cut list and source receipt.
- `docs/steam-store/`: the separate short/about/mature-content/AI fields plus
  claim evidence and the owner checklist. Only paste approved field contents.
- `manifest.json`: exact copied-file hashes and original project-relative paths.

## Required before release

The owner must supply the intended Steam App ID/publisher account, support contact,
price/date and supported-platform/language decisions. Voice/asset permissions,
trailer listening, native platform/controller playtests, observed newcomer/co-op
acceptance, signing and Steam review remain open. Start with
`docs/steam-store/owner-review.md` and `docs/release-readiness.md`.

The builds include the solo ready-up repair. Media retains its original capture
revision: it is not silently relabeled as footage captured from these binaries.
The selected media does not demonstrate the new Endless ready-up panel. Review
whether new footage is required before submission. No awards, audience response,
commercial performance or launch-readiness claim is implied.

Historical receipts retain their original source paths. Some deeper documentation
links and the trailer's raw movie inputs remain in the original project and are
not included in this package. This is a review handoff, not a complete source archive.
"""
    (output / "START-HERE.md").write_text(start)
    records.append({"file": "START-HERE.md", "source": "generated review index",
                    "sha256": sha(output / "START-HERE.md"),
                    "bytes": (output / "START-HERE.md").stat().st_size})
    (output / "manifest.json").write_text(json.dumps({
        "status": "review only; not uploaded, published, rights-cleared or platform-approved",
        "files": records}, indent=2) + "\n")
    with zipfile.ZipFile(archive_path, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
        for path in sorted(output.rglob("*")):
            if path.is_file():
                archive.write(path, path.relative_to(output))
    with zipfile.ZipFile(archive_path) as archive:
        if archive.testzip():
            raise ValueError("Review archive failed integrity check")
    verify(output)
    print(f"RELEASE REVIEW ASSEMBLED: {output}")
    print(f"ZIP SHA256: {sha(archive_path)}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("--verify", action="store_true", help="Verify an existing folder and sibling ZIP without changing either")
    args = parser.parse_args()
    try:
        if args.verify:
            verify(args.output.resolve())
        else:
            assemble(ROOT, args.output.resolve())
    except (ValueError, OSError, KeyError, zipfile.BadZipFile) as error:
        parser.exit(1, f"Release review assembly failed: {error}\n")
