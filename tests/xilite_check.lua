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
o.tools.us.alliance1.isCompact[1] = false; H.frames(1) -- the full view again, held by no corner
o.tools.us.xivParty[1] = true
local rooms, drawn = H.calls.Dummy or 0, H.calls['draw.AddText'] or 0
ok, problem = pcall(H.frames, 2)
H.print('xivparty style: frames ran', ok, ok and '' or problem, '| lists given room', ((H.calls.Dummy or 0) - rooms) / 2,
    '| names and figures drawn', (H.calls['draw.AddText'] or 0) > drawn)
H.print('xivparty style: the party list is held by its bottom left', o.tools.us.alliance1.corner ~= nil,
    '| the second alliance is not', o.tools.us.alliance2.corner == nil)
-- a line is a name and three figures; fewer with the MP and TP values switched off
H.frames(1); local before = H.calls['draw.AddText']; H.frames(1); local all = H.calls['draw.AddText'] - before
o.tools.us.xivShowMp[1] = false; H.frames(1); before = H.calls['draw.AddText']; H.frames(1); local noMp = H.calls['draw.AddText'] - before
o.tools.us.xivShowTp[1] = false; H.frames(1); before = H.calls['draw.AddText']; H.frames(1); local neither = H.calls['draw.AddText'] - before
H.print('texts a frame: all', all, '| without MP values', noMp, '| without MP or TP values', neither)
o.tools.us.xivShowMp[1], o.tools.us.xivShowTp[1] = true, true
o.tools.us.xivParty[1] = false

-- the pets are listed under the party, and the pet tool's own window is then left out
-- everyone here has a pet: whatever is looked up is an owner, but for the pet itself
local noEntity = GetEntity
GetEntity = function(index)
    if index == 99 then return { Name = 'Carbuncle', Distance = 16, HPPercent = 80 } end
    return { Name = 'Owner', Distance = 4, HPPercent = 100, ServerId = 0, PetTargetIndex = 99 }
end
local separators = H.calls.Separator or 0
o.tools.us.showPets[1] = false; H.frames(2)
local apart = (H.calls.Separator or 0) - separators
o.tools.us.showPets[1] = true; begun = H.calls.Begin; H.frames(1); local together = H.calls.Begin - begun
o.tools.us.showPets[1] = false; begun = H.calls.Begin; H.frames(1)
H.print('pets under the party: no line while apart', apart == 0, '| one window fewer while together', (H.calls.Begin - begun) - together)
o.tools.us.showPets[1] = true; separators = H.calls.Separator or 0
for _, style in ipairs({ 'full', 'compact', 'xivparty' }) do
    o.tools.us.alliance1.isCompact[1] = style == 'compact'
    o.tools.us.xivParty[1] = style == 'xivparty'
    ok, problem = pcall(H.frames, 2)
    H.print('pets under the party,', style, ': frames ran', ok, ok and '' or problem, '| a line drawn', (H.calls.Separator or 0) > separators)
    separators = H.calls.Separator or 0
end
o.tools.us.alliance1.isCompact[1], o.tools.us.xivParty[1] = false, false
GetEntity = noEntity

-- an experimental setting's name carries its tag, the word in a colour of its own
local colored = H.calls.TextColored or 0
require('winxi.widgets').Label('Compact Alliance 1', true)
H.print('experimental tag drawn', (H.calls.TextColored or 0) == colored + 1)
H.unload(); H.print('unload ran; saves', H.saves() > 0)
