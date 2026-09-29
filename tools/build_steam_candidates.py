"""Build pinned Steam-enabled local candidates without launching Steam or a game.

Install the separately pinned GodotSteam templates first; see the version note.
The output directory must be new. This is not a Steam upload or signing pipeline.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import zipfile

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
ERRORS = re.compile(r"SCRIPT ERROR|Parse Error|Compile Error|^ERROR:", re.MULTILINE)


def sha(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def require_pinned(path, expected):
    if not path.is_file() or sha(path) != expected:
        raise ValueError(f"Missing or non-pinned template/runtime: {path}")


def build(output, platforms, godot):
    if output.exists():
        raise ValueError("Output directory already exists; choose a new directory")
    for platform in platforms:
        for relative in TARGETS[platform][2]:
            require_pinned(TEMPLATES / relative, PINNED[relative])
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
        if result.returncode or ERRORS.search(log.read_text()) or not artifact.is_file():
            raise ValueError(f"Export failed or emitted errors; inspect {log}")
        if platform == "macos":
            with zipfile.ZipFile(artifact) as archive:
                libraries = [n for n in archive.namelist() if n.endswith("/libsteam_api.dylib")]
                if len(libraries) != 1 or archive.testzip():
                    raise ValueError("macOS archive lacks its Steam runtime or is corrupt")
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
                        "files": {p.name: sha(p) for p in sorted(directory.iterdir()) if p != log}})
        print(f"STEAM CANDIDATE BUILT: {platform}", flush=True)
    (output / "manifest.json").write_text(json.dumps({
        "status": "local candidates; not launched, uploaded, or platform-approved by this tool",
        "godotsteam": "4.22.1", "godot": "4.7.2", "steamworks": "1.65",
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
