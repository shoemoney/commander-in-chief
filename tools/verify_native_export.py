"""Verify exact release packs with isolated saves and no source fallback.

Stock release templates disable external driver injection. Use --engine to test
their exact pack with the standard engine; this does not execute the release
binary or prove Steam, signing, controller hardware, or rendering.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import tempfile
import zipfile

from verify_runtime_log import check_log

ROOT = Path(__file__).resolve().parents[1]
DRIVER = Path(__file__).with_name("native_export_smoke.gd")
REQUIRED = ("NATIVE EXPORT FONT AWESOME PASS", "NATIVE EXPORT PROGRESS PASS", "NATIVE EXPORT QUIT DRAIN PASS")
ROUTES = ("menu", "window", "paused-window")


def sha(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def unpack_artifact(artifact, directory, version):
    if artifact.suffix != ".zip":
        return artifact, artifact.with_suffix(".pck")
    with zipfile.ZipFile(artifact) as archive:
        for entry in archive.infolist():
            path = Path(entry.filename)
            if path.is_absolute() or ".." in path.parts:
                raise ValueError("Unsafe path in application archive")
        if archive.testzip():
            raise ValueError("Corrupt application archive")
        archive.extractall(directory)
    plists = list(directory.glob("*.app/Contents/Info.plist"))
    if len(plists) != 1:
        raise ValueError("Require one macOS application in archive")
    metadata = plistlib.loads(plists[0].read_bytes())
    if any(metadata.get(key) != version for key in ("CFBundleVersion", "CFBundleShortVersionString")):
        raise ValueError("macOS package metadata does not match the requested release")
    contents = plists[0].parent
    executable = contents / "MacOS" / metadata["CFBundleExecutable"]
    executable.chmod(executable.stat().st_mode | 0o111)
    packs = list((contents / "Resources").glob("*.pck"))
    if len(packs) != 1:
        raise ValueError("Require one macOS game pack")
    return executable, packs[0]


def verify(artifact, log_directory, version, routes=ROUTES, timeout=60, engine=None):
    artifact = artifact.resolve(strict=True)
    log_directory.mkdir(parents=True, exist_ok=False)
    receipt = {"artifact": str(artifact), "artifact_sha256": sha(artifact),
               "project_version": version, "driver_sha256": sha(DRIVER), "routes": []}
    receipt["execution_kind"] = "standard-engine-exact-pack" if engine else "native-external-driver"
    with tempfile.TemporaryDirectory(prefix="cic-native-") as temporary:
        isolated = Path(temporary).resolve()
        executable, pack = unpack_artifact(artifact, isolated / "application", version)
        if not executable.is_file() or not pack.is_file():
            raise ValueError("Release executable or adjacent game pack is missing")
        receipt["executable_sha256"] = sha(executable)
        receipt["pack_sha256"] = sha(pack)
        runtime = Path(shutil.which(str(engine)) or engine).resolve(strict=True) if engine else executable
        receipt["runtime"] = str(runtime)
        receipt["runtime_sha256"] = sha(runtime)
        external_driver = isolated / "native_driver.gd"
        shutil.copyfile(DRIVER, external_driver)
        empty_project = isolated / "empty"
        empty_project.mkdir()
        for route in routes:
            profile = isolated / route
            profile.mkdir()
            environment = os.environ.copy()
            for key in ("XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME"):
                environment.pop(key, None)
            environment.update({"HOME": str(profile), "USERPROFILE": str(profile),
                                "APPDATA": str(profile / "Roaming"), "LOCALAPPDATA": str(profile / "Local"),
                                "NATIVE_EXPORT_PROFILE": str(profile),
                                "NATIVE_EXPORT_ROUTE": route, "NATIVE_EXPORT_VERSION": version})
            (profile / "Roaming").mkdir()
            (profile / "Local").mkdir()
            command = [str(runtime), "--headless", "--main-pack", str(pack),
                       "--script", str(external_driver)]
            log = log_directory / f"{route}.log"
            with log.open("w", encoding="utf-8") as stream:
                result = subprocess.run(command, cwd=empty_project, env=environment,
                                        stdout=stream, stderr=subprocess.STDOUT, timeout=timeout)
            failures = check_log(log.read_text(errors="replace"), REQUIRED)
            if result.returncode or failures:
                raise ValueError(f"Release pack {route} exit failed, code {result.returncode}; inspect {log}: "
                                 + "; ".join(failures))
            if sha(executable) != receipt["executable_sha256"] or sha(pack) != receipt["pack_sha256"]:
                raise ValueError("Release executable or pack changed during native verification")
            if sha(runtime) != receipt["runtime_sha256"]:
                raise ValueError("Verification runtime changed during release verification")
            receipt["routes"].append({"route": route, "exit_code": result.returncode,
                                      "log_sha256": sha(log), "process_exited": True})
            label = "EXACT RELEASE PACK" if engine else "NATIVE EXPORT"
            print(f"{label} PASS: {route}, production exit, zero diagnostics", flush=True)
    if sha(artifact) != receipt["artifact_sha256"]:
        raise ValueError("Candidate artifact changed during native verification")
    (log_directory / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
    return receipt


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("artifact", type=Path)
    parser.add_argument("--log-dir", type=Path, required=True)
    parser.add_argument("--version")
    parser.add_argument("--route", choices=ROUTES, action="append")
    parser.add_argument("--engine", help="Standard engine for exact-pack checks; does not execute the native release binary")
    args = parser.parse_args()
    version = args.version or re.search(r'^config/version="([^"]+)"$',
                                       (ROOT / "project.godot").read_text(), re.MULTILINE).group(1)
    try:
        verify(args.artifact, args.log_dir.resolve(), version, args.route or ROUTES, engine=args.engine)
    except (ValueError, OSError, subprocess.SubprocessError) as error:
        parser.exit(1, f"Release pack verification failed: {error}\n")
