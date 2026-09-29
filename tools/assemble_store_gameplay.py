"""Copy inspected gameplay selections and their evidence into a new handoff.

Selection JSON: [{"take": "build/take-folder", "file": "gameplay-001.png",
"name": "01-combat.png"}, ...]. Paths are relative to --project, not the JSON.
Pixels are copied unchanged. Output must not exist.
"""
import argparse
import json
from pathlib import Path
import shutil

from verify_store_gameplay import digest, local_file, verify


def capture_identity(capture):
    """A new handoff must use one captured source version and an isolated bot."""
    if capture.get("os_gameplay_input_disabled") is not True:
        raise ValueError("New handoffs require input-isolated captures")
    sources = capture.get("source_files")
    if not sources or not capture.get("engine") or not capture.get("renderer"):
        raise ValueError("Missing capture source/toolchain identity")
    return (sources, capture["engine"], capture["renderer"])


def assemble(project, selection, output):
    picks = json.loads(selection.read_text())
    if len(picks) < 5:
        raise ValueError("Select at least five inspected gameplay images")
    verified = {}
    records = []
    names = set()
    images = set()
    identity = None
    for pick in picks:
        take = (project / pick["take"]).resolve()
        if not take.is_relative_to(project.resolve()):
            raise ValueError("Take is outside the project")
        if take not in verified:
            verified[take] = verify(take)
        if pick["file"] not in verified[take]["active_candidates"]:
            raise ValueError("Selection must show active, living gameplay")
        name = pick["name"]
        if Path(name).name != name or not name.endswith(".png") or name in names:
            raise ValueError("Invalid or duplicate destination filename")
        source = local_file(take, pick["file"])
        sha = digest(source)
        if sha in images:
            raise ValueError("Duplicate selected image")
        images.add(sha)
        names.add(name)
        capture = json.loads((take / "capture.json").read_text())
        current_identity = capture_identity(capture)
        if identity is not None and current_identity != identity:
            raise ValueError("Selected takes have different source/toolchain identities")
        identity = current_identity
        frame = next(frame for frame in capture["frames"] if frame["file"] == pick["file"])
        records.append({"file": name, "sha256": sha,
                        "evidence": f"evidence/{take.name}/capture.json",
                        "source_frame": frame, "source": source})
    output.mkdir(parents=False, exist_ok=False)
    (output / "evidence").mkdir()
    for take in verified:
        target = output / "evidence" / take.name
        target.mkdir()
        capture = json.loads((take / "capture.json").read_text())
        # Keep every captured frame, including rejected ones, and the full replay.
        for name in ["capture.json", capture["replay"]] + [
                frame[key] for frame in capture["frames"] for key in ("file", "raw_file")]:
            shutil.copy2(local_file(take, name), target / name)
        verify(target)
    for record in records:
        shutil.copy2(record.pop("source"), output / record["file"])
        if digest(output / record["file"]) != record["sha256"]:
            raise ValueError("Copied screenshot hash changed")
    manifest = {
        "status": "locally inspected draft; not uploaded or approved by Steam",
        "size": [1920, 1080], "presentation": "exact nearest 3x of 640x360 game canvas",
        "inputs": "production autoplay bot; no staged entities or god mode",
        "suitable_for_all_ages": "not asserted; combat content requires owner review",
        "remaining": ["owner content/rights review", "account-side preview and approval",
                      "new captures after material gameplay or visual changes"],
        "screenshots": records}
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    return {"output": str(output), "screenshots": len(records), "evidence_takes": len(verified)}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("selection", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--project", type=Path, default=Path.cwd())
    args = parser.parse_args()
    try:
        print(json.dumps(assemble(args.project, args.selection, args.output), indent=2))
    except (ValueError, KeyError, OSError, TypeError) as error:
        parser.exit(1, f"Gameplay assembly failed: {error}\n")
