#!/usr/bin/env python3
"""Make the status icons of the buffs addon from FFXIV's.

tools/status_icons.csv says which FFXIV icon stands for each FFXI status, a status to
a line:

    ffxi_id, ffxi_name, ffxiv_icon, ffxiv_name, tint

ffxiv_icon is the icon's number (a file of references/ffxiv-status-icons/icons), and
is what is used when it is given. Left empty, ffxiv_name is looked up in that folder's
statuses.csv instead: a status's name as FFXIV has it, with #n after it for the icon
of its nth stack ("Bunshin#2"). A line with neither leaves the status with the game's
own icon. tint, where given, is a colour (#rrggbb) the icon is turned to: what is coloured
in it takes that colour and what is grey or white is left, so that statuses FFXI draws
as one icon in several colours (a bard's songs, a corsair's rolls, a puppetmaster's
maneuvers) can share one of FFXIV's the same way. A grey tint takes the colour out.
To change an icon, put another number or name on its line (index.html in the
references folder is there to pick from) and run this again.

Each icon, 48 by 64 with its own transparency, is put in the middle of a square of 64
(a size a graphics card takes without stretching it) and written to
addons/buffs/icons/<ffxi_id>.png, and the numbers found for names are written back to
the csv. --sheet <file> also draws every status beside its icon, to look the choices over,
and --page writes mapping.html beside the FFXIV icons: each status's FFXI icon (XivParty's
copy, where the references have it), the FFXIV icon given it and the status that is from.

Requires Pillow.
"""
import argparse
import colorsys
import csv
import html
import os
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


def tone(pixels):
    """How strong and how bright the colour of an icon is, over what of it is coloured."""
    coloured = [(s, v) for _, s, v, a in pixels if a > 128 and s > 0.25 and v > 0.2]
    if not coloured:
        return 0.01, 0.5
    return sum(s for s, _ in coloured) / len(coloured), sum(v for _, v in coloured) / len(coloured)


def recolour(image, tint):
    """The icon with what is coloured in it turned to the tint; what is grey or white is left."""
    red, green, blue = (int(tint[i:i + 2], 16) / 255 for i in (1, 3, 5))
    hue, strength, brightness = colorsys.rgb_to_hsv(red, green, blue)
    raw = image.tobytes()
    data = [tuple(raw[at:at + 4]) for at in range(0, len(raw), 4)]
    pixels = [colorsys.rgb_to_hsv(r / 255, g / 255, b / 255) + (a,) for r, g, b, a in data]
    own_strength, own_brightness = tone(pixels)
    brighter = min(1.3, max(0.55, (brightness / own_brightness) ** 0.6))
    made = []
    for (r, g, b, a), (_, s, v, _) in zip(data, pixels):
        if s > 0.12 and a > 0:
            # eased in, so that no edge shows where the colour starts
            share = min(1, (s - 0.12) / 0.2)
            new = colorsys.hsv_to_rgb(hue, min(1, s * strength / own_strength), min(1, v * brighter))
            r, g, b = (round(share * 255 * n + (1 - share) * o) for n, o in zip(new, (r, g, b)))
        made.append((r, g, b, a))
    turned = Image.new('RGBA', image.size)
    turned.putdata(made)
    return turned


def load_icon(source, icon, tint):
    image = Image.open(source / 'icons' / f'{icon:06d}.png').convert('RGBA')
    return recolour(image, tint) if tint else image


def draw_sheet(rows, source, path):
    columns, cell_w, cell_h = 12, 132, 96
    sheet = Image.new('RGB', (columns * cell_w, -(-len(rows) // columns) * cell_h), (38, 41, 48))
    draw = ImageDraw.Draw(sheet)
    for index, (ffxi_id, name, icon, tint) in enumerate(rows):
        x, y = index % columns * cell_w, index // columns * cell_h
        image = load_icon(source, icon, tint)
        sheet.paste(image, (x + (cell_w - image.width) // 2, y + 2), image)
        draw.text((x + 4, y + 68), f'{ffxi_id} {name}'[:21], fill=(220, 220, 220))
    sheet.save(path)


PAGE = '''<!doctype html><meta charset="utf-8"><title>FFXI to FFXIV status icons</title>
<style>body{background:#1b1d22;color:#ddd;font:13px sans-serif;margin:16px}
input{background:#2a2d34;color:#eee;border:1px solid #444;padding:6px;font-size:14px}
#g{display:grid;grid-template-columns:repeat(auto-fill,minmax(270px,1fr));gap:6px;margin-top:12px}
.c{background:#262930;padding:6px 8px;border-radius:4px;display:flex;align-items:center;gap:8px}
.o{width:32px;height:32px;flex:none}.n{height:64px;width:48px;object-fit:cover;flex:none}.a{color:#777}.none{color:#888;width:48px;text-align:center}small{color:#999}</style>
<input id="q" placeholder="Filter by FFXI or FFXIV name, or status id" size="44" autofocus> <span id="t"></span>
<div id="g">%s</div>
<script>const q=document.getElementById('q'),c=[...document.querySelectorAll('.c')],t=document.getElementById('t');
function f(){const s=q.value.toLowerCase();let n=0;for(const e of c){const m=e.dataset.s.includes(s);e.style.display=m?'':'none';n+=m}t.textContent=n+' statuses'}q.oninput=f;f()</script>'''


def write_page(rows, source, out):
    built = os.path.relpath(out, source)
    cards = []
    for row in rows:
        ffxi_id, name, taken = row['ffxi_id'], row['ffxi_name'], row['ffxiv_name']
        old = source.parent / 'XivParty/assets/buffIcons' / f'{ffxi_id}.png'
        old = f'<img class="o" src="../XivParty/assets/buffIcons/{ffxi_id}.png">' if old.exists() else '<span class="o"></span>'
        new = f'<img class="n" src="{built}/{ffxi_id}.png">' if row['ffxiv_icon'] else '<span class="none">game icon</span>'
        search = html.escape(f'{ffxi_id} {name} {taken}'.lower())
        cards.append(f'<div class="c" data-s="{search}">{old}<span class="a">&rarr;</span>{new}'
                     f'<div><b>{ffxi_id} {html.escape(name)}</b><br><small>{html.escape(taken) or "&mdash;"}</small></div></div>')
    (source / 'mapping.html').write_text(PAGE % '\n'.join(cards))


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--map', type=Path, default=ROOT / 'tools/status_icons.csv')
    parser.add_argument('--source', type=Path, default=ROOT / 'references/ffxiv-status-icons')
    parser.add_argument('--out', type=Path, default=ROOT / 'addons/buffs/icons')
    parser.add_argument('--sheet', type=Path)
    parser.add_argument('--page', action='store_true')
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
        made.append((int(row['ffxi_id']), row['ffxi_name'], icon, (row.get('tint') or '').strip()))

    # the folder is this tool's own: what a line no longer asks for goes
    if args.out.exists():
        for old in args.out.glob('*.png'):
            old.unlink()
    args.out.mkdir(parents=True, exist_ok=True)
    for ffxi_id, _, icon, tint in made:
        image = load_icon(args.source, icon, tint)
        square = Image.new('RGBA', (SQUARE, SQUARE), (0, 0, 0, 0))
        square.paste(image, ((SQUARE - image.width) // 2, (SQUARE - image.height) // 2))
        square.save(args.out / f'{ffxi_id}.png', optimize=True)

    with open(args.map, 'w', newline='') as handle:
        writer = csv.DictWriter(handle, fieldnames=['ffxi_id', 'ffxi_name', 'ffxiv_icon', 'ffxiv_name', 'tint'], lineterminator='\n')
        writer.writeheader()
        writer.writerows(rows)

    if args.page:
        write_page(rows, args.source, args.out)
    if args.sheet:
        draw_sheet(made, args.source, args.sheet)
    print(f'{len(made)} of {len(rows)} statuses given an icon, in {args.out}')
    for line in unfound:
        print('  ' + line)


if __name__ == '__main__':
    main()
