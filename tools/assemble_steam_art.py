"""Assemble a fresh, checksummed art handoff; never uploads or overwrites one."""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import struct

SIZES = {
    "header_capsule": (920, 430), "main_capsule": (1232, 706),
    "small_capsule": (462, 174), "vertical_capsule": (748, 896),
    "library_capsule": (600, 900), "library_header": (920, 430),
    "library_hero": (3840, 1240), "library_logo": (1280, 540),
}


def assemble(base, hero, output):
    base, hero, output = (Path(p).resolve() for p in (base, hero, output))
    inputs = []
    for name, size in SIZES.items():
        stem = "header_capsule" if name == "library_header" else name
        source = (hero if name == "library_hero" else base) / (stem + ".png")
        data = source.read_bytes()
        if data[:8] != b"\x89PNG\r\n\x1a\n" or struct.unpack(">II", data[16:24]) != size:
            raise ValueError(f"Invalid PNG/dimensions: {source}")
        blend = source.with_suffix(".blend")
        if not blend.is_file():
            raise ValueError(f"Missing editable source: {blend}")
        inputs.append((name, size, source, blend, hashlib.sha256(data).hexdigest()))
    output.mkdir(parents=True, exist_ok=False)
    (output / "sources").mkdir()
    manifest = {"scope": "local Steam art handoff; no upload or platform approval",
                "library_header_mapping": "explicit byte-identical copy of store header capsule",
                "remaining_release_work": ["gameplay screenshot selection", "store writeups and disclosures",
                                           "account preview/review", "production build verification"],
                "assets": []}
    for name, size, source, blend, digest in inputs:
        shutil.copy2(source, output / (name + ".png"))
        shutil.copy2(blend, output / "sources" / (name + ".blend"))
        manifest["assets"].append({"name": name, "file": name + ".png", "size": size,
                                   "sha256": digest, "source_file": "sources/" + name + ".blend",
                                   "source_sha256": hashlib.sha256(blend.read_bytes()).hexdigest()})
    (output / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print("STEAM ART HANDOFF", output)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--base", required=True)
    parser.add_argument("--hero", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()
    assemble(args.base, args.hero, args.output)
