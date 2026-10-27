#!/usr/bin/env python3
"""Write addons/libs/winxi/debuff_durations.lua: how long a status put on something usually lasts,
for winxi.debuffs, which is told that a status took hold but never for how long.

Read from the server as live runs it: the live branch of phoenixffxi/Phoenix, fetched from GitHub
(tools/phoenix), or --server's checkout; its scripts, and over them the modules init.txt loads
(phoenix.modules), which replace some of what the scripts say:

  spells     the enfeebling spells' and songs' tables of base durations, each blue magic
             spell's table of additional effects, and any spell a module rewrites the casting
             of: spell number -> status -> seconds
  mobskills  a monster's move that puts a status on its target for a number of seconds
             written out in its script: move number -> status -> seconds
  statuses   for each status, the duration seen most often above: what is used where
             the spell or move is not known, or the status came by anything else
  ranges     where the server picks a duration at random (Blind 80 to 300 s on live), the
             least and most of it, spells and mobskills as above; the tables above have the most

The durations are the base ones: what merits, gear, job points and partial resists do to
them is not known, and the server saying a status wore off is what ends it early.

Every module override of what is read here goes by phoenix.modules.guard, and handle() below
says what was done with each: one it cannot account for stops the build.

The server's own numbers for the statuses are not in its scripts, so the names it uses
(xi.effect.PARALYSIS) are matched to the statuses' names in tools/status_icons.csv, and the
few that do not match by name are in SPECIAL below. What still does not match is listed.
"""
import argparse
import collections
import csv
import re
from pathlib import Path

from phoenix import modules, source

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

    spells = collections.defaultdict(dict)     # number -> status -> (least, most)
    mobskills = collections.defaultdict(dict)
    spell_effect = {}                           # an enfeebling spell's number -> the status its table names

    def keep(table, number, effect, span):
        effect = status(effect)
        if effect is None or number is None or span is None or span[1] <= 0:
            return
        table[number][effect] = span

    # the tables of enfeebling spells and songs: [xi.magic.spell.X] = { xi.effect.Y, ... }, the base
    # duration the sixth column of the one and the fifth of the other
    for file, column in (('enfeebling_spell.lua', 5), ('enfeebling_song.lua', 4)):
        text = (scripts / 'globals/spells' / file).read_text()
        for m in re.finditer(r'\[xi\.magic\.spell\.(\w+)\s*\]\s*=\s*\{([^}]*)\}', text):
            parts = [p.strip() for p in m.group(2).split(',')]
            effect = parts[0].removeprefix('xi.effect.')
            number = spell_ids.get(m.group(1))
            if number is not None:
                spell_effect[number] = effect
            if len(parts) > column and parts[column].isdigit():
                keep(spells, number, effect, (int(parts[column]), int(parts[column])))

    # blue magic: each spell's file, named for it, with its effects as { xi.effect.X, power, tick, duration }
    for path in sorted((scripts / 'actions/spells/blue').glob('*.lua')):
        number = spell_ids.get(path.stem.upper())
        for m in re.finditer(r'\{\s*xi\.effect\.(\w+)\s*,\s*[^,{}]+,\s*[^,{}]+,\s*(\d+)\s*\}', path.read_text()):
            keep(spells, number, m.group(1), (int(m.group(2)), int(m.group(2))))

    # a monster's moves: a file for each name, which several moves can have
    moves = collections.defaultdict(list)
    for m in re.finditer(r"INSERT INTO `mob_skills` VALUES \((\d+),\d+,'([^']*)'", (found.path / 'sql/mob_skills.sql').read_text()):
        moves[m.group(2).lower()].append(int(m.group(1)))

    def move_effects(text):
        """Each mobStatusEffectMove(mob, target, xi.effect.X, power, tick, duration) in text, and each
        row { effectId = xi.effect.X, ..., duration = d } of a table for executeMobskillStatusEffect,
        as (X, (least, most)), the span None where the duration is not one that can be read."""
        found = []
        for m in re.finditer(r'mobStatusEffectMove\s*\(', text):
            args = modules.arguments(text, m.end() - 1)
            if len(args) >= 6 and args[2].startswith('xi.effect.'):
                found.append((args[2].removeprefix('xi.effect.'), modules.seconds(args[5], text)))
        if 'executeMobskillStatusEffect' in text:
            for m in re.finditer(r'\{\s*effectId\s*=', text):
                row = modules.fields(text[m.start():modules.closing(text, m.start()) + 1])
                if row.get('effectId', '').startswith('xi.effect.'):
                    span = modules.seconds(row['duration'], text) if 'duration' in row else None
                    found.append((row['effectId'].removeprefix('xi.effect.'), span))
        return found

    for path in sorted((scripts / 'actions/mobskills').glob('*.lua')):
        for effect, span in move_effects(modules.blank_comments(path.read_text())):
            for number in moves.get(path.stem.lower(), []):
                keep(mobskills, number, effect, span)

    # What each module override of the above does on live. A spell or move a module rewrites is
    # what the module says, not its script; a status's own script setting its duration sets it
    # however it came.
    fixed = {}  # status -> seconds every time

    def on_target(text, file_text, depth=0):
        """The statuses text puts on its target, as [(X, span)]: target:addStatusEffect(xi.effect.X,
        { duration = d }) or (xi.effect.X, power, tick, d), target:getStatusEffect(X) then
        :setDuration(ms), and the same inside a local function of the file it calls, the
        function's parameters given the call's arguments. None where one cannot be read."""
        found = []
        for m in re.finditer(r'\btarget\s*:\s*addStatusEffect\s*\(', text):
            args = modules.arguments(text, m.end() - 1)
            effect = args[0].removeprefix('xi.effect.') if args else ''
            if len(args) == 2 and args[1].startswith('{'):
                duration = modules.fields(args[1]).get('duration')
            else:
                duration = args[3] if len(args) >= 4 else None
            span = modules.seconds(duration, text) if duration else None
            if not re.fullmatch(r'\w+', effect) or span is None:
                return None
            found.append((effect, span))
        for m in re.finditer(r'\blocal\s+(\w+)\s*=\s*target\s*:\s*getStatusEffect\s*\(\s*([\w.]+)\s*\)', text):
            for d in re.finditer(r'\b' + m.group(1) + r'\s*:\s*setDuration\s*\(\s*(\d+)\s*\)', text):
                found.append((m.group(2), (int(d.group(1)) // 1000,) * 2))
        if depth == 0:
            for m in re.finditer(r'\b(\w+)\s*\(', text):
                definition = re.search(r'\blocal\s+function\s+' + m.group(1) + r'\s*\(([^)]*)\)', file_text)
                if definition is None:
                    continue
                params = [p.strip() for p in definition.group(1).split(',')]
                inner = modules.function_body(file_text, definition.start())
                args = modules.arguments(text, m.end() - 1)
                for param, arg in zip(params, args):
                    # where it is read, not where a field of that name is set
                    inner = re.sub(r'(?<![\w.])' + param + r'\b(?!\s*=[^=])', arg, inner)
                more = on_target(inner, file_text, 1)
                if more is None:
                    return None
                found += more
        return found

    # overrides read and decided on by hand: what each does to durations, and why it is let be
    decided = {
        'xi.effects.dia.onEffectGain': 'Dia III lasts as long as its caster\'s merits say: not known, its base kept',
        'xi.effects.bio.onEffectGain': 'Bio III lasts as long as its caster\'s merits say: not known, its base kept',
    }

    def handle(override):
        target, parts = override.target, override.target.split('.')
        if target in decided:
            return decided[target]
        body = override.body
        if target == 'xi.spells.enfeebling.calculateDuration':
            # if spellId == xi.magic.spell.X or ... then duration = d, the rest left to super; what
            # follows the chain is Saboteur, merits and gear, which are not known here
            done = []
            chain = re.search(r'\belse\s+return\s+super\(', body)
            for m in re.finditer(r'\b(?:if|elseif)\b(.*?)\bthen\b\s*duration\s*=\s*([^\n]+)', body[:chain.start()] if chain else '', re.S):
                span = modules.seconds(m.group(2))
                names = re.findall(r'xi\.magic\.spell\.(\w+)', m.group(1))
                if span is None or not names:
                    return None
                for name in names:
                    number = spell_ids.get(name)
                    effect = spell_effect.get(number)
                    if effect is None:
                        return None
                    spells[number].pop(status(effect), None)
                    keep(spells, number, effect, span)
                    done.append(f'{name} {span[0]}-{span[1]} s' if span[0] != span[1] else f'{name} {span[0]} s')
            if not done:
                return None
            return 'applied: ' + ', '.join(done)
        if target.startswith('xi.actions.spells.') and parts[-1] == 'onSpellCast':
            number = spell_ids.get(key(parts[-2]))
            text = body
            for name, value in override.row.items():
                text = text.replace('entry.' + name, value)
            put = on_target(text, override.text)
            if put is None:
                return None
            if not put:
                return 'puts no status on its target' if not re.search(r'\btarget\s*:\s*(addStatusEffect|getStatusEffect)', text) else None
            spells.pop(number, None)
            for effect, span in put:
                keep(spells, number, effect.removeprefix('xi.effect.'), span)
            return 'applied: ' + ', '.join(f'{e.removeprefix("xi.effect.")} {s[1]} s' for e, s in put)
        if target.startswith('xi.actions.mobskills.'):
            numbers = moves.get(parts[3].lower(), [])
            put = [effect for _, case in override.cases() for effect in move_effects(case)]
            if any(span is None for _, span in put):
                return None
            if not put:
                # a buff the monster puts on itself or its own is not kept count of
                if 'mobBuffMove' in body and not re.search(r'addStatusEffect|setDuration|executeMobskillStatusEffect', body):
                    return 'a buff on the monster'
                if re.search(r'\bduration\b|addStatusEffect|setDuration', body):
                    return None
                return 'puts no status on its target'
            if not numbers:
                return 'a move no monster has'
            for number in numbers:
                mobskills.pop(number, None)
                for effect, span in put:
                    keep(mobskills, number, effect, span)
            return 'applied: ' + ', '.join(f'{e} {s[0]}-{s[1]} s' if s[0] != s[1] else f'{e} {s[0]} s' for e, s in put)
        if target.startswith('xi.effects.'):
            set_to = re.findall(r'\beffect\s*:\s*setDuration\s*\(\s*(\d+)\s*\)', body)
            if set_to:
                effect = status(key(parts[2]))
                if effect is None or len(set(set_to)) != 1:
                    return None
                fixed[effect] = int(set_to[0]) // 1000
                return f'applied: {fixed[effect]} s however it came'
            return None if re.search(r'duration', body, re.I) else 'leaves its duration'
        # anything else read here: only one that says nothing of durations can be passed over
        return None if re.search(r'\bduration\b|setDuration|addStatusEffect|mobStatusEffectMove', body, re.I) else 'nothing of durations in it'

    print('Modules:')
    modules.guard(found.path, ('xi.spells.enfeebling.', 'xi.actions.spells.', 'xi.actions.mobskills.',
                               'xi.mobskills.', 'xi.effects.'), handle)

    for table in (spells, mobskills):
        for by in table.values():
            for effect in by:
                if effect in fixed:
                    by[effect] = (fixed[effect], fixed[effect])

    # each status's usual duration: the one seen most, the longer of two seen as often
    seen = collections.defaultdict(collections.Counter)
    for table in (spells, mobskills):
        for by in table.values():
            for effect, span in by.items():
                seen[effect][span[1]] += 1
    statuses = {effect: max(counts.items(), key=lambda item: (item[1], item[0]))[0] for effect, counts in seen.items()}
    statuses.update(fixed)

    def table(name, rows, comment):
        lines = [f'    -- {comment}', f'    {name} = {{']
        for number in sorted(rows):
            inner = ', '.join(f'[{s}] = {d[1]}' for s, d in sorted(rows[number].items()))
            lines.append(f'        [{number}] = {{ {inner} }},')
        lines.append('    },')
        return lines

    out = ['-- Made by tools/build_debuff_durations.py from the server\'s scripts and the modules live loads over them:',
           f'-- {found.describe()}. Run it again, do not edit.',
           '-- How long a status usually lasts, in seconds, for winxi.debuffs.', 'return {']
    out += table('spells', spells, 'spell number -> status -> seconds')
    out += table('mobskills', mobskills, 'a monster\'s move -> status -> seconds')
    out += ['    -- status -> its usual seconds, whatever put it there', '    statuses = {']
    out += [f'        [{s}] = {d},' for s, d in sorted(statuses.items())]
    out += ['    },', '    -- where the server picks the duration at random: the least and the most, in the same order as above',
            '    ranges = {']
    for name, rows in (('spells', spells), ('mobskills', mobskills)):
        out += [f'        {name} = {{']
        for number in sorted(rows):
            inner = ', '.join(f'[{s}] = {{ {d[0]}, {d[1]} }}' for s, d in sorted(rows[number].items()) if d[0] != d[1])
            if inner:
                out.append(f'            [{number}] = {{ {inner} }},')
        out += ['        },']
    out += ['    },', '};', '']
    args.out.write_text('\n'.join(out))

    print(f'{len(spells)} spells, {len(mobskills)} monster moves and {len(statuses)} statuses, in {args.out}')
    print(f'Server: {found.describe()}')
    for name, count in unmatched.most_common():
        print(f'  no status called {name} ({count})')


if __name__ == '__main__':
    main()
