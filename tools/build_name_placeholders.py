#!/usr/bin/env python3
"""Export each zone's notorious-monster placeholders for the name addon.

A lottery NM is a member of one of its zone's slots (data/zones/<zone>/mobs.yaml)
with a chance and a cooldown, drawn from the slot's other members. Some NMs' scripts
still list theirs instead, entity.phList = { [placeholder id] = NM id }: those are run
in LuaJIT against stand-ins for the server's globals, with the zone's real IDs, and
the lists read off. Both are taken.
Names are resolved by the MobDB importer (forks/addons/mobdb/mobdb/import_phoenix.py).
Requires PyYAML and luajit. Reads the live branch of phoenixffxi/Phoenix, fetched from GitHub
(tools/phoenix), and writes winxi's placeholders set (addons/libs/winxi/data/placeholders);
tools/build_winxi_data.py runs it with the other sets.
"""
import argparse
import hashlib
import re
import subprocess
import tempfile
from pathlib import Path
from phoenix import importer, lotteries, source

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / 'addons/libs/winxi/data/placeholders'

# Prints "placeholder id<TAB>NM id" for every phList entry of a zone's mob scripts.
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
GetFirstID = function(name) return ids[name] and ids[name][1] or nil end
GetTableOfIDs = function(name, count)
    local all, out = ids[name] or {}, {}
    for i = 1, count or #all do out[i] = all[i] or (all[1] and all[1] + i - 1) end
    return out
end
setmetatable(_G, { __index = function(t, k) local v = stand(); rawset(t, k, v); return v end })
local ok, problem = pcall(dofile, zoneDir .. '/IDs.lua')
if not ok then io.stderr:write('IDs: ' .. tostring(problem) .. '\n') end
for file in io.lines() do
    local loaded, entity = pcall(dofile, file)
    local list = loaded and type(entity) == 'table' and rawget(entity, 'phList')
    if type(list) == 'table' and getmetatable(list) ~= inert then
        for ph, nms in pairs(list) do
            -- one placeholder can be several monsters': the value is then a list of them
            for _, nm in ipairs(type(nms) == 'table' and nms or { nms }) do
                if type(ph) == 'number' and type(nm) == 'number' then
                    print(('%d\t%d'):format(ph, nm))
                else
                    io.stderr:write('skipped entry: ' .. file .. '\n')
                end
            end
        end
    elseif not loaded then
        io.stderr:write('unreadable: ' .. file .. ': ' .. tostring(entity) .. '\n')
    else
        io.stderr:write('no list read: ' .. file .. '\n')
    end
end
'''


def squash(name):
    return re.sub(r'[^a-z0-9]', '', name.lower())


def slot_pairs(document):
    """(placeholder id, NM id) for each lottery of the zone's slots."""
    return [(ph, nm) for nm, placeholders, _ in lotteries.from_slots(document) for ph in placeholders]


def build(server, output=OUTPUT, settings=()):
    module = importer.load('name_phoenix_import')
    generator = importer.generator(server, output, settings, module=module)
    server, output = Path(server), Path(output)
    output.mkdir(parents=True, exist_ok=True)
    for stale in output.glob('*.lua'):
        stale.unlink()
    scripts = {squash(path.name): path for path in (server / 'scripts/zones').iterdir() if path.is_dir()}
    zone_count = nm_count = ph_count = 0
    problems = []
    with tempfile.TemporaryDirectory() as scratch:
        reader = Path(scratch) / 'reader.lua'
        reader.write_text(READER)
        for path in sorted((server / 'data/zones').glob('*/mobs.yaml')):
            zone = path.parent.name
            zone_id = generator.zone_ids.get(zone)
            folder = scripts.get(squash(zone))
            if zone_id is None or folder is None:
                continue
            files = sorted(str(file) for file in (folder / 'mobs').glob('*.lua') if 'phList' in file.read_text(errors='replace'))
            document = generator.load_zone(zone)
            lotteries = slot_pairs(document)
            if not files and not lotteries:
                continue
            templates = document.get('templates') or {}
            by_template, shown = {}, {}
            for mob_id, spawn in sorted((document.get('spawns') or {}).items()):
                spawn = spawn or {}
                template_name = spawn.get('template')
                template = templates.get(template_name)
                if not template:
                    continue
                # the server's lookups are by script name, which is the template's unless the spawn has its own
                by_template.setdefault(spawn.get('script') or template.get('script') or template_name, []).append(int(mob_id))
                if generator.content_enabled(template.get('content')):
                    shown[int(mob_id)] = generator.client_name(zone_id, template_name, template, spawn, int(mob_id) & 0xFFF)[0]
            pairs = list(lotteries)
            if files:
                npcs = server / 'data/zones' / zone / 'npcs.yaml'
                if npcs.exists():  # IDs.lua looks NPCs up too; the scripts only need the lookups not to fail
                    for npc_id, npc in sorted(((module.load_yaml(str(npcs)) or {}).get('npcs') or {}).items()):
                        name = (npc or {}).get('script')
                        if name:
                            by_template.setdefault(name, []).append(int(npc_id))
                ids = Path(scratch) / 'ids.lua'
                ids.write_text('return {\n' + ''.join(
                    f'    [{module.lua_string(name)}] = {{ {", ".join(map(str, found))} }},\n' for name, found in by_template.items()) + '}\n')
                ran = subprocess.run(['luajit', str(reader), str(folder), str(ids)], input='\n'.join(files) + '\n',
                                     capture_output=True, text=True, check=True)
                problems += [f'{zone}: {line}' for line in ran.stderr.splitlines()]
                pairs += [tuple(map(int, line.split('\t'))) for line in ran.stdout.splitlines()]
            found = {}
            for ph, nm in pairs:
                # only slots of this zone that the roster also has: the addon knows a monster by its index
                if ph in shown and nm in shown and ph != nm:
                    found.setdefault(shown[nm], set()).add(ph & 0xfff)
                else:
                    problems.append(f'{zone}: placeholder {ph} of {nm} is not a spawn of this zone')
            if not found:
                continue
            rows = [f'    [{module.lua_string(name)}] = {{ {", ".join(map(str, sorted(indices)))} }},'
                    for name, indices in sorted(found.items())]
            digest = hashlib.sha256('\n'.join(rows).encode()).hexdigest()
            (output / f'{zone_id}.lua').write_text(
                f'-- Generated by tools/build_name_placeholders.py\n-- Zone: {zone} ({zone_id})\n'
                f'-- Notorious monster -> its placeholders\' entity indices; SHA256: {digest}\nreturn {{\n' + '\n'.join(rows) + '\n};\n')
            zone_count += 1
            nm_count += len(found)
            ph_count += sum(len(indices) for indices in found.values())
    for problem in problems:
        print('  ' + problem)
    print(f'Exported {ph_count} placeholders of {nm_count} notorious monsters in {zone_count} zones to {output} ({len(problems)} notes above)')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    source.add_arguments(parser)
    parser.add_argument('--output', type=Path, default=OUTPUT)
    args = parser.parse_args()
    found = source.from_arguments(args)
    print(f'Server: {found.describe()}')
    build(found.path, args.output)
