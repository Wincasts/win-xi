#!/usr/bin/env python3
# Makes a uihook skin (uihook 1.33+, /uihook skin <name>) by recolouring the game's own interface textures, as a
# texture census wrote them (/uihook textures, logs\uihook-textures\NN\tex-<hash>.bmp). Read from the census
# folder; written only to the output folder, to be copied to <Ashita>\config\uihook\skins\<name>\.
#
#   python3 tools/uihook_skin.py CENSUS_DIR [OUT_DIR] [--scale N]
#
# OUT_DIR defaults to plugins/uihook/build/skins/test. --scale draws each picture N times larger (nearest), to see
# that a larger picture is drawn in the same place. The game's art is the user's own copy and stays out of the
# repository: build/ is ignored.
import argparse, colorsys, os, sys
from PIL import Image

# The shared chrome the first census found (47 windows), each with what is done to it in the test skin: strong
# enough to be plain at a glance
GOLD = (1.0, 0.78, 0.30)
RECIPES = {
    '72D3D795': ('tint', GOLD),          # border corners
    '3C8984C5': ('tint', GOLD),          # top and bottom edges, tiled
    '1023C0C5': ('tint', GOLD),          # side edges, tiled
    '92C145C5': ('hue', 0.34),           # the blue striped background, turned to deep red
    'C4DDAEB2': ('tint', (0.35, 1.0, 0.35)),  # the hand cursor, green
    '9E2854A3': ('hue', 0.55),           # menu buttons and highlight bars, turned to amber
}

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

def main():
    here = os.path.dirname(os.path.abspath(__file__))
    ap = argparse.ArgumentParser()
    ap.add_argument('census')
    ap.add_argument('out', nargs='?', default=os.path.join(here, '..', 'plugins', 'uihook', 'build', 'skins', 'test'))
    ap.add_argument('--scale', type=int, default=1)
    args = ap.parse_args()
    out = os.path.normpath(args.out)
    if os.path.normpath(args.census) == out: sys.exit('the output folder is the census folder')
    os.makedirs(out, exist_ok=True)
    made = 0
    for name, (kind, value) in RECIPES.items():
        source = os.path.join(args.census, f'tex-{name}.bmp')
        if not os.path.exists(source):
            print(f'{name}: not in the census, left'); continue
        im = Image.open(source).convert('RGBA')
        im = tint(im, value) if kind == 'tint' else hue(im, value)
        if args.scale > 1: im = im.resize((im.width * args.scale, im.height * args.scale), Image.NEAREST)
        im.save(os.path.join(out, f'tex-{name}.png'))
        made += 1
    print(f'{made} pictures written to {out}')

if __name__ == '__main__':
    main()
