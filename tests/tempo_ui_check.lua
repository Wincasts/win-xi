-- tempo: loads, draws nothing until there is something to show, shows its bars with the settings open,
-- and follows an engage, a round and a rest through the game's memory and packets
local window = require('winxi.window')
local text = require('winxi.text')

local failed = 0
local function check(label, ok, ...)
    H.print(label, ok, ...)
    if not ok then failed = failed + 1 end
end

-- the game: a WAR with a 224 sword, resting or fighting as status says
local me, status, hp, mp = 0x1001, 0, 500, 100
local entity = {}
function GetPlayerEntity() entity.Status = status; return entity end
local party = { GetMemberServerId = function() return me end, GetMemberTargetIndex = function() return 0x400 end,
    GetMemberName = function() return 'Tester' end,
    GetMemberHP = function() return hp end, GetMemberMP = function() return mp end }
local player = { GetMainJob = function() return 1 end, GetMainJobLevel = function() return 75 end,
    GetSubJob = function() return 13 end, GetSubJobLevel = function() return 37 end,
    GetHPMax = function() return 900 end, GetMPMax = function() return 400 end,
    GetBuffs = function() return {} end, GetLoginStatus = function() return 2 end,
    GetIsZoning = function() return 0 end, GetStatusIcons = function() return {} end }
local inventory = { GetEquippedItem = function(_, slot) return slot == 0 and { Index = 1 } or nil end,
    GetContainerItem = function() return { Id = 16535 } end }
local memory = { GetParty = function() return party end, GetPlayer = function() return player end,
    GetInventory = function() return inventory end,
    GetTarget = function() return { GetTargetIndex = function() return 0 end, GetIsSubTargetActive = function() return 0 end } end,
    GetEntity = function() return {} end }
local resources = { GetItemById = function() return { Delay = 224, Skill = 3 } end }
local core = AshitaCore
AshitaCore = setmetatable({ GetMemoryManager = function() return memory end, GetResourceManager = function() return resources end },
    { __index = core })

-- what the window says in a frame
local said, drawn = {}, 0
local plain = window.Full
window.Full = function(name, open, flags, draw, options)
    if name == 'tempo.window' then
        drawn = drawn + 1
        draw()
        return true
    end
    return plain(name, open, flags, draw, options)
end
text.Draw = function(_, _, _, _, words) said[#said + 1] = words end
text.Outlined = function(words) said[#said + 1] = words end
local function shown()
    for i = #said, 1, -1 do said[i] = nil end
    drawn = 0
    H.frames(1)
    return table.concat(said, ' | ')
end

local o = H.options()
o.fadeInOut[1] = false
H.play(true); H.login(2); H.frames(3)
check('idle: no window', shown() == '' and drawn == 0)

H.command('/tempo')
local sample = shown()
check('settings open: the sample bars', sample:find('Attack', 1, true) ~= nil and sample:find('HP', 1, true) ~= nil, sample)
H.command('/tempo')
check('settings closed: gone again', shown() == '')

-- engaged: the first round 2.8 s off, a 224 sword's 3.73 s delay marked as worked out
status = 1
local fight = shown()
check('engaged: attack bar', fight:find('Attack  ~3.73s', 1, true) ~= nil, fight)

-- a round of ours: an action packet of category 1 from our id
local function action(actor, category, what)
    local bits = {}
    local function put(offset, length, value)
        for i = 0, length - 1 do bits[offset + i] = math.floor(value / 2 ^ i) % 2 end
    end
    put(40, 32, actor); put(72, 6, 1); put(82, 4, category); put(86, 32, what or 0)
    local bytes = {}
    for index = 0, 40 do
        local byte = 0
        for i = 0, 7 do byte = byte + (bits[index * 8 + i] or 0) * 2 ^ i end
        bytes[#bytes + 1] = string.char(byte)
    end
    return table.concat(bytes)
end
H.wait(3)
H.packetData(0x028, action(me, 1))
local afterRound = shown()
check('a round: the bar starts over at the delay', afterRound:find('3.7', 1, true) ~= nil, afterRound)
H.packetData(0x028, action(me, 8, 0x6163))
check('a spell begun: Casting', shown():find('Casting', 1, true) ~= nil)
H.packetData(0x028, action(me, 4, 144))
check('and done', shown():find('Casting', 1, true) == nil)

-- resting
status = 0; H.frames(1)
status = 33
local resting = shown()
check('resting: the tick bar', resting:find('+10 HP  +12 MP', 1, true) ~= nil and resting:find('Full in', 1, true) ~= nil, resting)

if failed > 0 then
    H.print(('%d failed'):format(failed))
    os.exit(1)
end
H.print('all passed')
