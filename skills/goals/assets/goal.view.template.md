# Goal: {{title or id}} (`{{id}}`)

**Status:** {{status}} · **Iteration:** {{iteration.count}} / {{stop_policy.max_iterations}} · **Turns:** {{iteration.turns_used}} / {{stop_policy.max_turns}} · **Updated:** {{updated_at}}

## Objective

{{objective}}

## Done when

<!-- one line per definition_of_done item; [x] when status == met, [ ] otherwise -->
- [ ] **{{dod.id}}** — {{dod.check}} _({{dod.evidence_kind}})_
  <!-- when evidence exists, append: — latest: {{last evidence entry}} -->

## Constraints

<!-- one bullet per constraints entry; omit section when empty -->
- {{constraint}}

## Assumptions

<!-- one bullet per assumptions entry; omit section when empty -->
- {{assumption}}

## Stop policy

- max_iterations: {{stop_policy.max_iterations}} · max_turns: {{stop_policy.max_turns}} · deadline: {{stop_policy.deadline or "none"}} · token_budget: {{stop_policy.token_budget or "none"}}
- on bound reached → {{stop_policy.on_bound_reached}}

## Blockers

<!-- present only when status == blocked; one bullet per blockers entry -->
- {{blocker}}

## Recent history

<!-- last 5 history entries, newest first -->
- **iter {{n}}** ({{ts}}) — verdict: {{evaluation.verdict}}{{#evaluation.unmet}}; unmet: {{unmet list}}{{/evaluation.unmet}} — {{evaluation.notes}}

## Completion

<!-- present only when status == complete; render completion.summary, then met_criteria, changed_files, checks, remaining_risks as lists -->

---
_Generated from `.goals/{{id}}.json` — do not edit by hand; regenerate after every state write._
