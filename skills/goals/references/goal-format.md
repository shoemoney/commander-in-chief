# Goal contract anatomy

> Read before drafting any `.goals/<id>.json`. The schema
> (`../assets/goal.schema.json`) is the machine contract; this file explains how
> to write each field well.

## Contents

- [Design principles](#design-principles)
- [File layout and identity](#file-layout-and-identity)
- [Field contract](#field-contract)
  - [schema_version](#schema_version)
  - [id and title](#id-and-title)
  - [objective](#objective)
  - [context](#context)
  - [assumptions](#assumptions)
  - [constraints](#constraints)
  - [definition_of_done](#definition_of_done)
  - [evidence_requirements](#evidence_requirements)
  - [stop_policy](#stop_policy)
  - [evaluator](#evaluator)
  - [iteration](#iteration)
  - [history](#history)
  - [blockers](#blockers)
  - [completion](#completion)
- [The human .md view](#the-human-md-view)
- [Writing rules](#writing-rules)
- [Versioning](#versioning)

## Design principles

- **A goal states the outcome and how to know it worked — not an implementation
  recipe.** Pin the outcome, the evidence, the true constraints, and the stop
  policy. Leave sequencing, internal design, and decomposition to the executor
  after it reads the repo or source material.
- **One goal per file.** Multi-objective goals cause thrash. Two outcomes means
  two files.
- **Done is binary.** "`ruff check .` exits 0" is binary; "code is clean" is
  not. Every done item must be checkable by a command, an artifact, a count, a
  parse, a runtime response, a source, or an explicit rubric line.
- **Smallest sufficient contract.** Add a clause only if removing it could
  change the outcome, the evidence, a true constraint, a boundary, iteration
  behavior, or the stop decision. Never shrink the outcome itself; compress
  only the surrounding text.
- **A task list is not done.** "Build UI, add API, write tests" is a plan. The
  contract first defines the user-visible outcome and its proof; implementation
  phases are allowed only after done is clear.

## File layout and identity

- `.goals/` sits at the active project root. Create it on first use.
- `<id>` is the filename: a slug matching `^[a-z0-9][a-z0-9-]{0,49}$`.
- `.goals/<id>.json` is the source of truth. `.goals/<id>.md` is a derived,
  optional human view — regenerate, never hand-edit.
- Timestamps are ISO-8601 (`YYYY-MM-DDTHH:MM:SSZ` or with offset).

## Field contract

### schema_version

Semver string equal to the `metadata.version` of the skill that wrote the file
(currently `1.0.0`). Validate a goal file against the schema of its own version
— see [Versioning](#versioning).

### id and title

`id` is immutable after creation (it is the filename). `title` is a short
human label; optional, changeable, never used by the gate.

### objective

One sentence naming the final, verifiable state: "X does Y, verified by Z."
Not "improve X". Written in the task's own terms. Immutable once the goal is
active — changing it is an amendment: stop, ask the user, log the decision.

### context

Facts the executor cannot derive: absolute paths, branch or commit, prior
decisions, pinned dependencies, the one or two anchors that genuinely must be
read first. Absolute paths only — cwd shifts between turns. A path earns its
place only if it is the scope boundary or where evidence comes from; enumerated
path lists go stale, so prefer one or two anchors plus "discover adjacent docs
as needed". Never invent a fact: write `<TODO: user fills in>`.

### assumptions

Low-risk ambiguity resolved by statement, not by question. Each entry is one
sentence the run treats as true until evidence contradicts it. If a wrong
assumption could change done, it was not low-risk — it belonged in the
clarify round.

### constraints

Hard rules and out-of-scope. Models bias toward action, so "do NOT touch X"
beats "focus on Y". Include:

- the scope rule — the simplest thing that meets the objective; no refactors,
  features, or abstractions beyond it
- the 1–3 boundaries this task could actually break, named concretely
  (forbidden flags, off-limits paths, no-deploy, no public behavior change)
- compatibility only when external behavior, safety, or validation requires it
- the anti-weakening rule: checks must not pass by deleting, weakening,
  bypassing, or narrowing required behavior, tests, or data
- for user-facing work: **no visible dead ends** — every visible control,
  artifact, route, or advertised capability either works through the real path
  or is honestly marked out of scope; never present placeholders, fake traces,
  demo data, or local-only state as the completed outcome

Use "must", "never", and "only" only for true invariants.

### definition_of_done

The heart of the contract. An array of 1–5 items; more than 5 means the scope
is too large — split the goal. Each item:

- `id` — `dod-N`, stable for the life of the goal
- `check` — one binary pass/fail criterion
- `evidence_kind` — `command` | `artifact` | `test` | `runtime` | `source` |
  `review`
- `status` — `pending` → `met` / `unmet`, set only by gate evaluations
- `evidence` — raw proof appended across iterations (command + exit code, file
  path, count, parse result)

Per-domain check targets:

| Domain | Check shape |
|---|---|
| bug fix | reproduce the failure first; done = the failing case passes with no related regressions |
| performance | metric + threshold + method + runs (e.g. p95 < 250 ms over 3 runs) |
| tests / CI | the exact command and its pass condition |
| migration / batch | counts verified by query or grep, with the coverage bound stated |
| research | the decision the work must enable; at least one pass tries to disprove the leading conclusion; missing evidence is reported "unconfirmed", never as a factual "no" |
| quality | an observable bar — lint/types/tests green, N reviewed examples |

Every named item in the objective (each file, command, deliverable, quantity)
gets its own done item. Itemized checks must not hide a broken whole: when
first-use coherence matters, add one holistic check ("the core flow runs end to
end"). A check that could not have failed proves nothing — where outcomes have
distinct classes (success / failure / timeout), require evidence that each
relevant class fired.

### evidence_requirements

- `proof_surface` — where the judge looks: `transcript` | `files` | `commands`
  | `runtime` | `mixed`
- `required` — concrete proof expectations: counts, named files, named screens,
  exact cases, timings, error messages, before/after states
- `substitutions_allowed` — default `false`. Demo data, fixtures, mocks, fake
  services, and nearby examples are supporting evidence only; they cannot
  complete a named requirement unless this is `true`

If no honest check exists, the first goal builds the smallest practical one
(rubric, baseline, reproduction). If building it needs unavailable credentials
or services, that is a blocker — say so instead of inventing a proxy.

### stop_policy

Bounds checked before every iteration's work. Defaults:

| Field | Default | Notes |
|---|---|---|
| `max_iterations` | 25 | evaluation cycles; one per gate run |
| `max_turns` | 100 | total working turns across the goal |
| `deadline` | `null` | ISO-8601 cutoff |
| `token_budget` | `null` | cumulative token cap; `null` = untracked |
| `on_bound_reached` | `failed` | terminal status when a bound trips; use `blocked` only when the bound is really an external wait |

Set explicit values when the user names scope, deadline, or budget. A tripped
bound ends the run with a summary — never with a silent stop and never with a
`complete`.

### evaluator

- `kind`:
  - `deterministic` — every done item is machine-checkable; the gate runs the
    commands and compares exit codes and outputs
  - `reviewer-subagent` — default; a separate read-only subagent judges raw
    evidence (see `evaluation-gate.md`)
  - `user` — subjective rubric or high-risk sign-off; the user is the judge
- `instructions` — what the judge checks, phrased as an evidence checklist.
  Never instructions to trust the worker.

### iteration

Counters updated on every write: `count` (evaluation cycles), `turns_used`,
`tokens_used` (0 when untracked). The pre-work bound check reads these.

### history

Append-only, one entry per iteration:

- `iteration`, `ts`
- `actions` — short strings: what was actually done
- `evidence` — raw pointers: command outputs, paths, counts
- `evaluation` — `{ verdict, unmet, notes }`; notes record material decisions
  and gaps so the next iteration does not re-explore

History is resume state, not a verbose log. Never rewrite or delete entries.

### blockers

The exact questions or decisions when `blocked`. Leave the smallest next user
action and, when practical, the exact command or check to rerun after that
action. A blocked goal with a vague blocker is a stalled goal.

### completion

Filled only at `complete`:

- `met_criteria` — each done item plus its decisive evidence
- `changed_files` — created or modified paths
- `checks` — exact commands and exits
- `remaining_risks` — honest residuals
- `summary` — plain words for a reader who watched none of the run; name any
  decision the goal left undefined that judgment settled

## The human .md view

Regenerate `.goals/<id>.md` from the JSON after every write, using
`../assets/goal.view.template.md`. It renders: status line, objective, the done
list as checkboxes with evidence, constraints, stop policy with counters, last
5 history entries, and blockers. It is a view — if it disagrees with the JSON,
the JSON is right; regenerate.

## Writing rules

- No slop words: robust, leverage, seamless, delve, harness, cutting-edge,
  game-changing.
- Decision rules over step sequences. Do not prescribe implementation order
  unless the user already did.
- Compact: if the contract reads long, cut clauses that would not change the
  run. A contract the executor cannot hold in its head fails its purpose.
- Write in the user's language.

## Versioning

- A goal file's `schema_version` equals the skill `metadata.version` that wrote
  it. Validate against the schema of that version, not necessarily the newest.
- **Patch bump** (1.0.x): clarifications only; schema unchanged.
- **Minor bump** (1.x.0): new optional fields. Old files still validate against
  the new schema; new files may not validate against an old schema — always
  validate against the file's own `schema_version`.
- **Major bump** (x.0.0): breaking changes. Before continuing a goal written
  under an older major version, migrate it: read the old file, write a new one
  conforming to the current schema, record the migration in `history`.
