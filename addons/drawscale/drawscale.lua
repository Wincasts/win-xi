addon.name    = 'drawscale';
addon.author  = 'win';
addon.version = '1.2';
addon.desc    = 'World and entity draw distance with the fog kept where you want it: three multipliers, saved per character.';
addon.link    = 'https://github.com/Wincasts/win-xi';

--[[
The client multiplies its far clip, fog, zone-object ranges and entity cull distance by two floats,
world and entity, which the drawdistance addon sets; every distance asks one small function for the
scale. The fog asks it twice, for its start and its end, from a function just before it. This addon
sets the two floats and sends the fog's two calls through a stub that multiplies their answer by
fog / world, so the fog sits at fog times stock whatever the world multiplier is. A fog of 1 with a
world of 2 is stock fog in front of twice the terrain.

The finding is done in the running game: the client DLL is packed on disk. The scale function is
found by drawdistance's bytes, its entry by the calls to it, and the fog's calls by their shape: in
the function before, pushing the world selector, multiplying by the answer. /drawscale callers lists
every call for the record, and /drawscale patch <n> <mult> still re-scales any one of them by number.
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
    vis     = true,   -- draw distant terrain the zone's visibility lists would hide
    square  = false,  -- the world at the window's true proportions
};

local state = T{
    settings = nil,
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
    view     = nil,    -- the visibility-list site and the game pointer, from view.find
};

-- The client's memory, as the detail and view modules see it.
local mem = {
    find = function (pattern) return ashita.memory.find(0, 0, pattern, 0, 0); end,
    read = function (addr, n) return ashita.memory.read_array(addr, n); end,
    read_u32 = function (addr) return ashita.memory.read_uint32(addr); end,
    write = nil, -- writeBytes, below
    write_u32 = function (addr, v) ashita.memory.write_uint32(addr, v); end,
    write_float = function (addr, v) ashita.memory.write_float(addr, v); end,
    alloc = function (n) return ashita.memory.alloc(n) or 0; end,
};

local function say(s)
    if (chat) then print(chat.header(addon.name):append(chat.message(s))); else print('[drawscale] ' .. s); end
end
local function fail(s)
    if (chat) then print(chat.header(addon.name):append(chat.error(s))); else print('[drawscale] error: ' .. s); end
end

local function reportPath()
    local dir = ('%s\\config\\addons\\drawscale\\'):format(AshitaCore:GetInstallPath());
    if (ashita.fs and ashita.fs.create_directory) then ashita.fs.create_directory(dir); end
    return dir .. 'callers.txt';
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
    lines:append(('detail: %d of %d sites; vis site %s; game pointer %s'):format(
        state.detail and #state.detail.sites or 0, #detail.PATTERNS,
        (state.view and state.view.visSite ~= 0) and 'found' or 'not found', (state.view and state.view.gamePointer ~= 0) and 'found' or 'not found'));
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
        say('Details are in config/addons/drawscale/callers.txt.');
    end
    local f = io.open(reportPath(), 'w');
    if (f) then
        f:write(('drawscale %s, %s\n'):format(addon.version, os.date('%Y-%m-%d %H:%M:%S')));
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
local function objectsValue() local s = state.settings; return (s.objects ~= nil and s.objects > 0) and s.objects or s.world; end
local function detailValue() local s = state.settings; return (s.detail ~= nil and s.detail > 0) and s.detail or s.world; end

-- Keeps each stub's ratio right for the world multiplier as it is now: a manual patch wants
-- mult x stock, the fog wants the fog setting x stock, and the object range wants its setting
-- squared, since the client compares squared distances against it.
local function applyRatios()
    if (next(state.patches) == nil or state.world == 0) then return; end
    local world = ashita.memory.read_float(state.world);
    for _, p in pairs(state.patches) do
        local mult = p.fog and state.settings.fog or p.objects and (objectsValue() ^ 2) or p.mult;
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
-- their stubs, the mesh-detail factor, the visibility lists, and the projection constant.
local function apply()
    if (state.fn == 0 or state.settings == nil) then return; end
    local s = state.settings;
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
    if (state.view ~= nil) then
        view.setVis(mem, state.view, s.vis ~= false);
        view.setSquare(mem, state.view, s.square == true);
    end
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
        fail('The fog\'s two calls were not recognised; world and entity work, the fog setting does not. /drawscale callers shows what was found.');
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
    if (state.view.gamePointer == 0) then fail('The game pointer was not found; square is unavailable.'); end
    return true;
end

local function status()
    local s = state.settings or defaults;
    local fogState = #state.fogSites == 2 and '' or ' (fog calls not found)';
    local objectsState = state.objectSite and '' or ' (range call not found)';
    say(('world x%.2f, entity x%.2f, fog x%.2f%s of stock.'):format(s.world, s.entity, s.fog, fogState));
    say(('objects x%.2f%s%s, detail x%.2f%s, vis %s, square %s.'):format(
        objectsValue(), (s.objects == nil or s.objects <= 0) and ' (same as world)' or '', objectsState,
        detailValue(), (s.detail == nil or s.detail <= 0) and ' (same as world)' or '',
        s.vis ~= false and 'on' or 'off', s.square == true and 'on' or 'off'));
end

local function help()
    say('/drawscale - the current values.');
    say('/drawscale world <n> - terrain, objects and far clip: n times stock (1 = stock).');
    say('/drawscale entity <n> - players, NPCs and mobs: n times stock. The server sends entities within about 50 yalms.');
    say('/drawscale fog <n> - the fog: n times stock, whatever world is. 1 keeps the stock fog.');
    say('/drawscale objects <n> - buildings, trees and props: n times stock. 0 = the same as world.');
    say('/drawscale detail <n> - how much further objects keep their detailed mesh. 0 = the same as world.');
    say('/drawscale vis on|off - on: draw distant terrain the zone would hide from your area. off: stock.');
    say('/drawscale square on|off - on: the world at the window\'s true proportions. off: stock.');
    say('/drawscale callers - every call to the scale function, for the record (also in config/addons/drawscale/callers.txt).');
    say('/drawscale patch <n> <mult> - re-scale caller n by hand; /drawscale unpatch [n] puts it (or all) back.');
end

local numeric = { world = true, entity = true, fog = true, objects = true, detail = true };
local toggles = { vis = true, square = true };

local function settle(s)
    if (s ~= nil) then state.settings = s; end
    if (state.settings == nil) then state.settings = T{}; end
    for k, v in pairs(defaults) do
        if (numeric[k]) then
            local min = (k == 'objects' or k == 'detail') and 0 or 0.1;
            if (type(state.settings[k]) ~= 'number' or state.settings[k] < min or state.settings[k] > 100) then state.settings[k] = v; end
        elseif (type(state.settings[k]) ~= 'boolean') then
            state.settings[k] = v;
        end
    end
end

local function setValue(key, text)
    local v = tonumber(text);
    local min = (key == 'objects' or key == 'detail') and 0 or 0.1;
    if (v == nil or v < min or v > 100) then fail(('Usage: /drawscale %s <n>, n from %s to 100.'):format(key, min == 0 and '0 (same as world)' or '0.1')); return; end
    state.settings[key] = v;
    settings.save();
    apply();
    status();
end

local function setToggle(key, text)
    local on;
    if (text == nil) then on = not (state.settings[key] == true);
    elseif (text:lower() == 'on') then on = true;
    elseif (text:lower() == 'off') then on = false;
    else fail(('Usage: /drawscale %s on|off'):format(key)); return; end
    state.settings[key] = on;
    settings.save();
    apply();
    status();
end

settings.register('settings', 'settings_update', function (s)
    settle(s);
    apply();
end);

ashita.events.register('load', 'load_cb', function ()
    settle(settings.load(defaults));
    if (rescan()) then
        report(false);
        apply();
        status();
    end
end);

ashita.events.register('unload', 'unload_cb', function ()
    for n in pairs(state.patches) do unpatchCaller(n); end
    if (state.detail ~= nil) then detail.restore(mem, state.detail); end
    if (state.view ~= nil) then view.restore(mem, state.view); end
    if (state.fn ~= 0) then
        ashita.memory.write_float(state.world, 1.0);
        ashita.memory.write_float(state.entity, 1.0);
    end
    -- The stubs stay allocated: the render thread may be inside one as we go.
end);

ashita.events.register('d3d_present', 'present_cb', function ()
    applyRatios();
    -- the game object may not exist at load; the constant is set once it does, and kept
    if (state.view ~= nil and state.settings ~= nil) then view.setSquare(mem, state.view, state.settings.square == true); end
end);

ashita.events.register('command', 'command_cb', function (e)
    local args = e.command:args();
    if (#args == 0 or args[1] ~= '/drawscale') then return; end
    e.blocked = true;
    local verb = (args[2] or ''):lower();
    if (verb == '') then
        status();
    elseif (numeric[verb]) then
        if (args[3] == nil) then status(); else setValue(verb, args[3]); end
    elseif (toggles[verb]) then
        setToggle(verb, args[3]);
    elseif (verb == 'callers') then
        if (state.fn == 0) then rescan(); end
        if (state.fn ~= 0) then report(true); end
    elseif (verb == 'scan') then
        for n in pairs(state.patches) do unpatchCaller(n); end
        if (state.detail ~= nil) then detail.restore(mem, state.detail); state.detailMem = 0; end
        if (state.view ~= nil) then view.restore(mem, state.view); end
        if (rescan()) then report(true); apply(); end
    elseif (verb == 'patch') then
        local n, mult = tonumber(args[3]), tonumber(args[4]);
        if (n == nil or mult == nil or mult <= 0) then fail('Usage: /drawscale patch <n> <mult>'); return; end
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
end);
