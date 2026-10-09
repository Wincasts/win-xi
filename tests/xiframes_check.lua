-- xiframes: loads, brings over from xilite what it has a setting for, draws its frames, answers its command
H.load()
local o = H.options()
local us, tgt, pet = o.tools.us, o.tools.tgt, o.tools.pet
H.print('imported', o.importedFromXilite, '| said:', H.printed[#H.printed])
H.print('party: scale', us.xivScale[1], 'name size', us.xivNameSize[1], 'TP values', us.xivShowTp[1], 'HP offset', us.xivHpOffset[1], us.xivHpOffset[2],
    '| hide when solo', us.hideWhenSolo[1])
H.print('party window: named', us.alliance1.name, 'at', us.alliance1.pos[1], us.alliance1.pos[2], 'corner', us.alliance1.corner[1], us.alliance1.corner[2])
H.print('left behind: cast bar', us.showCastbar == nil, '| style switch', us.xivParty == nil, '| compact', us.alliance1.isCompact == nil and tgt.compact == nil,
    '| me', o.tools.me == nil, '| pet window', pet.pos == nil and pet.name == nil)
H.print('target: named', tgt.mainWindow.name, 'at', tgt.mainWindow.pos[1], 'debuffs', tgt.mainWindow.showStatus[1], '| pet: party pets', pet.showParty[1])
H.print('globals: clickthrough', o.globals.isClickThru[1], '| own theme', o.globals.useSharedTheme == false, '| hide chat', o.globals.hide.UnderChat,
    '| fade', o.globals.fade.Enabled, 'us fades', o.globals.fade.tools.us[1], '| no fade for pet or me', o.globals.fade.tools.pet == nil and o.globals.fade.tools.me == nil)
H.print('links kept', #o.globals.links, o.globals.links[1].child, o.globals.links[1].side, o.globals.links[1].parent)

H.frames(3); H.print('loading: windows begun', H.calls.Begin or 0)

-- in game, everyone with a pet and something targeted: the memory here answers 1 to whatever it is asked
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
GetEntity = function(index)
    if index == 99 then return { Name = 'Carbuncle', Distance = 16, HPPercent = 80 } end
    return { Name = 'Greater Colibri', Distance = 64, HPPercent = 75, ServerId = 7, PetTargetIndex = 99, TargetedIndex = 0 }
end
GetPlayerEntity = function() return { Name = 'Tester', HPPercent = 100, Distance = 0, ServerId = 1, TargetIndex = 1 } end
us.hideWhenSolo[1] = false

local ok, problem = pcall(function() H.packet(0x00A); H.frames(4) end)
H.print('in game: frames ran', ok, ok and '' or problem, '| windows begun', H.calls.Begin or 0, '| lists given room', (H.calls.Dummy or 0) > 0,
    '| a line over the pets', (H.calls.Separator or 0) > 0, '| progress bars', H.calls.ProgressBar or 0)

-- the settings, tab by tab: drawn directly, as the harness shows only a window's first tab
for _, name in ipairs({ 'us', 'tgt', 'pet' }) do
    require('imgui').BeginTabBar('check')
    ok, problem = pcall(require(name).DrawConfig, o.tools[name], o.globals)
    H.print(name, 'settings draw', ok, ok and '' or problem)
end

local before = H.calls.Begin or 0
H.print('/xiframes kept from the game', H.command('/xiframes'), '| settings showing', o.showConfig[1]); H.frames(1)
H.print('settings window drawn', (H.calls.Begin or 0) > before)
H.print('/xif closes it', H.command('/xif') and o.showConfig[1] == false, '| /xiframesx is left alone', H.command('/xiframesx') == false)
H.unload(); H.print('unload ran; saves', H.saves() > 0)
