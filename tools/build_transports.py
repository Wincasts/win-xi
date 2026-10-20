#!/usr/bin/env python3
"""Build the info panel's ship and airship timetable from the Phoenix server's zone data.

The server (src/map/transports/ship_handler.cpp) runs every ship on a cycle from each zone's
data/zones/<name>/zone.yaml transport block: a run has a cycle length in seconds (every), an
offset, and phases laid back to back from the offset (arriving, docked, closing, departing; or
cycling and holding for a ship that carries nobody). The seconds into the cycle are
(vanadiel_timestamp - offset) mod every, the Vana'diel timestamp being the Earth seconds since the
Vana'diel epoch, which is the client's raw game time. The door is open through the docked phase:
boarding begins at its start and ends at its end (Voyage::boardingEnds), the riders are carried
into the voyage zone as the departing phase begins, and they are put ashore at the destination
at disembark seconds into the cycle (Voyage::disembarkFrom); the crossing takes
(disembark + every - boardingEnds) mod every seconds (Voyage::duration).

Only runs with a docked phase and voyage zones carry passengers (ShipHandler::registerVoyage);
the rest are scenery (the airships over the fields, Norg's ship, the pirates' ships) and are left
out. Each passenger run is named here with its kind, where it leaves from and where it goes, as
the data holds only the server's run names; a run the server adds that is not named here stops
the build, so the table is never missing a line without anyone knowing.

Writes addons/libs/winxi/infopanel/transports.lua: the kinds of line, the lines (each place a ship
leaves from and goes to, by the key the settings' whitelist knows it by) and each run's zone, labels,
cycle and phase seconds and voyage zones; winxi.infopanel.schedule
reads it. Reads the live branch of phoenixffxi/Phoenix, fetched from GitHub (tools/phoenix).
"""
import argparse
import re
import sys
from pathlib import Path

import yaml

sys.path.insert(0, str(Path(__file__).resolve().parent))
from build_zone_kinds import zone_ids  # noqa: E402
from phoenix import source  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]

# The groups as the timetable shows them, in order; the Whitegate ferries run only where the server has
# ENABLE_TOAU on (settings/default/main.lua), which Phoenix's live branch does
GROUPS = [
    ('airships', 'Airships'),
    ('ferry', 'Ferry: Selbina and Mhaura'),
    ('aht_urhgan', 'Ferries: Aht Urhgan'),
    ('manaclipper', 'Manaclipper: Bibiki Bay'),
    ('barge', "Barge: Carpenters' Landing"),
]

# run name -> (group, line, from, to). Two runs with the same line are one line of the timetable (the barge
# from the central landing runs by day and by night); the line's key names it in the settings' whitelist.
RUNS = {
    'sandoria_jeuno_airship': ('airships', 'sandoria_jeuno', "San d'Oria", 'Jeuno'),
    'jeuno_sandoria_airship': ('airships', 'jeuno_sandoria', 'Jeuno', "San d'Oria"),
    'bastok_jeuno_airship': ('airships', 'bastok_jeuno', 'Bastok', 'Jeuno'),
    'jeuno_bastok_airship': ('airships', 'jeuno_bastok', 'Jeuno', 'Bastok'),
    'windurst_jeuno_airship': ('airships', 'windurst_jeuno', 'Windurst', 'Jeuno'),
    'jeuno_windurst_airship': ('airships', 'jeuno_windurst', 'Jeuno', 'Windurst'),
    'kazham_jeuno_airship': ('airships', 'kazham_jeuno', 'Kazham', 'Jeuno'),
    'jeuno_kazham_airship': ('airships', 'jeuno_kazham', 'Jeuno', 'Kazham'),
    'selbina_mhaura_boat': ('ferry', 'selbina_mhaura', 'Selbina', 'Mhaura'),
    'mhaura_selbina_boat': ('ferry', 'mhaura_selbina', 'Mhaura', 'Selbina'),
    'mhaura_whitegate_boat': ('aht_urhgan', 'mhaura_alzahbi', 'Mhaura', 'Al Zahbi'),
    'whitegate_mhaura_boat': ('aht_urhgan', 'alzahbi_mhaura', 'Al Zahbi', 'Mhaura'),
    'whitegate_nashmau_boat': ('aht_urhgan', 'alzahbi_nashmau', 'Al Zahbi', 'Nashmau'),
    'nashmau_whitegate_boat': ('aht_urhgan', 'nashmau_alzahbi', 'Nashmau', 'Al Zahbi'),
    'manaclip_bibiki_purgonorgo': ('manaclipper', 'bibiki_purgonorgo', 'Bibiki Bay', 'Purgonorgo Isle'),
    'manaclip_purgonorgo_bibiki': ('manaclipper', 'purgonorgo_bibiki', 'Purgonorgo Isle', 'Bibiki Bay'),
    'manaclip_bibiki_tours': ('manaclipper', 'bibiki_tour', 'Bibiki Bay', 'Tour of the bay'),
    'barge_south_central': ('barge', 'barge_south_central', 'South landing', 'Central landing'),
    'barge_central_south_day': ('barge', 'barge_central_south', 'Central landing', 'South landing'),
    'barge_central_south_night': ('barge', 'barge_central_south', 'Central landing', 'South landing'),
    'barge_south_north': ('barge', 'barge_south_north', 'South landing', 'North landing'),
    'barge_north_central': ('barge', 'barge_north_central', 'North landing', 'Central landing'),
}

ORDER = list(RUNS)


def folder_of(name):
    """The server's data folder for a zone_settings name: Port_San_dOria -> port_san_doria."""
    return re.sub(r'[^a-z0-9_]', '', name.lower().replace('-', '_'))


def passenger_runs(server, ids):
    """Every run that carries riders, with its zone id, by run name."""
    folders = {folder_of(name): zone for zone, name in ids.items()}
    runs = {}
    for path in sorted((server / 'data/zones').glob('*/zone.yaml')):
        document = yaml.safe_load(path.read_text(encoding='utf-8')) or {}
        transport = document.get('transport')
        if not transport:
            continue
        zone = folders.get(path.parent.name)
        if zone is None:
            sys.exit(f'{path}: no zone id for {path.parent.name} in sql/zone_settings.sql')
        for name, run in transport['runs'].items():
            phases = run.get('phases') or []
            docked = [p for p in phases if p.get('state') == 'docked']
            crossings = run.get('voyage') or []
            if not docked or not crossings:
                continue
            every = int(run['every'])
            # phases run back to back from the offset; the one without a length takes the rest of the cycle
            stated = sum(int(p['seconds']) for p in phases if 'seconds' in p)
            cursor, starts = 0, {}
            for p in phases:
                starts[id(p)] = cursor
                cursor += int(p.get('seconds', every - stated))
            boards = starts[id(docked[0])]
            leaves = boards + int(docked[0]['seconds'])
            departing = [p for p in phases if p.get('state') == 'departing']
            departs = starts[id(departing[0])] if departing else leaves
            crossing_ids = []
            for crossing in crossings:
                found = folders.get(crossing)
                if found is None:
                    sys.exit(f'{path}: run {name} crosses {crossing}, which sql/zone_settings.sql has not')
                crossing_ids.append(found)
            if name in runs:
                sys.exit(f'{path}: run {name} is declared twice')
            runs[name] = {
                'zone': zone, 'every': every, 'offset': int(run.get('offset', 0)),
                'boards': boards, 'leaves': leaves, 'departs': departs,
                'disembark': int(run.get('disembark', 0)), 'crossings': crossing_ids,
            }
    return runs


def build(server, output):
    ids = zone_ids(server)
    runs = passenger_runs(server, ids)
    unnamed = sorted(set(runs) - set(RUNS))
    if unnamed:
        sys.exit('Passenger runs the server has that this script does not name: ' + ', '.join(unnamed)
                 + '\nAdd each to RUNS in tools/build_transports.py (its group, where it leaves from and where it goes).')
    missing = sorted(set(RUNS) - set(runs))
    if missing:
        sys.exit('Runs this script names that the server no longer has: ' + ', '.join(missing))
    lines = ['-- Generated by tools/build_transports.py; do not edit.',
             "-- The Phoenix server's ship and airship timetable, for the info panel (winxi.infopanel.schedule):",
             '-- groups: the kinds of line, in order; lines: each place a ship leaves from and goes to, in order,',
             '-- by the key the settings know it by; runs: each passenger run as the server cycles it, in seconds:',
             '-- every (the cycle), offset, boards (the door opens: the docked phase begins), leaves (the door',
             '-- shuts: it ends), departs (the riders are carried off), disembark (they are put ashore), the',
             '-- seconds into the cycle being (raw game time - offset) mod every; zone is where it boards,',
             '-- crossings the zones the riders cross, line the line it is a run of.',
             'return {',
             '    groups = {']
    for key, label in GROUPS:
        lines.append("        { key = '%s', label = %s }," % (key, lua_string(label)))
    lines.append('    },')
    lines.append('    lines = {')
    seen = set()
    for name in ORDER:
        group, line, origin, destination = RUNS[name]
        if line in seen:
            continue
        seen.add(line)
        lines.append("        { key = '%s', group = '%s', from = %s, to = %s }," % (line, group, lua_string(origin), lua_string(destination)))
    lines.append('    },')
    lines.append('    runs = {')
    for name in ORDER:
        group, line, origin, destination = RUNS[name]
        run = runs[name]
        lines.append("        { name = '%s', group = '%s', line = '%s', from = %s, to = %s," % (name, group, line, lua_string(origin), lua_string(destination)))
        lines.append('            zone = %d, every = %d, offset = %d, boards = %d, leaves = %d, departs = %d, disembark = %d,'
                     % (run['zone'], run['every'], run['offset'], run['boards'], run['leaves'], run['departs'], run['disembark']))
        lines.append('            crossings = { %s } }, -- %s to %s' % (', '.join(str(c) for c in run['crossings']), ids[run['zone']],
                                                                      ', '.join(ids[c] for c in run['crossings'])))
    lines.append('    },')
    lines.append('}')
    output.write_text('\n'.join(lines) + '\n', encoding='utf-8')
    return len(runs), len({run['zone'] for run in runs.values()})


def lua_string(text):
    return "'" + text.replace('\\', '\\\\').replace("'", "\\'") + "'"


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    source.add_arguments(parser)
    parser.add_argument('--output', type=Path, default=ROOT / 'addons/libs/winxi/infopanel/transports.lua')
    args = parser.parse_args()
    found = source.from_arguments(args)
    print(f'Server: {found.describe()}')
    count, zones = build(found.path, args.output)
    print(f'Wrote {args.output}: {count} passenger runs from {zones} zones')
