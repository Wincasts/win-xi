#!/usr/bin/env python3
"""Make the status icons of the buffs addon from FFXIV's.

tools/status_icons.csv says which FFXIV icon stands for each FFXI status, a status to
a line:

    ffxi_id, ffxi_name, ffxiv_icon, ffxiv_name

ffxiv_icon is the icon's number (a file of references/ffxiv-status-icons/icons), and
is what is used when it is given. Left empty, ffxiv_name is looked up in that folder's
statuses.csv instead: a status's name as FFXIV has it, with #n after it for the icon
of its nth stack ("Bunshin#2"). A line with neither leaves the status with the game's
own icon. To change an icon, put another number or name on its line (index.html in the
references folder is there to pick from) and run this again.

Each icon, 48 by 64 with its own transparency, is put in the middle of a square of 64
(a size a graphics card takes without stretching it) and written to
addons/buffs/icons/<ffxi_id>.png, and the numbers found for names are written back to
the csv. --sheet <file> also draws every status beside its icon, to look the choices over.

Requires Pillow.
"""
import argparse
import csv
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1]
SQUARE = 64  # the side of an icon as the addon is given it


def load_names(source):
    """FFXIV's statuses by name, in lower case: the rows of statuses.csv for each."""
    names = {}
    with open(source / 'statuses.csv', newline='') as handle:
        for row in csv.DictReader(handle):
            names.setdefault(row['name'].lower(), []).append(row)
    return names


def find_icon(names, wanted, debuff):
    """The icon number for a name as the csv gives it, or None."""
    name, _, stack = wanted.partition('#')
    stack = int(stack) if stack else 1
    rows = names.get(name.strip().lower())
    if not rows:
        return None
    # a buff's icon for a buff where the name has both; one with a count on it only where a stack is
    # asked for; then the oldest
    kind = 'debuff' if debuff else 'buff'
    counted = '#' in wanted
    row = min(rows, key=lambda r: (r['category'] != kind, (int(r['max_stacks']) > 1) != counted,
                                   int(r['max_stacks']) < stack, int(r['status_id'])))
    if stack > max(int(row['max_stacks']), 1):
        return None
    return int(row['icon_id']) + stack - 1


def draw_sheet(rows, source, path):
    columns, cell_w, cell_h = 12, 132, 96
    sheet = Image.new('RGB', (columns * cell_w, -(-len(rows) // columns) * cell_h), (38, 41, 48))
    draw = ImageDraw.Draw(sheet)
    for index, (ffxi_id, name, icon) in enumerate(rows):
        x, y = index % columns * cell_w, index // columns * cell_h
        image = Image.open(source / 'icons' / f'{icon:06d}.png').convert('RGBA')
        sheet.paste(image, (x + (cell_w - image.width) // 2, y + 2), image)
        draw.text((x + 4, y + 68), f'{ffxi_id} {name}'[:21], fill=(220, 220, 220))
    sheet.save(path)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--map', type=Path, default=ROOT / 'tools/status_icons.csv')
    parser.add_argument('--source', type=Path, default=ROOT / 'references/ffxiv-status-icons')
    parser.add_argument('--out', type=Path, default=ROOT / 'addons/buffs/icons')
    parser.add_argument('--sheet', type=Path)
    args = parser.parse_args()

    names = load_names(args.source)
    with open(args.map, newline='') as handle:
        rows = list(csv.DictReader(handle))

    made, unfound = [], []
    for row in rows:
        icon = row['ffxiv_icon'].strip()
        if icon:
            icon = int(icon)
        elif row['ffxiv_name'].strip():
            # windower's names, which the csv keeps, are in lower case for what ails a character
            icon = find_icon(names, row['ffxiv_name'], row['ffxi_name'][:1].islower())
            row['ffxiv_icon'] = icon or ''
        if not icon:
            if row['ffxiv_name'].strip():
                unfound.append(f"{row['ffxi_id']} {row['ffxi_name']}: no FFXIV status called {row['ffxiv_name']}")
            continue
        if not (args.source / 'icons' / f'{icon:06d}.png').exists():
            unfound.append(f"{row['ffxi_id']} {row['ffxi_name']}: no icon {icon}")
            continue
        made.append((int(row['ffxi_id']), row['ffxi_name'], icon))

    # the folder is this tool's own: what a line no longer asks for goes
    if args.out.exists():
        for old in args.out.glob('*.png'):
            old.unlink()
    args.out.mkdir(parents=True, exist_ok=True)
    for ffxi_id, _, icon in made:
        image = Image.open(args.source / 'icons' / f'{icon:06d}.png').convert('RGBA')
        square = Image.new('RGBA', (SQUARE, SQUARE), (0, 0, 0, 0))
        square.paste(image, ((SQUARE - image.width) // 2, (SQUARE - image.height) // 2))
        square.save(args.out / f'{ffxi_id}.png', optimize=True)

    with open(args.map, 'w', newline='') as handle:
        writer = csv.DictWriter(handle, fieldnames=['ffxi_id', 'ffxi_name', 'ffxiv_icon', 'ffxiv_name'], lineterminator='\n')
        writer.writeheader()
        writer.writerows(rows)

    if args.sheet:
        draw_sheet(made, args.source, args.sheet)
    print(f'{len(made)} of {len(rows)} statuses given an icon, in {args.out}')
    for line in unfound:
        print('  ' + line)


if __name__ == '__main__':
    main()
