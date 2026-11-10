# Run speech reset

The production caller is `Main._reset()`. It calls `Sfx.reset_run_speech()` before constructing the next run. Sfx owns the audio players, deferred speech and captions, so the caller does not manipulate those fields.

`reset_run_speech() -> void` cancels prior speech fades, stops old run speech, clears pending lines and per-run cooldowns, and removes prior captions. It restores the two speech-channel volumes to their configured values. Loaded resources and asynchronous load requests remain cached.

The opening narration intentionally continues after a splash skip. If `_startup_line_playing` is true, the reset preserves the dry narration player, its active caption, speech priority and startup lock. Other run speech and pending captions still clear. The existing completion callback releases that lock when the narration finishes.

The rejected alternative was stopping each player and clearing fields in Main. That would distribute Sfx lifecycle ownership across its caller and leave fade callbacks able to stop new speech.

The real-scene regression `tools/verify_run_speech.gd` uses actual player playback with synthetic two-second streams. The pre-change source fails seven checks after reset. It preserves the startup control. This checks lifecycle behavior, not voice intelligibility or a listening review.

The release and full-run verification agents independently reviewed the design. They identified the need to preserve the startup player's natural-finish callback and all active-caption fields while clearing queued combat state. Both fade tweens must cancel before volume restoration. These requirements are part of the implementation and regression contract.

The repaired scene probe passes all 16 checks with no engine errors or shutdown leaks. CI runs the same probe on its three operating systems and requires the complete sentinel through the strict runtime-log checker. The final converged source and hosted runs still require verification.
