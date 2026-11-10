# Game completion plan

This plan retains the current game and launch requirements from `docs/PLAN.md`. Post-launch online co-op, console ports and explicitly cut features retain their existing scope. The optional launch-scope question remains unanswered; no promise has been silently removed.

The sealed 1.4.4 review remains verified against its retained source, exports and receipts. The working source now includes additional accessibility controls and is undergoing fresh integration checks. Historical receipts below do not establish a pass for this changed source or a new export. The goal is active: local implementation continues while separate account, owner, hardware and human acceptance items remain open.

The launch-contract audit in `build/completion-audit/launch-contract-audit/finding.md` separates authorized local promises from actual owner decisions. Single-stick input, tiered assistance, toggle controls, Classic aim, 75% pacing, independent effects, retained timing and save integrity are local work. The contradictory infinite-revive/Last Stand rule remains an owner decision. Post-launch online co-op and historical architecture proposals do not require a mechanical rewrite.

The user's request to save all store assets is verified in `build/completion-audit/store-assets-save/CommanderInChief-store-assets-2026-10-04-receipt.json`: the durable Downloads folder and literal ZIP preserve existing originals, packed Blender sources, draft/historical media, copy and provenance. Preservation does not establish current-build media, rights declarations, owner review or Steam approval.

## M0. Establish the baseline

Exit status: verified. Exit requires a complete requirement inventory, a reproduced baseline and the next implementation units ordered by dependency and risk.

1. **VERIFIED** Audit the actual simulation, menus, input, presentation and shipped modes against the production plan.
   Evidence: `build/completion-audit/gameplay.md`; `build/completion-audit/presentation.md`; `build/completion-audit/requirements-reconciliation.md`.
   Coverage: These are inventory/audit results; their historical defect descriptions are superseded only by named current proving artifacts.
2. **VERIFIED** Audit art, animation, audio, onboarding and accessibility requirements, including unmet acceptance.
   Evidence: `build/completion-audit/presentation.md`; `docs/ten-item-acceptance.md`; `docs/completion-external-checks.md`.
   Coverage: An inventory is complete even when the separate human or whole-campaign acceptance remains open.
3. **VERIFIED** Audit exports, Steam integration, CI, media, source provenance and platform requirements.
   Evidence: `build/completion-audit/release/final-20261004-02/release-report.md`; `build/completion-audit/requirements-reconciliation.md`; `docs/completion-external-checks.md`.
4. **VERIFIED** Reproduce the current full regression and bind its retained logs to the frozen source.
   Evidence: `build/completion-audit/full-run/post-splash-regression.json`; `build/completion-audit/full-run/final-current-verification.json`.
   Coverage: 1,304 methods / 40,531 assertions / zero failures; all 2,775 regression dependencies remain current.
5. **VERIFIED** Assign proved defects, local coverage gaps, unanswered scope choices and external launch gates.
   Evidence: `docs/completion-plan.md`; `docs/completion-status.json`; `docs/completion-external-checks.md`.

## M1. Complete gameplay

Exit status: open. Exit requires all gameplay items to pass their behavior checks and a full campaign completion through the production scene. Any intentionally staged test must declare the state it changes.

1. **VERIFIED** Verify all six Campaign gates, bosses, Last Stand, victory and debrief through normal production input.
   Evidence: `build/completion-audit/full-run/final-common-matrix-04/summary.json`; `build/completion-audit/full-run/final-packaged-common-matrix/summary.json`.
   Coverage: Campaign solo/co-op, Arcade chapter one, Boss Rush and actual Daily complete normally. God mode is off; staged endings are excluded.
2. **VERIFIED** Verify normal finite Campaign, Arcade, Boss Rush and Daily entries, exact replays, save and Watch.
   Evidence: `build/completion-audit/full-run/final-common-matrix-04/summary.json`; `build/completion-audit/full-run/final-packaged-common-matrix/summary.json`; `build/completion-audit/full-run/final-packaged-process-restarts/summary.json`.
   Coverage: Five finite cases cover Campaign solo/co-op and the three other finite entries. Pack gameplay/restarts use plain Godot, not native-template driving.
3. **VERIFIED** Verify bounded normal Endless progression.
   Evidence: `build/completion-audit/full-run/final-common-matrix-04/summary.json`; `build/completion-audit/full-run/final-packaged-common-matrix/summary.json`.
   Coverage: Two waves clear and wave three is entered. This does not establish long-session survival, late modifiers, cooperative ready-up or an Endless terminal save.
4. **VERIFIED** Verify Chapter Select menu rows and the recorded chapter-jump subsystem contracts.
   Evidence: `build/completion-audit/full-run/post-splash-regression.json`; `tests/test_menu_layout.gd::test_modes_and_chapter_select_screens`; `tests/test_biomes.gd::test_jump_to_chapter_offsets_every_stream_cursor`.
   Coverage: Current tests cover six menu rows and chapter-one/chapter-four stream behavior; these are fixture/subsystem checks.
5. **PENDING** Exercise every deep Chapter Select entry through the production scene and retain its resolved entry/progression.
   Evidence: `build/completion-audit/full-run/post-splash-regression.json`; `build/completion-audit/gameplay.md`.
   Required: Current six-mode runs begin Arcade at chapter one. Independent production entry/progression evidence for every deep chapter is not retained.
6. **VERIFIED** Verify independent per-seat legal inputs and paid recovery during normal local co-op completion.
   Evidence: `build/completion-audit/full-run/final-common-matrix-04/summary.json`; `build/completion-audit/full-run/final-packaged-common-matrix/summary.json`.
   Coverage: Each seat records exactly one decision per actual replay tick. Bots do not establish independent human input or physical controllers.
7. **VERIFIED** Verify deaths, recovery, remote rally, tank crews, roll transitions and restart contracts in automated fixtures.
   Evidence: `build/completion-audit/full-run/post-splash-regression.json`; `tests/test_controls.gd`; `tests/test_tank.gd`; `tests/test_war_chest.gd`; `tests/test_main.gd`.
   Coverage: Subsystem and synthetic-input fixtures may stage state; they are not uninterrupted human/physical co-op evidence.
8. **VERIFIED** Verify shared War Chest, partial refill, salvage, spend-wheel and unanimous ready contracts in automated suites.
   Evidence: `build/completion-audit/full-run/post-splash-regression.json`; `tests/test_war_chest.gd`; `tests/test_shop.gd`; `tests/test_endless.gd`; `tests/test_controls.gd`.
   Coverage: This closes the current tests only; the full-run bot matrix does not itself exercise every production tank/rally/shop-vote scenario.
9. **PENDING** Retain production-scene integration receipts for tank/rally recovery and two-seat unanimous shop ready-up.
   Evidence: `build/completion-audit/full-run/post-splash-regression.json`; `build/completion-audit/gameplay.md`.
   Required: Use explicit declared staging if needed and legal production inputs; do not substitute subsystem fixtures or normal campaign completion for unexercised integration cases.
10. **VERIFIED** Verify enemy reachability, spawn/strike telegraphs, Observer cleanup, supplies and boss damage invariants.
   Evidence: `build/completion-audit/full-run/post-splash-regression.json`; `build/completion-audit/full-run/final-common-matrix-04/summary.json`; `tests/test_archetypes.gd`; `tests/test_observer.gd`; `tests/test_hitbox_fairness.gd`; `tests/test_view_honesty.gd`.
   Coverage: Automated behavioral checks and normal finite traversal; whole-campaign visual/audio comprehension stays separate.
11. **VERIFIED** Repair reproduced roll-latch, speech-reset, readable-layout and intro hidden-progress defects.
   Evidence: `build/completion-audit/full-run/post-splash-regression.json`; `build/completion-audit/speech-current.log`; `build/completion-audit/presentation/capture-splash-physics-review.md`; `build/completion-audit/release/final-20261004-02/release-report.md`.
   Coverage: Meaningful failing reproductions and passing current regressions retained. Current committed determinism tests pass; no difficulty/bot tuning was used to force completion.
12. **VERIFIED** Verify explicit finale victory and Last Stand wipe mechanics with declared staging.
   Evidence: `build/completion-audit/full-run/final-ending-stages-02/summary.json`.
   Coverage: Declared mutations remain in reports and cannot satisfy normal campaign completion or normal replay acceptance.

## M2. Complete the player experience

Exit status: open. Exit requires observed renderer evidence, clean input/audio checks and recorded newcomer/co-op acceptance from `docs/ten-item-acceptance.md`. An automated renderer check does not establish human comprehension or controller feel.

1. **VERIFIED** Review the captured menu, manual, rebind, Hall and selected HUD states in actual GL pixels.
   Evidence: `build/completion-audit/presentation/capture-splash-physics-review.md`; `build/completion-audit/presentation/rendered-splash-physics/capture-report.json`.
   Coverage: 70 actual frames, including 20 enlarged manual leaves, accepted on the frozen app. Actual client 1280x720 at 2x; minimum displayed text 18px, default body/controls 20px.
2. **PENDING** Complete combat-silhouette, projectile, explosion and world-label review across every environment and boss phase.
   Evidence: `build/completion-audit/presentation/capture-splash-physics-review.md`; `build/completion-audit/presentation.md`.
   Required: Captured menus/HUD and automated render/layout tests are not a complete whole-campaign combat review.
3. **VERIFIED** Verify current input lifecycle, rebind, focus, seat and accessibility-setting contracts in automated tests.
   Evidence: `build/completion-audit/full-run/post-splash-regression.json`; `tests/test_controls.gd`; `tests/test_main.gd`; `tests/test_menu_layout.gd`.
   Coverage: Synthetic/API input checks are separate from physical keyboard/mouse/gamepad behavior and absent planned assist schemes.
4. **EXTERNAL** Exercise actual keyboard/mouse, the controller matrix, reconnect/rebinding and independent local co-op seats.
   Evidence: `docs/completion-external-checks.md`.
   Required: Retain actual devices, platform, candidate hashes and observed input/seat behavior.
5. **VERIFIED** Verify old-run speech cancellation, pending/fade cleanup and preserved startup narration.
   Evidence: `build/completion-audit/speech-current.log`; `build/completion-audit/full-run/post-splash-regression.json`; `docs/completion-audio-design.md`.
   Coverage: 16 real-scene synthetic speech checks plus current full regression; listening to all campaign cues remains open.
6. **EXTERNAL** Review the full hit/death/revive/tank/supply/boss cue set with corresponding audio and captions.
   Evidence: `docs/completion-external-checks.md`.
   Required: Retain whole-campaign listening evidence and observations for speaker roles and enemy-shout meaning.
7. **VERIFIED** Verify current opening-delivery and recovery-teaching logic and captured guidance.
   Evidence: `build/completion-audit/full-run/post-splash-regression.json`; `tests/test_main.gd::test_onboarding_seen_is_delivery_based_and_empty_profile_rearms_opening`; `tests/test_view_honesty.gd`; `build/completion-audit/presentation/capture-splash-physics-review.md`.
   Coverage: Automated behavior/current captured guidance; comprehension and controller feel require unfamiliar players.
8. **EXTERNAL** Complete newcomer and paired co-op observations from the acceptance protocol.
   Evidence: `docs/ten-item-acceptance.md`.
   Required: Actual unfamiliar participants and recorded observations are required.
9. **VERIFIED** Check existing translation synchronization and current font/string contracts.
   Evidence: `build/completion-audit/lint-i18n-current.log`; `build/completion-audit/full-run/post-splash-regression.json`; `tests/test_localization.gd`.
   Coverage: The existing es/fr/ja files and current automated coverage do not establish the planned twelve-language launch contract.
10. **EXTERNAL** Obtain human localization QA for the approved language matrix.
   Evidence: `docs/completion-external-checks.md`.
   Required: Resolve the language scope separately and retain reviewed interface/subtitle/audio coverage.

## M3. Pass the integrated checks

Exit status: open. Exit requires complete pass sentinels, no unexpected engine errors and zero shutdown leaks. Test success applies only to the behavior each test actually exercises.

1. **VERIFIED** Import current assets/global classes and retain cache/source identity with the pinned engine.
   Evidence: `build/completion-audit/release/final-20261004-02/import-receipt.json`; `build/completion-audit/release/final-20261004-02/matrix-dependency-binding.json`.
   Coverage: Zero import diagnostics/leaks and zero class/UID/imported-cache drift from the final source matrix.
2. **VERIFIED** Run the full timing-free isolated-profile regression suite.
   Evidence: `build/completion-audit/full-run/post-splash-regression.json`; `build/completion-audit/full-run/post-splash-regression.log`; `build/completion-audit/full-run/final-current-verification.json`.
   Coverage: 1,304 methods / 40,531 assertions / zero failures. Unexpected diagnostics and shutdown leaks are zero; deliberate ConfigFile-corruption errors remain under the existing narrow allowlist.
3. **VERIFIED** Run simulation, asset and localization lint gates for the unchanged component inputs.
   Evidence: `build/completion-audit/lint-sim-current.log`; `build/completion-audit/lint-assets-current.log`; `build/completion-audit/lint-i18n-current.log`; `build/completion-audit/full-run/final-current-verification.json`.
   Coverage: Retained lints cover deterministic sim invariants, asset sidecars and synchronized existing locales. They do not establish human localization or missing feature scope.
4. **VERIFIED** Exercise current production boot, entry, input, debrief/title transitions and replay through real-scene checks.
   Evidence: `build/completion-audit/full-run/final-common-matrix-04/summary.json`; `build/completion-audit/full-run/final-packaged-common-matrix/summary.json`; `build/completion-audit/full-run/final-packaged-process-restarts/summary.json`; `build/completion-audit/full-run/post-splash-regression.json`.
   Coverage: Earlier smoke-current/e2e-current logs are supplementary short-run history; current completion evidence comes from the final production scene/pack matrices.
5. **VERIFIED** Exercise complete finite modes and bounded Endless with recorded legal inputs, replay checksums and strict error gates.
   Evidence: `build/completion-audit/full-run/final-common-matrix-04/summary.json`; `build/completion-audit/full-run/final-packaged-common-matrix/summary.json`; `build/completion-audit/full-run/final-ending-stages-02/summary.json`.
   Coverage: Actual 30-tick rejection controls, per-seat coverage, deterministic tick limits and owned process-group deadlines are required. Staged cases remain separate.
6. **VERIFIED** Verify production save/Watch and fresh OS reload of all finite saved runs.
   Evidence: `build/completion-audit/full-run/final-packaged-process-restarts/summary.json`; `build/completion-audit/full-run/final-packaged-common-matrix/summary.json`.
   Coverage: Fresh plain-Godot processes load Hall/career/best/replay/Daily metadata and reproduce exact state; durable ConfigFile values stay unchanged. Native-template restart is not established.
7. **VERIFIED** Verify plain-engine exact-pack menu/window/paused-window shutdown and actual Mac menu/OS Quit routes.
   Evidence: `build/completion-audit/release/final-20261004-02/stock-exact-pack-close/receipt.json`; `build/completion-audit/release/final-20261004-02/release-report.md`.
   Coverage: Actual native menu Quit and OS Cmd+Q during active/paused play exit cleanly. An OS Quit is not proof of the native red-window-button route.
8. **EXTERNAL** Observe the actual native Mac red-window-button shutdown route.
   Evidence: `build/completion-audit/release/final-20261004-02/release-report.md`.
   Required: Screen-sharing accessibility hid the button in retained native checks. Exercise and retain that distinct route before closing all normal shutdown requirements.

## M4. Verify stability and compatibility

Exit status: open. Exit requires direct platform and hardware evidence. A cross-export or headless source test cannot establish a foreign-platform runtime pass.

1. **VERIFIED** Run accelerated deterministic soak checks and retain allocation/entity samples.
   Evidence: `build/completion-audit/soak-648000.log`; `docs/completion-memory.json`.
   Coverage: 648,000 live ticks and 180 allocation samples with debug auto-restoration and accelerated simulation only. This is not a normal rendered survival session.
2. **PENDING** Run required rendered long sessions and campaign replay soaks with wall-clock, memory and frame-time evidence.
   Evidence: `docs/release-readiness.md`; `docs/completion-external-checks.md`.
   Required: Accelerated/debug soak and short GL capture cannot close the rendered long-session requirement.
3. **VERIFIED** Launch the exact stock Mac candidate and observe native menu/active/paused Quit and natural intro/title persistence.
   Evidence: `build/completion-audit/release/final-20261004-02/release-report.md`; `build/completion-audit/release/final-20261004-02/inspection/native-macos-producer-receipt.json`.
   Coverage: Current-host native Mac observations only; natural intro/title saved no hidden score after repair. Native full-gameplay and red-window-button routes are separate.
4. **EXTERNAL** Exercise actual Windows/Linux release games and the full Mac arm64/Intel distribution matrix.
   Evidence: `docs/completion-external-checks.md`.
   Required: Cross-exports, identical PCK hashes and plain-engine inspection do not establish native foreign-platform execution.
5. **EXTERNAL** Exercise Proton and Steam Deck LCD/OLED, including suspend/resume and long sessions.
   Evidence: `docs/completion-external-checks.md`.
   Required: Retain actual hardware and the exact candidate hashes.
6. **EXTERNAL** Exercise Xbox, DualSense, DS4, Switch Pro and 8BitDo device/seat stability.
   Evidence: `docs/completion-external-checks.md`.
   Required: Retain connect/disconnect/reconnect, rebind and local co-op results.
7. **VERIFIED** Verify the captured readable display layout and automated fullscreen-fallback contracts.
   Evidence: `build/completion-audit/presentation/capture-splash-physics-review.md`; `build/completion-audit/full-run/post-splash-regression.json`; `tests/test_main.gd::test_readable_window_falls_back_when_chrome_cannot_fit`.
   Coverage: Current 1280x720 client at 2x and selected larger text settings; 1x is unsupported. This does not publish a measured minimum hardware specification.
8. **EXTERNAL** Publish a measured minimum specification and complete display/GPU compatibility observations.
   Evidence: `docs/completion-external-checks.md`.
   Required: Keep Windows10/11, NVIDIA/AMD/Intel, Mac arm64/Intel and each untested display/hardware cell open.
9. **EXTERNAL** Gather real crash/session population evidence and human QA required by beta exit.
   Evidence: `docs/completion-external-checks.md`.
   Required: Source regression results cannot establish participant counts, population crash targets or observer outcomes.

## M5. Produce the release candidates

Exit status: open. Exit requires checksummed candidate artifacts, reproducible packaging checks and platform execution evidence for the exact candidates.

1. **VERIFIED** Freeze current working-source/version metadata and bind actual proving artifacts.
   Evidence: `build/completion-audit/full-run/final-current-verification.json`; `build/completion-audit/release/final-20261004-02/inspection/native-macos-producer-receipt.json`.
   Coverage: Version1.4.4, baseline revision a495bdc25628e4359f4753cd5f721fa448e35566 plus retained dirty working snapshot; builder and driver/source dependency fingerprints are distinct recorded scopes.
2. **VERIFIED** Export all three desktop stock and Steam-enabled candidates with selected pinned templates/sidecars.
   Evidence: `build/completion-audit/release/final-20261004-02/native-candidates-02/manifest.json`; `build/completion-audit/release/final-20261004-02/steam-candidates/manifest.json`.
   Coverage: These are actual fresh cross-exports and artifact hashes; they are not foreign native runtime or intended-account approval.
3. **VERIFIED** Inspect package manifests, required imported resources, official Font Awesome icons/licenses and excluded development files.
   Evidence: `build/completion-audit/release/final-20261004-02/content/manifest.json`; `build/completion-audit/release/final-20261004-02/packed-runtime/manifest.json`.
   Coverage: Seven configured resource exports and six exact stock/Steam PCK inspections passed, including all24 official FA imported textures.
4. **VERIFIED** Run complete gameplay outside the source tree against the producer-bound Mac pack.
   Evidence: `build/completion-audit/full-run/final-packaged-common-matrix/summary.json`.
   Coverage: Plain Godot inspector, empty cwd, private profiles and final ZIP/executable/PCK/engine/driver/source hash gates. Stock release templates reject external path/pack/script overrides.
5. **VERIFIED** Verify saved-run playback after fresh OS processes over the exact exported pack.
   Evidence: `build/completion-audit/full-run/final-packaged-process-restarts/summary.json`.
   Coverage: Plain-engine exact-PCK OS reload only; not native-template restart or Steam Cloud persistence.
6. **VERIFIED** Verify pinned Steam template archive and native runtime sidecar bytes in current candidates.
   Evidence: `build/completion-audit/release/final-20261004-02/steam-candidates/manifest.json`.
   Coverage: GodotSteam4.22.1/Godot4.7.2/Steamworks1.65 template and sidecar identities; source/mocks/pack resources do not prove intended-account live behavior.
7. **PENDING** Retain a current exact-candidate native Steam binding runtime check without conflating it with account acceptance.
   Evidence: `build/completion-audit/release/final-20261004-02/steam-candidates/manifest.json`; `docs/steam-candidate-validation.md`.
   Required: Earlier native binding reflection is historical. Current export/sidecar and plain-engine PCK checks are separate; retain the exact current executable proof if required.
8. **EXTERNAL** Exercise actual exported native games on all intended platforms.
   Evidence: `docs/completion-external-checks.md`.
   Required: Use the platform matrix from M4 for the exact selected candidate bytes.
9. **EXTERNAL** Complete signing/notarization and applicable distribution requirements.
   Evidence: `docs/completion-external-checks.md`.
   Required: Obtain the appropriate signing authority and retain actual distribution/launch acceptance.

## M6. Close launch acceptance

Exit status: open. Exit requires observed acceptance for the shipping build and no unresolved launch gate. Public publication is a separate release action from preparing a build ready to ship.

1. **EXTERNAL** Verify achievements, Steam Input, leaderboards, rich presence and user-specific Cloud against the intended Steam app.
   Evidence: `docs/completion-external-checks.md`.
   Required: Confirm AppID/account/depot/build authority and retain actual intended-app results.
2. **EXTERNAL** Complete independent human co-op, newcomer, controller-feel and localization acceptance.
   Evidence: `docs/completion-external-checks.md`.
   Required: Retain actual participants, devices, language scope and observations.
3. **VERIFIED** Preserve all existing store art, packed Blender sources, screenshots/handoff, trailer/poster/capture receipts, copy and provenance.
   Evidence: `build/completion-audit/store-assets-save/CommanderInChief-store-assets-2026-10-04-receipt.json`; `build/completion-audit/store-assets-save/browser-gallery-review.json`.
   Coverage: Durable Downloads folder and literal ZIP verified against original/source copies and archive contents. Historical/draft media is preserved; no fresh-build media, rights or Steam approval is inferred.
4. **VERIFIED** Retain current structural store-copy checks and selected Blender-source inspection.
   Evidence: `build/completion-audit/store-copy-current.log`; `build/completion-audit/blender-hero-inspection.json`.
   Coverage: Structure/source preservation is separate from owner-approved final store content and reviewed current gameplay media.
5. **EXTERNAL** Review approved current store copy, actual gameplay screenshots/trailer, capsule/library assets and disclosures.
   Evidence: `docs/steam-store/owner-review.md`; `build/completion-audit/store-assets-save/CommanderInChief-store-assets-2026-10-04-receipt.json`.
   Required: Saved historical assets do not establish final candidate media, owner approval or intended-store page acceptance.
6. **EXTERNAL** Resolve generation/permission/voice records, pricing/support/date/language/rights fields and owner decisions.
   Evidence: `docs/steam-store/owner-review.md`.
   Required: Do not infer declarations, permissions, legal decisions or acceptance from asset copies.
7. **EXTERNAL** Complete intended-account install/update/uninstall, depot/page previews, upload/review and platform acceptance.
   Evidence: `docs/completion-external-checks.md`.
   Required: Publishing/account actions require the applicable owner authority and explicit publication instruction.
8. **EXTERNAL** Preserve owner-managed IP, legal, market, funding and awards decisions.
   Evidence: `docs/PLAN.md`.
   Required: No participant outcome, consent, permission, commercial decision or platform approval is inferred.
9. **ACTIVE** Complete the planned local assist controls, score partitioning, run timer/splits and save integrity.
   Evidence: `build/completion-audit/launch-contract-audit/finding.md`; `build/completion-audit/launch-contract-audit/mapping.json`; `docs/completion-status.json`.
   Required: These explicit local promises are authorized by the completion goal. Assist implementation is undergoing fresh verification; timer/splits and save ownership/integrity follow. Only the infinite-revive/Last Stand conflict and actual account acceptance require owner input.
10. **SCOPE** Resolve replay submission, ownership validation, storage, deterministic verification jobs and enforcement scope, then implement included capabilities.
   Evidence: `build/completion-audit/requirements-reconciliation.md`.
   Required: The optional launch-scope question remains unanswered. Obtain the launch contract, then implement and verify any included capability; account access alone does not remove local implementation.
11. **SCOPE** Resolve Steam UGC attachment and intended-app authentication scope, then implement/test the included local boundary.
   Evidence: `build/completion-audit/requirements-reconciliation.md`.
   Required: The optional launch-scope question remains unanswered. Obtain the launch contract, then implement and verify any included capability; account access alone does not remove local implementation.
12. **EXTERNAL** Obtain replay-service deployment authority and prove real invalid-run rejection/enforcement when included.
   Evidence: `docs/completion-external-checks.md`.
   Required: Local deterministic score verification does not authenticate submissions or deploy a service.
13. **SCOPE** Resolve default-off telemetry consent/collection/transport scope and endpoint/retention decisions before included implementation/live collection.
   Evidence: `build/completion-audit/requirements-reconciliation.md`.
   Required: The optional launch-scope question remains unanswered. Obtain the launch contract, then implement and verify any included capability; account access alone does not remove local implementation.
14. **EXTERNAL** Gather actual beta population crash/session and human QA evidence.
   Evidence: `docs/completion-external-checks.md`.
   Required: Mocks and source checks cannot establish population targets.
15. **SCOPE** Resolve the promised language launch matrix and implement missing included interface coverage before human QA.
   Evidence: `build/completion-audit/requirements-reconciliation.md`.
   Required: The optional launch-scope question remains unanswered. Obtain the launch contract, then implement and verify any included capability; account access alone does not remove local implementation.
16. **SCOPE** Resolve the bounded Zone1/ten-wave demo scope and implement/verify the exact included demo artifact.
   Evidence: `build/completion-audit/requirements-reconciliation.md`.
   Required: The optional launch-scope question remains unanswered. Obtain the launch contract, then implement and verify any included capability; account access alone does not remove local implementation.
17. **EXTERNAL** Obtain intended demo app/depot/store/festival authority and complete applicable submissions when included.
   Evidence: `docs/completion-external-checks.md`.
   Required: An implementation or saved store archive does not provide external app/depot authority.
18. **PENDING** Prepare a release-day patch candidate, support/review process and local install verification before owner publication.
   Evidence: `docs/release-readiness.md`; `docs/completion-external-checks.md`.
   Required: Current review candidates are retained, but a reviewed patch/support/install/update handoff is not established by the source matrix.

## M7. Deliver the shipping handoff

Exit status: open. Exit requires the full done predicate from `todo.md`. A smaller local-only milestone must retain that label and does not close the goal.

1. **VERIFIED** Assemble and verify the current checksummed local review handoff with source/pack/restart/presentation/release evidence.
   Evidence: `build/completion-audit/release/final-20261004-02/handoff-receipt.json`.
   Coverage: 356 receipted files and same-source verification; final review archive CommanderInChief-1.4.zip SHA2562b859806cf92a385cf9173734c0372ab139ea338820eeae09fcf22000ba1b578. Optional approved store media was absent.
2. **VERIFIED** Reconcile the plan/status with current proving artifacts and retain local/scope/external gaps.
   Evidence: `docs/completion-plan.md`; `docs/completion-status.json`; `todo.md`; `build/completion-audit/full-run/final-current-verification.json`.
   Coverage: This closes evidence reconciliation only, not the open launch requirements.
3. **VERIFIED** Independently review local source-mode, exported-pack, fresh-process, renderer and package-tool contracts.
   Evidence: `build/completion-audit/full-run/final-report.md`; `build/completion-audit/presentation/acceptance-dashboard-review.json`; `build/completion-audit/release/final-20261004-02/offline-fixtures.json`.
   Coverage: Current read-only verifier reviews and81 release-tool fixtures pass; human/foreign-platform/live-service acceptance remains separate.
4. **VERIFIED** Record the precise local review-ready verdict and named remaining launch prerequisites.
   Evidence: `build/completion-audit/release/final-20261004-02/handoff-receipt.json`; `docs/completion-external-checks.md`.
   Coverage: Current local review is verified. Overall shipping remains blocked and the optional launch-scope question is unanswered.
5. **EXTERNAL** Complete the shipping handoff after every required launch gate and approved media decision is closed.
   Evidence: `docs/completion-external-checks.md`.
   Required: Meet the unchanged full done predicate in todo.md. A verified local review bundle and saved historical store archive do not close the shipping goal.

## Evidence and execution record

The sealed 1.4.4 baseline full regression passed 1,304 methods and 40,531 assertions with zero failures. `post-splash-regression.json` and `final-current-verification.json` bind the result to that historical source/test/dependency set. The changed working source needs its own complete regression and runtime/export acceptance. Earlier 1,289/1,303-method logs and intermediate controller/packaging attempts remain historical evidence, not the current inventory.

`final-common-matrix-04/summary.json` verifies Campaign solo/co-op, Arcade, Boss Rush, actual Daily seed335492300 and bounded Endless. Every finite run reaches its ordered gates, Last Stand, victory and debrief with exact inputs/replay/save/Watch. Each co-op seat has independent decision coverage. Explicit ending mutations live only in `final-ending-stages-02/summary.json`.

`final-packaged-common-matrix/summary.json` and `final-packaged-process-restarts/summary.json` inspect the exact producer-bound final Mac PCK through plain Godot, outside the source tree in isolated profiles. Five finite saved runs reload in fresh OS processes and replay exactly. These proofs do not claim native-template full gameplay or restart. Actual native Mac menu Quit and active/paused OS Quit are distinct release observations; the red-window-button route remains unverified.

The sealed baseline 70-frame GL review covers specified menu/manual/Hall/rebind/HUD states at a 1280x720 client with 2x projection and readable18px minimum/20px default body-controls. Full-campaign listening/visual comprehension, human playtests, hardware and foreign-platform execution remain separately open.

The final review receipt binds `CommanderInChief-1.4.zip` to SHA256 `2b859806cf92a385cf9173734c0372ab139ea338820eeae09fcf22000ba1b578`, with356 receipted files and same-source checks. Its optional approved store-media fields were absent. The newly saved historical store archive is a separate durable artifact and does not mutate that sealed review bundle.

The coordinator and three agents preserve assigned file ownership. The inventory reconciliation left the sealed bundle intact. Subsequent authorized accessibility work changed source, added focused runtime tests and produced 104 staged menu frames; those receipts apply to their own recorded source. Only the coordinator schedules future engine execution.
