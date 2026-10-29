#!/usr/bin/env python3
"""Turn ChatGPT-generated animation images into a Koderkatins / petdex sprite sheet.

Each input image holds ~6 frames of one animation in a loose grid with empty gutters
(see docs/SPRITES.md). The importer:
  1. makes the background transparent (keeps real alpha, otherwise keys out the flat
     colour sampled from the image corners),
  2. finds frames by cutting at empty rows/columns (no exact grid needed) and merges
     tiny detached bits such as sparkles into the nearest frame,
  3. scales ALL frames of ALL animations by one shared factor and puts the feet on a
     common baseline so the pet doesn't jump between animations,
  4. writes <out>/spritesheet.webp (8×9 grid of 192×208), pet.json and preview.png.

Usage:
  python3 tools/import_sprites.py --name "Midnight" --idle idle.png \
      [--working working.png] [--attention attention.png] [--worried worried.png] \
      [--done done.png] --out pets/midnight
Requires Pillow.
"""
import argparse
import json
import re
import sys
from pathlib import Path

from PIL import Image, ImageChops, ImageFilter

FW, FH = 192, 208
COLS, ROWS = 8, 9
ROW = {"idle": 0, "attention": 3, "done": 4, "worried": 5, "thinking": 6, "working": 7, "sleepy": 8}
PAD_X, PAD_TOP, BASELINE = 8, 6, 202   # frame box the art is fitted into


def remove_background(im: Image.Image, tolerance: int) -> Image.Image:
    im = im.convert("RGBA")
    alpha = im.getchannel("A")
    if alpha.getextrema()[0] < 250:          # real transparency present → trust it
        return im
    w, h = im.size
    corners = [im.getpixel(p)[:3] for p in ((2, 2), (w - 3, 2), (2, h - 3), (w - 3, h - 3))]
    bg = max(set(corners), key=corners.count)
    rgb = im.convert("RGB")
    diff = ImageChops.difference(rgb, Image.new("RGB", im.size, bg)).convert("L")
    mask = diff.point(lambda v: 255 if v > tolerance else 0).filter(ImageFilter.MinFilter(3))
    soft = diff.point(lambda v: 0 if v <= tolerance else min(255, (v - tolerance) * 4))
    im.putalpha(ImageChops.multiply(mask.filter(ImageFilter.MaxFilter(3)), soft))
    # despill chroma green / magenta fringes
    if bg[1] > 200 and bg[0] < 80 and bg[2] < 80:
        r, g, b, a = im.split()
        g = ImageChops.darker(g, ImageChops.lighter(r, b))
        im = Image.merge("RGBA", (r, g, b, a))
    return im


def spans(profile, min_gap):
    """Return [start, end) runs where profile is non-empty, joined across gaps < min_gap."""
    runs, start, gap = [], None, 0
    for i, v in enumerate(profile):
        if v:
            if start is None:
                start = i
            gap = 0
        elif start is not None:
            gap += 1
            if gap >= min_gap:
                runs.append((start, i - gap + 1))
                start, gap = None, 0
    if start is not None:
        runs.append((start, len(profile) - gap))
    return runs


def find_frames(im, min_gap, min_area):
    a = im.getchannel("A").point(lambda v: 255 if v > 24 else 0)
    w, h = a.size
    row_prof = [bool(a.crop((0, y, w, y + 1)).getbbox()) for y in range(h)]
    boxes = []
    for y0, y1 in spans(row_prof, min_gap):
        band = a.crop((0, y0, w, y1))
        col_prof = [bool(band.crop((x, 0, x + 1, y1 - y0)).getbbox()) for x in range(w)]
        for x0, x1 in spans(col_prof, min_gap):
            bb = a.crop((x0, y0, x1, y1)).getbbox()
            if bb:
                boxes.append([x0 + bb[0], y0 + bb[1], x0 + bb[2], y0 + bb[3]])
    if not boxes:
        return []
    biggest = max((b[2] - b[0]) * (b[3] - b[1]) for b in boxes)
    big = [b for b in boxes if (b[2] - b[0]) * (b[3] - b[1]) >= biggest * min_area * 10]
    small = [b for b in boxes if b not in big]
    for s in small:   # merge sparkles into the nearest real frame
        cx, cy = (s[0] + s[2]) / 2, (s[1] + s[3]) / 2
        t = min(big, key=lambda b: (cx - (b[0] + b[2]) / 2) ** 2 + (cy - (b[1] + b[3]) / 2) ** 2)
        t[0], t[1], t[2], t[3] = min(t[0], s[0]), min(t[1], s[1]), max(t[2], s[2]), max(t[3], s[3])
    # reading order: group into rows by vertical centre, then left→right
    big.sort(key=lambda b: (b[1] + b[3]) / 2)
    rows, cur = [], [big[0]]
    for b in big[1:]:
        if abs((b[1] + b[3]) / 2 - (cur[-1][1] + cur[-1][3]) / 2) < (cur[-1][3] - cur[-1][1]) * 0.5:
            cur.append(b)
        else:
            rows.append(cur)
            cur = [b]
    rows.append(cur)
    return [im.crop(tuple(b)) for r in rows for b in sorted(r, key=lambda b: b[0])]


def stabilize(frames, max_shift=18):
    """Shift each frame so its silhouette overlaps the first frame best.

    Image models draw every pose slightly off-centre; without this the pet wobbles
    from frame to frame. Limb/tail motion is kept because only a whole-frame shift is applied."""
    try:
        import numpy as np
    except ImportError:
        return frames
    if len(frames) < 2:
        return frames
    pad = max_shift
    W = max(f.width for f in frames) + 2 * pad
    H = max(f.height for f in frames) + 2 * pad

    def canvas(f, dx=0, dy=0):
        c = Image.new("RGBA", (W, H), (0, 0, 0, 0))
        c.alpha_composite(f, (pad + (W - 2 * pad - f.width) // 2 + dx, pad + (H - 2 * pad - f.height) + dy))
        return c

    ref = np.asarray(canvas(frames[0]).getchannel("A"), dtype=np.float32) / 255
    out = [canvas(frames[0])]
    for f in frames[1:]:
        m = np.asarray(canvas(f).getchannel("A"), dtype=np.float32) / 255
        best, bdx, bdy = -1.0, 0, 0
        for dy in range(-max_shift // 2, max_shift // 2 + 1, 1):
            for dx in range(-max_shift, max_shift + 1, 1):
                score = float((ref * np.roll(np.roll(m, dy, 0), dx, 1)).sum())
                if score > best:
                    best, bdx, bdy = score, dx, dy
        out.append(canvas(f, bdx, bdy))
    bb = None
    for c in out:
        b = c.getbbox()
        if b:
            bb = b if bb is None else (min(bb[0], b[0]), min(bb[1], b[1]), max(bb[2], b[2]), max(bb[3], b[3]))
    return [c.crop(bb) for c in out] if bb else frames


def grab_blobs(im, y0, y1, ncols, cell_w):
    """Per column, cut the artwork out as whole connected blobs: [(x0, piece) or None].

    A straight vertical cut slices off a tail tip that pokes under the neighbour's glasses.
    Each blob goes to the column its centre falls in; small detached bits (sweat drops,
    sparkles) join the nearest big blob. Returns None when scipy isn't installed."""
    try:
        import numpy as np
        from scipy import ndimage
    except ImportError:
        return None
    band = np.array(im.crop((0, y0, im.width, y1)))
    labels, n = ndimage.label(band[..., 3] > 40)
    if not n:
        return [None] * ncols
    ids = np.arange(1, n + 1)
    area = np.asarray(ndimage.sum(np.ones_like(labels), labels, ids))
    centre = np.asarray(ndimage.center_of_mass(np.ones_like(labels), labels, ids))   # (y, x)
    big = area >= area.max() * 0.1
    column = {}
    for i in ids:
        if area[i - 1] < area.max() * 0.0005:        # stray specks
            continue
        j = i
        if not big[i - 1]:
            j = int(ids[big][np.argmin(((centre[big] - centre[i - 1]) ** 2).sum(axis=1))])
        column.setdefault(min(ncols - 1, int(centre[j - 1][1] // cell_w)), []).append(i)
    grown = ndimage.grey_dilation(labels, size=(5, 5))   # keep the soft anti-aliased edge
    out = []
    for c in range(ncols):
        if c not in column:
            out.append(None)
            continue
        keep = np.isin(grown, column[c])
        cols = np.where(keep.any(axis=0))[0]
        x0, x1 = int(cols[0]), int(cols[-1]) + 1
        rgba = band.copy()
        rgba[..., 3] = np.where(keep, rgba[..., 3], 0)
        out.append((x0, Image.fromarray(rgba[:, x0:x1])))
    return out


def split_sheet(im, nrows, ncols):
    """Cut one image holding several animations (one per row) into frames.

    Rows are separated at empty horizontal lines; columns at the least-inked vertical
    line near each expected boundary, so frames that touch are still split sensibly."""
    a = im.getchannel("A").point(lambda v: 255 if v > 40 else 0)
    w, h = a.size

    def ink(box):
        return a.crop(box).histogram()[255]

    def cuts(length, n, profile):
        out = [0]
        for i in range(1, n):
            c = round(i * length / n)
            win = max(4, length // (n * 5))
            best = min(range(max(1, c - win), min(length - 1, c + win)), key=lambda x: (profile(x), abs(x - c)))
            out.append(best)
        return out + [length]

    row_profile = lambda y: ink((0, y, w, y + 1))
    ys = cuts(h, nrows, row_profile)
    rows = []
    for r in range(nrows):
        y0, y1 = ys[r], ys[r + 1]
        xs = cuts(w, ncols, lambda x: ink((x, y0, x + 1, y1)))
        # Keep the artist's placement: every frame of a row is cropped with the SAME box,
        # relative to its ideal grid cell, so the cat doesn't jitter between frames.
        cell_w = w / ncols
        blobs = grab_blobs(im, y0, y1, ncols, cell_w)
        cells, union = [], None
        for c in range(ncols):
            ox = round(c * cell_w)
            if blobs:
                if blobs[c] is None:
                    continue
                x0, piece = blobs[c]
            else:
                x0 = xs[c]
                piece = Image.new("RGBA", (xs[c + 1] - xs[c], y1 - y0), (0, 0, 0, 0))
                piece.alpha_composite(im.crop((xs[c], y0, xs[c + 1], y1)))
            bb = piece.getchannel("A").point(lambda v: 255 if v > 24 else 0).getbbox()
            cells.append((ox, x0, piece))
            if bb:
                b = (bb[0] + x0 - ox, bb[1], bb[2] + x0 - ox, bb[3])
                union = b if union is None else (min(union[0], b[0]), min(union[1], b[1]), max(union[2], b[2]), max(union[3], b[3]))
        frames = []
        if union:
            uw, uh = union[2] - union[0], union[3] - union[1]
            for ox, x0, piece in cells:
                f = Image.new("RGBA", (uw, uh), (0, 0, 0, 0))
                f.alpha_composite(piece, (x0 - ox - union[0], -union[1]))
                if f.getbbox():
                    frames.append(f)
        rows.append(stabilize(frames))
    return rows


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--name", required=True)
    ap.add_argument("--out", required=True)
    for k in ROW:
        ap.add_argument(f"--{k}", type=Path)
    ap.add_argument("--sheet", type=Path, help="one image with every animation, one per row")
    ap.add_argument("--grid", default="6x6", help="ROWSxCOLS of --sheet (default 6x6)")
    ap.add_argument("--rows", default="idle,working,thinking,done,attention,sleepy",
                    help="animation name of each --sheet row, in order; use - to skip a row")
    ap.add_argument("--tolerance", type=int, default=40, help="background key tolerance 0–255")
    ap.add_argument("--min-gap", type=int, default=10, help="empty pixels that separate two frames")
    ap.add_argument("--min-area", type=float, default=0.01, help="pieces smaller than this share are merged")
    ap.add_argument("--max-frames", type=int, default=8)
    args = ap.parse_args()

    anims = {}
    if args.sheet:
        nr, nc = (int(x) for x in args.grid.lower().split("x"))
        rows = split_sheet(remove_background(Image.open(args.sheet), args.tolerance), nr, nc)
        for name, frames in zip(args.rows.split(","), rows):
            name = name.strip()
            if name in ROW and frames:
                anims[name] = frames
                print(f"{name:9s} sheet row: {len(frames)} frames")
    elif not args.idle:
        sys.exit("give --idle IMAGE (one image per animation) or --sheet IMAGE (all animations in one)")
    for k in ROW:
        p = getattr(args, k)
        if not p:
            continue
        frames = find_frames(remove_background(Image.open(p), args.tolerance), args.min_gap, args.min_area)
        frames = frames[: args.max_frames]
        print(f"{k:9s} {p.name}: {len(frames)} frames" + ("" if len(frames) == 6 else "  ⚠ expected 6"))
        if not frames:
            sys.exit(f"no frames found in {p}")
        anims[k] = frames

    # one shared scale so every animation has the same character size
    max_w = max(f.width for fr in anims.values() for f in fr)
    max_h = max(f.height for fr in anims.values() for f in fr)
    scale = min((FW - 2 * PAD_X) / max_w, (BASELINE - PAD_TOP) / max_h)

    sheet = Image.new("RGBA", (COLS * FW, ROWS * FH), (0, 0, 0, 0))
    for r in range(ROWS):
        name = next((k for k, v in ROW.items() if v == r), "idle")
        # rows the app has no art for stay empty, so it can fall back sensibly (e.g. worried → sleepy)
        if name not in anims and name in ("worried", "thinking", "sleepy", "attention", "done"):
            continue
        frames = anims.get(name) or anims.get("idle") or next(iter(anims.values()))
        for c, f in enumerate(frames):
            f = f.resize((max(1, round(f.width * scale)), max(1, round(f.height * scale))), Image.LANCZOS)
            x = c * FW + (FW - f.width) // 2
            y = r * FH + BASELINE - f.height
            sheet.alpha_composite(f, (x, max(r * FH, y)))

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    sheet.save(out / "spritesheet.webp", lossless=True, quality=100)
    slug = re.sub(r"[^a-z0-9]+", "-", args.name.lower()).strip("-") or "pet"
    (out / "pet.json").write_text(json.dumps(
        {"id": slug, "displayName": args.name, "spritesheetPath": "spritesheet.webp"}, indent=2) + "\n")

    order = [k for k in ROW if k in anims]
    prev = Image.new("RGBA", (6 * FW, len(order) * FH), (34, 34, 40, 255))
    for i, k in enumerate(order):
        prev.alpha_composite(sheet.crop((0, ROW[k] * FH, 6 * FW, ROW[k] * FH + FH)), (0, i * FH))
    prev.save(out / "preview.png")
    print(f"✓ wrote {out}/spritesheet.webp, pet.json, preview.png  (scale {scale:.3f})")


if __name__ == "__main__":
    main()
