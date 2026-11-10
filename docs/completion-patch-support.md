# Prepare an update and handle launch issues

Use the selected 1.4.4 candidates as the proposed update. Keep the selected archives and their receipts together. The candidates are local review artifacts. Intended-account Steam checks, distribution signing, rights review, and human acceptance remain open.

## Select the candidate

1. Read `build/completion-audit/release/final-20261004-02/native-candidates-02/manifest.json` for the stock builds.
2. Read `build/completion-audit/release/final-20261004-02/steam-candidates/manifest.json` for the Steam builds and required runtime libraries.
3. Compare each selected file with the manifest's SHA-256 value before copying the file into a depot or review package.
4. Keep the producer's source records. The candidates came from dirty source at `a495bdc25628e4359f4753cd5f721fa448e35566`; that revision alone does not identify their contents.
5. Read `build/completion-audit/release/final-20261004-02/release-report.md` for the tested scope and open gates.

The sealed review archive is `build/completion-audit/release/final-20261004-02/CommanderInChief-1.4.zip`. The folder inside it is `CommanderInChief-1.4.4-review`. Preserve both names when matching receipts. Store media is saved separately in `/Users/shoemoney/Downloads/CommanderInChief-store-assets-2026-10-04`.

## Rehearse a local Mac upgrade

The executable checker uses a new install directory and a private profile. It refuses destinations outside `build/completion-audit/remaining-release`. The archived candidates and the actual OS user profile stay outside the replacement operation.

1. Choose a new output directory under `build/completion-audit/remaining-release`.
2. Prepare the pinned local 0.3.0 baseline and current 1.4.4 candidate:

   ```sh
   rtk proxy python3 tools/remaining_release_checks.py prepare build/completion-audit/remaining-release/install-next
   ```

3. Run the archive rejection controls:

   ```sh
   rtk proxy python3 tools/remaining_release_checks.py controls build/completion-audit/remaining-release/install-next
   ```

4. Launch the baseline through the private profile:

   ```sh
   rtk proxy python3 tools/remaining_release_checks.py launch build/completion-audit/remaining-release/install-next --label baseline
   ```

5. Before each live UI observation, require the tracked native handle to remain live:

   ```sh
   rtk proxy python3 tools/remaining_release_checks.py observe-guard build/completion-audit/remaining-release/install-next --label baseline
   ```

   Use the corresponding launch label for the update and rollback. The guard checks the selected executable, one native app, and its private HOME. It does not bind a CUA target to a PID. Do not use a CUA app path after the tracked process exits; that API can launch the app again through LaunchServices.
6. Observe the title and Hall of Fame. Record the displayed saved score. Quit through the game menu.
7. After Quit, wait on the owned process handle. Do not ask the app for another screenshot or accessibility state.
8. Replace the private installation with the exact 1.4.4 candidate:

   ```sh
   rtk proxy python3 tools/remaining_release_checks.py switch build/completion-audit/remaining-release/install-next --to current
   rtk proxy python3 tools/remaining_release_checks.py launch build/completion-audit/remaining-release/install-next --label update
   ```

9. Observe the saved score and Hall of Fame again. To check replay compatibility, start **Watch** and observe playback. File preservation alone cannot prove replay compatibility.
10. Quit through the game menu, then wait on the owned process handle.
11. Replace the private installation with its retained baseline:

   ```sh
   rtk proxy python3 tools/remaining_release_checks.py switch build/completion-audit/remaining-release/install-next --to old
   rtk proxy python3 tools/remaining_release_checks.py launch build/completion-audit/remaining-release/install-next --label rollback
   ```

12. Observe the saved score, then quit through the game menu. Wait on the owned process handle.
13. Write the final source and save comparison:

    ```sh
    rtk proxy python3 tools/remaining_release_checks.py finalize build/completion-audit/remaining-release/install-next
    ```

Use `install-summary.json`, the native process receipts, and retained screenshots to assess the result. A clean exit alone does not establish that the menu loaded the intended save. The fixture contains a verified 1.4.4 Campaign record. The old app's response to that fixture is a downgrade observation; it does not represent every historical user's save.

These steps test direct Mac filesystem installation. Steam client installation, depots, Cloud, uninstall behavior, other native platforms, and distribution Gatekeeper behavior require their own checks.

## Inspect the exact Steam engine offline

Run this inspection only when the shared engine slot is available:

```sh
rtk proxy python3 tools/remaining_release_checks.py binding-prepare build/completion-audit/remaining-release/install-next
rtk proxy python3 tools/remaining_release_checks.py binding-run build/completion-audit/remaining-release/install-next
```

Require `binding/summary.json` to report VERIFIED for the positive case and both precise rejection controls. The runner copies the exact exported Mac executable and Steam library unchanged. A separate adjacent inspection pack disables module initialization and embedded callbacks. The pack reads the bridge as text and reflects method and signal metadata. It never instantiates the bridge or game, initializes Steam, pumps callbacks, or calls operational methods.

The stock executable must reject the same positive inspection pack because the native Steam singleton is absent. The Steam executable must reject a separate pack whose inspection text names a deliberately absent method. Neither rejection proves live account behavior. Keep full-game Steam acceptance open until the intended app and account pass `completion-external-checks.md`.

## Build a patch after a reported defect

1. Copy the original report, exact build hash, and reproduction into a new issue record. Use `build/completion-audit/remaining-release/support-report-template.md`.
2. Reproduce the failure with the reported mode, seed, assist settings, and input method. Retain the original replay and save as evidence.
3. Add a behavior check that fails for the reported defect. Reject a control that fails for an unrelated parse error or empty test result.
4. Repair the responsible code. Preserve the deterministic simulation boundary and explain any intentional golden-checksum change.
5. Run the focused check, the full regression suite, simulation lint when applicable, and the affected production-scene case.
6. Export to a new directory. Keep the previous candidate intact.
7. Recheck the exact exported pack and the relevant native executable. Repeat the private install and saved-record checks for any save, replay, or launch change.
8. Record the fix, tested platforms, known limits, and candidate hashes in patch notes. State a fix as verified only for the evidence retained with that candidate.
9. Have the release owner review the candidate and completed external gates before selecting a depot branch. Publication requires the owner's authorized account action.

## Triage a launch report

Treat a reproduced save-loss defect, startup failure affecting a shipping platform, or a crash during normal play as a release blocker. Retain the previous installation and affected saves. Select a rollback only after testing the previous candidate with the affected save; downgrade compatibility cannot be assumed.

For a progression blocker, reproduce the exact mode and seed before promising a patch. For a visual or audio issue, request the platform, settings, and a recording that shows the problem. Avoid assigning a gameplay balance verdict from a single automated run.

Assign a release owner and support contact in `steam-store/owner-review.md`. Those fields are still unanswered. Before launch, record who reads reports, who approves fixes, and who can select or revert a Steam branch. The local procedure is prepared; no support mailbox, response schedule, or operator has been invented.

## Review a player report or store review

1. Retain the original report and its build identifier.
2. Separate a reproducible defect from a feature request or opinion.
3. Link a verified defect to its issue and test evidence.
4. Draft a response using the actual status. Do not claim that a fix is shipped while it remains a local candidate.
5. Have the support owner approve and send the response through the selected channel.

No player, reviewer, or third party has been contacted during this local preparation.

## Current rehearsal evidence

The current exact Steam-native reflection is VERIFIED in `build/completion-audit/remaining-release/install-01/binding/summary.json`. Its unchanged executable reflects all 22 bridge method names and five signal names. Native argument types and signal arity match the mock metadata. The stock executable rejects the same inspection pack for a missing singleton. The Steam executable rejects a separate inspection pack for the deliberately absent method. All three processes exit with their expected codes and no runtime or shutdown diagnostics. Steam initialization and embedded callbacks remain disabled; no live account behavior was tested.

Archive preparation and three archive rejection controls passed. The damaged-package controls leave the active installation and private saves unchanged. A synthetic live-process guard also prevents an installation replacement during a tracked launch.

The native install rehearsal remains NOT VERIFIED. Its tracked baseline exits cleanly, and the private saved ConfigFile and replay retain their original bytes. The tracked current process reaches its 360-second deadline and is terminated. Later CUA app observations launch a new process through LaunchServices outside the tracked profile. The visible saved-score and Watch screenshots therefore remain provisional evidence; they do not close the native load or playback requirement. Rollback was not run.

`observer-failure.json` retains the actual profile comparison and terminal process check. All preexisting saved progress files keep their original bytes. Diagnostic logs and one shader-cache file change. The full actual-user tree is not unchanged, and no missing historical diagnostic log has been reconstructed. All owned native processes are terminal.

The revised observer guard rejects a terminal handle, a reused PID, a duplicate native app, and the wrong HOME. Its synthetic metadata fixtures pass, and the already-terminal current handle is rejected. These controls do not replace a new native rehearsal with enforced observation identity. The shared engine slot is released, and no further native app observation or launch occurs in this lane until the coordinator grants it.

Independent review also found that a child ignoring TERM could survive the runner's deadline and that file-map comparison omitted extra install symlinks. The checker now escalates shutdown to an owned KILL and records the terminal outcome, and installation verification rejects symlinks. `install-01/lifetime-install-controls/receipt.json` retains passing controls using a Python child and small-file fixture. The child ignores TERM, receives KILL, and is reaped with exit -9. An extra symlink is rejected while the original fixture bytes remain unchanged. These offline controls do not close native installation acceptance.
