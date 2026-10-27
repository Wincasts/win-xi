#!/usr/bin/env python3
"""Build the zone addon's dungeon and town entrances from the Phoenix server's zone lines.

Each zone's data/zones/<name>/zone.yaml lists its zone lines, with where each one is (from) and the
zone it leads to. A dungeon entrance is a line from open country or a city into a dungeon (the
server's type, as tools/build_zone_kinds.py reads it); lines into the same dungeon within 30 yalms
and 10 of height of each other are one entrance. A town entrance is a line from open country or a
dungeon into a city (and Nashmau, which the server calls open country), its lines joined within 60
yalms: a town's gates are wider. Each one's place is the middle of its lines.

The number the zone's map gives each entrance, and a name where the map has one (the Horutoto
towers), are in addons/zone/research/dungeon_entrances.json, read off the maps by eye and keyed by
the entrance's zone and first line. An entrance the review has not seen is still written, without
a number, and named here so it can be looked at. A town entrance the review marks covered (a
feature of the map already names the way in, as Jeuno's bridges do) is left out.

Names are the game's English zone names, from Boussole's zone table (references/boussole).

Writes winxi's entrances set (addons/libs/winxi/data/<server>/entrances; a set of build_winxi_data). Reads the live branch of phoenixffxi/Phoenix, fetched from
GitHub (tools/phoenix), as live loads it: module SQL over zone_settings and each zone.yaml patched by
the modules (phoenix.modules.load_yaml).
"""
import argparse
import json
import math
import re
import sys
from pathlib import Path


sys.path.insert(0, str(Path(__file__).resolve().parent))
from phoenix import modules, source  # noqa: E402
from build_zone_kinds import zone_rows  # noqa: E402
from build_zone_ja import names as zone_names  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
REVIEW = ROOT / 'addons/zone/research/dungeon_entrances.json'
BOUSSOLE = ROOT / 'references/boussole/data/zones.lua'
OUTPUT = None  # the entrances set's index.lua: data/<server>/entrances
SAME_ENTRANCE = {'dungeon': 30.0, 'town': 60.0}  # yalms apart, level
SAME_HEIGHT = 10.0
# The server's types do not make every town a city or every city a town.
TOWNS = {'Nashmau'}
NOT_TOWNS = {'Hall_of_the_Gods'}


def folder(name):
    return re.sub(r'[^a-z0-9_]', '', name.lower().replace('-', '_'))


def zones(server):
    """zone id -> (server name, type, zone lines)."""
    found = {}
    for zone, name in zone_rows(server, 'zoneid, name'):
        zone = int(zone)
        document = modules.load_yaml(server, f'zones/{folder(name)}/zone') if zone else None
        if document is None:
            continue
        types = document.get('type') or [None]
        found[zone] = (name, types[0], document.get('zonelines') or {})
    if not found:
        sys.exit('No zones found in sql/zone_settings.sql')
    return found


def leads_to(found, source, to):
    """'dungeon' or 'town' for a line from one zone into another that is announced, or None."""
    name, kind = found[to][0], found[to][1]
    if found[source][1] in ('outdoors', 'city') and kind == 'dungeon':
        return 'dungeon'
    town = name in TOWNS or (kind == 'city' and name not in NOT_TOWNS)
    if found[source][1] in ('outdoors', 'dungeon') and town and found[source][0] not in TOWNS:
        return 'town'
    return None


def entrances(found):
    """Each entrance: its zone, where it leads, its kind ('dungeon' or 'town'), its lines (key, x,
    height, z as the server has them)."""
    by_folder = {folder(name): zone for zone, (name, _, _) in found.items()}
    result = []
    for zone in sorted(found):
        lines = found[zone][2]
        for key in sorted(lines):
            line = lines[key]
            to = by_folder.get(line.get('to'))
            kind = to is not None and leads_to(found, zone, to)
            if not kind:
                continue
            x, height, z = (float(v) for v in line['from'][:3])
            for entrance in result:
                if entrance['zone'] == zone and entrance['to'] == to and any(
                        math.hypot(x - other[1], z - other[3]) < SAME_ENTRANCE[kind] and abs(height - other[2]) < SAME_HEIGHT
                        for other in entrance['lines']):
                    entrance['lines'].append((key, x, height, z))
                    break
            else:
                result.append({'zone': zone, 'to': to, 'kind': kind, 'lines': [(key, x, height, z)]})
    return result


def lua_string(text):
    return "'" + text.replace('\\', '\\\\').replace("'", "\\'") + "'"


def build_set(server, output, settings=()):
    """The entrances set, as build_winxi_data makes it: output/index.lua."""
    english = {zone: en for zone, (en, _) in zone_names(BOUSSOLE.read_text(encoding='utf-8')).items()}
    output.mkdir(parents=True, exist_ok=True)
    return build(Path(server), REVIEW, english, output / 'index.lua')


def build(server, review, english, output):
    found = zones(server)
    marked = json.loads(review.read_text(encoding='utf-8'))
    rows, unreviewed, numbered, towns = {}, [], 0, 0
    for entrance in entrances(found):
        zone, to, lines = entrance['zone'], entrance['to'], entrance['lines']
        key = f'{zone}:{lines[0][0]}'
        seen = marked.get(key)
        if seen and seen.get('covered'):
            continue
        if seen is None:
            unreviewed.append(f'{key} {found[zone][0]} -> {found[to][0]}')
            seen = {}
        count = len(lines)
        x, height, z = (sum(line[i] for line in lines) / count for i in (1, 2, 3))
        fields = [f'id = {lua_string(lines[0][0])}', f'to = {to}', f"kind = '{entrance['kind']}'",
                  f'to_name = {lua_string(english.get(to, found[to][0].replace("_", " ")))}']
        towns += entrance['kind'] == 'town'
        if seen.get('label'):
            fields.append(f'label = {lua_string(seen["label"])}')
            numbered += 1
        if seen.get('place'):
            fields.append(f'place = {lua_string(seen["place"])}')
        # Ashita's horizontal X and Y are the server's x and z; its Z is the server's height.
        fields.append(f'x = {x:.1f}, y = {z:.1f}, z = {height:.1f}')
        rows.setdefault(zone, []).append('{ ' + ', '.join(fields) + ' }')
    text = ['-- Generated by tools/build_zone_entrances.py; do not edit.',
            "-- Dungeon entrances in open country and cities, and town entrances in open country and dungeons,",
            "-- from the Phoenix server's zone lines. x, y and z are Ashita's (y north, z height); label is the",
            "-- number the zone's map gives it, place a name it gives it (research/dungeon_entrances.json).",
            'return {']
    for zone in sorted(rows):
        text.append(f'    [{zone}] = {{ -- {english.get(zone, found[zone][0])}')
        text.extend(f'        {row},' for row in rows[zone])
        text.append('    },')
    text.append('}')
    output.write_text('\n'.join(text) + '\n', encoding='utf-8')
    total = sum(len(r) for r in rows.values())
    return total, numbered, len(rows), unreviewed, towns


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    source.add_arguments(parser)
    parser.add_argument('--review', type=Path, default=REVIEW)
    parser.add_argument('--zones', type=Path, default=BOUSSOLE, help="Boussole's data/zones.lua, for the English names")
    parser.add_argument('--output', type=Path, default=None, help='Where to write it; default data/<server>/entrances/index.lua.')
    args = parser.parse_args()
    server = source.from_arguments(args)
    args.output = args.output or ROOT / 'addons/libs/winxi/data' / source.KEY / 'entrances' / 'index.lua'
    args.output.parent.mkdir(parents=True, exist_ok=True)
    print(f'Server: {server.describe()}')
    english = {zone: en for zone, (en, _) in zone_names(args.zones.read_text(encoding='utf-8')).items()}
    total, numbered, zone_count, unreviewed, towns = build(server.path, args.review, english, args.output)
    print(f'Wrote {args.output}: {total} entrances in {zone_count} zones ({towns} into towns), {numbered} with a map number')
    if unreviewed:
        print(f'{len(unreviewed)} not in {args.review.name}, written without a number:')
        for line in unreviewed:
            print('  ' + line)
