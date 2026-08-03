#!/usr/bin/env python3
"""
localization-text-pipeline maintenance check: extracts the same set of English
strings the game's TranslationServer.translate() calls key off of, and diffs
them against every res://locale/strings.*.po file -- so a new/renamed/removed
translatable string is caught as MISSING (needs adding to every .po) or STALE
(a .po carries a msgid nothing in source uses anymore) instead of quietly
drifting out of sync one string at a time.

Not a generic xgettext string-scanner -- it targets the SPECIFIC extraction
points the codebase actually routes through TranslationServer.translate()
(see the comments at each of these in src/): menu.gd's SETTING_HELP dict,
sfx.gd's _VO_CAPTIONS/_BARK_CAPTIONS dicts, main.gd's static (and templated)
_hint() literals, hud.gd's VERB_SEGS labels, and the SELECT/BACK nav-legend
words. A string routed through translate() some other way won't be caught --
extend EXTRACTORS below when a new choke point is added.

Usage: python3 tools/i18n_check.py   (exit 0 = in sync, 1 = drift found)
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LOCALE_DIR = ROOT / "locale"


def _unescape(s: str) -> str:
    return s.replace('\\"', '"').replace("\\\\", "\\")


def _dict_string_values(src: str, dict_name: str) -> set[str]:
    """Every quoted VALUE (not key) in a `const NAME := { ... }` dict literal --
    works for both `"key": "value"` (SETTING_HELP) and `["key", "value"]` (VERB_SEGS,
    handled separately below) shapes."""
    m = re.search(re.escape(dict_name) + r"\s*:?=\s*\{", src)
    if not m:
        return set()
    start = m.end() - 1
    depth = 0
    end = start
    for i in range(start, len(src)):
        if src[i] == "{":
            depth += 1
        elif src[i] == "}":
            depth -= 1
            if depth == 0:
                end = i
                break
    body = src[start:end]
    # "key": "value"  -- take the value (2nd quoted string on the line)
    return {_unescape(v) for _, v in re.findall(r'"((?:[^"\\]|\\.)*)"\s*:\s*"((?:[^"\\]|\\.)*)"', body)}


def _hint_literals(src: str) -> set[str]:
    """Every string literal main.gd passes as _hint()'s `text` arg -- covers both the
    static one-liners and the templated ones now wrapped in TranslationServer.translate()."""
    out = set()
    for m in re.finditer(r'_hint\(\s*"(?:[^"\\]|\\.)*"\s*,\s*(?:TranslationServer\.translate\()?\s*"((?:[^"\\]|\\.)*)"', src):
        out.add(_unescape(m.group(1)))
    return out


def _verb_seg_labels(src: str) -> set[str]:
    m = re.search(r'VERB_SEGS\s*:?=\s*\[(.*?)\]\s*$', src, re.MULTILINE)
    if not m:
        return set()
    return {_unescape(v) for _, v in re.findall(r'\["((?:[^"\\]|\\.)*)",\s*"((?:[^"\\]|\\.)*)"\]', m.group(1))}


def extract_source_keys() -> set[str]:
    menu_src = (ROOT / "src/view/menu.gd").read_text(encoding="utf-8")
    sfx_src = (ROOT / "src/view/sfx.gd").read_text(encoding="utf-8")
    hud_src = (ROOT / "src/view/hud.gd").read_text(encoding="utf-8")
    main_src = (ROOT / "src/main.gd").read_text(encoding="utf-8")

    keys: set[str] = set()
    keys |= _dict_string_values(menu_src, "SETTING_HELP")
    keys |= _dict_string_values(sfx_src, "_VO_CAPTIONS")
    keys |= _dict_string_values(sfx_src, "_BARK_CAPTIONS")
    keys |= _hint_literals(main_src)
    keys |= _verb_seg_labels(hud_src)
    # Hand-wired choke points -- one-off translate() calls, not dict/array literals, so no
    # extractor above can see them. ⚠️ This list is the check's blind spot: a NEW one-off
    # translate("...") in a view script is invisible to i18n_check until someone adds it here,
    # so the .po drift it would have caught goes unreported (that is exactly how "CREW HIT! %ds"
    # shipped untranslated). Add the literal here in the same commit that adds the call.
    keys |= {"K.I.A.", "BAIL OUT! %ds", "CREW HIT! %ds", "SELECT", "BACK"}
    return keys


def parse_po(path: Path) -> set[str]:
    src = path.read_text(encoding="utf-8")
    return {_unescape(m) for m in re.findall(r'^msgid "((?:[^"\\]|\\.)*)"', src, re.MULTILINE) if m}


def main() -> int:
    source_keys = extract_source_keys()
    if not source_keys:
        print("i18n_check: extracted ZERO source keys -- the extractors are broken, not the .po files")
        return 1
    pos = sorted(LOCALE_DIR.glob("strings.*.po"))
    if not pos:
        print("i18n_check: no res://locale/strings.*.po files found")
        return 1
    drift = False
    for po in pos:
        po_keys = parse_po(po)
        missing = source_keys - po_keys
        stale = po_keys - source_keys
        if missing:
            drift = True
            print("%s: MISSING %d key(s) used in source but absent from this .po:" % (po.name, len(missing)))
            for k in sorted(missing):
                print("   + %r" % k)
        if stale:
            drift = True
            print("%s: STALE %d key(s) in this .po no longer used in source:" % (po.name, len(stale)))
            for k in sorted(stale):
                print("   - %r" % k)
        if not missing and not stale:
            print("%s: in sync (%d keys)" % (po.name, len(po_keys)))
    return 1 if drift else 0


if __name__ == "__main__":
    sys.exit(main())
