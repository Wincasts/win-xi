#!/usr/bin/env python3
"""Original nine-slice window borders for winxi's theme (first made for the party addon); requires Pillow.
64x64 RGBA, 8px corner slices. No game artwork is used.
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1] / 'addons/libs/winxi/assets/borders'
SIZE, INSET, S = 64, 8, 4
PALETTES = {
    'silver': [(14, 19, 26), (57, 66, 78), (216, 225, 235), (119, 135, 154), (39, 48, 62), (156, 173, 192), (28, 37, 50), (9, 14, 23)],
    'bronze': [(24, 17, 12), (78, 52, 32), (236, 207, 148), (163, 119, 65), (61, 40, 26), (184, 143, 84), (49, 34, 24), (16, 13, 12)],
    'ffxi': [(13, 18, 32), (71, 79, 106), (218, 223, 237), (153, 163, 193), (82, 94, 131), (184, 192, 216), (47, 59, 99), (10, 19, 47)],
    'crystal': [(9, 28, 47), (64, 135, 173), (211, 247, 255), (121, 201, 228), (41, 93, 137), (149, 231, 249), (49, 115, 159), (8, 27, 49)],
    'royal': [(29, 21, 22), (114, 83, 52), (252, 235, 184), (203, 172, 104), (84, 56, 40), (239, 215, 156), (114, 78, 43), (27, 21, 28)],
    'royal_silver': [(17, 22, 31), (89, 101, 119), (246, 250, 255), (177, 190, 208), (57, 69, 88), (223, 233, 247), (98, 114, 137), (16, 24, 37)],
    'royal_platinum': [(91, 101, 116), (177, 188, 204), (255, 255, 255), (229, 235, 244), (134, 148, 168), (247, 250, 255), (193, 206, 223), (80, 96, 117)],
    'mythril': [(12, 20, 33), (70, 96, 128), (226, 238, 252), (132, 162, 198), (44, 63, 92), (176, 202, 232), (34, 52, 80), (9, 16, 30)],
    'adaman': [(22, 10, 10), (92, 38, 30), (232, 178, 140), (150, 74, 52), (58, 22, 20), (196, 118, 84), (46, 18, 18), (14, 7, 9)],
    'jade': [(8, 24, 20), (44, 108, 84), (206, 248, 226), (98, 176, 140), (28, 74, 58), (150, 220, 186), (30, 88, 68), (6, 22, 18)],
    'amethyst': [(20, 10, 32), (86, 52, 128), (240, 222, 255), (150, 112, 196), (56, 32, 88), (200, 168, 236), (66, 40, 104), (16, 8, 28)],
    'obsidian': [(8, 9, 17), (46, 44, 66), (169, 168, 196), (76, 74, 96), (26, 25, 40), (117, 115, 150), (44, 41, 64), (11, 10, 22)],
}
# Plain Obsidian: obsidian's bands without the light slash in its corners
PALETTES['obsidian_plain'] = PALETTES['obsidian']


def generate(name, palette):
    im = Image.new('RGBA', (SIZE*S, SIZE*S))
    # Rounded nested bevel bands; centre is completely transparent.
    d = ImageDraw.Draw(im)
    for i, color in enumerate(palette):
        inset = i*S
        d.rounded_rectangle((inset, inset, SIZE*S-1-inset, SIZE*S-1-inset),
                            radius=max(1, (8-i)*S), fill=(*color, 255))
    d.rounded_rectangle((INSET*S, INSET*S, (SIZE-INSET)*S-1, (SIZE-INSET)*S-1),
                        radius=S, fill=(0, 0, 0, 0))
    if name in ('silver', 'bronze', 'mythril'):
        # Fine brushed highlights on the flat portions, without noisy corners.
        for x in range(11*S, 53*S, 3*S):
            d.line((x, 3*S, x+S, 3*S), fill=(255, 255, 255, 45))
        # Inlaid corner studs.
        for x, y in ((5,5), (58,5), (5,58), (58,58)):
            d.ellipse(((x-.65)*S, (y-.65)*S, (x+.65)*S, (y+.65)*S), fill=(*palette[2],255))
    if name in ('crystal', 'royal', 'royal_silver', 'royal_platinum', 'obsidian', 'adaman', 'jade', 'amethyst'):
        # Corner ornament stays inside each fixed-size corner slice, never in the content area.
        # Mirrored facets give crystal a cut-glass feel; gold has an inlaid lozenge,
        # and obsidian a restrained platinum slash.
        for flip_x, flip_y in ((False, False), (True, False), (False, True), (True, True)):
            def points(coords):
                return [((SIZE-x if flip_x else x)*S, (SIZE-y if flip_y else y)*S) for x,y in coords]
            if name in ('crystal', 'jade', 'amethyst'):
                face, shade = ((227, 253, 255), (96, 183, 221)) if name == 'crystal' else \
                    ((222, 255, 238), (72, 160, 120)) if name == 'jade' else ((246, 232, 255), (140, 98, 196))
                d.polygon(points(((1,7), (3,2), (7,1), (5,5))), fill=(*face, 255))
                d.polygon(points(((3,2), (7,1), (5,5))), fill=(*shade, 255))
            elif name == 'adaman':
                # A riveted plate across the corner.
                d.polygon(points(((1,4), (4,1), (7,1), (1,7))), fill=(*palette[5], 255))
                (cx, cy), = points(((4, 4),))
                d.ellipse((cx-.6*S, cy-.6*S, cx+.6*S, cy+.6*S), fill=(250, 214, 184, 255))
            elif name in ('royal', 'royal_silver', 'royal_platinum'):
                bright, inset = ((255, 244, 202), (75, 54, 52)) if name == 'royal' else ((250, 253, 255), (49, 63, 83))
                if name == 'royal_platinum':
                    bright, inset = (255, 255, 255), (137, 153, 175)
                d.line(points(((1,7), (2,3), (3,2), (7,1))), fill=(*bright, 255), width=S)
                d.polygon(points(((3,5), (5,3), (7,5), (5,7))), fill=(*palette[5], 255))
                d.polygon(points(((4,5), (5,4), (6,5), (5,6))), fill=(*inset, 255))
            else:
                d.line(points(((2,6), (6,2))), fill=(221, 221, 237, 255), width=S)
    im = im.resize((SIZE, SIZE), Image.Resampling.LANCZOS)
    im.save(ROOT / f'{name}.png')
    return im


def nine_slice(im, width, height):
    out = Image.new('RGBA', (width, height))
    src = [0, INSET, SIZE-INSET, SIZE]
    edge = 3  # Match the runtime border width; source slices retain the bevel detail.
    xx, yy = [0, edge, width-edge, width], [0, edge, height-edge, height]
    for row in range(3):
        for col in range(3):
            if row == col == 1:
                continue
            tile = im.crop((src[col], src[row], src[col+1], src[row+1]))
            tile = tile.resize((xx[col+1]-xx[col], yy[row+1]-yy[row]), Image.Resampling.BILINEAR)
            out.alpha_composite(tile, (xx[col], yy[row]))
    return out


def preview(textures):
    rows = (len(textures) + 2) // 3
    out = Image.new('RGBA', (960, 55 + rows * 305), '#141923')
    d = ImageDraw.Draw(out)
    font = ImageFont.truetype('DejaVuSans.ttf', 17)
    small = ImageFont.truetype('DejaVuSans.ttf', 14)
    d.text((24, 18), 'XIFRAMES / WINDOW BORDER CONCEPTS', font=font, fill='#d8e1ef')
    labels = {'silver':'BRUSHED SILVER', 'bronze':'BRONZE', 'ffxi':'FFXI-INSPIRED',
              'crystal':'CRYSTAL', 'royal':'ROYAL GOLD', 'royal_silver':'ROYAL SILVER', 'royal_platinum':'ROYAL PLATINUM', 'obsidian':'OBSIDIAN', 'obsidian_plain':'PLAIN OBSIDIAN',
              'mythril':'MYTHRIL', 'adaman':'ADAMAN', 'jade':'JADE', 'amethyst':'AMETHYST'}
    backgrounds = {'crystal': (13, 38, 63), 'royal': (39, 26, 42), 'obsidian': (20, 18, 32), 'obsidian_plain': (20, 18, 32),
                   'adaman': (36, 18, 18), 'jade': (12, 34, 28), 'amethyst': (28, 16, 42)}
    for index, (name, im) in enumerate(textures.items()):
        col, grid_row = index % 3, index // 3
        x, y, w, h = 24+col*314, 85+grid_row*305, 284, 236
        d.text((x, y-28), labels[name], font=font, fill='#bfcbdd')
        # Illustrative background only; runtime keeps the user's theme background.
        for line in range(h):
            t = line/h
            base = backgrounds.get(name, (20, 38, 84) if name == 'ffxi' else (23, 29, 39))
            color = tuple(int(channel * (1 - .4*t)) for channel in base)
            d.line((x,y+line,x+w-1,y+line), fill=color)
        out.alpha_composite(nine_slice(im,w,h), (x,y))
        for row, member in enumerate(('Ironwall', 'Quickblade', 'Healer')):
            yy = y+24+row*65
            d.text((x+19,yy), member, font=small, fill='#e1e6ef')
            d.rounded_rectangle((x+20, yy+23, x+w-20, yy+36), radius=2, fill='#26303f', outline='#8f9bad')
            d.rectangle((x+22,yy+25,x+22+int((w-44)*(.92-row*.23)),yy+34),fill='#a14e63')
            d.line((x+23,yy+26,x+22+int((w-44)*(.92-row*.23)),yy+26),fill='#de8794')
    out.convert('RGB').save(ROOT / 'preview.png')


if __name__ == '__main__':
    ROOT.mkdir(parents=True, exist_ok=True)
    preview({name: generate(name, palette) for name, palette in PALETTES.items()})
    print(f'Generated borders and preview in {ROOT}')
