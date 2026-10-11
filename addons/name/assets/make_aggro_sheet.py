#!/usr/bin/env python3
"""Gathers the twelve signs in aggro/ into the one sheet the addon draws from, aggro.png.

    python3 make_aggro_sheet.py

Run it after changing any of them. Mob2 to Mob7 are a monster that is not aggressive, from the weakest
to a notorious one; Mob8 to Mob13 the same for one that is. Each is 64 pixels square, and they go into
the sheet in that order, four to a row. Needs Pillow.
"""

import os

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
CELL = 64

sheet = Image.new('RGBA', (CELL * 4, CELL * 4), (0, 0, 0, 0))
for place, number in enumerate(range(2, 14)):
    sign = Image.open(os.path.join(HERE, 'aggro', 'Mob%d_Icon.png' % number)).convert('RGBA')
    if sign.size != (CELL, CELL):
        sign = sign.resize((CELL, CELL), Image.LANCZOS)
    sheet.paste(sign, ((place % 4) * CELL, (place // 4) * CELL))
sheet.save(os.path.join(HERE, 'aggro.png'))
print('aggro.png: %d signs' % 12)
