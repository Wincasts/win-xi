addon.name    = 'vis';
addon.author  = 'win';
addon.version = '2.2';
addon.desc    = 'World and entity draw distance with the fog kept where you want it: general values, a preset for cities, the outdoors and dungeons, and a zone\'s own, saved per character.';
addon.link    = 'https://github.com/Wincasts/win-xi';

--[[
The client multiplies its far clip, fog, zone-object ranges and entity cull distance by two floats,
world and entity, which the drawdistance addon sets; every distance asks one small function for the
scale. The fog asks it twice, for its start and its end, from a function just before it. This addon
sets the two floats and sends the fog's two calls through a stub that multiplies their answer by
fog / world, so the fog sits at fog times stock whatever the world multiplier is. A fog of 1 with a
world of 2 is stock fog in front of twice the terrain.

The values in force are resolved in three layers: the zone's own (/vis zone world 3), then
the preset for the zone's kind (/vis dungeon world 2; every zone is a city, outdoors or a
dungeon by zones.lua, built from the Phoenix server's zone data), then the general values
(/vis world 2). A layer holds only what was set in it, and each value comes from the most
particular layer that has it. The zone is read from the game at load and from the zone-in packet
after, and the values for it go into the game as it arrives, so a town can draw everything and a
big field keep its frames. Cities and dungeons begin with world x2 in their presets, once.

The finding is done in the running game: the client DLL is packed on disk. The scale function is
found by drawdistance's bytes, its entry by the calls to it, and the fog's calls by their shape: in
the function before, pushing the world selector, multiplying by the answer. /vis callers lists
every call for the record, and /vis patch <n> <mult> still re-scales any one of them by number.

The field of view and the projection's aspect constant (fov and square) were here until 2.0 and are the
lens plugin's now (/lens fov, /lens middle, /lens square); a character's saved ones are said once at load
as the lens commands that set them, and dropped.

This addon was drawscale until 2.1, and its terrain setting vis. A character's drawscale settings are
copied to vis's the first time vis loads for them (adoptDrawscale), and a saved vis is read as terrain.
--]]

require 'common';
local settings = require('settings');
local scan = require('scan');
local detail = require('detail');
local view = require('view');

local ok, chat = pcall(require, 'chat');
if (not ok) then chat = nil; end

local PATTERN   = '8BC1487408D80D'; -- mov eax, ecx; dec eax; jz +8; fmul dword [world]
local REACH     = 512;              -- a call may land this far before the pattern (the function's entry)
local CHUNK     = 4096;
local MAX_STUBS = 8;

local defaults = T{
    world   = 1.0,
    entity  = 1.0,
    fog     = 1.0,
    objects = 0,      -- zone-object ranges: n times stock; 0 = the same as world
    detail  = 0,      -- how much further objects keep their detailed mesh; 0 = the same as world
    terrain = false,  -- draw distant terrain the zone's visibility lists would hide
    zones   = T{},    -- zone id (as a string) -> the values set for that zone alone
    kinds   = T{ city = T{}, outdoors = T{}, dungeon = T{} }, -- the values set for every zone of a kind
    seeded  = false,  -- whether the city and dungeon presets were given their starting world x2
    adopted = false,  -- whether this character's drawscale settings were looked for, to copy
    terrainOff = false, -- whether a terrain on saved before 2.2, when on was the default, was turned off
};
local VALUES = { 'world', 'entity', 'fog', 'objects', 'detail', 'terrain' };
local KINDS = { city = 'a city', outdoors = 'outdoors', dungeon = 'a dungeon' };
local KIND_PRESET = { city = 'the city preset', outdoors = 'the outdoors preset', dungeon = 'the dungeon preset' };
local SEED = { city = { world = 2 }, dungeon = { world = 2 } };

-- Each zone's kind, from the server's data; without the file no zone has one.
local okZones, zoneKinds = pcall(require, 'zones');
if (not okZones or type(zoneKinds) ~= 'table') then zoneKinds = {}; end

local state = T{
    settings = nil,
    zone     = 0,      -- the zone the player is in; 0 until known
    kind     = nil,    -- its kind: 'city', 'outdoors', 'dungeon' or nil
    active   = nil,    -- the values in force, resolved from the three layers
    fn       = 0,      -- the scale function, where the pattern matched
    world    = 0,      -- address of the world multiplier float
    entity   = 0,      -- address of the entity multiplier float
    module   = nil,    -- { base, size } of the module holding the function
    thunks   = T{},
    pointers = T{},
    callers  = T{},    -- { address, delta, via, info, before, after, pattern }
    fogSites = T{},    -- the fog's two calls, as indexes into callers
    objectSite = nil,  -- the zone-object range's call, as an index into callers
    mem      = 0,      -- the stubs
    patches  = T{},    -- caller index -> { site, backup, stub, slot, mult, ratio, fog, objects }
    scanStats = nil,
    detail   = nil,    -- the mesh-detail sites, from detail.find
    detailMem = 0,     -- their stubs
    view     = nil,    -- the visibility-list site, from view.find
    moved    = nil,    -- what to say of fov and square saved before 2.0, said once at load
    adopted  = nil,    -- drawscale's settings were copied to vis's, to say once
    terrainOff = nil,  -- a saved terrain on was turned off, the default from 2.2, to say once
};

-- The client's memory, as the detail and view modules see it.
local mem = {
    find = function (pattern) return ashita.memory.find(0, 0, pattern, 0, 0); end,
    read = function (addr, n) return ashita.memory.read_array(addr, n); end,
    read_u32 = function (addr) return ashita.memory.read_uint32(addr); end,
    write = nil, -- writeBytes, below
    write_u32 = function (addr, v) ashita.memory.write_uint32(addr, v); end,
    read_float = function (addr) return ashita.memory.read_float(addr); end,
    write_float = function (addr, v) ashita.memory.write_float(addr, v); end,
    alloc = function (n) return ashita.memory.alloc(n) or 0; end,
};

-- How far from you the server sends entities: its own (winxi.rules, from its zone_entities.cpp), or 50
local function SendDistance()
    local ok, rules = pcall(require, 'winxi.rules');
    local found = ok and rules.Get('entities') or nil;
    return math.floor((found and found.SendDistance) or 50);
end

local function say(s)
    if (chat) then print(chat.header(addon.name):append(chat.message(s))); else print('[vis] ' .. s); end
end
local function fail(s)
    if (chat) then print(chat.header(addon.name):append(chat.error(s))); else print('[vis] error: ' .. s); end
end

-- The game's name for a zone, where it has one.
local function zoneName(id)
    local ok, name = pcall(function () return AshitaCore:GetResourceManager():GetString('zones.names', id); end);
    if (ok and type(name) == 'string' and name ~= '') then return name; end
    return ('zone %d'):format(id);
end

-- The zone the player is in, from the game; nil before there is one.
local function zoneFromGame()
    local ok, id = pcall(function () return AshitaCore:GetMemoryManager():GetParty():GetMemberZone(0); end);
    if (ok and type(id) == 'number' and id > 0) then return id; end
    return nil;
end

-- The three layers: the zone's own values (nil where it has none), the preset for its kind (nil
-- for a zone of no known kind), and the general values.
local function ownValues() local s = state.settings; return (s and state.zone ~= 0 and s.zones) and s.zones[tostring(state.zone)] or nil; end
local function kindValues() local s = state.settings; return (s and state.kind and s.kinds) and s.kinds[state.kind] or nil; end

-- The values in force: each from the most particular layer that has it.
local function resolve()
    local s = state.settings;
    if (s == nil) then state.active = nil; return defaults; end
    local own, kind = ownValues(), kindValues();
    local out = T{};
    for _, k in ipairs(VALUES) do
        local v = own and own[k];
        if (v == nil and kind) then v = kind[k]; end
        if (v == nil) then v = s[k]; end
        out[k] = v;
    end
    state.active = out;
    return out;
end
local function active() return state.active or resolve(); end

local function reportPath(name)
    local dir = ('%s\\config\\addons\\vis\\'):format(AshitaCore:GetInstallPath());
    if (ashita.fs and ashita.fs.create_directory) then ashita.fs.create_directory(dir); end
    return dir .. (name or 'callers.txt');
end

-- The module holding addr: FFXiMain.dll by Ashita's own knowledge of it when the address is inside,
-- else the nearest PE header below it. The client's code is not laid out in memory as the file's
-- sections say (the DLL is packed), so the whole module is scanned, not its code section.
local function moduleOf(addr)
    local known = ashita.memory.get_base('FFXiMain.dll');
    local knownSize = ashita.memory.get_size('FFXiMain.dll');
    if (known ~= nil and known ~= 0 and knownSize ~= nil and addr >= known and addr < known + knownSize) then
        return { base = known, size = knownSize };
    end
    local page = addr - (addr % 0x1000);
    for _ = 1, 16384 do
        local okMagic, magic = pcall(ashita.memory.read_uint16, page);
        if (okMagic and magic == 0x5A4D) then
            local peOk, pe = pcall(ashita.memory.read_uint32, page + 0x3C);
            if (peOk and pe > 0 and pe < 0x1000) then
                local sigOk, sig = pcall(ashita.memory.read_uint32, page + pe);
                if (sigOk and sig == 0x4550) then
                    local size = ashita.memory.read_uint32(page + pe + 24 + 56);
                    if (page + size > addr) then return { base = page, size = size }; end
                end
            end
        end
        page = page - 0x1000;
        if (page <= 0) then break; end
    end
    return nil;
end

-- Runs fn over the module in chunks: fn(bytes, address, count), bytes having a margin past count
-- where there was one to read. Counts what was read, for the report.
local function eachChunk(module, fn)
    local at = module.base;
    local stop = module.base + module.size;
    local stats = { read = 0, failed = 0, bytes = 0, calls = 0, patternSeen = false, firstError = nil };
    while (at < stop) do
        local count = math.min(CHUNK, stop - at);
        local readOk, bytes = pcall(ashita.memory.read_array, at, count + 8);
        if (not (readOk and type(bytes) == 'table')) then
            if (not readOk and stats.firstError == nil) then stats.firstError = tostring(bytes); end
            readOk, bytes = pcall(ashita.memory.read_array, at, count);
        end
        if (readOk and type(bytes) == 'table') then
            stats.read = stats.read + 1;
            stats.bytes = stats.bytes + count;
            for i = 1, count do if (bytes[i] == 0xE8) then stats.calls = stats.calls + 1; end end
            if (state.fn >= at and state.fn < at + count) then
                local i = state.fn - at + 1;
                stats.patternSeen = bytes[i] == 0x8B and bytes[i + 1] == 0xC1 and bytes[i + 2] == 0x48;
            end
            fn(bytes, at, count);
        else
            stats.failed = stats.failed + 1;
            if (not readOk and stats.firstError == nil) then stats.firstError = tostring(bytes); end
        end
        at = at + CHUNK;
    end
    state.scanStats = stats;
end

-- Every call to the scale function in the module holding it: direct calls, then calls through a
-- jump thunk, and the places holding its address.
local function findCallers()
    local found = T{};
    state.thunks, state.pointers = T{}, T{};
    state.module = moduleOf(state.fn);
    if (state.module == nil) then
        fail('The module holding the scale function was not found; nothing to scan.');
        return found;
    end
    eachChunk(state.module, function (bytes, at, count)
        for _, hit in ipairs(scan.callers(bytes, at, state.fn, count, REACH)) do found:append(hit); end
        for _, hit in ipairs(scan.jumps(bytes, at, state.fn, count, REACH)) do state.thunks:append(hit.address); end
        for _, addr in ipairs(scan.references(bytes, at, state.fn, count)) do state.pointers:append(addr); end
    end);
    if (#state.thunks > 0) then
        eachChunk(state.module, function (bytes, at, count)
            for _, thunk in ipairs(state.thunks) do
                for _, hit in ipairs(scan.callers(bytes, at, thunk, count, 0)) do
                    hit.via = thunk;
                    found:append(hit);
                end
            end
        end);
    end
    found:sort(function (a, b) return a.address < b.address; end);
    return found;
end

local function describeCallers()
    for _, c in ipairs(state.callers) do
        local okBefore, before = pcall(ashita.memory.read_array, c.address - 24, 24);
        local okAfter, after = pcall(ashita.memory.read_array, c.address + 5, 24);
        c.before = okBefore and before or {};
        c.after = okAfter and after or {};
        c.info = scan.describe(c.before, c.after);
        c.pattern = state.fn;
    end
end

local function findFog()
    state.fogSites = T{};
    local fog = scan.fogCallers(state.callers, REACH);
    if (fog == nil) then return false; end
    for n, c in ipairs(state.callers) do
        if (c == fog[1] or c == fog[2]) then state.fogSites:append(n); end
    end
    return #state.fogSites == 2;
end

-- The zone-object range's call: the one that stores the scale to the renderer's field for it. The
-- client culls an object with distance^2 > scale x range^2, so a world multiplier of w only pushes
-- objects out by sqrt(w); the stub multiplies the scale again so they go out by the objects setting.
local function findObjects()
    state.objectSite = nil;
    local found = scan.objectCaller(state.callers);
    if (found == nil) then return false; end
    for n, c in ipairs(state.callers) do
        if (c == found) then state.objectSite = n; end
    end
    return state.objectSite ~= nil;
end

local function lineFor(n, c)
    local info = c.info or {};
    local what = '';
    if (info.sink and info.sink:match('ebp%+0x39428')) then what = '  <- zone-object range'; end
    for _, f in ipairs(state.fogSites) do if (f == n) then what = '  <- fog'; end end
    local patched = state.patches[n];
    local mark = patched and (patched.fog and '  [fog stub]' or patched.objects and '  [objects stub]' or (('  [patched x%.2f]'):format(patched.mult))) or '';
    local via = c.via and ((' via thunk 0x%08X'):format(c.via)) or '';
    return ('#%d 0x%08X %s%s%s | pushes %s, then %s%s%s'):format(
        n, c.address, info.selector or '?', c.delta ~= 0 and ((' (call lands %d before the pattern)'):format(c.delta)) or '', via,
        info.push or '?', info.sink or (info.after and info.after[1]) or '?', what, mark);
end

local function detailFor(c)
    local info = c.info or {};
    return ('    before: %s  [%s]\n    after:  %s  [%s]'):format(
        table.concat(info.before or {}, '; '), scan.hex(c.before, 1, #c.before),
        table.concat(info.after or {}, '; '), scan.hex(c.after, 1, #c.after));
end

local function report(toChat)
    local lines = T{};
    local world = state.world ~= 0 and ashita.memory.read_float(state.world) or 0;
    local entity = state.entity ~= 0 and ashita.memory.read_float(state.entity) or 0;
    local m = state.module;
    lines:append(('scale function 0x%08X; world x%.2f at 0x%08X; entity x%.2f at 0x%08X; %d callers'):format(
        state.fn, world, state.world, entity, state.entity, #state.callers));
    lines:append(m and (('scanned module 0x%08X-0x%08X (%d KB); %d jump thunks; %d pointers to the function'):format(
        m.base, m.base + m.size, math.floor(m.size / 1024), #state.thunks, #state.pointers)) or 'no module scanned');
    local st = state.scanStats;
    if (st) then
        lines:append(('chunks read %d, failed %d (%d KB read); %d call opcodes seen; the function\'s bytes seen in the scan: %s%s'):format(
            st.read, st.failed, math.floor(st.bytes / 1024), st.calls, tostring(st.patternSeen),
            st.firstError and (('; first read error: %s'):format(st.firstError)) or ''));
    else
        lines:append('no scan');
    end
    lines:append(#state.fogSites == 2 and (('fog: callers #%d and #%d'):format(state.fogSites[1], state.fogSites[2])) or 'fog: its two calls were not recognised');
    lines:append(state.objectSite and (('objects: caller #%d'):format(state.objectSite)) or 'objects: the range call was not recognised');
    lines:append(('detail: %d of %d sites; vis site %s'):format(
        state.detail and #state.detail.sites or 0, #detail.PATTERNS, (state.view and state.view.visSite ~= 0) and 'found' or 'not found'));
    for n, c in ipairs(state.callers) do
        lines:append(lineFor(n, c));
        lines:append(detailFor(c));
    end
    for _, t in ipairs(state.thunks) do lines:append(('thunk: jmp at 0x%08X'):format(t)); end
    for _, p in ipairs(state.pointers) do lines:append(('pointer: 0x%08X holds the function'):format(p)); end
    if (toChat) then
        say(lines[1]);
        say(lines[2]);
        say(lines[4]);
        say(lines[5]);
        say(lines[6]);
        for n, c in ipairs(state.callers) do say(lineFor(n, c)); end
        say('Details are in config/addons/vis/callers.txt.');
    end
    local f = io.open(reportPath(), 'w');
    if (f) then
        f:write(('vis %s, %s\n'):format(addon.version, os.date('%Y-%m-%d %H:%M:%S')));
        f:write(table.concat(lines, '\n'), '\n');
        f:close();
    end
end

local function writeBytes(addr, bytes)
    local unOk, prot = ashita.memory.unprotect(addr, #bytes);
    if (not unOk) then return false; end
    ashita.memory.write_array(addr, bytes);
    ashita.memory.protect(addr, #bytes, prot);
    return true;
end
mem.write = writeBytes;

-- The objects and detail settings as used: 0 means the same as world.
local function objectsValue() local s = active(); return (s.objects ~= nil and s.objects > 0) and s.objects or s.world; end
local function detailValue() local s = active(); return (s.detail ~= nil and s.detail > 0) and s.detail or s.world; end

-- Keeps each stub's ratio right for the world multiplier as it is now: a manual patch wants
-- mult x stock, the fog wants the fog setting x stock, and the object range wants its setting
-- squared, since the client compares squared distances against it. world is the multiplier as read,
-- when the caller has it already.
local function applyRatios(world)
    if (next(state.patches) == nil or state.world == 0) then return; end
    world = world or ashita.memory.read_float(state.world);
    state.ratioWorld = world;
    for _, p in pairs(state.patches) do
        local mult = p.fog and active().fog or p.objects and (objectsValue() ^ 2) or p.mult;
        local ratio = scan.ratio(mult, world);
        if (ratio ~= p.ratio) then
            p.ratio = ratio;
            ashita.memory.write_float(p.stub + scan.RATIO_OFFSET, ratio);
        end
    end
end

local function freeSlot()
    for i = 0, MAX_STUBS - 1 do
        local taken = false;
        for _, p in pairs(state.patches) do if (p.slot == i) then taken = true; end end
        if (not taken) then return i; end
    end
    return nil;
end

-- Sends caller n through a stub; kind marks the fog's own ('fog') or the object range's ('objects'),
-- whose multipliers come from the settings.
local function patchCaller(n, mult, kind)
    local c = state.callers[n];
    if (c == nil) then fail(('There is no caller #%d.'):format(n)); return false; end
    local existing = state.patches[n];
    if (existing) then
        existing.mult = mult;
        if (kind == 'fog') then existing.fog = true; end
        if (kind == 'objects') then existing.objects = true; end
        existing.ratio = nil;
        applyRatios();
        return true;
    end
    if (state.mem == 0) then
        state.mem = ashita.memory.alloc(scan.STUB_SIZE * MAX_STUBS);
        if (state.mem == nil or state.mem == 0) then state.mem = 0; fail('Could not allocate memory for the stub.'); return false; end
    end
    local slot = freeSlot();
    if (slot == nil) then fail(('Only %d callers can be patched at once.'):format(MAX_STUBS)); return false; end
    local stub = state.mem + slot * scan.STUB_SIZE;
    local target = (c.address + 5 + ashita.memory.read_int32(c.address + 1)) % 4294967296;
    ashita.memory.write_array(stub, scan.stub(stub, target));
    ashita.memory.write_float(stub + scan.RATIO_OFFSET, 1.0);
    local site = c.address + 1;
    local backup = ashita.memory.read_array(site, 4);
    if (not writeBytes(site, scan.rel32(c.address, stub))) then fail('Could not write the call.'); return false; end
    state.patches[n] = { site = site, backup = backup, stub = stub, slot = slot, mult = mult, ratio = nil, fog = kind == 'fog', objects = kind == 'objects' };
    applyRatios();
    return true;
end

local function unpatchCaller(n)
    local p = state.patches[n];
    if (p == nil) then return false; end
    writeBytes(p.site, p.backup);
    state.patches[n] = nil;
    return true;
end

-- The settings, into the game: the two floats, the fog's and the object range's calls through
-- their stubs, the mesh-detail factor, and the visibility lists.
local function apply()
    local s = resolve();
    if (state.fn == 0 or state.settings == nil) then return; end
    ashita.memory.write_float(state.world, s.world);
    ashita.memory.write_float(state.entity, s.entity);
    for _, n in ipairs(state.fogSites) do
        if (state.patches[n] == nil) then patchCaller(n, s.fog, 'fog'); end
    end
    if (state.objectSite ~= nil and state.patches[state.objectSite] == nil) then
        patchCaller(state.objectSite, objectsValue() ^ 2, 'objects');
    end
    applyRatios();
    if (state.detail ~= nil) then
        if (state.detailMem == 0 and #state.detail.sites > 0) then
            state.detailMem = mem.alloc(detail.ALLOC_SIZE);
            if (state.detailMem ~= 0) then detail.install(mem, state.detail, state.detailMem); end
        end
        if (state.detailMem ~= 0) then detail.set(mem, state.detail, detailValue()); end
    end
    if (state.view ~= nil) then view.setVis(mem, state.view, s.terrain == true); end
end

local function rescan()
    state.fn = ashita.memory.find(0, 0, PATTERN, 0, 0);
    if (state.fn == 0) then
        fail('The scale function was not found; is this the usual client?');
        state.callers = T{};
        state.fogSites = T{};
        return false;
    end
    state.world = ashita.memory.read_uint32(state.fn + 0x07);
    state.entity = ashita.memory.read_uint32(state.fn + 0x0F);
    state.callers = findCallers();
    describeCallers();
    if (not findFog()) then
        fail('The fog\'s two calls were not recognised; world and entity work, the fog setting does not. /vis callers shows what was found.');
    end
    if (not findObjects()) then
        fail('The zone-object range call was not recognised; objects will pop in as with drawdistance.');
    end
    state.detail = detail.find(mem);
    if (state.detail.missing > 0) then
        fail(('%d of %d mesh-detail sites not found; some objects will still drop detail early.'):format(state.detail.missing, #detail.PATTERNS));
    end
    state.view = view.find(mem);
    if (state.view.visSite == 0) then fail('The visibility-list read was not found; distant terrain may still pop in.'); end
    return true;
end

local function valueText(k, v)
    if (k == 'terrain') then return ('terrain %s'):format(v and 'on' or 'off'); end
    if ((k == 'objects' or k == 'detail') and v <= 0) then return ('%s as world'):format(k); end
    return ('%s x%.2f'):format(k, v);
end

-- "world x2.00, terrain off" for what a layer holds, or nil for nothing.
local function layerText(t)
    local parts = T{};
    for _, k in ipairs(VALUES) do if (t ~= nil and t[k] ~= nil) then parts:append(valueText(k, t[k])); end end
    return #parts > 0 and table.concat(parts, ', ') or nil;
end

local function status()
    local s = resolve();
    if (state.zone == 0) then
        say('No zone known yet.');
    else
        say(('In %s (%d), %s.'):format(zoneName(state.zone), state.zone, state.kind and KINDS[state.kind] or 'of no known kind'));
    end
    local fogState = #state.fogSites == 2 and '' or ' (fog calls not found)';
    local objectsState = state.objectSite and '' or ' (range call not found)';
    say(('world x%.2f, entity x%.2f, fog x%.2f%s of stock.'):format(s.world, s.entity, s.fog, fogState));
    say(('objects x%.2f%s%s, detail x%.2f%s, terrain %s.'):format(
        objectsValue(), (s.objects == nil or s.objects <= 0) and ' (same as world)' or '', objectsState,
        detailValue(), (s.detail == nil or s.detail <= 0) and ' (same as world)' or '',
        s.terrain == true and 'on' or 'off'));
    local own, kind = layerText(ownValues()), layerText(kindValues());
    if (own == nil and kind == nil) then
        say('All from the general values.');
    else
        say(('%s%s'):format(own and (('From its own: %s. '):format(own)) or '', kind and (('From %s: %s.'):format(KIND_PRESET[state.kind], kind)) or ''));
    end
end

local function help()
    say('/vis - the values in force, and where each comes from.');
    say('/vis world <n> - terrain, objects and far clip: n times stock (1 = stock).');
    say(('/vis entity <n> - players, NPCs and mobs: n times stock. The server sends entities within about %d yalms.'):format(SendDistance()));
    say('/vis fog <n> - the fog: n times stock, whatever world is. 1 keeps the stock fog.');
    say('/vis objects <n> - buildings, trees and props: n times stock. 0 = the same as world.');
    say('/vis detail <n> - how much further objects keep their detailed mesh. 0 = the same as world.');
    say('/vis terrain on|off - on: draw distant terrain the zone would hide from your area. off (the default): stock.');
    say('The field of view and true proportions are the lens plugin\'s: /lens fov, /lens middle and /lens square.');
    say('Those set the general values. Over them, for every zone of a kind, and over those, for one zone:');
    say('/vis city|outdoors|dungeon <setting> <value> - the kind\'s preset; <setting> clear takes it out again, clear alone the whole preset.');
    say('/vis zone <setting> <value> - this zone\'s own; <setting> clear takes it out, clear alone all of them; zone list is every zone with its own.');
    say('/vis callers - every call to the scale function, for the record (also in config/addons/vis/callers.txt).');
    say('/vis patch <n> <mult> - re-scale caller n by hand; /vis unpatch [n] puts it (or all) back.');
end

local numeric = { world = true, entity = true, fog = true, objects = true, detail = true };

-- A numeric setting's range: its least and its most.
local function limits(k)
    if (k == 'objects' or k == 'detail') then return 0, 100; end
    return 0.1, 100;
end
local toggles = { terrain = true };

local function inRange(k, v)
    if (numeric[k]) then
        local min, max = limits(k);
        return type(v) == 'number' and v >= min and v <= max;
    end
    return type(v) == 'boolean';
end

-- The general values: every one a number or boolean in range, else the default.
local function settleGeneral(t)
    for _, k in ipairs(VALUES) do if (not inRange(k, t[k])) then t[k] = defaults[k]; end end
end

-- A layer over them: what is there is kept if in range, dropped otherwise.
local function settleLayer(t)
    for _, k in ipairs(VALUES) do if (t[k] ~= nil and not inRange(k, t[k])) then t[k] = nil; end end
end

-- fov and square saved before 2.0, gone to lens: the lens commands for the general ones, said once at
-- load, and every layer's taken out.
local function moveToLens(s)
    local parts = T{};
    if (type(s.fov) == 'number' and s.fov > 0) then parts:append(('/lens fov %g'):format(s.fov)); end
    if (s.square == true) then parts:append('/lens square on'); end
    local layered = false;
    local function strip(t)
        if (type(t) ~= 'table') then return; end
        if (t.fov ~= nil or t.square ~= nil) then layered = true; end
        t.fov, t.square = nil, nil;
    end
    for _, own in pairs(type(s.zones) == 'table' and s.zones or {}) do strip(own); end
    for _, preset in pairs(type(s.kinds) == 'table' and s.kinds or {}) do strip(preset); end
    local had = s.fov ~= nil or s.square ~= nil or layered;
    s.fov, s.square = nil, nil;
    if (#parts > 0) then
        state.moved = ('fov and square are the lens plugin\'s now; to keep yours: %s.%s'):format(table.concat(parts, ', '),
            layered and ' A zone\'s or preset\'s own fov or square is no more.' or '');
    elseif (layered) then
        state.moved = 'fov and square are the lens plugin\'s now; a zone\'s or preset\'s own fov or square is no more.';
    end
    return had;
end

-- vis, the terrain setting's name before 2.1, as terrain, in every layer; true when one was there.
local function renameVis(s)
    local had = false;
    local function rename(t)
        if (type(t) ~= 'table' or t.vis == nil) then return; end
        if (t.terrain == nil) then t.terrain = t.vis; end
        t.vis, had = nil, true;
    end
    rename(s);
    for _, own in pairs(type(s.zones) == 'table' and s.zones or {}) do rename(own); end
    for _, preset in pairs(type(s.kinds) == 'table' and s.kinds or {}) do rename(preset); end
    return had;
end

-- This character's drawscale settings (or drawscale's defaults when no one is logged in), copied over
-- vis's own file for them: the addon was drawscale until 2.1. Each file is looked for once a session, so
-- the reload that follows a copy does not copy again. True when copied.
local adopting = {};
local function adoptDrawscale()
    local ok, dir = pcall(settings.settings_path);
    if (not ok or type(dir) ~= 'string') then return false; end
    local new = dir .. 'settings.lua';
    if (adopting[new]) then return false; end
    adopting[new] = true;
    local old = (dir:gsub('\\addons\\vis\\', '\\addons\\drawscale\\', 1)) .. 'settings.lua';
    if (old == new) then return false; end
    local f = io.open(old, 'rb');
    if (f == nil) then return false; end
    local text = f:read('*a');
    f:close();
    if (ashita.fs.create_dir) then ashita.fs.create_dir(dir); end
    local out = io.open(new, 'wb');
    if (out == nil) then return false; end
    out:write(text);
    out:close();
    state.adopted = true;
    return true;
end

local function settle(s)
    if (s ~= nil) then state.settings = s; end
    if (state.settings == nil) then state.settings = T{}; end
    s = state.settings;
    local changed = moveToLens(s);
    if (renameVis(s)) then changed = true; end
    if (s.adopted ~= true) then s.adopted, changed = true, true; end
    -- terrain was on by default until 2.2 and saved so; off once, as the default is now
    if (s.terrainOff ~= true) then
        if (s.terrain == true) then s.terrain, state.terrainOff = false, true; end
        s.terrainOff, changed = true, true;
    end
    if (changed) then settings.save(); end
    settleGeneral(s);
    if (type(s.zones) ~= 'table') then s.zones = T{}; end
    for id, own in pairs(s.zones) do
        if (type(own) ~= 'table' or tonumber(id) == nil) then s.zones[id] = nil; else settleLayer(own); end
    end
    if (type(s.kinds) ~= 'table') then s.kinds = T{}; end
    for kind in pairs(KINDS) do
        if (type(s.kinds[kind]) ~= 'table') then s.kinds[kind] = T{}; end
        settleLayer(s.kinds[kind]);
    end
    if (s.seeded ~= true) then
        for kind, seed in pairs(SEED) do
            for k, v in pairs(seed) do if (s.kinds[kind][k] == nil) then s.kinds[kind][k] = v; end end
        end
        s.seeded = true;
    end
    resolve();
end

-- Sets key in a layer from the command's text: a number or on|off, or clear to take it out of a
-- layer over the general values. name says which layer, for the usage line.
local function setIn(layer, name, key, text)
    local v;
    if (text ~= nil and text:lower() == 'clear' and layer ~= state.settings) then
        v = nil;
    elseif (numeric[key]) then
        v = tonumber(text);
        if (not inRange(key, v)) then
            local min, max = limits(key);
            fail(('Usage: /vis %s%s <n>, n from %s to %g%s.'):format(name, key, min == 0 and '0 (same as world)' or ('%g'):format(min), max,
                layer ~= state.settings and ', or clear' or ''));
            return false;
        end
    else
        if (text == nil) then v = not (active()[key] == true);
        elseif (text:lower() == 'on') then v = true;
        elseif (text:lower() == 'off') then v = false;
        else fail(('Usage: /vis %s%s on|off%s'):format(name, key, layer ~= state.settings and '|clear' or '')); return false; end
    end
    layer[key] = v;
    settings.save();
    apply();
    return true;
end

-- The zone the player has come into: the values for it into the game.
local function enterZone(id)
    if (id == nil or id == 0 or id == state.zone) then return; end
    state.zone = id;
    state.kind = zoneKinds[id];
    apply();
    local own, kind = layerText(ownValues()), layerText(kindValues());
    if (own or kind) then
        say(('%s: %s%s'):format(zoneName(id), own and (('its own %s'):format(own)) or '', kind and ((own and '; ' or '') .. ('%s %s'):format(KIND_PRESET[state.kind], kind)) or ''));
    end
end

-- /vis zone [<setting> <value>|<setting> clear|clear|list]
local function zoneCommand(what, value)
    what = (what or ''):lower();
    local s = state.settings;
    if (what == 'list') then
        local ids = T{};
        for id, own in pairs(s.zones) do if (layerText(own)) then ids:append(tonumber(id)); end end
        if (#ids == 0) then say('No zone has values of its own.'); return; end
        ids:sort();
        for _, id in ipairs(ids) do
            local kind = zoneKinds[id];
            say(('%s (%d, %s): %s.'):format(zoneName(id), id, kind and KINDS[kind] or 'of no known kind', layerText(s.zones[tostring(id)])));
        end
        return;
    end
    if (what == '') then status(); return; end
    if (state.zone == 0) then fail('No zone known yet; try once you are in the world.'); return; end
    local key = tostring(state.zone);
    if (what == 'clear') then
        s.zones[key] = nil;
        settings.save();
        apply();
        say(('%s has nothing of its own now.'):format(zoneName(state.zone)));
        status();
        return;
    end
    if (not numeric[what] and not toggles[what]) then fail('Usage: /vis zone <setting> <value>|clear, /vis zone clear, or /vis zone list.'); return; end
    if (s.zones[key] == nil) then s.zones[key] = T{}; end
    if (setIn(s.zones[key], 'zone ', what, value)) then
        if (layerText(s.zones[key]) == nil) then s.zones[key] = nil; end
        status();
    end
end

-- /vis city|outdoors|dungeon [<setting> <value>|<setting> clear|clear]
local function kindCommand(kind, what, value)
    what = (what or ''):lower();
    local preset = state.settings.kinds[kind];
    local function show()
        local text = layerText(preset);
        if (text) then say(('%s: %s; the rest from the general values.'):format(KIND_PRESET[kind]:gsub('^%l', string.upper), text));
        else say(('%s holds nothing; %s draws with the general values.'):format(KIND_PRESET[kind]:gsub('^%l', string.upper), kind == 'outdoors' and 'the outdoors' or ('every ' .. kind))); end
    end
    if (what == '') then show(); return; end
    if (what == 'clear') then
        for _, k in ipairs(VALUES) do preset[k] = nil; end
        settings.save();
        apply();
        show();
        return;
    end
    if (not numeric[what] and not toggles[what]) then fail(('Usage: /vis %s <setting> <value>|clear, or /vis %s clear.'):format(kind, kind)); return; end
    if (setIn(preset, kind .. ' ', what, value)) then
        show();
        if (state.kind == kind) then status(); end
    end
end

-- Every event goes through here. Ashita unloads an addon whose event errors without running its unload
-- event, which would leave the game patched with nothing to put it back (as 1.6 did, 2026-10-21, when
-- its FFI casts filled LuaJIT's table); so an error is said once, the addon stays, and unloading still
-- restores everything.
local function guarded(name, fn)
    local said = false;
    return function (...)
        local ok, err = pcall(fn, ...);
        if (not ok and not said) then
            said = true;
            fail(('The %s event failed (said once; vis keeps going): %s'):format(name, tostring(err)));
        end
    end
end

-- What a load or a change of character found to say: drawscale's settings brought over, and fov and
-- square gone to lens, and terrain turned off. Each said once.
local function sayNotes()
    if (state.adopted) then
        say('Your drawscale settings are vis\'s now. vis replaces drawscale: take /addon load drawscale out of your startup script.');
        state.adopted = nil;
    end
    if (state.moved) then say(state.moved); state.moved = nil; end
    if (state.terrainOff) then
        say('terrain is off now, the default from vis 2.2: it costs frames in big zones and the fog hides most of it. /vis terrain on brings it back.');
        state.terrainOff = nil;
    end
end

settings.register('settings', 'settings_update', guarded('settings', function (s)
    -- a character new to vis: their drawscale settings copied over and read again, which comes back here
    if (type(s) == 'table' and s.adopted ~= true and settings.reload ~= nil and adoptDrawscale()) then settings.reload(); return; end
    settle(s);
    apply();
    sayNotes();
end));

ashita.events.register('load', 'load_cb', guarded('load', function ()
    -- the first load for this character: drawscale's settings in place before vis's are read
    local okPath, dir = pcall(settings.settings_path);
    if (okPath and type(dir) == 'string' and not ashita.fs.exists(dir .. 'settings.lua')) then adoptDrawscale(); end
    settle(settings.load(defaults));
    state.zone = zoneFromGame() or 0;
    state.kind = state.zone ~= 0 and zoneKinds[state.zone] or nil;
    if (rescan()) then
        report(false);
        apply();
        status();
    end
    sayNotes();
end));

ashita.events.register('unload', 'unload_cb', guarded('unload', function ()
    for n in pairs(state.patches) do unpatchCaller(n); end
    if (state.detail ~= nil) then detail.restore(mem, state.detail); end
    if (state.view ~= nil) then view.restore(mem, state.view); end
    if (state.fn ~= 0) then
        ashita.memory.write_float(state.world, 1.0);
        ashita.memory.write_float(state.entity, 1.0);
    end
    -- The stubs stay allocated: the render thread may be inside one as we go.
end));

ashita.events.register('d3d_present', 'present_cb', guarded('d3d_present', function ()
    -- the ratios follow the world multiplier, which something else (drawdistance) may write; every
    -- change of setting or stub runs applyRatios itself, so a frame only looks at the float
    if (next(state.patches) ~= nil and state.world ~= 0) then
        local world = ashita.memory.read_float(state.world);
        if (world ~= state.ratioWorld) then applyRatios(world); end
    end
end));

-- The zone-in packet carries the zone's id at 0x30.
ashita.events.register('packet_in', 'packet_in_cb', guarded('packet_in', function (e)
    if (e.id ~= 0x00A or type(e.data) ~= 'string' or #e.data < 0x32) then return; end
    local lo, hi = e.data:byte(0x31, 0x32);
    enterZone(lo + hi * 256);
end));

ashita.events.register('command', 'command_cb', guarded('command', function (e)
    local args = e.command:args();
    if (#args == 0 or args[1] ~= '/vis') then return; end
    e.blocked = true;
    local verb = (args[2] or ''):lower();
    if (verb == '') then
        status();
    elseif (numeric[verb]) then
        if (args[3] == nil) then status(); elseif (setIn(state.settings, '', verb, args[3])) then status(); end
    elseif (toggles[verb]) then
        if (setIn(state.settings, '', verb, args[3])) then status(); end
    elseif (verb == 'zone') then
        zoneCommand(args[3], args[4]);
    elseif (KINDS[verb]) then
        kindCommand(verb, args[3], args[4]);
    elseif (verb == 'callers') then
        if (state.fn == 0) then rescan(); end
        if (state.fn ~= 0) then report(true); end
    elseif (verb == 'scan') then
        for n in pairs(state.patches) do unpatchCaller(n); end
        if (state.detail ~= nil) then detail.restore(mem, state.detail); state.detailMem = 0; end
        if (state.view ~= nil) then view.restore(mem, state.view); end
        if (rescan()) then report(true); apply(); end
    elseif (verb == 'fov' or verb == 'square') then
        say(('%s is the lens plugin\'s now: /lens %s%s.'):format(verb, verb, verb == 'fov' and ' <n>, or /lens middle <n> to keep the middle as the warp changes' or ' on|off'));
    elseif (verb == 'patch') then
        local n, mult = tonumber(args[3]), tonumber(args[4]);
        if (n == nil or mult == nil or mult <= 0) then fail('Usage: /vis patch <n> <mult>'); return; end
        if (patchCaller(n, mult)) then say(('#%d goes through a stub now: x%.2f of stock, whatever the world multiplier.'):format(n, mult)); end
    elseif (verb == 'unpatch') then
        local n = tonumber(args[3]);
        if (n ~= nil) then
            if (unpatchCaller(n)) then say(('#%d is back to normal.'):format(n)); else fail(('#%d was not patched.'):format(n)); end
        else
            local count = 0;
            for k in pairs(state.patches) do if (unpatchCaller(k)) then count = count + 1; end end
            say(('%d caller(s) back to normal.'):format(count));
        end
        apply();
    else
        help();
    end
end));
