#!/usr/bin/env python3
"""Original slim bar bookends, one to match each of winxi's window borders; requires Pillow.

16x40 RGBA artwork is drawn at about 4x13px in game, so each is a bold silhouette: a dark outline
that holds against any background, a body lit from the left, and one bright gem or mark at its
centre. No game artwork is used. Includes a preview of each on Radiant HP/MP bars.
"""
from pathlib import Path
from PIL import Image, ImageChops, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1] / 'addons/party/assets'
W, H, S = 16, 40, 4

# shape, then the colours: outline, body, light (the lit side), gem, gem's shine
STYLES = {
    'silver':         ('stud',  (14, 19, 26),  (120, 136, 156), (226, 233, 242), (60, 72, 90),   (240, 246, 255)),
    'bronze':         ('stud',  (24, 15, 9),   (156, 108, 58),  (240, 206, 146), (84, 52, 26),   (255, 232, 184)),
    'mythril':        ('stud',  (10, 18, 32),  (112, 146, 188), (222, 236, 252), (52, 88, 140),  (200, 228, 255)),
    'ffxi':           ('plate', (10, 16, 40),  (140, 150, 184), (226, 230, 244), (48, 60, 104),  (196, 206, 236)),
    'obsidian':       ('plate', (6, 6, 14),    (64, 62, 86),    (150, 148, 178), (24, 22, 38),   (226, 226, 244)),
    'adaman':         ('plate', (20, 7, 7),    (132, 58, 40),   (226, 166, 126), (60, 18, 16),   (255, 214, 184)),
    'royal':          ('spine', (40, 24, 12),  (196, 152, 82),  (255, 238, 186), (110, 40, 52),  (255, 150, 160)),
    'royal_silver':   ('spine', (22, 30, 44),  (150, 168, 192), (246, 250, 255), (52, 76, 120),  (160, 196, 250)),
    'royal_platinum': ('spine', (60, 70, 86),  (206, 216, 230), (255, 255, 255), (130, 150, 180), (255, 255, 255)),
    'crystal':        ('facet', (10, 36, 60),  (84, 172, 212),  (232, 254, 255), (36, 112, 164), (240, 255, 255)),
    'jade':           ('facet', (6, 30, 22),   (72, 160, 120),  (214, 252, 232), (24, 96, 70),   (226, 255, 240)),
    'amethyst':       ('facet', (24, 10, 40),  (142, 100, 196), (244, 228, 255), (84, 44, 132),  (250, 236, 255)),
}
LABELS = {'ffxi': 'FFXI-INSPIRED', 'royal': 'ROYAL GOLD'}


def outline(shape, grow):
    """The shape's points, grown outward from its centre line by grow pixels (or shrunk, if negative)."""
    cx, cy = W / 2, H / 2
    points = []
    for x, y in SHAPES[shape]:
        dx = x - cx
        dy = y - cy
        nx = dx / abs(dx) if dx else 0
        # the ends grow up and down; the sides grow out
        ny = (dy / abs(dy)) if abs(dy) > H / 2 - 3 else 0
        points.append(((x + nx * grow) * S, (y + ny * grow) * S))
    return points


# Each silhouette, its points in the 16x40 grid; all symmetrical, left to right
SHAPES = {
    # a straight rod with rounded studs at each end, as on a riveted frame
    'stud':  ((5, 2), (11, 2), (13, 6), (11, 10), (11, 30), (13, 34), (11, 38), (5, 38), (3, 34), (5, 30), (5, 10), (3, 6)),
    # a long plate with chamfered corners
    'plate': ((4, 1), (12, 1), (14, 4), (14, 36), (12, 39), (4, 39), (2, 36), (2, 4)),
    # a tapered spine with shoulders at each end and a lozenge at its middle
    'spine': ((8, 1), (14, 4), (11, 8), (11, 14), (15, 20), (11, 26), (11, 32), (14, 36), (8, 39),
              (2, 36), (5, 32), (5, 26), (1, 20), (5, 14), (5, 8), (2, 4)),
    # a long cut crystal, pointed at each end and widest at its middle
    'facet': ((8, 0), (13, 8), (14, 20), (13, 32), (8, 40), (3, 32), (2, 20), (3, 8)),
}


def mask(shape, grow):
    im = Image.new('L', (W * S, H * S))
    ImageDraw.Draw(im).polygon(outline(shape, grow), fill=255)
    return im


def generate(name, style):
    shape, edge, body, light, gem, shine = style
    im = Image.new('RGBA', (W * S, H * S))
    im.paste((*edge, 255), mask=mask(shape, .6))
    inside = mask(shape, -.4)
    im.paste((*body, 255), mask=inside)

    # lit from the left: a bright band down the left of the body, a shadow down the right
    left = Image.new('L', im.size)
    ImageDraw.Draw(left).rectangle((0, 0, 7.5 * S, H * S), fill=255)
    im.paste((*light, 255), mask=ImageChops.multiply(inside, ImageChops.offset(left, -2 * S, 0)))
    right = Image.new('L', im.size)
    ImageDraw.Draw(right).rectangle((10 * S, 0, W * S, H * S), fill=90)
    im.paste((*edge, 255), mask=ImageChops.multiply(inside, right))

    d = ImageDraw.Draw(im)
    def poly(points, color):
        d.polygon([(x * S, y * S) for x, y in points], fill=(*color, 255))
    if shape == 'facet':
        # the split down the middle of a cut stone, and a band across its widest part
        poly(((8, 1), (8, 39), (3.5, 32), (2.6, 20), (3.5, 8)), light)
        poly(((8, 1), (12.4, 8), (8, 20)), body)
        poly(((8, 15), (11.5, 20), (8, 25), (4.5, 20)), gem)
        poly(((8, 16.5), (8, 20), (6, 20)), shine)
    elif shape == 'spine':
        poly(((8, 14), (13.5, 20), (8, 26), (2.5, 20)), edge)
        poly(((8, 16), (11, 20), (8, 24), (5, 20)), gem)
        poly(((8, 17), (8, 20), (6, 20)), shine)
        for y in (4, 36):
            poly(((8, y - 1.6), (9.6, y), (8, y + 1.6), (6.4, y)), light)
    elif shape == 'plate':
        # a rivet at each end and a jewel set in the middle
        for y in (6, 34):
            d.ellipse(((6.4) * S, (y - 1.6) * S, 9.6 * S, (y + 1.6) * S), fill=(*edge, 255))
            d.ellipse(((7) * S, (y - 1) * S, 9 * S, (y + 1) * S), fill=(*shine, 255))
        d.rectangle((4.5 * S, 14 * S, 11.5 * S, 26 * S), fill=(*edge, 255))
        d.rectangle((5.5 * S, 15 * S, 10.5 * S, 25 * S), fill=(*gem, 255))
        d.rectangle((5.5 * S, 15 * S, 7.5 * S, 20 * S), fill=(*shine, 255))
    else:
        # studs at each end, and a bead in the middle
        for y in (6, 20, 34):
            d.ellipse((4.6 * S, (y - 3) * S, 11.4 * S, (y + 3) * S), fill=(*edge, 255))
            d.ellipse((5.5 * S, (y - 2.1) * S, 10.5 * S, (y + 2.1) * S), fill=(*(gem if y == 20 else body), 255))
            d.ellipse((6 * S, (y - 1.6) * S, 8 * S, (y + .2) * S), fill=(*shine, 255))
    im = im.resize((W, H), Image.Resampling.LANCZOS)
    im.save(ROOT / 'bookends' / f'{name}.png')
    return im


def preview(textures):
    columns = 4
    rows = (len(textures) + columns - 1) // columns
    out = Image.new('RGBA', (24 + columns * 240, 60 + rows * 230), '#141923')
    d = ImageDraw.Draw(out)
    font = ImageFont.truetype('DejaVuSans.ttf', 17)
    small = ImageFont.truetype('DejaVuSans.ttf', 13)
    d.text((24, 16), 'XIFRAMES / RADIANT BARS + MATCHING BOOKENDS', font=font, fill='#dce6f3')
    for index, (name, cap) in enumerate(textures.items()):
        x, y = 24 + index % columns * 240, 84 + index // columns * 230
        d.text((x, y - 28), LABELS.get(name, name.upper().replace('_', ' ')), font=font, fill='#c1d0e0')
        for kind, w, h, color, yy in (('hp', 200, 28, (232, 94, 112), y), ('mp', 150, 24, (105, 159, 237), y + 40)):
            for layer in ('back', 'fill', 'front'):
                im = Image.open(ROOT / 'bars/radiant' / f'{kind}_{layer}.png')
                im = im.crop((0, 0, w, h)) if layer != 'fill' else im.resize((w - 14, h))
                r, g, b, a = im.split()
                rgb = [channel.point(lambda value, tint=tint: round(value * tint / 255)) for channel, tint in zip((r, g, b), color)]
                out.alpha_composite(Image.merge('RGBA', (*rgb, a)), (x + (7 if layer == 'fill' else 0), yy))
            # about as it is drawn in game at a scale of 100: 4 wide, the frame's height and a little over
            shown = cap.resize((4, h - 9), Image.Resampling.LANCZOS)
            for cx in (x + 6, x + w - 6):
                out.alpha_composite(shown, (cx - 2, yy + 4))
        # enlarged, to show the ornament; not its size in game
        out.alpha_composite(cap.resize((32, 80), Image.Resampling.NEAREST), (x + 80, y + 80))
    out.convert('RGB').save(ROOT / 'bookends/preview.png')


if __name__ == '__main__':
    (ROOT / 'bookends').mkdir(parents=True, exist_ok=True)
    preview({name: generate(name, style) for name, style in STYLES.items()})
    print(f'Generated {len(STYLES)} bookends and preview in {ROOT / "bookends"}')
