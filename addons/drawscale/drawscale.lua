addon.name    = 'drawscale';
addon.author  = 'win';
addon.version = '0.1';
addon.desc    = 'Lists every place the client scales a distance by the draw distance, and lets one of them be re-scaled on its own, to find where the fog is set.';
addon.link    = 'https://github.com/Wincasts/win-xi';

--[[
A diagnostic. The client multiplies its far clip, fog, zone-object ranges and entity cull distance by
two floats, world and entity, which the drawdistance and drawcull addons set; they all go through one
small function. This addon finds that function, scans the client's code for every call to it, and
says what each caller hands it and does with the answer, in the chat and in
config/addons/drawscale/callers.txt. Then /drawscale patch <n> <mult> sends caller n through a stub
that multiplies its answer by mult / world, so that one distance sits at mult times stock while the
world multiplier stays where drawdistance put it. Unloading puts every call back.
--]]

require 'common';
local scan = require('scan');

local ok, chat = pcall(require, 'chat');
if (not ok) then chat = nil; end

local PATTERN   = '8BC1487408D80D'; -- mov eax, ecx; dec eax; jz +8; fmul dword [world]
local REACH     = 16;               -- a call may land this far before the pattern (a prologue)
local CHUNK     = 16384;
local MAX_STUBS = 8;

local state = T{
    fn      = 0,      -- the scale function, where the pattern matched
    world   = 0,      -- address of the world multiplier float
    entity  = 0,      -- address of the entity multiplier float
    callers = T{},    -- { address, delta, info, before, after }
    mem     = 0,      -- the stubs
    patches = T{},    -- caller index -> { site, backup, stub, mult, ratio }
    report  = T{},    -- the lines last printed
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

-- The executable sections of a module in memory, from its PE header: { address, size }.
local function codeSections(base)
    local sections = T{};
    local peOk, pe = pcall(ashita.memory.read_uint32, base + 0x3C);
    if (not peOk or pe == 0 or pe > 0x1000) then return sections; end
    local header = base + pe;
    local count = ashita.memory.read_uint16(header + 6);
    local optional = ashita.memory.read_uint16(header + 20);
    local first = header + 24 + optional;
    for i = 0, count - 1 do
        local s = first + i * 40;
        local vsize = ashita.memory.read_uint32(s + 8);
        local va = ashita.memory.read_uint32(s + 12);
        local flags = ashita.memory.read_uint32(s + 36);
        if (bit.band(flags, 0x20000000) ~= 0 and vsize > 0) then
            sections:append({ address = base + va, size = vsize });
        end
    end
    return sections;
end

-- Every call to the scale function in the client's code.
local function findCallers()
    local base = ashita.memory.get_base('FFXiMain.dll');
    local size = ashita.memory.get_size('FFXiMain.dll');
    if (base == nil or base == 0) then
        fail('FFXiMain.dll is not loaded; nothing to scan.');
        return T{};
    end
    local sections = codeSections(base);
    if (#sections == 0) then sections:append({ address = base, size = size }); end
    local found = T{};
    for _, section in ipairs(sections) do
        local at = section.address;
        local stop = section.address + section.size;
        while (at < stop) do
            local count = math.min(CHUNK, stop - at);
            -- a few bytes past the chunk let a call that begins at its end be read whole; a chunk at the
            -- very end of readable memory is read without them
            local readOk, bytes = pcall(ashita.memory.read_array, at, count + 8);
            if (not (readOk and type(bytes) == 'table')) then
                readOk, bytes = pcall(ashita.memory.read_array, at, count);
            end
            if (readOk and type(bytes) == 'table') then
                for _, hit in ipairs(scan.callers(bytes, at, state.fn, count, REACH)) do
                    found:append(hit);
                end
            end
            at = at + CHUNK;
        end
    end
    return found;
end

local function describeCallers()
    for _, c in ipairs(state.callers) do
        local okBefore, before = pcall(ashita.memory.read_array, c.address - 24, 24);
        local okAfter, after = pcall(ashita.memory.read_array, c.address + 5, 24);
        c.before = okBefore and before or {};
        c.after = okAfter and after or {};
        c.info = scan.describe(c.before, c.after);
    end
end

local function lineFor(n, c)
    local info = c.info or {};
    local what = '';
    if (info.sink and info.sink:match('ebp%+0x39428')) then what = '  <- zone-object range (drawcull patches this one)'; end
    local patched = state.patches[n];
    local mark = patched and (('  [patched x%.2f]'):format(patched.mult)) or '';
    return ('#%d 0x%08X %s%s | ecx %s, pushes %s, then %s%s%s'):format(
        n, c.address, info.selector or '?', c.delta ~= 0 and ((' (call lands %d before the pattern)'):format(c.delta)) or '',
        tostring(info.ecx == nil and '?' or info.ecx), info.push or '?', info.sink or (info.after and info.after[1]) or '?', what, mark);
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
    lines:append(('scale function 0x%08X; world x%.2f at 0x%08X; entity x%.2f at 0x%08X; %d callers'):format(
        state.fn, world, state.world, entity, state.entity, #state.callers));
    for n, c in ipairs(state.callers) do
        lines:append(lineFor(n, c));
        lines:append(detailFor(c));
    end
    state.report = lines;
    if (toChat) then
        say(lines[1]);
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

local function rescan()
    state.fn = ashita.memory.find(0, 0, PATTERN, 0, 0);
    if (state.fn == 0) then
        fail('The scale function was not found; is this the usual client?');
        state.callers = T{};
        return false;
    end
    state.world = ashita.memory.read_uint32(state.fn + 0x07);
    state.entity = ashita.memory.read_uint32(state.fn + 0x0F);
    state.callers = findCallers();
    describeCallers();
    return true;
end

local function writeBytes(addr, bytes)
    local unOk, prot = ashita.memory.unprotect(addr, #bytes);
    if (not unOk) then return false; end
    ashita.memory.write_array(addr, bytes);
    ashita.memory.protect(addr, #bytes, prot);
    return true;
end

local function applyRatios()
    if (next(state.patches) == nil) then return; end
    local world = ashita.memory.read_float(state.world);
    for _, p in pairs(state.patches) do
        local ratio = scan.ratio(p.mult, world);
        if (ratio ~= p.ratio) then
            p.ratio = ratio;
            ashita.memory.write_float(p.stub + scan.RATIO_OFFSET, ratio);
        end
    end
end

local function patchCaller(n, mult)
    local c = state.callers[n];
    if (c == nil) then fail(('There is no caller #%d.'):format(n)); return; end
    local existing = state.patches[n];
    if (existing) then
        existing.mult = mult;
        existing.ratio = nil;
        applyRatios();
        say(('#%d now at x%.2f of stock.'):format(n, mult));
        return;
    end
    local used = 0;
    for _ in pairs(state.patches) do used = used + 1; end
    if (used >= MAX_STUBS) then fail(('Only %d callers can be patched at once.'):format(MAX_STUBS)); return; end
    if (state.mem == 0) then
        state.mem = ashita.memory.alloc(scan.STUB_SIZE * MAX_STUBS);
        if (state.mem == nil or state.mem == 0) then state.mem = 0; fail('Could not allocate memory for the stub.'); return; end
    end
    local slot;
    for i = 0, MAX_STUBS - 1 do
        local taken = false;
        for _, p in pairs(state.patches) do if (p.slot == i) then taken = true; end end
        if (not taken) then slot = i; break; end
    end
    local stub = state.mem + slot * scan.STUB_SIZE;
    local target = (c.address + 5 + ashita.memory.read_int32(c.address + 1)) % 4294967296;
    ashita.memory.write_array(stub, scan.stub(stub, target));
    ashita.memory.write_float(stub + scan.RATIO_OFFSET, 1.0);
    local site = c.address + 1;
    local backup = ashita.memory.read_array(site, 4);
    if (not writeBytes(site, scan.rel32(c.address, stub))) then fail('Could not write the call.'); return; end
    state.patches[n] = { site = site, backup = backup, stub = stub, slot = slot, mult = mult, ratio = nil };
    applyRatios();
    say(('#%d goes through a stub now: x%.2f of stock, whatever the world multiplier.'):format(n, mult));
end

local function unpatchCaller(n)
    local p = state.patches[n];
    if (p == nil) then return false; end
    writeBytes(p.site, p.backup);
    state.patches[n] = nil;
    return true;
end

local function help()
    say('/drawscale - the callers of the draw-distance scale function, again.');
    say('/drawscale scan - find them afresh.');
    say('/drawscale patch <n> <mult> - send caller n through a stub so its distance is mult x stock (1 = stock).');
    say('/drawscale unpatch [n] - put caller n (or all of them) back.');
end

ashita.events.register('load', 'load_cb', function ()
    if (rescan()) then report(true); end
end);

ashita.events.register('unload', 'unload_cb', function ()
    for n in pairs(state.patches) do unpatchCaller(n); end
    -- The stubs stay allocated: the render thread may be inside one as we go.
end);

ashita.events.register('d3d_present', 'present_cb', function ()
    applyRatios();
end);

ashita.events.register('command', 'command_cb', function (e)
    local args = e.command:args();
    if (#args == 0 or args[1] ~= '/drawscale') then return; end
    e.blocked = true;
    local verb = (args[2] or ''):lower();
    if (verb == '' ) then
        if (state.fn == 0) then rescan(); end
        if (state.fn ~= 0) then report(true); end
    elseif (verb == 'scan') then
        if (rescan()) then report(true); end
    elseif (verb == 'patch') then
        local n, mult = tonumber(args[3]), tonumber(args[4]);
        if (n == nil or mult == nil or mult <= 0) then fail('Usage: /drawscale patch <n> <mult>'); return; end
        patchCaller(n, mult);
    elseif (verb == 'unpatch') then
        local n = tonumber(args[3]);
        if (n ~= nil) then
            if (unpatchCaller(n)) then say(('#%d is back to normal.'):format(n)); else fail(('#%d was not patched.'):format(n)); end
        else
            local count = 0;
            for k in pairs(state.patches) do if (unpatchCaller(k)) then count = count + 1; end end
            say(('%d caller(s) back to normal.'):format(count));
        end
    else
        help();
    end
end);
