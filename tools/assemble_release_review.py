"""Assemble explicitly selected, receipted artifacts without launching or uploading."""
import argparse
import hashlib
import json
from pathlib import Path, PureWindowsPath
import re
import shutil
import zipfile

from verify_store_copy import validate as validate_copy
from build_steam_candidates import SOURCE_DIRS, SOURCE_FILES

ROOT = Path(__file__).resolve().parents[1]


def sha(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def safe_member(base, name):
    if not isinstance(name, str) or not name or "\\" in name or PureWindowsPath(name).drive:
        raise ValueError(f"Unsafe artifact path: {name}")
    relative = Path(name)
    path = base / relative
    if relative.is_absolute() or ".." in relative.parts or not path.resolve().is_relative_to(base.resolve()):
        raise ValueError(f"Unsafe artifact path: {name}")
    if not path.is_file() or any((base / Path(*relative.parts[:index])).is_symlink()
                                 for index in range(1, len(relative.parts) + 1)):
        raise ValueError(f"Missing/nonregular artifact: {path}")
    return path


def require_hash(path, expected):
    if not isinstance(expected, str) or not re.fullmatch(r"[0-9a-f]{64}", expected):
        raise ValueError(f"Invalid source checksum: {path}")
    if sha(path) != expected:
        raise ValueError(f"Artifact checksum differs from its source receipt: {path}")


def verify(output):
    """Check copied files and ZIP bytes against the handoff manifest; no extraction."""
    manifest_path = output / "manifest.json"
    manifest = json.loads(manifest_path.read_text())
    rows = manifest["files"]
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
    if manifest.get("schema_version") == 2:
        selections = manifest["selections"]
        candidate = selections["builds"]["source_identity"]
        for kind, selection in selections.items():
            prefix = "store-art" if kind == "art" else kind
            source_receipt = safe_member(output, f"{prefix}/source-manifest.json")
            require_hash(source_receipt, selection["manifest_sha256"])
            identity = declared_identity(json.loads(source_receipt.read_text()))
            if identity != selection["source_identity"]:
                raise ValueError(f"Copied {kind} source identity differs from selection declaration")
            if kind == "art" and selection["source_relation"] != "historical art":
                raise ValueError("Historical art was relabeled as current gameplay evidence")
            if selection["source_relation"] == "same source snapshot" and not same_source(identity, candidate):
                raise ValueError(f"False same-source declaration for {kind}")
            if manifest["require_same_source"] and kind not in ("builds", "art") and not same_source(identity, candidate):
                raise ValueError(f"Same-source promise failed for {kind}")
    print(f"RELEASE REVIEW VERIFIED: {len(rows)} receipted files; folder and ZIP bytes match")


def source_identity(record, complete=False):
    if not isinstance(record, dict):
        raise ValueError("Source identity must be a dictionary")
    revision = record.get("revision", record.get("source_revision"))
    files = record.get("files", record.get("source_files", {}))
    if not isinstance(revision, str) or not re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}", revision):
        raise ValueError("Source identity has no valid revision")
    if not isinstance(files, dict) or not files:
        raise ValueError("Source identity has no file fingerprints")
    normalized = {}
    for name, digest in files.items():
        if not isinstance(name, str):
            raise ValueError("Source fingerprint paths must be strings")
        name = name.removeprefix("res://")
        if not name or name in normalized or "\\" in name or Path(name).is_absolute() or ".." in Path(name).parts or PureWindowsPath(name).drive:
            raise ValueError(f"Unsafe or duplicate source path: {name}")
        if not isinstance(digest, str) or not re.fullmatch(r"[0-9a-f]{64}", digest):
            raise ValueError(f"Invalid source fingerprint: {name}")
        normalized[name] = digest
    fingerprint = hashlib.sha256(json.dumps(normalized, sort_keys=True).encode()).hexdigest()
    if record.get("fingerprint_sha256", fingerprint) != fingerprint:
        raise ValueError("Source identity fingerprint differs from its file map")
    return {"revision": revision, "fingerprint_sha256": fingerprint, "files": normalized,
            "project_version": record.get("project_version"), "complete": complete,
            "dirty": record.get("dirty", record.get("source_dirty"))}


def same_source(left, right):
    if left is None or right is None or not left["complete"] or not right["complete"]:
        return False
    return all(left[key] == right[key] for key in ("revision", "fingerprint_sha256", "project_version"))


def current_source_files(root):
    paths = [root / name for name in SOURCE_FILES if (root / name).is_file()]
    for directory in SOURCE_DIRS:
        paths.extend(path for path in (root / directory).rglob("*")
                     if path.is_file() and path.name != ".DS_Store")
    return {path.relative_to(root).as_posix(): sha(safe_member(root, path.relative_to(root).as_posix()))
            for path in sorted(paths)}


def read_manifest(directory):
    path = safe_member(directory, "manifest.json")
    record = json.loads(path.read_text())
    if not isinstance(record, dict):
        raise ValueError("Artifact manifest must be a dictionary")
    return record, path


def declared_identity(manifest):
    if "source_before" in manifest or "source_after" in manifest:
        if manifest.get("source_before") != manifest.get("source_after"):
            raise ValueError("Source changed between the artifact's recorded snapshots")
        identity = source_identity(manifest["source_before"], complete=True)
        if "source_identity" in manifest and identity != source_identity(manifest["source_identity"], complete=True):
            raise ValueError("Source identity conflicts with its recorded snapshots")
        return identity
    if "source_identity" in manifest:
        return source_identity(manifest["source_identity"], complete=True)
    if "source_revision" in manifest:
        return source_identity(manifest)
    return None


def plan(root, sources, require_same_source=False):
    """Validate recorded artifact bytes before creating any destination."""
    validate_copy(root / "docs/steam-store")
    selected = {}
    selections = {}

    def add(path, destination):
        if not path.is_file() or path.is_symlink():
            raise ValueError(f"Missing/nonregular selected file: {path}")
        if destination in selected:
            raise ValueError(f"Duplicate destination: {destination}")
        selected[destination] = (path, sha(path))

    def selection(kind, manifest, manifest_path, historical=False):
        identity = declared_identity(manifest)
        candidate = selections.get("builds", {}).get("source_identity")
        relation = "historical art" if historical else "source unspecified"
        if not historical and identity is not None:
            relation = "recorded partial source" if not identity["complete"] else "different source snapshot"
            if same_source(identity, candidate):
                relation = "same source snapshot"
        if require_same_source and kind not in ("builds", "art") and relation != "same source snapshot":
            raise ValueError(f"Same-source promise failed for {kind}: {relation}")
        selections[kind] = {"directory": str(sources[kind].resolve()),
                            "manifest_sha256": sha(manifest_path),
                            "source_identity": identity, "source_relation": relation}

    builds_dir = sources["builds"]
    builds, builds_manifest = read_manifest(builds_dir)
    identity = declared_identity(builds)
    if "source_before" not in builds or "source_after" not in builds or identity is None or not identity["complete"] or not identity["project_version"]:
        raise ValueError("Fresh candidates require complete unchanged source identity and project version")
    if identity["files"] != current_source_files(root):
        raise ValueError("Candidate source fingerprint differs from the current source files; rebuild after convergence")
    version = re.search(r'^config/version="([^"]+)"$', (root / "project.godot").read_text(), re.MULTILINE)
    if version is None or identity["project_version"] != version.group(1):
        raise ValueError("Candidate project version differs from the current project version")
    if {r["platform"] for r in builds["exports"]} != {"macos", "linux", "windows"} or len(builds["exports"]) != 3:
        raise ValueError("Expected all three desktop candidate records")
    selection("builds", builds, builds_manifest)
    selections["builds"]["source_relation"] = "verified current source files"
    for record in builds["exports"]:
        if not record["files"]:
            raise ValueError("Candidate record has no exported files")
        for name, expected in record["files"].items():
            path = safe_member(builds_dir / record["platform"], name)
            require_hash(path, expected)
            add(path, f"builds/{record['platform']}/{name}")
        if "export_log_sha256" not in record:
            raise ValueError("Fresh candidate receipt is missing its export log hash")
        log = safe_member(builds_dir / record["platform"], "export.log")
        require_hash(log, record["export_log_sha256"])
        add(log, f"builds/{record['platform']}/export.log")
    add(builds_manifest, "builds/source-manifest.json")

    if sources.get("art"):
        art, art_manifest = read_manifest(sources["art"])
        if not art["assets"]:
            raise ValueError("Art selection has no assets")
        selection("art", art, art_manifest, historical=True)
        for record in art["assets"]:
            for field, hash_field in [("file", "sha256"), ("source_file", "source_sha256")]:
                path = safe_member(sources["art"], record[field])
                require_hash(path, record[hash_field])
                add(path, "store-art/" + record[field])
        add(art_manifest, "store-art/source-manifest.json")

    for kind in ("screenshots", "trailer", "evidence"):
        if not sources.get(kind):
            continue
        manifest, manifest_path = read_manifest(sources[kind])
        selection(kind, manifest, manifest_path)
        recorded_files = manifest.get("files", {})
        if not isinstance(recorded_files, dict):
            raise ValueError(f"{kind} file receipt must be a path-to-checksum dictionary")
        files = dict(recorded_files)
        if kind == "screenshots":
            if not manifest["screenshots"]:
                raise ValueError("Screenshot selection has no screenshots")
            for record in manifest["screenshots"]:
                if record["file"] in files and files[record["file"]] != record["sha256"]:
                    raise ValueError("Screenshot hash conflicts with its file receipt")
                files[record["file"]] = record["sha256"]
        elif kind == "trailer":
            name = manifest["file"]
            if name in files and files[name] != manifest["sha256"]:
                raise ValueError("Trailer hash conflicts with its file receipt")
            files[name] = manifest["sha256"]
        if not files:
            raise ValueError(f"{kind} has no receipted files")
        for name, expected in files.items():
            path = safe_member(sources[kind], name)
            require_hash(path, expected)
            add(path, f"{kind}/{name}")
        add(manifest_path, f"{kind}/source-manifest.json")

    for path in sorted((root / "docs/steam-store").iterdir()):
        if path.is_file() and not path.name.startswith("."):
            add(path, "docs/steam-store/" + path.name)
    for name in ["release-readiness", "steam-candidate-validation", "steam-gameplay-screenshots",
                 "gameplay-trailer-draft", "movie-capture-validation", "steam-hero-validation",
                 "blender-media-validation", "godotsteam_api_version", "steam_cloud_paths",
                 "ten-item-acceptance", "ready-feedback"]:
        path = root / "docs" / (name + ".md")
        if path.exists():
            add(path, "docs/" + name + ".md")
    for name in ("completion-handoff.md", "completion-plan.md", "completion-status.json", "completion-external-checks.md"):
        path = root / "docs" / name
        if path.exists():
            add(path, "docs/" + name)
    for name in ["ASSETS.md", "NOTICE.md"]:
        add(root / name, name)
    return selected, selections


def assemble(root, output, sources, require_same_source=False):
    archive_path = output.with_suffix(".zip")
    if output.exists() or archive_path.exists():
        raise ValueError("Destination or archive already exists; choose a new destination")
    selected, selections = plan(root, sources, require_same_source)
    output.mkdir()
    records = []
    for destination, (source, expected) in selected.items():
        target = output / destination
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
        require_hash(target, expected)
        records.append({"file": destination, "source": str(source.resolve()),
                        "sha256": expected, "bytes": target.stat().st_size})
    start = "# Release review package\n\nThis is a checksummed review handoff. Assembly does not establish launch approval.\n\n"
    start += "## Selected sources\n\n"
    for kind in ("builds", "art", "screenshots", "trailer", "evidence"):
        item = selections.get(kind)
        if item is None:
            start += f"- {kind}: absent from this handoff. Its review remains open.\n"
            continue
        identity = item["source_identity"]
        version = f" Version {identity['project_version']}." if identity and identity.get("project_version") else ""
        revision = f" Recorded revision {identity['revision']}." if identity else " No game-source identity is declared."
        start += f"- {kind}: {item['source_relation']}.{version}{revision}\n"
    start += """
## Evidence limits

Each source manifest remains inside its artifact folder. The handoff manifest records
the selected source directories, manifest hashes, identities, copied-file hashes, and
whether the same-source promise was required. Supporting media or runtime files are
included only when their source manifest supplies hashes. Unlisted captures, raw movie
inputs, posters, cut lists, and platform logs are absent rather than silently copied.

Historical store art has independent image and source-file receipts. That art does not
prove capture from the candidate game. A partial or missing media identity cannot prove
the same source snapshot. Current source-file hashes prove packaging provenance, not
native execution, listening review, hardware/controller acceptance, signing, asset rights,
intended Steam-account behavior, or platform review.

Project documentation retains its recorded scope and dates. Open launch requirements
remain in `docs/completion-handoff.md`, `docs/completion-status.json`, and
`docs/steam-store/owner-review.md` when those files are present. Publication is separate.
"""
    for source, expected in selected.values():
        require_hash(source, expected)
    if selections["builds"]["source_identity"]["files"] != current_source_files(root):
        raise ValueError("Source changed during review assembly; create a new handoff after convergence")
    (output / "START-HERE.md").write_text(start)
    records.append({"file": "START-HERE.md", "source": "generated review index",
                    "sha256": sha(output / "START-HERE.md"),
                    "bytes": (output / "START-HERE.md").stat().st_size})
    (output / "manifest.json").write_text(json.dumps({
        "status": "review only; not uploaded, published, rights-cleared or platform-approved",
        "schema_version": 2, "require_same_source": require_same_source,
        "selections": selections, "files": records}, indent=2) + "\n")
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
    for kind in ("builds", "art", "screenshots", "trailer", "evidence"):
        parser.add_argument("--" + kind, type=Path, help=f"Explicit {kind} source directory with manifest.json")
    parser.add_argument("--require-same-source", action="store_true",
                        help="Require complete candidate-matching source identity on supplied media and runtime evidence")
    args = parser.parse_args()
    try:
        if args.verify:
            verify(args.output.resolve())
        else:
            if args.builds is None:
                parser.error("--builds is required for new assembly; historical directories have no defaults")
            sources = {kind: getattr(args, kind).resolve() for kind in
                       ("builds", "art", "screenshots", "trailer", "evidence") if getattr(args, kind) is not None}
            assemble(ROOT, args.output.resolve(), sources, args.require_same_source)
    except (ValueError, OSError, KeyError, zipfile.BadZipFile) as error:
        parser.exit(1, f"Release review assembly failed: {error}\n")
