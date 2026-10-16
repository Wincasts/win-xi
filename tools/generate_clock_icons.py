#!/usr/bin/env python3
"""The clock addon's 'gems' icon set: the game's marbled day circles cut as gemstones for the days, and weather icons after the
game's own (font el* in ROM/119/51.DAT: a fireball, an ice sphere, a whirlwind, an earth block, a
bolt, a drop, a glow and a dark swirl), with a sun for a clear sky, which the game has none for.

Usage: python3 tools/generate_clock_icons.py [--output addons/clock/icons/gems]
Requires Pillow and numpy. Each is drawn at 256 pixels and brought down to 32, twice the game's 16,
so that it is crisp where uihook draws it at the game's icon's size.
"""
import argparse
import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

BIG = 256   # drawn at
SIZE = 32   # saved at
C = BIG / 2

# The days' gems, in the colours of the game's day circles (menu colorbal in ROM/119/51.DAT): each
# circle's brightest, middle and darkest tenth, as sampled from it
DAYS = {
    'firesday': ((241, 62, 54), (171, 43, 31), (92, 22, 14)),
    'earthsday': ((220, 215, 45), (176, 173, 31), (106, 102, 18)),
    'watersday': ((121, 117, 198), (85, 82, 151), (48, 46, 85)),
    'windsday': ((81, 185, 96), (43, 145, 58), (21, 79, 31)),
    'iceday': ((167, 201, 209), (128, 170, 189), (80, 116, 136)),
    'lightningday': ((208, 162, 206), (184, 124, 183), (109, 68, 109)),
    'lightsday': ((222, 224, 195), (191, 191, 172), (132, 130, 120)),
    'darksday': ((130, 110, 108), (79, 61, 57), (37, 27, 24)),
}
OUTLINE = (24, 16, 28, 255)
LIGHT = math.radians(225)  # from the top left, as the game lights its icons


def mix(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def shade(color, amount):
    """amount -1 (black) .. 0 (as is) .. 1 (white)"""
    return mix(color, (0, 0, 0), -amount) if amount < 0 else mix(color, (255, 255, 255), amount)


def canvas():
    return Image.new('RGBA', (BIG, BIG), (0, 0, 0, 0))


def outlined(art, width=12, color=OUTLINE):
    """The art with a dark edge all round it, as the game's icons have."""
    alpha = art.getchannel('A').point(lambda a: 255 if a > 40 else 0)
    edge = alpha.filter(ImageFilter.MaxFilter(width * 2 + 1)).filter(ImageFilter.GaussianBlur(1.5))
    under = Image.new('RGBA', art.size, color)
    under.putalpha(edge)
    under.alpha_composite(art)
    return under


def radial(color_in, color_out, center=(C, C), radius=C, power=1.0):
    yy, xx = np.mgrid[0:BIG, 0:BIG]
    t = np.clip(np.hypot(xx - center[0], yy - center[1]) / radius, 0, 1) ** power
    img = np.zeros((BIG, BIG, 4), np.uint8)
    for i in range(3):
        img[..., i] = (color_in[i] + (color_out[i] - color_in[i]) * t).astype(np.uint8)
    img[..., 3] = 255
    return Image.fromarray(img, 'RGBA')


def masked(fill, mask):
    out = canvas()
    out.paste(fill, (0, 0), mask)
    return out


def glint(img, x, y, r, strength=255):
    """A soft white highlight."""
    spot = Image.new('L', (BIG, BIG), 0)
    ImageDraw.Draw(spot).ellipse((x - r, y - r, x + r, y + r), fill=strength)
    spot = spot.filter(ImageFilter.GaussianBlur(r * 0.45))
    white = Image.new('RGBA', (BIG, BIG), (255, 255, 255, 0))
    white.putalpha(Image.fromarray(np.minimum(np.array(spot), np.array(img.getchannel('A'))).astype(np.uint8)))
    img.alpha_composite(white)


def sparkle(img, x, y, r):
    """A four-pointed star of light."""
    d = ImageDraw.Draw(img)
    w = r * 0.18
    d.polygon([(x, y - r), (x + w, y - w), (x + r, y), (x + w, y + w), (x, y + r), (x - w, y + w), (x - r, y), (x - w, y - w)],
              fill=(255, 255, 255, 235))


def save(img, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    img.resize((SIZE, SIZE), Image.LANCZOS).save(path)


# --- the days: the game's marbled circles, cut as gems -----------------------------------------------

def marbling(seed):
    """Soft streaks, as the game's circles are mottled: a few waves, bent by others."""
    rng = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:BIG, 0:BIG] / BIG
    field = np.zeros((BIG, BIG))
    for _ in range(5):
        fx, fy, phase = rng.uniform(2, 6), rng.uniform(2, 6), rng.uniform(0, 6.3)
        bend = np.sin(yy * rng.uniform(3, 7) + rng.uniform(0, 6.3)) * 0.6
        field += np.sin(xx * fx * 6.3 + yy * fy * 3.1 + bend * 3 + phase)
    field = (field - field.min()) / (field.max() - field.min())
    return np.array(Image.fromarray((field * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(6))) / 255.0


def gem(colors, seed):
    light, middle, dark = (np.array(c, np.float32) for c in colors)
    R = BIG * 0.45  # the game's fill fourteen and a half of sixteen
    yy, xx = np.mgrid[0:BIG, 0:BIG]
    nx, ny = (xx - C) / R, (yy - C) / R
    r2 = nx * nx + ny * ny
    nz = np.sqrt(np.clip(1 - r2, 0, 1))
    # lit from the top left and a little in front, as the game's
    lx, ly, lz = -0.5, -0.62, 0.6
    norm = math.sqrt(lx * lx + ly * ly + lz * lz)
    lambert = np.clip((nx * lx + ny * ly + nz * lz) / norm, 0, 1)
    shade_t = lambert ** 0.85
    # dark to middle to light, then the marbling over it
    t = shade_t[..., None]
    rgb = np.where(t < 0.5, dark + (middle - dark) * (t / 0.5), middle + (light - middle) * ((t - 0.5) / 0.5))
    rgb *= (0.86 + 0.28 * marbling(seed))[..., None]
    # a faint cut: an octagonal table, lighter, and its facets' edges
    angle = np.arctan2(ny, nx)
    octagon = np.cos(math.pi / 8) / np.cos(((angle + math.pi / 8) % (math.pi / 4)) - math.pi / 8)
    table = np.sqrt(r2) < 0.5 * octagon
    rgb[table] = rgb[table] * 0.75 + light * 0.34
    facets = np.abs(((angle / (math.pi / 8)) % 1) - 0.5) > 0.44
    edges = facets & ~table & (r2 < 0.92)
    rgb[edges] = rgb[edges] * 0.72 + light * 0.36
    # its rim, darker, as the game's circles' edges are
    rim = np.clip((np.sqrt(r2) - 0.78) / 0.22, 0, 1)[..., None]
    rgb = rgb * (1 - 0.45 * rim) + dark * 0.45 * rim * 0.4
    alpha = np.clip((1 - np.sqrt(r2)) * R / 2.5, 0, 1) * 255
    img = Image.fromarray(np.dstack([rgb.clip(0, 255), alpha]).astype(np.uint8), 'RGBA')
    glint(img, C - R * 0.38, C - R * 0.42, R * 0.2, 235)
    sparkle(img, C - R * 0.4, C - R * 0.44, R * 0.3)
    return outlined(img, 5, tuple(int(v * 0.55) for v in dark) + (255,))


# --- the weather, after the game's ---------------------------------------------------------------

def fireball():
    img = canvas()
    flame = Image.new('L', (BIG, BIG), 0)
    d = ImageDraw.Draw(flame)
    d.ellipse((50, 86, 206, 236), fill=255)
    # tongues rising from it, leaning as it flies
    for cx, top, w in ((92, 26, 34), (134, 8, 40), (176, 40, 30), (66, 62, 24), (202, 78, 22)):
        d.polygon([(cx - w, 140), (cx + 4, top), (cx + w, 140)], fill=255)
    flame = flame.filter(ImageFilter.GaussianBlur(5)).point(lambda a: 255 if a > 110 else 0)
    img = masked(radial((255, 238, 110), (200, 34, 10), center=(122, 168), radius=124, power=0.75), flame)
    core = Image.new('L', (BIG, BIG), 0)
    ImageDraw.Draw(core).ellipse((92, 136, 160, 200), fill=200)
    core = core.filter(ImageFilter.GaussianBlur(16))
    img.alpha_composite(masked(Image.new('RGBA', (BIG, BIG), (255, 250, 200, 255)), core))
    return outlined(img)


def ice():
    img = canvas()
    # a six-sided crystal, its facets lit from the top left
    top, bottom, mid_y = 18, 238, 128
    left, right = 52, 204
    faces = [
        ([(C, top), (left, 84), (C - 10, mid_y)], 0.55),
        ([(C, top), (C - 10, mid_y), (right, 84)], 0.2),
        ([(left, 84), (left + 4, 172), (C - 10, mid_y)], 0.3),
        ([(right, 84), (C - 10, mid_y), (right - 4, 172)], -0.12),
        ([(left + 4, 172), (C, bottom), (C - 10, mid_y)], 0.0),
        ([(C - 10, mid_y), (C, bottom), (right - 4, 172)], -0.3),
    ]
    d = ImageDraw.Draw(img)
    base = (118, 186, 236)
    for points, amount in faces:
        d.polygon(points, fill=shade(base, amount) + (255,))
    for points, _ in faces:
        d.line(points + [points[0]], fill=(235, 250, 255, 170), width=3)
    glint(img, 98, 70, 22, 220)
    sparkle(img, 94, 64, 34)
    return outlined(img)


def whirlwind():
    img = canvas()
    d = ImageDraw.Draw(img)
    base = (52, 190, 150)
    # bands, wide at the top and narrowing to a point, each lit along its upper edge
    bands = [(28, 228, 22, 74), (52, 214, 70, 116), (78, 196, 112, 152), (100, 176, 148, 184), (116, 160, 178, 210), (126, 148, 202, 236)]
    for i, (x0, x1, y0, y1) in enumerate(bands):
        sway = (-1) ** i * 10
        d.ellipse((x0 + sway, y0, x1 + sway, y1), fill=shade(base, -0.25 + 0.06 * i) + (255,))
        d.arc((x0 + sway + 6, y0 + 4, x1 + sway - 6, y1 - 2), 190, 350, fill=shade(base, 0.55) + (255,), width=7)
    d.line([(40, 50), (16, 38)], fill=shade(base, 0.4) + (255,), width=8)
    d.line([(214, 98), (240, 88)], fill=shade(base, 0.4) + (255,), width=7)
    return outlined(img)


def earth():
    img = canvas()
    d = ImageDraw.Draw(img)
    base = (196, 164, 44)
    # a block seen from above a corner: its top, its left and its right
    top = [(128, 26), (226, 78), (128, 130), (30, 78)]
    left = [(30, 78), (128, 130), (128, 232), (40, 176)]
    right = [(128, 130), (226, 78), (216, 176), (128, 232)]
    d.polygon(top, fill=shade(base, 0.35) + (255,))
    d.polygon(left, fill=shade(base, -0.05) + (255,))
    d.polygon(right, fill=shade(base, -0.38) + (255,))
    # cracks and grain
    for line in ([(70, 120), (96, 150), (88, 190)], [(160, 154), (182, 132), (196, 160)], [(100, 70), (134, 84), (150, 70)]):
        d.line(line, fill=shade(base, -0.55) + (255,), width=5)
    d.line(top + [top[0]], fill=shade(base, 0.6) + (200,), width=3)
    return outlined(img)


def bolt():
    img = canvas()
    path = [(150, 10), (66, 128), (122, 132), (82, 246), (196, 104), (138, 102), (190, 10)]
    glow = Image.new('L', (BIG, BIG), 0)
    ImageDraw.Draw(glow).polygon(path, fill=255)
    halo = glow.filter(ImageFilter.MaxFilter(25)).filter(ImageFilter.GaussianBlur(10))
    img.alpha_composite(masked(Image.new('RGBA', (BIG, BIG), (150, 80, 230, 255)), halo.point(lambda a: a * 0.75)))
    img.alpha_composite(masked(radial((255, 240, 255), (146, 62, 220), center=(130, 110), radius=150, power=0.7), glow))
    d = ImageDraw.Draw(img)
    d.line([(152, 26), (100, 112), (128, 118), (104, 196)], fill=(255, 255, 255, 230), width=7)
    return outlined(img, 10)


def drop():
    img = canvas()
    shape = Image.new('L', (BIG, BIG), 0)
    d = ImageDraw.Draw(shape)
    d.ellipse((48, 92, 208, 244), fill=255)
    d.polygon([(128, 8), (58, 140), (198, 140)], fill=255)
    shape = shape.filter(ImageFilter.GaussianBlur(4)).point(lambda a: 255 if a > 128 else 0)
    img = masked(radial((170, 232, 246), (30, 110, 170), center=(104, 150), radius=130, power=0.9), shape)
    glint(img, 98, 150, 26, 230)
    d = ImageDraw.Draw(img)
    d.arc((70, 112, 186, 226), 100, 170, fill=(230, 250, 255, 200), width=6)
    return outlined(img)


def glow():
    img = canvas()
    halo = Image.new('L', (BIG, BIG), 0)
    ImageDraw.Draw(halo).ellipse((28, 28, 228, 228), fill=210)
    halo = halo.filter(ImageFilter.GaussianBlur(14))
    img.alpha_composite(masked(radial((255, 255, 255), (214, 196, 222), radius=110, power=1.4), halo))
    orb = Image.new('L', (BIG, BIG), 0)
    ImageDraw.Draw(orb).ellipse((64, 64, 192, 192), fill=255)
    img.alpha_composite(masked(radial((255, 255, 255), (236, 222, 236), radius=64, power=2), orb.filter(ImageFilter.GaussianBlur(3))))
    sparkle(img, C, C, 112)
    sparkle(img, C, C, 70)
    edge = outlined(img, 8, (90, 70, 96, 255))
    return edge


def swirl():
    img = canvas()
    disc = Image.new('L', (BIG, BIG), 0)
    ImageDraw.Draw(disc).ellipse((26, 26, 230, 230), fill=255)
    img = masked(radial((214, 120, 214), (112, 40, 128), radius=104, power=0.8), disc)
    d = ImageDraw.Draw(img)
    # a spiral of dark arms drawn in towards a dark middle, each with a light edge, as the game's
    for arm in range(3):
        points = []
        for step in range(60):
            t = step / 59
            angle = arm * 2 * math.pi / 3 + t * 3.2 * math.pi
            r = 100 * (1 - t) + 10
            points.append((C + r * math.cos(angle), C + r * math.sin(angle)))
        d.line(points, fill=(52, 10, 64, 255), width=16)
        d.line([(x + 5, y - 5) for x, y in points[:45]], fill=(236, 170, 236, 150), width=4)
    d.ellipse((C - 20, C - 20, C + 20, C + 20), fill=(24, 0, 32, 255))
    return outlined(img)


def sun():
    img = canvas()
    d = ImageDraw.Draw(img)
    # short rays, then the disc over them
    for i in range(12):
        a = i * math.pi / 6
        long = 122 if i % 2 == 0 else 106
        w = 0.17
        d.polygon([(C + 70 * math.cos(a - w), C + 70 * math.sin(a - w)), (C + long * math.cos(a), C + long * math.sin(a)),
                   (C + 70 * math.cos(a + w), C + 70 * math.sin(a + w))], fill=(255, 176, 38, 255))
    disc = Image.new('L', (BIG, BIG), 0)
    ImageDraw.Draw(disc).ellipse((C - 74, C - 74, C + 74, C + 74), fill=255)
    img.alpha_composite(masked(radial((255, 252, 196), (246, 150, 20), center=(C - 20, C - 22), radius=110, power=0.9), disc))
    glint(img, C - 26, C - 28, 24, 200)
    return outlined(img, 10, (70, 34, 10, 255))


WEATHER = {
    'fire': fireball, 'ice': ice, 'wind': whirlwind, 'earth': earth,
    'thunder': bolt, 'water': drop, 'light': glow, 'dark': swirl, 'clear': sun,
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', default=str(Path(__file__).resolve().parents[1] / 'addons/clock/icons/gems'))
    args = parser.parse_args()
    out = Path(args.output)
    for seed, (name, colors) in enumerate(DAYS.items()):
        save(gem(colors, seed), out / 'days' / f'{name}.png')
    for name, draw in WEATHER.items():
        save(draw(), out / 'weather' / f'{name}.png')
    print(f'{len(DAYS)} days and {len(WEATHER)} weather icons in {out}')


if __name__ == '__main__':
    main()
