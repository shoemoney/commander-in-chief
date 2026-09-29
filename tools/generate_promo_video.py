#!/usr/bin/env python3
"""Submit/poll a bounded Replicate promo-art animation using aigate credentials.

No automatic paid retries. A receipt is created before submission; an uncertain
submission must be reconciled manually, never silently submitted a second time.
This produces illustrated marketing footage, NOT gameplay footage.
"""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import urllib.request

MODEL = "wan-video/wan-2.2-i2v-fast"
VERSION = "4eaf2b01d3bf70d8a2e00b219efeb7cb415855ad18b7dacdc4cae664a73a6eea"
PROMPT = ("An animated illustrated game poster. Camera completely locked. Preserve the "
          "same older golden-blond commander, face, swept comb-over hair, hands, olive "
          "vest, red necktie and rifle exactly, holding the same heroic pose. Only the "
          "distant amber smoke curls slowly and a few tiny dust motes drift. Gentle "
          "atmospheric light flicker in the distant desert. No speaking, no walking, "
          "no firing, no camera movement, no morphing, no new objects, no lettering. "
          "Keep the hand-painted vintage action-poster style and dark left area.")


def toolkit():
    path = Path.home() / ".codex/skills/image-toolkit/scripts/generate.py"
    spec = importlib.util.spec_from_file_location("image_toolkit", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def request(key, path, body=None):
    req = urllib.request.Request("https://api.replicate.com/v1/" + path,
        data=None if body is None else json.dumps(body).encode(),
        headers={"Authorization": "Bearer " + key, "Content-Type": "application/json",
                 "User-Agent": "CommanderInChief-AssetPipeline/1.0"})
    with urllib.request.urlopen(req, timeout=45) as response:
        return json.load(response)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("submit", "poll"))
    parser.add_argument("--receipt", required=True, type=Path)
    parser.add_argument("--image", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    lib = toolkit()
    key = lib.aigate_key("replicate")
    if not key:
        parser.error("Replicate credential is unavailable from aigate")
    if args.action == "submit":
        if not args.image or not args.output:
            parser.error("submit requires --image and --output")
        params = {"prompt": PROMPT, "seed": 7312026, "num_frames": 81,
                  "resolution": "720p", "frames_per_second": 16,
                  "go_fast": True, "interpolate_output": False,
                  "disable_safety_checker": False}
        record = {"state": "submission_pending", "model": MODEL, "version": VERSION,
                  "input": params.copy(), "source": str(args.image.resolve()),
                  "source_sha256": hashlib.sha256(args.image.read_bytes()).hexdigest(),
                  "destination": str(args.output.resolve()), "credential_source": "aigate",
                  "content_type": "illustrated_promo_not_gameplay"}
        args.receipt.parent.mkdir(parents=True, exist_ok=True)
        # Exclusive creation prevents an accidental second charged submission.
        with args.receipt.open("x") as receipt:
            json.dump(record, receipt, indent=2)
        params["image"] = lib.file_to_data_url(args.image)
        result = request(key, "predictions", {"version": VERSION, "input": params})
    else:
        record = json.loads(args.receipt.read_text())
        prediction = record.get("id", "")
        if not re.fullmatch(r"[a-zA-Z0-9_-]+", prediction):
            parser.error("receipt has no prediction ID; reconcile submission before retrying")
        result = request(key, "predictions/" + prediction)
    for field in ("id", "status", "error", "created_at", "completed_at", "metrics", "output"):
        if field in result:
            record[field] = result[field]
    record["state"] = result["status"]
    args.receipt.write_text(json.dumps(record, indent=2) + "\n")
    print(json.dumps({k: record.get(k) for k in ("id", "status", "error")}), flush=True)
    if record["status"] == "succeeded":
        url = record["output"]
        if not isinstance(url, str) or not url.startswith("https://"):
            raise ValueError("expected an HTTPS video output")
        dest = Path(record["destination"])
        dest.parent.mkdir(parents=True, exist_ok=True)
        lib.download(url, dest)
        record["output_sha256"] = hashlib.sha256(dest.read_bytes()).hexdigest()
        args.receipt.write_text(json.dumps(record, indent=2) + "\n")
        print(dest)
    return int(record["status"] in ("failed", "canceled"))


if __name__ == "__main__":
    raise SystemExit(main())
