"""Reject Godot runtime errors, shutdown leaks, and missing success markers."""
import argparse
from pathlib import Path
import re

DIAGNOSTICS = re.compile(
    r"SCRIPT ERROR|Parse Error|Compile Error|(?:^|\s)ERROR:|"
    r"was leaked|were leaked|resources still in use at exit|leaked \d+ bytes",
    re.MULTILINE,
)


def check_log(text, required):
    failures = [line for line in text.splitlines() if DIAGNOSTICS.search(line)]
    failures.extend(f"Missing success marker: {marker}" for marker in required if marker not in text)
    return failures


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("log", type=Path)
    parser.add_argument("--require", action="append", default=[])
    args = parser.parse_args()
    failures = check_log(args.log.read_text(errors="replace"), args.require)
    if failures:
        parser.exit(1, "\n".join(failures) + "\n")
    print("RUNTIME LOG PASS: success markers present, zero errors or shutdown leaks")
