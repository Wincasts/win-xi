#!/usr/bin/env python3
"""The info panel's 'classic' icon set: days and weather drawn after the game's own, rather than cut as gems.

The game's day circles (menu colorbal in ROM/119/51.DAT) are flat, mottled marble balls with a small soft
highlight and a darker rim; its weather icons (font el* there) are small soft sprites: a pale teardrop, a teal
funnel, a purple vortex, a periwinkle sphere, a white glow, a fireball with a gold heart, an olive block and a
violet bolt. These are drawn afresh in that manner, in colours sampled from them (none of the game's pixels are
used), with a sun in the same manner for a clear sky, which the game draws none for.

Usage: python3 tools/generate_classic_icons.py [--output addons/libs/winxi/infopanel/icons/classic]
Requires Pillow and numpy. Drawn at 256 pixels and brought down to 32, twice the game's 16.
"""
import argparse
import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

from generate_clock_icons import BIG, C, canvas, masked, outlined, save

# The game's day circles' darkest, middle and lightest tenth (as the gems set samples them)
DAYS = {
    'firesday': ((92, 22, 14), (171, 43, 31), (241, 62, 54)),
    'earthsday': ((106, 102, 18), (176, 173, 31), (220, 215, 45)),
    'watersday': ((48, 46, 85), (85, 82, 151), (121, 117, 198)),
    'windsday': ((21, 79, 31), (43, 145, 58), (81, 185, 96)),
    'iceday': ((80, 116, 136), (128, 170, 189), (167, 201, 209)),
    'lightningday': ((109, 68, 109), (184, 124, 183), (208, 162, 206)),
    'lightsday': ((132, 130, 120), (191, 191, 172), (222, 224, 195)),
    'darksday': ((37, 27, 24), (79, 61, 57), (130, 110, 108)),
}

YY, XX = np.mgrid[0:BIG, 0:BIG].astype(np.float32)


def mottle(seed, cells=12, blur=5):
    """The game's sprites are mottled at about two of their pixels: blotches of light and dark, 0..1"""
    rng = np.random.default_rng(seed)
    coarse = Image.fromarray((rng.random((cells, cells)) * 255).astype(np.uint8)).resize((BIG, BIG), Image.BICUBIC)
    fine = Image.fromarray((rng.random((cells * 2, cells * 2)) * 255).astype(np.uint8)).resize((BIG, BIG), Image.BICUBIC)
    field = np.array(coarse, np.float32) * 0.65 + np.array(fine, np.float32) * 0.35
    field = np.array(Image.fromarray(field.clip(0, 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(blur)), np.float32) / 255
    return (field - field.min()) / max(1e-6, field.max() - field.min())


def ramp(t, dark, middle, light):
    """t 0..1 through dark, middle and light"""
    dark, middle, light = (np.array(c, np.float32) for c in (dark, middle, light))
    t = np.clip(t, 0, 1)[..., None]
    return np.where(t < 0.5, dark + (middle - dark) * (t / 0.5), middle + (light - middle) * ((t - 0.5) / 0.5))


def sphere_light(cx, cy, r):
    """Lambert light on a ball, from the top left and in front, as the game lights its sprites; and the ball's radius 0..1"""
    nx, ny = (XX - cx) / r, (YY - cy) / r
    d = np.sqrt(nx * nx + ny * ny)
    nz = np.sqrt(np.clip(1 - d * d, 0, 1))
    lx, ly, lz = -0.45, -0.55, 0.7
    n = math.sqrt(lx * lx + ly * ly + lz * lz)
    return np.clip((nx * lx + ny * ly + nz * lz) / n, 0, 1), d


def image(rgb, alpha):
    return Image.fromarray(np.dstack([np.clip(rgb, 0, 255), np.clip(alpha, 0, 255)]).astype(np.uint8), 'RGBA')


def soft_spot(img, x, y, r, strength=220, color=(255, 255, 255)):
    """A small soft highlight, kept inside the art"""
    spot = Image.new('L', (BIG, BIG), 0)
    ImageDraw.Draw(spot).ellipse((x - r, y - r, x + r, y + r), fill=strength)
    spot = np.array(spot.filter(ImageFilter.GaussianBlur(r * 0.6)), np.float32)
    inside = np.array(img.getchannel('A'), np.float32) / 255
    top = Image.new('RGBA', (BIG, BIG), color + (0,))
    top.putalpha(Image.fromarray((spot * inside).astype(np.uint8)))
    img.alpha_composite(top)


def edge(img, color, width=6):
    """The game's sprites' thin dark edge"""
    return outlined(img, width, tuple(int(v) for v in color) + (255,))


def shape_alpha(mask, blur=2):
    return np.array(mask.filter(ImageFilter.GaussianBlur(blur)), np.float32)


# --- the days: mottled marble balls ------------------------------------------------------------------

def ball(colors, seed):
    dark, middle, light = colors
    r = BIG * 0.44
    lit, d = sphere_light(C, C, r)
    # flat, as the game's: a little light across it, mostly its blotches
    t = 0.32 + 0.3 * lit + (mottle(seed, 10, 3) - 0.5) * 0.85
    rgb = ramp(t, dark, middle, light)
    rim = np.clip((d - 0.82) / 0.18, 0, 1)[..., None]
    rgb = rgb * (1 - 0.3 * rim) + np.array(dark, np.float32) * 0.3 * rim
    alpha = np.clip((1 - d) * r / 2.5, 0, 1) * 255
    img = image(rgb, alpha)
    soft_spot(img, C - r * 0.12, C - r * 0.2, r * 0.09, 230)
    return edge(img, tuple(v * 0.7 for v in dark), 3)


# --- the weather ----------------------------------------------------------------------------------

def water():
    dark, middle, light = (49, 85, 115), (76, 126, 142), (150, 200, 214)
    mask = Image.new('L', (BIG, BIG), 0)
    d = ImageDraw.Draw(mask)
    d.ellipse((50, 92, 206, 240), fill=255)
    d.polygon([(118, 10), (54, 150), (200, 146)], fill=255)
    alpha = shape_alpha(mask, 4)
    lit, _ = sphere_light(118, 160, 110)
    t = 0.2 + 0.6 * lit + (mottle(11, 10, 3) - 0.5) * 0.7 + np.clip((140 - YY) / 400, 0, 0.15)
    img = image(ramp(t, dark, middle, light), alpha)
    soft_spot(img, 100, 150, 20, 200)
    return edge(img, (22, 40, 56))


def wind():
    dark, middle, light = (13, 52, 46), (49, 121, 107), (110, 186, 168)
    img = canvas()
    noise = mottle(12)
    # bands of the funnel, wide at the top and narrowing down to the left, each lit along its top
    bands = [(30, 236, 24, 80), (48, 218, 66, 118), (64, 196, 106, 154), (78, 170, 144, 186), (88, 148, 176, 214), (92, 128, 204, 240)]
    for i, (x0, x1, y0, y1) in enumerate(bands):
        sway = -i * 6
        band = Image.new('L', (BIG, BIG), 0)
        ImageDraw.Draw(band).ellipse((x0 + sway, y0, x1 + sway, y1), fill=255)
        alpha = shape_alpha(band, 2)
        cy = (y0 + y1) / 2
        t = 0.35 + 0.5 * np.clip((cy - YY) / ((y1 - y0) / 2), -1, 1) * 0.5 + (noise - 0.5) * 0.45 - i * 0.02
        img.alpha_composite(image(ramp(t, dark, middle, light), alpha))
    return edge(img, (8, 26, 22))


def dark():
    dark, middle, light = (43, 8, 43), (96, 34, 96), (150, 76, 150)
    r = BIG * 0.43
    _, d = sphere_light(C, C, r)
    angle = np.arctan2(YY - C, XX - C)
    # a vortex: arms wound in to a black heart
    swirl = 0.5 + 0.5 * np.sin(angle * 3 + d * 9)
    t = 0.15 + 0.55 * swirl * np.clip(d * 1.4, 0, 1) + (mottle(13, 10, 3) - 0.5) * 0.5 - np.clip(0.3 - d, 0, 0.3) * 1.6
    rgb = ramp(t, dark, middle, light)
    alpha = np.clip((1 - d) * r / 2.5, 0, 1) * 255
    return edge(image(rgb, alpha), (20, 0, 22))


def ice():
    dark, middle, light = (66, 62, 142), (132, 125, 231), (190, 186, 255)
    r = BIG * 0.43
    lit, d = sphere_light(C, C, r)
    t = 0.2 + 0.6 * lit + (mottle(14, 10, 3) - 0.5) * 0.6
    img = image(ramp(t, dark, middle, light), np.clip((1 - d) * r / 2.5, 0, 1) * 255)
    soft_spot(img, C - r * 0.3, C - r * 0.35, r * 0.16, 200)
    return edge(img, (34, 30, 80))


def light():
    img = canvas()
    # a soft halo of short rays, then a white heart
    rays = Image.new('L', (BIG, BIG), 0)
    d = ImageDraw.Draw(rays)
    d.ellipse((C - 96, C - 96, C + 96, C + 96), fill=150)
    for i in range(16):
        a = i * math.pi / 8 + 0.1
        long = 126 if i % 2 == 0 else 112
        w = 0.2
        d.polygon([(C + 60 * math.cos(a - w), C + 60 * math.sin(a - w)), (C + long * math.cos(a), C + long * math.sin(a)),
                   (C + 60 * math.cos(a + w), C + 60 * math.sin(a + w))], fill=190)
    rays = shape_alpha(rays, 9)
    dist = np.hypot(XX - C, YY - C) / 120
    halo = ramp(1 - dist + (mottle(15) - 0.5) * 0.3, (96, 84, 92), (170, 150, 160), (255, 243, 255))
    img.alpha_composite(image(halo, rays))
    heart = Image.new('L', (BIG, BIG), 0)
    ImageDraw.Draw(heart).ellipse((C - 74, C - 74, C + 74, C + 74), fill=255)
    lit, _ = sphere_light(C, C, 74)
    core = ramp(0.72 + 0.28 * lit, (200, 180, 196), (236, 226, 236), (255, 250, 255))
    img.alpha_composite(image(core, shape_alpha(heart, 16)))
    return img  # the game's glow has no hard edge


def fire():
    img = canvas()
    flame = Image.new('L', (BIG, BIG), 0)
    d = ImageDraw.Draw(flame)
    d.ellipse((40, 84, 216, 240), fill=255)
    for cx, top, w in ((80, 30, 30), (122, 6, 38), (168, 26, 32), (204, 70, 24), (52, 66, 22)):
        d.polygon([(cx - w, 150), (cx + 6, top), (cx + w, 150)], fill=255)
    alpha = shape_alpha(flame, 6)
    heat = 1 - np.clip(np.hypot((XX - 126) / 1.1, YY - 176) / 130, 0, 1)
    t = heat ** 0.8 + (mottle(16, 10) - 0.5) * 0.4
    rgb = ramp(t, (90, 16, 10), (189, 73, 24), (250, 226, 132))
    # its outer flames darker, as the game's
    rgb = rgb * (0.65 + 0.35 * np.clip(alpha / 255 * 1.4, 0, 1))[..., None]
    return edge(image(rgb, alpha), (41, 9, 8))


def earth():
    img = canvas()
    noise = mottle(17)
    # a slab, tilted: its broad face, a lit top edge and a shaded side, as the game's
    face = [(66, 44), (210, 82), (178, 228), (34, 190)]
    top = [(86, 22), (226, 58), (210, 82), (66, 44)]
    side = [(226, 58), (212, 206), (178, 228), (210, 82)]
    for face, level in ((face, 0.48), (top, 0.85), (side, 0.2)):
        mask = Image.new('L', (BIG, BIG), 0)
        ImageDraw.Draw(mask).polygon(face, fill=255)
        t = level + (noise - 0.5) * 0.4
        img.alpha_composite(image(ramp(t, (90, 80, 16), (123, 109, 8), (220, 202, 112)), shape_alpha(mask, 1.5)))
    return edge(img, (48, 42, 6))


def thunder():
    img = canvas()
    # a bolt corner to corner, its heart white, in a violet glow with dark flecks along it
    path = [(36, 22), (128, 116), (104, 126), (222, 236), (142, 128), (164, 118), (70, 18)]
    bolt = Image.new('L', (BIG, BIG), 0)
    ImageDraw.Draw(bolt).polygon(path, fill=255)
    glow = np.array(bolt.filter(ImageFilter.MaxFilter(51)).filter(ImageFilter.GaussianBlur(10)), np.float32)
    flecks = (mottle(18, 16, 2) > 0.55).astype(np.float32) * (glow > 30)
    halo = ramp(glow / 255 * 0.8 + (mottle(19) - 0.5) * 0.3, (8, 0, 40), (40, 10, 190), (150, 120, 235))
    halo = halo * (1 - 0.75 * flecks[..., None])
    img.alpha_composite(image(halo, glow * 0.9))
    heart = ramp(np.full((BIG, BIG), 0.85), (120, 90, 220), (190, 160, 240), (250, 240, 255))
    img.alpha_composite(image(heart, shape_alpha(bolt, 2)))
    core = Image.new('L', (BIG, BIG), 0)
    ImageDraw.Draw(core).line([(52, 24), (120, 112), (110, 124), (210, 228)], fill=255, width=10)
    img.alpha_composite(image(np.full((BIG, BIG, 3), 255, np.float32), shape_alpha(core, 3)))
    return edge(img, (8, 0, 24), 4)


def clear():
    """No icon of the game's: a sun in the same manner"""
    img = canvas()
    rays = Image.new('L', (BIG, BIG), 0)
    d = ImageDraw.Draw(rays)
    for i in range(12):
        a = i * math.pi / 6
        long = 122 if i % 2 == 0 else 104
        w = 0.18
        d.polygon([(C + 64 * math.cos(a - w), C + 64 * math.sin(a - w)), (C + long * math.cos(a), C + long * math.sin(a)),
                   (C + 64 * math.cos(a + w), C + 64 * math.sin(a + w))], fill=255)
    img.alpha_composite(image(ramp(0.6 + (mottle(20) - 0.5) * 0.4, (150, 70, 10), (226, 140, 30), (255, 210, 90)), shape_alpha(rays, 2)))
    r = 74
    lit, dd = sphere_light(C, C, r)
    t = 0.3 + 0.6 * lit + (mottle(21) - 0.5) * 0.4
    disc = image(ramp(t, (170, 90, 12), (236, 170, 40), (255, 240, 160)), np.clip((1 - dd) * r / 2.5, 0, 1) * 255)
    img.alpha_composite(disc)
    soft_spot(img, C - 22, C - 26, 12, 220)
    return edge(img, (70, 34, 6))


WEATHER = {
    'fire': fire, 'ice': ice, 'wind': wind, 'earth': earth,
    'thunder': thunder, 'water': water, 'light': light, 'dark': dark, 'clear': clear,
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', default=str(Path(__file__).resolve().parents[1] / 'addons/libs/winxi/infopanel/icons/classic'))
    args = parser.parse_args()
    out = Path(args.output)
    for seed, (name, colors) in enumerate(DAYS.items()):
        save(ball(colors, seed), out / 'days' / f'{name}.png')
    for name, draw in WEATHER.items():
        save(draw(), out / 'weather' / f'{name}.png')
    print(f'{len(DAYS)} days and {len(WEATHER)} weather icons in {out}')


if __name__ == '__main__':
    main()
