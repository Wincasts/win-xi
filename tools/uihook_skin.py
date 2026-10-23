#!/usr/bin/env python3
# Makes a uihook skin (uihook 1.33+, /uihook skin <name>) by recolouring the game's own interface textures, as a
# texture census wrote them (/uihook textures, logs\uihook-textures\NN\tex-<hash>.bmp). Read from the census
# folder; written only to the output folder, to be copied to <Ashita>\config\uihook\skins\<name>\.
#
#   python3 tools/uihook_skin.py CENSUS_DIR [OUT_DIR] [--style test|winxi] [--scale N]
#
# OUT_DIR defaults to plugins/uihook/build/skins/<style>. --scale draws each recoloured picture N times larger
# (nearest), to see that a larger picture is drawn in the same place. The game's art is the user's own copy and
# stays out of the repository: build/ is ignored.
#
# test:  strong colours, plain at a glance (gold frame, red background, green hand, amber buttons).
# winxi: the winxi theme's look (libs\winxi\theme.lua, borders\ffxi.png): the frame drawn anew at four times the
#        game's size, rounded at its corners, in the steel of the FFXI-inspired border; the background the theme's
#        navy in the game's stripes; the hand and item boxes steel, the buttons and highlight bars the theme's blue.
import argparse, colorsys, math, os, sys
from PIL import Image

# The shared chrome the first census found (47 windows), and what each style does to each
GOLD = (1.0, 0.78, 0.30)
TEST = {
    '72D3D795': ('tint', GOLD),          # border corners
    '3C8984C5': ('tint', GOLD),          # top and bottom edges, tiled
    '1023C0C5': ('tint', GOLD),          # side edges, tiled
    '92C145C5': ('hue', 0.34),           # the blue striped background, turned to deep red
    'C4DDAEB2': ('tint', (0.35, 1.0, 0.35)),  # the hand cursor, green
    '9E2854A3': ('hue', 0.55),           # menu buttons and highlight bars, turned to amber
}

# The frame's line across, from its outside in, as borders\ffxi.png has it (dark edge, highlight, steel, a
# second fine highlight, dark inner edge), laid over the game's 3 pixels from 1 to 4 in from the edge
STEEL_LINE = [(14, 19, 35), (76, 84, 109), (208, 213, 229), (153, 162, 192), (94, 105, 141), (168, 177, 203), (56, 67, 106), (20, 28, 60)]
# Grey to a colour, by brightness
STEEL = [(0, (0, 0, 0)), (40, (9, 19, 48)), (100, (94, 105, 141)), (170, (168, 177, 203)), (230, (208, 213, 229)), (255, (240, 244, 255))]
HIGHLIGHT = [(0, (0, 0, 0)), (40, (15, 25, 70)), (100, (50, 80, 165)), (160, (90, 130, 220)), (220, (180, 200, 245)), (255, (235, 242, 255))]
SLOT = [(0, (0, 0, 0)), (60, (22, 24, 42)), (140, (76, 80, 108)), (200, (128, 132, 160)), (255, (200, 204, 228))]
WINXI = {
    '72D3D795': ('frame', 'ring'),       # border corners: a ring, drawn anew, rounded
    '3C8984C5': ('frame', 'rows'),       # top and bottom edges, tiled across
    '1023C0C5': ('frame', 'columns'),    # side edges, tiled down
    '92C145C5': ('stripes', ((50, 50, 86), (38, 38, 66))),  # the theme's navy (0.153, 0.153, 0.263), a darker row pair between
    'C4DDAEB2': ('ramp', STEEL),         # the hand cursor
    '9E2854A3': ('ramp', HIGHLIGHT),     # menu buttons and highlight bars: the theme's Highlight Color
    '2EFCC31D': ('ramp', SLOT),          # the item slot box
}
STYLES = {'test': TEST, 'winxi': WINXI}

def tint(im, colour):
    r, g, b, a = im.split()
    grey = Image.merge('RGB', (r, g, b)).convert('L')
    bands = [grey.point(lambda v, c=c: min(255, int(v * c * 1.25))) for c in colour]
    return Image.merge('RGBA', (*bands, a))

def hue(im, turn):
    px = im.load()
    out = im.copy(); po = out.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
            r, g, b = colorsys.hsv_to_rgb((h + turn) % 1.0, s, v)
            po[x, y] = (int(r * 255), int(g * 255), int(b * 255), a)
    return out

def ramp(im, stops):
    r, g, b, a = im.split()
    grey = Image.merge('RGB', (r, g, b)).convert('L')
    table = []
    for v in range(256):
        for (v0, c0), (v1, c1) in zip(stops, stops[1:]):
            if v0 <= v <= v1:
                t = (v - v0) / (v1 - v0) if v1 > v0 else 0
                table.append(tuple(int(c0[i] + (c1[i] - c0[i]) * t) for i in range(3))); break
    px = grey.load(); out = Image.new('RGBA', im.size); po = out.load(); pa = a.load()
    for y in range(im.height):
        for x in range(im.width):
            po[x, y] = (*table[px[x, y]], pa[x, y])
    return out

def line_colour(d):
    # d: distance in from the edge in the game's pixels; the line is from 1 to 4, black (drawn as nothing) about it
    if d < 1 or d >= 4: return (0, 0, 0)
    t = (d - 1) / 3 * len(STEEL_LINE)
    i = min(int(t), len(STEEL_LINE) - 1)
    j = min(i + 1, len(STEEL_LINE) - 1); f = t - int(t)
    return tuple(int(STEEL_LINE[i][k] * (1 - f) + STEEL_LINE[j][k] * f) for k in range(3))

def frame(kind, size=32, scale=4, radius=4.5):
    # the game's frame pieces are a line 1 to 4 pixels in from the edge (all three textures, exactly): drawn anew at
    # scale times the size, each texel the average of 4x4 samples, the ring's corners rounded to radius
    n = size * scale
    out = Image.new('RGBA', (n, n)); po = out.load()
    for y in range(n):
        for x in range(n):
            acc = [0, 0, 0]
            for sy in range(4):
                for sx in range(4):
                    px = (x + (sx + 0.5) / 4) / scale; py = (y + (sy + 0.5) / 4) / scale
                    dx = min(px, size - px); dy = min(py, size - py)
                    if kind == 'rows': d = dy
                    elif kind == 'columns': d = dx
                    elif dx < radius and dy < radius: d = radius - math.hypot(radius - dx, radius - dy)
                    else: d = min(dx, dy)
                    c = line_colour(d)
                    for k in range(3): acc[k] += c[k]
            po[x, y] = (*(v // 16 for v in acc), 255)
    return out

def stripes(im, colours):
    # the game's stripes kept where they are (rows as light or dark as the game's), in colours of the theme's
    grey = im.convert('L'); px = grey.load()
    rows = [px[0, y] for y in range(im.height)]
    middle = (max(rows) + min(rows)) / 2
    out = Image.new('RGBA', im.size); po = out.load()
    for y in range(im.height):
        c = colours[0] if rows[y] >= middle else colours[1]
        for x in range(im.width): po[x, y] = (*c, 255)
    return out

def main():
    here = os.path.dirname(os.path.abspath(__file__))
    ap = argparse.ArgumentParser()
    ap.add_argument('census')
    ap.add_argument('out', nargs='?')
    ap.add_argument('--style', choices=sorted(STYLES), default='test')
    ap.add_argument('--scale', type=int, default=1)
    args = ap.parse_args()
    out = os.path.normpath(args.out or os.path.join(here, '..', 'plugins', 'uihook', 'build', 'skins', args.style))
    if os.path.normpath(args.census) == out: sys.exit('the output folder is the census folder')
    os.makedirs(out, exist_ok=True)
    made = 0
    for name, (kind, value) in STYLES[args.style].items():
        if kind == 'frame':
            im = frame(value)
        else:
            source = os.path.join(args.census, f'tex-{name}.bmp')
            if not os.path.exists(source):
                print(f'{name}: not in the census, left'); continue
            im = Image.open(source).convert('RGBA')
            im = {'tint': tint, 'hue': hue, 'ramp': ramp, 'stripes': stripes}[kind](im, value)
            if args.scale > 1: im = im.resize((im.width * args.scale, im.height * args.scale), Image.NEAREST)
        im.save(os.path.join(out, f'tex-{name}.png'))
        made += 1
    print(f'{made} pictures written to {out}')

if __name__ == '__main__':
    main()
