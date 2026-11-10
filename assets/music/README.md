# Score

Original, owned music. Composed as note data in `tools/compose_music.py` and rendered by the
offline synthesizer in that file (numpy + ffmpeg/libvorbis, 44.1 kHz stereo, ~q5). No samples,
no third-party audio, no generator service. Deterministic: fixed seeds, no clock.

Regenerate everything: `python3 tools/compose_music.py` (about 30 s). One piece:
`python3 tools/compose_music.py --only boss`. Then `godot --headless --path . --import` so the
`.import` sidecars follow. Check it: `python3 tools/test_compose_music.py`.

**Validated by measurement only (loudness, true peak, loop length and wrap, key, distinctness,
theme presence, melody/chord fit). Nobody has listened to it. It needs a human ear.**

## The theme

One 8-bar leitmotif in D minor (4/4). Phrase A (bars 1-4) asks: D-A-A-D leaps up a fifth and
back, then steps down F-E-D-C, Bb-A-G-F and lands on the dominant (E-A). Phrase B (bars 5-8)
answers: the same opening, climbs to A5, and resolves to D. The first two bars are the *motto*,
eight notes with the step sequence +7 0 +5 +3 -1 -2 -2; every loop quotes it.

## Contract (for the engine)

`<id>_combat.ogg` is the full arrangement, `<id>_lull.ogg` the thinned one (bass, pad, sparse
percussion, motto fragments). Both stems of an id have identical sample length and tempo, and
each wraps seamlessly (reverb/delay tails are folded back into the head). Ids: title, sector1-6,
boss, shop, laststand. Stingers: `sting_boss_intro`, `sting_sector_clear`, `sting_victory`,
`sting_defeat` (4.0, 3.2, 5.0, 4.0 s). `manifest.json` carries bpm/bars/beats_per_bar per loop
and seconds per stinger. All loops are 16 bars. Every file is mastered to -16 LUFS (+-0.3) with a
soft-clip ceiling, true peak well under -1 dBTP, so crossfades need no level matching.

## Tracks

| id | bpm | key | intent |
|---|---|---|---|
| title | 104 | D min | The theme stated plainly and heroically, then doubled an octave down. |
| sector1 Staging Ground | 112 | D min | Snare-driven march; motto first, then the phrases, snare roll into the wrap. |
| sector2 Marsh Basin | 100 | D min | Murky half-time; the theme sits in the bass, then drops an octave. |
| sector3 Bridge Gunship | 126 | G min | Urgent driving eighths over a tonic pedal; motto, echo and cadence. |
| sector4 Foundry Works | 118 | D min | Industrial: metal hits, narrow pulse lead, theme as a bass riff. |
| sector5 Crashed Convoy | 124 | A min | Tense, syncopated dusk; sparse motto, inverted answer phrase. |
| sector6 Foundry Core | 132 | D min | Climactic: the full theme, doubled, then lead and bass together. |
| boss | 140 | D min | Relentless 16th pump on a tonic pedal; the theme inverted up top and plain in the bass. |
| shop | 92 | D min | Relaxed, swung, mellow lead; rests between phrases. |
| laststand | 144 | D min | The motto under maximum pressure, rolls at every phrase end. |

Loops use a 16-bar form in four 4-bar slots with a drum fill at every phrase end and a military
snare roll plus kick into the loop point where marked. Harmony is derived from the melody:
each theme bar has a short list of chords it tolerates (`HARM` in the tool) and each track picks
colours from it.
