#!/usr/bin/env python3
"""The game's own invitation and treasure icons for the party addon, cut from name's player icon sheet.

name's sheet (addons/name/assets/player-icons.png) is exported from the client's menu DAT by
tools/export_name_icons.py. This takes two of its 32x32 icons, the dark circle with a green
exclamation mark and the treasure chest, so that the party addon needs nothing of name's at runtime. Requires Pillow.
"""
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1] / 'addons'
SHEET = ROOT / 'name/assets/player-icons.png'
OUT = ROOT / 'party/assets/notices'
ICONS = {'invite': (64, 64), 'treasure': (128, 32)}  # the top left of each, in the sheet

if __name__ == '__main__':
    OUT.mkdir(parents=True, exist_ok=True)
    sheet = Image.open(SHEET).convert('RGBA')
    for name, (x, y) in ICONS.items():
        sheet.crop((x, y, x + 32, y + 32)).save(OUT / f'{name}.png')
    print(f'Cut {len(ICONS)} icons into {OUT}')
