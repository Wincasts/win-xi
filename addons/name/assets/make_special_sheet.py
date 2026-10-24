#!/usr/bin/env python3
"""Gathers the signs in special/ into the one sheet the addon draws them from, special.png.

    python3 make_special_sheet.py

Run it after changing any of them. The plugin has eight textures for the names and they are all
taken, so the tracked notorious monster's sign, a vendor's coin and the party and alliance roles share
one: 64 pixels square each, four to a row, in the order of SIGNS. special.lua numbers them the same.
Needs Pillow.
"""

import os

from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
CELL = 64
ACROSS, DOWN = 4, 2
SIGNS = ('hunt.png', 'vendor.png', 'alliance-leader.png', 'party-leader.png',
         'alliance-party-leader.png', 'alliance-member.png', 'party-member.png')

sheet = Image.new('RGBA', (CELL * ACROSS, CELL * DOWN), (0, 0, 0, 0))
for place, name in enumerate(SIGNS):
    sign = Image.open(os.path.join(HERE, 'special', name)).convert('RGBA')
    if sign.size != (CELL, CELL):
        sign = sign.resize((CELL, CELL), Image.LANCZOS)
    sheet.paste(sign, ((place % ACROSS) * CELL, (place // ACROSS) * CELL))
sheet.save(os.path.join(HERE, 'special.png'))
print('special.png: %d signs' % len(SIGNS))
