-- xilite: loads, brings its four tools' settings over from xitools, draws its windows, answers its command
H.load()
local o = H.options()
H.print('imported', o.importedFromXitools, '| me pos', o.tools.me.pos[1], o.tools.me.pos[2], '| me named', o.tools.me.name,
    '| tgt named', o.tools.tgt.mainWindow.name, 'at', o.tools.tgt.mainWindow.pos[1], '| tgt enabled', o.tools.tgt.isEnabled[1])
H.print('said:', H.printed[#H.printed])
H.print('globals: clickthrough', o.globals.isClickThru[1], '| hide chat', o.globals.hide.UnderChat, 'map', o.globals.hide.UnderMap,
    '| fade', o.globals.fade.Enabled, 'me fades', o.globals.fade.tools.me[1], 'pet fades', o.globals.fade.tools.pet[1])
H.print('links kept', #o.globals.links, o.globals.links[1].child, 'under', o.globals.links[1].parent)
H.print('what was kept untouched: us named', o.tools.us.alliance1.name, '| pet enabled', o.tools.pet.isEnabled[1])

H.frames(3); H.print('loading: windows begun', H.calls.Begin or 0)

-- in game, with a party of one and nothing targeted: the memory here answers 1 to whatever it is asked
local anything
local managers = { GetParty = true, GetPlayer = true, GetEntity = true, GetTarget = true, GetRecast = true, GetCastBar = true, GetInventory = true }
anything = setmetatable({}, { __index = function(_, k) return function()
    if managers[k] then return anything end
    if k:match('Name$') then return 'Tester' end
    if k:match('Buffs') or k:match('StatusIcons') then return {} end
    if k == 'GetIsZoning' then return 0 end
    return 1
end end })
local core = AshitaCore
AshitaCore = setmetatable({ GetMemoryManager = function() return anything end }, { __index = core })
GetEntity = function() return nil end
GetPlayerEntity = function() return { Name = 'Tester', HPPercent = 100, Distance = 0, ServerId = 1, TargetIndex = 1 } end

local ok, problem = pcall(H.frames, 5)
H.print('in game: frames ran', ok, ok and '' or problem, '| windows begun', H.calls.Begin or 0)

-- the target window too, and the packets it reads
o.tools.tgt.isEnabled[1] = true
local begun = H.calls.Begin
ok, problem = pcall(function() H.packet(0x00A); H.frames(5) end)
H.print('with tgt on: frames ran', ok, ok and '' or problem, '| more windows begun', H.calls.Begin > begun)

-- the party window in its compact form: a line a member, with their TP written beside the window
o.tools.us.alliance1.isCompact[1] = true
local bars, texts = H.calls.ProgressBar, H.calls['draw.AddText'] or 0
ok, problem = pcall(H.frames, 1)
H.print('compact party: frame ran', ok, ok and '' or problem, '| bars drawn', H.calls.ProgressBar - bars, '| TP figures drawn', (H.calls['draw.AddText'] or 0) > texts)
-- and it grows upwards: held by its bottom left corner, which is kept with its settings; the other lists are not
local corner = o.tools.us.alliance1.corner
H.print('compact party is held by its bottom left', corner ~= nil and corner[1] == 100 and corner[2] == 200 + 150,
    '| the second alliance is not', o.tools.us.alliance2.corner == nil)
o.tools.us.alliance1.isCompact[1] = false; H.frames(1)
H.print('full again: the corner is forgotten', o.tools.us.alliance1.corner == nil)
o.tools.us.alliance1.isCompact[1] = true
-- a window off screen, as the one a list is measured in is, has no TP figures drawn beside it
local pos, cursor = H.ret.GetWindowPos, H.ret.GetCursorScreenPos
H.ret.GetWindowPos, H.ret.GetCursorScreenPos = { -20000, -20000 }, { -19990, -19990 }
texts = H.calls['draw.AddText']; H.frames(1)
H.print('off screen: no TP figures drawn', H.calls['draw.AddText'] == texts)
H.ret.GetWindowPos, H.ret.GetCursorScreenPos = pos, cursor

local before = H.calls.Begin or 0
H.print('/xilite kept from the game', H.command('/xilite'), '| settings showing', o.showConfig[1]); H.frames(1)
H.print('settings window drawn', (H.calls.Begin or 0) > before, '| tab bars', H.calls.BeginTabBar)
H.print('/xil closes it', H.command('/xil') and o.showConfig[1] == false, '| /xilitex is left alone', H.command('/xilitex') == false)
-- XivParty Style: the lists take up their own room and draw themselves into it
o.tools.us.xivParty[1] = true
local rooms, drawn = H.calls.Dummy or 0, H.calls['draw.AddText'] or 0
ok, problem = pcall(H.frames, 2)
H.print('xivparty style: frames ran', ok, ok and '' or problem, '| lists given room', ((H.calls.Dummy or 0) - rooms) / 2,
    '| names and figures drawn', (H.calls['draw.AddText'] or 0) > drawn)
o.tools.us.xivParty[1] = false

-- an experimental setting's name carries its tag, the word in a colour of its own
local colored = H.calls.TextColored or 0
require('winxi.widgets').Label('Compact Alliance 1', true)
H.print('experimental tag drawn', (H.calls.TextColored or 0) == colored + 1)
H.unload(); H.print('unload ran; saves', H.saves() > 0)
