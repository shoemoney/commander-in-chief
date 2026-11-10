"""Build pinned Steam-enabled local candidates without launching Steam or a game.

Install the separately pinned GodotSteam templates first; see the version note.
The output directory must be new. This is not a Steam upload or signing pipeline.
"""
import argparse
import configparser
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import zipfile

from verify_runtime_log import DIAGNOSTICS
from package_attribution import package as package_attribution

ROOT = Path(__file__).resolve().parents[1]
TEMPLATES = ROOT / "build/godotsteam-4.22.1/templates"
PINNED = {
    "macos/macos.zip": "9b40d3d1e38c084e0cd785e39e50d560b267970d2e5946cefb8ad6c02f9857d9",
    "linux64/godotsteam.472.template.x86_64": "490c648f85697f7a7ac10311bbaee304399a0291992a081811d89a14f856541d",
    "linux64/libsteam_api.so": "659127fd3c36788162149006efb607ae24c08b7264259c7af52c806fa40c2b4f",
    "win64/godotsteam.472.template.win64.exe": "faa0439b5a20861cc511df5d9cc47694f0c2e62b047b2927bf4f3d98473bfc85",
    "win64/steam_api64.dll": "8de54d32508e216c9135b8bf025749243d44e404c1c22a8e5fe35acecabe7a9c",
}
TARGETS = {
    "macos": ("Steam macOS universal", "CommanderInChief-macos.zip", ["macos/macos.zip"]),
    "linux": ("Steam Linux x86_64", "CommanderInChief-linux.x86_64",
              ["linux64/godotsteam.472.template.x86_64", "linux64/libsteam_api.so"]),
    "windows": ("Steam Windows x86_64", "CommanderInChief-windows.exe",
                ["win64/godotsteam.472.template.win64.exe", "win64/steam_api64.dll"]),
}
SOURCE_DIRS = ("src", "assets", "locale", "addons")
SOURCE_FILES = ("project.godot", "export_presets.cfg", "icon.ico", "icon.png",
                "icon.png.import", "tools/versions.lock", "tools/build_steam_candidates.py",
                "tools/package_attribution.py", "tools/verify_runtime_log.py")


def sha(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def require_pinned(path, expected):
    if not path.is_file() or sha(path) != expected:
        raise ValueError(f"Missing or non-pinned template/runtime: {path}")


def command_output(command):
    with subprocess.Popen(command, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE) as process:
        output, errors = process.communicate(timeout=30)
        if process.returncode:
            raise ValueError(f"Cannot read build provenance: {errors.decode(errors='replace')}")
        return output.decode(errors="replace").strip()


def source_state():
    paths = [ROOT / name for name in SOURCE_FILES if (ROOT / name).is_file()]
    for directory in SOURCE_DIRS:
        paths.extend(path for path in (ROOT / directory).rglob("*")
                     if path.is_file() and path.name != ".DS_Store")
    fingerprints = {path.relative_to(ROOT).as_posix(): sha(path) for path in sorted(paths)}
    version = re.search(r'^config/version="([^"]+)"$',
                        (ROOT / "project.godot").read_text(), re.MULTILINE)
    if not version:
        raise ValueError("project.godot has no project version")
    dirty = command_output(["git", "status", "--porcelain=v1", "--untracked-files=all", "--",
                            *SOURCE_DIRS, *SOURCE_FILES]).splitlines()
    return {
        "revision": command_output(["git", "rev-parse", "HEAD"]),
        "dirty": bool(dirty), "dirty_paths": dirty, "project_version": version.group(1),
        "fingerprint_sha256": hashlib.sha256(json.dumps(fingerprints, sort_keys=True).encode()).hexdigest(),
        "files": fingerprints,
    }


def check_preset_versions(version):
    presets = configparser.ConfigParser(interpolation=None)
    presets.read(ROOT / "export_presets.cfg")
    for section in presets.sections():
        if section.endswith(".options") or not section.startswith("preset."):
            continue
        platform = presets[section].get("platform", "").strip('"')
        options = presets[section + ".options"]
        keys = ("application/short_version", "application/version") if platform == "macOS" else ()
        expected = version
        if platform == "Windows Desktop":
            keys = ("application/file_version", "application/product_version")
            expected = version + ".0" if version.count(".") == 2 else version
        for key in keys:
            if options.get(key, "").strip('"') != expected:
                raise ValueError(f"Stale export metadata: {section} {key} must be {expected}")


def check_mac_archive(artifact, version):
    with zipfile.ZipFile(artifact) as archive:
        libraries = [n for n in archive.namelist() if n.endswith("/libsteam_api.dylib")]
        plists = [n for n in archive.namelist() if n.endswith(".app/Contents/Info.plist")]
        if len(libraries) != 1 or archive.testzip():
            raise ValueError("macOS archive lacks its Steam runtime or is corrupt")
        if len(plists) != 1:
            raise ValueError("macOS archive must carry exactly one application Info.plist")
        metadata = plistlib.loads(archive.read(plists[0]))
        for key in ("CFBundleShortVersionString", "CFBundleVersion"):
            if metadata.get(key) != version:
                raise ValueError(f"Stale macOS archive metadata: {key} is not {version}")
        return {key: metadata[key] for key in ("CFBundleShortVersionString", "CFBundleVersion")}


def build(output, platforms, godot):
    if output.exists():
        raise ValueError("Output directory already exists; choose a new directory")
    for platform in platforms:
        for relative in TARGETS[platform][2]:
            require_pinned(TEMPLATES / relative, PINNED[relative])
    source = source_state()
    check_preset_versions(source["project_version"])
    engine = command_output([godot, "--version"])
    if not engine.startswith("4.7.2."):
        raise ValueError(f"Candidate engine does not match pinned Godot 4.7.2: {engine}")
    output.mkdir(parents=False)
    records = []
    for platform in platforms:
        preset, filename, files = TARGETS[platform]
        directory = output / platform
        directory.mkdir()
        artifact = directory / filename
        log = directory / "export.log"
        with log.open("w") as stream:
            result = subprocess.run([godot, "--headless", "--path", str(ROOT),
                                     "--export-release", preset, str(artifact.resolve())],
                                    stdout=stream, stderr=subprocess.STDOUT, timeout=300)
        if result.returncode or DIAGNOSTICS.search(log.read_text()) or not artifact.is_file():
            raise ValueError(f"Export failed or emitted errors; inspect {log}")
        if source_state() != source:
            raise ValueError("Source changed during export; discard these candidates and rebuild after convergence")
        metadata = {}
        if platform == "macos":
            metadata = check_mac_archive(artifact, source["project_version"])
        else:
            # A custom executable alone is not a complete Steam distribution.
            # Godot does not infer this module's sidecar library dependency.
            library = files[1]
            target = directory / Path(library).name
            shutil.copy2(TEMPLATES / library, target)
            require_pinned(target, PINNED[library])
            if not artifact.with_suffix(".pck").is_file():
                raise ValueError(f"Exported game data missing beside {artifact}")
        records.append({"platform": platform, "preset": preset,
                        "attribution": package_attribution(artifact, ROOT),
                        "metadata": metadata, "export_log_sha256": sha(log),
                        "files": {p.relative_to(directory).as_posix(): sha(p)
                                  for p in sorted(directory.rglob("*")) if p.is_file() and p != log}})
        print(f"STEAM CANDIDATE BUILT: {platform}", flush=True)
    final_source = source_state()
    if final_source != source:
        raise ValueError("Source changed before receipt; discard these candidates and rebuild after convergence")
    for platform in platforms:
        for relative in TARGETS[platform][2]:
            require_pinned(TEMPLATES / relative, PINNED[relative])
    (output / "manifest.json").write_text(json.dumps({
        "schema_version": 2, "created_utc": datetime.now(timezone.utc).isoformat(),
        "status": "local candidates; not launched, uploaded, or platform-approved by this tool",
        "godotsteam": "4.22.1", "godot": "4.7.2", "steamworks": "1.65",
        "engine_version": engine, "source_before": source, "source_after": final_source,
        "project_version": source["project_version"],
        "template_archive_sha256": "ae0b83d87b4877bf2b1ed0bd19286d2c145796fad8d155e93a2ae6e055484ef9",
        "template_files": PINNED, "exports": records,
        "remaining": ["native platform execution", "intended Steam app/account verification",
                      "distribution signing", "content and rights review"]}, indent=2) + "\n")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", type=Path)
    parser.add_argument("--platform", choices=TARGETS, action="append")
    parser.add_argument("--godot", default="/Applications/Godot.app/Contents/MacOS/Godot")
    args = parser.parse_args()
    try:
        build(args.output.resolve(), list(dict.fromkeys(args.platform or TARGETS)), args.godot)
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        parser.exit(1, f"Steam candidate build failed: {error}\n")
