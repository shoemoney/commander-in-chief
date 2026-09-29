#!/usr/bin/env python3
"""Structural checks only: no rights, feature, rating or Steam approval verdict."""

import argparse
import json
import re
from pathlib import Path


def validate(directory: Path) -> dict:
    required = ["short-description.txt", "about.bbcode", "mature-content.txt",
                "ai-disclosure.txt", "README.md", "claim-evidence.md", "owner-review.md"]
    missing = [name for name in required if not (directory / name).is_file()]
    if missing:
        raise ValueError(f"Missing handoff files: {', '.join(missing)}")
    fields = {name: (directory / name).read_text(encoding="utf-8").strip()
              for name in required[:4]}
    for name, content in fields.items():
        if not content:
            raise ValueError(f"Empty field: {name}")
        if re.search(r"https?://|www\.|\[url", content, re.I):
            raise ValueError(f"External link in store field: {name}")
    short = fields["short-description.txt"]
    if len(short) > 300 or "\n" in short or "[" in short or "]" in short:
        raise ValueError("Short description must be one plain-text paragraph within the project 300-character budget")
    stack = []
    for token in re.findall(r"\[[^]]*\]", fields["about.bbcode"]):
        if token == "[*]":
            if not stack or stack[-1] != "list":
                raise ValueError("List item outside a list")
        elif token in ("[h2]", "[list]", "[b]"):
            stack.append(token[1:-1])
        elif token in ("[/h2]", "[/list]", "[/b]"):
            if not stack or stack.pop() != token[2:-1]:
                raise ValueError(f"Unbalanced BBCode: {token}")
        else:
            raise ValueError(f"Unexpected BBCode: {token}")
    if stack:
        raise ValueError("Unclosed BBCode")
    return {"structural_checks": "pass", "short_description_characters": len(short),
            "field_files": list(fields), "platform_approval": "not assessed",
            "rights_and_feature_claims": "require review"}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("directory", nargs="?", type=Path,
                        default=Path(__file__).resolve().parents[1] / "docs/steam-store")
    args = parser.parse_args()
    try:
        print(json.dumps(validate(args.directory), indent=2))
    except (ValueError, OSError) as error:
        parser.exit(1, f"Store copy validation failed: {error}\n")
