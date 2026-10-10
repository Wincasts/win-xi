# Redraws the game's own status icons, which are soft little paintings, as firmer ones: the same
# shapes in flatter, stronger colours, with hard edges and a dark line round each. xiframes shows
# <status>.png from this folder in place of the game's icon for that status.
#
#   python3 redraw.py <the game's status icon file> [sheet.png]
#
# The file is ROM/119/57.DAT, the game's or an icon set's (XiView's, under polplugins/DATs). Only
# icons that are the game's own art are redrawn: the game counts an alpha of 128 as solid, so none of
# its icons has much more, where one an icon set has drawn again is solid at 255 and is sharp already.
# An icon drawn by generate.py (Dia) is left alone. With a second name, a sheet of them all is written
# too, each as it was above what it is now. It needs Pillow and numpy.
#
# What is done to an icon, in Redraw below: it is drawn four times the size, sharpened and smoothed
# there so that each patch of colour becomes one colour with a clean edge, cut to sixteen colours and
# brought back down; that is laid over the icon simply sharpened, which keeps the small detail the
# flattening loses; the colours are strengthened; and its outermost pixels are darkened to a line.
import os, struct, sys
import numpy as np
from PIL import Image, ImageEnhance, ImageFilter

here = os.path.dirname(os.path.abspath(__file__))
SIDE = 32
RECORD = 0x1800            # each status has this much of the file
HEADER = struct.pack('<IiiHH', 40, SIDE, SIDE, 1, 32)  # how an icon's bitmap begins
GAMES_SOLID = 136          # the most alpha one of the game's icons has, with a little to spare
FAINTEST = 48 / 128        # of an icon's most alpha: fainter than this is not part of the icon
DRAWN_BY_HAND = { 134 }    # generate.py's

def Icons(path):
    data = open(path, 'rb').read()
    at = data.find(HEADER)
    while at != -1:
        pixels = data[at + 40:at + 40 + SIDE * SIDE * 4]
        if len(pixels) == SIDE * SIDE * 4:
            yield at // RECORD, Image.frombuffer('RGBA', (SIDE, SIDE), pixels, 'raw', 'BGRA', 0, -1)
        at = data.find(HEADER, at + 1)

def FillOutside(rgb, mask):
    # outside the icon is given the colours of its edge, so that nothing dark bleeds in when it is smoothed
    pixels = np.array(rgb).astype(float); known = mask.copy()
    for _ in range(6):
        if known.all():
            break
        total = np.zeros_like(pixels); count = np.zeros(known.shape)
        for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
            beside = np.roll(known, (dy, dx), (0, 1))
            total += np.roll(pixels, (dy, dx), (0, 1)) * beside[..., None]; count += beside
        new = (~known) & (count > 0)
        pixels[new] = total[new] / count[new][..., None]; known = known | new
    return Image.fromarray(pixels.round().clip(0, 255).astype('uint8'))

def Flat(rgb, colours=16, scale=4):
    big = rgb.resize((SIDE * scale, SIDE * scale), Image.BICUBIC)
    big = big.filter(ImageFilter.UnsharpMask(radius=scale, percent=180, threshold=0)).filter(ImageFilter.MedianFilter(5))
    cut = big.quantize(colours, method=Image.Quantize.MEDIANCUT, kmeans=4, dither=Image.Dither.NONE)
    small = cut.convert('RGB').resize((SIDE, SIDE), Image.BOX)
    # each pixel is one of the colours again, not a mix of two at an edge
    return small.quantize(palette=cut, dither=Image.Dither.NONE).convert('RGB')

def Outline(rgb, mask, keeps=0.1):
    # the icon's own outermost pixels, darkened: only where the inside is beside them, so that a part
    # too thin to have an inside is not all line
    pixels = np.array(rgb).astype(float); padded = np.pad(mask, 1)
    edge = mask & ~(padded[1:-1, :-2] & padded[1:-1, 2:] & padded[:-2, 1:-1] & padded[2:, 1:-1])
    inside = np.pad(mask & ~edge, 1)
    near = np.zeros_like(mask)
    for dy in range(3):
        for dx in range(3):
            near |= inside[dy:dy + SIDE, dx:dx + SIDE]
    pixels[edge & near] *= keeps
    pixels[~mask] = 0
    return Image.fromarray(np.dstack([pixels.round().clip(0, 255).astype('uint8'), (mask * 255).astype('uint8')]), 'RGBA')

def Redraw(icon):
    alpha = np.array(icon.getchannel('A'))
    mask = alpha >= round(int(alpha.max()) * FAINTEST)
    rgb = FillOutside(icon.convert('RGB'), mask)
    sharp = rgb.filter(ImageFilter.UnsharpMask(radius=1, percent=260, threshold=0))
    both = Image.blend(Flat(rgb), sharp, 0.4)
    strong = ImageEnhance.Contrast(ImageEnhance.Color(both).enhance(1.3)).enhance(1.12)
    return Outline(strong, mask)

if __name__ == '__main__':
    if len(sys.argv) < 2:
        sys.exit(__doc__ or 'python3 redraw.py <57.DAT> [sheet.png]')
    done = []
    for status, icon in Icons(sys.argv[1]):
        if status in DRAWN_BY_HAND or icon.getchannel('A').getextrema()[1] > GAMES_SOLID:
            continue
        new = Redraw(icon)
        new.save(os.path.join(here, '%d.png' % status))
        done.append((status, icon, new))
    print('%d icons redrawn' % len(done))

    if len(sys.argv) > 2:
        from PIL import ImageDraw
        columns, zoom = 20, 3
        size = SIDE * zoom
        sheet = Image.new('RGBA', (columns * (size + 8) + 8, -(-len(done) // columns) * (size * 2 + 26) + 8), (48, 48, 64, 255))
        pen = ImageDraw.Draw(sheet)
        for n, (status, icon, new) in enumerate(done):
            x, y = 8 + (n % columns) * (size + 8), 8 + (n // columns) * (size * 2 + 26)
            r, g, b, a = icon.split()
            was = Image.merge('RGBA', (r, g, b, a.point(lambda v: 255 if v > 0 else 0))).resize((size, size), Image.NEAREST)
            sheet.paste(was, (x, y), was)
            now = new.resize((size, size), Image.NEAREST); sheet.paste(now, (x, y + size), now)
            pen.text((x + size // 2, y + size * 2 + 1), str(status), fill=(230, 230, 240, 255), anchor='ma')
        sheet.save(sys.argv[2])
