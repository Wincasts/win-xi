-- A recorder for working out how the game says where its party cursor is. Temporary: started and
-- stopped with /xit us debug, it writes what the game's memory holds, each time that changes, to
-- config\addons\xitools\us_cursor.log.
--
-- What is written: the name of the menu on top, the party window's object (the bytes around the
-- cursor us reads at +0x50 and +0x54), the pointers beside the one that leads to it, and what the
-- target says of itself.
local ffxi = require('utils/ffxi')

local recorder = { }

local file = nil
local last = nil
local lines = 0
local maxLines = 6000   -- some of the bytes may never keep still
local objectBytes = 0xC0

-- The game's party frames, found as hideparty finds them: the main party's, the target's, and the two
-- other alliance parties'. Each is a pointer to an object whose +0x08 is the frame itself, and hideparty
-- hides a frame by writing its +0x69 and +0x6A.
local frames = nil

local function Frames()
    if frames == nil then
        frames = { }
        local first = ashita.memory.find(0, 0, '66C78182000000????C7818C000000????????C781900000', 0, 0)
        if first ~= 0 then
            frames[#frames + 1] = { name = 'party0', at = ashita.memory.read_uint32(first + 0x19) }
            frames[#frames + 1] = { name = 'target', at = ashita.memory.read_uint32(first + 0x23) }
        end
        local second = ashita.memory.find(0, 0, 'A1????????8B0D????????89442424A1????????33DB89', 0, 0)
        if second ~= 0 then
            frames[#frames + 1] = { name = 'party1', at = ashita.memory.read_uint32(second + 0x01) }
            frames[#frames + 1] = { name = 'party2', at = ashita.memory.read_uint32(second + 0x07) }
        end
    end
    return frames
end

local frameBytes = 0xA0

local function AddFrames(parts)
    for _, frame in ipairs(Frames()) do
        local object = frame.at ~= 0 and ashita.memory.read_uint32(frame.at) or 0
        local primitive = object ~= 0 and ashita.memory.read_uint32(object + 0x08) or 0
        if primitive == 0 then
            parts[#parts + 1] = ('%s: object=%08X frame=none'):format(frame.name, object)
        else
            parts[#parts + 1] = ('%s: object=%08X frame=%08X vis(+69)=%d vis(+6A)=%d'):format(
                frame.name, object, primitive,
                ashita.memory.read_uint8(primitive + 0x69), ashita.memory.read_uint8(primitive + 0x6A))
            for row = 0, frameBytes - 1, 16 do
                local bytes = { }
                for column = 0, 15 do
                    bytes[#bytes + 1] = ('%02X'):format(ashita.memory.read_uint8(primitive + row + column))
                end
                parts[#parts + 1] = ('%s+%02X: %s'):format(frame.name, row, table.concat(bytes, ' '))
            end
        end
    end
end

local function Say(text)
    print(('\30\81[xitools]\30\01 %s'):format(text))
end

local function Try(object, method, ...)
    local fn = object[method]
    if fn == nil then
        return '?'
    end
    local ok, value = pcall(fn, object, ...)
    return ok and tostring(value) or '!'
end

local function Snapshot()
    local parts = { }
    parts[#parts + 1] = ('menu=[%s]'):format(ffxi.GetMenuName())

    local target = AshitaCore:GetMemoryManager():GetTarget()
    parts[#parts + 1] = ('tgt sub=%s flags=%s act0=%s act1=%s id0=%s id1=%s idx0=%s idx1=%s menuOpen=%s action=%s'):format(
        Try(target, 'GetIsSubTargetActive'), Try(target, 'GetSubTargetFlags'),
        Try(target, 'GetIsActive', 0), Try(target, 'GetIsActive', 1),
        Try(target, 'GetServerId', 0), Try(target, 'GetServerId', 1),
        Try(target, 'GetTargetIndex', 0), Try(target, 'GetTargetIndex', 1),
        Try(target, 'GetIsMenuOpen'), Try(target, 'GetActionTargetActive'))

    local p0 = AshitaCore:GetPointerManager():Get('party')
    if p0 == nil or p0 == 0 then
        parts[#parts + 1] = 'party pointer: none'
        return table.concat(parts, '\n  ')
    end

    local p1 = ashita.memory.read_uint32(p0)
    if p1 == 0 then
        parts[#parts + 1] = ('p0=%08X p1=0'):format(p0)
        return table.concat(parts, '\n  ')
    end

    -- the pointers that sit beside the one us follows: the other party windows may be among them
    local beside = { }
    for offset = 0, 0x1C, 4 do
        beside[#beside + 1] = ('%08X'):format(ashita.memory.read_uint32(p1 + offset))
    end
    parts[#parts + 1] = ('p0=%08X p1=%08X beside: %s'):format(p0, p1, table.concat(beside, ' '))

    local p2 = ashita.memory.read_uint32(p1)
    if p2 == 0 then
        parts[#parts + 1] = 'p2=0'
        return table.concat(parts, '\n  ')
    end

    parts[#parts + 1] = ('p2=%08X cursor(+50)=%d active(+54)=%08X'):format(
        p2, ashita.memory.read_uint8(p2 + 0x50), ashita.memory.read_uint32(p2 + 0x54))

    for row = 0, objectBytes - 1, 16 do
        local bytes = { }
        for column = 0, 15 do
            bytes[#bytes + 1] = ('%02X'):format(ashita.memory.read_uint8(p2 + row + column))
        end
        parts[#parts + 1] = ('+%02X: %s'):format(row, table.concat(bytes, ' '))
    end

    AddFrames(parts)

    return table.concat(parts, '\n  ')
end

function recorder.IsRecording()
    return file ~= nil
end

function recorder.Toggle()
    if file ~= nil then
        file:close()
        file = nil
        Say(('Cursor recording stopped: %d entries.'):format(lines))
        return
    end

    local path = ('%sconfig\\addons\\xitools\\us_cursor.log'):format(AshitaCore:GetInstallPath())
    local opened, problem = io.open(path, 'w')
    if opened == nil then
        Say(('Could not write %s: %s'):format(path, tostring(problem)))
        return
    end

    file, last, lines = opened, nil, 0
    file:write(('started %s\n'):format(os.date('%Y-%m-%d %H:%M:%S')))
    Say('Cursor recording started. /xit us debug again to stop.')
end

-- A note of the player's own, written between the entries: what they are about to do
function recorder.Note(text)
    if file ~= nil then
        file:write(('\n#### %s\n'):format(text))
        file:flush()
        Say(('Noted: %s'):format(text))
    end
end

-- Once a frame while recording
function recorder.Update()
    if file == nil then
        return
    end

    local ok, snapshot = pcall(Snapshot)
    if not ok then
        snapshot = 'error: ' .. tostring(snapshot)
    end
    if snapshot == last then
        return
    end
    last = snapshot

    lines = lines + 1
    file:write(('\n@%.2f\n  %s\n'):format(os.clock(), snapshot))
    file:flush()

    if lines >= maxLines then
        recorder.Toggle()
    end
end

return recorder
