#!/usr/bin/env python3
"""Makes mobs.lua, what twister knows of the game's mobs, for its triggers.

The kinds of mob there are (the server's families: sheep, crabs, quadav), and for each kind what its
mobs can do between them, wherever they are, by the numbers the game sends when a mob does it: the
spells they cast, the weaponskills they ready, and their abilities, which are what a mob uses at once,
with nothing readied first (a job's special among them). And for every area, the mobs in it of each
kind, by the name the game shows, which is how a mob is known for one of a kind when it does something.

By kind and not by mob, so that there is less to choose among, and so that a trigger made for a kind
is for its mobs everywhere. What a kind can do is then more than any one of its mobs does.

What only a kind's notorious monsters do is kept apart from what its other mobs do, under the name and
level of the monster that does it, so that a beetle is not said to cast what one notorious beetle
casts. Notorious monsters that do the same things are written together.

It is read from a checkout of the server (Phoenix, which keeps its mobs in data/zones/<zone>/mobs.yaml),
by way of the reading MobDB's importer already does, so that addon's folder has to be beside this one:

    python3 generate_mobs.py --server /path/to/Phoenix

A mob's weaponskills and abilities are those of its skill list, those its own script names, and, where
its script takes the job special mixin and names none, the special of its main job. Only mobs that do
something are written. Run it again when the server's mobs change. Requires PyYAML.

mobs.lua is written to be small and to cost nothing until it is wanted: what a kind does is two strings
of numbers, and an area is one string, taken apart only when twister asks about that area.

    kinds = { ['Sheep'] = { spells = '53 59', moves = '260 261 a688',      a marks an ability
                            notorious = { { who = 'Name (Lv 55)', spells = '', moves = '' } } } }
    zones = { [area] = 'Sheep:Carnero|Ornery Sheep;Crab:Land Crab;' }
    names = ';260=Lamb Chop;'                                              the server's name for each move
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
        self.zones = {}    # area -> kind -> the names of its mobs there
        self.kinds = {}    # kind -> what its mobs do, wherever they are, and what only each notorious one does
        # species -> the family it is of, which is the kind of mob
        self.families = {}
        ecosystems = mobdb.load_yaml(os.path.join(self.server, 'data', 'ecosystems.yaml'))['ecosystems']
        for ecosystem in ecosystems.values():
            for family, found in (ecosystem.get('families') or {}).items():
                for species in found.get('species') or {}:
                    self.families[str(species)] = str(family)

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
        here = {}  # kind -> the names of its mobs in this area
        for _, spawn in sorted((document.get('spawns') or {}).items()):
            spawn = spawn or {}
            template = templates.get(spawn.get('template'))
            if template is None or not self.content_enabled(template.get('content')):
                continue
            name, _ = self.client_name(zone_id, spawn.get('template'), template, spawn)
            low, high = (list(spawn.get('level') or [0, 0]) + [0, 0])[:2]
            spells = set(self.spell_ids(template, low, high))
            moves = self.moves(zone, spawn.get('template'), template, spawn)
            if not spells and not moves:
                continue
            species = str(template.get('species'))
            kind = spoken(self.families.get(species, species))
            here.setdefault(kind, set()).add(name)

            # a notorious monster: the server says so, or the mob has a name of its own (the game
            # writes it with no 'the'), which takes in those the server has not marked
            attributes = mobdb.overlay(self.species.get(species, {}), template.get('attributes') or {})
            attributes = mobdb.overlay(attributes, spawn.get('attributes') or {})
            named = int((attributes.get('render') or {}).get('name_prefix') or 0) & 32
            known = self.kinds.setdefault(kind, {'spells': set(), 'moves': set(), 'notorious': {}})
            if named or 'notorious' in (template.get('type') or []):
                known = known['notorious'].setdefault(name, {'spells': set(), 'moves': set(), 'levels': set()})
                known['levels'].update(level for level in (low, high) if level)
            known['spells'].update(spells)
            known['moves'].update(moves)
        if here:
            self.zones[zone_id] = here
            self.stats['zones written'] += 1
            self.stats['mobs written'] += sum(len(names) for names in here.values())
        return bool(here)

    def written(self, spells, moves):
        """Lists of spells and of moves as mobs.lua has them."""
        return (' '.join(map(str, sorted(spells))),
                ' '.join(('a%d' if self.skills[move][1] else '%d') % move for move in sorted(moves)))

    def run(self):
        super().run()
        used, sections = set(), 0
        with open(self.args.target, 'w', encoding='utf-8', newline='\n') as out:
            out.write('-- Made by generate_mobs.py, which says how this is laid out\nreturn {\n    kinds = {\n')
            for kind, known in sorted(self.kinds.items()):
                used |= known['moves']
                out.write("        [%s] = { spells = '%s', moves = '%s'" % ((mobdb.lua_string(kind),) + self.written(known['spells'], known['moves'])))

                # what only its notorious monsters do: those that do the same things are written together
                alike = collections.defaultdict(list)  # (spells, moves) -> [(lowest level, who)]
                for name, mob in known['notorious'].items():
                    spells, moves = mob['spells'] - known['spells'], mob['moves'] - known['moves']
                    if spells or moves:
                        used |= moves
                        low, high = min(mob['levels'], default=0), max(mob['levels'], default=0)
                        level = ' (Lv %d)' % low if low == high else ' (Lv %d-%d)' % (low, high)
                        alike[self.written(spells, moves)].append((low, name + (level if low else '')))
                if alike:
                    out.write(', notorious = {\n')
                    for does, mobs in sorted(alike.items(), key=lambda found: sorted(found[1])[0]):
                        mobs = [who for _, who in sorted(mobs)]
                        who = ', '.join(mobs[:3]) + (' +%d more' % (len(mobs) - 3) if len(mobs) > 3 else '')
                        out.write("            { who = %s, spells = '%s', moves = '%s' },\n" % ((mobdb.lua_string(who),) + does))
                        sections += 1
                    out.write('        }')
                out.write(' },\n')
            out.write('    },\n    zones = {\n')
            for zone_id in sorted(self.zones):
                entries = []
                for kind, names in sorted(self.zones[zone_id].items()):
                    if re.search(r'[;:|]', kind) or any(re.search(r'[;|]', name) for name in names):
                        sys.exit('a name that cannot be written: %s, or one of %s' % (kind, sorted(names)))
                    entries.append('%s:%s;' % (kind, '|'.join(sorted(names))))
                out.write('        [%d] = %s,\n' % (zone_id, mobdb.lua_string(''.join(entries))))
            out.write('    },\n    names = %s,\n}\n' % mobdb.lua_string(
                ';' + ''.join('%d=%s;' % (move, spoken(self.skills[move][0])) for move in sorted(used))))
        print('%8d  kinds of mob\n%8d  lists of what only notorious monsters do\n%8d  bytes: %s' % (
            len(self.kinds), sections, os.path.getsize(self.args.target), self.args.target))


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
