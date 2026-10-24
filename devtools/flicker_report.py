"""Flicker report for devtools/FlickerProbe frame sequences.

A pixel "blinks" at frame t when its luminance jumps by more than THRESH from t-1 to t and jumps back (opposite sign,
also > THRESH) from t to t+1. Smooth motion (sun, wind sway, water) changes pixels gradually and rarely blinks;
popping, z-fighting, shadow crawl and dithered fades do. For each sequence this writes <dir>_heat.png
(first frame, blinking pixels in red, brighter = more blinks) and prints the share of pixels that blinked 2+ times.

  python flicker_report.py <folder with sequence subfolders>
"""
import sys
from pathlib import Path

import numpy as np
from PIL import Image

THRESH = 0.10


def lum(path):
    a = np.asarray(Image.open(path).convert("RGB"), dtype=np.float32) / 255.0
    return a, 0.2126 * a[..., 0] + 0.7152 * a[..., 1] + 0.0722 * a[..., 2]


def report(seq: Path):
    files = sorted(seq.glob("f_*.png"))
    if len(files) < 3:
        return None
    first, _ = lum(files[0])
    L = np.stack([lum(f)[1] for f in files])
    d = np.diff(L, axis=0)                       # t -> t+1
    up = d[:-1]
    back = d[1:]
    blink = (np.abs(up) > THRESH) & (np.abs(back) > THRESH) & (np.sign(up) != np.sign(back))
    count = blink.sum(axis=0)
    share = float((count >= 2).mean())
    heat = first.copy()
    m = np.clip(count / 6.0, 0, 1)[..., None]
    heat = heat * (1 - m * 0.85) + np.array([1.0, 0.1, 0.1]) * m * 0.85
    Image.fromarray((heat * 255).astype(np.uint8)).save(seq.parent / f"{seq.name}_heat.png")
    return share, int(count.max())


def jiggle_score(seq: Path):
    """Camera wiggles 1/3 px left/right; content is static. Mean absolute frame-to-frame change over the last 30
    frames (after temporal AA has settled), in 1/255 units, and the share of pixels changing by more than 0.05."""
    files = sorted(seq.glob("f_*.png"))[-31:]
    L = np.stack([lum(f)[1] for f in files])
    d = np.abs(np.diff(L, axis=0))
    return float(d.mean() * 255.0), float((d > 0.05).mean() * 100.0)


if "--jiggle" in sys.argv:
    root = Path(sys.argv[1])
    for seq in sorted(p for p in root.iterdir() if p.is_dir()):
        m, share = jiggle_score(seq)
        print(f"{seq.name:28s} mean change {m:5.2f}/255   pixels changing > 5 %: {share:5.2f} %")
    sys.exit(0)

root = Path(sys.argv[1])
for seq in sorted(p for p in root.iterdir() if p.is_dir()):
    r = report(seq)
    if r:
        print(f"{seq.name:24s} blinking pixels (2+ times in {len(list(seq.glob('f_*.png')))} frames): {r[0] * 100:6.3f} %   max blinks {r[1]}")
