# Draws the status icons in this folder: each large, as flat shapes with a black line round them, and
# brought down to 32x32, in the manner of the icons XiView has redrawn. xiframes shows <status>.png
# from here in place of the game's own icon for that status. It needs Pillow.
#
#   python3 generate.py            writes the icons beside this file
#   python3 generate.py sheet.png  and a sheet of them all, enlarged, to look over
import os, sys
from PIL import Image, ImageDraw
out = os.path.dirname(os.path.abspath(__file__))
K = 16                      # drawn at 16 times the size
N = 32 * K
BLACK = (12, 10, 14, 255)

def lighter(c, f): return tuple(round(v + (255 - v) * f) for v in c[:3]) + (255,)
def darker(c, f): return tuple(round(v * (1 - f)) for v in c[:3]) + (255,)
def P(points): return [(x * K, y * K) for x, y in points]

def octagon(cx, cy, r, cut):
    a, b = r, r - cut
    return [(cx - b, cy - a), (cx + b, cy - a), (cx + a, cy - b), (cx + a, cy + b),
            (cx + b, cy + a), (cx - b, cy + a), (cx - a, cy + b), (cx - a, cy - b)]

def gem(d, color):
    # a cut stone: black edge, a dark rim, a face, a pale facet at the top left and a deep one opposite
    d.polygon(P(octagon(15.5, 16.5, 14.5, 8)), fill=BLACK)
    d.polygon(P(octagon(15.5, 16.5, 13.3, 7.4)), fill=darker(color, 0.45))
    d.polygon(P(octagon(15.5, 16.5, 11.2, 6.2)), fill=color)
    d.polygon(P([(6, 10), (11, 5.6), (20, 5.6), (9, 17), (4.6, 17), (4.6, 11.4)]), fill=lighter(color, 0.45))
    d.polygon(P([(7.2, 10.4), (11.4, 6.8), (15, 6.8), (6, 14.6), (6, 11.6)]), fill=lighter(color, 0.8))
    d.polygon(P([(26.4, 16), (26.4, 21.8), (20.6, 27.4), (12, 27.4), (22, 16)]), fill=darker(color, 0.25))

def arrow(d, color):
    # up and to the right, with a hooked tail, as the game's has
    def L(g):  # the hook: down from the tail and along to the right
        return [(4.6 - g, 18.2 - g), (9.4 + g, 18.2 - g), (9.4 + g, 24.4 - g), (15.4 + g, 24.4 - g), (15.4 + g, 29.0 + g), (4.6 - g, 29.0 + g)]
    def shape(g):
        return [(30.6 + g, 1.6 - g), (18.4 - g * 1.6, 3.2 - g), (22.2, 7.0), (7.4 - g, 21.8), (10.6, 25.0 + g), (25.4, 10.2), (29.2 + g, 14.0 + g * 1.6)]
    d.polygon(P(L(1.2)), fill=BLACK); d.polygon(P(shape(1.2)), fill=BLACK)
    d.polygon(P(L(0)), fill=darker(color, 0.25))
    d.polygon(P(shape(0)), fill=color)
    d.polygon(P([(29.6, 2.6), (19.6, 4.0), (21.2, 5.4), (27.8, 4.6)]), fill=lighter(color, 0.55))
    d.polygon(P([(21.0, 8.6), (9.0, 20.6), (10.0, 21.6), (22.0, 9.6)]), fill=lighter(color, 0.45))

def bolt(d, color):
    pts = lambda g: [(26.5 + g, 0.8 - g), (9.0 - g, 14.6), (16.4, 16.8), (6.0 - g, 31.2 + g), (27.4 + g, 14.2), (18.6, 12.0)]
    d.polygon(P([(26.5 + 1.4, -0.6), (7.0, 14.9), (14.4, 17.2), (3.6, 32.4), (29.6, 13.6), (20.8, 11.4)]), fill=BLACK)
    d.polygon(P(pts(0)), fill=color)
    d.polygon(P([(25.2, 2.2), (11.4, 13.8), (13.6, 14.4), (22.6, 6.4)]), fill=lighter(color, 0.5))

def finish(im):
    small = im.resize((32, 32), Image.LANCZOS)
    # hard edges, as the redrawn icons have: a pixel is there or it is not
    r, g, b, a = small.split()
    return Image.merge('RGBA', (r, g, b, a.point(lambda v: 255 if v >= 128 else 0)))

RED = (226, 30, 34, 255)
maneuvers = {300: (214, 52, 44), 301: (96, 200, 236), 302: (60, 190, 70), 303: (224, 176, 48),
             304: (150, 70, 220), 305: (40, 96, 220), 306: (236, 232, 214), 307: (70, 56, 84)}
icons = {}
for status, color in maneuvers.items():
    im = Image.new('RGBA', (N, N), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    gem(d, color + (255,))
    # on the fire stone a red arrow would be lost: it is gold there
    arrow(d, (250, 196, 50, 255) if status == 300 else RED)
    icons[status] = finish(im)
im = Image.new('RGBA', (N, N), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
gem(d, (120, 122, 130, 255)); bolt(d, RED)
icons[299] = finish(im)

for status, im in icons.items():
    im.save(f'{out}/{status}.png')
if len(sys.argv) > 1:
    ids = sorted(icons)
    sheet = Image.new('RGBA', (len(ids) * 136, 136 + 84), (48, 48, 64, 255))
    for n, i in enumerate(ids):
        b = icons[i].resize((128, 128), Image.NEAREST); sheet.paste(b, (n * 136 + 4, 4), b)
        s = icons[i].resize((26, 26), Image.BILINEAR).resize((78, 78), Image.NEAREST); sheet.paste(s, (n * 136 + 29, 136), s)
    sheet.save(sys.argv[1])
