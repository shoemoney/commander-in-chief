#!/usr/bin/env python3
"""Commander In Chief score: composed as note data, rendered by an offline synth.

    python3 tools/compose_music.py            # all loops + stingers + manifest
    python3 tools/compose_music.py --only boss --only sting_victory
    python3 tools/compose_music.py --out /tmp/x

Deterministic (fixed seeds, no clock); python3 + numpy + ffmpeg(libvorbis) only.
The score is ONE 8-bar leitmotif (THEME) quoted, varied, inverted and
re-harmonised in every track.  See assets/music/README.md.
"""
import argparse
import concurrent.futures as cf
import json
import os
import subprocess
import sys

import numpy as np

SR = 44100
TARGET_LUFS = -16.0
CEIL = 0.78          # tanh ceiling (-2.2 dBFS) so the decoded true peak stays under -1 dBTP
BEATS = 4
D4 = 62

# ---------------------------------------------------------------- the theme
# (midi pitch, beats) per bar, D minor.  Phrase A (bars 1-4) asks and lands on
# the dominant; phrase B (bars 5-8) answers, climbs to A5 and resolves to D.
THEME_BARS = [
    [(62, 1), (69, 1.5), (69, .5), (74, 1)],
    [(77, 1.5), (76, .5), (74, 1), (72, 1)],
    [(70, 1.5), (69, .5), (67, 1), (65, 1)],
    [(64, 1), (69, 3)],
    [(62, 1), (69, 1.5), (69, .5), (74, 1)],
    [(81, 1.5), (79, .5), (77, 1), (74, 1)],
    [(76, 1), (77, 1), (76, .5), (73, .5), (69, 1)],
    [(74, 3.5)],
]
HEAD = [p for bar in THEME_BARS[:2] for p, _ in bar]        # the 8-note motto
THEME_INTERVALS = [b - a for a, b in zip(HEAD, HEAD[1:])]   # +7 0 +5 +3 -1 -2 -2

# chords the melody of each theme bar tolerates, in order of preference
HARM = [["Dm", "Bb", "Gm"], ["Dm", "F", "Dm"], ["Bb", "Gm", "Gm"], ["A", "Am", "A7"],
        ["Dm", "Bb", "Gm"], ["Bb", "F", "Dm"], ["A7", "A7", "A"], ["Dm", "Bb", "Gm"]]
CHORDS = {"Dm": (0, "m"), "Bb": (8, "M"), "Gm": (5, "m"), "A": (7, "M"), "A7": (7, "7"),
          "F": (3, "M"), "Am": (7, "m")}
QUAL = {"m": [0, 3, 7], "M": [0, 4, 7], "7": [0, 4, 7, 10]}
SLOT_BARS = {"A": [0, 1, 2, 3], "B": [4, 5, 6, 7], "H": [0, 1, 2, 3], "HH": [0, 1, 0, 3],
             "Ai": [0, 1, 2, 3], "Bi": [4, 5, 6, 7], "X": [0, 1, 2, 3]}

# ------------------------------------------------------------ the track table
# slots: 4 four-bar slots -> (kind, octave shift, voicing)
#   kinds: A B (phrases) H (motto only) HH (motto + echo + cadence) Ai Bi (inverted) X (no tune)
#   voicing: lead | lead2 (octave-doubled) | bass (tune in the bass) | both
TRACKS = {
    "title":     dict(bpm=104, trans=0,  bars=16, harm=[0, 0, 1, 0], drum="title", bass="title", arp=("eighth", [0, 2, 1, 2], .55),
                      slots=[("A", 0, "lead"), ("B", 0, "lead"), ("A", 0, "lead2"), ("B", 0, "lead2")], duty=.3, pad=1.0, roll=True),
    "sector1":   dict(bpm=112, trans=0,  bars=16, harm=[0, 0, 0, 1], drum="march", bass="march", arp=("eighth", [0, 2, 1, 2], .4),
                      slots=[("H", 0, "lead"), ("A", 0, "lead"), ("H", 0, "lead"), ("B", 0, "lead")], duty=.25, pad=.8, roll=True),
    "sector2":   dict(bpm=100, trans=0,  bars=16, harm=[2, 2, 1, 0], drum="half", bass="half", arp=("eighth", [0, 1, 2, 1], .35),
                      slots=[("A", 0, "bass"), ("X", 0, ""), ("A", -12, "lead"), ("B", -12, "lead")], duty=.5, pad=1.3, roll=False),
    "sector3":   dict(bpm=126, trans=5,  bars=16, pedal=True, harm=[0, 1, 0, 0], drum="drive", bass="drive", arp=("sixteenth", [0, 2, 1, 3], .35),
                      slots=[("HH", 0, "lead"), ("A", 0, "lead"), ("HH", 0, "lead"), ("B", 0, "lead")], duty=.25, pad=.7, roll=False),
    "sector4":   dict(bpm=118, trans=0,  bars=16, harm=[2, 0, 2, 0], drum="industrial", bass="industrial", arp=("eighth", [0, 3, 2, 3], .4),
                      slots=[("A", 0, "bass"), ("H", 0, "lead"), ("A", 0, "bass"), ("A", 0, "lead")], duty=.125, pad=.8, roll=False),
    "sector5":   dict(bpm=124, trans=-5, bars=16, harm=[1, 0, 2, 0], drum="syncop", bass="syncop", arp=("dotted", [0, 2, 1, 3], .45),
                      slots=[("H", 0, "lead"), ("X", 0, ""), ("A", 0, "lead"), ("Bi", 0, "lead")], duty=.35, pad=1.1, roll=False),
    "sector6":   dict(bpm=132, trans=0,  bars=16, harm=[0, 0, 1, 0], drum="climax", bass="climax", arp=("sixteenth", [0, 1, 2, 3], .35),
                      slots=[("A", 0, "lead2"), ("B", 0, "lead2"), ("A", 0, "both"), ("B", 0, "both")], duty=.3, pad=1.0, roll=True),
    "boss":      dict(bpm=140, trans=0,  bars=16, pedal=True, harm=[0, 2, 0, 0], drum="boss", bass="boss", arp=("sixteenth", [0, 2, 3, 2], .3),
                      slots=[("Ai", 0, "lead"), ("A", 0, "bass"), ("Bi", 0, "lead"), ("A", 0, "both")], duty=.2, pad=.7, roll=True),
    "shop":      dict(bpm=92,  trans=0,  bars=16, harm=[1, 1, 0, 1], drum="shop", bass="shop", arp=("eighth", [0, 1, 2, 1], .3),
                      slots=[("A", 0, "lead"), ("X", 0, ""), ("B", 0, "lead"), ("X", 0, "")], duty=.5, pad=1.2, roll=False, swing=.07),
    "laststand": dict(bpm=144, trans=0,  bars=16, pedal=True, harm=[0, 0, 0, 0], drum="laststand", bass="boss", arp=("sixteenth", [0, 2, 1, 3], .4),
                      slots=[("HH", 0, "lead2"), ("A", 0, "both"), ("HH", 0, "lead2"), ("B", 0, "both")], duty=.2, pad=.8, roll=True),
}
LOOP_IDS = list(TRACKS)
KEY = {tid: ((2 + t["trans"]) % 12, "minor") for tid, t in TRACKS.items()}
STINGERS = {"boss_intro": 4.0, "sector_clear": 3.2, "victory": 5.0, "defeat": 4.0}

# drum grids: one char per 16th. X accent, x normal, o ghost
DRUMS = {
    "title":      dict(kick="x.......x..x....", snare="....X.......X...", hat="x.x.x.x.x.x.x.x.", tomh="..............o."),
    "march":      dict(kick="x.......x.......", snare="o.o.X.o.o.o.X.oo", hat="x.x.x.x.x.x.x.x."),
    "half":       dict(kick="x.....x.........", snare="........X.......", hat="x.o.x.o.x.o.x.o.", toml="..............o."),
    "drive":      dict(kick="x...x...x...x...", snare="....X.......X...", hat="xoxoxoxoxoxoxoxo", ohat="..x...x...x...x."),
    "industrial": dict(kick="x..x..x...x.x...", snare="....X.......X...", metal="..o...x...o...x.", hat="x.x.x.x.x.x.x.x."),
    "syncop":     dict(kick="x..x..x...x..x..", snare="....X..o....X..o", hat="x.xox.xox.xox.xo", tomm="...........o..o."),
    "climax":     dict(kick="x.x.x.x.x.x.x.x.", snare="....X.......X...", hat="xxxxxxxxxxxxxxxx", tomh="..............oo"),
    "boss":       dict(kick="x.xx.xx.x.xx.xx.", snare="....X.......X...", hat="x.x.x.x.x.x.x.x.", ohat="...o...o...o...o"),
    "shop":       dict(kick="x.......x.......", rim="....o.......o...", hat="x.o.x.o.x.o.x.o."),
    "laststand":  dict(kick="x.xx.xx.x.xx.xxx", snare="....X..o....X.oX", hat="XxxxXxxxXxxxXxxx", ohat="...o...o...o...o"),
}
LULL_DRUMS = dict(kick="x...............", rim="........o.......", hat="..............o.")
# bass cells: (step16, length16, semitones above chord root)
BASS = {
    "title":      [(0, 3, 0), (4, 2, 0), (6, 2, 12), (8, 3, 0), (12, 2, 0), (14, 2, 7)],
    "march":      [(0, 3, 0), (4, 3, 0), (8, 3, 0), (12, 2, 0), (14, 2, 7)],
    "half":       [(0, 10, 0), (10, 6, 7)],
    "drive":      [(0, 2, 0), (2, 2, 12), (4, 2, 0), (6, 2, 12), (8, 2, 0), (10, 2, 12), (12, 2, 0), (14, 2, 7)],
    "industrial": [(0, 2, 0), (3, 1, 0), (6, 2, 0), (8, 2, 7), (10, 1, 0), (12, 2, 0), (15, 1, 12)],
    "syncop":     [(0, 3, 0), (3, 3, 0), (6, 2, 7), (8, 2, 0), (10, 3, 0), (13, 3, 12)],
    "climax":     [(i * 2, 2, [0, 0, 12, 0, 0, 7, 12, 7][i]) for i in range(8)],
    "boss":       [(i, 1, 12 if i in (3, 7, 11, 15) else 0) for i in range(16)],
    "shop":       [(0, 6, 0), (6, 2, 7), (8, 4, 0), (12, 4, 7)],
}
LULL_BASS = [(0, 12, 0), (12, 4, 7)]
SLOT_DYN = [0.88, 0.95, 1.0, 1.06]


def chord_name(tid, bar, half=0):
    """Chord symbol for a global bar (half 0/1 selects the half-bar in the turnaround)."""
    t = TRACKS[tid]
    slot, j = divmod(bar, 4)
    kind = t["slots"][slot][0]
    v = t["harm"][slot]
    tb = SLOT_BARS[kind][j]
    c = HARM[tb][min(v, len(HARM[tb]) - 1)]
    if bar == t["bars"] - 1 and c != "A" and c != "A7":
        return c if half == 0 else "A7"
    return c


def chord_pcs(tid, bar, half=0):
    root, q = CHORDS[chord_name(tid, bar, half)]
    base = (2 + TRACKS[tid]["trans"] + root) % 12
    return {(base + i) % 12 for i in QUAL[q]}


def chord_root_midi(tid, name, lo=33):
    root = 0 if TRACKS[tid].get("pedal") else CHORDS[name][0]   # pedal tracks pump the tonic under every chord
    m = 38 + TRACKS[tid]["trans"] + root
    while m > lo + 11:
        m -= 12
    while m < lo:
        m += 12
    return m


def chord_tones(tid, name, floor=57):
    root, q = CHORDS[name]
    base = 38 + TRACKS[tid]["trans"] + root
    while base < floor:
        base += 12
    while base >= floor + 12:
        base -= 12
    tones = [base + i for i in QUAL[q]]
    if q != "7":
        tones.append(base + 12)
    else:
        tones.append(base + 12)
    return tones


# ----------------------------------------------------------- note generation
HARMONIC_MINOR = [0, 2, 3, 5, 7, 8, 11]


def invert(p, trans):
    q = 2 * 69 - p
    rel = (q - 2) % 12
    best = min(HARMONIC_MINOR, key=lambda s: min((rel - s) % 12, (s - rel) % 12))
    d = (best - rel + 6) % 12 - 6
    return q + d


def theme_notes(kind, bar_in_slot_limit=None):
    """[(slot_bar, beat_offset, dur, pitch)] for one 4-bar slot (untransposed)."""
    out = []
    if kind == "X":
        return out
    order = SLOT_BARS[kind]
    for j in range(4):
        tb = order[j]
        if kind == "H" and j >= 2:
            continue
        if kind == "HH" and j == 3:
            notes = THEME_BARS[3]
        else:
            notes = THEME_BARS[tb]
        off = 0.0
        for p, d in notes:
            if kind in ("Ai", "Bi"):
                p = invert(p, 0)
            out.append((j, off, d, p))
            off += d
    return out


def build_events(tid, stem):
    """Full note/drum data for one stem.  Pure function of the tables above."""
    t = TRACKS[tid]
    lull = stem == "lull"
    ev = []
    rng = np.random.default_rng(abs(hash_str(tid + stem)) % (2 ** 32))
    nbars = t["bars"]
    trans = t["trans"]
    swing = t.get("swing", 0.0)

    def sw(step):
        return swing if step % 4 == 2 else 0.0

    # ---- melody
    for s, (kind, osh, voicing) in enumerate(t["slots"]):
        dyn = SLOT_DYN[s]
        for (j, off, d, p) in theme_notes(kind):
            bar = s * 4 + j
            if bar == nbars - 1 and off >= 2:
                continue
            if bar == nbars - 1:
                d = min(d, 2 - off)
            start = bar * BEATS + off
            if lull:
                if j < 2 and kind != "X":
                    ev.append(dict(voice="lead", start=start, dur=d * .95, pitch=p + trans + osh, vel=.62 * dyn))
                continue
            v = voicing
            if v in ("lead", "lead2", "both"):
                ev.append(dict(voice="lead", start=start, dur=d * .95, pitch=p + trans + osh, vel=.95 * dyn))
            if v in ("lead2", "both"):
                ev.append(dict(voice="lead2", start=start, dur=d * .95, pitch=p + trans + osh - 12, vel=.6 * dyn))
            if v in ("bass", "both"):
                ev.append(dict(voice="bassm", start=start, dur=d * .97, pitch=p + trans - 24, vel=.95 * dyn))

    # ---- bass line, arp, pad, per half-bar chords
    cells = LULL_BASS if lull else BASS[t["bass"]]
    melodic_bass = {s for s, sl in enumerate(t["slots"]) if sl[2] in ("bass", "both") and not lull}
    mode, idxs, avel = t["arp"]
    for bar in range(nbars):
        s = bar // 4
        dyn = SLOT_DYN[s]
        for step, ln, semi in cells:
            half = 1 if step >= 8 else 0
            cn = chord_name(tid, bar, half)
            if s in melodic_bass:
                continue  # the tune lives in the bass this slot
            root = chord_root_midi(tid, cn)
            ev.append(dict(voice="bass", start=bar * BEATS + step / 4.0 + sw(step), dur=ln / 4.0 * .92,
                           pitch=root + semi, vel=(.7 if lull else .95) * dyn))
        if not lull:
            step_len = {"eighth": 2, "sixteenth": 1, "dotted": 3}[mode]
            k = 0
            for step in range(0, 16, step_len):
                half = 1 if step >= 8 else 0
                tones = chord_tones(tid, chord_name(tid, bar, half))
                pitch = tones[idxs[k % len(idxs)] % len(tones)] + (12 if (k // len(idxs)) % 2 and mode == "sixteenth" else 0)
                ev.append(dict(voice="arp", start=bar * BEATS + step / 4.0 + sw(step), dur=step_len / 4.0 * .8,
                               pitch=pitch, vel=avel * dyn * (1.0 if k % 2 == 0 else .8), pan=(-.4 if k % 2 == 0 else .4)))
                k += 1
        # pad: one chord per half bar for 2-chord bars, else per bar
        halves = [chord_name(tid, bar, 0), chord_name(tid, bar, 1)]
        if halves[0] != halves[1]:
            spans = [(0, 2, halves[0]), (2, 2, halves[1])]
        else:
            spans = [(0, 4, halves[0])]
        if t.get("pedal"):   # tonic drone keeps the key anchored while the chords move
            for dp, dv in ((38, 1.0), (50, .5)):
                ev.append(dict(voice="sub", start=bar * BEATS, dur=4.0, pitch=dp + trans, vel=dv * dyn))
        for off, ln, cn in spans:
            for p in chord_tones(tid, cn, 50)[:3]:
                ev.append(dict(voice="pad", start=bar * BEATS + off, dur=ln * 1.0, pitch=p,
                               vel=(.55 if lull else .45) * t["pad"] * dyn))

    # ---- drums
    pat = LULL_DRUMS if lull else DRUMS[t["drum"]]
    vmap = {"X": 1.0, "x": .8, "o": .42}
    for bar in range(nbars):
        s = bar // 4
        dyn = SLOT_DYN[s] * (.85 if lull else 1.0)
        phrase_end = bar % 4 == 3
        big_end = bar % 8 == 7
        last = bar == nbars - 1
        fill_from = 16
        if not lull and (phrase_end or last):
            fill_from = 8 if (last or big_end) else 12
        for name, grid in pat.items():
            for step, ch in enumerate(grid):
                if ch == "." or step >= fill_from:
                    continue
                if lull and name == "kick" and bar % 2:
                    continue
                ev.append(dict(voice="drum", drum=name, start=bar * BEATS + step / 4.0 + sw(step),
                               vel=vmap[ch] * dyn * (.7 if lull else 1.0)))
        if not lull and bar % 8 == 0:
            ev.append(dict(voice="drum", drum="crash", start=bar * BEATS, vel=.8))
        if not lull and (phrase_end or last):
            ev.extend(drum_fill(t, bar, last, big_end))
        if lull and last:
            for k in range(8):
                ev.append(dict(voice="drum", drum="snare", start=bar * BEATS + 3 + k / 8.0, vel=.15 + .05 * k))
    ev.sort(key=lambda e: (e["start"], e["voice"], e.get("pitch", 0)))
    for e in ev:
        e["start"] = round(e["start"], 5)
        e["dur"] = round(e.get("dur", 0), 5) if "dur" in e else None
        if e["dur"] is None:
            del e["dur"]
        e["vel"] = round(e["vel"], 4)
    return ev


def hash_str(s):
    h = 2166136261
    for ch in s.encode():
        h = ((h ^ ch) * 16777619) & 0xFFFFFFFF
    return h


def drum_fill(t, bar, last, big):
    out = []
    b0 = bar * BEATS
    roll = t.get("roll", False)
    if last or (big and roll):
        # military snare roll: 32nds crescendo over the last two beats, tom drop, crash on the wrap
        n = 16
        for k in range(n):
            out.append(dict(voice="drum", drum="snare", start=b0 + 2 + k / 8.0, vel=.35 + .65 * k / (n - 1)))
        if last:
            out.append(dict(voice="drum", drum="kick", start=b0 + 3.75, vel=1.0))
    elif big:
        for k, (d, v) in enumerate([("snare", .9), ("snare", .7), ("tomh", .9), ("tomh", .8), ("tomm", .9), ("tomm", .8), ("toml", 1.0), ("toml", .9)]):
            out.append(dict(voice="drum", drum=d, start=b0 + 2 + k * .5, vel=v))
    else:
        for k, (d, v) in enumerate([("snare", .8), ("snare", .6), ("tomh", .85), ("toml", .95)]):
            out.append(dict(voice="drum", drum=d, start=b0 + 3 + k * .25, vel=v))
    return out


def contains_intervals(events, intervals):
    """True if any melodic voice has consecutive notes whose steps equal `intervals`."""
    for voice in ("lead", "lead2", "bassm"):
        notes = sorted((e for e in events if e["voice"] == voice), key=lambda e: e["start"])
        ps = [e["pitch"] for e in notes]
        seq = [b - a for a, b in zip(ps, ps[1:])]
        n = len(intervals)
        for i in range(len(seq) - n + 1):
            if seq[i:i + n] == list(intervals):
                return True
    return False


def harmony_fit(tid):
    """Fraction of long, non-inverted lead notes that are chord tones or colour tones (7th/9th/6th)."""
    t = TRACKS[tid]
    ok = tot = 0
    for e in build_events(tid, "combat"):
        if e["voice"] != "lead" or e["dur"] < .9:
            continue
        bar = int(e["start"] // BEATS)
        if t["slots"][bar // 4][0] in ("Ai", "Bi"):
            continue
        half = 1 if (e["start"] - bar * BEATS) >= 2 else 0
        pc = e["pitch"] % 12
        root = (2 + t["trans"] + CHORDS[chord_name(tid, bar, half)][0]) % 12
        tot += 1
        if pc in chord_pcs(tid, bar, half) or (pc - root) % 12 in (2, 9, 10, 11):
            ok += 1
    return ok / max(tot, 1)


# ------------------------------------------------------------------ the synth
def midi_hz(m):
    return 440.0 * 2.0 ** ((m - 69) / 12.0)


def adsr(n, gate, a, d, s, r):
    gate = min(gate, n - 1)
    a = min(a, gate * .5)
    d = min(d, max(gate - a, 1))
    x = [0, a, a + d, gate, gate + r]
    return np.interp(np.arange(n), x, [0, 1, s, s, 0])


def osc(f0, n, kind="saw", duty=.5, rolloff=1.0, vib=0.0, vib_hz=5.5, vib_delay=.15, detune=1.0, cap=28):
    t = np.arange(n) / SR
    ratio = 1.0
    if vib:
        ratio = 2.0 ** ((vib * np.sin(2 * np.pi * vib_hz * t) * np.clip((t - vib_delay) / .3, 0, 1)) / 1200.0)
    ph = 2 * np.pi * np.cumsum(f0 * detune * ratio) / SR
    nh = max(1, min(cap, int(0.42 * SR / (f0 * detune))))
    y = np.zeros(n)
    for h in range(1, nh + 1):
        if kind == "saw":
            y += np.sin(h * ph) / h ** rolloff
        else:
            y += np.sin(h * np.pi * duty) / h ** rolloff * np.cos(h * (ph - np.pi * duty))
    return y * (0.7 if kind == "saw" else 0.9)


class Kit:
    """Drum one-shots, synthesised once from a fixed seed."""

    def __init__(self):
        rng = np.random.default_rng(20261110)
        self.s = {}

        def tt(sec):
            return np.arange(int(sec * SR)) / SR

        t = tt(.45)
        f = 46 + 120 * np.exp(-t / .028)
        self.s["kick"] = (np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / .16)
                          + .35 * np.sin(2 * np.pi * 1800 * t) * np.exp(-t / .004))
        t = tt(.3)
        nz = rng.standard_normal(len(t))
        hp = nz - np.convolve(nz, np.ones(3) / 3, mode="same")
        self.s["snare"] = (hp * np.exp(-t / .07) * 1.1 + .6 * np.sin(2 * np.pi * 190 * t) * np.exp(-t / .05)
                           + .3 * np.sin(2 * np.pi * 330 * t) * np.exp(-t / .03))
        for name, f0 in (("tomh", 190), ("tomm", 140), ("toml", 100)):
            t = tt(.4)
            f = f0 * (1 + .7 * np.exp(-t / .04))
            self.s[name] = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / .13)
        t = tt(.07)
        nz = rng.standard_normal(len(t))
        hp = np.diff(nz, prepend=0)
        hp = np.diff(hp, prepend=0)
        self.s["hat"] = hp * np.exp(-t / .016) * .35
        t = tt(.35)
        nz = rng.standard_normal(len(t))
        hp = np.diff(np.diff(nz, prepend=0), prepend=0)
        self.s["ohat"] = hp * np.exp(-t / .1) * .3
        t = tt(1.4)
        nz = rng.standard_normal(len(t))
        hp = np.diff(np.diff(nz, prepend=0), prepend=0)
        self.s["crash"] = hp * np.exp(-t / .5) * .3
        t = tt(.06)
        self.s["rim"] = (np.sin(2 * np.pi * 1700 * t) + .4 * rng.standard_normal(len(t))) * np.exp(-t / .008) * .6
        t = tt(.5)
        self.s["metal"] = sum(np.sin(2 * np.pi * 420 * r * t) / (1 + i) for i, r in enumerate([1, 1.47, 2.09, 2.57, 3.91])) * np.exp(-t / .12) * .8
        for k, v in self.s.items():
            self.s[k] = v / (np.abs(v).max() + 1e-9)


KIT = None
DRUM_GAIN = dict(kick=1.0, snare=.8, tomh=.7, tomm=.7, toml=.75, hat=.3, ohat=.28, crash=.42, rim=.5, metal=.45)
DRUM_PAN = dict(kick=0, snare=0, tomh=-.35, tomm=0, toml=.35, hat=.25, ohat=-.25, crash=-.15, rim=.2, metal=.3)
# per-voice: (dry gain, reverb send, delay send)
SENDS = dict(lead=(.55, .22, .30), lead2=(.4, .2, .2), arp=(.34, .15, .32), bass=(.62, 0, 0), sub=(.6, 0, 0), bassm=(.6, .03, 0),
             pad=(.3, .3, 0), drum=(.8, .0, 0))
DRUM_SENDS = dict(snare=.22, crash=.3, rim=.2, tomh=.15, tomm=.15, toml=.15, metal=.1)


def synth_note(e, spb_s, bpm):
    v = e["voice"]
    dur_s = e["dur"] * spb_s
    f = midi_hz(e["pitch"])
    gate = int(dur_s * SR)
    if v in ("lead", "lead2"):
        rel = int(.12 * SR)
        n = gate + rel
        duty = e.get("duty", .3)
        y = osc(f, n, "pulse", duty=duty if v == "lead" else .5, rolloff=1.0, vib=14 if v == "lead" else 6)
        if v == "lead":
            y = y * .75 + .35 * osc(f, n, "saw", rolloff=1.2, vib=14)
        return y * adsr(n, gate, .008, .12, .75, .12) * e["vel"], 0.0
    if v == "arp":
        rel = int(.06 * SR)
        n = gate + rel
        return osc(f, n, "pulse", duty=.125, rolloff=1.0) * adsr(n, gate, .002, .07, .3, .05) * e["vel"], e.get("pan", 0)
    if v == "sub":
        rel = int(.05 * SR)
        n = gate + rel
        return np.sin(2 * np.pi * f * np.arange(n) / SR) * adsr(n, gate, .01, .1, 1.0, .05) * e["vel"], 0.0
    if v in ("bass", "bassm"):
        rel = int(.06 * SR)
        n = gate + rel
        y = osc(f, n, "saw", rolloff=1.3, cap=14) + .8 * np.sin(2 * np.pi * f * np.arange(n) / SR)
        if v == "bassm":
            y = y + .5 * osc(f, n, "pulse", duty=.3, rolloff=1.4, cap=12)
        return y * adsr(n, gate, .004, .12, .8, .06) * e["vel"] * (.9 if v == "bass" else .8), 0.0
    raise ValueError(v)


def synth_pad(e, spb_s):
    gate = int(e["dur"] * spb_s * SR)
    rel = int(.6 * SR)
    n = gate + rel
    env = adsr(n, gate, .45, .2, .85, .6) * e["vel"]
    f = midi_hz(e["pitch"])
    L = osc(f, n, "saw", rolloff=1.5, detune=.997, cap=9) * env
    R = osc(f, n, "saw", rolloff=1.5, detune=1.003, cap=9) * env
    return L * .6, R * .6


def add_wrap(buf, idx, sig, gl, gr):
    n = buf.shape[1]
    i = int(idx) % n
    end = i + len(sig)
    if end <= n:
        buf[0, i:end] += sig * gl
        buf[1, i:end] += sig * gr
    else:
        k = n - i
        buf[0, i:] += sig[:k] * gl
        buf[1, i:] += sig[:k] * gr
        buf[0, :end - n] += sig[k:] * gl
        buf[1, :end - n] += sig[k:] * gr


def pan_gains(p):
    a = (p + 1) * np.pi / 4
    return np.cos(a), np.sin(a)


def reverb_ir(n, rng):
    ir = np.zeros((2, n))
    L = min(int(1.5 * SR), n - 400)
    decay = np.exp(-np.arange(L) / SR / .42)
    for c in range(2):
        nz = np.convolve(rng.standard_normal(L), np.ones(5) / 5, mode="same") * decay
        d = int(.014 * SR) + c * 97
        seg = nz[:n - d]
        ir[c, d:d + len(seg)] = seg
    return ir * 0.045


def render(events, bpm, total, loop=True, duty=.3):
    """Mix events into a stereo buffer of `total` samples (circular when loop=True)."""
    global KIT
    if KIT is None:
        KIT = Kit()
    pad = 0 if loop else int(3.2 * SR)
    N = total + pad
    spb_s = 60.0 / bpm
    spb = spb_s * SR
    dry = np.zeros((2, N))
    rev = np.zeros((2, N))
    dly = np.zeros((2, N))
    for e in events:
        idx = int(round(e["start"] * spb))
        v = e["voice"]
        if v == "drum":
            name = e["drum"]
            smp = KIT.s[name] * DRUM_GAIN[name] * e["vel"]
            gl, gr = pan_gains(DRUM_PAN[name])
            add_wrap(dry, idx, smp, gl * SENDS["drum"][0], gr * SENDS["drum"][0])
            rs = DRUM_SENDS.get(name, 0)
            if rs:
                add_wrap(rev, idx, smp, gl * rs, gr * rs)
            continue
        if v == "pad":
            l, r = synth_pad(e, spb_s)
            for sig, g in ((l, (1.0, .0)), (r, (.0, 1.0))):
                add_wrap(dry, idx, sig, g[0] * SENDS["pad"][0], g[1] * SENDS["pad"][0])
                add_wrap(rev, idx, sig, g[0] * SENDS["pad"][1], g[1] * SENDS["pad"][1])
            continue
        e2 = dict(e)
        e2["duty"] = duty
        sig, pan = synth_note(e2, spb_s, bpm)
        gl, gr = pan_gains(pan)
        dg, rs, ds = SENDS[v]
        add_wrap(dry, idx, sig, gl * dg, gr * dg)
        if rs:
            add_wrap(rev, idx, sig, gl * rs, gr * rs)
        if ds:
            add_wrap(dly, idx, sig, gl * ds, gr * ds)
    # ping-pong dotted-eighth delay
    D = int(.75 * spb)
    wet = np.zeros_like(dly)
    for k in range(1, 7):
        sh = np.roll(dly, k * D, axis=1)
        if k % 2:
            sh = sh[::-1]
        wet += sh * (.5 ** k) * 1.4
    if not loop:
        wet[:, -1] = 0
    # circular convolution reverb (circular wrap == seamless loop; padded stinger tails never reach the head)
    rng = np.random.default_rng(777)
    ir = reverb_ir(N, rng)
    send = rev + wet * .5
    wetrev = np.fft.irfft(np.fft.rfft(send, axis=1) * np.fft.rfft(ir, axis=1), n=N, axis=1)
    out = dry + wet * .6 + wetrev * 1.6
    out -= out.mean(axis=1, keepdims=True)
    return out[:, :total] if not loop else out


# ------------------------------------------------------------- mastering / io
def ffmpeg_measure(x):
    p = subprocess.run(["ffmpeg", "-nostats", "-f", "f32le", "-ar", str(SR), "-ac", "2", "-i", "-", "-af",
                        "ebur128=peak=true", "-f", "null", "-"], input=x.astype("<f4").tobytes(),
                       capture_output=True)
    s = p.stderr.decode().split("Summary:")[-1]
    import re
    i = float(re.search(r"I:\s+(-?\d+\.\d+) LUFS", s).group(1))
    tp = float(re.search(r"Peak:\s+(-?\d+\.\d+) dBFS", s).group(1))
    return i, tp


def master(out, fade=0):
    """Gain-to-target through a tanh soft-clip ceiling; returns (N,2) float."""
    x = out.T.copy()
    g = .25 / (np.sqrt((x ** 2).mean()) + 1e-9)
    best = None
    for _ in range(8):
        y = CEIL * np.tanh(x * g / CEIL)
        if fade:
            y[:fade] *= np.linspace(0, 1, fade)[:, None]
            y[-fade:] *= np.linspace(1, 0, fade)[:, None]
        i, tp = ffmpeg_measure(y)
        best = y
        if abs(i - TARGET_LUFS) < .2 and tp <= -1.6:
            break
        g *= 10 ** ((TARGET_LUFS - i) / 20.0)
    return best


def render_float(tid, stem, repeat=1):
    """Un-mastered (2, N*repeat) mix; repeat>1 plays the loop back-to-back (seam test)."""
    t = TRACKS[tid]
    total = int(round(t["bars"] * BEATS * 60.0 / t["bpm"] * SR))
    ev = build_events(tid, stem)
    shift = total / (SR * 60.0 / t["bpm"])          # one loop in beats, exactly as long as the buffer
    ev = [dict(e, start=e["start"] + k * shift) for k in range(repeat) for e in ev]
    return render(ev, t["bpm"], total * repeat, True, t["duty"])


def render_pcm(tid, stem):
    return master(render_float(tid, stem)).astype("<f4")


def encode_ogg(pcm, path):
    p = subprocess.run(["ffmpeg", "-v", "error", "-y", "-f", "f32le", "-ar", str(SR), "-ac", "2", "-i", "-",
                        "-c:a", "libvorbis", "-q:a", "5", "-fflags", "+bitexact", "-flags:a", "+bitexact", path],
                       input=pcm.tobytes(), capture_output=True)
    if p.returncode:
        raise RuntimeError(p.stderr.decode())


# ------------------------------------------------------------------ stingers
def n_(voice, start, dur, pitch, vel=.9, **kw):
    return dict(voice=voice, start=start, dur=dur, pitch=pitch, vel=vel, **kw)


def d_(drum, start, vel=.9):
    return dict(voice="drum", drum=drum, start=start, vel=vel)


def sting_events(name):
    if name == "boss_intro":     # 150 bpm: the motto in the bass under a rising roll, then the hit
        bpm = 150
        ev = [n_("bassm", i * 1.0, .95, p - 24) for i, p in enumerate(HEAD)]
        ev += [n_("pad", 0, 8, p, .9) for p in (50, 57, 65)] + [n_("pad", 8, 3, p, .9) for p in (50, 57, 62, 65)]
        ev += [d_("snare", 4 + k / 4.0, .25 + .7 * k / 15) for k in range(16)]
        ev += [d_("toml", 0, .9), d_("toml", 4, .8), d_("kick", 8, 1), d_("crash", 8, 1), d_("toml", 8, 1)]
        ev += [n_("lead", 8, 2.5, 62, 1.0), n_("lead2", 8, 2.5, 50, .8), n_("bassm", 8, 2.5, 38, 1.0)]
        return bpm, ev
    if name == "sector_clear":   # 132 bpm: the motto's opening leap, up to a D major cadence
        bpm = 132
        ev = [n_("lead", 0, .9, 74), n_("lead", 1, .9, 81), n_("lead", 2, .45, 81), n_("lead", 2.5, 2.5, 86)]
        ev += [n_("lead2", 2.5, 2.5, 74, .6), n_("bass", 0, 2, 38, .9), n_("bass", 2.5, 2.5, 38, 1.0)]
        ev += [n_("pad", 0, 2.4, p, .8) for p in (50, 57, 62)] + [n_("pad", 2.5, 2.2, p, .9) for p in (50, 57, 62, 66)]
        ev += [d_("snare", 0, .7), d_("snare", 1, .7), d_("snare", 1.5, .6), d_("snare", 2, .8),
               d_("kick", 2.5, 1), d_("crash", 2.5, .9), d_("snare", 2.5, .9)]
        return bpm, ev
    if name == "victory":        # 160 bpm: the motto in D major, then the held resolution
        bpm = 160
        maj = {77: 78, 72: 73}
        ev = []
        t0 = 0.0
        for bar in THEME_BARS[:2]:
            for p, d in bar:
                ev.append(n_("lead", t0, d * .95, maj.get(p, p) + 0))
                ev.append(n_("lead2", t0, d * .95, maj.get(p, p) - 12, .55))
                t0 += d
        ev += [n_("lead", 8, 4.5, 74, 1.0), n_("lead2", 8, 4.5, 62, .7), n_("bass", 0, 4, 38), n_("bass", 4, 4, 43), n_("bass", 8, 4.5, 38)]
        ev += [n_("pad", 0, 4, p, .8) for p in (50, 57, 62)] + [n_("pad", 4, 4, p, .8) for p in (55, 59, 62)]
        ev += [n_("pad", 8, 5, p, 1.0) for p in (50, 57, 62, 66)]
        ev += [d_("kick", 0, 1), d_("snare", 2, .9), d_("kick", 4, 1), d_("snare", 6, .9), d_("crash", 8, 1), d_("kick", 8, 1)]
        ev += [d_("snare", 7 + k / 4.0, .4 + .15 * k) for k in range(4)]
        return bpm, ev
    if name == "defeat":         # 90 bpm: a slow minor descent, tolling toms
        bpm = 90
        ev = [n_("lead", 0, 1.1, 69, .8), n_("lead", 1, 1.1, 65, .8), n_("lead", 2, 1.1, 64, .8), n_("lead", 3, 2.4, 62, .9)]
        ev += [n_("bass", 0, 2, 38, .9), n_("bass", 2, 3.2, 33, .9)]
        ev += [n_("pad", 0, 2, p, .9) for p in (50, 57, 65)] + [n_("pad", 2, 3.5, p, .9) for p in (50, 57, 64)]
        ev += [d_("toml", 0, 1), d_("toml", 2, .8), d_("toml", 3, .9), d_("kick", 3, 1)]
        return bpm, ev
    raise ValueError(name)


def render_sting(name):
    bpm, ev = sting_events(name)
    total = int(STINGERS[name] * SR)
    out = render(ev, bpm, total, loop=False, duty=.3)
    fade = int(.012 * SR)
    tail = int(.45 * SR)
    out[:, -tail:] *= np.linspace(1, 0, tail)[None, :]
    return master(out, fade).astype("<f4")


# ---------------------------------------------------------------------- main
def job(arg):
    kind, name, outdir = arg
    if kind == "loop":
        for stem in ("combat", "lull"):
            encode_ogg(render_pcm(name, stem), os.path.join(outdir, f"{name}_{stem}.ogg"))
    else:
        encode_ogg(render_sting(name), os.path.join(outdir, f"sting_{name}.ogg"))
    return name


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "assets", "music"))
    ap.add_argument("--only", action="append", default=[])
    ap.add_argument("--jobs", type=int, default=6)
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    jobs = [("loop", i, a.out) for i in LOOP_IDS] + [("sting", s, a.out) for s in STINGERS]
    if a.only:
        jobs = [j for j in jobs if j[1] in a.only or "sting_" + j[1] in a.only]
    with cf.ProcessPoolExecutor(a.jobs) as ex:
        for name in ex.map(job, jobs):
            print("rendered", name, flush=True)
    man = {"tracks": {i: {"bpm": t["bpm"], "bars": t["bars"], "beats_per_bar": 4} for i, t in TRACKS.items()},
           "stingers": {}}
    for s in STINGERS:
        p = os.path.join(a.out, f"sting_{s}.ogg")
        if os.path.exists(p):
            man["stingers"][s] = {"seconds": round(STINGERS[s], 3)}
    with open(os.path.join(a.out, "manifest.json"), "w") as f:
        json.dump(man, f, indent=2, sort_keys=True)
        f.write("\n")


if __name__ == "__main__":
    sys.exit(main())
