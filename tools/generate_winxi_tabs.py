#!/usr/bin/env python3
"""Original tab textures for winxi's theme; requires Pillow and numpy.

Each is a 64x24 image drawn over a tab of a window on the game screen, on top of the tab imgui draws
in the theme's colours: white where the tab is to be lighter and black where it is to be darker, both
faint, and clear where it is left alone. So it keeps whatever colour the tab is, chosen or not or
under the mouse, and only gives it a texture. The first and last 4 columns are the tab's left and
right edges; the 56 between them are repeated across the tab, and wrap. Every row is stretched to the
tab's height. No game artwork is used. See libs/winxi/tabs.lua.
"""
from pathlib import Path
import numpy as np
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1] / 'addons/libs/winxi/assets/tabs'
W, H, CAP = 64, 24, 4
M = W - 2 * CAP  # the repeated middle
rng = np.random.default_rng(2026)


def middle_x():
    """for each column, where it falls in the repeated middle: the caps carry on from it"""
    return (np.arange(W) - CAP) % M


def wrapped_noise(cells_x, cells_y):
    """smooth noise that wraps across the middle, eased between random values on a grid"""
    grid = rng.random((cells_y + 1, cells_x))
    xs = middle_x() * cells_x / M
    x0 = np.floor(xs).astype(int)
    tx = xs - x0
    tx = tx * tx * (3 - 2 * tx)
    x1 = (x0 + 1) % cells_x
    ys = np.arange(H) * cells_y / H
    y0 = np.floor(ys).astype(int)
    ty = ys - y0
    ty = ty * ty * (3 - 2 * ty)
    y1 = y0 + 1
    a = grid[np.ix_(y0, x0)] * (1 - tx)[None, :] + grid[np.ix_(y0, x1)] * tx[None, :]
    b = grid[np.ix_(y1, x0)] * (1 - tx)[None, :] + grid[np.ix_(y1, x1)] * tx[None, :]
    return a * (1 - ty)[:, None] + b * ty[:, None]


def rows():
    """each pixel's row, 0 at the top and 1 at the foot"""
    return np.repeat((np.arange(H) / (H - 1))[:, None], W, axis=1)


def to_image(light):
    """light from -1 to 1 into white (more than 0) or black (less), as faint as it is near 0"""
    light = np.clip(light, -1, 1)
    grey = np.where(light > 0, 255, 0).astype(np.uint8)
    alpha = (np.abs(light) * 255).round().astype(np.uint8)
    return Image.merge('RGBA', [Image.fromarray(grey, 'L')] * 3 + [Image.fromarray(alpha, 'L')])


def edges(light, top=0.0, foot=0.0, left=0.0, right=0.0):
    """a line of a pixel along each edge, lighter (more than 0) or darker"""
    light[0, :] += top
    light[-1, :] += foot
    light[:, 0] += left
    light[:, -1] += right
    return light


def glass():
    # a bright upper half that stops sharp at the middle, a little darker below
    y = rows()
    light = np.where(y < 0.46, 0.30 - 0.16 * y / 0.46, -0.16 * (y - 0.46) / 0.54)
    return edges(light, top=0.20)


def bevel():
    # raised: light along the top and left, dark along the foot and right
    y = rows()
    light = 0.08 * (1 - y) - 0.08 * y
    light[1, :] += 0.14
    light[-2, :] -= 0.16
    light[:, 1] += 0.10
    light[:, -2] -= 0.12
    return edges(light, top=0.34, foot=-0.40, left=0.24, right=-0.30)


def brushed():
    # brushed metal: fine streaks across, uneven along their length, under a soft light at the top
    streaks = rng.random(H) - 0.5
    along = wrapped_noise(4, 2) - 0.5
    light = streaks[:, None] * 0.26 + along * 0.10 + 0.10 * (1 - rows()) - 0.06
    return edges(light, top=0.16)


def grain():
    # stone: soft blotches with a fine speckle through them
    speckle = rng.random((H, M))[:, middle_x()] - 0.5
    blotches = wrapped_noise(7, 4) - 0.5
    light = blotches * 0.22 + speckle * 0.16 + 0.06 * (1 - 2 * rows())
    return edges(light, top=0.14, foot=-0.18)


def lined():
    # after the game's own windows: lighter at the top, darker at the foot, a fine dark line every other row
    y = rows()
    light = 0.20 * (1 - y) - 0.20 * y
    light[1::2, :] -= 0.14
    return edges(light, top=0.12)


def satin():
    # soft folds of light running across on a slant, wrapping with the middle
    x = middle_x()[None, :] / M
    y = rows()
    folds = np.sin(2 * np.pi * (2 * x + 0.6 * y))
    light = 0.13 * folds + 0.10 * (1 - y) - 0.06 * y
    return edges(light, top=0.12)


TEXTURES = {'glass': glass, 'bevel': bevel, 'brushed': brushed, 'grain': grain, 'lined': lined, 'satin': satin}
LABELS = {'plain': 'PLAIN', 'sheen': 'SHEEN', 'glass': 'GLASS', 'bevel': 'BEVEL', 'brushed': 'BRUSHED METAL',
          'grain': 'GRAIN', 'lined': 'FFXI-INSPIRED', 'satin': 'SATIN'}


def sheen():
    """as tabs.lua draws its Sheen: light at the top, fading out by the middle, then dark to the foot"""
    y = rows()
    light = np.where(y < 0.5, 0.22 * (1 - y / 0.5), -0.28 * (y - 0.5) / 0.5)
    return to_image(light)


def tab(texture, w, h, color):
    """one tab as winxi draws it: imgui's own in color, then the texture over it, caps and middle"""
    out = Image.new('RGBA', (w, h))
    ImageDraw.Draw(out).rounded_rectangle((0, 0, w - 1, h + 4), radius=4, fill=color)
    if texture is not None:
        strip = Image.new('RGBA', (w, H))
        strip.alpha_composite(texture.crop((0, 0, CAP, H)), (0, 0))
        for x in range(CAP, w - CAP, M):
            piece = texture.crop((CAP, 0, CAP + min(M, w - CAP - x), H))
            strip.alpha_composite(piece, (x, 0))
        strip.alpha_composite(texture.crop((W - CAP, 0, W, H)), (w - CAP, 0))
        mask = Image.new('L', (w, h))
        ImageDraw.Draw(mask).rounded_rectangle((0, 0, w - 1, h + 4), radius=4, fill=255)
        over = strip.resize((w, h), Image.BILINEAR)
        over.putalpha(Image.fromarray((np.array(over.getchannel('A')) * (np.array(mask) / 255)).astype(np.uint8)))
        out.alpha_composite(over)
    return out


def bar_line(out, left, right, y, chosen_left, chosen_right, styled, color):
    """the line under the tabs as tabs.lua draws it, or imgui's own for Plain"""
    d = ImageDraw.Draw(out)
    if not styled:
        d.line((left, y - 1, right - 1, y - 1), fill=color)
        return
    over = Image.new('RGBA', out.size)
    od = ImageDraw.Draw(over)
    rgb = color[:3]
    od.rectangle((left, y - 1, right - 1, y), fill=rgb + (255,))
    od.line((left, y + 1, right - 1, y + 1), fill=(0, 0, 0, 76))
    od.line((left, y + 2, right - 1, y + 2), fill=(0, 0, 0, 38))
    od.rectangle((chosen_left, y - 1, chosen_right - 1, y), fill=tuple(min(255, round(c * 1.25)) for c in rgb) + (255,))
    od.line((chosen_left, y - 1, chosen_right - 1, y - 1), fill=(255, 255, 255, 110))
    out.alpha_composite(Image.alpha_composite(Image.new('RGBA', out.size), over))


def preview(textures):
    names = ['plain', 'sheen', *TEXTURES]
    columns, w, h = 4, 230, 70
    rows_ = (len(names) + columns - 1) // columns
    out = Image.new('RGBA', (24 + columns * (w + 24), 60 + rows_ * (h + 50)), '#3a4a3a')
    d = ImageDraw.Draw(out)
    font = ImageFont.truetype('DejaVuSans.ttf', 17)
    small = ImageFont.truetype('DejaVuSans.ttf', 14)
    d.text((24, 16), 'WINXI / TAB STYLES (the chosen tab first, over a navy window)', font=font, fill='#e8eef6')
    chosen, other = (122, 120, 150, 255), (58, 60, 92, 255)
    for index, name in enumerate(names):
        x, y = 24 + index % columns * (w + 24), 76 + index // columns * (h + 50)
        d.text((x, y - 24), LABELS[name], font=font, fill='#e8eef6')
        d.rectangle((x, y, x + w - 1, y + h - 1), fill=(24, 26, 52), outline='#b0aec8')
        texture = textures.get(name)
        for t, (label, color) in enumerate((('bag', chosen), ('satchel', other), ('ward', other))):
            left, tw = x + 8 + t * 72, 66
            out.alpha_composite(tab(texture, tw, 24, color), (left, y + 12))
            d.text((left + 10, y + 15), label, font=small, fill='#ffffff')
        bar_line(out, x + 8, x + w - 8, y + 36, x + 8, x + 74, name != 'plain', chosen)
    out.convert('RGB').save(ROOT / 'preview.png')


if __name__ == '__main__':
    ROOT.mkdir(parents=True, exist_ok=True)
    textures = {}
    for name, make in TEXTURES.items():
        textures[name] = to_image(make())
        textures[name].save(ROOT / f'{name}.png')
    textures['sheen'] = sheen()
    preview(textures)
    print(f'Generated {len(TEXTURES)} tab textures and preview in {ROOT}')
