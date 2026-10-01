# Commander In Chief — Completion Plan

Status: living. Updated each loop iteration. Epistemic status of every claim is
retained in the Hindsight bank `cic` (tags: `claim:verified` / `claim:unverified`
/ `claim:disproven`) so a later session inherits the state, not just the plan.

## Autonomy: how to make me continue without prompting

**The mechanism already exists — `.opencode/ralph-loop.local.md`.** It carries
`active: true`, an `iteration` counter, and `maxIterations: 100`. That file is
what keeps the loop running between turns. It is NOT a suggestion: while
`active: true`, the loop re-invokes me after each turn and I keep working.

Three things that make it real rather than ceremonial:

1. **The loop state file is the handoff.** A fresh session reads it and knows the
   next action without re-deriving it. This is the part that works reliably.
2. **The recall step is a hard pre-step in `tools/loop_review.py`,** so skipping it
   breaks the run the way a red test does. A memory bank nobody reads is the same
   as no bank, and nothing fails when you skip it — so it needs teeth.
3. **A ratchet, not a promise.** The one thing this loop reliably obeys is a red
   test. Anything I merely intend to do is not a mechanism.

Honest caveat: I have ignored this loop's own state file twice in one session. If
you want stronger guarantees than "the loop re-prompts me", the only reliable ones
are external — a cron that re-runs the loop, or a CI job that fails when an
iteration does not advance the version. I can wire the second; say the word.

## Milestone 1 — Close the verification debt  [IN PROGRESS]

The loop's credibility rests on not overclaiming. Right now one shipped change is
unverified.

- **M1.1 Make the GL capture work.** `tools/role_sheet.gd` always exits 2. NOT in
  my tool: a minimal probe with none of my code is also 0% lit, while
  `campaign_contact_sheet.gd` is 99% lit with near-identical boot. The cause is
  how the working tool primes its FIRST presented frame. **Next action:**
  instrument `campaign_contact_sheet.gd`'s `_warm()`/`_drive()` to print a lit
  count per step and find where it first goes non-black. Measurement, not a guess.
- **M1.2 Close the role-rim claim.** With a working capture, run the per-kind
  hue-clash check. Exit 0 = nine roles read as nine roles and the claim upgrades
  to `claim:verified`. Non-zero = it does not, and the rims get reworked.
- **M1.3 Sweep the repo for unproven claims.** Every commit message this session
  that said "renders" without a measurement. Downgrade or prove each.

**Done when:** no `claim:unverified` remains in the bank for a shipped change.

## Milestone 2 — Make the reviewer trustworthy end to end

- **M2.1 Feed real-run frames by default.** `loop_review.py` should capture via
  `campaign_contact_sheet.gd`, not `screenshots.gd`. The harness is the single
  biggest source of phantom findings this loop has produced.
- **M2.2 Retain every reviewer verdict.** Ranked lists go into `cic` tagged
  `claim:unverified` with the model and frame set, so a later iteration can ask
  "what has already been proposed and rejected" instead of re-litigating.
- **M2.3 Detect a corrupted review.** One response this session returned the
  model's own skill boilerplate instead of a review. `-o` to a file plus a shape
  check (must contain a numbered list) before acting on it.

## Milestone 3 — The remaining VISUAL items

- **M3.1 Survival-first HUD** (reviewer #7). `src/view/hud.gd` is heavily
  ratcheted: dynamic plate widths, an 18px text minimum, a stub-parity test, and
  a world-text gate. One verified pass or not at all. Prefer raising vitals
  emphasis WITHOUT moving plate geometry, so the arbitration is untouched.
- **M3.2 Foundry landmark** (#9) — a procedural industrial structure so the arena
  reads without its title.

## Milestone 4 — The SYSTEMS tier

All three need footage and audio, which a still cannot give. The reviewer has said
so every time, and the honest answer is that these need a human at the controls.

- **M4.1 Enemy combos forcing different responses** (#2) — only worth doing once
  M1.2 confirms roles are actually readable.
- **M4.2 Per-shot outcome legibility** (#4) — hit / armour-resist / stagger /
  kill as four distinct responses.
- **M4.3 Colossus windup / recovery cycle** (#5) — a learnable tell-response-open
  window per attack.

**Blocked on:** a human playtest with audio. I can build the instrumentation, but
I cannot declare these fair without someone playing it.

## Milestone 5 — Ship

- **M5.1 Green the pre-existing `gl-capture` CI failure.** Red since before this
  loop; it is why no GitHub release has ever been cut.
- **M5.2 Cut a release.** All three platforms, once CI is green.

## The rules this loop learned, and why they are ratchets not advice

- **Hand the reviewer real-run captures.** Proven: two phantom "THE ONE thing"
  findings, ~3 probes each to disprove.
- **A saved PNG is not a usable PNG.** Now enforced in code; refused 7 saves.
- **Stop adding hypotheses after three failures.** Write a minimal probe. This one
  cost two commit cycles of a confidently wrong fix.
- **Never quote a number from a measurement that cannot isolate the change.** I
  nearly shipped a coverage "win" off a metric dominated by a red vignette.
- **Check the design before the asset.** The ground texture fight was a design
  contradiction wearing an art problem's clothes.
