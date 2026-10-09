-- xiframes: loads, brings old settings up to date, draws its frames, marks what is waiting, answers its command
H.load()
local o = H.options()
H.print('settings by section', o.style ~= nil and o.party ~= nil and o.target ~= nil and o.pets ~= nil, '| nothing of the old layout', o.tools == nil and o.globals == nil,
    '| scale', o.style.scale[1], '| party at', o.party.pos1[1], o.party.pos1[2], '| icons beside', o.party.iconCorner)

-- new settings start as the author's own; what may be taken out again (the links, the corner the
-- party's window is held by) is given the once, and not put back when the settings are next loaded
H.print('new settings: value size', o.style.valueSize[1], '| HP offset', o.style.hpOffset[1], '| click through', o.clickThrough[1], '| fade after', o.fade.Delay,
    '| links', #o.links, '| held at', o.party.corner1 and o.party.corner1[2])
do
    local again = require('options').Defaults()
    again.version, again.links = 2, T{ }
    require('options').Complete(again)
    H.print('loaded again: links left out stay out', #again.links == 0, '| no corner put back', again.party.corner1 == nil)
end

-- a character's settings from before they were set out by section: what was set is carried over
local options = require('options')
local old = options.Complete(dofile('tests/fixtures/xiframes_v1_settings.lua'))
H.print('old settings: scale', old.style.scale[1], 'name size', old.style.nameSize[1], 'value size', old.style.valueSize[1], 'buff size', old.style.buffSize[1],
    '| HP offset', old.style.hpOffset[1], old.style.hpOffset[2], 'TP offset', old.style.tpOffset[1], old.style.tpOffset[2])
H.print('old settings: party at', old.party.pos1[1], old.party.pos1[2], 'held at', old.party.corner1 and old.party.corner1[2], '| icon offset', old.party.iconOffset[1], old.party.iconOffset[2],
    '| target at', old.target.mainPos[1], old.target.mainPos[2], '| links', #old.links, old.links[2].child, old.links[2].side, old.links[2].parent)
H.print('old settings: fade', old.fade.Enabled, 'after', old.fade.Delay, '| party fades', old.fade.windows.party and old.fade.windows.party[1], '| hide under map', old.hide.UnderMap,
    '| shared theme', old.useSharedTheme, '| the old tables gone', old.tools == nil and old.globals == nil and old.importedFromXilite == nil)

H.frames(3); H.print('loading: windows begun', H.calls.Begin or 0)

-- in game, everyone with a pet and something targeted: the memory here answers 1 to whatever it is asked
local anything
local managers = { GetParty = true, GetPlayer = true, GetEntity = true, GetTarget = true, GetRecast = true, GetCastBar = true }
anything = setmetatable({}, { __index = function(_, k) return function()
    if managers[k] then return anything end
    if k:match('Name$') then return 'Tester' end
    if k:match('Buffs') or k:match('StatusIcons') then return {} end
    if k == 'GetIsZoning' then return 0 end
    if k == 'GetLoginStatus' then return 2 end
    return 1
end end })
local core = AshitaCore
AshitaCore = setmetatable({ GetMemoryManager = function() return anything end }, { __index = core })
-- but the inventory is the harness's own, which has a treasure pool
rawset(anything, 'GetInventory', function() return core.GetMemoryManager():GetInventory() end)
GetEntity = function(index)
    if index == 99 then return { Name = 'Carbuncle', Distance = 16, HPPercent = 80 } end
    return { Name = 'Greater Colibri', Distance = 64, HPPercent = 75, ServerId = 7, PetTargetIndex = 99, TargetedIndex = 0 }
end
GetPlayerEntity = function() return { Name = 'Tester', HPPercent = 100, Distance = 0, ServerId = 1, TargetIndex = 1 } end
o.party.showTreasure[1] = false

local ok, problem = pcall(function() H.packet(0x00A); H.frames(4) end)
H.print('in game: frames ran', ok, ok and '' or problem, '| windows begun', H.calls.Begin or 0, '| lists given room', (H.calls.Dummy or 0) > 0,
    '| a line over the pets', (H.calls.Separator or 0) > 0)

-- a leader has a circle in front of their name: here everyone leads their party and the alliance, so two each
rawset(anything, 'GetMemberFlagMask', function() return 12 end)
local circles = H.calls['draw.AddCircleFilled'] or 0
ok, problem = pcall(H.frames, 5)
H.print('leaders: frames ran', ok, ok and '' or problem, '| circles drawn', (H.calls['draw.AddCircleFilled'] or 0) > circles)
rawset(anything, 'GetMemberFlagMask', nil)

-- an invitation: marked beside the party's window until it is answered
local function invitation(kind) return ('\0'):rep(0x0B) .. string.char(kind) .. ('\0'):rep(20) end
local realUnpack = struct.unpack
struct.unpack = function(format, data, at)
    if format == 'B' and #data > 0x0B then return data:byte(at) end
    return realUnpack(format, data, at)
end
-- the icons are circles, as leaders' marks are: no one leads now, so only an icon is one
local function drawn() local before = H.calls['draw.AddCircleFilled'] or 0; H.frames(1); return (H.calls['draw.AddCircleFilled'] or 0) > before end
H.print('no invitation: no mark', drawn() == false)
H.packetData(0x0DC, invitation(0)); H.print('a party invite: marked', drawn())
H.packetOut(0x074); H.print('answered: gone', drawn() == false)
H.packetData(0x0DC, invitation(5)); H.print('an alliance invite: marked', drawn())
H.packet(0x00A); H.print('a change of area: gone', drawn() == false)
struct.unpack = realUnpack

-- the treasure pool: an icon while there is something in it. It is looked at twice a second.
o.party.showTreasure[1] = true
H.frames(20); H.print('an empty pool: no icon', drawn() == false)
H.pool(2); H.frames(20); H.print('two items in the pool: an icon', drawn())
H.pool(0); H.frames(20); H.print('emptied: gone', drawn() == false)

-- the settings, tab by tab: drawn directly, as the harness shows only a window's first tab
local config = require('config')
local sliders = H.calls.SliderInt or 0
for _, tab in ipairs(config.Tabs) do
    ok, problem = pcall(tab.draw, o)
    H.print(tab.name, 'tab draws', ok, ok and '' or problem)
end
H.print('sliders in the tabs', (H.calls.SliderInt or 0) - sliders)

local before = H.calls.Begin or 0
H.print('/xiframes kept from the game', H.command('/xiframes'), '| settings showing', o.showConfig[1]); H.frames(1)
H.print('settings window drawn', (H.calls.Begin or 0) > before)
H.print('/xif closes it', H.command('/xif') and o.showConfig[1] == false, '| /xiframesx is left alone', H.command('/xiframesx') == false)
H.unload(); H.print('unload ran; saves', H.saves() > 0)
