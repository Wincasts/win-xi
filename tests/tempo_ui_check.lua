-- tempo: loads, draws nothing until there is something to show, shows its bars with the settings open,
-- and follows an engage, a round and a rest through the game's memory and packets
local window = require('winxi.window')
local text = require('winxi.text')
local bars = require('winxi.bars')
local barsDrawn = {}
local realDraw = bars.Draw
bars.Draw = function(_, x, y, width, height, fraction, color)
    barsDrawn[#barsDrawn + 1] = { x = x, y = y, width = width, height = height, fraction = fraction, color = color }
    return true
end

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
local said, drawn, look, lookFlags = {}, 0, nil, 0
local plain = window.Full
window.Full = function(name, open, flags, draw, options)
    if name == 'tempo.window' then
        drawn, look, lookFlags = drawn + 1, options, flags
        draw()
        return true
    end
    return plain(name, open, flags, draw, options)
end
text.Draw = function(_, _, _, _, words) said[#said + 1] = words end
text.Outlined = function(words) said[#said + 1] = words end
local function shown()
    for i = #said, 1, -1 do said[i] = nil end
    for i = #barsDrawn, 1, -1 do barsDrawn[i] = nil end
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

-- the bars: the theme's texture, at the bars' size, tinted their colour
local first = barsDrawn[1]
check('a themed bar, 220 by 22, in the rest colour', first ~= nil and first.width == 220 and first.height == 22 and first.color == o.restColor)
check('the background on: the theme\'s', look.background == nil and look.shadow == nil)

-- the label moved 30 above the bar: the bar comes down to make room for it
local baseY = first.y
o.labelY[1] = -30
shown()
check('a label moved up makes room above the bar', barsDrawn[1].y > baseY, barsDrawn[1].y - baseY)
o.labelY[1] = 0

-- the background off: none, no border, no shadow
o.showBackground[1] = false
shown()
check('background off: clear, no border or shadow', look.background ~= nil and look.background[4] == 0 and look.border[4] == 0
    and look.shadow == false and bit.band(lookFlags, ImGuiWindowFlags_NoBackground) ~= 0)
o.showBackground[1] = true
shown()
check('and on again', look.background == nil and look.border == nil and look.shadow == nil)

-- winxi.bars itself: a 200 by 14 bar (half the art's 28) half full. Each end is 12 of the art's pixels at
-- half scale, 6 wide; the fill starts 8 art pixels in (4) and reaches half of the 192 between its ends.
local loads = 0
bars.Load = function(file) loads = loads + 1; return loads end
local images = {}
local list = { AddImage = function(_, texture, a, b, uvA, uvB)
    images[#images + 1] = { texture = texture, x1 = a[1], x2 = b[1], u1 = uvA[1], u2 = uvB[1] }
end }
local ok = realDraw(list, 100, 50, 200, 14, 0.5, { 1, 1, 1, 1 })
local back1, back2, back3, fill, front3 = images[1], images[2], images[3], images[4], images[7]
check('bars: drawn in the texture, back, fill and front', ok and #images == 7 and loads == 3, #images, loads)
check('bars: the ends keep their shape', back1.x1 == 100 and back1.x2 == 106 and back2.x2 == 294 and back3.x2 == 300
    and math.abs(back1.u2 - 12 / 220) < 1e-9 and math.abs(front3.u2 - 220 / 226) < 1e-9)
check('bars: the fill inside its ends, half way', fill.x1 == 104 and math.abs(fill.x2 - (104 + 192 / 2)) < 1e-9, fill.x1, fill.x2)
images = {}
realDraw(list, 0, 0, 200, 14, 0, { 1, 1, 1, 1 })
check('bars: empty, no fill', #images == 6 and loads == 3)

if failed > 0 then
    H.print(('%d failed'):format(failed))
    os.exit(1)
end
H.print('all passed')
