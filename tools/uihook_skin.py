#!/usr/bin/env python3
# Makes a uihook skin (uihook 1.33+, /uihook skin <name>) for the game's own interface, from a texture census
# (/uihook textures, logs\uihook-textures\NN\tex-<hash>.bmp). Read from the census folder and the winxi theme;
# written only to the output folder, to be copied to <Ashita>\config\uihook\skins\<name>\.
#
#   python3 tools/uihook_skin.py CENSUS_DIR [OUT_DIR] [--style test|winxi] [--theme THEME_LUA] [--scale N]
#
# OUT_DIR defaults to plugins/uihook/build/skins/<style>. --scale draws each recoloured picture N times larger
# (nearest), to see that a larger picture is drawn in the same place. The game's art is the user's own copy and
# stays out of the repository: build/ is ignored.
#
# test:  strong colours, plain at a glance (gold frame, red background, green hand, amber buttons).
# winxi: the winxi theme's look, from its theme file (config\addons\winxi\theme.lua; --theme, or the Defaults of
#        libs\winxi\theme.lua) and its own images (libs\winxi\assets):
#        - the frame drawn anew at four times the game's size, its line across the Border Style's art
#          (borders\<style>.png), rounded at its corners; the game's three frame textures are exactly a 3-pixel
#          line 1 pixel in from the edge, clear about it
#        - the background the Background Style's: the theme's Background Color with lines.png over it for
#          'ffxi', a tile of backgrounds\<style>.png tinted by it for the others, flat for 'plain' and 'gradient'
#          (the game tiles it across a window, so no gradient across one)
#        - the buttons the Tab Style's (tabs\<style>.png, its middle column down a bar) on grey, and skin.txt
#          colouring them as the theme colours its tabs: the game's blue-grey bars as a tab not chosen, its
#          orange ones as the chosen tab, in the Highlight Color
#        - the hand and item boxes in the steel of the border
import argparse, colorsys, math, os, re, struct, sys
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ASSETS = os.path.join(HERE, '..', 'addons', 'libs', 'winxi', 'assets')
LIVE_THEME = os.path.expanduser('~/Games/PhoenixXI/config/addons/winxi/theme.lua')
DEFAULT_THEME = os.path.join(HERE, '..', 'addons', 'libs', 'winxi', 'theme.lua')

# The census's pictures: 32-bit, alpha kept, which PIL reads as opaque
def read_bmp(path):
    d = open(path, 'rb').read()
    offset = struct.unpack_from('<I', d, 10)[0]
    w, h = struct.unpack_from('<ii', d, 18)
    bits = struct.unpack_from('<H', d, 28)[0]
    if bits != 32: return Image.open(path).convert('RGBA')
    im = Image.frombuffer('RGBA', (w, abs(h)), d[offset:offset + w * abs(h) * 4], 'raw', 'BGRA', 0, 1 if h < 0 else -1)
    return im.copy()

# The theme's values, as theme.lua keeps them (Defaults, or the file written in game)
def read_theme(path):
    text = open(path).read()
    values = {}
    for key, body in re.findall(r'(\w+)\s*=\s*\{\s*([0-9.,\s]+)\}', text):
        values.setdefault(key, [float(v) for v in body.replace(' ', '').split(',') if v])
    for key, value in re.findall(r'(\w+)\s*=\s*["\']([^"\']*)["\']', text):
        values.setdefault(key, value)
    return values

# ---- the test skin ----
GOLD = (1.0, 0.78, 0.30)
def tint(im, colour):
    r, g, b, a = im.split()
    grey = Image.merge('RGB', (r, g, b)).convert('L')
    bands = [grey.point(lambda v, c=c: min(255, int(v * c * 1.25))) for c in colour]
    return Image.merge('RGBA', (*bands, a))

def hue(im, turn):
    px = im.load(); out = im.copy(); po = out.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
            r, g, b = colorsys.hsv_to_rgb((h + turn) % 1.0, s, v)
            po[x, y] = (int(r * 255), int(g * 255), int(b * 255), a)
    return out

def test_skin(census, theme):
    pictures = {}
    for name, how in [('72D3D795', lambda im: tint(im, GOLD)), ('3C8984C5', lambda im: tint(im, GOLD)), ('1023C0C5', lambda im: tint(im, GOLD)),
                      ('92C145C5', lambda im: hue(im, 0.34)), ('C4DDAEB2', lambda im: tint(im, (0.35, 1.0, 0.35))), ('9E2854A3', lambda im: hue(im, 0.55))]:
        im = census(name)
        if im: pictures[name] = how(im)
    return pictures, None

# ---- the winxi skin ----
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

def border_line(style):
    # the border art's line across, from its outside in, down the middle of its left edge, to where it is clear
    path = os.path.join(ASSETS, 'borders', f'{style}.png')
    if not os.path.exists(path): path = os.path.join(ASSETS, 'borders', 'ffxi.png')
    im = Image.open(path).convert('RGBA')
    line = []
    for x in range(im.width // 2):
        p = im.getpixel((x, im.height // 2))
        if p[3] < 8 and line: break
        if p[3] >= 8: line.append(p)
    return line

def steel_of(line):
    # grey to the border's colours by brightness, for the hand and item boxes: its darkest, middle and lightest
    lit = sorted(line, key=lambda p: sum(p[:3]))
    dark, mid, light = lit[0][:3], lit[len(lit) // 2][:3], lit[-1][:3]
    return [(0, (0, 0, 0)), (40, dark), (120, mid), (230, light), (255, tuple(min(255, c + 30) for c in light))]

def frame(kind, line, size=32, scale=4, radius=4.5):
    # the line from 1 to 4 in from the edge in the game's pixels, the art's line laid across it, clear about it;
    # scale times the size, each texel the average of 4x4 samples, colour weighted by its alpha; the ring's
    # corners rounded to radius
    n = size * scale
    out = Image.new('RGBA', (n, n)); po = out.load()
    def at(d):
        if d < 1 or d >= 4: return (0, 0, 0, 0)
        t = (d - 1) / 3 * len(line)
        i = min(int(t), len(line) - 1); j = min(i + 1, len(line) - 1); f = t - int(t)
        return tuple(line[i][k] * (1 - f) + line[j][k] * f for k in range(4))
    for y in range(n):
        for x in range(n):
            acc = [0.0, 0.0, 0.0, 0.0]
            for sy in range(4):
                for sx in range(4):
                    px = (x + (sx + 0.5) / 4) / scale; py = (y + (sy + 0.5) / 4) / scale
                    dx = min(px, size - px); dy = min(py, size - py)
                    if kind == 'rows': d = dy
                    elif kind == 'columns': d = dx
                    elif dx < radius and dy < radius: d = radius - math.hypot(radius - dx, radius - dy)
                    else: d = min(dx, dy)
                    c = at(d)
                    for k in range(3): acc[k] += c[k] * c[3]
                    acc[3] += c[3]
            a = acc[3] / 16
            po[x, y] = (*(int(acc[k] / acc[3]) if acc[3] else 0 for k in range(3)), int(a))
    return out

# The game draws its background darker than its texture (by its vertices, 0x414141 doubled): drawn this much
# brighter, so it is seen in the theme's colour
BACKGROUND_GAIN = 255 / (2 * 0x41)

def background(theme, size):
    colour = theme['BackgroundColor']
    style = theme.get('BackgroundStyle', 'ffxi')
    rgb = tuple(min(255, int(c * 255 * BACKGROUND_GAIN)) for c in colour[:3])
    out = Image.new('RGBA', size, (*rgb, 255))
    if style == 'ffxi':
        lines = Image.open(os.path.join(ASSETS, 'backgrounds', 'lines.png')).convert('RGBA')
        tile = Image.new('RGBA', size)
        for y in range(0, size[1], lines.height):
            for x in range(0, size[0], lines.width): tile.paste(lines, (x, y))
        out.alpha_composite(tile)
    elif os.path.exists(os.path.join(ASSETS, 'backgrounds', f'{style}.png')):
        grain = Image.open(os.path.join(ASSETS, 'backgrounds', f'{style}.png')).convert('RGBA')
        g = grain.resize(size) if grain.size != size else grain
        po = out.load(); pg = g.load()
        for y in range(size[1]):
            for x in range(size[0]):
                v = pg[x, y]
                po[x, y] = (*(min(255, int(rgb[k] * v[k] / 255)) for k in range(3)), 255)
    return out

def buttons(im, style):
    # each bar of the game's (its run of opaque rows in a column) a grey of 128, the tab art's middle column laid
    # down it (white to lighten, black to darken, as the tabs are), a darker edge where it meets the clear
    path = os.path.join(ASSETS, 'tabs', f'{style}.png')
    column = []
    if os.path.exists(path):
        tab = Image.open(path).convert('RGBA')
        column = [tab.getpixel((tab.width // 2, y)) for y in range(tab.height)]
    px = im.load(); out = Image.new('RGBA', im.size); po = out.load()
    for x in range(im.width):
        y = 0
        while y < im.height:
            if px[x, y][3] < 128: y += 1; continue
            top = y
            while y < im.height and px[x, y][3] >= 128: y += 1
            height = y - top
            for row in range(top, y):
                v = 128.0
                if column:
                    c = column[min(len(column) - 1, int((row - top + 0.5) / height * len(column)))]
                    v = v + (c[0] - v) * c[3] / 255 * 1.6
                edge = (row == top or row == y - 1 or x == 0 or x == im.width - 1
                        or px[x - 1, row][3] < 128 or px[x + 1, row][3] < 128)
                if edge: v *= 0.7
                v = max(0, min(255, int(v)))
                po[x, row] = (v, v, v, px[x, row][3])
    return out

# How the game blends a bar (its vertices' alpha, 0xA9), and how winxi blends a tab over the background: a tab
# not chosen is the Border Color at 0.18, the chosen the Highlight Color at its own alpha
GAME_BAR_ALPHA = 0xA9 / 255
def tab_colour(theme, key, strength):
    bg = theme['BackgroundColor']; over = theme[key]
    share = min(1.0, strength / GAME_BAR_ALPHA)
    return tuple(int(255 * (bg[k] + share * (over[k] - bg[k]))) for k in range(3))

def winxi_skin(census, theme):
    pictures = {}
    line = border_line(theme.get('BorderStyle', 'ffxi'))
    steel = steel_of(line)
    pictures['72D3D795'] = frame('ring', line)
    pictures['3C8984C5'] = frame('rows', line)
    pictures['1023C0C5'] = frame('columns', line)
    pictures['92C145C5'] = background(theme, (128, 128))
    for name, how in [('C4DDAEB2', lambda im: ramp(im, steel)), ('2EFCC31D', lambda im: ramp(im, steel)),
                      ('9E2854A3', lambda im: buttons(im, theme.get('TabStyle', 'glass')))]:
        im = census(name)
        if im: pictures[name] = how(im)
    plain = tab_colour(theme, 'BorderColor', 0.18)
    chosen = tab_colour(theme, 'HighlightColor', theme['HighlightColor'][3])
    txt = ('# winxi: the game\'s button bars coloured as winxi colours its tabs (made by tools/uihook_skin.py)\n'
           '# <texture> <the game\'s colour, or *> <drawn as>\n'
           f'9E2854A3 616180 {plain[0]:02X}{plain[1]:02X}{plain[2]:02X}   # the game\'s blue-grey bars: a tab not chosen\n'
           f'9E2854A3 613C20 {chosen[0]:02X}{chosen[1]:02X}{chosen[2]:02X}   # its orange ones: the chosen tab, in the Highlight Color\n')
    return pictures, txt

STYLES = {'test': test_skin, 'winxi': winxi_skin}

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('census')
    ap.add_argument('out', nargs='?')
    ap.add_argument('--style', choices=sorted(STYLES), default='test')
    ap.add_argument('--theme')
    ap.add_argument('--scale', type=int, default=1)
    args = ap.parse_args()
    out = os.path.normpath(args.out or os.path.join(HERE, '..', 'plugins', 'uihook', 'build', 'skins', args.style))
    if os.path.normpath(args.census) == out: sys.exit('the output folder is the census folder')
    theme_path = args.theme or (LIVE_THEME if os.path.exists(LIVE_THEME) else DEFAULT_THEME)
    theme = read_theme(theme_path)
    def census(name):
        path = os.path.join(args.census, f'tex-{name}.bmp')
        if not os.path.exists(path):
            print(f'{name}: not in the census, left'); return None
        im = read_bmp(path)
        return im
    pictures, txt = STYLES[args.style](census, theme)
    os.makedirs(out, exist_ok=True)
    for name, im in pictures.items():
        if args.scale > 1 and im.width <= 64: im = im.resize((im.width * args.scale, im.height * args.scale), Image.NEAREST)
        im.save(os.path.join(out, f'tex-{name}.png'))
    if txt is not None: open(os.path.join(out, 'skin.txt'), 'w', newline='\r\n').write(txt)
    print(f'{len(pictures)} pictures{" and skin.txt" if txt else ""} written to {out}, theme {theme_path}')

if __name__ == '__main__':
    main()
