#!/usr/bin/env python3
"""Measurement gate for the composed score (tools/compose_music.py -> assets/music/).

Nobody can audition the score in CI, so everything that CAN be measured is:
file/manifest contract, loop length, loudness, true peak, clipping, loop seam,
key, distinctness between places, theme presence in the note data, melody/chord
fit, determinism.  Passing this proves the files are well-formed and
musically-coherent by the numbers; it does not prove they sound good.

Run:  python3 tools/test_compose_music.py        (exit 0 = all green)
"""
import json
import os
import re
import subprocess
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import compose_music as cm  # noqa: E402

MUSIC = os.path.join(ROOT, "assets", "music")
SR = 44100
FAILS = []
CHECKS = 0


def check(cond, msg):
    global CHECKS
    CHECKS += 1
    if not cond:
        FAILS.append(msg)
        print("FAIL  " + msg)


def decode(path):
    p = subprocess.run(["ffmpeg", "-v", "error", "-i", path, "-f", "f32le", "-ac", "2",
                        "-ar", str(SR), "-"], capture_output=True)
    return np.frombuffer(p.stdout, dtype=np.float32).reshape(-1, 2).astype(np.float64)


def ebur(path):
    p = subprocess.run(["ffmpeg", "-nostats", "-i", path, "-af", "ebur128=peak=true",
                        "-f", "null", "-"], capture_output=True, text=True)
    s = p.stderr.split("Summary:")[-1]
    i = re.search(r"I:\s+(-?\d+\.\d+) LUFS", s)
    tp = re.search(r"Peak:\s+(-?\d+\.\d+) dBFS", s)
    return (float(i.group(1)) if i else None, float(tp.group(1)) if tp else None)


# ---- DSP helpers --------------------------------------------------------
def stft_mag(x, n=4096, hop=2048):
    w = np.hanning(n)
    frames = [np.abs(np.fft.rfft(x[i:i + n] * w)) for i in range(0, len(x) - n, hop)]
    return np.array(frames)


KS_MAJ = np.array([6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88])
KS_MIN = np.array([6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17])


def chroma(x):
    n = 8192
    mag = stft_mag(x, n, 4096)
    f = np.fft.rfftfreq(n, 1 / SR)
    sel = (f > 55) & (f < 2500)
    pc = (np.round(12 * np.log2(f[sel] / 440.0) + 69).astype(int)) % 12
    c = np.zeros(12)
    p = (mag[:, sel] ** 2).mean(axis=0)
    for k in range(12):
        c[k] = p[pc == k].sum()
    return c / c.sum()


def detect_key(c):
    best = (-9, None)
    for t in range(12):
        for mode, prof in (("major", KS_MAJ), ("minor", KS_MIN)):
            r = np.corrcoef(c, np.roll(prof, t))[0, 1]
            if r > best[0]:
                best = (r, (t, mode))
    return best[1]


def centroid(x):
    mag = stft_mag(x, 2048, 1024)
    f = np.fft.rfftfreq(2048, 1 / SR)
    return float(np.mean((mag * f).sum(axis=1) / (mag.sum(axis=1) + 1e-9)))


def flux(frames):
    d = np.diff(np.log1p(frames * 50), axis=0)
    return np.maximum(d, 0).sum(axis=1)


def main():
    man_path = os.path.join(MUSIC, "manifest.json")
    check(os.path.exists(man_path), "manifest.json exists")
    man = json.load(open(man_path)) if os.path.exists(man_path) else {"tracks": {}, "stingers": {}}
    feats = {}

    for tid in cm.LOOP_IDS:
        spec = cm.TRACKS[tid]
        m = man["tracks"].get(tid)
        check(m is not None, f"{tid}: in manifest")
        if m:
            check(m == {"bpm": spec["bpm"], "bars": spec["bars"], "beats_per_bar": 4},
                  f"{tid}: manifest matches track table")
        expect = spec["bars"] * 4 * 60.0 / spec["bpm"] * SR
        stems = {}
        for stem in ("combat", "lull"):
            p = os.path.join(MUSIC, f"{tid}_{stem}.ogg")
            if not os.path.exists(p):
                check(False, f"{tid}_{stem}.ogg exists")
                continue
            check(os.path.getsize(p) < 1_200_000, f"{tid}_{stem}: under 1.2 MB ({os.path.getsize(p)})")
            x = decode(p)
            stems[stem] = x
            check(abs(len(x) - expect) <= 2, f"{tid}_{stem}: {len(x)} samples vs expected {expect:.1f}")
            lufs, tp = ebur(p)
            check(lufs is not None and abs(lufs - (-16.0)) <= 1.5, f"{tid}_{stem}: loudness {lufs} LUFS not within -16 +-1.5")
            check(tp is not None and tp <= -1.0, f"{tid}_{stem}: true peak {tp} dBTP above -1")
            check(np.abs(x).max() < 0.999, f"{tid}_{stem}: clipped samples")
            # loop seam
            mono = x.mean(axis=1)
            step = np.abs(np.diff(mono))
            jump = abs(mono[0] - mono[-1])
            check(jump <= 4 * np.percentile(step, 99.9) + 1e-4,
                  f"{tid}_{stem}: seam jump {jump:.4f} vs p99.9 step {np.percentile(step, 99.9):.4f}")
            half = len(mono) // 2
            rolled = np.roll(mono, half)
            fl = flux(stft_mag(rolled, 2048, 512))
            mid = (half) // 512
            seam = fl[max(0, mid - 4):mid + 4].max()
            rest = np.concatenate([fl[:max(0, mid - 6)], fl[mid + 6:]])
            check(seam <= 1.25 * rest.max(), f"{tid}_{stem}: seam flux {seam:.1f} vs worst normal {rest.max():.1f}")
            if stem == "combat":
                c = chroma(mono)
                key = detect_key(c)
                feats[tid] = dict(bpm=spec["bpm"], cen=centroid(mono), chroma=c, key=key)
                tonic, mode = cm.KEY[tid]
                rel = ((tonic + 3) % 12, "major") if mode == "minor" else ((tonic + 9) % 12, "minor")
                ok = key == (tonic, mode) or (tid == "shop" and key == rel)
                check(ok, f"{tid}: detected key {key} vs declared {(tonic, mode)}")
        if len(stems) == 2:
            check(len(stems["combat"]) == len(stems["lull"]), f"{tid}: stems differ in length")

        # theme in the note data
        ev = cm.build_events(tid, "combat")
        check(cm.contains_intervals(ev, cm.THEME_INTERVALS), f"{tid}: theme head intervals absent from note data")
        check(cm.contains_intervals(cm.build_events(tid, "lull"), cm.THEME_INTERVALS[:5]),
              f"{tid}: lull has no theme fragment")
        fit = cm.harmony_fit(tid)
        check(fit >= 0.85, f"{tid}: melody/chord fit {fit:.2f} < 0.85")

    # distinctness
    ids = [i for i in cm.LOOP_IDS if i in feats]
    for a in range(len(ids)):
        for b in range(a + 1, len(ids)):
            A, B = feats[ids[a]], feats[ids[b]]
            dbpm = abs(A["bpm"] - B["bpm"])
            dcen = abs(A["cen"] - B["cen"]) / max(A["cen"], B["cen"])
            corr = float(np.corrcoef(A["chroma"], B["chroma"])[0, 1])
            check(dbpm >= 4 or dcen >= 0.08 or corr < 0.95,
                  f"{ids[a]} vs {ids[b]} not distinct (bpm d={dbpm}, centroid d={dcen:.2f}, chroma r={corr:.2f})")
    cens = sorted(f["cen"] for f in feats.values())
    if cens:
        check(cens[-1] / cens[0] > 1.15, "spectral centroid spread across the score is too narrow")

    # stingers
    for name in cm.STINGERS:
        p = os.path.join(MUSIC, f"sting_{name}.ogg")
        if not os.path.exists(p):
            check(False, f"sting_{name}.ogg exists")
            continue
        x = decode(p)
        secs = len(x) / SR
        check(2.0 <= secs <= 5.0, f"sting_{name}: {secs:.2f}s outside 2-5s")
        ms = man["stingers"].get(name, {}).get("seconds")
        check(ms is not None and abs(ms - secs) < 0.05, f"sting_{name}: manifest seconds {ms} vs {secs:.2f}")
        lufs, tp = ebur(p)
        check(tp is not None and tp <= -1.0, f"sting_{name}: true peak {tp}")
        check(np.abs(x).max() < 0.999, f"sting_{name}: clipped")
        check(np.abs(x[:50]).max() < 0.05 and np.abs(x[-50:]).max() < 0.05, f"sting_{name}: ends not faded")

    # seamless-by-construction: the loop played twice back-to-back must reproduce, in its second
    # pass, exactly the single-loop render (tails wrapped into the head ARE the previous pass's tails)
    for tid in ("title", "boss", "shop"):
        for stem in ("combat", "lull"):
            one = cm.render_float(tid, stem)
            two = cm.render_float(tid, stem, 2)
            n = one.shape[1]
            err = np.abs(two[:, n:] - one).max() / np.abs(one).max()
            check(err < 1e-6, f"{tid}_{stem}: loop wrap not seamless (rel err {err:.2e})")
    # control: drop the tail wrap (shift the loop by a beat in one pass) and the same test must fail
    one = cm.render_float("title", "combat")
    two = cm.render_float("title", "combat", 2)
    n = one.shape[1]
    check(np.abs(two[:, n:] - np.roll(one, 22050, axis=1)).max() / np.abs(one).max() > 1e-3,
          "seamless test cannot fail (control)")

    # determinism: two renders of the same stem are bit-identical
    a = cm.render_pcm("shop", "lull")
    b = cm.render_pcm("shop", "lull")
    check(np.array_equal(a, b), "render is not deterministic")
    check(json.dumps(cm.build_events("boss", "combat"), sort_keys=True)
          == json.dumps(cm.build_events("boss", "combat"), sort_keys=True), "note data not deterministic")

    print(f"{'PASS' if not FAILS else 'FAIL'} - {CHECKS} checks, {len(FAILS)} failed")
    return 1 if FAILS else 0


if __name__ == "__main__":
    sys.exit(main())
