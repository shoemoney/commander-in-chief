# Rendered endurance acceptance

The required run lasts at least three wall-clock hours. It rotates the retained normal solo Campaign, co-op Campaign and Arcade full-run replays through `main.start_watch()`. Automatic production physics, world drawing and game audio remain enabled. At least three complete Campaign replays must match their recorded tick count, input count, score, victory state and deterministic checksum. Arcade cycles also verify their full recorded ending, but do not count toward the three required Campaign completions.

The standard Godot engine runs the current source project at a physical 1280×720 window with the compatibility renderer and a 60-frame process cap. This is a local Mac renderer and lifetime check. It does not establish native-release, Steam Deck, controller, foreign-platform, human listening or live Steam acceptance. No debug restoration, gameplay mutation, accelerated clock or synthetic movie delta is permitted.

The protocol first exercises a short retained normal Endless replay. The positive pilot must render and complete playback. Its score-mismatch control must render the same progression, then reject exactly the incorrect terminal score. Additional bounded controls disable production physics, mute the actual Master bus, or suspend the owned process for three seconds; each must reject its single expected fault after real progression. A short pilot never closes the long-session requirement.

The runner records the actual engine process, watchdog, command, engine hash, source and import dependencies, fixture hashes, engine stdout, OS resident-memory samples, frame-interval histogram, draw counts, CPU/GPU timing counters and engine object/resource/node counts. Zero-valued GPU or VRAM counters remain unmeasured. The exit gate rejects every engine error and shutdown leak. The running verifier observes enabled production physics, advancing replay frames, distributed draw calls, advancing persistent music playback and repeated Master-bus peaks. It rejects Dummy or muted audio and observes the actual 60 Hz engine clock, unit time/audio scale, and physical window size. This establishes production mixer activity, not a human listening or speaker-output result.

Each frame contributes at most 250 ms toward the required active-render duration; any two-second frame gap fails. Engine and OS samples must cover the complete run and both memory windows with no gap above 7.5 seconds. Exact 64-bit checksums travel as decimal strings rather than rounded JSON floating-point numbers.

After three complete replays, the first 180 seconds form the warmed baseline. Later samples must stay within these declared envelopes above that baseline peak.

| Counter | Additional allowance |
| --- | --- |
| Engine static memory | 16 MiB |
| Live objects | 128 |
| Live resources | 32 |
| Live nodes | 8 |
| Orphan nodes | 0 |
| OS resident memory | 128 MiB |

These bounds allow transient scene effects and allocator retention while detecting sustained growth. The final report retains the full time series and envelope result. It does not describe all sub-threshold growth as impossible. Frame intervals include host scheduling and the explicit process cap; this run makes no speedup comparison or minimum-hardware claim.

Run the pilot and negative control in new output folders, with sole use of the Commander Godot runtime. After they pass, run the full soak in another new folder.

```sh
rtk proxy python3 tools/run_rendered_soak.py --pilot --duration 20 --output build/completion-audit/rendered-soak/pilot
rtk proxy python3 tools/run_rendered_soak.py --pilot --duration 20 --score-offset 1 --output build/completion-audit/rendered-soak/score-control
rtk proxy python3 tools/run_rendered_soak.py --duration 10800 --output build/completion-audit/rendered-soak/full
```

Keep the process receipt as RUNNING until the same observed process exits. A polling timeout does not authorize restarting the soak. The verifier rejects source/import drift, an insufficient duration, missing post-warm samples, unexpected terminal states, or a memory envelope violation.

Current state: the revised positive pilot completed 20 active-render seconds with one exact normal Endless replay, zero runtime errors/leaks and no source drift. Thirteen synthetic memory controls passed, including sparse, missing, nonmonotonic and growth failures. Typed runtime fault controls are in progress. The full three-hour run follows completion and freezing of the newly audited accessibility work; no completed endurance run is claimed.
