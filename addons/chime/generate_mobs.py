#!/usr/bin/env python3
"""Makes mobs.lua, what chime knows of each area's mobs, for its triggers.

For every area, the mobs in it by the name the game shows, and for each what it can do, by the numbers
the game sends when a mob does it: the spells it casts, the weaponskills it readies, and its abilities,
which are what it uses at once, with nothing readied first (a job's special among them).

It is read from a checkout of the server (Phoenix, which keeps its mobs in data/zones/<zone>/mobs.yaml),
by way of the reading MobDB's importer already does, so that addon's folder has to be beside this one:

    python3 generate_mobs.py --server /path/to/Phoenix

A mob's weaponskills and abilities are those of its skill list, those its own script names, and, where
its script takes the job special mixin and names none, the special of its main job. Run it again when
the server's mobs change. Requires PyYAML.

mobs.lua is written to be small and to cost nothing until it is wanted: an area is one string, a mob
in it a name and two numbers, and each number one of the lists of spells or of moves, which most mobs
share with others. Nothing is taken apart until chime asks for an area's mobs.

    zones  = { [area] = 'Name=spells,moves;Name=spells,moves;' }   either number may be missing
    spells = { '53 59 102' }                                       a list of spells
    moves  = { '392 394 a688' }                                    a list of moves: a marks an ability
    names  = ';392=Ultrasonics;'                                   the server's name for each move
"""
import argparse
import collections
import glob
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
MOBDB = os.path.join(HERE, '..', 'mobdb', 'mobdb')
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


def read(path):
    with open(path, encoding='utf-8', errors='replace') as handle:
        return handle.read()


def skill_lists(server):
    """skill list id -> the skills in it. The modules' changes are applied over the server's own lists:
    a list added to, or emptied by name."""
    lists = collections.defaultdict(list)
    ids = {}  # list name -> list id
    for path in [os.path.join(server, 'sql', 'mob_skill_lists.sql')] + module_sql(server):
        for line in read(path).splitlines():
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
    return lists


def skills(server):
    """skill id -> (its name as the server has it, whether it is used at once: no time to ready it)."""
    found = {}
    row = re.compile(r"INSERT INTO `mob_skills` VALUES \((\d+),\s*\d+,\s*'([^']*)',\s*\d+,\s*[\d.]+,\s*[\d.]+,\s*\d+,\s*(\d+)")
    for line in read(os.path.join(server, 'sql', 'mob_skills.sql')).splitlines():
        match = row.match(line)
        if match:
            found[int(match.group(1))] = (match.group(2), int(match.group(3)) == 0)
    return found


def uncommented(lua):
    return re.sub(r'--.*', '', re.sub(r'--\[\[.*?\]\]', '', lua, flags=re.S))


def job_specials(server):
    """What the job special mixin gives a mob that names no special of its own: by main job, and for
    a ranger by species. Returns (job -> skill name, species -> skill name)."""
    text = uncommented(read(os.path.join(server, 'scripts', 'mixins', 'job_special.lua')))
    by_job = {job.lower(): skill for job, skill in re.findall(r'\[xi\.job\.(\w+)\s*\]\s*=\s*xi\.mobSkill\.(\w+)', text)}
    by_species = {species.lower(): skill for species, skill in re.findall(r'\[xi\.mobSpecies\.(\w+)\s*\]\s*=\s*xi\.mobSkill\.(\w+)', text)}
    return by_job, by_species


def spoken(name):
    """foot_kick -> Foot Kick: only used where the game has no name of its own for a move."""
    return ' '.join(word.capitalize() for word in name.split('_'))


class Mobs(mobdb.Generator):
    def __init__(self, args):
        super().__init__(args)
        self.skill_lists = skill_lists(self.server)
        self.skills = skills(self.server)
        enum = uncommented(read(os.path.join(self.server, 'scripts', 'enum', 'mob_skill.lua')))
        self.skill_ids = {name: int(number) for name, number in re.findall(r'^\s*(\w+)\s*=\s*(\d+)\s*,', enum, flags=re.M)}
        self.special_by_job, self.special_by_species = job_specials(self.server)
        self.script_folders = {mobdb.normalize(os.path.basename(path)): path
                               for path in glob.glob(os.path.join(self.server, 'scripts', 'zones', '*'))}
        self.scripts = {}  # path -> the skills a script names, and whether it takes the job special mixin
        self.zones = {}    # area -> name -> (spells, moves)

    def script(self, zone, name):
        folder = self.script_folders.get(mobdb.normalize(zone))
        path = folder and os.path.join(folder, 'mobs', '%s.lua' % name)
        if path not in self.scripts:
            named, special = set(), False
            if path and os.path.exists(path):
                text = uncommented(read(path))
                named = {self.skill_ids[skill] for skill in re.findall(r'xi\.mobSkill\.(\w+)', text) if skill in self.skill_ids}
                special = 'job_special' in text
            self.scripts[path] = (named, special)
        return self.scripts[path]

    def moves(self, zone, template_name, template, spawn):
        found = set(self.skill_lists.get(spawn.get('skill_list_id') or template.get('skill_list_id') or 0, []))
        named, special = self.script(zone, spawn.get('script') or template_name)
        found |= named
        if special and not named:
            species = str(template.get('species'))
            attributes = mobdb.overlay(self.species.get(species, {}), template.get('attributes') or {})
            jobs = mobdb.overlay(attributes, spawn.get('attributes') or {}).get('jobs') or []
            job = str(jobs[0]).lower() if jobs else None
            skill = self.special_by_species.get(species.lower()) if job == 'rng' else self.special_by_job.get(job)
            if skill in self.skill_ids:
                found.add(self.skill_ids[skill])
        return {skill for skill in found if skill in self.skills}

    def generate_zone(self, zone):
        zone_id = self.zone_ids.get(zone)
        if zone_id is None:
            return False
        document = self.load_zone(zone)
        templates = document.get('templates') or {}
        mobs = {}
        for _, spawn in sorted((document.get('spawns') or {}).items()):
            spawn = spawn or {}
            template = templates.get(spawn.get('template'))
            if template is None or not self.content_enabled(template.get('content')):
                continue
            name, _ = self.client_name(zone_id, spawn.get('template'), template, spawn)
            low, high = (list(spawn.get('level') or [0, 0]) + [0, 0])[:2]
            spells, moves = mobs.setdefault(name, (set(), set()))
            spells.update(self.spell_ids(template, low, high))
            moves.update(self.moves(zone, spawn.get('template'), template, spawn))
        mobs = {name: found for name, found in mobs.items() if found[0] or found[1]}
        if mobs:
            self.zones[zone_id] = mobs
            self.stats['zones written'] += 1
            self.stats['mobs written'] += len(mobs)
        return bool(mobs)

    def run(self):
        super().run()
        lists = {'spells': {}, 'moves': {}}  # what a list holds, as written -> its place among the lists

        def place(kind, written):
            if not written:
                return ''
            return str(lists[kind].setdefault(written, len(lists[kind]) + 1))

        used, areas = set(), []
        for zone_id in sorted(self.zones):
            entries = []
            for name, (spells, moves) in sorted(self.zones[zone_id].items()):
                if re.search(r'[=;]', name):
                    sys.exit('a name that cannot be written: %s' % name)
                used |= moves
                entries.append('%s=%s,%s;' % (
                    name, place('spells', ' '.join(map(str, sorted(spells)))),
                    place('moves', ' '.join(('a%d' if self.skills[move][1] else '%d') % move for move in sorted(moves)))))
            areas.append('        [%d] = %s,\n' % (zone_id, mobdb.lua_string(''.join(entries))))

        with open(self.args.target, 'w', encoding='utf-8', newline='\n') as out:
            out.write('-- Made by generate_mobs.py, which says how this is laid out\nreturn {\n    zones = {\n')
            out.writelines(areas)
            for kind in ('spells', 'moves'):
                out.write('    },\n    %s = {\n' % kind)
                out.writelines("        '%s',\n" % written for written in lists[kind])
            out.write('    },\n    names = %s,\n}\n' % mobdb.lua_string(
                ';' + ''.join('%d=%s;' % (move, spoken(self.skills[move][0])) for move in sorted(used))))
        print('%8d  lists of spells\n%8d  lists of moves\n%8d  bytes: %s' % (
            len(lists['spells']), len(lists['moves']), os.path.getsize(self.args.target), self.args.target))


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--server', required=True, help='The server checkout: the folder holding data/, sql/ and modules/.')
    args = parser.parse_args()
    args.target = os.path.join(HERE, 'mobs.lua')
    # the rest is as MobDB's importer has it when asked for nothing in particular; it writes nothing itself
    args.out, args.names, args.set, args.zone = HERE, os.path.join(MOBDB, 'client_names.json'), [], None
    args.no_module_data, args.elements = False, 'rank'
    Mobs(args).run()


if __name__ == '__main__':
    main()
