-- Database details stay above a fixed, separated search footer; long records scroll independently.
require('winxi.gamedata').Root('addons/libs/winxi/data/') -- the server's sets, from the repository's data
local function check(label, ok) assert(ok, label); H.print(label, true) end
local imgui, hunts = require('imgui'), require('hunts')
local record = { indices = { 295 }, level = { 1, 1 }, kinds = 't', respawn = { 300, 600 }, drops = {} }
for i = 1, 40 do record.drops[i] = { rate = 100, items = { { 5000 + i, 10000 } } } end
hunts.Monster = function(_, name) return name ~= 'Missing' and record or nil end
hunts.ZoneName = function(z) return z == 100 and 'Test Zone' or 'Other Zone' end
hunts.Zones = function() return {
    { id = 100, name = 'Test Zone', label = 'Test Zone##100', monsters = { 'NM One' } },
    { id = 200, name = 'Other Zone', label = 'Other Zone##200', monsters = { 'NM Two' } },
} end
local searched = nil
hunts.Find = function(words)
    searched = words
    return { { zone = 200, name = 'NM Two', label = 'NM Two (Other Zone)' } }
end
local memory = AshitaCore:GetMemoryManager()
local party = memory:GetParty()
party.GetMemberZone = function() return 100 end
party.GetMemberTargetIndex = function() return 0 end
memory.GetParty = function() return party end
memory.GetEntity = function() return { GetRenderFlags0 = function() return 0 end } end
AshitaCore.GetMemoryManager = function() return memory end
H.play(true)
local o = H.options()
o.viewZone, o.viewName, o.maxTh[1] = 100, 'NM One', 14
o.fadeInOut[1] = false
local events, depth, clipped, resets, size, flags = {}, 0, false, 0, nil, nil
local screenW, screenH = 1920, 1080
rawset(imgui, 'GetIO', function() return { DisplaySize = { x = screenW, y = screenH } } end)
local function event(kind, text) events[#events + 1] = { kind = kind, text = text, depth = depth } end
rawset(imgui, 'BeginChild', function(id, dimensions, childFlags, f)
    assert(id == '##mark.databaseDetails', 'dedicated database scroll pane')
    -- Ashita's imgui 1.91 binding takes ImGuiChildFlags here and errors on a boolean.
    assert(type(childFlags) == 'number', 'BeginChild child flags must be a number')
    size, flags = { dimensions[1], dimensions[2] }, f
    event('begin', id); depth = depth + 1
    return not clipped
end)
rawset(imgui, 'EndChild', function() depth = depth - 1; event('end') end)
rawset(imgui, 'SetScrollY', function(y) resets = resets + 1; assert(y == 0 and depth == 1) end)
rawset(imgui, 'SetScrollX', function(x) assert(x == 0 and depth == 1) end)
for _, f in ipairs({ 'Text', 'TextUnformatted', 'TextDisabled', 'TableSetupColumn' }) do
    rawset(imgui, f, function(text) event('text', text) end)
end
rawset(imgui, 'TextColored', function(_, text) event('text', text) end)
rawset(imgui, 'Separator', function() event('separator') end)
local open, choose, typeText = false, nil, nil
rawset(imgui, 'BeginCombo', function(label) event('combo', label); return open end)
rawset(imgui, 'Selectable', function(label) return label == choose end)
rawset(imgui, 'InputText', function(label, value)
    event('input', label)
    if typeText then value[1] = typeText; typeText = nil; return true end
    return false
end)
local tabLabel = nil
local originalTab = imgui.BeginTabItem
rawset(imgui, 'BeginTabItem', function(label, ...) if not tabLabel then tabLabel = label end; return originalTab(label, ...) end)
local function frame(count)
    events, tabLabel = {}, nil
    H.frames(count or 1)
    assert(depth == 0, 'balanced child scopes')
end
local function find(kind, text)
    for i, e in ipairs(events) do if e.kind == kind and (text == nil or e.text == text) then return e, i end end
end
frame()
check('first tab named Database', tabLabel == 'Database##mark.database')
local title, titleAt = find('text', 'NM One')
local lastDrop, dropAt = find('text', 'Item 5040')
local ending, endAt = find('end')
local combo, comboAt = find('combo', '##mark.zone')
local input, inputAt = find('input', '##mark.find')
check('full selected NM details precede footer controls', title and lastDrop and title.depth == 1 and lastDrop.depth == 1 and titleAt < dropAt and dropAt < endAt and endAt < comboAt and comboAt < inputAt)
check('footer outside scroll pane and immediately below separator', combo.depth == 0 and input.depth == 0 and events[endAt + 1].kind == 'separator' and events[endAt + 1].depth == 0)
check('details have bounded height and horizontal scrolling for TH14', size[2] == 600 and size[1] == 728 and flags == ImGuiWindowFlags_HorizontalScrollbar)
local before = resets
frame()
check('ordinary redraw preserves details scroll position', resets == before)

-- Search is submitted in the footer, then the selected record changes on the following frame.
typeText = 'Two'; frame()
open, choose = true, 'NM Two (Other Zone)'
frame()
check('footer search can select a result from another zone', searched == 'Two' and o.viewZone == 200 and o.viewName == 'NM Two')
check('selection frame still shows one coherent old record', find('text', 'NM One') ~= nil and find('text', 'NM Two') == nil)
open, choose = false, nil
frame()
check('new record displayed at top and scroll reset once', find('text', 'NM Two') ~= nil and resets == before + 1)
clipped = true
frame()
check('clipped details still end child and expose footer', find('text', 'NM Two') == nil and find('combo', '##mark.zone').depth == 0 and find('input', '##mark.find').depth == 0)
clipped = false
screenW, screenH = 640, 480
frame()
check('details pane fits smaller displays', size[1] == 560 and size[2] == 220)
o.viewName = 'Missing'; frame()
check('missing record keeps footer usable', find('text', 'There is no data for Missing.') ~= nil and find('input', '##mark.find') ~= nil)
o.viewName = ''; frame()
check('empty record points user at footer', find('text', 'Choose a zone and a notorious monster below.') ~= nil)
o.viewName = 'NM One'
rawset(imgui, 'TextColored', function(_, text)
    if text == 'NM One' then error('database draw fixture failure') end
    event('text', text)
end)
local ok, err = pcall(frame)
check('details draw failure still closes child before propagation', not ok and tostring(err):find('database draw fixture failure', 1, true) ~= nil and depth == 0)
H.unload()
