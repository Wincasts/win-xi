-- Cache, lifecycle and memory-read regressions. Run through tests/harness.lua.
H.load()
local o = H.options()
local core = AshitaCore
local stats, activeReads = 0, 0
local active = { [0] = true, [1] = true }
local party = setmetatable({}, { __index = function(_, key)
    return function(_, place)
        if key == 'GetMemberIsActive' then activeReads = activeReads + 1; return active[place] and 1 or 0 end
        if key == 'GetMemberName' then return active[place] and ('Member' .. place) or '' end
        if key == 'GetMemberServerId' then return 100 + place end
        if key == 'GetMemberTargetIndex' then return 10 + place end
        if key == 'GetMemberZone' then return 1 end
        stats = stats + 1
        return 0
    end
end })
local player = setmetatable({ GetBuffs = function() return { 0, 40, 255, 513 } end, GetMainJob = function() return 18 end,
    GetPetMPPercent = function() return 50 end, GetPetTP = function() return 100 end,
}, { __index = function() return function() return 0 end end })
local targets = setmetatable({}, { __index = function() return function() return 0 end end })
local memory = { GetParty = function() return party end, GetPlayer = function() return player end,
    GetTarget = function() return targets end }
AshitaCore = setmetatable({ GetMemoryManager = function() return memory end }, { __index = core })
local entities = {
    [10] = { ServerId = 100, PetTargetIndex = 20 },
    [11] = { ServerId = 101, PetTargetIndex = 21 },
    [20] = { Name = 'Own pet', HPPercent = 50 },
    [21] = { Name = 'Other pet', HPPercent = 70 },
}
GetEntity = function(index) return entities[index] end
GetPlayerEntity = function() return entities[10] end

-- Neither a missing pointer registration nor a null pointee may read low memory.
local roster = require('roster')
local read32 = ashita.memory.read_uint32
ashita.memory.read_uint32 = function(address) assert(address ~= 0, 'null buff pointer dereferenced'); return 0 end
roster.Forget()
local members = roster.Members(1, false, false)
assert(#members == 2 and stats > 0)
assert(table.concat(members[1].statusIds, ',') == '40,513', 'own buffs must exclude empty IDs 0 and 255, preserving high IDs')
local populatedStats = stats
stats = 0
roster.Members(2, false, false)
assert(stats == 0, 'empty alliance slots read stats')
local reads = activeReads
roster.Members(1, false, false)
assert(stats == 0 and activeReads == reads, 'cached roster read memory')
roster.Members(2, true, false)
assert(stats == 0, 'sample empty slots read stats')
H.print('roster: inactive slots skip stats; cached frames skip reads; null pointer safe', true,
    '| two populated slots stat calls', populatedStats)

-- Reload only the direct-test module to exercise a registered pointer with a null pointee.
local pointers = core.GetPointerManager
AshitaCore.GetPointerManager = function() return { Get = function() return 4096 end } end
package.loaded.roster = nil
local registered = require('roster')
ashita.memory.read_uint32 = function(address) assert(address == 4096); return 0 end
assert(#registered.Members(1, false, false) == 2)
local read8, readArray = ashita.memory.read_uint8, ashita.memory.read_array
local bytes = {}
for i = 1, 48 do bytes[i] = 0 end
bytes[9] = 9 -- high bits: 1 for slot zero, 2 for slot one
for i = 17, 48 do bytes[i] = 255 end
bytes[17], bytes[18] = 44, 1 -- status IDs 300 and 513
ashita.memory.read_uint32 = function(address)
    if address == 4096 then return 8192 end
    assert(address == 8192, 'unexpected member buff entry')
    return 101
end
ashita.memory.read_uint8 = function(address) return bytes[address - 8192 + 1] end
for _, bulk in ipairs({ true, false }) do
    ashita.memory.read_array = bulk and function() return bytes end or function() error('unsupported bulk read') end
    registered.Forget()
    local buffs = registered.Members(1, false, false)[2].statusIds
    assert(#buffs == 2 and buffs[1] == 300 and buffs[2] == 513, 'packed buffs: bulk/fallback disagreement')
end
ashita.memory.read_uint8, ashita.memory.read_array = read8, readArray
ashita.memory.read_uint32 = read32
AshitaCore.GetPointerManager = pointers
package.loaded.roster = roster
H.print('roster: null pointee safe; packed high-bit buffs agree in bulk and byte fallback', true)

local pets = require('pets')
pets.Forget(true)
o.pets.showParty[1] = true
assert(#pets.Lines(false, o.pets) == 2)
o.pets.showParty[1] = false
assert(#pets.Lines(false, o.pets) == 1, 'pet settings must invalidate cache immediately')
o.pets.showParty[1] = true
assert(#pets.Lines(false, o.pets) == 2)
local unpack = struct.unpack
struct.unpack = function(format, data, at)
    return ({ [5] = 18, [105] = 500, [107] = 1000, [109] = 200, [111] = 400 })[at] or 0
end
H.packetData(0x044, string.rep('\0', 112))
pets.Forget()
assert(pets.Lines(false, o.pets)[1].hp == 500)
o.pets.exactAutomaton[1] = false
assert(pets.Lines(false, o.pets)[1].hp == nil)
o.pets.exactAutomaton[1] = true
assert(pets.Lines(false, o.pets)[1].hp == 500)
o.pets.enabled[1] = false
H.packet(0x00A)
o.pets.enabled[1] = true
assert(pets.Lines(false, o.pets)[1].hp == nil, 'zone reset while pets disabled')
struct.unpack = unpack
H.print('pets: settings invalidate cache immediately; zoning clears exact values even while disabled', true)

local notices = require('notices')
o.party.enabled[1] = false
H.packetData(0x0DC, string.rep('\0', 32))
assert(notices.Invitation() ~= nil)
H.packetOut(0x074)
assert(notices.Invitation() == nil, 'answer while disabled must clear invitation')
H.packetData(0x0DC, string.rep('\0', 32))
H.packet(0x00A)
assert(notices.Invitation() == nil)
H.print('invitations: answer and zone reset remain current while party disabled', true)

-- No actual drawing is needed: force a lingering window, then reuse its entity slot.
local target, windows = require('target'), require('windows')
local index, drawn = 30, 0
entities[30] = { ServerId = 500, Name = 'Original' }
target.Indexes = function() return index, 0, 0 end
windows.Lingers = function() return true end
windows.IsFadedOut = function() return false end
windows.UpdateFade = function() end
windows.Draw = function(window) if window == windows.List.main then drawn = drawn + 1 end end
require('winxi.game').IsHidden = function() return false end
o.target.enabled[1] = true
o.automaticPositioning[1] = false
H.frames(1)
assert(drawn == 1)
index = 0
H.frames(1)
assert(drawn == 2, 'original entity should linger')
entities[30] = { ServerId = 501, Name = 'Reused slot' }
H.frames(1)
assert(drawn == 2, 'reused entity slot must not linger')
H.packet(0x00A)
entities[30].ServerId = 500
H.frames(1)
assert(drawn == 2, 'zone reset must clear lingering identity')
H.print('target fade: original identity lingers, reused slots and zoning do not', true)
