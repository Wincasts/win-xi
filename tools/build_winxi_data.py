#!/usr/bin/env python3
"""Make winxi's game data (addons/libs/winxi/data) from the Phoenix server's live branch on GitHub.

    python3 tools/build_winxi_data.py                 fetch live, make every set, write the manifest
    python3 tools/build_winxi_data.py --only mobs     make one set (repeatable); the others are kept
    python3 tools/build_winxi_data.py --offline       make them from the copy fetched last time
    python3 tools/build_winxi_data.py --server PATH   from another checkout, for a change not pushed yet

Each set is a folder of data/ that winxi.gamedata reads: emptied, then made again, so a zone the
server no longer has is gone from it. data/manifest.lua says what the data was made from (the
repository, branch and commit, and when) and how many files each set has; winxi.gamedata.Manifest()
reads it.

A set is a SETS entry: its folder, what it is, and a function given the fetched server and the
folder to fill. Adding data for winxi is adding one here and a module to read it.

Requires PyYAML and luajit.
"""
import argparse
import io
import re
import shutil
import sys
import tempfile
from pathlib import Path

from phoenix import importer, modules, source
import build_name_placeholders
import build_item_data
import build_action_data
import build_quest_data
import build_rules
import build_trigger_mobs
import build_mark_data
import build_name_cast_times
import build_name_vendors
import build_zone_weather
import build_transports
import build_debuff_durations

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / 'addons/libs/winxi/data'


def build_mobs(server, output, settings):
    """An area's monsters, as mobdb has them: levels, aggro, senses, links, family, drops, spells.

    The importer reads the zone data as the modules patch it, and the module SQL. A monster's own
    script is not read (what it does in a fight is not mobdb's), and so neither is a module's
    override of one: those that change a monster's stats there are listed, not taken."""
    def handle(override):
        if re.search(r'\b(setMod|addMod|setMobMod|addImmunity|setMobLevel|setDropID|addStatusEffect)\s*\(', override.body):
            return 'changes a monster in its script: listed, not in mobdb\'s data'
        return 'nothing mobdb has'
    changed = [o for o, what in modules.guard(server, ('xi.zones.',), handle, out=io.StringIO()) if what.startswith('changes')]
    if changed:
        print(f'  {len(changed)} module overrides change monsters in their scripts, which mobdb does not read')
    importer.generator(server, output, settings).run()


def build_placeholders(server, output, settings):
    """Each notorious monster's placeholders, by entity index."""
    build_name_placeholders.build(server, output, settings)


SETS = {
    'items': ('All item IDs, server stats and script evidence (winxi.items.Get)', build_item_data.build),
    'quests': ('Quest-log identities, NPC/zone references, declared rewards and source evidence (winxi.quests)', build_quest_data.build),
    **{kind: (f'Phoenix {kind}: definitions and source evidence (winxi.{kind})', build_action_data.builder(kind))
       for kind in ('spells', 'abilities', 'weaponskills', 'traits', 'jobs', 'skills', 'elements')},
    'statuses': ('Every status effect the server has: name, flags, element (winxi.statuses)', build_action_data.build_statuses),
    'durations': ('How long each status a spell or monster\'s move puts on lasts (winxi.debuffs)', build_debuff_durations.build),
    'weather': ('Each zone\'s weather table and the rare and common chances (winxi.infopanel.forecast)',
                lambda server, output, settings: build_zone_weather.build(Path(server), output / 'index.lua')),
    'transports': ('The ships\' and airships\' timetable (winxi.infopanel.schedule)',
                   lambda server, output, settings: build_transports.build(Path(server), output / 'index.lua')),
    'casttimes': ('Each monster move\'s ready time (name\'s cast bars)', build_name_cast_times.build),
    'vendors': ('The NPCs whose scripts open a shop, by area (name\'s [vendor])',
                lambda server, output, settings: build_name_vendors.build(Path(server), output / 'index.lua')),
    'marks': ('Each notorious monster: how it comes to be there, its placeholders, spawns and drops (mark)',
              lambda server, output, settings: build_mark_data.Builder(server, output).run()),
    'triggermobs': ('The kinds of mob, what each can do, and each area\'s mobs of each kind (trigger)', build_trigger_mobs.build),
    'rules': ('The server\'s game rules read from its code: Treasure Hunter, haste, swing, resting, bind (winxi.rules)', build_rules.build),
    'mobs': ('An area\'s monsters, as mobdb has them (winxi.mobs.Zone)', build_mobs),
    'placeholders': ('Each notorious monster\'s placeholders (winxi.mobs.Placeholders)', build_placeholders),
}


def lua_string(value):
    return "'" + str(value).replace('\\', '\\\\').replace("'", "\\'") + "'"


def write_datasets():
    """data/datasets.lua: every server there is data for (a folder of data with a manifest), for the
    choice in winxisettings."""
    lines = ['-- Generated by tools/build_winxi_data.py: the servers there is data for (winxi.gamedata.Datasets)', 'return {']
    for manifest in sorted(DATA.glob('*/manifest.lua')):
        text = manifest.read_text(encoding='utf-8')
        name = re.search(r"Name = '((?:[^'\\]|\\.)*)'", text)
        lines.append(f"    {{ Key = {lua_string(manifest.parent.name)}, Name = {lua_string(name.group(1) if name else manifest.parent.name)} }},")
    lines += ['};', '']
    (DATA / 'datasets.lua').write_text('\n'.join(lines), encoding='utf-8', newline='\n')


def write_manifest(found, settings, folder):
    counts = {name: len(list((folder / name).glob('*.lua'))) for name in SETS if (folder / name).is_dir()}
    lines = [
        '-- Generated by tools/build_winxi_data.py: what winxi\'s game data was made from (winxi.gamedata.Manifest)',
        'return {',
        '    Source = {',
        f'        Name = {lua_string(source.NAME)},',
        f'        Key = {lua_string(source.KEY)},',
        f'        Repository = {lua_string(found.repository)},',
        f'        Branch = {lua_string(found.branch)},',
        f'        Commit = {lua_string(found.commit)},',
        f'        Committed = {lua_string(found.committed)},',
        f'        Built = {lua_string(source.now())},',
        '        Settings = { ' + ''.join(f'{lua_string(item)}, ' for item in settings) + '},',
        '    },',
        '    Sets = {',
    ]
    for name in SETS:
        if name in counts:
            lines.append(f'        {name} = {{ Files = {counts[name]}, About = {lua_string(SETS[name][0])} }},')
    lines += ['    },', '};', '']
    (folder / 'manifest.lua').write_text('\n'.join(lines), encoding='utf-8', newline='\n')
    return counts


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    source.add_arguments(parser)
    parser.add_argument('--only', action='append', choices=sorted(SETS), help='Make only this set. Repeatable.')
    parser.add_argument('--set', action='append', default=[], metavar='KEY=VALUE',
                        help='Override a server settings/main.lua value, e.g. --set RESTRICT_CONTENT=1. Repeatable.')
    args = parser.parse_args()

    found = source.from_arguments(args)
    print(f'Server: {found.describe()}')
    folder = DATA / source.KEY  # the server's own folder of data: its key, the profile's
    folder.mkdir(parents=True, exist_ok=True)
    for name in args.only or list(SETS):
        about, build = SETS[name]
        print(f'\n== {name}: {about}')
        # made beside, then put in place: a set that fails half way leaves the one there was
        with tempfile.TemporaryDirectory(dir=source.cache_for(found.branch or 'local').parent) as scratch:
            made = Path(scratch) / name
            made.mkdir()
            build(found.path, made, args.set)
            if not any(made.glob('*.lua')):
                sys.exit(f'{name}: nothing was made; {folder / name} is left as it was')
            target = folder / name
            if target.exists():
                shutil.rmtree(target)
            shutil.move(str(made), str(target))
    counts = write_manifest(found, args.set, folder)
    write_datasets()
    print('\nWritten to ' + str(folder) + ': ' + ', '.join(f'{name} {count} files' for name, count in counts.items()))


if __name__ == '__main__':
    main()
