# Commander voice-over — radio spotter, downed pilot, and combat barks

56 mp3 across three provenance groups (verified by file layout + git history, not a
generation manifest — none exists for this directory).

## Radio VO — `vo_*.mp3` (14 files)

| File | Voice | Role |
|---|---|---|
| vo_chest_empty | Adam | Radio Commander |
| vo_wiped | Matilda | Spotter |
| vo_last_stand | Matilda | Spotter |
| vo_observer | Matilda | Spotter |
| vo_surge | Matilda | Spotter |
| vo_core | Matilda | Spotter |
| vo_flawless | Matilda | Spotter |
| vo_ransom_lost | Matilda | Spotter |
| vo_victoly | Adam | Radio Commander |
| vo_airstrike | Matilda | Spotter |
| vo_pilot_down | Matilda | Spotter |
| vo_shop_locked | Matilda | Spotter |
| vo_clip_dry | Matilda | Spotter |
| vo_pilot_plea | Harry | Downed Pilot |

**Voices (per commit `b4f12b6`):** Radio Commander — Adam; Spotter — Matilda; Downed Pilot — Harry.  
**Format (measured):** mono, 44.1kHz, 128kbps mp3.  
**Pipeline:** commissioned through a hosted TTS service — the three voice names above match
ElevenLabs' stock premade-voice roster, and the measured format matches the `mp3_44100_128`
output param recorded for `assets/audio/ya_chants/`, so that is the inferred source. Inferred
from the recorded parameters, not from a logged API call; see `ASSETS.md` for what that means
for downstream licensing.

Wired in `src/view/sfx.gd::play_vo()`, preloaded at sfx.gd:356–362.

## Commander combat barks — `cmd/*.mp3` (41 files)

11 combat events × several takes each (per commit `becbc9e`: level-start, boss rally, kill-streak,
6 hit-reaction variants, player-down, revive, airstrike boom, pickup, victory, shoot, grenade).

**Voice:** a clone of a real public figure's voice ("Trump commander voice" per the commit
message) — this is the identifiable-likeness voice `ASSETS.md`'s owner-decision box discusses.  
**Format (measured):** mono, 24kHz, 160kbps mp3 — distinct from the Radio VO group above.  
**Pipeline (recorded, not inferred):** per commit `becbc9e`, "cloned via the fleet VoiceStudio
(.4)" — a self-hosted voice-cloning tool. This is NOT ElevenLabs and NOT a stock voice roster;
`ASSETS.md`'s directory-level "ElevenLabs hosted TTS, stock voice roster" line does not hold for
this group — see the note at the bottom of this file.

Wired in `src/view/sfx.gd::_load_cmd_barks()` / `play_cmd_bark()`, called from `main.gd`.

## Intro narration — `intro_crawl.mp3` (1 file)

**Voice:** "Trump VO" per commit `024ea55` — the same character voiced in `cmd/*.mp3` above.  
**Format (measured):** mono, 24kHz, 160kbps mp3 — identical to the `cmd/` group, unlike the Radio
VO group's 44.1kHz/128kbps.  
**Pipeline:** unrecorded in the `024ea55` commit message itself — it names the VO but doesn't
restate a service. The format match to `cmd/` (added the same day) makes the fleet VoiceStudio
pipeline plausible, but that is this file's own inference, not a repeated record — call it
**unconfirmed**, weaker than the `cmd/` entry above.

Wired in `src/view/sfx.gd::play_vo("intro_crawl")`, fired once from `main._process` on the intro
crawl beat.

## Note on `ASSETS.md`

`ASSETS.md`'s audio table lists all 56 files here as one row ("ElevenLabs hosted TTS, stock voice
roster"). That holds for the 14-file Radio VO group above; the 42 remaining files (`cmd/` +
`intro_crawl.mp3`) have a git-recorded pipeline (fleet VoiceStudio, a voice clone, not a stock
roster) that this file's breakdown reflects and `ASSETS.md`'s single row does not. Worth a
follow-up edit to `ASSETS.md` by the owner; not made here since this job's scope is this README
only.
