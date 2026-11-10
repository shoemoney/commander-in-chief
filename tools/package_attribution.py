"""Carry exact Font Awesome license and source attribution into release packages."""
import argparse
import hashlib
import json
from pathlib import Path
import zipfile

ROOT = Path(__file__).resolve().parents[1]
RECORDS = ("LICENSE.txt", "manifest.json")
DESTINATION = "licenses/fontawesome"


def source_records(root):
    source = root / "assets/fontawesome"
    records = {f"{DESTINATION}/{name}": (source / name).read_bytes() for name in RECORDS}
    manifest = json.loads(records[f"{DESTINATION}/manifest.json"])
    if manifest.get("icons_license") != "CC BY 4.0" or not manifest.get("icons"):
        raise ValueError("Font Awesome attribution must identify CC BY 4.0 and its runtime icons")
    named_icons = {icon["icon"] for icon in manifest["icons"]}
    actual_icons = {path.stem for path in (source / "solid").glob("*.svg")}
    if named_icons != actual_icons or len(named_icons) != len(manifest["icons"]):
        raise ValueError("Font Awesome attribution must list each runtime SVG exactly once")
    for icon in manifest["icons"]:
        svg = source / "solid" / (icon["icon"] + ".svg")
        if hashlib.sha256(svg.read_bytes()).hexdigest() != icon["local_sha256"]:
            raise ValueError(f"Font Awesome attribution does not match runtime icon {svg.name}")
    return records


def check(artifact, root=ROOT):
    records = source_records(root)
    if artifact.suffix == ".zip":
        with zipfile.ZipFile(artifact) as archive:
            for name, expected in records.items():
                if archive.namelist().count(name) != 1 or archive.read(name) != expected:
                    raise ValueError(f"Release archive is missing or has stale attribution: {name}")
    else:
        for name, expected in records.items():
            path = artifact.parent / name
            if not path.is_file() or path.read_bytes() != expected:
                raise ValueError(f"Release folder is missing or has stale attribution: {name}")
    return {name: hashlib.sha256(data).hexdigest() for name, data in records.items()}


def package(artifact, root=ROOT):
    records = source_records(root)
    if artifact.suffix == ".zip":
        with zipfile.ZipFile(artifact, "a", compression=zipfile.ZIP_DEFLATED) as archive:
            for name, data in records.items():
                count = archive.namelist().count(name)
                if count:
                    if count != 1 or archive.read(name) != data:
                        raise ValueError(f"Existing release attribution differs: {name}")
                else:
                    archive.writestr(name, data)
    else:
        for name, data in records.items():
            path = artifact.parent / name
            if path.exists() and path.read_bytes() != data:
                raise ValueError(f"Existing release attribution differs: {name}")
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
    return check(artifact, root)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("artifact", type=Path)
    parser.add_argument("--verify", action="store_true")
    args = parser.parse_args()
    try:
        if not args.artifact.is_file():
            raise ValueError("Release artifact is missing")
        records = check(args.artifact) if args.verify else package(args.artifact)
    except (ValueError, KeyError, OSError, zipfile.BadZipFile) as error:
        parser.exit(1, f"Release attribution failed: {error}\n")
    print(f"RELEASE ATTRIBUTION PASS: exact license and manifest, {len(records)} records")
