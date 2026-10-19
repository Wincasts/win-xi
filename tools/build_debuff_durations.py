#!/usr/bin/env python3
"""Write addons/libs/winxi/debuff_durations.lua: how long a status put on something usually lasts,
for winxi.debuffs, which is told that a status took hold but never for how long.

Read from the server's scripts: the live branch of phoenixffxi/Phoenix, fetched from GitHub
(tools/phoenix), or --server's checkout:

  spells     the enfeebling spells' and songs' tables of base durations, and each blue
             magic spell's table of additional effects: spell number -> status -> seconds
  mobskills  a monster's move that puts a status on its target for a number of seconds
             written out in its script: move number -> status -> seconds
  statuses   for each status, the duration seen most often above: what is used where
             the spell or move is not known, or the status came by anything else

The durations are the base ones: what merits, gear, job points and partial resists do to
them is not known, and the server saying a status wore off is what ends it early.

The server's own numbers for the statuses are not in its scripts, so the names it uses
(xi.effect.PARALYSIS) are matched to the statuses' names in tools/status_icons.csv, and the
few that do not match by name are in SPECIAL below. What still does not match is listed.
"""
import argparse
import collections
import csv
import re
from pathlib import Path

from phoenix import source

ROOT = Path(__file__).resolve().parents[1]

# names of the server's that are not the status's own
SPECIAL = {
    'SLEEP_I': 2, 'SLEEP_II': 19, 'CHARM_I': 14, 'CHARM_II': 17, 'CURSE_I': 9, 'CURSE_II': 20,
    'CRIT_HIT_EVASION_DOWN': 298,
}


def key(name):
    return re.sub(r'[^A-Z0-9]+', '_', name.upper()).strip('_')


def status_numbers(csv_path):
    numbers = dict(SPECIAL)
    with open(csv_path, newline='') as handle:
        for row in csv.DictReader(handle):
            numbers.setdefault(key(row['ffxi_name']), int(row['ffxi_id']))
    return numbers


def enum_block(text, name):
    """The NAME = number pairs of a table in an enum file."""
    found = re.search(re.escape(name) + r'\s*=\s*\{(.*?)\n\}', text, re.S)
    return {m.group(1): int(m.group(2)) for m in re.finditer(r'(\w+)\s*=\s*(\d+)', found.group(1))} if found else {}


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    source.add_arguments(parser)
    parser.add_argument('--out', type=Path, default=ROOT / 'addons/libs/winxi/debuff_durations.lua')
    args = parser.parse_args()
    found = source.from_arguments(args)
    print(f'Server: {found.describe()}')
    scripts = found.path / 'scripts'

    numbers = status_numbers(ROOT / 'tools/status_icons.csv')
    spell_ids = enum_block((scripts / 'enum/magic.lua').read_text(), 'xi.magic.spell')
    unmatched = collections.Counter()

    def status(name):
        number = numbers.get(name)
        if number is None and name != 'NONE':
            unmatched[name] += 1
        return number

    spells = collections.defaultdict(dict)
    mobskills = collections.defaultdict(dict)
    seen = collections.defaultdict(collections.Counter)

    def keep(table, number, effect, seconds):
        effect = status(effect)
        if effect is None or number is None or seconds <= 0:
            return
        table[number][effect] = seconds
        seen[effect][seconds] += 1

    # the tables of enfeebling spells and songs: [xi.magic.spell.X] = { xi.effect.Y, ... }, the base
    # duration the sixth column of the one and the fifth of the other
    for file, column in (('enfeebling_spell.lua', 5), ('enfeebling_song.lua', 4)):
        text = (scripts / 'globals/spells' / file).read_text()
        for m in re.finditer(r'\[xi\.magic\.spell\.(\w+)\s*\]\s*=\s*\{([^}]*)\}', text):
            parts = [p.strip() for p in m.group(2).split(',')]
            effect = parts[0].removeprefix('xi.effect.')
            if len(parts) > column and parts[column].isdigit():
                keep(spells, spell_ids.get(m.group(1)), effect, int(parts[column]))

    # blue magic: each spell's file, named for it, with its effects as { xi.effect.X, power, tick, duration }
    for path in sorted((scripts / 'actions/spells/blue').glob('*.lua')):
        number = spell_ids.get(path.stem.upper())
        for m in re.finditer(r'\{\s*xi\.effect\.(\w+)\s*,\s*[^,{}]+,\s*[^,{}]+,\s*(\d+)\s*\}', path.read_text()):
            keep(spells, number, m.group(1), int(m.group(2)))

    # a monster's moves: a file for each name, which several moves can have
    moves = collections.defaultdict(list)
    for m in re.finditer(r"INSERT INTO `mob_skills` VALUES \((\d+),\d+,'([^']*)'", (found.path / 'sql/mob_skills.sql').read_text()):
        moves[m.group(2).lower()].append(int(m.group(1)))
    for path in sorted((scripts / 'actions/mobskills').glob('*.lua')):
        text = path.read_text()
        for m in re.finditer(r'mobStatusEffectMove\(\s*\w+\s*,\s*\w+\s*,\s*xi\.effect\.(\w+)\s*,[^,()]+,[^,()]+,\s*(\d+)\s*\)', text):
            for number in moves.get(path.stem.lower(), []):
                keep(mobskills, number, m.group(1), int(m.group(2)))

    # each status's usual duration: the one seen most, the longer of two seen as often
    statuses = {effect: max(counts.items(), key=lambda item: (item[1], item[0]))[0] for effect, counts in seen.items()}

    def table(name, rows, comment):
        lines = [f'    -- {comment}', f'    {name} = {{']
        for number in sorted(rows):
            inner = ', '.join(f'[{s}] = {d}' for s, d in sorted(rows[number].items()))
            lines.append(f'        [{number}] = {{ {inner} }},')
        lines.append('    },')
        return lines

    out = ['-- Made by tools/build_debuff_durations.py from the server\'s scripts: run it again, do not edit.',
           '-- How long a status usually lasts, in seconds, for winxi.debuffs.', 'return {']
    out += table('spells', spells, 'spell number -> status -> seconds')
    out += table('mobskills', mobskills, 'a monster\'s move -> status -> seconds')
    out += ['    -- status -> its usual seconds, whatever put it there', '    statuses = {']
    out += [f'        [{s}] = {d},' for s, d in sorted(statuses.items())]
    out += ['    },', '};', '']
    args.out.write_text('\n'.join(out))

    print(f'{len(spells)} spells, {len(mobskills)} monster moves and {len(statuses)} statuses, in {args.out}')
    for name, count in unmatched.most_common():
        print(f'  no status called {name} ({count})')


if __name__ == '__main__':
    main()
