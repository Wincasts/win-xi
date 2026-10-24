#!/usr/bin/env python3
"""Generate original, tintable party bar textures. Requires Pillow.

Run from any directory; preserves the bundled XivParty textures.
The front atlas reserves its final four columns for the existing cap UVs.
"""
from pathlib import Path
import math
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1] / 'addons/party/assets/bars'
S = 4
WINXI = Path(__file__).resolve().parents[1] / 'addons/libs/winxi/assets/bars'
STYLES = ('glass', 'detailed', 'crystal', 'satin', 'runic', 'classic', 'radiant', 'chrome', 'flat', 'segmented', 'ember', 'kingdom', 'magitek', 'aether', 'elven', 'gothic',
          'enamel', 'enamel_rim', 'enamel_gradient', 'tube', 'tube_deep', 'glass_enamel')
LABELS = {'classic': 'CLASSIC FF', 'enamel_rim': 'ENAMEL (LIT RIM)', 'enamel_gradient': 'ENAMEL (GRADIENT)', 'tube': 'GLASS TUBE',
          'tube_deep': 'GLASS TUBE (DEEP)', 'glass_enamel': 'GLASS ENAMEL'}
# Smooth sets: shaded from top to bottom only, with nothing along the bar, so that the fill looks the same
# however far it is stretched. Their frames are the quiet thin ones of satin and the rest.
SMOOTH = ('enamel', 'enamel_rim', 'enamel_gradient', 'tube', 'tube_deep', 'glass_enamel')


def bump(t, centre, width):
    return math.exp(-((t - centre) / width) ** 2)


def smooth(style, t):
    """How light a smooth set's fill is at t, 0 at its top to 1 at its foot, from 0 to 1."""
    if style == 'enamel':
        # a bright upper half and a deeper lower one, softly parted, as the game's own bars are
        v = (0.97 - 0.12 * t if t < 0.5 else 0.70 - 0.12 * (t - 0.5)) * (1 - 0.25 * bump(t, 1, 0.08))
    elif style == 'enamel_rim':
        v = (0.90 - 0.10 * t if t < 0.48 else 0.64 + 0.10 * (t - 0.5)) + 0.12 * bump(t, 0.04, 0.05) - 0.18 * bump(t, 1, 0.07)
    elif style == 'enamel_gradient':
        v = (1.0 - 0.35 * t if t < 0.5 else 0.60 + 0.30 * (t - 0.5) ** 1.5) * (1 - 0.2 * bump(t, 1, 0.07))
    elif style == 'tube':
        # round like a tube: dark at its edges, a highlight a quarter of the way down, light along the foot
        v = 0.42 + 0.40 * math.sin(math.pi * t) ** 0.5 + 0.30 * bump(t, 0.26, 0.11) + 0.12 * bump(t, 0.88, 0.08)
    elif style == 'tube_deep':
        v = 0.30 + 0.45 * math.sin(math.pi * t) ** 0.8 + 0.45 * bump(t, 0.22, 0.08) + 0.18 * bump(t, 0.86, 0.07)
    else:  # glass_enamel: the enamel's two halves with the tube's highlight
        v = (0.84 if t < 0.5 else 0.64) + 0.25 * bump(t, 0.2, 0.07) + 0.12 * bump(t, 0.9, 0.07) - 0.15 * bump(t, 1, 0.05) - 0.06 * bump(t, 0.5, 0.04)
    return max(0.0, min(1.0, v))


def canvas(w, h):
    return Image.new('RGBA', (w * S, h * S))


def box(draw, bounds, color, radius=0):
    bounds = tuple(round(v * S) for v in bounds)
    if radius:
        draw.rounded_rectangle(bounds, radius=round(radius * S), fill=color)
    else:
        draw.rectangle(bounds, fill=color)


def save(image, path):
    image.resize((image.width // S, image.height // S), Image.Resampling.LANCZOS).save(path)


def generate(style, kind, width, height, cap_height):
    folder = ROOT / style
    folder.mkdir(parents=True, exist_ok=True)
    top, bottom = 6, height - 6
    back = canvas(width, height)
    d = ImageDraw.Draw(back)
    if style == 'kingdom':
        # A flat, square field with no highlight, so the empty part of the bar reads as one plain
        # void under the rail, with a shadow line under the top rail.
        box(d, (5, top - 1, width - 5, bottom + 1), (8, 8, 8, 250))
        for y in range(top * S, bottom * S):
            t = (y / S - top) / (bottom - top)
            v = int(18 + 10 * t)
            d.line((6 * S, y, (width - 6) * S, y), fill=(v, v, v, 240))
        box(d, (6, top, width - 6, top + .75), (4, 4, 4, 255))
    else:
        box(d, (5, top - 1, width - 5, bottom + 1), (12, 12, 12, 245), 2)
        for y in range(top * S, bottom * S):
            t = (y / S - top) / (bottom - top)
            v = int(22 + 18 * t + 8 * math.exp(-((t - .12) / .15) ** 2))
            d.line((6 * S, y, (width - 6) * S, y), fill=(v, v, v, 235))
    save(back, folder / f'{kind}_back.png')

    fill = canvas(width - 16, height)
    d = ImageDraw.Draw(fill)
    for y in range(top * S, bottom * S):
        t = (y / S - top) / (bottom - top)
        if style in SMOOTH:
            v = 255 * smooth(style, t)
        elif style == 'glass':
            v = 105 + 105 * math.exp(-((t - .14) / .23) ** 2) + 65 * t ** 3
        elif style == 'crystal':
            # A hard central facet and reflected lower edge, rather than a glass gloss.
            v = 220 - 85 * t if t < .48 else 100 + 85 * t
        elif style == 'satin':
            v = 150 + 40 * math.sin(math.pi * t)
        elif style == 'runic':
            v = 95 + 110 * math.exp(-((t - .5) / .30) ** 2)
        elif style == 'radiant':
            # Near-white modulation gives the full HP/MP tint instead of a darkened fill.
            v = 225 + 30 * math.exp(-((t - .22) / .22) ** 2)
        elif style == 'classic':
            v = 225 - 100 * t
        elif style == 'chrome':
            # Polished metal: a hard bright band above, a dark horizon, a soft reflection below.
            v = 245 - 60 * t / .42 if t < .42 else (95 if t < .5 else 110 + 120 * (t - .5))
        elif style == 'flat':
            v = 205
        elif style == 'segmented':
            v = 175 + 45 * math.exp(-((t - .2) / .2) ** 2) - 30 * t ** 2
        elif style == 'kingdom':
            v = 245 - 110 * t  # crisp, old-school menu bevel
        elif style == 'magitek':
            v = 205 - 55 * t + 30 * math.cos(t * math.pi * 4)
        elif style == 'aether':
            v = 145 + 105 * math.exp(-((t - .5) / .22) ** 2)
        elif style == 'elven':
            v = 185 + 55 * math.sin(math.pi * t)
        elif style == 'gothic':
            v = 100 + 115 * math.sin(math.pi * t)
        elif style == 'ember':
            # Bright at the core, glowing out to darker edges.
            v = 120 + 130 * math.exp(-((t - .45) / .28) ** 2)
        else:
            v = 115 + 75 * math.exp(-((t - .25) / .32) ** 2) + 30 * t
        d.line((0, y, fill.width, y), fill=(int(v), int(v), int(v), 255))
    if style == 'detailed':
        for x in range(10, width - 16, 12):
            box(d, (x, top + 1, x + .35, bottom - 1), (20, 20, 20, 35))
        for y in range(top + 2, bottom - 1, 2):
            box(d, (0, y, width - 16, y + .15), (240, 240, 240, 20))
    if style == 'crystal':
        for x in range(0, width - 16, 28):
            d.polygon([(x*S, top*S), ((x+18)*S, top*S), ((x+6)*S, bottom*S), ((x-12)*S, bottom*S)],
                      fill=(240, 240, 240, 38))
    elif style == 'ember':
        # Fine sparks, spread so that they read as a texture however far the fill is stretched.
        for i, x in enumerate(range(5, width - 16, 9)):
            y = top + 1.5 + (i * 7 % 5) * (bottom - top - 3) / 5
            box(d, (x, y, x + .5, y + .5), (255, 255, 255, 70))
    elif style == 'runic':
        for x in range(16, width - 16, 24):
            cy = (top + bottom) / 2
            d.line([(x*S, (cy-2)*S), ((x+3)*S, cy*S), (x*S, (cy+2)*S)],
                   fill=(235, 235, 235, 65), width=S)
    if style == 'aether':
        for x in range(0, width - 16, 22):
            d.polygon([(x*S, bottom*S), ((x+10)*S, top*S), ((x+18)*S, bottom*S)],
                      fill=(245, 245, 245, 65))
    elif style == 'magitek':
        for x in range(6, width - 16, 16):
            box(d, (x, top + 1, x + .5, bottom - 1), (45, 45, 45, 150))
    elif style == 'elven':
        for x in range(0, width - 16, 24):
            d.arc((x*S, (top+1)*S, (x+30)*S, (bottom+4)*S), 190, 340,
                  fill=(255, 255, 255, 80), width=S)
    save(fill, folder / f'{kind}_fill.png')

    front = canvas(width + 6, height)
    d = ImageDraw.Draw(front)
    # Nested bevels, with transparent centre. All RGB is neutral for game tinting.
    box(d, (4, top - 2, width - 4, bottom + 2), (15, 15, 15, 230), 3)
    box(d, (5, top - 1, width - 5, bottom + 1), (155, 155, 155, 255), 2)
    box(d, (6, top, width - 6, bottom), (48, 48, 48, 255), 1)
    box(d, (7, top + 1, width - 7, bottom - 1), (0, 0, 0, 0), 1)
    box(d, (7, top - 1, width - 7, top - .35), (245, 245, 245, 230))
    box(d, (7, bottom + .25, width - 7, bottom + .8), (210, 210, 210, 180))
    if style == 'glass':
        # Broad upper reflection and angled sheen stay fixed as the fill shrinks.
        box(d, (7, top + 1, width - 7, top + 3.4), (255, 255, 255, 38), .6)
        for x, span in ((width * .16, 16), (width * .70, 9)):
            d.polygon([(int(x*S), (top+1)*S), (int((x+span)*S), (top+1)*S),
                       (int((x+span-9)*S), (bottom-1)*S), (int((x-9)*S), (bottom-1)*S)],
                      fill=(255, 255, 255, 17))
    elif style == 'detailed':
        for x in range(12, width - 10, 8):
            box(d, (x, top - 1, x + 2, top - .55), (255, 255, 255, 140))
        for x in (5.3, width - 6.3):
            box(d, (x, top + 2, x + 1, bottom - 2), (210, 210, 210, 255))
    elif style == 'chrome':
        box(d, (7, top + 1, width - 7, top + 1.6), (255, 255, 255, 150))
        box(d, (7, bottom - 1.6, width - 7, bottom - 1), (255, 255, 255, 40))
        for x in (5.4, width - 6.4):
            box(d, (x, top + 1, x + 1, bottom - 1), (235, 235, 235, 255))
    elif style == 'segmented':
        # Ten cells, marked on the frame so that they stay put as the fill empties.
        inner = width - 14
        for cell in range(1, 10):
            x = 7 + inner * cell / 10
            box(d, (x - .45, top + 1, x + .45, bottom - 1), (20, 20, 20, 200))
            box(d, (x + .45, top + 1, x + .8, bottom - 1), (255, 255, 255, 40))
    elif style in ('satin', 'classic', 'radiant', 'flat', 'ember') + SMOOTH:
        # Quiet, thin framing; classic has square corners and a sharp bright top bevel.
        front = canvas(width + 6, height)
        d = ImageDraw.Draw(front)
        radius = 0 if style in ('classic', 'flat') else 1.5
        box(d, (5, top - 1, width - 5, bottom + 1), (30, 30, 30, 255), radius)
        box(d, (6, top, width - 6, bottom), (160, 160, 160, 255), max(0, radius - .5))
        box(d, (7, top + 1, width - 7, bottom - 1), (0, 0, 0, 0))
        if style == 'ember':
            box(d, (6, top, width - 6, top + .5), (255, 255, 255, 200))
            box(d, (6, bottom - .5, width - 6, bottom), (255, 255, 255, 120))
        if style == 'radiant':
            box(d, (6, top, width - 6, top + .7), (255, 255, 255, 255))
            box(d, (7, top + 1, width - 7, top + 1.6), (255, 255, 255, 45))
        if style == 'classic':
            box(d, (6, top, width - 6, top + .6), (255, 255, 255, 255))
            box(d, (6, bottom - .6, width - 6, bottom), (75, 75, 75, 255))
    elif style == 'crystal':
        box(d, (7, top + 1, width - 7, top + 1.5), (255, 255, 255, 80))
        for x in (9, width - 13):
            cy = (top + bottom) / 2
            d.polygon([(x*S, cy*S), ((x+2)*S, (cy-2)*S), ((x+4)*S, cy*S), ((x+2)*S, (cy+2)*S)],
                      fill=(255, 255, 255, 175))
    elif style == 'runic':
        # Marks on the stationary frame stay put as the fill empties.
        for x in range(18, width - 16, 24):
            box(d, (x, top - 1.4, x + .6, top + 1), (255, 255, 255, 210))
            box(d, (x - 1, top - 1.4, x + 1.6, top - .8), (255, 255, 255, 210))
            box(d, (x, bottom - 1, x + .6, bottom + 1.4), (225, 225, 225, 160))
    if style == 'kingdom':
        # A square console-menu rail, not copied game artwork: one dark line, one bright rail and
        # one shade line, and nothing drawn inside, so that the empty part stays plain. At the
        # party addon's scale the earlier four alternating rails smeared into a second inner frame.
        front = canvas(width + 6, height)
        d = ImageDraw.Draw(front)
        for inset, value in ((3, 20), (4, 240), (5, 70)):
            box(d, (inset, top - 5 + inset, width - inset, bottom + 5 - inset), (value, value, value, 255))
        box(d, (7, top + 1, width - 7, bottom - 1), (0, 0, 0, 0))
    elif style == 'magitek':
        for x in range(10, width - 10, 18):
            box(d, (x, top - 2, x + 7, top - 1), (245, 245, 245, 255))
            box(d, (x, bottom + 1, x + 4, bottom + 2), (110, 110, 110, 255))
        for x in (5, width - 7):
            box(d, (x, top - 1, x + 2, bottom + 1), (230, 230, 230, 255))
    elif style == 'aether':
        for x in range(12, width - 12, 30):
            cy = top - .5
            d.polygon([(x*S, (cy-2)*S), ((x+3)*S, cy*S), (x*S, (cy+2)*S), ((x-3)*S, cy*S)],
                      fill=(245, 245, 245, 230))
        box(d, (7, bottom, width - 7, bottom + .7), (255, 255, 255, 230))
    elif style == 'elven':
        for x in range(10, width - 18, 26):
            d.arc((x*S, (top-4)*S, (x+24)*S, (top+2)*S), 0, 180,
                  fill=(245, 245, 245, 240), width=S)
            d.arc((x*S, (bottom-2)*S, (x+24)*S, (bottom+4)*S), 180, 360,
                  fill=(200, 200, 200, 230), width=S)
    elif style == 'gothic':
        for x in range(10, width - 10, 20):
            for y, direction in ((top - 1, -1), (bottom + 1, 1)):
                d.polygon([((x-3)*S, y*S), (x*S, (y+3*direction)*S), ((x+3)*S, y*S)],
                          fill=(190, 190, 190, 255))
        box(d, (7, top + 1, width - 7, top + 1.5), (255, 255, 255, 120))
    # Cap atlas: x=width+2..width+6, y=0..cap_height.
    box(d, (width + 2, 0, width + 5.75, cap_height - .25), (35, 35, 35, 255), .7)
    box(d, (width + 2.7, .5, width + 4.8, cap_height - .75), (155, 155, 155, 255), .4)
    box(d, (width + 3, 1, width + 3.6, cap_height - 1), (245, 245, 245, 255))
    save(front, folder / f'{kind}_front.png')
    if kind == 'hp':
        # winxi.bars draws a bar of any size with the HP art of each set
        shared = WINXI / style
        shared.mkdir(parents=True, exist_ok=True)
        for layer in ('back', 'fill', 'front'):
            (shared / f'{layer}.png').write_bytes((folder / f'hp_{layer}.png').read_bytes())


def glow():
    """The light at the end of a fill: white, as tall as a fill image, brightest at its right edge and fading
    out leftwards. One for every set, drawn over the fill's end and made more or less solid by the theme."""
    width, height = 32, 28
    top, bottom = 6, height - 6
    im = Image.new('RGBA', (width * S, height * S))
    d = ImageDraw.Draw(im)
    for x in range(width * S):
        u = 1 - (x + .5) / (width * S)  # 0 at the right edge
        a = math.exp(-(u / .38) ** 2)
        d.line((x, top * S, x, bottom * S - 1), fill=(255, 255, 255, round(255 * a)))
    save(im, ROOT / 'glow.png')
    (WINXI / 'glow.png').write_bytes((ROOT / 'glow.png').read_bytes())


def preview():
    out = Image.new('RGBA', (780, 65 + len(STYLES) * 130), (19, 24, 33, 255))
    d = ImageDraw.Draw(out)
    font = ImageFont.truetype('DejaVuSans.ttf', 18)
    small = ImageFont.truetype('DejaVuSans.ttf', 14)
    d.text((24, 15), 'XIFRAMES / BAR TEXTURES', font=font, fill='#d9e5ef')
    for row, style in enumerate(STYLES):
        y = 65 + row * 130
        d.text((24, y), LABELS.get(style, style.upper()), font=font, fill='#a9bfd3')
        for col, fraction in enumerate((1, .65, .25)):
            x = 180 + col * 195
            for kind, color, yy, width in [('hp', (232, 94, 112), y, 220),
                                           ('mp', (105, 159, 237), y + 42, 164)]:
                scale = .8
                def layer(name):
                    im = Image.open(ROOT / style / f'{kind}_{name}.png')
                    if name == 'front':
                        im = im.crop((0, 0, width, im.height))
                    r, g, b, a = im.split()
                    channels = [c.point(lambda v, tint=t: round(v*tint/255)) for c, t in zip((r,g,b), color)]
                    return Image.merge('RGBA', (*channels, a))
                back = layer('back').resize((round(width*scale), round((28 if kind=='hp' else 24)*scale)), Image.Resampling.LANCZOS)
                out.alpha_composite(back, (x, yy))
                fill = layer('fill')
                fill = fill.resize((max(1, round((width-16)*scale*fraction)), back.height), Image.Resampling.LANCZOS)
                out.alpha_composite(fill, (x+round(8*scale), yy))
                out.alpha_composite(layer('front').resize(back.size, Image.Resampling.LANCZOS), (x, yy))
            d.text((x+45, y+78), f'{round(fraction*100)}% HP', font=small, fill='#b5c1cd')
    out.convert('RGB').save(ROOT / 'preview.png')


if __name__ == '__main__':
    import sys
    # with sets named, only those are made again, and the others' images are left as they are
    for style in sys.argv[1:] or STYLES:
        generate(style, 'hp', 220, 28, 14)
        generate(style, 'mp', 164, 24, 11)
    glow()
    preview()
    print(f'Generated {len(sys.argv[1:] or STYLES)} texture sets and preview in {ROOT}')
