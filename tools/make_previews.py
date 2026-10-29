#!/usr/bin/env python3
"""Make the animated previews shown in README.md from the sprite sheets in pets/.

  docs/pets/<id>.webp          one loop through every mood a pet has art for
  docs/pets/states/<mood>.webp the default pet, one clip per mood (missing moods fall back
                               the same way the app does)

Usage:  python3 tools/make_previews.py [--default claudiks]
Requires Pillow.
"""
import argparse
import json
from pathlib import Path

from PIL import Image

from import_sprites import COLS, FH, FW, ROW

ORDER = ["idle", "working", "thinking", "attention", "done", "worried", "sleepy"]
FALLBACK = {"worried": ["sleepy", "idle"], "sleepy": ["idle"], "thinking": ["working", "idle"]}   # as in Pets.swift
FRAME_MS = 250
HALF_SPEED = ("idle", "sleepy")   # the app plays these at half speed


def read_rows(sheet: Image.Image) -> dict:
    rows = {}
    for mood, r in ROW.items():
        frames = []
        for c in range(COLS):
            f = sheet.crop((c * FW, r * FH, (c + 1) * FW, (r + 1) * FH))
            if not f.getbbox():
                break
            frames.append(f)
        if frames:
            rows[mood] = frames
    return rows


def resolve(rows: dict, mood: str) -> list:
    for m in [mood] + FALLBACK.get(mood, ["idle"]):
        if m in rows:
            return rows[m]
    return []


def save(path: Path, frames: list, durations: list):
    path.parent.mkdir(parents=True, exist_ok=True)
    frames[0].save(path, save_all=True, append_images=frames[1:], duration=durations, loop=0,
                   lossless=False, quality=90, alpha_quality=100, method=6)
    print(f"  {path}  ({len(frames)} frames, {path.stat().st_size // 1024} KB)")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--default", default="claudiks", help="pet whose per-mood clips go to docs/pets/states")
    ap.add_argument("--pets", type=Path, default=Path("pets"))
    ap.add_argument("--out", type=Path, default=Path("docs/pets"))
    args = ap.parse_args()

    for folder in sorted(p for p in args.pets.iterdir() if (p / "spritesheet.webp").exists()):
        rows = read_rows(Image.open(folder / "spritesheet.webp").convert("RGBA"))
        boxes = [f.getbbox() for fr in rows.values() for f in fr]
        pad = 4   # one crop for the whole pet, so it doesn't jump between moods
        box = (max(0, min(b[0] for b in boxes) - pad), max(0, min(b[1] for b in boxes) - pad),
               min(FW, max(b[2] for b in boxes) + pad), min(FH, max(b[3] for b in boxes) + pad))
        rows = {m: [f.crop(box) for f in fr] for m, fr in rows.items()}
        print(folder.name)

        frames, durations = [], []
        for mood in ORDER:
            if mood in rows:
                frames += rows[mood]
                durations += [FRAME_MS * (2 if mood in HALF_SPEED else 1)] * len(rows[mood])
        save(args.out / f"{folder.name}.webp", frames, durations)

        if folder.name == args.default:
            for mood in ORDER:
                fr = resolve(rows, mood)
                if fr:
                    save(args.out / "states" / f"{mood}.webp", fr,
                         [FRAME_MS * (2 if mood in HALF_SPEED else 1)] * len(fr))


if __name__ == "__main__":
    main()
