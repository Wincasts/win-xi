-- winxi.perf: how long each of this addon's event handlers takes, for the perf addon to show.
--
-- Required once before the addon registers its events (winxi.shell does it), it wraps
-- ashita.events.register so that every handler registered after it is timed with the game's
-- performance counter, and adds up the calls, the time and the longest call for each kind of event:
-- d3d_present, packet_in, packet_out, text_in, command, input (key, key_data, key_state, mouse,
-- dinput_button and xinput_button) and the rest. The sums go into a block of shared memory that every
-- addon in the game maps (Local\winxi-perf-1), one row an addon, and the perf addon reads them all;
-- where there is no such memory (outside the game) they stay in a table of this state's own, and
-- Rows() reads that. CPU time inside the handler only: the imgui lists an addon builds are drawn
-- later by Ashita, and the GPU's time is nowhere in it.
--
--     local perf = require('winxi.perf');
--     perf.Events          -- the slots' names, in order: d3d_present, packet_in, packet_out, text_in, command, input, other
--     perf.Rows()          -- every addon's row: { name, touched, generation, events = { { calls, us, maxus }, ... } }
--     perf.ResetMax()      -- every row's longest call set back to zero
--     perf.Active          -- whether this addon's handlers are being timed
--     perf.Shared          -- whether the rows are in shared memory (false: this state's own table)
local M = {}

M.Events = { 'd3d_present', 'packet_in', 'packet_out', 'text_in', 'command', 'input', 'other' };
local SLOTS = 8;
local ROWS = 64;
local MAGIC = 'WINXIPRF';
local VERSION = 1;
local NAME = 'Local\\winxi-perf-1';
local slotOf = { d3d_present = 1, packet_in = 2, packet_out = 3, text_in = 4, command = 5,
                 key = 6, key_data = 6, key_state = 6, mouse = 6, dinput_button = 6, xinput_button = 6 };

M.Active, M.Shared = false, false;

local okFfi, ffi = pcall(require, 'ffi');
local block, handle, view, row, rows;     -- the shared block and this addon's row in it; or the local rows

if okFfi then
    pcall(ffi.cdef, [[
        typedef struct { uint32_t calls; uint32_t maxus; uint64_t us; } winxi_perf_event_t;
        typedef struct { char name[32]; uint32_t generation; uint32_t touched; winxi_perf_event_t events[8]; } winxi_perf_row_t;
        typedef struct { char magic[8]; uint32_t version; uint32_t rows; winxi_perf_row_t row[64]; } winxi_perf_block_t;
    ]]);
    pcall(ffi.cdef, 'void* __stdcall CreateFileMappingA(void* file, void* attributes, uint32_t protect, uint32_t sizeHigh, uint32_t sizeLow, const char* name);');
    pcall(ffi.cdef, 'void* __stdcall MapViewOfFile(void* mapping, uint32_t access, uint32_t offsetHigh, uint32_t offsetLow, size_t size);');
    pcall(ffi.cdef, 'int __stdcall UnmapViewOfFile(const void* address);');
    pcall(ffi.cdef, 'int __stdcall CloseHandle(void* handle);');
end

local function ZeroEvents(target)
    for i = 0, SLOTS - 1 do target.events[i].calls, target.events[i].maxus, target.events[i].us = 0, 0, 0; end
end

-- The row for this addon: the one of its name (loaded before), or the first free; its sums start over
local function Claim(name)
    local free;
    for i = 0, ROWS - 1 do
        local candidate = block.row[i];
        if ffi.string(candidate.name) == name then free = candidate; break; end
        if not free and candidate.name[0] == 0 then free = candidate; end
    end
    if not free then return nil; end
    ffi.fill(free.name, 32);
    ffi.copy(free.name, name:sub(1, 31));
    ZeroEvents(free);
    free.generation = free.generation + 1;
    free.touched = 0;
    return free;
end

local function MapShared()
    if not okFfi or type(addon) ~= 'table' or type(addon.name) ~= 'string' then return false; end
    local okLib, kernel = pcall(ffi.load, 'kernel32');
    if not okLib or not pcall(function() return ffi.sizeof('winxi_perf_block_t'); end) then return false; end
    local size = ffi.sizeof('winxi_perf_block_t');
    local ok = pcall(function()
        local invalid = ffi.cast('void*', ffi.new('uintptr_t', 0) - 1);   -- INVALID_HANDLE_VALUE: the page file backs it
        handle = kernel.CreateFileMappingA(invalid, nil, 0x04, 0, size, NAME);
        if handle == nil then error('no mapping'); end
        view = kernel.MapViewOfFile(handle, 0x000F001F, 0, 0, size);
        if view == nil then kernel.CloseHandle(handle); handle = nil; error('no view'); end
        block = ffi.cast('winxi_perf_block_t*', view);
        if ffi.string(block.magic, 8) ~= MAGIC then
            ffi.fill(block, size);
            ffi.copy(block.magic, MAGIC, 8);
            block.version, block.rows = VERSION, ROWS;
        end
        row = Claim(addon.name);
        if not row then error('no row free'); end
    end);
    if not ok then block, row = nil, nil; end
    return ok;
end

local function LocalRow(name)
    local events = {};
    for i = 1, SLOTS do events[i] = { calls = 0, us = 0, maxus = 0 }; end
    return { name = name, touched = 0, generation = 1, events = events };
end

M.Shared = MapShared();
if not M.Shared then
    rows = {};
    row = LocalRow(type(addon) == 'table' and addon.name or '?');
    rows[1] = row;
end

local frequency = 1;
local function Now() return tonumber(ashita.time.qpc().q); end
pcall(function() frequency = tonumber(ashita.time.qpf().q) or 1; end);
if frequency == 0 then frequency = 1; end

local function Add(slot, before)
    local took = (Now() - before) * 1000000 / frequency;
    if took < 0 then took = 0; end
    local event = M.Shared and row.events[slot - 1] or row.events[slot];
    event.calls = event.calls + 1;
    event.us = event.us + took;
    if took > event.maxus then event.maxus = took; end
    row.touched = math.floor(before / frequency);
end

local function Clear()
    if M.Shared then
        if row then ffi.fill(row.name, 32); ZeroEvents(row); row.touched = 0; end
    else
        for i = 1, SLOTS do row.events[i].calls, row.events[i].us, row.events[i].maxus = 0, 0, 0; end
        row.touched, row.name = 0, '';
    end
end

-- Wrapping the register: every handler from now on is timed
do
    local events = type(ashita) == 'table' and ashita.events;
    local original = type(events) == 'table' and events.register;
    if type(original) == 'function' then
        local function Wrap(event, fn)
            local slot = slotOf[event] or 7;
            if event == 'unload' then
                return function(...) local before = Now(); local result = fn(...); Add(slot, before); Clear(); return result; end
            end
            return function(...) local before = Now(); local result = fn(...); Add(slot, before); return result; end
        end
        local function Register(event, name, fn, ...)
            if type(fn) ~= 'function' then return original(event, name, fn, ...); end
            return original(event, name, Wrap(event, fn), ...);
        end
        local ok = pcall(function() events.register = Register; end);
        M.Active = ok and events.register == Register;
        if M.Active then pcall(original, 'unload', 'winxi_perf_unload', Clear); end
    end
end

local function Copy(source, shared)
    local events = {};
    for i = 1, SLOTS do
        local event = shared and source.events[i - 1] or source.events[i];
        events[i] = { calls = tonumber(event.calls), us = tonumber(event.us), maxus = tonumber(event.maxus) };
    end
    return { name = shared and ffi.string(source.name) or source.name, touched = tonumber(source.touched), generation = tonumber(source.generation), events = events };
end

function M.Rows()
    local found = {};
    if M.Shared then
        for i = 0, ROWS - 1 do
            local candidate = block.row[i];
            if candidate.name[0] ~= 0 then found[#found + 1] = Copy(candidate, true); end
        end
    else
        for _, candidate in ipairs(rows) do if candidate.name ~= '' then found[#found + 1] = Copy(candidate, false); end end
    end
    return found;
end

function M.ResetMax()
    if M.Shared then
        for i = 0, ROWS - 1 do for s = 0, SLOTS - 1 do block.row[i].events[s].maxus = 0; end end
    else
        for _, candidate in ipairs(rows) do for s = 1, SLOTS do candidate.events[s].maxus = 0; end end
    end
end

-- The game's performance counter in seconds, as the rows' touched is measured
function M.Seconds() return Now() / frequency; end

return M;
