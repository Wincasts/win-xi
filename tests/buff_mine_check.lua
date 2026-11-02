-- winbuff's Your Colour: the time under a status the player put on themselves in Your Colour, until
-- someone else's is seen to land over it; kept through a change of area; nothing followed while the
-- times are not shown
local o = H.options()
local debuffs = require('winxi.debuffs')
local text = require('winxi.text')
H.print('Your Colour to begin with', table.concat(o.mineColor, ','))

-- the game's clock, and the player (0x100) under Protect (40) with 90 s left
local EPOCH, STAMP = 0x3C307D70, 0x3C307D70 + 5000
local memory = { [0x9000] = 0x9100, [0x9100] = 0x9200, [0x9200 + 0x0C] = STAMP }
local realFind = ashita.memory.find
ashita.memory.find = function(module, offset, pattern, ...) if pattern == '8B0D????????8B410C8B49108D04808D04808D04808D04C1C3' then return 0x9000 end return realFind(module, offset, pattern, ...) end
ashita.memory.read_uint32 = function(at) return memory[at] or 0 end
local ids, timers = {}, {}
for slot = 1, 32 do ids[slot], timers[slot] = 255, 0 end
ids[1], timers[1] = 40, (STAMP - EPOCH) * 60 + 90 * 60
AshitaCore.GetMemoryManager = function() return {
    GetParty = function() return { GetMemberServerId = function() return 0x100 end } end,
    GetPlayer = function() return { GetIsZoning = function() return 0 end, GetStatusIcons = function() return ids end,
        GetStatusTimers = function() return timers end, GetLoginStatus = function() return 2 end } end } end
AshitaCore.GetResourceManager = function() return { GetString = function(_, _, id) return 'Status ' .. id end,
    GetStatusIconByIndex = function() return { CanCancel = 0, HideTimer = 0, Description = { '' } } end } end

local drawn = {}
local realDraw = text.Draw
text.Draw = function(_, _, _, color, words) drawn[words] = color end
local function frame() drawn = {}; H.frames(1); return drawn['1m'] end
local function protect(by) debuffs.Action({ actor_id = by, category = 4, param = 43, targets = { { id = 0x100, actions = { { message = 230, param = 40 } } } } }) end

H.play(true)
frame() -- the bar's first frame, its size found
local before = frame()
H.print('Protect nobody was seen to cast: the text colour', before ~= nil and before ~= o.mineColor)
protect(0x100)
H.print('cast by you: Your Colour', frame() == o.mineColor)
protect(0x500)
H.print('someone else\'s over it: the text colour again', frame() ~= o.mineColor)
protect(0x100); frame()
debuffs.Clear() -- a change of area
H.print('yours, through a change of area: Your Colour still', frame() == o.mineColor)
-- the packets: followed while times are shown, and not while they are not
debuffs.Clear()
local handled = 0
local realHandle = debuffs.HandlePacket
debuffs.HandlePacket = function() handled = handled + 1 end
H.packet(0x028)
o.showTimers[1] = false
H.packet(0x028)
H.print('packets followed with times shown, not without', handled == 1, handled)
o.showTimers[1] = true
debuffs.HandlePacket, text.Draw = realHandle, realDraw
