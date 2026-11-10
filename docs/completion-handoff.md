# Completion handoff

This document describes the final local review handoff. It does not declare launch
approval. The work inventory is [completion-status.json](completion-status.json);
its 2026-10-04T04:15:28Z snapshot predates the final source and package checks below.

## Current local handoff

The final 1.4.4 stock and Steam exports, source/cache binding, exact-pack checks and
actual Mac UI observations are retained under
`build/completion-audit/release/final-20261004-02/`. Select stock builds only from
`native-candidates-02/`; the earlier `native-candidates/` attempt failed on an
incorrect preset name and has no success manifest. All pre-splash-fix packages in
`fresh-20261004-01/` remain historical.

The current source regression, six-mode legal-input matrix, separately staged
endings, producer-bound exact-pack six-mode matrix and fresh-OS-process save/Watch
checks are VERIFIED in `build/completion-audit/full-run/final-current-verification.json`.
The exact-pack and fresh-process tests use plain Godot over the final exported PCK.
Actual native Mac intro/title and quit observations have their own receipts; they
do not supply native-template full-game or restart acceptance.

The concrete review folder is
`build/completion-audit/release/final-20261004-02/CommanderInChief-1.4.4-review/`,
with a sibling ZIP. Its `START-HERE.md` and manifest identify the selected sources
and copied hashes. Primary builds are the final stock desktop candidates. Same-source
Steam candidates and current source/stage/pack/restart/presentation receipts are
supporting evidence. The current presentation gallery is staged UI review evidence;
approved store screenshot, trailer and selected store-art sources are absent.

The source, package and current-file receipts supersede the older work inventory
for their stated checks. Remaining launch requirements retain the scope below and
the unchecked owner fields in `docs/steam-store/owner-review.md`. Local archive
verification does not close them.

## Freeze the source and candidate evidence

1. Finish the source regression, simulation lint, production-scene playthrough and
   presentation checks. Retain their original logs and the state each check exercised.
2. Export the final candidates from the same source snapshot. The candidate manifest
   must include identical `source_before` and `source_after` records, the project
   version, three desktop export records, exported-file hashes and each export-log hash.
3. Retain the native smoke receipts for the exact exported artifacts. Record platform,
   executable and pack hashes, close-route results and diagnostics. A source-tree run
   or a foreign-platform cross-export does not prove native candidate execution.
   Godot 4.7.2 stock release templates disable external pack and script overrides.
   Use `verify_native_export.py --engine godot` for an explicitly labeled standard
   engine check of the exact release pack, then observe the real native application
   separately. Keep the actual interaction, process exit and diagnostics in its
   receipt; OS Quit and the window close button are distinct observations.
4. Include the Font Awesome license and attribution manifest in each release archive.
   Verify those bytes against `assets/fontawesome/` and retain the packaging receipts.
5. Stop source changes while capturing candidate media. If a runtime source file
   changes, create fresh candidates and repeat the affected evidence checks.

The assembler compares the candidate's entire recorded runtime file map against the
current tree, including newly added files. It rechecks selected artifact bytes and
runtime source files before writing a success manifest. A failed copy can leave an
incomplete directory; it has no success manifest and must not be presented as a handoff.

## Give fresh captures explicit provenance

Each selected source directory needs a `manifest.json`. The candidate builder's
`source_state` shape defines a complete identity:

```json
{
  "revision": "<Git revision captured when evidence was produced>",
  "project_version": "<captured project version>",
  "files": {"<repository-relative runtime path>": "<SHA256>"},
  "fingerprint_sha256": "<SHA256 of the sorted JSON file map>",
  "dirty": true
}
```

Capture that complete state before and after producing evidence. Retain the two
identical records as `source_before` and `source_after`; a consolidated manifest can
also declare the captured record as `source_identity`. Use the builder's fingerprint
calculation rather than a differently formatted JSON hash. Dirty source is permitted
when its exact file hashes are recorded and unchanged. Do not attach today's identity
to older images, footage or logs: such a stamp would not establish their provenance.

Source directories declare the files they contribute:

- Screenshots use `screenshots` records with `file` and `sha256`. Add supporting raw
  frames, replays, capture receipts and indexes to a flat `files` path-to-SHA256 map.
- A trailer uses `file` and `sha256` for the video. Its flat `files` map must hash any
  included poster, cut list, clip receipts or raw inputs.
- Runtime evidence uses a flat `files` map for logs, summaries and exact-artifact
  receipts. Include the captured complete source identity when promising the same
  source snapshot as the candidates.
- Historical store art uses `assets` records with `file`, `sha256`, `source_file` and
  `source_sha256`. It remains labeled historical art even when supplied alongside
  fresh game captures. Keep its provenance and rights records with the review.

Paths must be relative regular files inside the selected directory. Absolute paths,
parent traversal and symlinks are rejected. Only receipted files are copied. Existing
partial capture identities remain useful historical evidence, but cannot satisfy an
exact same-source promise. Missing sources are labeled absent in `START-HERE.md`.

## Assemble only from explicitly selected sources

Use new output paths. Replace these placeholders with the final verified source
directories; they are not ready-made artifact locations:

```sh
rtk proxy python3 tools/assemble_release_review.py /absolute/path/final-review \
  --builds /absolute/path/fresh-candidates \
  --art /absolute/path/historical-store-art \
  --screenshots /absolute/path/fresh-screenshot-handoff \
  --trailer /absolute/path/fresh-trailer-handoff \
  --evidence /absolute/path/fresh-runtime-evidence \
  --require-same-source

rtk proxy python3 tools/assemble_release_review.py /absolute/path/final-review --verify
```

Omit an optional source only when its absence is intentional and its review remains
open. `--require-same-source` checks every supplied screenshot, trailer and runtime
evidence selection against the candidates' complete revision, version and file
fingerprint. Historical art has a separate declaration. There are no automatic
historical source-directory defaults.

The review folder and sibling ZIP retain each original source manifest, source
identity and manifest hash. The handoff manifest inventories copied file hashes and
sizes. Read-only `--verify` checks folder and ZIP bytes without refreshing evidence
or changing an old handoff. Verification of a historical package proves only its
recorded bytes; it does not make its evidence current.

## Close the remaining launch requirements with observations

Update [completion-status.json](completion-status.json) only with actual evidence
and its limits. Follow [completion-external-checks.md](completion-external-checks.md)
for the platform and controller matrix, unfamiliar-player and co-op observations,
audio and localization review, intended Steam AppID/account behavior, Playtest
evidence, rights declarations and release operations. Signing and notarization need
their actual results. Source checks, package hashes and manifest identities do not
establish those outcomes.

Resolve the unanswered owner fields in [owner-review.md](steam-store/owner-review.md)
and record platform acceptance before declaring launch approval. Assembly performs
no upload, publication, signing, Steam account operation or human acceptance session.
