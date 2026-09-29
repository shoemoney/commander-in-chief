# Native candidate verification — September 7, 2026

These are local test candidates, not an approved Steam release. They were built
from the uncommitted working tree based on `cf2338712e804d8e3ccfdf88b4f665a304532dc0`.

## Current macOS refresh

The latest local universal candidate is
`build/native-current.3Qly07/CommanderInChief-macos.zip`. This supersedes the older
Mac candidates below and includes the character/readability, ground progression,
streak feedback and HUD visibility changes in the current working tree.

- ZIP SHA256: `6dbb702d09e860a07f36abaa184cc99e13ddb68589356641da23c38575d119fc`.
- Bundled PCK SHA256: `4c14594d55312bc06fc24b7d7cd6bd1ebc82597f31e29213abe418a5c3b77911`.
- Godot 4.7.2 release export completed without error/warning diagnostics.
  `codesign --verify --deep --strict` passed; this remains **ad-hoc**, with no
  TeamIdentifier, not Developer ID signing or notarization. Both arm64 and
  x86_64 executable slices are present; only Apple Silicon execution was tested.
- The exact bundled PCK passed the external runtime probe using an empty project
  directory and a private profile. It loaded 52 player/enemy animation textures,
  four projectile textures and the HUD visibility shader. The real HUD had that
  shader attached, and campaign simulation advanced. This probe uses the editor
  executable with the packed resources, not the native release executable.
- The strengthened probe rejects the older `native-quit.RiCCuf` PCK, exiting
  nonzero for the missing HUD shader. This is a negative control for that missing
  resource, not a general byte-for-byte stale-build detector.
- The six package-checker unit tests pass; a fresh ZIP main-pack export for the
  universal macOS preset passes manifest-byte, development-file and class-cache
  checks. The native PCK probe also rejects bundled development directories.
- **Actual release app:** launched the extracted executable from its own bundle
  with `playtest_newcomer.sh --standalone` and an isolated profile. Native window
  captures showed the title screen, then Campaign after Return, with enemies,
  effects and reinforcement state advancing. Escape displayed the pause menu.
  Clicking its red window-close button while paused exited zero without script,
  render or shutdown-leak diagnostics; the owned process was confirmed gone.
  These observations close the earlier unverified native Campaign-start check.

Logs are `export.log`, `packed-runtime.log`, `content.log`,
`stale-pack-negative.log` and `native-play.log` in the same candidate directory.
The native window observations are in the task's screenshot tool results; no
separate screenshot files were saved. Resource loading and shader attachment do
not alone prove the rendered aperture effect; the source-render evidence remains
in `hud-player-visibility.md`.

This is a short boot/gameplay/pause/close smoke test, **not** a complete playthrough,
input-latency benchmark, controller check, audio listening review or fun rating.
Windows/Linux candidates below were not refreshed in this pass. Steam-enabled
templates, live account integration, platform acceptance, voice permissions and
distribution signing remain open. No gameplay source was changed in this pass.

## Toolchain and artifacts

Installed the desktop subset of the official Godot 4.7.2 export templates without
replacing the older installed versions. The download matched the release API's
SHA256 and the published SHA512 list from the
[official release](https://github.com/godotengine/godot/releases/tag/4.7.2-stable).
Archive SHA256: `f298490b8d44d934be425a5a65a51bf15f422428b229a06a6e11d9ffea248011`.

Artifacts are under `build/native-candidate.2EgRma/`:

- `CommanderInChief-macos-clean.zip`: universal macOS app (arm64 and x86_64).
- `CommanderInChief-linux.x86_64` plus `CommanderInChief-linux.pck`.
- `CommanderInChief-windows.exe` plus `CommanderInChief-windows.pck`.
- `SHA256SUMS`: measured checksums of those candidate files.

Keep each Windows/Linux executable beside its matching PCK. The macOS archive
already includes its PCK. The initial `CommanderInChief-macos.zip` and `original/`
are retained negative-control evidence, not the corrected candidate.

## Verified

- All three release exports exited successfully with Godot 4.7.2. Binary format
  inspection identified the expected macOS universal, Linux ELF x86_64 and
  Windows PE32+ x86_64 executables.
- The first macOS export included `reviews/` and `skills/` data. New negative
  tests failed before the checker repair; the original native PCK was also
  rejected by the extended runtime probe. These directories are now excluded
  from every preset. Source files were not deleted.
- The six package-checker unit tests pass. Actual ZIP main-pack exports for all
  four presets pass manifest-byte, development-file and class-cache checks.
- Each corrected native candidate's actual PCK passed
  `tools/verify_export_runtime.gd` in an empty project directory: the main scene
  loaded, the Steam Input manifest was readable and campaign ticks advanced.
  These PCK probes used the macOS editor executable with isolated saves and
  quiet teardown, not the Windows/Linux executable.
- macOS `codesign --verify --deep --strict` passed. The signature is **ad-hoc**,
  with no TeamIdentifier. This is not Developer ID signing or notarization.
- The actual macOS release executable started from its own bundle and rendered
  the title menu, observed through native window capture. The window-control
  tool subsequently reported no accessible window, so the attempted Campaign
  keypress is **not** claimed as a successful native gameplay test. Its owned
  test process was terminated after inspection; no other app was stopped.

## Open findings and evidence limits

### Follow-up: normal application shutdown repaired

The real menu Quit path reproduced 25 retained objects before repair. Quit and
window-close now share `Main.request_quit()`: stop gameplay, release audio players
and cached playback references, flush pending persistence, and allow a wall-clock
audio-drain interval before exiting. Deferred startup cannot restart stopped audio.
The drain timer remains active while paused and at zero time scale.

`tools/verify_game_quit.gd` passes menu, window-close and paused-window routes,
including repeated close requests, through the isolated zero-leak wrapper. These
checks use production shutdown, not `Quiesce`. The full suite exited successfully;
the two added regression methods bring the README count to 1,203. gda 0.15.0
validation passes all four changed runtime/probe scripts with canonical `res://`
paths. Relative paths initially caused duplicate-global-class diagnostics in gda;
these were not reproduced with canonical resource paths.

A replacement universal Mac candidate is
`build/native-quit.RiCCuf/CommanderInChief-macos.zip`, SHA256
`bced149fcd15b29b4ddd03f817911a42106f438b1419c5e76f5fccea59e0748b`.
Export and strict ad-hoc signature verification passed. Its actual release app
rendered the title menu; clicking its native red window-close button exited zero
with no shutdown diagnostics on stdout, and the owned process was confirmed gone.
The earlier candidates above predate this shutdown repair; Windows/Linux were not
rebuilt in this follow-up. Developer ID/notarization remains unverified.

### Forced engine shutdown remains distinct

The direct native `--headless --quit-after 120 --max-fps 60 --verbose` smoke run
exited zero but printed two retained `AudioStreamPlaybackPolyphonic` objects
during final cleanup (SFX and UI). The exit status alone therefore does not pass
the quiet-shutdown requirement. The file logger did not retain that final
diagnostic; it was captured on process stdout after logging shut down. No
allowlist or leak threshold was relaxed. A trial `_exit_tree` reference cleanup
also failed the source-run shutdown gate and was removed.

The templates are plain Godot, not GodotSteam-enabled production templates.
These candidates run offline and do not establish live achievements, Steam
Input, Cloud, leaderboards or store-account readiness. Windows/Linux runtime,
macOS Intel execution, Proton, Deck, signing/notarization, physical controllers,
long-session behavior and human acceptance remain unverified.

`tools/playtest_newcomer.sh --standalone` now supports isolated testing of native
release executables without `--path`, which these official release templates
reject. Set `GODOT` to the exact candidate executable. The existing default
source-project launch behavior is unchanged. Private profiles are preserved
for diagnosis; no real player save was used.

No upload, publication, release tag, commit or push was performed.
