# Commander In Chief — Completion Plan

Status: living. Updated each loop iteration. Epistemic status of every claim is
retained in the Hindsight bank `cic` (tags: `claim:verified` / `claim:unverified`
/ `claim:disproven`) so a later session inherits the state, not just the plan.

## Where this stands (2026-10-03)

Eight commits across two iterations, all verified by planting a defect rather than
by asserting one cannot happen. Suite: **1,289 methods / 39,434 assertions / 0
failures**, `lint_sim` clean, CI green on all jobs.

**Iteration 1** found three shipped features that were dead code, all the same
shape — a table row naming something the code that reads it can never be handed:

| Claim | What it actually was |
|---|---|
| a3-33 "nine roles read as nine roles" | 4 of 14 hues unreachable; worst pair 2.8°; four hues on one cosmetic job |
| a3-27 "stop teaching verbs during a boss" | never fired in any of four modes |
| a1-02 "the heavy already reads" | the row's absence was the CAUSE of no rim, not a decision |

**Iteration 2** worked the four leads the first audit left as UNPROVEN. One was a
real hole, one was already fine, and two turned out to be missing measurements:

| Lead | Verdict |
|---|---|
| **U1 event-seam coverage** | **REAL, and the worst of the set.** The gate asserted on what a 600-tick × 2-mode sample fired: **15 of 101 event types (15%)**. Pushed to 12k ticks × 4 modes it reached 38, so 63 types need a tank, a purchase, a route or a boss kill. Add an event, forget the handler, go green — on 85% of the seam. Now the static harvest is the gate and the sample is corroboration. |
| **U2 chip-band ratchet** | **NOT BROKEN.** All 14 ids the draw can hand `_fits2` are banded, and planting the described blind spot was caught by the *existing* fixture test. Kept the source-level check as hardening; claims no fix. |
| **U3 sprite silhouettes** | **NOT BROKEN** (23/23 solid) — but the check had no plant, and neutering its threshold left the suite green. Now has planted controls through a shared predicate. |
| **U4 `Fixed.length` overflow** | **A HAZARD OF UNKNOWN SIZE.** The tripwire existed; the reason for it was false (removed in iteration 1). Measured: 4000 px worst case against a 46340 px bound — **8.6%, 11× headroom.** Now a ratchet on the *margin*, not the sign. |

The shape that recurred across both iterations is not "dead code" but **a gate that
cannot fail**: U1 asserted only what it happened to see, U3 asserted only negatives.
Both were found by planting, and in U3's case the first version of the fix
reproduced the same blind spot inside itself — the control inlined its own copy of
the census, so it passed no matter what the real threshold became.

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

## Milestone 1 — Close the verification debt  [DONE, 2026-10-02]

The loop's credibility rests on not overclaiming. Everything below is now
**proven rather than asserted** — and two of the claims came back *disproven*,
which is the useful outcome.

- **M1.1 Make the GL capture work.** ✅ `tools/role_sheet.gd` captures. The cause
  was arithmetic, not the framebuffer: `PX_PER_UNIT` was 2.0, which put the band
  20px BELOW the bottom of a 640x360 viewport, so `clampi()` slid the crop onto
  the bottom HUD strip. Every assertion passed because that strip is lit. That is
  also how it reported "28 rim-hue clashes" with confidence — it was measuring
  sand. Committed `877851c1`.
- **M1.2 The role-rim claim.** ❌ **DISPROVEN**, then fixed. It was not merely
  unverified. 4 of 14 `_ROLE_RIM` rows were **dead code** — the hue was applied
  from inside `Art.outlined(...)`, so every self-keylined role (ghillie, sapper,
  frogman, m_bombsuit) could never receive one. A 5th row (`elite`) was never a
  style_key. And the hues did not separate: worst pair **2.8°**, three exact
  duplicates, one of them between two sprites guaranteed co-present. It also gave
  four hues to what is **one job wearing four cosmetic skins chosen by a position
  hash**. Rebuilt against the sim's own co-occurrence data: **34°** minimum
  separation, 30° clear of the lethal red, 31° clear of the hero's cool contour.
  Committed `b17c5009`.
- **M1.3 Sweep the repo for unproven claims.** ✅ Done, and it paid. A
  dead-config audit found **22 more rows** that read as live configuration and
  could never take effect — `BOSS_VERB_SUPPRESS` (an entire boss-detection
  feature inert in all four modes), 3 of 8 glyph-hint rows, a 12-cell brand
  table with no reader, 8 of 69 `Art.OUTLINE` rows the draw path never evaluates,
  and the tree's only zero-reader const. Commits `0afb65dd`, `d33691eb`.
- **M1.4 The recurring shape.** All three findings are the SAME bug: a
  configuration row naming something the code that reads it can never be handed.
  What made it survivable is that every one of them sat behind a test that
  checked *adjacent* facts (a row mirrors a live TEX key; a kind is a string; a
  suite is green) rather than the reachability that matters.

**Done when:** no `claim:unverified` remains for a shipped change. ✅ for M1.

## Milestone 1b — Gates that cannot fail  [DONE, 2026-10-03]

The follow-on question M1 raised: if dead code hides behind adjacent checks, what
about the checks themselves? Audited the leads the M1 sweep left UNPROVEN.

- **M1b.1 The event seam.** ❌→✅ The one real hole. `test_event_coverage.gd`
  asserted only on what a 600-tick × 2-mode torture sample fired — **15 of 101
  types**. The static harvest is now the gate; the sample is corroboration. Proven
  with a controlled plant: renaming the victory event (emitted only when the
  colossus dies, which no 600-tick sample reaches) passes under the old
  sample-only gate and fails by name under the new one. Committed `06e98dfd`.
- **M1b.2 The chip-band ratchet.** ✅ Already correct — all 14 `_fits2` ids are
  banded, and the fixture caught the planted blind spot itself. Kept a
  source-level check because a fixture can only see what it stages, including the
  one non-literal call site (`"mutator" if si == 0 else "mutator2"`) a literal
  harvest misses. Committed `170ff9ec`.
- **M1b.3 Sprite silhouettes.** ✅ All 23 are solid. But the check had no plant and
  neutering its threshold left the suite green — an assertion that only ever
  reports negatives. Now routed through one shared predicate with planted
  controls; both knobs verified load-bearing. Committed `fb539a53`.
- **M1b.4 The `Fixed.length` overflow.** ✅ Measured. The tripwire existed; its
  stated reason was false (M1). Worst case across four modes is **4000 px against
  a 46340 px bound — 8.6%, 11× headroom** — so it is now a ratchet on the margin,
  which catches an 8× squeeze that a sign-check would miss. Committed `c9b134b2`.

**Done when:** every gate touched has a plant that turns it red. ✅

## Milestone 2 — Make the reviewer trustworthy end to end

- **M2.1 Feed real-run frames by default.** ❌ **NOT DONE — the premise is false.**
  Measured `tools/screenshots.gd` before changing anything: 3/3 runs, 14 PNGs
  each, 300–400KB per frame. Those are the exact frames the reviewer has been
  grading, and they are real. The phantom findings this item was written to
  prevent came from the *reviews*, not the harness. Left alone deliberately.
- **M2.2 Retain every reviewer verdict.** ✅ `/tmp/loop-ledger.json` already records
  model, timestamp, shot list, output path and token count per ask.
- **M2.3 Detect a corrupted review.** ✅ `verdict_defect()` in
  `tools/loop_review.py` rejects a response that is structurally not a verdict —
  the model's own skill boilerplate, a stub, a refusal echo, unnumbered prose —
  and still **saves** it as `.REJECTED.md` so a bad rotation is visible. Five
  cases, including the real boilerplate incident, are asserted by
  `loop_review.py selftest`, which CI now runs: a gate nobody has watched reject
  is not a gate.

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

- **M4.1 Enemy combos forcing different responses** (#2) — now partly
  unblocked: the role contours the claim depends on actually apply.
- **M4.2 Per-shot outcome legibility** (#4) — hit / armour-resist / stagger /
  kill as four distinct responses.
- **M4.3 Colossus windup / recovery cycle** (#5) — a learnable tell-response-open
  window per attack.

**Blocked on:** a human playtest with audio. I can build the instrumentation, but
I cannot declare these fair without someone playing it.

## Milestone 5 — Ship

- **M5.1 Green the pre-existing `gl-capture` CI failure.** ✅ Done — the run at
  the top of this file's history is `success` on all jobs.
- **M5.2 Cut a release.** v0.3.0 is the only GitHub release; tags through v1.3.0
  exist locally. **Not done — deliberately.** Cutting a release is an
  irreversible public action, so it is the one thing here that needs a human's
  explicit go-ahead.

## The rules this loop learned, and why they are ratchets not advice

- **Hand the reviewer real-run frames.** Proven: two phantom "THE ONE thing"
  findings, ~3 probes each to disprove.
- **A saved PNG is not a usable PNG.** Now enforced in code; refused 7 saves.
- **Stop adding hypotheses after three failures.** Write a minimal probe. This one
  cost two commit cycles of a confidently wrong fix.
- **Never quote a number from a measurement that cannot isolate the change.** I
  nearly shipped a coverage "win" off a metric dominated by a red vignette.
- **Check the design before the asset.** The ground texture fight was a design
  contradiction wearing an art problem's clothes.
- **A test that reads configuration cannot catch an unreachable row.** Added:
  with the whole role-rim draw call deleted, every table assertion still passed.
  The gate had to reach the DRAW PATH, so `role_rim_color()` is now a pure static
  the ratchet calls directly. Verified by planting the deletion.
- **A gate keyed by a hue dictionary is blind to an identical pair.** My own
  separation test built a dict keyed BY HUE and compared distinct keys, so two
  roles on the *same* hue merged into one entry — the exact shape of the shipped
  defect. Found only by planting it. Shares are now enumerated and must match a
  documented reason.
- **A measurement whose answer moves is not measuring the thing it names.** The
  pixel census returned 24/27/30 "clashes" across six identical runs. The fix was
  to stop using pixels for a question pixels cannot answer, not to average them.
- **I fixed a measurement artifact that did not exist.** Mid-loop I "fixed" the
  GL capture's flakiness by polling the framebuffer — and made it worse (2/5 →
  0/5). The original 2/5 was **CPU contention from my own concurrent test
  suite**, the exact failure AGENTS.md documents. Reverting was the correct
  move; the lesson is that a "fix" whose measurement came from a busy machine is
  a fix to nothing.
- **Measure the premise before fixing the item.** M2.1 said `screenshots.gd` was the
  source of phantom findings. Measured: 3/3 runs, 14 real frames each. The item was
  dropped rather than "completed", because acting on it would have replaced a
  working harness for no reason. The same discipline killed the U2 fix: that
  fixture was NOT broken — the planted blind spot was caught by the existing test —
  so the commit adds hardening and says "not a bug fix" rather than claiming credit.
- **A gate that has never been shown to reject is not a gate.** Found twice more in
  the second iteration, and once the FIX reproduced the bug inside itself: the first
  version of U3's control inlined its own copy of the alpha census, so it passed no
  matter what the real threshold became. A planted control has to travel through the
  same code the gate uses, or it is decoration.
- **An assert inside a test aborts the method WITHOUT failing the run.** This cost a
  U4 test that reported PASS while tripping a SCRIPT ERROR. Demonstrating that a
  function rejects its own bad input is not a test — the runner cannot see it — so
  the boundary is pinned as arithmetic and the assert left to do its real job.
- **Audit what a gate COVERS, not just whether it passes.** U1 was green on every
  run for the life of the suite and structurally covered 15% of the event seam. The
  question that finds these is "what would this NOT see?", not "is it red?".
