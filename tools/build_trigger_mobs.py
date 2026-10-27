#!/usr/bin/env python3
"""Makes mobs.lua, what trigger knows of the game's mobs, for its triggers.

The kinds of mob there are (the server's families: sheep, crabs, quadav), and for each kind what its
mobs can do between them, wherever they are, by the numbers the game sends when a mob does it: the
spells they cast, the weaponskills they ready, and their abilities, which are what a mob uses at once,
with nothing readied first (a job's special among them). And for every area, the mobs in it of each
kind, by the name the game shows, which is how a mob is known for one of a kind when it does something.

By kind and not by mob, so that there is less to choose among, and so that a trigger made for a kind
is for its mobs everywhere. What a kind can do is then more than any one of its mobs does.

What only a kind's notorious monsters do is kept apart from what its other mobs do, with the name,
area and level of the monster that does it, so that a beetle is not said to cast what one notorious
beetle casts. A monster that is in two areas is two monsters where it is of another level there or does
other things, and one where it is the same. What they do is one of the lists, which many share.
What three or more of a kind's notorious monsters do, and its other mobs do not, is written once for
them all and left out of each one's own, so that fifty goblins are not each listed for the dice they
all throw. A notorious monster is one the server marks, or one with a name of its own; the mobs of
Dynamis, which the server's Dynamis module marks one and all, are taken as they were before it.

It is read from the server as live runs it: the live branch fetched by tools/phoenix (or --server's
checkout), by way of the reading MobDB's importer already does (which patches the zones' mobs.yaml with
the modules), the skills and skill lists with the module SQL replayed over them, and the moves a
module's override of a mob's script names on live as well as its own script's (phoenix.modules.guard):

    python3 tools/build_trigger_mobs.py

A mob's weaponskills and abilities are those of its skill list, those its own script names, and, where
its script takes the job special mixin and names none, the special of its main job. Only mobs that do
something are written. Run it again when the server's mobs change. Requires PyYAML.

mobs.lua is written to be small and to cost nothing until it is wanted: what a kind does is two strings
of numbers, and an area is one string, taken apart only when trigger asks about that area.

    kinds = { ['Sheep'] = { spells = '53 59', moves = '260 261 a688',      a marks an ability
                            several = { spells = '', moves = '' },            what three or more of its notorious monsters do
                            notorious = 'Name=area.area,level,spells,moves;' } }   the level 55 or 25-26 or nothing,
    lists = { '144 145', '265 a688' }                                        and each of the last two a list or nothing
    zones = { [area] = 'Sheep:Carnero|Ornery Sheep;Crab:Land Crab;' }
    names = ';260=Lamb Chop;'                                              the server's name for each move
"""
import argparse
import collections
import glob
import os
import re
import sys

import io
import sqlite3
from pathlib import Path

from build_item_data import enabled_files, replay
from phoenix import importer, modules, source

ROOT = Path(__file__).resolve().parents[1]
TARGET = ROOT / 'addons/trigger/mobs.lua'
mobdb = importer.load('trigger_phoenix_import')


SEVERAL = 3  # as many notorious monsters of a kind doing a thing as have it written once for them all


def tables(server):
    """mob_skill_lists and mob_skills as live has them: the server's SQL and the module SQL over it."""
    db = sqlite3.connect(':memory:')
    names = ('mob_skill_lists', 'mob_skills')
    variables = {}
    for name in names:
        replay(db, Path(server) / f'sql/{name}.sql', variables, tables=names)
    for path in enabled_files(server, '.sql'):
        replay(db, path, variables, True, tables=names)
    return db


def skill_lists(db):
    """skill list id -> the skills in it."""
    lists = collections.defaultdict(list)
    for list_id, skill in db.execute('SELECT skill_list_id, mob_skill_id FROM mob_skill_lists ORDER BY rowid'):
        if skill not in lists[list_id]:
            lists[list_id].append(skill)
    return lists


def skills(db):
    """skill id -> (its name as the server has it, whether it is used at once: no time to ready it)."""
    return {skill: (name, prepare == 0) for skill, name, prepare in db.execute('SELECT mob_skill_id, mob_skill_name, mob_prepare_time FROM mob_skills')}


def read(path):
    with open(path, encoding='utf-8', errors='replace') as handle:
        return handle.read()


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
        db = tables(self.server)
        self.skill_lists = skill_lists(db)
        self.skills = skills(db)
        db.close()
        enum = uncommented(read(os.path.join(self.server, 'scripts', 'enum', 'mob_skill.lua')))
        self.skill_ids = {name: int(number) for name, number in re.findall(r'^\s*(\w+)\s*=\s*(\d+)\s*,', enum, flags=re.M)}
        self.special_by_job, self.special_by_species = job_specials(self.server)
        self.script_folders = {mobdb.normalize(os.path.basename(path)): path
                               for path in glob.glob(os.path.join(self.server, 'scripts', 'zones', '*'))}
        self.scripts = {}  # path -> the skills a script names, and whether it takes the job special mixin
        # (zone, mob script) -> the skills a module's overrides of the script on live name
        self.overridden = collections.defaultdict(set)

        def handle(override):
            match = re.match(r'xi\.zones\.([^.]+)\.mobs\.([^.]+)\.', override.target)
            named = {self.skill_ids[skill] for skill in re.findall(r'xi\.mobSkill\.(\w+)', override.body) if skill in self.skill_ids}
            if match is None or '*' in override.target:
                return None if named else 'names no mob skill'
            self.overridden[(mobdb.normalize(match.group(1)), match.group(2))] |= named
            return f'names {len(named)} mob skill(s)' if named else 'names no mob skill'
        modules.guard(self.server, ('xi.zones.',), handle, out=io.StringIO())
        self.zones = {}    # area -> kind -> the names of its mobs there
        self.kinds = {}    # kind -> what its mobs do, wherever they are, and what only each notorious one does
        # species -> the family it is of, which is the kind of mob
        self.families = {}
        ecosystems = modules.load_yaml(self.server, 'ecosystems')['ecosystems']
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
            named = named | self.overridden.get((mobdb.normalize(zone), name), set())
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
        # In Dynamis the server's own module marks every mob notorious, the rank and file with the
        # rest, which they are not for this: there, a mob is taken as the server's data had it
        # before the module, where only the monsters with names are marked.
        unmarked = None
        if zone.startswith('dynamis'):
            unmarked = mobdb.load_yaml(os.path.join(self.server, 'data', 'zones', zone, 'mobs.yaml')).get('templates') or {}
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
            marked = template if unmarked is None else unmarked.get(spawn.get('template')) or {}
            if named or 'notorious' in (marked.get('type') or []):
                # one in two areas is two monsters: they are not of a level, and need not do the same things
                known = known['notorious'].setdefault((name, zone_id), {'spells': set(), 'moves': set(), 'levels': set()})
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
        used = set()
        lists = {}  # a list of spells or of moves, as written -> its place among the lists

        def place(written):
            return str(lists.setdefault(written, len(lists) + 1)) if written else ''

        monsters = 0
        with open(self.args.target, 'w', encoding='utf-8', newline='\n') as out:
            out.write('-- Made by tools/build_trigger_mobs.py, which says how this is laid out\nreturn {\n    kinds = {\n')
            for kind, known in sorted(self.kinds.items()):
                # what several of its notorious monsters do, and its other mobs do not, is written once
                # for them all: it need not be said again under each of them
                several = {}
                for does in ('spells', 'moves'):
                    doers = collections.defaultdict(set)  # a spell or a move -> the monsters that do it, by name
                    for (name, _), mob in known['notorious'].items():
                        for done in mob[does] - known[does]:
                            doers[done].add(name)
                    several[does] = {done for done, names in doers.items() if len(names) >= SEVERAL}
                used |= known['moves'] | several['moves']
                # what only its notorious monsters do, each with its area and level, the lowest first
                # and those of no known level last
                # one that is the same in several areas, in level and in what it does, is written once,
                # with all of its areas
                notorious = collections.defaultdict(list)  # (level it sorts by, name, level, spells, moves) -> its areas
                for (name, zone_id), mob in known['notorious'].items():
                    spells = mob['spells'] - known['spells'] - several['spells']
                    moves = mob['moves'] - known['moves'] - several['moves']
                    if spells or moves:
                        if re.search(r'[=;,]', name):
                            sys.exit('a name that cannot be written: %s' % name)
                        used |= moves
                        low, high = min(mob['levels'], default=0), max(mob['levels'], default=0)
                        level = '' if not low else str(low) if low == high else '%d-%d' % (low, high)
                        notorious[(low or 999, name, level) + tuple(map(place, self.written(spells, moves)))].append(zone_id)
                out.write("        [%s] = { spells = '%s', moves = '%s', several = { spells = '%s', moves = '%s' }, notorious = %s },\n" % (
                    (mobdb.lua_string(kind),) + self.written(known['spells'], known['moves'])
                    + self.written(several['spells'], several['moves'])
                    + (mobdb.lua_string(''.join('%s=%s,%s,%s,%s;' % (
                        (found[1], '.'.join(map(str, sorted(notorious[found])))) + found[2:]) for found in sorted(notorious))),)))
                monsters += len(notorious)
            out.write('    },\n    lists = {\n')
            out.writelines("        '%s',\n" % written for written in lists)
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
        print('%8d  kinds of mob\n%8d  notorious monsters that do what the others of their kind do not\n%8d  lists of what they do\n%8d  bytes: %s' % (
            len(self.kinds), monsters, len(lists), os.path.getsize(self.args.target), self.args.target))


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    source.add_arguments(parser)
    args = parser.parse_args()
    found = source.from_arguments(args)
    print(f'Server: {found.describe()}')
    args.server, args.target = str(found.path), str(TARGET)
    # the rest is as MobDB's importer has it when asked for nothing in particular; it writes nothing itself
    args.out, args.names, args.set, args.zone = str(TARGET.parent), str(importer.CLIENT_NAMES), [], None
    args.no_module_data, args.elements = False, 'rank'
    args.build_dat_names, args.dat_overlay = None, []
    Mobs(args).run()


if __name__ == '__main__':
    main()
