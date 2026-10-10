#!/usr/bin/env python3
"""Makes what chime knows of each area's mobs, for its triggers: mobs/<zone id>.lua, and mobs/skills.lua.

For every area, the mobs in it by the name the game shows, and for each the spells it casts and the
weaponskills it readies, by their numbers: the numbers the game sends when a mob begins one. skills.lua
gives each weaponskill's number a name, for when the game has none for it.

It is read from a checkout of the server (Phoenix, which keeps its mobs in data/zones/<zone>/mobs.yaml),
by way of the reading MobDB's importer already does, so that addon's folder has to be beside this one's:

    python3 generate.py --server /path/to/Phoenix

Run it again when the server's mobs change. Requires PyYAML.
"""
import argparse
import collections
import glob
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
MOBDB = os.path.join(HERE, '..', '..', 'mobdb', 'mobdb')
sys.path.insert(0, MOBDB)
import import_phoenix as mobdb  # noqa: E402


def module_sql(server):
    """The .sql files of the server's modules that are switched on, in the order they are applied."""
    found = []
    for entry in mobdb.read_init(server):
        path = os.path.join(server, 'modules', entry)
        if os.path.isdir(path):
            found += sorted(glob.glob(os.path.join(path, '*.sql')))
        elif path.endswith('.sql') and os.path.exists(path):
            found.append(path)
    return found


def skill_tables(server):
    """skill list id -> the skills in it, and skill id -> its name as the server has it.

    The modules' changes to the lists are applied over the server's own: a list added to, or emptied by name.
    """
    lists = collections.defaultdict(list)
    ids = {}  # list name -> list id
    for path in [os.path.join(server, 'sql', 'mob_skill_lists.sql')] + module_sql(server):
        for line in open(path, encoding='utf-8', errors='replace'):
            if '`mob_skill_lists`' not in line:
                continue
            added = re.match(r"\s*INSERT INTO `mob_skill_lists` VALUES? \('((?:[^'\\]|\\.|'')*)',\s*(\d+),\s*(\d+)\)", line)
            emptied = re.match(r"\s*DELETE FROM `mob_skill_lists` WHERE `skill_list_name` = '([^']*)'", line)
            if added:
                ids[added.group(1)] = int(added.group(2))
                if int(added.group(3)) not in lists[int(added.group(2))]:
                    lists[int(added.group(2))].append(int(added.group(3)))
            elif emptied:
                lists.pop(ids.get(emptied.group(1)), None)
            elif line.lstrip().startswith(('INSERT', 'DELETE', 'UPDATE')):
                print('not understood: %s' % line.strip())
    names = {}
    for line in open(os.path.join(server, 'sql', 'mob_skills.sql'), encoding='utf-8', errors='replace'):
        found = re.match(r"INSERT INTO `mob_skills` VALUES \((\d+),\s*\d+,\s*'([^']*)'", line)
        if found:
            names[int(found.group(1))] = found.group(2)
    return lists, names


def spoken(name):
    """foot_kick -> Foot Kick: only used where the game has no name of its own for a skill."""
    return ' '.join(word.capitalize() for word in name.split('_'))


class Mobs(mobdb.Generator):
    def __init__(self, args):
        super().__init__(args)
        self.skill_lists, self.skill_names = skill_tables(self.server)
        self.used_skills = set()

    def generate_zone(self, zone):
        zone_id = self.zone_ids.get(zone)
        if zone_id is None:
            return False
        document = self.load_zone(zone)
        templates = document.get('templates') or {}
        mobs = {}  # name -> (spells, skills)
        for _, spawn in sorted((document.get('spawns') or {}).items()):
            spawn = spawn or {}
            template = templates.get(spawn.get('template'))
            if template is None or not self.content_enabled(template.get('content')):
                continue
            name, _ = self.client_name(zone_id, spawn.get('template'), template, spawn)
            low, high = (list(spawn.get('level') or [0, 0]) + [0, 0])[:2]
            spells, skills = mobs.setdefault(name, (set(), set()))
            spells.update(self.spell_ids(template, low, high))
            skills.update(self.skill_lists.get(spawn.get('skill_list_id') or template.get('skill_list_id') or 0, []))

        mobs = {name: found for name, found in mobs.items() if found[0] or found[1]}
        if not mobs:
            return False
        with open(os.path.join(self.args.out, '%u.lua' % zone_id), 'w', encoding='utf-8', newline='\n') as out:
            out.write('-- Made by generate.py: %s\nreturn {\n' % zone)
            for name in sorted(mobs):
                spells, skills = mobs[name]
                self.used_skills.update(skills)
                out.write('    [%s] = { spells = { %s }, skills = { %s } },\n' % (
                    mobdb.lua_string(name), ', '.join(map(str, sorted(spells))), ', '.join(map(str, sorted(skills)))))
            out.write('}\n')
        self.stats['zones written'] += 1
        self.stats['mobs written'] += len(mobs)
        return True

    def run(self):
        super().run()
        with open(os.path.join(self.args.out, 'skills.lua'), 'w', encoding='utf-8', newline='\n') as out:
            out.write('-- Made by generate.py: the weaponskills of mobs, by number, as the server names them\nreturn {\n')
            for skill in sorted(self.used_skills):
                if skill in self.skill_names:
                    out.write('    [%d] = %s,\n' % (skill, mobdb.lua_string(spoken(self.skill_names[skill]))))
            out.write('}\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--server', required=True, help='The server checkout: the folder holding data/, sql/ and modules/.')
    args = parser.parse_args()
    # the rest is as MobDB's importer has it when asked for nothing in particular
    args.out, args.names, args.set, args.zone = HERE, os.path.join(MOBDB, 'client_names.json'), [], None
    args.no_module_data, args.elements = False, 'rank'
    Mobs(args).run()


if __name__ == '__main__':
    main()
