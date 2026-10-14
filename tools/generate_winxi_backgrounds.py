#!/usr/bin/env python3
"""Original seamless window background tiles for winxi's theme; requires Pillow and numpy.

Each is a 128x128 greyscale tile, near white, so that tinted by the theme's background colour it is
that colour with a quiet texture in it: light at 255, the darkest marks about 70% of it. The tiles
wrap on every side, and are drawn pixel for pixel, side by side. No game artwork is used.
"""
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1] / 'addons/libs/winxi/assets/backgrounds'
N = 128
rng = np.random.default_rng(1999)


def wrapped_noise(cells):
    """Smooth noise that wraps: random values on a cells x cells grid, eased between."""
    grid = rng.random((cells, cells))
    coords = np.arange(N) * cells / N
    i0 = np.floor(coords).astype(int)
    t = coords - i0
    t = t * t * (3 - 2 * t)
    i1 = (i0 + 1) % cells
    a = grid[np.ix_(i0, i0)] * (1 - t)[None, :] + grid[np.ix_(i0, i1)] * t[None, :]
    b = grid[np.ix_(i1, i0)] * (1 - t)[None, :] + grid[np.ix_(i1, i1)] * t[None, :]
    return a * (1 - t)[:, None] + b * t[:, None]


def fractal(octaves):
    total, weight = np.zeros((N, N)), 0
    for octave, cells in enumerate(octaves):
        amount = 0.55 ** octave
        total += wrapped_noise(cells) * amount
        weight += amount
    return total / weight


def to_tile(values, low):
    """values from 0 to 1 into a tile from low (0 to 1) to white"""
    values = (values - values.min()) / max(1e-9, values.max() - values.min())
    grey = (255 * (low + (1 - low) * values)).astype(np.uint8)
    return Image.fromarray(grey, 'L').convert('RGBA')


def grain():
    # stone: soft blotches with a fine speckle through them
    return to_tile(fractal((4, 8, 16)) * .7 + rng.random((N, N)) * .3, .78)


def marble():
    # veins: a sine through fractal noise, its sharp troughs the veins
    y, x = np.mgrid[0:N, 0:N] / N
    warp = fractal((2, 4, 8, 16))
    veins = np.abs(np.sin(2 * np.pi * (x + y + 1.6 * warp)))
    return to_tile(veins ** .35 * .8 + fractal((4, 8)) * .2, .72)


def weave():
    # linen: threads over and under, a little uneven
    y, x = np.mgrid[0:N, 0:N]
    across = 0.5 + 0.5 * np.cos(2 * np.pi * y / 4)
    down = 0.5 + 0.5 * np.cos(2 * np.pi * x / 4)
    over = ((x // 4 + y // 4) % 2) == 0
    cloth = np.where(over, across * .75 + down * .25, down * .75 + across * .25)
    return to_tile(cloth * .8 + fractal((8, 32)) * .2, .8)


def brushed():
    # brushed metal: long fine streaks across, uneven along their length
    streaks = rng.random(N)
    rows = np.repeat(streaks[:, None], N, axis=1)
    along = fractal((2, 4))
    return to_tile(rows * .75 + along * .25, .8)


TILES = {'grain': grain, 'marble': marble, 'weave': weave, 'brushed': brushed}
LABELS = {'plain': 'PLAIN', 'gradient': 'GRADIENT', 'ffxi': 'FFXI-INSPIRED', 'grain': 'GRAIN',
          'marble': 'MARBLE', 'weave': 'WEAVE', 'brushed': 'BRUSHED METAL'}


def shade(color, amount):
    return tuple(min(255, round(c * amount)) for c in color)


def panel(name, w, h, color, tiles):
    """As winxi draws it: see backgrounds.lua"""
    out = Image.new('RGBA', (w, h))
    d = ImageDraw.Draw(out)
    if name in ('gradient', 'ffxi'):
        top, bottom = shade(color, 1.45), shade(color, .75)
        for y in range(h):
            t = y / max(1, h - 1)
            d.line((0, y, w, y), fill=tuple(round(a + (b - a) * t) for a, b in zip(top, bottom)) + (230,))
        if name == 'ffxi':
            lines = Image.new('RGBA', (w, h))
            ld = ImageDraw.Draw(lines)
            for y in range(0, h, 2):
                ld.line((0, y, w, y), fill=(0, 0, 0, 36))
            out.alpha_composite(lines)
    elif name in tiles:
        tile = tiles[name]
        tinted = Image.merge('RGBA', [tile.getchannel(i).point(lambda v, c=c: round(v * c / 255)) for i, c in enumerate(color)] + [Image.new('L', tile.size, 230)])
        for y in range(0, h, N):
            for x in range(0, w, N):
                out.alpha_composite(tinted, (x, y))
    else:
        d.rectangle((0, 0, w, h), fill=color + (230,))
    return out


def preview(tiles):
    names = ['plain', 'gradient', 'ffxi', *TILES]
    columns, w, h = 4, 220, 150
    rows = (len(names) + columns - 1) // columns
    out = Image.new('RGBA', (24 + columns * (w + 24), 60 + rows * (h + 50)), '#3a4a3a')
    d = ImageDraw.Draw(out)
    font = ImageFont.truetype('DejaVuSans.ttf', 17)
    small = ImageFont.truetype('DejaVuSans.ttf', 14)
    d.text((24, 16), 'WINXI / WINDOW BACKGROUNDS (tinted navy, as an example)', font=font, fill='#e8eef6')
    for index, name in enumerate(names):
        x, y = 24 + index % columns * (w + 24), 76 + index // columns * (h + 50)
        d.text((x, y - 24), LABELS[name], font=font, fill='#e8eef6')
        out.alpha_composite(panel(name, w, h, (38, 40, 92), tiles), (x, y))
        d.rectangle((x, y, x + w - 1, y + h - 1), outline='#b0aec8')
        for line, text in enumerate(('Lasko: Teleport-Holla?', 'Rise: WTB Field Gloves', '[Addons] Loaded xiframes')):
            d.text((x + 10, y + 12 + line * 22), text, font=small, fill='#ffffff')
    out.convert('RGB').save(ROOT / 'preview.png')


if __name__ == '__main__':
    ROOT.mkdir(parents=True, exist_ok=True)
    tiles = {}
    for name, make in TILES.items():
        tiles[name] = make()
        tiles[name].save(ROOT / f'{name}.png')
    preview(tiles)
    print(f'Generated {len(tiles)} background tiles and preview in {ROOT}')
