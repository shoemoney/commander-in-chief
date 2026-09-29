#!/usr/bin/env python3
"""The improvement loop: render the real game, ask a vision model, save the verdict.

USAGE
    tools/loop_review.py render                      # capture the signature shots
    tools/loop_review.py ask <model-id> <shot> ...   # one advisory review, images attached
    tools/loop_review.py next                        # the next model in the rotation

WHY A HARNESS AND NOT A SUBAGENT. Every verdict in this loop has to be
ATTACHABLE TO A NUMBER. Three times now a change went green, rendered, and
either did nothing (a tint that moved 337 pixels of 230,400) or looked wrong in
a way an eyeball endorsed — the "dirt card popped as an orange rectangle" claim
that measured a 17.6 -> 17.0 change, i.e. nothing. So the shots are rendered
once, by the real game, and the same bytes go to every reviewer. A model that
disagrees with another model is then decidable instead of a matter of taste.

COST. 640x360 PNGs are tiny; six of them is well under a cent per call. We ask
for exactly five findings, because a reviewer given "find everything" returns a
list whose last three items are always filler.
"""
from __future__ import annotations

import base64
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
SHOTS = Path("/tmp/loop-shots")
LEDGER = Path("/tmp/loop-ledger.json")
GODOT = "/Applications/Godot.app/Contents/MacOS/Godot"
KEY = os.environ.get("OPENROUTER_API_KEY") or Path.home().joinpath(".openrouter").read_text().strip()

# One model per vendor family, strongest first. Diversity is the point: five
# opinions from the same lab agree with each other, which is not evidence.
# VERIFIED vision-capable — probed, not assumed. OpenRouter lists 292 models
# whose architecture block claims image input, and most of those lie: glm-4.7
# reports input_modalities including "image" and then routes exclusively to
# endpoints that 404 on it. Every entry here was probed with a real PNG and got
# a real completion. One per vendor family where possible — five opinions from
# the same lab agree with each other, which is not evidence.
ROTATION = [
    "google/gemini-3-flash-preview",
    "x-ai/grok-4.7",
    "qwen/qwen3.8-omni-flash",
    "deepseek/deepseek-v4.1-flash",
    "inclusionai/ling-3.0-flash-vl",
    "perceptron/perceptron-mk1.5",
    "xiaomi/mimo-v2.6-pro",
    "cohere/command-a-plus",
    "z-ai/glm-5.3-flashx",
    "z-ai/glm-4.6v",
    "qwen/qwen3.8-flash",
    "x-ai/grok-4.6",
]

PROMPT = """You are a harsh, senior VFX/art director reviewing a shipped 2D game.

GAME: "Commander In Chief" — a vertical run-and-gun (a modern Ikari Warriors
remake). It renders at a 640x360 internal resolution, integer-scaled to the
window, so everything is seen small. Top-down camera, you play two soldiers
marching north through six war zones, with a shared coin economy.

The attached images are REAL CAPTURES of the real game, taken by
tools/screenshots.gd, which stages authored sim states and renders them through
the actual view layer. They are not concept art and not mockups.

Judge it against the bar for a GROUNDED 2D top-down shooter in 2026 — Metal Slug
and Gunstar Heroes for the arcade lineage, Nuclear Throne and Hells Yeah for the
modern indie bar.

Give me EXACTLY FIVE improvements. For each one:
  1. WHAT you can SEE — name the specific element in the specific image. If you
     cannot see it, do not invent it.
  2. WHY it reads wrong — what the player's eye does with it.
  3. THE FIX — concrete and implementable, not "improve the art".

Rules:
- Look at every image before answering. Do not generalise from the first.
- Be harsh. The value of this review is entirely in its negativity. If you think
  it looks good you are not looking hard enough.
- Rank by how much each one costs the image, not by how easy it is to fix.
- If something is genuinely excellent, do not pad the list with it. Five real
  findings, not five things.
- Be specific enough that an engineer could act without re-deriving your
  reasoning.

Then, separately and briefly: what is the ONE change that would most raise the
perceived production value, and why is it worth more than the other four?

End with a one-line verdict: Goty contender / solid indie / visibly amateur.
"""


def render() -> None:
    SHOTS.mkdir(parents=True, exist_ok=True)
    for p in SHOTS.glob("*.png"):
        p.unlink()
    env = dict(os.environ, SHOT_DIR=str(SHOTS))
    r = subprocess.run(
        [GODOT, "--path", ".", "--rendering-method", "gl_compatibility",
         "-s", "res://tools/screenshots.gd"],
        cwd=REPO, env=env, capture_output=True, text=True, timeout=400)
    n = len(list(SHOTS.glob("*.png")))
    print(f"rendered {n} shots -> {SHOTS}")
    if "ALL SHOTS DONE" not in r.stdout:
        print("RENDER FAILED:", r.stdout[-800:], r.stderr[-800:])
        sys.exit(1)


def ask(model: str, shots: list[str]) -> None:
    content = [{"type": "text", "text": PROMPT}]
    for s in shots:
        p = Path(s)
        if not p.exists():
            print("missing shot:", s); continue
        b64 = base64.b64encode(p.read_bytes()).decode()
        content.append({"type": "text", "text": f"--- IMAGE: {p.name} ---"})
        content.append({"type": "image_url",
                        "image_url": {"url": f"data:image/png;base64,{b64}"}})
    payload = {
        "model": model,
        "messages": [{"role": "user", "content": content}],
        "max_tokens": 4000,
        "temperature": 0.4,
    }
    req = urllib.request.Request(
        "https://openrouter.ai/api/v1/chat/completions",
        data=json.dumps(payload).encode(),
        headers={"Authorization": f"Bearer {KEY}", "Content-Type": "application/json"})
    t0 = time.time()
    try:
        with urllib.request.urlopen(req, timeout=300) as r:
            body = json.load(r)
    except urllib.error.HTTPError as e:
        print(f"HTTP {e.code}: {e.read()[:900].decode(errors='replace')}")
        sys.exit(2)
    dt = time.time() - t0
    msg = body["choices"][0]["message"]
    # Reasoning models (mimo, command-a) burn thousands of tokens and return
    # `content: null` with the answer in `reasoning` or in a content-part array.
    # Reading only `content` silently produced two empty 47-byte verdict files
    # that looked like refusals.
    text = msg.get("content") or ""
    if not text and msg.get("reasoning"):
        text = msg["reasoning"]
    if isinstance(text, list):   # some providers return [{type:text,text:...}]
        text = " ".join(c.get("text", "") for c in text if isinstance(c, dict))
    if not text:
        print("EMPTY after all fallbacks:", json.dumps(msg)[:600]); sys.exit(2)
    used = body.get("usage", {})
    slug = model.replace("/", "_")
    out = Path(f"/tmp/loop-{slug}.md")
    out.write_text(f"# {model}  ({dt:.0f}s, {used.get('total_tokens','?')} tok)\n\n{text}\n")
    led = json.loads(LEDGER.read_text()) if LEDGER.exists() else {"asked": []}
    led["asked"].append({"model": model, "when": time.strftime("%Y-%m-%d %H:%M"),
                         "shots": [Path(s).name for s in shots], "out": str(out),
                         "tokens": used.get("total_tokens")})
    LEDGER.write_text(json.dumps(led, indent=1))
    print(f"=== {model}  ({dt:.0f}s, {used.get('total_tokens','?')} tokens) -> {out} ===\n")
    print(text)


def nxt() -> None:
    led = json.loads(LEDGER.read_text()) if LEDGER.exists() else {"asked": []}
    done = {a["model"] for a in led["asked"]}
    for m in ROTATION:
        if m not in done:
            print(m); return
    print("ALL DONE — every model in the rotation has been asked"); sys.exit(3)


if __name__ == "__main__":
    cmd = sys.argv[1]
    if cmd == "render":
        render()
    elif cmd == "ask":
        ask(sys.argv[2], sys.argv[3:])
    elif cmd == "next":
        nxt()
    else:
        print(__doc__); sys.exit(1)
