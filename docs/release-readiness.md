# Release readiness — evidence and remaining work

## Subsequent local verification

The current builds, store art and packed Blender sources, screenshot selection
with replay evidence, trailer draft and store-field writeups are consolidated in
`build/release-review.FZF6US/CommanderInChief-review/` with a sibling ZIP.
`release-review-package.md` records the verified hashes, copied-evidence checks
and explicit review-only status. This does not close the owner/platform gates.

Solo Endless ready-up now shares the co-op hold-progress feedback, with an explicit
release-to-keep-shopping cue. The actual hold duration and simulation are unchanged.
`ready-feedback.md` records the reproduced defect, state-machine regression and
five inspected renderer cases. Refreshed candidates under
`build/steam-ready.jqZpJ9/candidates/` now include that repair and pass the actual
packed hold/release check. The older pack fails that new check as intended.
See `steam-candidate-validation.md` for the current hashes and exact test scope.

The initial explicit Steam-enabled candidates for macOS, Linux and Windows remain under
`build/steam-native.DjatEv/candidates/`, including required runtime libraries.
Their packs pass the resource-selection gate; the Mac game pack boots and advances
under a separate plain-Godot inspector. The exact exported Mac release executable
passes an isolated native binding probe without initializing Steam; a plain-Godot
release executable fails that same probe as intended. See
`steam-candidate-validation.md` for hashes, reproduction and evidence boundaries.
These candidates include the title fix described below, but have not been run as
full Steam-enabled games against an intended app/account or uploaded.

The current actual-gameplay screenshot selection is refreshed in
`build/steam-current.pKhThM/handoff/`, with five unretouched 1920×1080 images and
their complete capture/replay evidence. All selected takes match the current
captured source version and rendering setup; replay checks, source stability,
pixel equivalence and clean exits passed. `steam-gameplay-screenshots.md` records
the new input-isolation and cross-take identity checks. No upload or acceptance
is claimed, and this does not replace the outstanding owner/platform gates.

A later title-only clarity repair suppresses the attract demo's screen-anchored
combat alerts over the logo, while retaining actual gameplay/pause overlays.
The rendered gameplay control is byte-identical before and after; the staged
title reproduction and regression evidence are in `title-clarity.md`. The
macOS candidate immediately below predates this later source change.

The latest visually exercised **offline** macOS local candidate is
`build/native-current.3Qly07/CommanderInChief-macos.zip`. Its actual release app
rendered Campaign, accepted pause and closed cleanly while paused. The bundled
PCK also passed an isolated resource/runtime check including all character pose
textures, projectile textures and attachment of the HUD visibility shader.
The older PCK is rejected by the new missing-shader check. See
`native-candidate-validation.md` for hashes, logs, negative-control limits and
the remaining platform/Steam/signing gates. This is not evidence of a 10/10 game,
commercial readiness or an audience response.

Character aiming/locomotion and real-renderer evidence are recorded in
`character-readability.md`. That full suite passed with 1,191 methods and
38,241 assertions, and the real-scene E2E passed its 80 checks. Existing Blender
store-art source portability and PNG reproduction are now verified in
`blender-media-validation.md`; this does not establish store acceptance or replace
the outstanding human/platform checks below.

The Steam bridge was then checked against the official GodotSteam 4.22.1
macOS module for Godot 4.7.2. The original real-binding probe rejected fifteen
method names and one signal; the repaired bridge and mock now pass the native
method/signal surface check without initializing Steam. Inactive input and failed
or other-user stats replies have regression coverage. The subsequent full suite
passed 1,194 methods and 38,262 assertions, with a clean shutdown gate.
See `godotsteam_api_version.md` for the binary/source pin and limits.

Achievement persistence was subsequently separated by Steam identity. A new
regression reproduced another account inheriting and submitting cached unlocks
before the repair. The repaired implementation preserves the legacy anonymous
cache, validates schema and ownership, writes through a temporary file, and
recovers malformed saves from the last good backup. Newer-schema and
differently owned files are preserved read-only rather than overwritten.
The focused suite passed 23 methods and 95 assertions; the current full suite
passed 1,199 methods and 38,284 assertions with zero failures and a clean shutdown
gate. `tools/verify_achievement_persistence.gd` also passed separate-process
write/relaunch checks for the owning account, a second account and anonymous
play, using fictional identities in an isolated profile. This does not verify
live Steam account switching or Cloud synchronization. Bests/settings and the
last replay remain OS-profile-shared; see `steam_cloud_paths.md` for the scope.

Steam Input device callbacks now refresh action handles through the production
callback pump. Regression tests reproduced eight failed assertions before the
repair, then verified late connections, stale-input removal, replacement
handles, stable surviving player seats, duplicate-event batching and inert
failed setup. The native GodotSteam API surface probe also passed with the new
method and signals (`build/godotsteam-4.22.1/api-hotplug.json`), without Steam
initialization. The latest full suite passed 1,201 methods and 38,302 assertions,
zero failures and a clean shutdown gate. Physical device/seat mapping and
Steam Input coexistence with raw movement/aim still require hardware testing.

## Updated launch scope: local assets are not yet upload-approved

The requested end state now explicitly includes all Steam assets and writeups
prepared for launch. Local artifacts and source readiness must be distinguished
from a verified production build and Steamworks account/review state. No
publication, audience response or platform approval is established here.

A September 7 inspection measured the actual PNG files in
`build/steam-media/deliverables/`, rather than trusting their manifest. The four
store capsules are 920×430, 1232×706, 462×174 and 748×896; the library capsule,
hero and logo are 600×900, 3840×1240 and 1280×540. These match the corresponding
size criteria in the [Steam asset directory](https://partner.steamgames.com/doc/store/assets)
and [library specifications](https://partner.steamgames.com/doc/store/assets/libraryassets).
Dimension checks alone do not approve image content or placement.

The main capsule and library hero were opened this pass. The main title is
legible and not clipped. The hero is text-free, but the illustrated head extends
beyond the top edge and is not contained in the central protected region. Its
framing needs correction and a client-size crop preview before acceptance;
the [library specifications](https://partner.steamgames.com/doc/store/assets/libraryassets)
describe the protected region and separate logo placement. No artwork was changed
in this inspection. See `blender-media-validation.md` for earlier reproduction
evidence, which remains distinct from this storefront-layout finding.

Subsequent repair: the original artifact above remains unchanged as evidence.
A new panoramic hero was generated, exported through Blender, reproduced in a
fresh process and checked in wide/narrow logo previews and a protected-center
crop. The corrected asset is in the checksummed art handoff described by
`steam-hero-validation.md`. This closes the local cropping defect, not Steam's
account-side preview or approval requirements.

There is no separate library-header file in that deliverables folder. Steam
documents a fallback to the store header, so that absence is not by itself a
missing-art defect; choose and preview that mapping explicitly. Promotional
card/overlay artwork must not be substituted for gameplay screenshots. Steam
requires at least five actual gameplay screenshots and specifies a minimum
1920×1080, 16:9 format on its
[store graphical assets page](https://partner.steamgames.com/doc/store/assets/standard).
An approved screenshot selection, finalized store-field writeups and an upload
manifest have not yet been assembled in this deliverables folder.

The initial template inspection found only `4.7.stable` and `4.7.1.stable`.
The matching official `4.7.2.stable` desktop templates were subsequently
installed and fresh macOS, Windows and Linux candidates exported. The native
pass also removed bundled review/workflow data and exposed a direct-shutdown
audio cleanup diagnostic. See `native-candidate-validation.md` for exact
artifacts, completed checks and remaining gates. These are plain-Godot offline
candidates, not Steam-enabled approved production builds.

Follow-up: production Quit and window-close now stop audio and drain it before
exit, including while paused at zero time scale. All three isolated quit-route
probes pass, the full regression run exits successfully, and a freshly exported
Mac app was observed rendering its menu and exiting cleanly through its native
window-close button. See `native-candidate-validation.md` for the replacement
artifact and limits; forced engine `--quit-after` is a separate, unresolved path.

The subsequent opening-clarity pass replaced unconditional paid-revive teaching
with current recovery rules and retired obsolete advice without blocking the
next lesson. Three real-renderer QA captures were inspected. The full suite
passed 1,206 methods and 38,323 assertions, with zero failures and a clean
shutdown gate. See `recovery-clarity.md`; human comprehension remains unverified.

## September 7, 2026: export-content repair

Baseline: `cf23387` plus the existing uncommitted gameplay/UI work. Godot
`4.7.2.stable.official.ed1daf0bf`; gda MCP `0.15.0`. This is a local verification
record, not a release approval or a claim of zero bugs.

An actual Linux ZIP main-pack export reproduced three packaging problems:

- `assets/input/actions.vdf` was absent. SteamBridge reads this file as bytes;
  Godot's `all_resources` selection alone does not include it.
- The locally installed `addons/godot_mcp` scripts, their class-cache references,
  a scratch probe, and a prior build resource were included in the export.
- The `#` comment before the fourth export preset prevented Godot from seeing
  that preset. Godot's configuration comment syntax is `;`.

All presets now explicitly include the controller manifest, exclude development
and prior-build directories, and use valid comment syntax. Runtime addons such
as GodotSteam are not blanket-excluded. The native-arm64 preset still requires
custom executable templates as its comment explains; exporting its data pack
does **not** prove that a native executable can be produced with stock templates.

### Verification completed

- Full existing suite: 1187 test methods, 38072 assertions, no failures; the
  private-profile wrapper's shutdown-leak check passed.
- Real-scene E2E: 80 checks, no failures; clean teardown.
- Actual ZIP packs for all four presets passed byte-for-byte manifest checks,
  required project/scene presence, development-file exclusion and class-cache
  exclusion. Archive CRCs were checked.
- The new verifier rejects the original defective package. Its unit tests
  independently reject missing/stale manifests, missing project/scene files,
  bundled development code and stale development class-cache references.
- gda MCP enumerated all four presets, created the corrected Linux pack and
  reported the main scene ready without startup diagnostics.
- The corrected pack was booted from a separate folder, without source-tree
  resource fallback. Its manifest was readable and its campaign advanced through
  real physics frames; the process exited without leak diagnostics.

The CI lint job now checks all presets' exported contents. This is a ZIP/PCK
resource-selection check, separate from the existing native executable smoke jobs.
CI has not been rerun remotely for these uncommitted changes.

Reproduce the package gate:

```sh
python3 -m unittest discover -s tools -p test_verify_export_content.py -v
python3 tools/verify_export_content.py --godot /opt/homebrew/bin/godot
```

For an independently generated ZIP pack, inspect it with
`python3 tools/verify_export_content.py --archive /absolute/path/game.zip`.
To exercise packed runtime loading, run the external
`tools/verify_export_runtime.gd` with `--main-pack /absolute/path/game.zip`
and `--path` set to an otherwise empty directory, through `tools/run_tests.sh`
to isolate saves and enforce quiet shutdown. Require its `EXPORT RUNTIME PASS`
line **and** no script/runtime errors; the exit code alone is not sufficient.

## Release requirements still unproven

These remain part of the full release objective; the packaging repair does not
replace them with a smaller definition of success.

- Execute the newly exported Steam module candidates on every shipping platform.
  Matching module templates and sidecar packaging are now present; the Mac
  release binary's isolated binding inspection passes. Full game initialization
  and intended-account behavior remain unproven. No GDExtension is used by these
  module candidates, and mock tests do not replace live-platform verification.
- Verify achievements, Steam Input reconnect/rebinding, leaderboard behavior,
  user-specific saves/Cloud and presence against the intended Steam app.
- Verify the fresh native candidates on Windows, macOS, Linux, Proton and
  Steam Deck, including controllers, suspend/resume and long sessions. Matching
  plain-Godot and Steam module desktop templates are installed; live Steam
  execution and forced-engine shutdown diagnostics remain open. Normal Mac
  window-close now passes; this does not establish other-platform behavior.
- Complete observed newcomer and co-op acceptance from `ten-item-acceptance.md`.
  No human results were fabricated or inferred from bot tests.
- Continue visual, animation, audio, combat-readability and performance review
  throughout the campaign and all modes, not only the opening scene.
- Complete and review the requested Blender/MCP and fal/Replicate-via-aigate
  image/video production work, integrate approved assets, record provenance and
  inspect them in actual gameplay. No new media was generated in this repair.
- Verify store assets, disclosures, release metadata, Steam build/upload/review
  requirements and acceptance on the intended account. Local tests prove none
  of the external Steam publication state.
- Gather sustained external playtest/QA evidence for exceptional game quality.
  “Game of the Year” is a subjective aspiration, not an automated pass condition.

Online co-op is still a future update in the production plan, not a working
feature to advertise at launch. See `docs/PLAN.md` (repository root-relative) for broader planned scope and its
explicit distinction between implemented functionality and aspirational phases.

The subsequent cannon-feedback pass repairs silent empty/reloading driver inputs
and contextualizes the transient vehicle-control reminder. See
`cannon-feedback.md` for regression evidence, inspected renderer captures and
the remaining human-listening/comprehension gate. Earlier native candidates
predate this change; the source repair is not a new release artifact.
The final full suite passed 1,211 methods and 38,355 assertions, with zero
failures and a clean shutdown gate; the real-scene E2E passed all 80 checks.

## Store-writeup draft handoff

`docs/steam-store/README.md` (repository-relative) now indexes short/about copy,
mature-content and AI disclosure drafts, implementation evidence and an owner
review checklist. The provenance audit corrected the blanket stock-voice claim:
radio speech, commit-recorded commander cloning and an unconfirmed intro are
separate groups. Missing generation/permission records remain explicit.
This is prepared review material, not completed Steam survey declarations,
publication or legal clearance. Final screenshots/trailer, localized copy,
platform/feature verification and owner/account decisions remain open.

## Actual gameplay screenshot draft

Five actual-gameplay images are now assembled in
`build/steam-gameplay.6jrjaB/handoff/` with unmodified raw frames, full input
replays and per-frame/source fingerprints. Four real-renderer runs passed
replayed-score and captured simulation-checksum checks; all eighty source/display
pairs matched exact integer presentation. The selected images were visually
inspected. See `steam-gameplay-screenshots.md` for reproduction, six verifier
tests and limits. This advances local media preparation; final content/rights
review, account previews, trailer and Steam acceptance are still open. The
captures also expose remaining combat-text clutter and limited sector palette
distinction; successful integrity checks do not establish exceptional game quality.

## Combat reward readability

`streak-readability.md` records a subsequent source repair: combined streak/bonus
receipts, drawable-only message budgeting and milestone recognition across
batched kills. Focused tests and real-scene end-to-end checks passed, with staged
typography/expiry captures and a replay-verified live run. Earlier screenshot
drafts and exported binaries predate this repair and are not silently relabeled
as current release artifacts. Human acceptance and the broader launch gates
remain open.

The final streak-readability regression passed 1,213 methods and 38,387
assertions with zero failures and clean shutdown; real-scene E2E passed 80 checks.

## Chapter environment progression

`environment-progression.md` records the repair to Chapter Select's environment
state and the retained terrain cache. All six chapters were rendered and their
opening frames inspected; full replays and exact presentation pixels were checked.
The environment source suite passed 1,213 methods and 38,427 assertions. Later
chapters now use their existing authored treatments immediately on entry.

Two initial capture shutdown warnings were traced to audio playback handles and
an accelerated game-time cleanup timer. The tool now waits on monotonic elapsed
time, with a new accelerated/paused regression in CI. Fresh repeats of both
affected chapters shut down cleanly, as did boot and real-scene E2E checks.
These improvements do not refresh earlier exports/store selections or close
the human-playtest, asset-rights, Steam-account and platform acceptance gates.

## Gameplay trailer draft

`gameplay-trailer-draft.md` records a new 23-second 1080p60 gameplay cut with
synchronized game audio, a freshly reproduced packed Blender logo, source replays
and per-frame evidence. The exact-frame-count export and full decode passed;
eight decoded boundary frames were inspected. This is a local draft, not an
audibly reviewed or rights-cleared final trailer. No upload/publication occurred.
The excluded endless take also identified weak bot framing and shop-heavy footage
for a subsequent game-polish review. Gameplay source is unchanged by this pass.

## HUD visibility follow-up — 2026-09-07

Players beneath the top HUD now reveal a local transparent area in solo and
co-op, including downed bodies. Four staged edge cases and a real 660-iteration
gameplay capture verify the repair; the saved replay and captured checksums pass.
Full regression suite: 1,214 methods, 38,441 assertions, zero failures.
See [HUD player visibility](hud-player-visibility.md) for evidence and limitations.
Movie Maker capture initially stalled; those incomplete recordings are not
release evidence. The subsequent movie-capture follow-up below supplies a
verified replacement trailer. No new native export or Steam upload is claimed.

## Movie capture follow-up — 2026-09-07

Movie capture now uses one explicit draw per process iteration with automatic
rendering disabled, correct movie-file indexing, isolated OS gameplay input,
simulation-identity checks, and an independent watchdog/completion gate.
Four current takes completed with 2,880 checked frames in total, matching source
fingerprints, exact PNG/audio timing, and verified replay states. Input isolation
has a positive/negative-control test; the source gate has 11 passing fixtures.

The current local trailer is
`build/trailer-current.YSYUiS/draft/CommanderInChief-gameplay-draft.mp4`, with
`poster.png` and `manifest.json` beside it. Its 1,380 frames and both 23-second
tracks were checked; full decode passed, and eight boundary frames were inspected.
See [trailer evidence](gameplay-trailer-draft.md) and
[capture validation](movie-capture-validation.md).

No new voices were generated. Listening review, commercial voice/asset permissions,
Steam app/account details, human playtesting, and platform acceptance remain open.
The requested Steam App ID, public support email, and existing voice-permission
status have not yet been supplied in this follow-up. No upload or publication occurred.
