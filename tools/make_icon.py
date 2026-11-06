#!/usr/bin/env python3
"""Draws SnapSack's app icon: a soft canvas satchel with a screenshot card and a cursor coming out of it,
in ink on warm paper. Lines have varying weight and no perfectly straight edges, so it reads as drawn, not built.

Output: Resources/AppIcon.png (1024x1024).   Needs Pillow:  pip3 install pillow
"""
import math
import os
import random
import sys

from PIL import Image, ImageDraw, ImageFilter

K = 2                                   # supersampling
S = 1024 * K
INK = (36, 32, 28, 255)
PAPER = (246, 239, 226, 255)
CANVAS = (255, 251, 243, 255)
FLAP = (238, 226, 203, 255)
CARD = (255, 255, 255, 255)
SKY = (226, 236, 240, 255)
HILL = (120, 132, 112, 255)
SUN = (238, 186, 96, 255)
TILE = (100 * K, 100 * K, 924 * K, 924 * K)
TILE_RADIUS = 200 * K

rng = random.Random(4)


def scale(points):
    return [(x * K, y * K) for x, y in points]


def smooth(points, closed=True, seg=24):
    """Catmull-Rom through the control points: organic curves, no kinks. Input and output are K-scaled."""
    n = len(points)
    out = []
    edges = range(n) if closed else range(n - 1)
    for i in edges:
        if closed:
            p0, p1, p2, p3 = points[(i - 1) % n], points[i], points[(i + 1) % n], points[(i + 2) % n]
        else:
            p0 = points[max(i - 1, 0)]
            p1 = points[i]
            p2 = points[i + 1]
            p3 = points[min(i + 2, n - 1)]
        for s in range(seg):
            t = s / seg
            t2, t3 = t * t, t * t * t
            x = 0.5 * (2 * p1[0] + (-p0[0] + p2[0]) * t
                       + (2 * p0[0] - 5 * p1[0] + 4 * p2[0] - p3[0]) * t2
                       + (-p0[0] + 3 * p1[0] - 3 * p2[0] + p3[0]) * t3)
            y = 0.5 * (2 * p1[1] + (-p0[1] + p2[1]) * t
                       + (2 * p0[1] - 5 * p1[1] + 4 * p2[1] - p3[1]) * t2
                       + (-p0[1] + 3 * p1[1] - 3 * p2[1] + p3[1]) * t3)
            out.append((x, y))
    if not closed:
        out.append(points[-1])
    return out


def resample(points, step):
    """Even spacing along the path, so the dots of a pen line overlap into a solid line."""
    out = [points[0]]
    carry = 0.0
    for (x0, y0), (x1, y1) in zip(points, points[1:]):
        seg = math.hypot(x1 - x0, y1 - y0)
        if seg == 0:
            continue
        t = step - carry
        while t <= seg:
            f = t / seg
            out.append((x0 + (x1 - x0) * f, y0 + (y1 - y0) * f))
            t += step
        carry = seg - (t - step)
    return out


def ink(draw, pts, width, color=INK, closed=False, pressure=0.12):
    """A pen line: a chain of dots whose size varies gently along the stroke, so it isn't a uniform vector line."""
    phase = rng.uniform(0, 6.28)
    seq = resample(pts + pts[:1] if closed else pts, 1.2 * K)
    n = len(seq)
    for i, (x, y) in enumerate(seq):
        wobble = 1 + pressure * math.sin(i * 0.11 + phase)
        r = max(1.0, width * K * wobble / 2)
        draw.ellipse([x - r, y - r, x + r, y + r], fill=color)


def fill(draw, pts, color):
    draw.polygon(pts, fill=color)


def rotate(points, center, degrees):
    a = math.radians(degrees)
    ca, sa = math.cos(a), math.sin(a)
    cx, cy = center
    return [(cx + (x - cx) * ca - (y - cy) * sa, cy + (x - cx) * sa + (y - cy) * ca) for x, y in points]


def translate(points, dx, dy):
    return [(x + dx, y + dy) for x, y in points]


def grain(layer_size, count):
    """Paper fibre: faint specks, a little denser at the edges."""
    g = Image.new("RGBA", layer_size, (0, 0, 0, 0))
    d = ImageDraw.Draw(g)
    w, h = layer_size
    for _ in range(count):
        x, y = rng.uniform(0, w), rng.uniform(0, h)
        a = rng.randint(5, 16)
        r = rng.uniform(0.6, 1.8) * K
        d.ellipse([x - r, y - r, x + r, y + r], fill=(92, 72, 46, a))
    return g


def main(out_path):
    # 1. Paper tile, with a soft shadow under it.
    base = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    shadow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        [TILE[0], TILE[1] + 12 * K, TILE[2], TILE[3] + 12 * K], TILE_RADIUS, fill=(40, 30, 20, 80))
    base.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(14 * K)))

    tile_mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(tile_mask).rounded_rectangle(TILE, TILE_RADIUS, fill=255)

    paper = Image.new("RGBA", (S, S), PAPER)
    paper.putalpha(tile_mask)
    base.alpha_composite(paper)

    # 2. The artwork, drawn on its own layer and clipped to the tile.
    art = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(art)

    # A soft ground shadow under the satchel.
    ground = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    ImageDraw.Draw(ground).ellipse([300 * K, 800 * K, 724 * K, 846 * K], fill=(60, 44, 30, 70))
    ground = ground.filter(ImageFilter.GaussianBlur(16 * K))
    art.alpha_composite(ground)
    d = ImageDraw.Draw(art)

    # Photo card, sticking out of the top of the satchel.
    card_local = [(-124, -92), (126, -100), (121, 94), (-118, 99)]
    card = translate(rotate(card_local, (0, 0), 8), 598, 318)
    card_pts = smooth(scale(card), seg=10)
    fill(d, card_pts, CARD)
    ink(d, card_pts, 9, closed=True)

    sky_local = [(-98, -68), (100, -76), (96, 52), (-94, 58)]
    sky = scale(translate(rotate(sky_local, (0, 0), 8), 598, 318))
    fill(d, smooth(sky, seg=8), SKY)

    sun_c = translate(rotate([(64, -34)], (0, 0), 8), 598, 318)[0]
    sr = 20 * K
    d.ellipse([sun_c[0] * K - sr, sun_c[1] * K - sr, sun_c[0] * K + sr, sun_c[1] * K + sr], fill=SUN)

    hill = scale(translate(rotate([(-98, 44), (-44, -2), (-6, 26), (40, -20), (98, 46), (98, 60), (-98, 60)],
                                  (0, 0), 8), 598, 318))
    fill(d, smooth(hill, closed=False, seg=10), HILL)

    # Satchel body: a soft pouch, wider at the bottom, with an uneven mouth.
    pouch_ctrl = [(296, 468), (384, 436), (512, 430), (640, 438), (728, 468),
                  (756, 566), (764, 668), (734, 764), (640, 818),
                  (512, 832), (384, 816), (292, 764), (262, 664), (270, 566)]
    pouch = smooth(scale(pouch_ctrl), seg=18)
    fill(d, pouch, CANVAS)
    ink(d, pouch, 15, closed=True)

    # Flap: drapes over the mouth, a little uneven, with a separate line along its lower edge.
    flap_ctrl = [(282, 520), (362, 470), (486, 462), (604, 486), (740, 514),
                 (722, 556), (604, 540), (480, 528), (358, 550), (300, 572)]
    flap = smooth(scale(flap_ctrl), seg=18)
    fill(d, flap, FLAP)
    ink(d, flap, 12, closed=True)

    # Clasp: an uneven blob, ink-filled.
    clasp_ctrl = [(512 + 30 * math.cos(a) * (1 + 0.1 * math.sin(3 * a)),
                   566 + 26 * math.sin(a) * (1 + 0.08 * math.cos(2 * a))) for a in
                  [i * math.tau / 9 for i in range(9)]]
    clasp = smooth(scale(clasp_ctrl), seg=10)
    fill(d, clasp, INK)

    # Cursor: pointing out of the satchel, over the card. A pale halo lifts it off what's behind.
    arrow_rel = [(0, 0), (0, 252), (68, 192), (114, 302), (160, 282), (114, 184), (208, 184)]
    arrow = rotate(translate([(x * 0.94, y * 0.94) for x, y in arrow_rel], 432, 292), (432, 292), 12)
    arrow_pts = scale(arrow)
    halo = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    hd = ImageDraw.Draw(halo)
    hd.polygon(arrow_pts, fill=(255, 251, 243, 255))
    hd.line(arrow_pts + arrow_pts[:1], fill=(255, 251, 243, 255), width=44 * K, joint="curve")
    art.alpha_composite(halo)
    d = ImageDraw.Draw(art)
    fill(d, arrow_pts, INK)
    ink(d, arrow_pts, 6, closed=True, pressure=0.1)

    # Grain over the artwork, then clip everything to the tile.
    art.alpha_composite(grain((S, S), 7000))

    clipped = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    clipped.paste(art, (0, 0), tile_mask)
    base.alpha_composite(clipped)

    out = base.resize((1024, 1024), Image.LANCZOS)
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    out.save(out_path)
    print("wrote", out_path)


if __name__ == "__main__":
    here = os.path.dirname(os.path.abspath(__file__))
    main(sys.argv[1] if len(sys.argv) > 1 else os.path.join(here, "..", "Resources", "AppIcon.png"))
