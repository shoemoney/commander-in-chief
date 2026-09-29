# Steam store writeup handoff

For the frozen combined builds/art/media/writeup review package, see
[release review package](../release-review-package.md). Its start-here guide keeps
submission fields separate from evidence and outstanding owner decisions.

Prepared September 7, 2026 against local `cf23387` plus the uncommitted source
changes documented in `../release-readiness.md`. **Draft for owner review; not
submitted, approved, published or cleared for launch.**

## Store fields

- [Short description](short-description.txt): one plain-text paragraph. Project
  budget is 300 characters, checked locally; confirm the account editor's limit.
- [About this game](about.bbcode): Steam-style BBCode, gameplay-first description.
- [Mature-content description](mature-content.txt): content summary for review,
  not completed regional ratings or a substitute for the full survey.
- [AI disclosure](ai-disclosure.txt): prerecorded/generated asset explanation,
  not a representation that permission or licensing checks are complete.

Paste only the individual field contents into their matching editor fields,
after the review below. Do not paste this handoff's notes or source links into
the description. Preview BBCode in Steamworks before publishing.

Recheck local structure with `python3 tools/verify_store_copy.py` from the
repository root. Its tests are `python3 -m unittest discover -s tools -p
test_verify_store_copy.py`. This check covers missing fields, plain short copy,
the local character budget, external URLs and BBCode balance only. It does not
verify gameplay claims, legal permissions, translations or platform acceptance.

Local validation passed: all required files present, short description 261
characters, supported BBCode balanced, and five verifier tests passing. No game
runtime code or assets were changed during this writeup pass.

## Review before use

Read [claim evidence](claim-evidence.md) and [owner review](owner-review.md).
The current local source implements the described modes. That is separate from
platform certification, physical controller testing and a verified shipping build.
Do not add online co-op, Deck Verified, live Steam features, a release date,
performance minimums, review scores, player counts or awards without evidence.

The AI statement is based on the asset records and a runtime source search. No
live generative service integration was found in `src/` or `project.godot`.
Recheck the actual shipping executable, its native dependencies and bundled
content before answering the survey's live-generation question. Source inspection
alone does not prove the behavior of a different release binary.

## Related art

The locally verified eight-image art handoff and Blender sources are at
`build/steam-hero.KRzhYW/steam-art-handoff/` (repository-relative), with checksums
in its manifest. See `../steam-hero-validation.md` for reproduction and limits.
That existing manifest is a historical snapshot; this writeup package does not
overwrite it or assert completion of its remaining release gates.

The recent recovery/cannon QA images are staged test cases. They are not the
store selection. Five refreshed actual-gameplay draft screenshots are prepared at
`build/steam-current.pKhThM/handoff/`, with complete raw frames, replays and
checksums. See [capture validation](../steam-gameplay-screenshots.md) and
[selection](gameplay-selection.json). The older screenshot handoff is retained as
an archive. Final owner review, trailer listening review, store
localization and account-side previews remain open; no age-suitability designation
or Steam acceptance is asserted.

A subsequent actual-gameplay trailer draft is prepared at
`build/trailer-assembly.CgKxAr/draft-v2/CommanderInChief-gameplay-draft.mp4`.
See [trailer evidence and remaining review](../gameplay-trailer-draft.md) and
[cut list](trailer-cut-list.json). It uses current captured gameplay and existing
game audio; final listening, rights review and account approval remain open.

The current replacement trailer and poster are in `build/trailer-current.YSYUiS/draft/`.
This revision includes the HUD visibility repair and verified input-isolated movie
captures. The [trailer notes](../gameplay-trailer-draft.md) identify the exact file,
hash, cut list and remaining release checks; older trailer folders are retained archives.

## Platform guidance checked

Steam asks for plain text in the short description, discourages time-sensitive
copy, and prohibits external links and promotion of other games in descriptions.
The supplied copy follows those constraints; its source notes remain outside the
store fields. [Steam description guidance](https://partner.steamgames.com/doc/store/page/description).

The Content Survey distinguishes pre-generated from live-generated AI content
and requires accurate disclosure of mature content, including uploaded material
that is inaccessible in play. Disclosing content does not itself approve it.
[Steam Content Survey](https://partner.steamgames.com/doc/gettingstarted/contentsurvey).
