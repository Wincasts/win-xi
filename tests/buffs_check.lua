-- buffs: loads, shows the player's statuses with their icons and times, removes one on a right click,
-- and switches the game's own icons off and on again
local o = H.options()
H.print('defaults: size', o.iconSize[1], '| per row', o.perRow[1], '| timers', o.showTimers[1], '| ffxiv icons', o.ffxivIcons[1])
H.print('nowhere to hide the game\'s icons, said once:', H.printed[#H.printed])

-- a player under Protect (40, no end), Haste (33, 90 seconds left) and a food (251, two hours)
local stamp, epoch = 2000000000, 0x3C307D70
local ids, timers = {}, {}
for slot = 1, 32 do ids[slot], timers[slot] = 255, 0 end
local function under(slot, id, seconds) ids[slot] = id; timers[slot] = seconds and (stamp - epoch) * 60 + seconds * 60 or 0x7FFFFFFF end
local serverId, zoning = 0, 0
local memory = { GetParty = function() return { GetMemberServerId = function() return serverId end } end,
    GetPlayer = function() return { GetIsZoning = function() return zoning end, GetStatusIcons = function() return ids end, GetStatusTimers = function() return timers end,
        GetLoginStatus = function() return 2 end } end }
AshitaCore.GetMemoryManager = function() return memory end
local asked = {}
AshitaCore.GetResourceManager = function() return { GetString = function(_, _, id) return 'Status ' .. id end,
    GetStatusIconByIndex = function(_, id) asked[#asked + 1] = id; return { CanCancel = id == 33 and 1 or 0, HideTimer = id == 251 and 1 or 0, Description = { 'What it does.' } } end } end

local statuses = require('statuses')
local list = {}
H.print('no player: statuses', statuses.Read(list))
serverId = 1; under(1, 40); under(2, 33, 90); under(5, 251, 7200)
H.print('three statuses read', statuses.Read(list) == 3, '| in order', list[1].id, list[2].id, list[3].id, '| no time read without the game\'s clock', list[2].seconds == nil)
zoning = 1; H.print('between areas: statuses', statuses.Read(list), '| list emptied', #list == 0); zoning = 0

H.play(true); H.frames(3)
H.print('window begun', (H.calls.Begin or 0) > 0, '| an item for each status a frame', H.calls.Dummy % 3 == 0, '| on a row', (H.calls.SameLine or 0) > 0)
H.print('no device: no icon drawn', (H.calls['draw.AddImage'] or 0) == 0)

-- the icons folder has what the build tool made
local icons = require('icons')
H.print('an icon made for Haste', ashita.fs.exists(addon.path .. 'icons\\33.png'), '| none for KO', not ashita.fs.exists(addon.path .. 'icons\\0.png'))
H.print('icon shape', icons.OwnAspect, icons.OwnLeft, icons.OwnRight)

-- a right click on each status: only the one that can be removed is
H.ret.IsItemHovered = { true }; H.ret.IsItemClicked = { true }; H.frames(1); H.ret.IsItemHovered = { false }; H.ret.IsItemClicked = { false }
H.print('right click removes Haste alone: packets', #H.sent, H.sent[1], '| tooltips', H.calls.BeginTooltip)

o.perRow[1] = 1; local before = H.calls.SameLine or 0; H.frames(1); H.print('one to a row: none beside another', (H.calls.SameLine or 0) == before)
for slot = 1, 32 do ids[slot] = 255 end
local begun = H.calls.Begin; H.frames(20); H.print('no status: no window', H.calls.Begin == begun)

-- the game's own icons: three places changed, and put back
local native = require('native')
local written, at = {}, { ['75??8B4E0851B9'] = 100, ['7D??33C05EC20400C6'] = 200, ['85C00F??????????6A0232DBE8'] = 300 }
ashita.memory.find = function(_, _, pattern) return at[pattern] or 0 end
ashita.memory.read_uint16 = function(pointer) return written[pointer] or pointer + 1 end
ashita.memory.write_uint16 = function(pointer, value) written[pointer] = value end
H.print('hidden', native.Set(true), native.IsHidden(), '|', written[100] == 0x9090, written[200] == 0x9090, written[300] == 0xC031)
H.print('hidden already by another: left alone', (function() local n = dofile('addons/buffs/native.lua') return n.Set(true) == false and written[100] == 0x9090 end)())
H.unload(); H.print('unload puts them back', native.IsHidden() == false, written[100] == 101, written[200] == 201, written[300] == 301)

H.print('/buffs config kept from the game', H.command('/buffs config'), '| /buffs hides it', H.command('/buffs') and o.isVisible[1] == false, '| /buffsx is left alone', H.command('/buffsx') == false)
