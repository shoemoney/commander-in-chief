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
    "openai/gpt-6.1-sol",
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

PROMPT = PROMPT = """You are a harsh, senior game director reviewing a shipped 2D game, mid-development.

GAME: "Commander In Chief" — a vertical run-and-gun (a modern Ikari Warriors
remake), Godot 4.7 / GDScript, 640x360 internal resolution integer-scaled up.
Top-down camera. Two soldiers march north through six war zones. A shared coin
economy ("War Chest"): every kill mints, every revive spends. 4 modes, campaign
+ endless survival + boss rush + arcade, 1-2 player local co-op, Steam-shipped.

The attached images are REAL CAPTURES taken by tools/screenshots.gd, which stages
authored sim states and renders them through the actual view layer. Not concept
art, not mockups.

Review these FIVE areas in order. For each, give at most 3 findings, and for each
finding: WHAT you can SEE (name the element in the specific image) -> WHY it reads
wrong or fails the player -> THE FIX (concrete and implementable).

 1. ASSETS TO IMPLEMENT. An operator has a private library of ~1,600 game-asset
    archives (CraftPix 2D packs, Kenney CC0, ambientCG CC0 PBR, OpenGameArt).
    CRITICAL LEGAL CONSTRAINT you must respect in any suggestion: the CraftPix
    licence says "Distribution of source files is NOT permitted" and separately
    forbids using the assets to train or improve any AI system. The repo is
    PUBLIC and MIT. So CraftPix CANNOT be used and CANNOT be used as a generation
    reference. Only CC0 is usable: Kenney (crosshair, UI, top-down tower-defense,
    UI audio, impact, sci-fi) and ambientCG (2,000+ PBR ground/material tiles).
    If you think a specific KIND of asset would lift the game, name the kind and
    say which CC0 source. If the honest answer is "none", say none.

 2. GAMEPLAY MECHANICS. Is the core loop sound, is anything broken, over- or
    under-tuned, or missing that a player would notice within 10 minutes?

 3. USER INTERFACE. Legibility at 640x360, information hierarchy, what is noise.

 4. USER EXPERIENCE. What does it FEEL like to pick up and play — onboarding,
    feedback, control clarity, pacing, the first 60 seconds.

 5. DIFFICULTY LEVEL. Is it fair, is it readable where it needs to be, and is the
    one-hit-death + paid-revive economy tuned or brutal?

Rules:
- Look at every image before answering. Do not generalise from the first.
- Be harsh. The value of this review is entirely in its negativity. If you think
  it looks good you are not looking hard enough.
- Do NOT pad. Fewer real findings beat a full list of filler.
- Say when something is already good rather than inventing a problem for it.
- Be specific enough that an engineer could act without re-deriving your reasoning.

End with: one line per area (ASSETS / MECHANICS / UI / UX / DIFFICULTY) giving a
1-5 score and a single most valuable change, then a one-line verdict
(Goty contender / solid indie / visibly amateur).
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


def recall_precedents() -> str:
    """HARD PRE-STEP. What this loop already tried, and what it disproved.

    This is the memory architect's whole argument made mechanical. A bank nobody
    reads is the same as no bank, and nothing fails when you skip it -- which is
    exactly the condition that produced this loop's worst outcome: three separate
    confidently-wrong fixes to a black frame, one of which was committed. So this
    is not advice printed at the top of a file. It writes a receipt, and a run
    whose receipt is missing is a run that did not do the work.

    Recall is also where the DISPROVEN hypotheses come back, which is the whole
    value of keeping memory: winning ideas end up in code and are visible in the
    diff, so they are already carried. Losing ideas evaporate unless recorded, and
    re-deriving one costs a commit cycle.

    Degrades loudly rather than silently: if hindsight is unreachable the caller
    still gets a receipt saying so, because a run that says "memory unavailable"
    is honest and a run that silently skipped recall is not.
    """
    out = Path("/tmp/loop-precedents.md")
    q = ("what has this loop already tried and DISPROVEN for the current task, "
         "and what reviewer findings were already rejected")
    try:
        r = subprocess.run(
            ["uvx", "hindsight-embed", "-p", "cic", "memory", "recall", "cic", q],
            capture_output=True, text=True, timeout=180, cwd=REPO)
        body = r.stdout if r.returncode == 0 else (
            "!! hindsight recall UNAVAILABLE (exit %d). This run proceeded WITHOUT "
            "precedents, so any hypothesis below has NOT been checked against "
            "prior disproven work. Treat that as a real risk, not a formality.\n"
            % r.returncode)
    except Exception as e:                      # noqa: BLE001 - never block on memory
        body = ("!! hindsight recall ERRORED (%s). This run proceeded WITHOUT "
                "precedents.\n" % e)
    out.write_text("# Precedents (Hindsight bank: cic)\n\n" + body)
    print("PRECEDENTS -> %s (%d bytes)" % (out, len(body)))
    return body


def ask_codex(model: str, shots: list[str]) -> None:
    """The advisory reviewer: codex CLI, images attached natively via -i.

    codex is ChatGPT-authenticated here and rejects gpt-6-1-sol outright
    ("not supported when using Codex with a ChatGPT account"), so the reviewer is
    pointed at OpenRouter with the Responses wire format codex now requires
    (wire_api="chat" was removed upstream). Images go in as -i rather than as
    base64 in a request body, which is what lets the reviewer actually SEE the
    frames rather than reason about filenames.
    """
    recall_precedents()   # M2.1: hard pre-step, receipted. See its docstring.
    imgs = [s for s in shots if Path(s).exists()]
    cmd = ["codex", "exec", "-m", model, "--sandbox", "read-only",
           "--skip-git-repo-check", "-c",
           'model_providers.openrouter={ name="OpenRouter", base_url="https://openrouter.ai/api/v1", env_key="OPENROUTER_API_KEY", wire_api="responses" }',
           "-c", 'model_provider="openrouter"']
    for i in imgs:
        cmd += ["-i", i]
    r = subprocess.run(cmd, cwd=REPO, input=PROMPT, capture_output=True, text=True, timeout=1800)
    text = r.stdout
    slug = model.replace("/", "_")
    out = Path(f"/tmp/loop-{slug}.md")
    out.write_text(text)
    led = json.loads(LEDGER.read_text()) if LEDGER.exists() else {"asked": []}
    led["asked"].append({"model": "codex/" + model, "when": time.strftime("%Y-%m-%d %H:%M"),
                         "shots": [Path(s).name for s in imgs], "out": str(out)})
    LEDGER.write_text(json.dumps(led, indent=1))
    print(f"=== codex {model} -> {out} ===")
    print(text[-9000:])


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
        "max_tokens": 9000,
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
