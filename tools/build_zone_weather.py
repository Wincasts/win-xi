#!/usr/bin/env python3
"""Build the info panel's zone weather tables from the Phoenix server's data, for the forecast.

The server (src/map/zone.cpp, UpdateWeather) rolls each zone's weather from a table of 2160
Vana'diel days (sql/zone_weather.sql: a blob of 2160 16-bit words, a day each, holding three 5-bit
weather ids: normal in the top bits, then common, then rare). Day n of the cycle is the number of
Vana'diel days since the Vana'diel epoch (1 January 2002 JST; the client's raw game time is the
Earth seconds since it, 3456 to a day) modulo 2160. A word of 0 holds no entry: the day takes the
last entry before it, and days before the first entry have no weather at all. Every 3 to 30 Earth
minutes the zone rolls again: 15% the rare weather, 35% the common, the rest the normal. From 2:00
to 7:00, outside cities, a roll that gives a clear sky (none, sunshine, clouds or fog) is fog
instead. A zone with one entry or none never rolls: its weather is the common weather of the entry
at day 0, or none.

Writes addons/libs/winxi/infopanel/zone_weather.lua: the distinct day tables (one string of 2160
bytes each, a byte a day, 33 + the index of the day's weather triple), each zone's table or its
fixed weather, and which zones are cities (data/zones/<name>/zone.yaml types) for the fog rule.
Reads the live branch of phoenixffxi/Phoenix, fetched from GitHub (tools/phoenix), as live loads it:
the zone.yaml types patched by the modules, and the build stops if module SQL ever touches
zone_weather (none does) or a module's Lua sets a zone's weather (phoenix.modules.guard).
"""
import argparse
import io
import re
import sys
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_zone_kinds import zone_ids  # noqa: E402
from build_item_data import enabled_files  # noqa: E402
from phoenix import modules, source  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
CYCLE = 2160
FIRST_BYTE = 33


def is_city(server, name):
    """Whether the zone's types (data/zones/<name>/zone.yaml) include city, as the server's type mask has it."""
    folder = re.sub(r'[^a-z0-9_]', '', name.lower().replace('-', '_'))
    document = modules.load_yaml(server, f'zones/{folder}/zone')
    return document is not None and 'city' in (document.get('type') or [])


def check_modules(server):
    """Stops the build where a module would change the weather: SQL over zone_weather, which this
    does not replay, or Lua that sets a zone's weather."""
    touching = [p.relative_to(server).as_posix() for p in enabled_files(server, '.sql')
                if re.search(r'\bzone_weather\b', p.read_text(encoding='utf-8-sig'))]
    if touching:
        sys.exit('Module SQL changes zone_weather, which this build does not replay: ' + ', '.join(touching))
    modules.guard(server, ('xi.zones.', 'xi.weather'), lambda o: None if 'setWeather' in o.body else 'leaves the weather',
                  out=io.StringIO())


def entries(blob):
    """(day, (normal, common, rare)) for each word that holds one, in day order."""
    found = []
    for day in range(CYCLE):
        word = int.from_bytes(blob[2 * day:2 * day + 2], 'little')
        if word:
            found.append((day, (word >> 10, (word >> 5) & 0x1F, word & 0x1F)))
    return found


def expand(found):
    """The triple in force on each of the 2160 days: the last entry at or before it, none before the first."""
    days, current, at = [], (0, 0, 0), 0
    for day in range(CYCLE):
        while at < len(found) and found[at][0] <= day:
            current = found[at][1]
            at += 1
        days.append(current)
    return days


def lua_string(indexes):
    """A Lua string literal of one byte a day: 33 + the index, escaped where the byte is not plain."""
    out = []
    for index in indexes:
        byte = FIRST_BYTE + index
        if byte > 126:
            out.append('\\%d' % byte)
        elif byte in (34, 92):  # " and \
            out.append('\\' + chr(byte))
        else:
            out.append(chr(byte))
    return '"' + ''.join(out) + '"'


def chances(server):
    """The rare and common weather's chances out of 100 (zone.cpp's UpdateWeather)."""
    found = modules.cpp_modules_mentioning(server, 'WeatherChance', 'UpdateWeather')
    if found:
        sys.exit(f'{", ".join(found)} name UpdateWeather: read what they change first')
    code = modules.blank_cpp_comments((server / 'src/map/zone.cpp').read_text())
    m = re.search(r'if \(WeatherChance < (\d+)\)\s*\{\s*selectedWeather = weatherType\.rare;\s*\}\s*else if \(WeatherChance < (\d+)\)\s*\{\s*selectedWeather = weatherType\.common;', code)
    if m is None:
        sys.exit('src/map/zone.cpp: the rare and common weather\'s chances are not as they were written')
    return int(m.group(1)), int(m.group(2)) - int(m.group(1))


def build(server, output):
    check_modules(server)
    rare, common = chances(server)
    ids = zone_ids(server)
    text = (server / 'sql/zone_weather.sql').read_text(encoding='utf-8')
    rows = re.findall(r"\((\d+),(0x[0-9A-Fa-f]+|NULL)\)", text)
    if not rows:
        sys.exit('No zones found in sql/zone_weather.sql')
    fixed, dynamic = {}, {}
    for zone, blob in rows:
        zone = int(zone)
        found = entries(bytes.fromhex(blob[2:])) if blob != 'NULL' else []
        if len(found) <= 1:
            fixed[zone] = found[0][1][1] if found and found[0][0] == 0 else 0
        else:
            dynamic[zone] = tuple(expand(found))
    counts = Counter(triple for days in dynamic.values() for triple in days)
    triples = [triple for triple, _ in counts.most_common()]
    index = {triple: i for i, triple in enumerate(triples)}
    patterns, pattern_of = [], {}
    for zone in sorted(dynamic):
        days = dynamic[zone]
        if days not in pattern_of:
            pattern_of[days] = len(patterns) + 1
            patterns.append(days)
    cities = sorted(zone for zone, name in ids.items() if is_city(server, name))
    lines = ['-- Generated by tools/build_zone_weather.py; do not edit.',
             '-- The Phoenix server\'s weather tables, for the info panel\'s forecast (winxi.infopanel.forecast):',
             '-- triples: every (normal, common, rare) weather the tables hold, by index; patterns: the distinct',
             '-- tables, a byte a day for the 2160 days of the cycle, 33 + the index of the day\'s triple; zones:',
             '-- each rolling zone\'s pattern; fixed: the weather of each zone that never rolls; cities: the',
             '-- zones the fog rule leaves alone.',
             'return {',
             '    cycle = %d,' % CYCLE,
             '    rareChance = %d, commonChance = %d, -- of 100 (zone.cpp\'s UpdateWeather); the normal weather takes the rest' % (rare, common),
             '    triples = {']
    for triple in triples:
        lines.append('        { %d, %d, %d },' % triple)
    lines.append('    },')
    lines.append('    patterns = {')
    for days in patterns:
        lines.append('        ' + lua_string([index[t] for t in days]) + ',')
    lines.append('    },')
    lines.append('    zones = {')
    for zone in sorted(dynamic):
        lines.append('        [%d] = %d, -- %s' % (zone, pattern_of[dynamic[zone]], ids.get(zone, '?')))
    lines.append('    },')
    lines.append('    fixed = {')
    for zone in sorted(fixed):
        lines.append('        [%d] = %d, -- %s' % (zone, fixed[zone], ids.get(zone, '?')))
    lines.append('    },')
    lines.append('    cities = {')
    for zone in cities:
        lines.append('        [%d] = true, -- %s' % (zone, ids[zone]))
    lines.append('    },')
    lines.append('}')
    output.write_text('\n'.join(lines) + '\n', encoding='utf-8')
    return len(dynamic), len(fixed), len(patterns), len(triples), len(cities)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    source.add_arguments(parser)
    parser.add_argument('--output', type=Path, default=ROOT / 'addons/libs/winxi/infopanel/zone_weather.lua')
    args = parser.parse_args()
    found = source.from_arguments(args)
    print(f'Server: {found.describe()}')
    rolling, fixed, patterns, triples, cities = build(found.path, args.output)
    print(f'Wrote {args.output}: {rolling} rolling zones over {patterns} patterns of {triples} triples, '
          f'{fixed} fixed, {cities} cities')
