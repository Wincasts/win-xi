#!/usr/bin/env python3
# Makes a uihook skin (uihook 1.33+, /uihook skin <name>) for the game's own interface, from a texture census
# (/uihook textures, in a uihook built with --diagnostics; logs\uihook-textures\NN\tex-<hash>.bmp). Read from the
# census folder and the winxi theme; written only to the output folder, to be copied to
# <Ashita>\config\uihook\skins\<name>\.
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
#          --frame-width (1 by default; 3 the game's whole line), drawn at --frame-alpha (20 hex by default, or
#          'theme' for the Border Opacity)
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
#        - every picture at several sizes (SIZES: 0.5 to 2 times the game's), tex-<hash>@<size>.png: uihook 1.49
#          draws each draw with the size whose texels are nearest its pixels, a texel to a pixel unfiltered, so
#          the menus are crisp at any Menu Scale up to 2
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

# A length r times the game's, whole
def at(v, r): return max(1, int(round(v * r)))
# A picture r times its size: smoothed larger or smaller, as it is at 1
def resized(im, r): return im if r == 1 else im.resize((at(im.width, r), at(im.height, r)), Image.LANCZOS)

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
        if im: pictures[name] = {1: how(im)}
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
    size = (at(size[0], r), at(size[1], r))
    style = theme.get('BackgroundStyle', 'ffxi')
    rgb = tuple(min(255, int(c * 255 * BACKGROUND_GAIN)) for c in colour[:3])
    out = Image.new('RGBA', size, (*rgb, 255))
    if style == 'ffxi':
        lines = Image.open(os.path.join(ASSETS, 'backgrounds', 'lines.png')).convert('RGBA')
        # a line as many whole texels as the size is times the game's (one at least: smaller, the lines as they are)
        thick = max(1, int(round(r)))
        if thick > 1: lines = lines.resize((lines.width * thick, lines.height * thick), Image.NEAREST)
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
    if r != 1:   # the bars' shape r times the size, smoothed, then laid down as at the game's
        a = im.split()[3].resize((at(im.width, r), at(im.height, r)), Image.LANCZOS)
        im = Image.merge('RGBA', (a, a, a, a))
    edge_rows = max(1, int(round(r)))
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
                if row - top < edge_rows or y - 1 - row < edge_rows: v *= 0.7
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
    n, edge, inset = at(size, scale), at(max(1, min(3, width)), scale), at(1, scale)
    ring = Image.new('RGBA', (n, n)); ring.paste(nine_slice(art, n - 2 * inset, edge), (inset, inset))
    rows = Image.new('RGBA', (n, n)); columns = Image.new('RGBA', (n, n))
    rp, cp, gp = rows.load(), columns.load(), ring.load()
    for i in range(n):
        for j in range(n):
            rp[i, j] = gp[n // 2, j] if j < inset + edge or j >= n - inset - edge else (0, 0, 0, 0)
            cp[i, j] = gp[i, n // 2] if i < inset + edge or i >= n - inset - edge else (0, 0, 0, 0)
    return ring, rows, columns

# The sizes of each picture made, times the game's: uihook (1.49) draws each draw with the one whose texels are as
# near its pixels as can be (the menu font, drawn at half its texture's size, with 0.5 at a Menu Scale of 1), so up
# to a Menu Scale of 2 there is always one to draw a texel to a pixel, crisp
SIZES = (0.5, 0.75, 1, 1.25, 1.5, 1.75, 2)

def winxi_skin(census, theme, frame_scale=1, font=None, frame_width=1, sizes=SIZES, frame_alpha='15'):
    made = {}
    glyphs = winxi_glyphs(census, theme)
    for r in sizes:
        for name, im in winxi_size(census, theme, font, frame_width, r, glyphs).items():
            made.setdefault(name, {})[r] = im
    return made, winxi_colours(theme, frame_alpha)

def winxi_glyphs(census, theme):
    lines = []
    im = census('30CDD9D4')
    if im: lines += small_layout(im) + menu_layout(im)
    im, title = census('5218C635'), font_file(theme.get('TitleFontFile') or 'trebucbi.ttf')
    if im and title: lines += title_layout(im, title)
    return lines

def winxi_size(census, theme, font, frame_width, r, glyphs):
    pictures = {}
    name = font or theme.get('FontFile') or 'trebuc.ttf'
    faces = {'menu': font_file(name), 'title': font_file(theme.get('TitleFontFile') or 'trebucbi.ttf')}
    for hsh in ('30CDD9D4', '5218C635'):
        im = census(hsh)
        if im: pictures[hsh] = draw_layout(im, glyphs, faces, hsh, r)
    style = theme.get('BorderStyle', 'ffxi')
    line = border_line(style)
    steel = steel_of(line)
    pictures['72D3D795'], pictures['3C8984C5'], pictures['1023C0C5'] = frames(border_art(style), r, width=frame_width)
    pictures['92C145C5'] = background(theme, (128, 128), r)
    for name, how in [('C4DDAEB2', lambda im: resized(ramp(im, steel), r)), ('2EFCC31D', lambda im: resized(ramp(im, steel), r)),
                      ('9E2854A3', lambda im: buttons(im, theme.get('TabStyle', 'glass'), r))]:
        im = census(name)
        if im: pictures[name] = how(im)
    return pictures

# The frame's vertices' alpha: faint by default (0x20), as a winxi window's border is over the game; 'theme' for the
# theme's Border Opacity
FRAME_ALPHA = '20'

def winxi_colours(theme, frame_alpha=FRAME_ALPHA):
    plain = tab_colour(theme, 'BorderColor', 0.18)
    chosen = tab_colour(theme, 'HighlightColor', theme['HighlightColor'][3])
    if frame_alpha == 'theme': opacity = int(round(float(theme.get('BorderOpacity', 40)) / 100 * 255))
    else: opacity = int(frame_alpha, 16)
    frame_lines = ''.join(f'{name} * {opacity:02X}808080   # {what}, even all round\n'
                          for name, what in [('72D3D795', 'the frame\'s corners'), ('3C8984C5', 'its top and bottom'), ('1023C0C5', 'its sides')])
    txt = ('# winxi (made by tools/uihook_skin.py)\n'
           '# <texture> <the game\'s colour, or *> <drawn as: RRGGBB, its alpha the game\'s, or AARRGGBB>\n'
           + frame_lines +
           f'9E2854A3 616180 {plain[0]:02X}{plain[1]:02X}{plain[2]:02X}   # the game\'s blue-grey bars: a tab not chosen\n'
           f'9E2854A3 613C20 {chosen[0]:02X}{chosen[1]:02X}{chosen[2]:02X}   # its orange ones: the chosen tab, in the Highlight Color\n')
    return txt

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

# ---- the title font ----
# 5218C635's italic font (the windows' titles on their top edges, "Commands", "Network"), in rows: each piece a
# letter, a word (the jobs' and races' names) or a sign, told apart by the gaps between them; drawn a translucent
# grey (alpha 136 at most) the game colours by its vertices
TITLE_ROWS = [
    (161, 172, list('ABCDEFGHIJKLMNOPQRSTUVWX')),
    # the small letters as the game keeps them, each its columns: told apart by eye from the texture's ink and checked
    # against the census's pieces of the windows' titles (Help, Network, Commands, Linkshell, Status); found by
    # their gaps alone, f and g (which touch) were taken for one and every letter after put one to the right
    (173, 184, list('YZabcdefghijklmnopqrstuvwxyz'), [(4, 11), (13, 21), (23, 29), (32, 38), (41, 47), (50, 56), (59, 66),
        (68, 75), (75, 82), (83, 91), (93, 98), (99, 106), (107, 115), (116, 122), (123, 134), (136, 144), (146, 154),
        (155, 163), (165, 172), (174, 181), (181, 188), (190, 196), (197, 205), (207, 215), (217, 226), (228, 236),
        (236, 245), (246, 253)]),
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

# ---- the glyph map (fonts.txt) ----
# Where each glyph of the two fonts goes, for uihook 1.52 to draw them itself from a font chosen in game (/uihook skin
# font), at each size, in place of the skin's own: in the game's texels (a size's are times its factor), a line each:
#   font <hash> kind=<menu|title> fill=<AARRGGBB> edge=<texels> edgecolour=<AARRGGBB> widen=<share>
#   clear <hash> <x0> <y0> <x1> <y1>          cleared before the glyphs are drawn
#   glyph <hash> line <a> <b> <cx0> <cx1> <top> <bottom> <baseline> <height> <ref> <text>
#       on baseline, at the size whose ref is height tall, centred on a..b and no wider than it less the edges
#       (widened to widen of that), drawn only within cx0..cx1, top..bottom
#   glyph <hash> fit <a> <b> <cx0> <cx1> <top> <bottom> 0 0 - <text>
#       its ink fitted to a..b, top..bottom: as tall, no wider
def menu_layout(im):
    lines = [f'font 30CDD9D4 kind=menu fill=FFFFFFFF edge={MENU_EDGE} edgecolour={MENU_EDGE_COLOUR[3]:02X}{MENU_EDGE_COLOUR[0]:02X}{MENU_EDGE_COLOUR[1]:02X}{MENU_EDGE_COLOUR[2]:02X} widen={MENU_FILL}']
    for top, chars in MENU_FONT_ROWS:
        boxes = glyph_boxes(im, top, chars)
        if not boxes: continue
        for i, (ch, (a, b)) in enumerate(zip(chars, boxes)):
            left = 0 if i == 0 else (boxes[i - 1][1] + a) // 2
            right = im.width if i == len(boxes) - 1 else (b + boxes[i + 1][0]) // 2
            lines.append(f'clear 30CDD9D4 {left} {top} {right} {top + 24}')
            lines.append(f'glyph 30CDD9D4 line {a} {b} {left} {right} {top} {top + 24} {top + MENU_BASELINE} {MENU_CAPS} E {ch}')
    return lines

def title_layout(im, path):
    px = im.load()
    solid = [px[x, y] for y in range(161, 172) for x in range(im.width) if px[x, y][3] >= 120]
    solid.sort(key=lambda p: sum(p[:3]))
    fill = solid[len(solid) // 2] if solid else (200, 200, 200, 136)
    lines = [f'font 5218C635 kind=title fill={fill[3]:02X}{fill[0]:02X}{fill[1]:02X}{fill[2]:02X} edge=0 edgecolour=00000000 widen=0']
    for top, bottom, pieces, *known in TITLE_ROWS:
        runs = known[0] if known else title_pieces(im, top, bottom, pieces, path)
        if not runs: continue
        lines.append(f'clear 5218C635 0 {top} {im.width} {bottom}')
        if all(len(p) == 1 for p in pieces):
            spans = []
            for a, b in runs:
                ys = [y for y in range(top, bottom) if any(px[x, y][3] >= 40 for x in range(a, b))]
                if ys: spans.append((ys[0], ys[-1] + 1))
            baseline = max(set(e for _, e in spans), key=[e for _, e in spans].count)
            tall = baseline - max(set(t for t, _ in spans), key=[t for t, _ in spans].count)
            ref = 'x' if pieces[-1].islower() else 'E'
            for text, (a, b) in zip(pieces, runs):
                lines.append(f'glyph 5218C635 line {a} {b + 1} 0 {im.width} {top} {bottom} {baseline} {tall} {ref} {text}')
            continue
        for text, (a, b) in zip(pieces, runs):
            ys = [y for y in range(top, bottom) if any(px[x, y][3] >= 40 for x in range(max(0, a - 1), min(im.width, b + 1)))]
            if not ys: continue
            lines.append(f'glyph 5218C635 fit {a} {b} 0 {im.width} {ys[0]} {ys[-1] + 1} 0 0 - {text}')
    return lines

# ---- the small font ----
# 30CDD9D4's small grey font, top left (the menus' buttons: Status, Equipment, Magic...): in rows of 13 texels, each
# glyph a near-white fill, a dark grey shadow a texel down and right, and a faint black edge about it, drawn a texel
# to a pixel; capitals 9 texels tall on a baseline 10 below the row's top. Its signs (an ellipsis, the copyright, the
# hand, the circle, triangle, square and cross of a controller) are left as the game's.
SMALL_ROWS = [(0, 12, '!"#$%&\'()*+'), (13, 25, ',-./01234567'), (26, 38, '89:;<=>?@ABCD…'), (39, 51, 'EFGHIJKLMNOP'),
              (52, 64, 'QRSTUVWXYZ['), (65, 78, '\\]^_`abcdefg'), (78, 91, 'hijklmnopqrs©'), (91, 104, 'tuvwxyz{↖}○△'),
              (104, 116, '□×0123456789'), (117, 128, '|~0123456789')]
SMALL_SIGNS = set('…©↖○△□×')

def small_layout(im):
    px = im.load()
    lines = ['font 30CDD9D4 kind=menu fill=99F6F6F6 edge=1 edgecolour=66000000 shadow=99525052 shadowx=1 shadowy=1 widen=0.85']
    for top, bottom, chars in SMALL_ROWS:
        cols = [max(px[x, y][3] for y in range(top, bottom)) for x in range(128)]
        runs, x = [], 0
        while x < 128:
            if cols[x] >= 120:
                a = x
                while x < 128 and cols[x] >= 120: x += 1
                runs.append((a, x))
            else: x += 1
        if len(runs) != len(chars): print(f'small font row {top}: its glyphs could not be told apart, left'); continue
        bottoms = []
        for a, b in runs:
            ys = [y for y in range(top, bottom) if any(px[x, y][3] >= 120 for x in range(a, b))]
            if ys: bottoms.append(ys[-1] + 1)
        baseline = max(set(bottoms), key=bottoms.count)
        for i, (ch, (a, b)) in enumerate(zip(chars, runs)):
            if ch in SMALL_SIGNS: continue
            left = 0 if i == 0 else (runs[i - 1][1] + a) // 2
            right = 128 if i == len(runs) - 1 else (b + runs[i + 1][0]) // 2
            lines.append(f'clear 30CDD9D4 {left} {top} {right} {bottom}')
            # the fill's columns and the edge each side: the room it has
            lines.append(f'glyph 30CDD9D4 line {a - 1} {b + 1} {left} {right} {top} {bottom} {baseline} 9 E {ch}')
    return lines

# ---- drawing from the glyph map ----
# As uihook draws a skin's fonts (skinfont.h), so the skin's own pictures and a font chosen in game are drawn alike:
# a font line's style for the lines after it; each glyph on its baseline at the size whose ref is its height, or its
# ink fitted to its box; edge, shadow and fill, within its bounds
def parse_layout(lines):
    styles, items = [], []
    for line in lines:
        w = line.split(' ')
        if w[0] == 'font':
            st = {'hash': w[1], 'kind': '', 'fill': 0xFFFFFFFF, 'edge': 0, 'edgecolour': 0, 'shadow': 0, 'shadowx': 0, 'shadowy': 0, 'widen': 0}
            for kv in w[2:]:
                k, v = kv.split('=')
                st[k] = v if k == 'kind' else (int(v, 16) if k in ('fill', 'edgecolour', 'shadow') else float(v))
            styles.append(st)
        elif w[0] == 'clear':
            items.append(('clear', styles[-1], w[1], [float(v) for v in w[2:6]]))
        elif w[0] == 'glyph':
            rest = line.split(' ', 12)
            items.append(('glyph', styles[-1], w[1], rest[2], [float(v) for v in rest[3:11]], rest[11], rest[12]))
    return items

def argb(c): return ((c >> 16) & 255, (c >> 8) & 255, c & 255, c >> 24)

def draw_layout(im, lines, faces, hashname, r):
    out = resized(im, r).copy()
    sizes = {}
    def size_for(path, ref, height):
        key = (path, ref, height)
        if key not in sizes:
            size = 2
            while size < 400:
                m = Image.new('L', (size * 3, size * 3)); ImageDraw.Draw(m).text((size, size * 2), ref, font=ImageFont.truetype(path, size), fill=255, anchor='ls')
                b = m.getbbox()
                if b and b[3] - b[1] >= height: break
                size += 1
            sizes[key] = size
        return sizes[key]
    for item in parse_layout(lines):
        style, hsh = item[1], item[2]
        path = faces.get(style['kind'])
        if hsh != hashname or not path: continue
        if item[0] == 'clear':
            x0, y0, x1, y1 = item[3]
            out.paste((0, 0, 0, 0), (at(x0, r), at(y0, r), at(x1, r), at(y1, r)))
            continue
        mode, (a, b, cx0, cx1, top, bottom, baseline, height), ref, text = item[3], item[4], item[5], item[6]
        if mode == 'fit':
            px = max(4, int((bottom - top) * max(1, r) * 2))
        else:
            px = size_for(path, ref if ref != '-' else 'E', max(1, at(height, r)))
        font = ImageFont.truetype(path, px)
        mask = Image.new('L', (px * (len(text) + 2), px * 3)); ImageDraw.Draw(mask).text((px, px * 2), text, font=font, fill=255, anchor='ls')
        ink = mask.getbbox()
        if not ink: continue
        glyph = mask.crop(ink)
        edge = max(1, at(style['edge'], r)) if style['edge'] > 0 else 0
        if mode == 'fit':
            bx0, by0, bx1, by1 = at(a, r), at(top, r), at(b, r), at(bottom, r)
            h = max(1, by1 - by0); w = max(1, min(bx1 - bx0, round(glyph.width * h / glyph.height)))
            glyph = glyph.resize((w, h), Image.LANCZOS)
            gx, gy = (bx0 + bx1) // 2 - w // 2, by0
        else:
            above = px * 2 - ink[1]
            room = at(b, r) - at(a, r) - 2 * edge
            want = min(room, max(glyph.width, int(room * style['widen'])))
            if want > 0 and want != glyph.width: glyph = glyph.resize((want, glyph.height), Image.LANCZOS)
            gx, gy = at((a + b) / 2, r) - glyph.width // 2, max(0, at(baseline, r) - above)
        sx, sy = (at(style['shadowx'], r), at(style['shadowy'], r)) if style['shadow'] else (0, 0)
        pad = edge + max(sx, sy) + 1
        tile = Image.new('L', (glyph.width + 2 * pad, glyph.height + 2 * pad)); tile.paste(glyph, (pad, pad))
        piece = Image.new('RGBA', tile.size, (0, 0, 0, 0))
        def lay(mask, colour):
            c = argb(colour)
            piece.alpha_composite(Image.composite(Image.new('RGBA', tile.size, c[:3] + (c[3],)), Image.new('RGBA', tile.size, (0, 0, 0, 0)), mask))
        if edge: lay(tile.filter(ImageFilter.MaxFilter(2 * edge + 1)), style['edgecolour'])
        if style['shadow']:
            shifted = Image.new('L', tile.size); shifted.paste(glyph, (pad + sx, pad + sy)); lay(shifted, style['shadow'])
        lay(tile, style['fill'])
        x0, y0 = gx - pad, gy - pad
        clip = (max(0, at(cx0, r) - x0), max(0, at(top, r) - y0), min(piece.width, at(cx1, r) - x0), min(piece.height, at(bottom, r) - y0))
        if clip[2] > clip[0] and clip[3] > clip[1]:
            out.alpha_composite(piece.crop(clip), (x0 + clip[0], y0 + clip[1]))
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
    ap.add_argument('--frame-width', type=int, default=1, choices=(1, 2, 3))
    ap.add_argument('--frame-alpha', default=FRAME_ALPHA, help='the frame\'s alpha, two hex digits, or theme')
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
    pictures, txt = winxi_skin(census, theme, args.frame_scale, args.font, args.frame_width, frame_alpha=args.frame_alpha) if args.style == 'winxi' else STYLES[args.style](census, theme)
    os.makedirs(out, exist_ok=True)
    # sizes made before, of a skin made again: gone, so none is left of an older one
    for f in os.listdir(out):
        if re.match(r'tex-[0-9A-Fa-f]{8}(@[0-9.]+)?\.png$', f): os.remove(os.path.join(out, f))
    files = 0
    for name, sizes in pictures.items():
        for r, im in sizes.items():
            if args.scale > 1 and im.width <= 64: im = im.resize((im.width * args.scale, im.height * args.scale), Image.NEAREST)
            im.save(os.path.join(out, f'tex-{name}.png' if r == 1 else f'tex-{name}@{r:g}.png'))
            files += 1
    if txt is not None: open(os.path.join(out, 'skin.txt'), 'w', newline='\r\n').write(txt)
    if args.style == 'winxi':
        glyphs = winxi_glyphs(census, theme)
        with open(os.path.join(out, 'fonts.txt'), 'w', encoding='utf-8', newline='\r\n') as f:
            f.write('# where each glyph of the skin\'s fonts goes, for uihook to draw them from a font chosen in game (made by tools/uihook_skin.py)\n')
            f.write('\n'.join(glyphs) + '\n')
    print(f'{len(pictures)} pictures ({files} files, every size){" and skin.txt" if txt else ""} written to {out}, theme {theme_path}')

if __name__ == '__main__':
    main()
