# Draws the status icons in this folder: each large, as flat shapes with a dark line round them, and
# brought down to 32x32. xiframes shows <status>.png from here in place of the game's own icon for
# that status. It needs Pillow.
#
#   python3 generate.py            writes the icons beside this file
#   python3 generate.py sheet.png  and a sheet of them all, enlarged, to look over
import math, os, sys
from PIL import Image, ImageDraw
out = os.path.dirname(os.path.abspath(__file__))
K = 16                      # drawn at 16 times the size
N = 32 * K
DARK = (30, 22, 8, 255)

def star(cx, cy, rays, inner, turn=0):
    # a star: rays is how far each point reaches, one after another round it; inner how far in the hollows between come
    points = []
    for n, reach in enumerate(rays):
        angle = turn + n * 2 * math.pi / len(rays)
        points.append(((cx + math.sin(angle) * reach) * K, (cy - math.cos(angle) * reach) * K))
        angle += math.pi / len(rays)
        points.append(((cx + math.sin(angle) * inner) * K, (cy - math.cos(angle) * inner) * K))
    return points

def finish(im):
    small = im.resize((32, 32), Image.LANCZOS)
    # hard edges: a pixel is there or it is not
    r, g, b, a = small.split()
    return Image.merge('RGBA', (r, g, b, a.point(lambda v: 255 if v >= 128 else 0)))

def dia():
    # a shine: four long rays and four short between them, gold at the edge and white at the heart
    im = Image.new('RGBA', (N, N), (0, 0, 0, 0)); d = ImageDraw.Draw(im)
    long, short = 15.6, 10.4
    def burst(grow, inner, fill):
        d.polygon(star(16, 16, [long + grow, short + grow] * 4, inner), fill=fill)
    burst(0, 7.0, DARK)
    burst(-1.5, 5.6, (236, 160, 28, 255))
    burst(-3.4, 4.6, (255, 214, 84, 255))
    burst(-6.4, 3.4, (255, 246, 190, 255))
    d.ellipse([(16 - 3.4) * K, (16 - 3.4) * K, (16 + 3.4) * K, (16 + 3.4) * K], fill=(255, 255, 255, 255))
    return finish(im)

icons = { 134: dia() }

for status, im in icons.items():
    im.save(f'{out}/{status}.png')
if len(sys.argv) > 1:
    ids = sorted(icons)
    sheet = Image.new('RGBA', (len(ids) * 264, 264 + 84), (48, 48, 64, 255))
    for n, i in enumerate(ids):
        b = icons[i].resize((256, 256), Image.NEAREST); sheet.paste(b, (n * 264 + 4, 4), b)
        s = icons[i].resize((26, 26), Image.BILINEAR).resize((78, 78), Image.NEAREST); sheet.paste(s, (n * 264 + 93, 264), s)
    sheet.save(sys.argv[1])
