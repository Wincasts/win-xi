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
#        - the frame the Border Style's art (borders\<style>.png) as winxi.borders draws it, a nine-slice whose
#          corners and edges are the art's outer 8 of 64 texels in 3 pixels: the game's three frame textures are
#          exactly a 3-pixel line 1 pixel in from the edge, clear about it, so the slice is laid there, as wide as
#          --frame-width (2 by default; 3 the game's whole line)
#          (--frame-scale times the game's size, 1 by default: the game draws its frame a texel to a pixel, and a
#          larger one is shrunk unsmoothed). skin.txt draws every piece of it at the theme's Border
#          Opacity: the game fades its frame by its vertices' alpha (its sides near 0, its top and bottom 0x61),
#          which left the top and bottom as the game's
#        - the background the Background Style's: the theme's Background Color with lines.png over it for
#          'ffxi', a tile of backgrounds\<style>.png tinted by it for the others, flat for 'plain' and 'gradient'
#          (the game tiles it across a window, so no gradient across one)
#        - the buttons the Tab Style's (tabs\<style>.png, its middle column down a bar) on grey, and skin.txt
#          colouring them as the theme colours its tabs: the game's blue-grey bars as a tab not chosen, its
#          orange ones as the chosen tab, in the Highlight Color
#        - the hand and item boxes in the steel of the border
#        - every picture --resolution times the game's size (2 by default, the largest Menu Scale): uihook 1.48
#          makes it smaller for each smaller size and draws it smoothed, so it is crisp at any scale up to that
#        - the title font (5218C635: the windows' titles, the jobs' and races' names) in the theme's Title Font,
#          each letter or word fitted to the game's piece's ink
#        - the menu font (30CDD9D4's large font: the menus' labels and lists) in the theme's Font, each glyph drawn
#          where the game's was (the game places and spaces them as ever), on its baseline at its height, white with
#          the game's dark edge; --font names another (a file of the game's C:\Windows\Fonts, or a path)
import argparse, colorsys, math, os, re, struct, sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ASSETS = os.path.join(HERE, '..', 'addons', 'libs', 'winxi', 'assets')
LIVE_THEME = os.path.expanduser('~/Games/PhoenixXI/config/addons/winxi/theme.lua')
DEFAULT_THEME = os.path.join(HERE, '..', 'addons', 'libs', 'winxi', 'theme.lua')
GAME_FONTS = os.path.expanduser('~/.local/share/com.phoenixxi.launcher/prefix/0/drive_c/windows/Fonts')

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
    for key, value in re.findall(r'(\w+)\s*=\s*(-?[0-9.]+)\s*,', text):
        values.setdefault(key, float(value))
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

# How much brighter than the theme's Background Color the texture is: the game darkens it by its vertices (0x414141
# doubled) but draws it more solid than winxi does; measured in game against a winxi window over the same ground
# (1.96, the vertices' darkening alone, came out 1.65 times too bright)
BACKGROUND_GAIN = 1.2

def background(theme, size, r=1):
    colour = theme['BackgroundColor']
    size = (size[0] * r, size[1] * r)
    style = theme.get('BackgroundStyle', 'ffxi')
    rgb = tuple(min(255, int(c * 255 * BACKGROUND_GAIN)) for c in colour[:3])
    out = Image.new('RGBA', size, (*rgb, 255))
    if style == 'ffxi':
        lines = Image.open(os.path.join(ASSETS, 'backgrounds', 'lines.png')).convert('RGBA')
        if r > 1: lines = lines.resize((lines.width * r, lines.height * r), Image.NEAREST)   # a line r texels, a pixel drawn
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

def buttons(im, style, r=1):
    # each bar of the game's (its run of opaque rows in a column) a grey of 128, the tab art's middle column laid
    # down it (white to lighten, black to darken, as the tabs are), its top and bottom rows darker. Not its ends:
    # the game makes a button of the ends of two bars, and a darker end showed as a line where they meet.
    path = os.path.join(ASSETS, 'tabs', f'{style}.png')
    column = []
    if os.path.exists(path):
        tab = Image.open(path).convert('RGBA')
        column = [tab.getpixel((tab.width // 2, y)) for y in range(tab.height)]
    if r > 1:   # the bars' shape r times the size, smoothed, then laid down as at the game's
        a = im.split()[3].resize((im.width * r, im.height * r), Image.LANCZOS)
        im = Image.merge('RGBA', (a, a, a, a))
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
                if row - top < r or y - 1 - row < r: v *= 0.7
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

def border_art(style):
    path = os.path.join(ASSETS, 'borders', f'{style}.png')
    if not os.path.exists(path): path = os.path.join(ASSETS, 'borders', 'ffxi.png')
    return Image.open(path).convert('RGBA')

def nine_slice(art, size, edge):
    # as winxi.borders' ArtEdge: the art's outer 8/64 at each side in edge pixels, its middle stretched; no centre
    cut = art.width * 8 // 64
    xs_art = [0, cut, art.width - cut, art.width]; xs = [0, edge, size - edge, size]
    out = Image.new('RGBA', (size, size))
    for row in range(3):
        for col in range(3):
            if row == 1 and col == 1: continue
            piece = art.crop((xs_art[col], xs_art[row], xs_art[col + 1], xs_art[row + 1]))
            w, h = xs[col + 1] - xs[col], xs[row + 1] - xs[row]
            if w > 0 and h > 0: out.paste(piece.resize((w, h), Image.BILINEAR), (xs[col], xs[row]))
    return out

def frames(art, scale=1, size=32, width=3):
    # the ring a nine-slice from 1 to size-1, its line width pixels (the game's is 3: thinner, the outer part of it,
    # clear inside); the edges' textures its top and bottom rows (tiled across) or its sides (tiled down), taken from
    # its middle
    n, edge, inset = size * scale, max(1, min(3, width)) * scale, scale
    ring = Image.new('RGBA', (n, n)); ring.paste(nine_slice(art, n - 2 * inset, edge), (inset, inset))
    rows = Image.new('RGBA', (n, n)); columns = Image.new('RGBA', (n, n))
    rp, cp, gp = rows.load(), columns.load(), ring.load()
    for i in range(n):
        for j in range(n):
            rp[i, j] = gp[n // 2, j] if j < inset + edge or j >= n - inset - edge else (0, 0, 0, 0)
            cp[i, j] = gp[i, n // 2] if i < inset + edge or i >= n - inset - edge else (0, 0, 0, 0)
    return ring, rows, columns

def winxi_skin(census, theme, frame_scale=1, font=None, frame_width=2, r=2):
    pictures = {}
    name = font or theme.get('FontFile') or 'trebuc.ttf'
    path = font_file(name)
    im = census('30CDD9D4')
    if im and path: pictures['30CDD9D4'] = menu_font(im, path, r)
    elif im: print(f'font {name} not found; the menu font left')
    title = font_file(theme.get('TitleFontFile') or 'trebucbi.ttf')
    im = census('5218C635')
    if im and title: pictures['5218C635'] = title_font(im, title, r)
    elif im: print('title font not found; the title font left')
    style = theme.get('BorderStyle', 'ffxi')
    line = border_line(style)
    steel = steel_of(line)
    pictures['72D3D795'], pictures['3C8984C5'], pictures['1023C0C5'] = frames(border_art(style), max(frame_scale, r), width=frame_width)
    pictures['92C145C5'] = background(theme, (128, 128), r)
    larger = lambda im: im.resize((im.width * r, im.height * r), Image.LANCZOS) if r > 1 else im
    for name, how in [('C4DDAEB2', lambda im: larger(ramp(im, steel))), ('2EFCC31D', lambda im: larger(ramp(im, steel))),
                      ('9E2854A3', lambda im: buttons(im, theme.get('TabStyle', 'glass'), r))]:
        im = census(name)
        if im: pictures[name] = how(im)
    plain = tab_colour(theme, 'BorderColor', 0.18)
    chosen = tab_colour(theme, 'HighlightColor', theme['HighlightColor'][3])
    opacity = int(round(float(theme.get('BorderOpacity', 40)) / 100 * 255))
    frame_lines = ''.join(f'{name} * {opacity:02X}808080   # {what}, even all round at the Border Opacity\n'
                          for name, what in [('72D3D795', 'the frame\'s corners'), ('3C8984C5', 'its top and bottom'), ('1023C0C5', 'its sides')])
    txt = ('# winxi (made by tools/uihook_skin.py)\n'
           '# <texture> <the game\'s colour, or *> <drawn as: RRGGBB, its alpha the game\'s, or AARRGGBB>\n'
           + frame_lines +
           f'9E2854A3 616180 {plain[0]:02X}{plain[1]:02X}{plain[2]:02X}   # the game\'s blue-grey bars: a tab not chosen\n'
           f'9E2854A3 613C20 {chosen[0]:02X}{chosen[1]:02X}{chosen[2]:02X}   # its orange ones: the chosen tab, in the Highlight Color\n')
    return pictures, txt

# ---- the menu font ----
# 30CDD9D4's large font, in rows of 24 texels from 131 (as the census's glyphs and the texture's own ink show):
# each glyph white with a dark edge 2 texels wide, drawn half size; its baseline 19 texels down its row, capitals
# 17 tall
MENU_FONT_ROWS = [(131, '/0123456789AB'), (155, 'CDEFGHIJKLMN'), (179, 'OPQRSTUVWXY'), (203, 'Zabcdefghijklm'), (227, 'nopqrstuvwxyz')]
MENU_BASELINE, MENU_CAPS, MENU_EDGE = 19, 17, 2
MENU_EDGE_COLOUR = (8, 16, 8, 150)
MENU_FILL = 0.85   # each glyph widened to at least this share of the game's glyph's width: the game spaces them as its own

def glyph_boxes(im, top, chars):
    # each glyph's columns in its row: runs of ink, the threshold raised until there are as many as the characters
    px = im.load()
    for threshold in (40, 80, 120, 160, 200):
        cols = [max(px[x, y][3] for y in range(top, top + 24)) for x in range(im.width)]
        runs, x = [], 0
        while x < im.width:
            if cols[x] >= threshold:
                a = x
                while x < im.width and cols[x] >= threshold: x += 1
                runs.append((a, x))
            else: x += 1
        if len(runs) == len(chars):
            # told apart only above their edges' strength: the edges given back
            grow = 0 if threshold == 40 else MENU_EDGE
            return [(max(0, a - grow), min(im.width, b + grow)) for a, b in runs]
    return None

def font_file(name):
    if os.path.isabs(name) and os.path.exists(name): return name
    for folder in (GAME_FONTS, '/usr/share/fonts'):
        for root, _, files in os.walk(folder):
            for f in files:
                if f.lower() == name.lower(): return os.path.join(root, f)
    return None

def menu_font(im, path, r=1):
    # the game's large font cleared and drawn again in the font at path, each glyph in the place of the game's; the
    # whole r times the game's size (the rest of the texture, the small font and the damage digits, enlarged as it is)
    out = im.resize((im.width * r, im.height * r), Image.LANCZOS) if r > 1 else im.copy()
    po = out.load()
    size = 10
    while size < 80 * r:   # the size whose capitals are as tall as the game's
        b = ImageFont.truetype(path, size).getbbox('E', anchor='ls')
        if b[3] - b[1] >= MENU_CAPS * r: break
        size += 1
    font = ImageFont.truetype(path, size)
    edge, row = MENU_EDGE * r, 24 * r
    for top0, chars in MENU_FONT_ROWS:
        boxes = glyph_boxes(im, top0, chars)
        if not boxes:
            print(f'menu font row {top0}: its glyphs could not be told apart, left'); continue
        top = top0 * r
        boxes = [(a * r, b * r) for a, b in boxes]
        for i, (ch, (a, b)) in enumerate(zip(chars, boxes)):
            # the room it has: to halfway to its neighbours, inside the row
            left = 0 if i == 0 else (boxes[i - 1][1] + a) // 2
            right = out.width if i == len(boxes) - 1 else (b + boxes[i + 1][0]) // 2
            for y in range(top, top + row):
                for x in range(left, right): po[x, y] = (0, 0, 0, 0)
            # the glyph drawn large enough for its edge, cut to its ink, squeezed to the game's ink width if wider
            mask = Image.new('L', (96 * r, 64 * r)); ImageDraw.Draw(mask).text((24 * r, 44 * r), ch, font=font, fill=255, anchor='ls')
            ink = mask.getbbox()
            if not ink: continue
            glyph = mask.crop(ink); baseline = 44 * r - ink[1]
            room = (b - a) - 2 * edge
            want = min(room, max(glyph.width, int(room * MENU_FILL)))
            if want > 0 and want != glyph.width: glyph = glyph.resize((want, glyph.height), Image.LANCZOS)
            gx = (a + b) // 2 - glyph.width // 2; gy = top + MENU_BASELINE * r - baseline
            pad = edge + 1
            tile = Image.new('L', (glyph.width + 2 * pad, glyph.height + 2 * pad)); tile.paste(glyph, (pad, pad))
            ring = tile.filter(ImageFilter.MaxFilter(2 * edge + 1))
            piece = Image.new('RGBA', tile.size, (0, 0, 0, 0))
            piece.paste(Image.new('RGBA', tile.size, MENU_EDGE_COLOUR[:3] + (255,)), (0, 0), ring.point(lambda v: v * MENU_EDGE_COLOUR[3] // 255))
            piece.paste(Image.new('RGBA', tile.size, (255, 255, 255, 255)), (0, 0), tile)
            # kept within its room, so no neighbour is drawn over
            px0, py0 = gx - pad, gy - pad
            crop = (max(0, left - px0), max(0, top - py0), min(piece.width, right - px0), min(piece.height, top + row - py0))
            if crop[2] > crop[0] and crop[3] > crop[1]:
                out.alpha_composite(piece.crop(crop), (px0 + crop[0], py0 + crop[1]))
    return out

# ---- the title font ----
# 5218C635's italic font (the windows' titles on their top edges, "Commands", "Network"), in rows: each piece a
# letter, a word (the jobs' and races' names) or a sign, told apart by the gaps between them; drawn a translucent
# grey (alpha 136 at most) the game colours by its vertices
TITLE_ROWS = [
    (161, 172, list('ABCDEFGHIJKLMNOPQRSTUVWX')),
    (173, 184, list('YZabcdefghijklmnopqrstuvwxyz')),
    (184, 193, ['WAR', 'MNK', 'WHM', 'BLM', 'RDM', 'THF', 'PLD', 'DRK', 'BST', 'BRD']),
    (193, 203, ['RNG', 'SAM', 'NIN', 'DRG', 'SMN', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9']),
    (203, 213, ['Hum', 'Elv', 'Tar', 'Gal', 'Mit', '/', 'San', 'Bas', 'Win', '[', ']']),
    (213, 223, ['BLU', 'COR', 'PUP', 'DNC', 'SCH', 'ä', 'ö', 'ü', 'ß', 'GEO', 'RUN']),
]

def title_pieces(im, top, bottom, pieces, font_path):
    # each piece's columns across the row, at its middle height. The ink is looked at slanted, as the letters are
    # (italic letters side by side share columns straight down), split finely (at a strength that parts letters
    # touching at their faint edges), then grouped in order, a group for each piece, as near as can be to each
    # piece's width as the font draws it (scaled to the row's): the pieces of a row are of all widths (letters,
    # words, a slash). The slant whose grouping fits best is kept.
    # a row of letters alone: the game's letters are near as wide as each other (a slab serif), so each the same;
    # a row of words: as the font draws them
    font = ImageFont.truetype(font_path, 40)
    letters = all(len(p) == 1 for p in pieces)
    widths = [1 if letters else max(1, font.getbbox(p)[2] - font.getbbox(p)[0]) for p in pieces]
    band = im.crop((0, top, im.width, bottom))
    middle = (bottom - top) / 2
    n = len(pieces)
    found, least = None, float('inf')
    for slant in (0, 0.1, 0.15, 0.2, 0.25, 0.3):
        sheared = band.transform(band.size, Image.AFFINE, (1, slant, -slant * middle, 0, 1, 0), resample=Image.BILINEAR)
        px = sheared.load()
        cols = [max(px[x, y][3] for y in range(sheared.height)) for x in range(sheared.width)]
        for threshold in (120, 100, 80, 60, 40):
            runs, x = [], 0
            while x < len(cols):
                if cols[x] >= threshold:
                    a = x
                    while x < len(cols) and cols[x] >= threshold: x += 1
                    runs.append((a, x))
                else: x += 1
            if len(runs) >= n: break
        # letters touching at every strength (f and g): a run much wider than a letter split at its faintest column
        if letters and runs:
            usual = sorted(b - a for a, b in runs)[len(runs) // 2]
            parted = []
            for a, b in runs:
                while b - a > 1.6 * usual:
                    inner = range(a + usual // 2, b - usual // 2)
                    cut = min(inner, key=lambda x: cols[x]) if len(inner) else (a + b) // 2
                    parted.append((a, cut)); a = cut + 1
                parted.append((a, b))
            runs = parted
        m = len(runs)
        if m < n: continue
        span = runs[-1][1] - runs[0][0]
        gaps = sum(runs[k + 1][0] - runs[k][1] for k in range(m - 1))
        scale = (span - gaps * n / m) / sum(widths)
        INF = float('inf')
        cost = [[INF] * (m + 1) for _ in range(n + 1)]; back = [[0] * (m + 1) for _ in range(n + 1)]
        cost[0][0] = 0
        for i in range(1, n + 1):
            for k in range(i, m - (n - i) + 1):
                for j in range(i - 1, k):
                    if cost[i - 1][j] == INF: continue
                    w = runs[k - 1][1] - runs[j][0]
                    c = cost[i - 1][j] + (w - widths[i - 1] * scale) ** 2
                    if c < cost[i][k]: cost[i][k], back[i][k] = c, j
        if cost[n][m] < least:
            out, k = [], m
            for i in range(n, 0, -1):
                j = back[i][k]; out.append((runs[j][0], runs[k - 1][1])); k = j
            found, least = out[::-1], cost[n][m]
    return found

def title_font(im, path, r=1):
    out = im.resize((im.width * r, im.height * r), Image.LANCZOS) if r > 1 else im.copy()
    px = im.load()
    solid = [px[x, y] for y in range(161, 172) for x in range(im.width) if px[x, y][3] >= 120]
    solid.sort(key=lambda p: sum(p[:3]))
    fill = solid[len(solid) // 2] if solid else (200, 200, 200, 136)
    for top, bottom, pieces in TITLE_ROWS:
        runs = title_pieces(im, top, bottom, pieces, path)
        if not runs:
            print(f'title font row {top}: its pieces could not be told apart, left'); continue
        # the row cleared whole, the faint edges between its pieces too
        out.paste((0, 0, 0, 0), (0, top * r, out.width, bottom * r))
        if all(len(p) == 1 for p in pieces):
            # letters: on the row's baseline (the bottom most of its letters share), the size whose capitals (or
            # x-height, a row of small letters) are as tall as most of the game's
            spans = []
            for a, b in runs:
                ys = [y for y in range(top, bottom) if any(px[x, y][3] >= 40 for x in range(a, b))]
                if ys: spans.append((ys[0], ys[-1] + 1))
            baseline = max(set(e for _, e in spans), key=[e for _, e in spans].count)
            tall = baseline - max(set(t for t, _ in spans), key=[t for t, _ in spans].count)
            sample = 'x' if pieces[-1].islower() else 'E'
            size = 4
            while size < 200:
                g = ImageFont.truetype(path, size).getbbox(sample, anchor='ls')
                if g[3] - g[1] >= tall * r: break
                size += 1
            font = ImageFont.truetype(path, size)
            for text, (a, b) in zip(pieces, runs):
                mask = Image.new('L', (size * 3, size * 3)); ImageDraw.Draw(mask).text((size, size * 2), text, font=font, fill=255, anchor='ls')
                ink = mask.getbbox()
                if not ink: continue
                glyph = mask.crop(ink); above = size * 2 - ink[1]
                room = (b - a) * r + r
                if glyph.width > room: glyph = glyph.resize((room, glyph.height), Image.LANCZOS)
                piece = Image.new('RGBA', glyph.size, fill[:3] + (255,))
                piece.putalpha(glyph.point(lambda v: v * fill[3] // 255))
                out.alpha_composite(piece, ((a + b) * r // 2 - glyph.width // 2, max(0, baseline * r - above)))
            continue
        for text, (a, b) in zip(pieces, runs):
            # the game's piece's ink: where the new one goes, as tall and no wider
            ys = [y for y in range(top, bottom) if any(px[x, y][3] >= 40 for x in range(max(0, a - 1), min(im.width, b + 1)))]
            if not ys: continue
            y0, y1 = ys[0], ys[-1] + 1
            box = (a * r, y0 * r, b * r, y1 * r)
            font = ImageFont.truetype(path, (y1 - y0) * r * 2)
            mask = Image.new('L', (font.size * (len(text) + 2), font.size * 3))
            ImageDraw.Draw(mask).text((font.size, font.size), text, font=font, fill=255)
            ink = mask.getbbox()
            if not ink: continue
            glyph = mask.crop(ink)
            h = box[3] - box[1]
            w = max(1, min(box[2] - box[0], round(glyph.width * h / glyph.height)))
            glyph = glyph.resize((w, h), Image.LANCZOS)
            piece = Image.new('RGBA', glyph.size, fill[:3] + (255,))
            piece.putalpha(glyph.point(lambda v: v * fill[3] // 255))
            out.alpha_composite(piece, ((box[0] + box[2]) // 2 - w // 2, box[1]))
    return out

STYLES = {'test': test_skin, 'winxi': winxi_skin}

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('census')
    ap.add_argument('out', nargs='?')
    ap.add_argument('--style', choices=sorted(STYLES), default='test')
    ap.add_argument('--theme')
    ap.add_argument('--scale', type=int, default=1)
    ap.add_argument('--frame-scale', type=int, default=1)
    ap.add_argument('--font')
    ap.add_argument('--frame-width', type=int, default=2, choices=(1, 2, 3))
    ap.add_argument('--resolution', type=int, default=2, choices=(1, 2, 3, 4))
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
    pictures, txt = winxi_skin(census, theme, args.frame_scale, args.font, args.frame_width, args.resolution) if args.style == 'winxi' else STYLES[args.style](census, theme)
    os.makedirs(out, exist_ok=True)
    for name, im in pictures.items():
        if args.scale > 1 and im.width <= 64: im = im.resize((im.width * args.scale, im.height * args.scale), Image.NEAREST)
        im.save(os.path.join(out, f'tex-{name}.png'))
    if txt is not None: open(os.path.join(out, 'skin.txt'), 'w', newline='\r\n').write(txt)
    print(f'{len(pictures)} pictures{" and skin.txt" if txt else ""} written to {out}, theme {theme_path}')

if __name__ == '__main__':
    main()
