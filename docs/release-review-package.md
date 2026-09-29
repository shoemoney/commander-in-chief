# Consolidated release review package

Current folder: `build/release-review.FZF6US/CommanderInChief-review/`.
Start with `START-HERE.md` inside it.

Archive: `build/release-review.FZF6US/CommanderInChief-review.zip`.
SHA-256: `c6b035914b3480e08d7d531aa289dc46b74df2667ac462d5a5c1f2340628efd1`.

This is a frozen **review package**, not a launch approval, upload, publication
or complete source archive. It contains the current Steam module candidates,
eight store/library PNGs and packed Blender sources, five selected actual-gameplay
screenshots with their source/replay evidence, the current trailer draft/poster,
store-field drafts, rights records and owner checklist. Historical receipts keep
their capture revisions and original project paths; not every deeper linked
artifact or the trailer's raw movie inputs is included.

The build contains the solo ready-up repair; the media predates that change and
does not demonstrate the new Endless panel. No media was regenerated, edited or
silently relabeled as captured from the new binaries.

## Verification

- The assembler checks build, art, Blender-source, selected screenshot and trailer
  bytes against their original manifests before copying. The store-field structure
  check also passes. No original artifact is modified.
- The final verifier checks 227 receipted files against the manifest and compares
  every archived file's bytes to the same hash, with an exact member-list check.
  The ZIP's own manifest is byte-identical to the folder manifest.
- The copied screenshot evidence passes replay-file hashes, recorded frame hashes
  and exact raw-to-display presentation checks for all 80 retained frames. This
  rechecks preserved evidence; it is not a new game run or human playtest.
- Five assembler/verifier tests pass: checked copies, destination preservation,
  changed-source rejection, path traversal rejection and modified-copy rejection.
  The five existing store-copy validator tests also pass.

Logs are beside the review folder: `assembly.log`, `verify.log`,
`copied-evidence.log`, `tests-final.log`.

```sh
rtk proxy python3 tools/assemble_release_review.py --verify build/release-review.FZF6US/CommanderInChief-review
rtk proxy python3 -m unittest discover -s tools -p test_release_review.py -v
```

To assemble again, pass a new, nonexistent output path under an existing parent.
`tools/assemble_release_review.py` intentionally selects explicit reviewed source
folders, not whichever timestamp happens to be newest. Update those selections
after validating replacements. Existing destinations and archives are refused.

## Outstanding requirements

The owner checklist remains authoritative for App ID/publisher account, support
contact, price/date, platform/language choices and permission records. Live Steam
integration, actual target hardware/controllers, signing, newcomer/co-op acceptance,
trailer listening and Steam review are still unverified. Neither packaging nor
automated tests establish audience reception or exceptional game quality.
