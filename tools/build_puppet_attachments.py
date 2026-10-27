#!/usr/bin/env python3
"""Build the automaton's attachments, winxi's attachments set (addons/libs/winxi/data/<server>/attachments;
a set of build_winxi_data), for puppet's Attachment Bonuses, from the server as live loads it.

The attachments and their elements are item_puppet (slot 3) with the module SQL init.txt loads
replayed over it; their modifiers and HP/MP formulas are scripts/globals/automaton.lua's tables,
and then what each module's xi.server.onServerStart on live puts in their place
(xi.automaton.attachmentModifiers['x'] = ..., xi.automaton.repairKit.data / manaTank.data), in
init.txt's order, through phoenix.modules.guard. A module override that changes the attachments in
a way not read here stops the build. Each frame's divisor of a Repair Kit's HP boost and a Mana Tank's
MP boost (xi.automaton.repairKit / manaTank.frameDivisors) is read too, by the frames' numbers
(scripts/enum/automaton.lua).
"""
import io
import re
import sqlite3
from pathlib import Path

from build_item_data import enabled_files, replay
from phoenix import modules, source

ROOT = Path(__file__).resolve().parents[1]
GLOBAL = 'scripts/globals/automaton.lua'
ENTRY = re.compile(r"\['([^']+)'\s*\]\s*=\s*\{(.*?)(?=\n\s*(?:\['|\}|xi\.automaton))", re.S)
MOD = re.compile(r'modifier\s*=\s*xi\.mod\.(\w+),\s*values\s*=\s*\{([^}]+)\},\s*opticFiber\s*=\s*(true|false)')
DIVISORS = re.compile(r'xi\.automaton\.(repairKit|manaTank)\s*=\s*\{\s*frameDivisors\s*=\s*\{([^}]*)\}')
FORMULA = re.compile(r"\['([^']+)'\s*\]\s*=\s*\{\s*id\s*=([^}]+\}[^}]+\})")
# what a module assigns: one attachment's modifiers, or one repair kit's or mana tank's formula
ASSIGNED_MODS = re.compile(r"xi\.automaton\.attachmentModifiers\s*\[\s*'([^']+)'\s*\]\s*=\s*\{")
ASSIGNED_FORMULA = re.compile(r"xi\.automaton\.(?:repairKit|manaTank)\.data\s*\[\s*'([^']+)'\s*\]\s*=\s*(\{)")


def formula_of(body):
    boost = re.search(r'(hpBoost|mpBoost)\s*=\s*(\d+)', body)
    arrays = re.findall(r'(?:regen|refresh)(?:Base|Multiplier)\s*=\s*\{([^}]+)\}', body)
    return (boost.group(1), boost.group(2), arrays) if boost and len(arrays) == 2 else None


def attachments(server):
    """(item id, name, element bits) of every attachment, as live has item_puppet: the name item_basic's,
    which is the one the server keys the attachment by (CItem::getName; item_puppet's can be shortened,
    'ten._spring_v' for tension_spring_v)."""
    db = sqlite3.connect(':memory:')
    variables, tables = {}, ('item_puppet', 'item_basic')
    replay(db, server / 'sql/item_puppet.sql', variables, tables=tables)
    replay(db, server / 'sql/item_basic.sql', variables, tables=tables)
    for path in enabled_files(server, '.sql'):
        replay(db, path, variables, True, tables=tables)
    rows = db.execute('SELECT p.itemid, COALESCE(b.name, p.name), p.element FROM item_puppet p '
                      'LEFT JOIN item_basic b ON b.itemid = p.itemid WHERE p.slot = 3 ORDER BY p.itemid').fetchall()
    db.close()
    return rows


def frame_divisors(path, base):
    """{'HP': {frame: divisor}, 'MP': {...}}: what a Repair Kit's and a Mana Tank's boost is divided by on each frame."""
    enum = (path / 'scripts/enum/automaton.lua').read_text()
    block = re.search(r'xi\.automaton\.frame\s*=\s*\{([^}]*)\}', enum)
    if block is None:
        raise SystemExit('scripts/enum/automaton.lua: no xi.automaton.frame')
    frames = {name: int(value, 0) for name, value in re.findall(r'(\w+)\s*=\s*(0x[0-9A-Fa-f]+|\d+)', block.group(1))}
    found = {}
    for kind, body in DIVISORS.findall(modules.blank_comments(base)):
        rows = re.findall(r'\[\s*xi\.automaton\.frame\.(\w+)\s*\]\s*=\s*(\d+)', body)
        if not rows or any(name not in frames for name, _ in rows):
            raise SystemExit(f'{GLOBAL}: {kind}.frameDivisors is not as it was')
        found['HP' if kind == 'repairKit' else 'MP'] = {frames[name]: int(value) for name, value in rows}
    if set(found) != {'HP', 'MP'}:
        raise SystemExit(f'{GLOBAL}: repairKit and manaTank frameDivisors not both found')
    return found


def build(server):
    path = server.path
    found = modules.cpp_modules_mentioning(path, 'LoadAutomatonStats', 'frameDivisors', 'attachmentModifiers')
    if found:
        raise SystemExit(f'{", ".join(found)} name how attachments are applied: read what they change first')
    base = (path / GLOBAL).read_text()
    divisors = frame_divisors(path, base)
    table = base[base.index('xi.automaton.attachmentModifiers ='):base.index('--', base.index("['volt_gun'"))]
    modifiers = {name: MOD.findall(body) for name, body in ENTRY.findall(table) if MOD.findall(body)}
    formulas = {name: found for name, body in FORMULA.findall(base) if (found := formula_of(body))}

    def handle(override):
        if override.target == '?':
            # a target not written out: only one whose code is of automatons would matter here
            return None if re.search(r'automaton|attachment', override.body, re.I) else 'target not written out; nothing of automatons'
        if override.target.startswith('xi.actions.abilities.pets.'):
            return 'how an attachment or ability works: not its modifiers'
        if override.target != 'xi.server.onServerStart':
            return None  # an xi.automaton function on live: read it before trusting the tables
        done = []
        for _, body in override.cases():
            for m in ASSIGNED_MODS.finditer(body):
                close = modules.closing(body, m.end() - 1)
                modifiers[m.group(1)] = MOD.findall(body[m.end() - 1:close + 1])
                done.append(m.group(1))
            for m in ASSIGNED_FORMULA.finditer(body):
                found = formula_of(body[m.start(2):modules.closing(body, m.start(2)) + 1])
                if found is None:
                    return None
                formulas[m.group(1)] = found
                done.append(m.group(1))
        if done:
            return 'replaces ' + ', '.join(done)
        if re.search(r'xi\.automaton\.(attachmentModifiers|repairKit|manaTank)|frameDivisors', override.body):
            return None
        return 'nothing of attachments'

    modules.guard(path, ('xi.server.onServerStart', 'xi.automaton.', 'xi.actions.abilities.pets.'), handle,
                  out=io.StringIO())

    out = ['-- Generated by tools/build_puppet_attachments.py; do not edit.',
           f'-- {server.repository} {server.branch} {server.commit}',
           'return {', f"    commit = '{server.commit}',", '    attachments = {']
    elements = ['fire', 'ice', 'wind', 'earth', 'thunder', 'water', 'light', 'dark']
    fitted = attachments(path)
    names = {name for _, name, _ in fitted}
    unmatched = sorted(set(modifiers) - names) + sorted(set(formulas) - names)
    if unmatched:
        raise SystemExit(f'{GLOBAL}: modifiers or formulas for {", ".join(unmatched)}, which no attachment is named')
    for item, name, slots in fitted:
        ident = int(item) - 8448
        element = next((elements[i] for i in range(8) if (int(slots) >> (i * 4)) & 15), None)
        if not element or not 0 < ident < 256:
            continue
        display = name.replace('_', ' ').title()
        for roman in ('Ii', 'Iii', 'Iv', 'V'):
            if display.endswith(' ' + roman):
                display = display[:-len(roman)] + roman.upper()
        out.append(f"        [{ident}] = {{ name = '{display}', element = '{element}', key = '{name}', mods = {{")
        for modifier, values, optic in modifiers.get(name, []):
            out.append(f"            {{ key = '{modifier}', values = {{ {values.strip()} }}, optic = {optic} }},")
        out.append('        },')
        if name in formulas:
            kind, boost, arrays = formulas[name]
            out.append(f"        resource = '{'HP' if kind == 'hpBoost' else 'MP'}', boost = {boost}, base = {{ {arrays[0].strip()} }}, scale = {{ {arrays[1].strip()} }},")
        out.append('        },')
    out.append('    },')
    out.append('    -- what a Repair Kit\'s HP boost (HP) and a Mana Tank\'s MP boost (MP) is divided by, by frame')
    out.append('    frames = {')
    for resource in ('HP', 'MP'):
        out.append(f'        {resource} = {{ ' + ', '.join(f'[{frame}] = {value}' for frame, value in sorted(divisors[resource].items())) + ' },')
    out += ['    },', '}']
    return '\n'.join(out) + '\n'


def build_set(server, output, settings=None):
    """The attachments set: build_winxi_data's, into output/index.lua."""
    output.mkdir(parents=True, exist_ok=True)
    (output / 'index.lua').write_text(build(source.read(Path(server))), encoding='utf-8')


if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    source.add_arguments(parser)
    server = source.from_arguments(parser.parse_args())
    target = ROOT / 'addons/libs/winxi/data' / source.KEY / 'attachments'
    build_set(server.path, target)
    print(f'{target / "index.lua"}: {server.describe()}')
