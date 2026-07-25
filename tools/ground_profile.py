#!/usr/bin/env python3
"""aaa-2/#1 pixel gate: no persistent centre lane in the ground paint.

Fails (exit 1) if any 16px-boxcar column mean of the play corridor sits more
than 4.75% below the row median. Field rows y in [60,280) (below the HUD,
above the caption strip); x in [200,440) — the play corridor where the
spine actually lived (the full [40,600) width includes the right-edge
vignette, which dips ~6% on every frame regardless of the spine and isn't
what this gate is measuring).

4.75% threshold: the fixed build measures 2.2-4.4% centre dip, HEAD measures
5.3-7.1% — 4.75% sits in the gap, clearing every fixed frame by >=0.4pp and
catching every HEAD frame by >=0.5pp.
"""
import sys
from PIL import Image

THRESHOLD_PCT = 4.75
BOX = 16
Y0, Y1 = 60, 280
X0, X1 = 200, 440


def column_means(path: str) -> list[float]:
    img = Image.open(path).convert("L")
    px = img.load()
    means = []
    for x in range(X0, X1):
        total = 0
        count = 0
        for y in range(Y0, Y1):
            total += px[x, y]
            count += 1
        means.append(total / count)
    return means


def boxcar(values: list[float], box: int) -> list[float]:
    out = []
    for i in range(0, len(values) - box + 1):
        out.append(sum(values[i:i + box]) / box)
    return out


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} <png>", file=sys.stderr)
        return 2
    path = sys.argv[1]
    means = boxcar(column_means(path), BOX)
    median = sorted(means)[len(means) // 2]
    max_dip_pct = 0.0
    max_dip_x = X0
    for i, m in enumerate(means):
        dip_pct = (median - m) / median * 100.0
        if dip_pct > max_dip_pct:
            max_dip_pct = dip_pct
            max_dip_x = X0 + i
    print(f"max dip {max_dip_pct:.2f}% @ x={max_dip_x} (median={median:.1f}, threshold={THRESHOLD_PCT}%)")
    if max_dip_pct > THRESHOLD_PCT:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
