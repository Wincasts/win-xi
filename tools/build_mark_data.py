#!/usr/bin/env python3
"""Export what the server knows of each notorious monster for the mark addon.

For every notorious monster of every zone: how it comes to be there (a lottery on
placeholders, a timed respawn, a trade to a ???, or a script the data says no more
of), its placeholders and where they stand, its own spawn points, and what it drops
with the chance of each roll. Read from the server's zone data and scripts; names
are resolved by the MobDB importer (forks/addons/mobdb/mobdb/import_phoenix.py).

The mob scripts are run in LuaJIT against stand-ins for the server's globals (as
tools/build_name_placeholders.py runs them), for their placeholder lists, spawn
points and respawn windows. What the placeholders' scripts and the modules say of
the lottery is read off the text: the module files live loads with a module on in them
(phoenix.modules.files_on_live), and every module override of a zone's script goes by
phoenix.modules.guard. The zone data is as the modules patch it (the importer's load_zone and
phoenix.modules.load_yaml).

Requires PyYAML and luajit. Reads the live branch of phoenixffxi/Phoenix, fetched from GitHub
(tools/phoenix).
"""
import argparse
import io
import re
import subprocess
import tempfile
from pathlib import Path
from types import SimpleNamespace

from phoenix import importer, lotteries, modules, source

ROOT = Path(__file__).resolve().parents[1]

# Prints, for a zone's mob scripts:
#   ID <constant> <mob id>                      every mob constant of the zone's IDs.lua
#   PH <placeholder id> <NM id>                 every phList entry
#   SP <script> <mob id or 0> <x> <y> <z>       every spawnPoints entry (0: for whichever mob has the script)
#   RT <script> <least> <most>                  the respawn times its onMobDespawn sets, over many runs
#   PA <script> <x,y,z;x,y,z;...>               each route a handler of it walks the monster over (pathThrough)
READER = r'''
local zoneDir, idsFile = arg[1], arg[2]
local ids = dofile(idsFile)
-- Anything the scripts ask of the server that is not an ID: indexable, callable, inert.
local inert = {}
local function stand() return setmetatable({}, inert) end
inert.__index = function(t, k) local v = stand(); rawset(t, k, v); return v end
inert.__call = stand
for _, op in ipairs({ '__add', '__sub', '__mul', '__div', '__mod', '__unm', '__pow' }) do inert[op] = function() return 0 end end
inert.__concat = function() return '' end
inert.__lt = function() return false end
inert.__le = function() return false end
zones = {}
require = stand
math.randomInt = function(low, high)
    if type(low) ~= 'number' then return 0 end
    if type(high) ~= 'number' then return math.random(0, low) end
    return math.random(low, high)
end
GetFirstID = function(name) return ids[name] and ids[name][1] or nil end
GetTableOfIDs = function(name, count)
    local all, out = ids[name] or {}, {}
    for i = 1, count or #all do out[i] = all[i] or (all[1] and all[1] + i - 1) end
    return out
end
setmetatable(_G, { __index = function(t, k) local v = stand(); rawset(t, k, v); return v end })
local ok, problem = pcall(dofile, zoneDir .. '/IDs.lua')
if not ok then io.stderr:write('IDs: ' .. tostring(problem) .. '\n') end
for _, zone in pairs(zones) do
    local mobs = type(zone) == 'table' and rawget(zone, 'mob')
    if type(mobs) == 'table' and getmetatable(mobs) ~= inert then
        for name, id in pairs(mobs) do
            if type(name) == 'string' and type(id) == 'number' then print(('ID\t%s\t%d'):format(name, id)) end
            -- monsters of one name and several ids: NAME[1], NAME[2]
            if type(name) == 'string' and type(id) == 'table' and getmetatable(id) ~= inert then
                for place, one in ipairs(id) do
                    if type(one) == 'number' then print(('ID\t%s[%d]\t%d'):format(name, place, one)) end
                end
            end
        end
    end
end

local function point(script, id, p)
    if type(p) == 'table' and type(rawget(p, 'x')) == 'number' and type(rawget(p, 'y')) == 'number' and type(rawget(p, 'z')) == 'number' then
        print(('SP\t%s\t%d\t%.3f\t%.3f\t%.3f'):format(script, id, p.x, p.y, p.z))
    end
end

for file in io.lines() do
    if file == '' then break end
    local script = file:match('([^/]+)%.lua$')
    local loaded, entity = pcall(dofile, file)
    if loaded and type(entity) == 'table' then
        local list = rawget(entity, 'phList')
        if type(list) == 'table' and getmetatable(list) ~= inert then
            for ph, nms in pairs(list) do
                -- one placeholder can be several monsters': the value is then a list of them
                for _, nm in ipairs(type(nms) == 'table' and nms or { nms }) do
                    if type(ph) == 'number' and type(nm) == 'number' then print(('PH\t%d\t%d'):format(ph, nm)) end
                end
            end
        end
        local points = rawget(entity, 'spawnPoints')
        if type(points) == 'table' and getmetatable(points) ~= inert then
            for key, value in pairs(points) do
                if type(key) == 'number' and key > 0xFFFF and type(value) == 'table' then
                    -- monsters of one name and several ids: a list for each
                    for _, p in ipairs(value) do point(script, key, p) end
                else
                    point(script, 0, value)
                end
            end
        end
        -- the routes it is walked over: what its handlers hand to pathThrough, as points or as bare numbers
        local routes, written = {}, {}
        local walker = stand()
        rawset(walker, 'pathThrough', function(_, points)
            local found = {}
            if type(points) == 'table' and getmetatable(points) ~= inert then
                if type(rawget(points, 1)) == 'number' then
                    for i = 1, #points - 2, 3 do
                        if type(points[i]) == 'number' and type(points[i + 1]) == 'number' and type(points[i + 2]) == 'number' then
                            found[#found + 1] = ('%.1f,%.1f,%.1f'):format(points[i], points[i + 1], points[i + 2])
                        end
                    end
                else
                    for _, p in ipairs(points) do
                        if type(p) == 'table' and type(rawget(p, 'x')) == 'number' and type(rawget(p, 'y')) == 'number' and type(rawget(p, 'z')) == 'number' then
                            found[#found + 1] = ('%.1f,%.1f,%.1f'):format(p.x, p.y, p.z)
                        end
                    end
                end
            end
            local line = table.concat(found, ';')
            if #found > 1 and not written[line] then written[line] = true; routes[#routes + 1] = line end
        end)
        for _, handler in ipairs({ 'onMobInitialize', 'onMobSpawn', 'onMobRoam', 'onPath' }) do
            local run = rawget(entity, handler)
            if type(run) == 'function' then
                for _ = 1, 20 do
                    debug.sethook(function() error('too long') end, '', 200000)
                    pcall(run, walker)
                    debug.sethook()
                end
            end
        end
        for _, line in ipairs(routes) do print(('PA\t%s\t%s'):format(script, line)) end
        local despawn = rawget(entity, 'onMobDespawn')
        if type(despawn) == 'function' then
            local least, most
            local mob = stand()
            rawset(mob, 'setRespawnTime', function(_, seconds)
                if type(seconds) == 'number' and seconds > 0 then
                    least = math.min(least or seconds, seconds)
                    most = math.max(most or seconds, seconds)
                end
            end)
            for _ = 1, 400 do
                -- a script that loops for ever on a stand-in is given up on
                debug.sethook(function() error('too long') end, '', 200000)
                pcall(despawn, mob)
                debug.sethook()
            end
            if least then print(('RT\t%s\t%d\t%d'):format(script, least, most)) end
        end
    else
        io.stderr:write('unreadable: ' .. file .. '\n')
    end
end
'''

DROP_RATES = {}  # the server's names for a chance, in tenths of a percent: filled from data/enums/drop_rate.yaml
SPAWN_CONDITIONS = ('at_night', 'at_evening', 'weather', 'fog', 'moonphase')


def squash(name):
    return re.sub(r'[^a-z0-9]', '', str(name).lower())


def split_args(text):
    """The arguments of a call, given the text after its opening bracket: split at the commas of its own level."""
    args, depth, current = [], 0, ''
    for char in text:
        if char in '({[':
            depth += 1
        elif char in ')}]':
            if depth == 0:
                break
            depth -= 1
        elif char == ',' and depth == 0:
            args.append(current.strip())
            current = ''
            continue
        current += char
    args.append(current.strip())
    return args


def calls(text, name):
    """The argument lists of every call of name in text."""
    return [split_args(text[match.end():]) for match in re.finditer(re.escape(name) + r'\s*\(', text)]


def seconds(text):
    """A wait as the scripts write one: a number, utils.hours(n), utils.minutes(n), or math.random(least, most) of those."""
    text = text.strip()
    match = re.fullmatch(r'math\.random(?:Int)?\((.+),(.+)\)', text)
    if match:
        least, most = seconds(match.group(1)), seconds(match.group(2))
        return (least[0], most[1]) if least and most else None
    match = re.fullmatch(r'utils\.(hours|minutes)\(([\d.]+)\)', text)
    if match:
        whole = int(float(match.group(2)) * (3600 if match.group(1) == 'hours' else 60))
        return whole, whole
    try:
        return int(float(text)), int(float(text))
    except ValueError:
        return None


def simplify(points, tolerance):
    """An outline with the points left out that lie within tolerance of the line between their neighbours (Douglas-Peucker)."""
    if len(points) < 4:
        return points

    def reduce(run):
        (ax, ay), (bx, by) = run[0], run[-1]
        length = ((bx - ax) ** 2 + (by - ay) ** 2) ** 0.5
        worst, at = 0.0, 0
        for place in range(1, len(run) - 1):
            px, py = run[place]
            off = (abs((bx - ax) * (ay - py) - (ax - px) * (by - ay)) / length) if length else ((px - ax) ** 2 + (py - ay) ** 2) ** 0.5
            if off > worst:
                worst, at = off, place
        if worst <= tolerance:
            return [run[0], run[-1]]
        return reduce(run[:at + 1])[:-1] + reduce(run[at:])

    # a ring: cut at the point furthest from the first, and reduce each half
    far = max(range(len(points)), key=lambda place: (points[place][0] - points[0][0]) ** 2 + (points[place][1] - points[0][1]) ** 2)
    return reduce(points[:far + 1])[:-1] + reduce(points[far:] + [points[0]])[:-1]


def strip_comments(text):
    return re.sub(r'--[^\n]*', '', text)


def point_tables(text):
    """local name = { { x = , y = , z = }, ... } tables of a script, by name."""
    found = {}
    for match in re.finditer(r'local\s+(\w+)\s*=\s*\{((?:\s*\{\s*x\s*=[^{}]*\}\s*,?)+)\s*\}', text):
        points = [tuple(round(float(n), 3) for n in p) for p in re.findall(
            r'x\s*=\s*(-?[\d.]+)\s*,\s*y\s*=\s*(-?[\d.]+)\s*,\s*z\s*=\s*(-?[\d.]+)', match.group(2))]
        if points:
            found[match.group(1)] = points
    return found


def lua(value):
    if isinstance(value, bool):
        return 'true' if value else 'false'
    if isinstance(value, int):
        return str(value)
    if isinstance(value, float):
        return ('%.1f' % value).rstrip('0').rstrip('.') if value != int(value) else str(int(value))
    if isinstance(value, str):
        return "'" + value.replace('\\', '\\\\').replace("'", "\\'") + "'"
    if isinstance(value, (list, tuple)):
        return '{ ' + ', '.join(lua(item) for item in value) + ' }' if value else '{}'
    if isinstance(value, dict):
        return '{ ' + ', '.join(f'{key} = {lua(item)}' for key, item in value.items()) + ' }' if value else '{}'
    raise TypeError(type(value))


class Builder:
    def __init__(self, server, output):
        self.server, self.output = Path(server), Path(output)
        self.slot_lottery = {}  # (zone, NM id) -> { chance, cooldown }, from the zones' slots as they are read
        self.importer = importer.load('mark_phoenix_import')
        self.generator = importer.generator(server, output, module=self.importer)
        DROP_RATES.update(self.importer.load_yaml(str(self.server / 'data/enums/drop_rate.yaml'))['values'])
        self.item_enum = dict((name, int(number)) for name, number in re.findall(
            r'^\s*(\w+)\s*=\s*(\d+)\s*,', (self.server / 'scripts/enum/item.lua').read_text(errors='replace'), re.M))
        self.scripts = {squash(path.name): path for path in (self.server / 'scripts/zones').iterdir() if path.is_dir()}
        self.zones = {}      # zone folder (data) -> what was read of it
        self.by_squash = {}  # squashed zone name -> zone folder (data)
        self.notes = []

    # -- the zone's own data ---------------------------------------------------------------------

    def read_zone(self, zone, scratch):
        generator, importer = self.generator, self.importer
        zone_id = generator.zone_ids.get(zone)
        if zone_id is None:
            return
        document = generator.load_zone(zone)
        templates = document.get('templates') or {}
        info = SimpleNamespace(zone=zone, id=zone_id, folder=self.scripts.get(squash(zone)), templates=templates,
                               spawns={}, shown={}, by_script={}, script_of={}, regions={}, npcs={},
                               constants={}, ph={}, points={}, respawns={}, paths={})
        for mob_id, spawn in sorted((document.get('spawns') or {}).items()):
            spawn = spawn or {}
            template = templates.get(spawn.get('template'))
            if not template:
                continue
            mob_id = int(mob_id)
            script = spawn.get('script') or template.get('script') or spawn.get('template')
            info.by_script.setdefault(script, []).append(mob_id)
            info.script_of[mob_id] = script
            if generator.content_enabled(template.get('content')):
                info.spawns[mob_id] = spawn
                info.shown[mob_id] = generator.client_name(zone_id, spawn.get('template'), template, spawn, int(mob_id) & 0xFFF)[0]
        regions = modules.load_yaml(self.server, f'zones/{zone}/regions')
        if regions is not None:
            for name, region in ((regions or {}).get('regions') or {}).items():
                poly = (region or {}).get('poly') or []
                if poly:
                    xs, ys, zs = [p[0] for p in poly], [p[1] for p in poly], [p[2] for p in poly]
                    # the middle of what the region covers, and how far it reaches from there
                    # to within three yalms, or less for a region too narrow to stand it
                    ring = [(p[0], p[2]) for p in poly]
                    outline = simplify(ring, min(3.0, min(max(xs) - min(xs), max(zs) - min(zs)) / 8))
                    if len(outline) < 3:
                        outline = ring
                    info.regions[name] = {'at': [round((min(xs) + max(xs)) / 2, 1), round(sum(ys) / len(ys), 1), round((min(zs) + max(zs)) / 2, 1)],
                                          'reach': round(max(max(xs) - min(xs), max(zs) - min(zs)) / 2),
                                          'poly': [round(n) for point in outline for n in point]}
        npcs = modules.load_yaml(self.server, f'zones/{zone}/npcs')
        if npcs is not None:
            for npc_id, npc in sorted(((npcs or {}).get('npcs') or {}).items()):
                name = (npc or {}).get('script')
                if name:
                    info.by_script.setdefault(name, []).append(int(npc_id))
                    info.npcs.setdefault(name, npc)
        self.zones[zone] = info
        self.by_squash[squash(zone)] = zone
        # the lotteries the zone's data sets out: its slots, each NM with its placeholders, chance and cooldown
        for nm, placeholders, rule in lotteries.from_slots(document):
            if nm not in info.shown:
                continue
            info.ph.setdefault(nm, set()).update(ph for ph in placeholders if ph in info.shown and ph != nm)
            entry = {'chance': float(rule['chance']), 'cooldown': int(rule['cooldown'] or 0)}
            self.slot_lottery[(zone, nm)] = entry
        if info.folder is None:
            return

        files = sorted(str(file) for file in (info.folder / 'mobs').glob('*.lua')
                       if re.search(r'phList|spawnPoints|setRespawnTime|pathThrough', file.read_text(errors='replace')))
        ids = Path(scratch) / 'ids.lua'
        ids.write_text('return {\n' + ''.join(
            f'    [{importer.lua_string(name)}] = {{ {", ".join(map(str, found))} }},\n' for name, found in info.by_script.items()) + '}\n')
        ran = subprocess.run(['luajit', '-joff', str(Path(scratch) / 'reader.lua'), str(info.folder), str(ids)],
                             input='\n'.join(files) + '\n', capture_output=True, text=True, check=True)
        self.notes += [f'{zone}: {line}' for line in ran.stderr.splitlines()]
        for line in ran.stdout.splitlines():
            kind, *rest = line.split('\t')
            if kind == 'ID':
                info.constants[rest[0]] = int(rest[1])
            elif kind == 'PH':
                ph, nm = int(rest[0]), int(rest[1])
                if ph in info.shown and nm in info.shown and ph != nm:
                    info.ph.setdefault(nm, set()).add(ph)
            elif kind == 'SP':
                point = tuple(float(n) for n in rest[2:5])
                targets = [int(rest[1])] if int(rest[1]) else info.by_script.get(rest[0], [])
                for mob_id in targets:
                    info.points.setdefault(mob_id, []).append(point)
            elif kind == 'PA':
                route = [[float(n) for n in point.split(',')] for point in rest[1].split(';')]
                for mob_id in info.by_script.get(rest[0], []):
                    info.paths.setdefault(mob_id, []).append(route)
            elif kind == 'RT':
                for mob_id in info.by_script.get(rest[0], []):
                    least, most = int(rest[1]), int(rest[2])
                    if most - least > 600:
                        # a window seen by sampling: its ends are taken to the five minutes they fall short of
                        least, most = least // 300 * 300, -(-most // 300) * 300
                    info.respawns[mob_id] = (least, most)

    # -- what the scripts' text says -------------------------------------------------------------

    def module_files(self):
        """The Lua files of the modules the server loads, in the order it loads them, but those whose
        every module is off on live."""
        return modules.files_on_live(self.server)

    def resolve_mob(self, expression, home, aliases):
        """A mob id from 'ID.mob.NAME', 'zones[xi.zone.ZONE].mob.NAME' or '<alias>.mob.NAME', with an offset if there is one."""
        match = re.match(r'(?:zones\[xi\.zone\.(\w+)\]|(\w+))\.mob\.(\w+(?:\[\d+\])?)\s*(?:([+-])\s*(\d+))?$', expression.strip())
        if not match:
            return None, None
        zone_name = match.group(1) or aliases.get(match.group(2))
        zone = self.by_squash.get(squash(zone_name)) if zone_name else home
        info = self.zones.get(zone)
        # a name that is several monsters' stands for the first of them
        mob_id = info and (info.constants.get(match.group(3)) or info.constants.get(match.group(3) + '[1]'))
        if mob_id is None:
            return None, None
        if match.group(4):
            mob_id += int(match.group(5)) * (1 if match.group(4) == '+' else -1)
        return info, mob_id

    def read_lotteries(self):
        """xi.mob.phOnDespawn(ph, NM, chance, cooldown, params): the chance in percent, the wait in seconds.
        Where the zone's data has the lottery as a slot (lotteries.from_slots), that stands."""
        # (zone, NM id) -> { chance, cooldown, immediate, day, night }: the zone data's slots first, which
        # a script's word does not replace and a module's does
        self.lottery = dict(self.slot_lottery)
        sources = []
        for zone, info in sorted(self.zones.items()):
            if info.folder is not None:
                sources += [(zone, path) for path in sorted((info.folder / 'mobs').glob('*.lua'))]
        sources += [(None, path) for path in self.module_files()]
        for home, path in sources:
            text = path.read_text(errors='replace')
            if 'phOnDespawn' not in text and 'spawnPoints' not in text:
                continue
            text = strip_comments(text)
            aliases = dict(re.findall(r'local\s+(\w+)\s*=\s*zones\[xi\.zone\.(\w+)\]', text))
            tables = point_tables(text)
            seen = set()
            for args in calls(text, 'phOnDespawn'):
                if len(args) < 4:
                    continue
                info, nm = self.resolve_mob(args[1], home, aliases)
                wait = seconds(args[3])
                try:
                    chance = float(args[2])
                except ValueError:
                    continue
                if nm is None or wait is None:
                    continue
                params = args[4] if len(args) > 4 else ''
                if re.fullmatch(r'\w+', params):
                    # handed over in a variable: what the script puts in a table of that name
                    params = ' '.join(re.findall(r'\b' + params + r'\s*=\s*(\{[^{}]*\})', text)
                                      + re.findall(r'\b' + params + r'\.(\w+\s*=\s*\w+)', text))
                entry = {'chance': chance, 'cooldown': wait[0]}
                if wait[1] != wait[0]:
                    entry['cooldownMost'] = wait[1]
                for key, word in (('immediate', 'immediate'), ('day', 'dayOnly'), ('night', 'nightOnly')):
                    if re.search(word + r'\s*=\s*true', params):
                        entry[key] = True
                key = (info.zone, nm)
                # a module's word replaces the scripts'; within one file the first placeholder's stands
                if key not in seen:
                    seen.add(key)
                    if home is None or key not in self.lottery:
                        self.lottery[key] = entry
                handed = re.search(r'spawnPoints\s*=\s*(\w+)', params)
                if handed and handed.group(1) in tables:
                    info.points[nm] = list(tables[handed.group(1)])
            # a module that gives a monster other spawn points: xi.zones.<Zone>.mobs.<Mob>.spawnPoints = <table>
            for zone_name, script, table in re.findall(r'xi\.zones\.(\w+)\.mobs\.([\w\-]+)\.spawnPoints\s*=\s*(\w+)', text):
                info = self.zones.get(self.by_squash.get(squash(zone_name)))
                if info and table in tables:
                    for mob_id in info.by_script.get(script, []):
                        info.points[mob_id] = list(tables[table])
            if home is None:
                # tables a module works through: { 'Zone', 'Mob', least, most } respawn windows and
                # { 'Zone', 'Mob', cooldown } lottery waits
                for zone_name, script, first, second in re.findall(
                        r"\{\s*'(\w+)'\s*,\s*'([\w\-]+)'\s*,\s*(\d+)\s*(?:,\s*(\d+)\s*)?\}", text):
                    info = self.zones.get(self.by_squash.get(squash(zone_name)))
                    for mob_id in (info.by_script.get(script, []) if info else []):
                        if second:
                            info.respawns[mob_id] = (int(first), int(second))
                        elif (info.zone, mob_id) in self.lottery:
                            self.lottery[(info.zone, mob_id)] = dict(self.lottery[(info.zone, mob_id)], cooldown=int(first))

    def read_forced(self):
        """npcUtil.popFromQM in a zone's NPC scripts: what is traded to (or done at) which ??? brings which monster."""
        self.forced = {}  # (zone, NM id) -> [ { npc, at, items } ]
        for zone, info in sorted(self.zones.items()):
            if info.folder is None or not (info.folder / 'npcs').is_dir():
                continue
            for path in sorted((info.folder / 'npcs').glob('*.lua')):
                text = path.read_text(errors='replace')
                if 'popFromQM' not in text:
                    continue
                text = strip_comments(text)
                pops = [re.findall(r'ID\.mob\.(\w+)', args[2]) if len(args) > 2 else [] for args in calls(text, 'popFromQM')]
                trades = [re.findall(r'xi\.item\.(\w+)', ','.join(args[1:]))
                          for args in calls(text, 'tradeHasExactly') + calls(text, 'tradeHas')]
                trades = [trade for trade in trades if trade]
                everything = re.findall(r'ID\.mob\.(\w+)', text)
                npc = info.npcs.get(path.stem) or {}
                for number, names in enumerate(pops):
                    # the monsters named in the call, or (handed over in a variable) every one the script names
                    names = names or everything
                    if len(trades) == len(pops):
                        items = trades[number]      # a trade for each monster, in the order written
                    elif len(trades) == 1:
                        items = trades[0]
                    else:
                        items = []
                    for name in dict.fromkeys(names):
                        mob_id = info.constants.get(name)
                        if mob_id is None or mob_id not in info.shown:
                            continue
                        entry = {'npc': str(npc.get('display_name') or path.stem.replace('_', ' ')),
                                 'items': [self.item_enum[item] for item in items if item in self.item_enum]}
                        if npc.get('at'):
                            entry['at'] = [round(float(n), 1) for n in npc['at'][:3]]
                        if len(trades) > 1 and len(trades) != len(pops):
                            entry['unsure'] = True  # several trades in the script, and no telling which is this monster's
                        found = self.forced.setdefault((zone, mob_id), [])
                        if entry not in found:
                            found.append(entry)

    # -- what is written -------------------------------------------------------------------------

    def place(self, info, mob_id):
        """Where a spawn stands: its points, or the regions it is put down in."""
        spawn = info.spawns.get(mob_id) or {}
        if info.points.get(mob_id):
            return [[round(n, 1) for n in point] for point in dict.fromkeys(info.points[mob_id])], []
        if spawn.get('at'):
            # 1, 1, 1 is where the data puts a monster that has no place of its own
            at = [round(float(n), 1) for n in spawn['at'][:3]]
            return ([at] if at != [1, 1, 1] else []), []
        names = spawn.get('region') or []
        areas = [info.regions[name] for name in ([names] if isinstance(names, str) else names) if name in info.regions]
        return [], areas

    def routes(self, info, mob_id):
        """The routes a spawn walks: its own in the zone's data, and those its script walks it over."""
        spawn = info.spawns.get(mob_id) or {}
        found = []
        for key in ('path', 'circuit'):
            if spawn.get(key):
                found.append({'loop': key == 'circuit', 'points': [[round(float(n), 1) for n in point[:3]] for point in spawn[key]]})
        for route in info.paths.get(mob_id, []):
            found.append({'loop': False, 'points': [[round(n, 1) for n in point] for point in route]})
        return found

    def rolls(self, loot):
        """Each roll made as the monster dies: its chance in tenths of a percent, and what it gives (item id, share of 10000)."""
        found = []
        for roll in loot.get('drops') or []:
            chance = roll.get('chance')
            rate = DROP_RATES.get(chance) if isinstance(chance, str) else int(round(float(chance or 0) * 10))
            if rate is None:
                self.notes.append(f'unknown chance: {chance}')
                continue
            if 'item' in roll:
                shares = [(roll['item'], 10000)]
            elif isinstance(roll.get('one_of'), dict):
                shares = [(name, int(round(float(percent) * 100))) for name, percent in roll['one_of'].items()]
            else:
                names = roll.get('one_of') or []
                shares = [(name, 10000 // len(names)) for name in names]
            items = []
            for name, share in shares:
                item = 0 if name == 'nothing' else self.generator.items.get(str(name))
                if item is None:
                    self.notes.append(f'unknown item: {name}')
                elif item:
                    items.append([item, share])
            if items:
                found.append({'rate': rate, 'items': items})
        return found

    def monster(self, info, name, ids):
        generator = self.generator
        first = info.spawns[ids[0]]
        template = info.templates[first['template']]
        entry = generator.build_entry(template, first)
        attributes = self.importer.overlay(generator.species.get(str(template.get('species')), {}), template.get('attributes') or {})
        spawn_types = (attributes.get('spawn') or {}).get('type') or []
        levels = [spawn.get('level') or [0, 0] for spawn in (info.spawns[mob_id] for mob_id in ids)]

        out = {'name': name, 'indices': [mob_id & 0xFFF for mob_id in ids],
               'level': [min(level[0] for level in levels), max(level[-1] for level in levels)]}
        if entry['Family']:
            out['family'] = entry['Family']
        if entry['Job']:
            out['job'] = entry['Job']
        for key, field in (('aggro', 'Aggro'), ('link', 'Link'), ('truesight', 'TrueSight')):
            if entry[field]:
                out[key] = True
        detects = [word for word, field in (('Sight', 'Sight'), ('Sound', 'Sound'), ('Low HP', 'Blood'), ('Magic', 'Magic'),
                                            ('Job Abilities', 'JA'), ('Scent', 'Scent')) if entry[field]]
        if detects:
            out['detects'] = detects

        # how it comes to be there
        placeholders = sorted(set().union(*(info.ph.get(mob_id, set()) for mob_id in ids)))
        lottery = next((self.lottery[(info.zone, mob_id)] for mob_id in ids if (info.zone, mob_id) in self.lottery), None)
        forced = [entry for mob_id in ids for entry in self.forced.get((info.zone, mob_id), [])]
        respawn = next((info.respawns[mob_id] for mob_id in ids if mob_id in info.respawns), None)
        if respawn is None and entry['Respawn']:
            respawn = (entry['Respawn'], entry['Respawn'])
        kinds = ''
        if placeholders or 'lottery' in spawn_types:
            kinds += 'l'
            out['lottery'] = lottery or {}
        elif respawn:
            kinds += 't'
            out['respawn'] = list(respawn)
        if forced:
            kinds += 'f'
            out['forced'] = [dict(found) for found in {lua(found): found for found in forced}.values()]
        if not kinds:
            kinds = 's'
        out['kinds'] = kinds
        conditions = [condition for condition in SPAWN_CONDITIONS if condition in spawn_types]
        if conditions:
            out['conditions'] = conditions

        # where: its own points and regions, and its placeholders'
        points, areas, routes = [], [], []
        for mob_id in ids:
            found_points, found_areas = self.place(info, mob_id)
            points += [point for point in found_points if point not in points]
            areas += [area for area in found_areas if area not in areas]
            routes += [route for route in self.routes(info, mob_id) if route not in routes]
        if points:
            out['points'] = points
        if areas:
            out['areas'] = areas
        if routes:
            out['routes'] = routes
        if placeholders:
            out['placeholders'] = []
            for ph in placeholders:
                spawn = info.spawns[ph]
                ph_template = info.templates[spawn['template']]
                ph_points, ph_areas = self.place(info, ph)
                found = {'index': ph & 0xFFF, 'name': info.shown[ph], 'level': list(spawn.get('level') or [0, 0])}
                ph_attributes = self.importer.overlay(self.importer.overlay(
                    generator.species.get(str(ph_template.get('species')), {}), ph_template.get('attributes') or {}),
                    spawn.get('attributes') or {})
                ph_respawn = (ph_attributes.get('spawn') or {}).get('respawn')
                if ph_respawn:
                    found['respawn'] = ph_respawn
                if ph_points:
                    found['points'] = ph_points
                if ph_areas:
                    found['areas'] = ph_areas
                ph_routes = self.routes(info, ph)
                if ph_routes:
                    found['routes'] = ph_routes
                out['placeholders'].append(found)

        loot = template.get('loot') or {}
        out['drops'] = self.rolls(loot)
        steal = generator.steals(loot)
        if steal:
            out['steal'] = steal
        despoil = generator.despoils(loot)
        if despoil:
            out['despoil'] = despoil
        return out

    def write(self):
        self.output.mkdir(parents=True, exist_ok=True)
        for stale in self.output.glob('*.lua'):
            stale.unlink()
        index, total = [], 0
        for zone, info in sorted(self.zones.items()):
            by_name = {}
            for mob_id, spawn in sorted(info.spawns.items()):
                if 'notorious' in (info.templates[spawn['template']].get('type') or []):
                    by_name.setdefault(info.shown[mob_id], []).append(mob_id)
            if not by_name:
                continue
            monsters = [self.monster(info, name, ids) for name, ids in sorted(by_name.items())]
            lines = [f'-- Generated by tools/build_mark_data.py\n-- Zone: {zone} ({info.id})\nreturn {{']
            for monster in monsters:
                lines.append(f'    [{lua(monster["name"])}] = {{')
                lines += [f'        {key} = {lua(value)},' for key, value in monster.items() if key != 'name']
                lines.append('    },')
            lines.append('};\n')
            (self.output / f'{info.id}.lua').write_text('\n'.join(lines))
            index.append((zone.replace('_', ' ').title(), info.id, monsters))
            total += len(monsters)
        # every zone and its monsters, with how each comes to be there: l(ottery), t(imed), f(orced), s(cripted)
        lines = ['-- Generated by tools/build_mark_data.py', '-- Every zone with notorious monsters: its id, a name to fall back on, and each monster with how it comes to be there', 'return {']
        for name, zone_id, monsters in sorted(index):
            listed = ', '.join(f'{{ {lua(monster["name"])}, {lua(monster["kinds"])} }}' for monster in monsters)
            lines.append(f'    {{ id = {zone_id}, name = {lua(name)}, {listed} }},')
        lines.append('};\n')
        (self.output / 'index.lua').write_text('\n'.join(lines))
        self.write_maps({zone_id for _, zone_id, _ in index})
        return total, len(index)

    def write_maps(self, zones):
        """Each zone's maps, a floor to each: where it is in the client's table of maps, and its picture's file under the game's folder."""
        source = ROOT / 'addons/zone/data/all_maps.lua'
        if not source.exists():
            print('  no addons/zone/data/all_maps.lua: data/maps.lua not written')
            return
        floors = {}
        for zone_id, floor, index, dat in re.findall(
                r'zone_id = (\d+), name = "[^"]*", floor_id = (\d+), table_index = (\d+),.*?dat = "([^"]+)"', source.read_text()):
            if int(zone_id) in zones:
                floors.setdefault(int(zone_id), {}).setdefault(int(floor), (int(index), dat))
        lines = ['-- Generated by tools/build_mark_data.py from addons/zone/data/all_maps.lua',
                 '-- Zone -> its maps: the floor\'s id, its place in the client\'s table of maps, and its picture\'s file', 'return {']
        for zone_id, found in sorted(floors.items()):
            listed = ', '.join(f'{{ floor = {floor}, index = {index}, dat = {lua(dat)} }}' for floor, (index, dat) in sorted(found.items()))
            lines.append(f'    [{zone_id}] = {{ {listed} }},')
        lines.append('};\n')
        (self.output / 'maps.lua').write_text('\n'.join(lines))

    # Module overrides read and decided on by hand, by module and target: what each does to what is
    # exported here, and why it is let be. A change of target sends it back to be read.
    DECIDED = {
        ('pxi_timed_nm_respawn_persistence', 'xi.zones.*.mobs.*.onMobInitialize'):
            'keeps a timed NM\'s pending respawn across a restart; its window is its script\'s',
        ('pxi_timed_nm_respawn_persistence', 'xi.zones.*.mobs.*.onMobDespawn'):
            'keeps a timed NM\'s pending respawn across a restart; its window is its script\'s',
        ('pxi_timed_nm_respawn_persistence', 'xi.zones.*.Zone.onInitialize'):
            'keeps a rescheduled NM\'s pending respawn across a restart',
        # the NMs it treats one by one: each saves and restores the window its own script sets
        **{('pxi_timed_nm_respawn_persistence', f'xi.zones.{zone}.mobs.{mob}.{event}'):
           'keeps the window its own script sets across a restart'
           for zone, mob, events in (('Misareaux_Coast', 'Odqan', ('onMobDespawn', 'onMobInitialize')),
                                     ('Riverne-Site_A01', 'Carmine_Dobsonfly', ('onMobDespawn', 'onMobInitialize')),
                                     ('Jugner_Forest', 'King_Arthro', ('onMobDespawn', 'onMobInitialize')),
                                     ('Batallia_Downs', 'Lumber_Jack', ('onMobInitialize', 'onMobSpawn', 'onMobDespawn')))
           for event in events},
    }

    def window_of(self, body):
        """The respawn window an override writes, in seconds, (least, most), or None: a + math.random(p, q) * k,
        math.random(least, most) of ten minutes or more, or setRespawnTime(n); None too where it writes
        two that differ."""
        found, rest = set(), body
        for m in re.finditer(r'(\d+)\s*\+\s*math\.random(?:Int)?\(\s*(\d+)\s*,\s*(\d+)\s*\)\s*\*\s*(\d+)', body):
            a, p, q, k = (int(g) for g in m.groups())
            found.add((a + p * k, a + q * k))
            rest = rest.replace(m.group(0), '')
        for m in re.finditer(r'math\.random(?:Int)?\(\s*(\d+)\s*,\s*(\d+)\s*\)', rest):
            if int(m.group(1)) >= 600:
                found.add((int(m.group(1)), int(m.group(2))))
        for m in re.finditer(r'setRespawnTime\(\s*(\d+)\s*\)', rest):
            if int(m.group(1)):
                found.add((int(m.group(1)),) * 2)
        return found.pop() if len(found) == 1 else None

    def check_modules(self):
        """Every module override of a zone's script on live, for what of it this reads. The module
        files' text is read for lotteries, spawn points and the tables of respawn windows a module
        works through (read_lotteries); a respawn window an override writes itself is read here and
        stands for the monster it is of and those it names; one that pops a monster from a ???
        (read_forced reads the zones' own NPC scripts only), or says of respawns what is not read,
        stops the build."""
        def with_helpers(override):
            """The override's code and that of the local functions of its file it calls."""
            body = override.body
            for name in set(re.findall(r'\b(\w+)\s*\(', override.body)):
                definition = re.search(r'\blocal\s+function\s+' + name + r'\s*\(', override.text)
                if definition:
                    body += '\n' + modules.function_body(override.text, definition.start())
            return body

        def handle(override):
            body, target = with_helpers(override), override.target
            decided = self.DECIDED.get((override.module, target))
            if decided:
                return decided
            if 'popFromQM' in body:
                return None
            if re.search(r'phOnDespawn|spawnPoints', body):
                return 'read off its file\'s text'
            if not re.search(r'setRespawnTime|[\'"]respawn[\'"]|phList|SpawnMob', body):
                return 'nothing of lotteries, spawns or respawns'
            if '*' in target and re.search(r"\{\s*'\w+'\s*,\s*'[\w\-]+'\s*,\s*\d+", override.text):
                return 'read off its file\'s table'
            if target.endswith('.Zone.onInitialize'):
                return 'the first pop after a restart, not a respawn window'
            match = re.match(r'xi\.zones\.([^.*]+)\.mobs\.([^.*]+)\.(onMobDespawn|onMobInitialize)$', target)
            window = self.window_of(body)
            if match is None or window is None:
                return None
            info = self.zones.get(self.by_squash.get(squash(match.group(1))))
            if info is None:
                return 'a zone not exported'
            aliases = dict(re.findall(r'local\s+(\w+)\s*=\s*zones\[xi\.zone\.(\w+)\]', override.text))
            mob_ids = set(info.by_script.get(match.group(2), []))
            for named in re.findall(r'\b(\w+\.mob\.\w+)', body):
                found_info, mob_id = self.resolve_mob(named, info.zone, aliases)
                if found_info is info and mob_id is not None:
                    mob_ids.add(mob_id)
            for mob_id in mob_ids:
                info.respawns[mob_id] = window
            return f'respawns in {window[0]}-{window[1]} s, {len(mob_ids)} monster(s)'
        modules.guard(self.server, ('xi.zones.', 'xi.mob.'), handle, out=io.StringIO())

    def run(self):
        with tempfile.TemporaryDirectory() as scratch:
            (Path(scratch) / 'reader.lua').write_text(READER)
            for path in sorted((self.server / 'data/zones').glob('*/mobs.yaml')):
                self.read_zone(path.parent.name, scratch)
        self.read_lotteries()
        self.check_modules()
        self.read_forced()
        total, zones = self.write()
        for note, count in sorted({note: self.notes.count(note) for note in self.notes}.items())[:40]:
            print(f'  {note}' + (f' (x{count})' if count > 1 else ''))
        print(f'Exported {total} notorious monsters in {zones} zones to {self.output}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    source.add_arguments(parser)
    parser.add_argument('--output', type=Path, default=ROOT / 'addons/mark/data')
    args = parser.parse_args()
    found = source.from_arguments(args)
    print(f'Server: {found.describe()}')
    Builder(found.path, args.output).run()
