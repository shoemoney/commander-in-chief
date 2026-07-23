# Workflow: regenerate desert asset groups via fanned-out subagents

Runbook for regenerating the Iran-desert nano-banana sprites
(`assets/legacy-art/cactus_*`, `decor/tumbleweed.png`, `decor/dry_shrub.png`,
`p2/cactus_dead*`) from inside a live Claude Code session, dispatching one
subagent per asset group instead of running
`tools/generate_desert_assets.py` as a single top-to-bottom script. Use
this when a group needs a restyle or a bad render needs a reroll and you
want the groups worked in parallel by independent agents rather than
serially by one.

The three groups and their consistency intent (kept in sync with
`tools/generate_desert_assets.py::GROUPS` and
`assets/legacy-art/desert_assets_source.md` -- update all three together if a
group ever changes):

| group | jobs | material to keep consistent across the group |
|---|---|---|
| cacti | cactus_large, cactus_small | dusty sage-green low-poly cactus |
| scrub | scrub, tumbleweed, dry_shrub | sun-bleached dry-brush low-poly |
| dead  | cactus_dead1, cactus_dead2, cactus_dead3 | sooty black/ash-grey charred low-poly |

## Steps

1. **Fan out one subagent per group, in parallel.** Dispatch three Task
   subagents in the same turn (do not wait on one before starting the
   next). Copy-paste the three calls below verbatim (only the
   `description`/`prompt` differ per group -- the command each one runs
   is already filled in, nothing to re-type):

   ```
   Task(subagent_type="general-purpose", description="Regen cacti desert assets", prompt="""
   Run `python3 tools/generate_desert_assets.py --group cacti --skip-import`
   from the repo root (/Users/shoemoney/Projects/commander-in-chief). This
   generates and post-processes only the cacti asset group (its own
   nano-banana renders, chroma-keyed, trimmed, and letterboxed to the
   correct canvas size) and writes cactus_large.png / cactus_small.png
   straight into assets/legacy-art/. Report back the exact output paths and
   sizes it printed, and whether it exited 0.
   """)

   Task(subagent_type="general-purpose", description="Regen scrub desert assets", prompt="""
   Run `python3 tools/generate_desert_assets.py --group scrub --skip-import`
   from the repo root (/Users/shoemoney/Projects/commander-in-chief). This
   generates and post-processes only the scrub asset group and writes
   scrub.png, decor/tumbleweed.png, decor/dry_shrub.png straight into
   assets/legacy-art/. Report back the exact output paths and sizes it
   printed, and whether it exited 0.
   """)

   Task(subagent_type="general-purpose", description="Regen dead desert assets", prompt="""
   Run `python3 tools/generate_desert_assets.py --group dead --skip-import`
   from the repo root (/Users/shoemoney/Projects/commander-in-chief). This
   generates and post-processes only the dead asset group and writes
   p2/cactus_dead1.png, p2/cactus_dead2.png, p2/cactus_dead3.png straight
   into assets/legacy-art/. Report back the exact output paths and sizes it
   printed, and whether it exited 0.
   """)
   ```

   Each subagent is an independent worker over one `GROUPS` entry --
   `run_group()` in the script is exactly this unit of work, so the
   subagent's job is just "invoke the script with this one flag and
   report the result," no image-editing judgment required of the
   subagent itself (the prompt-consistency notes live in `GROUPS`, not in
   the subagent's head).

2. **Wait for all three subagents to report success.** If any group
   reports a non-zero exit, do not proceed to step 3 for that group's
   assets until it's fixed (a bad render can be retried by re-running
   just that group -- the other two groups' output is untouched, since
   each group only ever writes its own PNGs).

3. **Bake `.import` sidecars once, after every group has finished** (not
   per group -- concurrent `godot --headless --import` calls would race
   on the shared `.godot/imported/` cache, which is exactly why step 1's
   subagents are told to pass `--skip-import`):

   ```sh
   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . --import
   ```

   then run `tools/generate_desert_assets.py`'s `fix_import_settings()` /
   `assert_lossless_legacy-art_import()` pass on the changed files (or just
   re-run the whole script without `--group`/`--skip-import`, which is
   idempotent over already-correct PNGs and will re-bake every `.import`
   to the lossless legacy art-bake convention) and re-import once more.

4. **Verify.**

   ```sh
   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s res://tests/run_tests.gd
   ```

   Must print `PASS` with 0 failures and no `SCRIPT ERROR` line;
   `test_a1_legacy-art_bakes_are_lossless()` is what actually checks the
   `.import` convention landed correctly.

## Dry-running the dispatch itself

To rehearse steps 1-2's fan-out without spending an API call or needing
the image-toolkit skill installed, have each subagent run with
`--dry-run` instead against a **scratch** `--out-dir` (never the default
`assets/legacy-art` -- `--dry-run` refuses to write inside the real `assets/`
tree and will exit 1 if a subagent forgets to pass a scratch path):

```sh
python3 tools/generate_desert_assets.py --group cacti --dry-run --out-dir /tmp/desert-dry-run
```

This is also exactly what `dispatch_groups()` in the script itself does
when invoked without `--group` -- it re-invokes itself once per group as
a `subprocess.Popen` instead of a Task subagent, so this workflow and that
function are two dispatch mechanisms over the identical per-group unit of
work (`GROUPS`). Use the script directly for a CLI/CI regen; use this
workflow when working inside an agent session and you want the groups
handled by parallel subagents instead of parallel OS processes.

## Smoke test on record

Steps 1-2's three-way parallel dispatch was rehearsed for real (three
`--dry-run --skip-import` subprocesses launched together via `&`/`wait`
against a scratch `--out-dir`, mirroring exactly what three parallel Task
subagents would each independently invoke) on 2026-07-22:

```
=== cacti ===
[cacti] fanning out 2 sprite render(s) (dry-run)...
[cacti] post-processing (chroma-key -> trim -> letterbox -> validate)...
  [cacti] /tmp/desert-dry-run-smoketest/cactus_large.png (120x120)
  [cacti] /tmp/desert-dry-run-smoketest/cactus_small.png (96x96)
EXIT(cacti)=0
=== scrub ===
[scrub] fanning out 3 sprite render(s) (dry-run)...
[scrub] post-processing (chroma-key -> trim -> letterbox -> validate)...
  [scrub] /tmp/desert-dry-run-smoketest/scrub.png (72x72)
  [scrub] /tmp/desert-dry-run-smoketest/decor/tumbleweed.png (200x200)
  [scrub] /tmp/desert-dry-run-smoketest/decor/dry_shrub.png (220x220)
EXIT(scrub)=0
=== dead ===
[dead] fanning out 3 sprite render(s) (dry-run)...
[dead] post-processing (chroma-key -> trim -> letterbox -> validate)...
  [dead] /tmp/desert-dry-run-smoketest/p2/cactus_dead1.png (120x120)
  [dead] /tmp/desert-dry-run-smoketest/p2/cactus_dead2.png (120x120)
  [dead] /tmp/desert-dry-run-smoketest/p2/cactus_dead3.png (120x120)
EXIT(dead)=0
```

All three groups exited 0 with the expected paths/sizes -- the fan-out
wiring (parallel launch, per-group isolated output, no cross-group file
collisions) is confirmed. This dry-run only exercises dispatch/post-
processing plumbing, not the actual nano-banana render quality (that
needs a live API key and the real Task subagents from step 1, which do
real image generation instead of synthetic placeholders).
