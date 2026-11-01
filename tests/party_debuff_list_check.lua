-- Debuff List: a box listing the debuffs seen to land on the main target, each with the time it has
-- left, off to begin with. A plain imgui window dragged by its body, held still by Lock Windows; with
-- Winxi Theme, one of the addon's windows, moved as the target windows are. Placed by Debuff List
-- Position, which a drag sets too; the sample while organizing; tracked while the list alone is on;
-- its rows under Target -> Debuff List.
H.load()
local o = H.options()
local imgui, bit, tracker, windows = require('imgui'), require('bit'), require('winxi.debuffs'), require('windows')
local target, debufflist, organize = require('target'), require('debufflist'), require('winxi.organize')
o.party.enabled[1], o.pets.enabled[1], o.showConfig[1] = false, false, false
o.fade.Enabled, o.automaticPositioning[1], o.clickThrough[1] = false, false, false
o.target.enabled[1], o.target.showMain[1], o.target.mainDebuffs[1] = false, false, false
require('winxi.game').IsHidden = function() return false end
require('game').StPartyIndex = function() return nil end
AshitaCore.GetResourceManager = function() return { GetString = function(_, _, id) return 'Effect ' .. id end } end
local entity = { Name = 'Goblin', Distance = 64, HPPercent = 80, ServerId = 900 }
GetEntity = function(index) return index == 10 and entity or nil end
local mainIndex = 10
target.MainIndex = function() return mainIndex end
organize.SetActive(false)
-- the harness numbers imgui's flags one after another: these bits of their own, to be seen
ImGuiWindowFlags_NoMove, ImGuiWindowFlags_NoInputs, ImGuiWindowFlags_NoDecoration = 0x100000, 0x200000, 0x400000

-- each window begun in a frame, with its flags and the texts written in it
local begun, current = { }, nil
local begin, text, textDisabled = imgui.Begin, imgui.Text, imgui.TextDisabled
imgui.Begin = function(name, open, flags)
    current = { name = name, flags = flags or 0, texts = { } }
    begun[#begun + 1] = current
    return begin(name, open, flags)
end
imgui.Text = function(t) if current then current.texts[#current.texts + 1] = t end return text(t) end
imgui.TextDisabled = function(t) if current then current.texts[#current.texts + 1] = t end return textDisabled(t) end
local function Frame()
    begun = { }
    H.frames(1)
    for _, w in ipairs(begun) do
        if w.name == windows.List.debuffs.name then return w end
    end
    return nil
end
local function Has(flags, flag) return bit.band(flags, flag) ~= 0 end
local function Dia() tracker.Action({ actor_id = 1, category = 4, param = 23, targets = { { id = 900, actions = { { message = 2 } } } } }) end
local function Paralyze() tracker.Action({ actor_id = 1, category = 4, param = 58, targets = { { id = 900, actions = { { message = 236, param = 4 } } } } }) end

assert(o.target.debuffList[1] == false and o.target.debuffListTheme[1] == false, 'off to begin with, plain')
assert(Frame() == nil, 'off: no box')

o.target.debuffList[1] = true
local box = Frame()
assert(box ~= nil, 'on: the box, with no target window shown')
assert(not Has(box.flags, ImGuiWindowFlags_NoMove) and not Has(box.flags, ImGuiWindowFlags_NoInputs), 'plain: dragged by its body')
assert(not Has(box.flags, ImGuiWindowFlags_NoDecoration), 'plain: imgui\'s own window, not the theme\'s')
assert(box.texts[1] == 'Goblin' and box.texts[2] == 'No debuffs seen', 'the target\'s name, and nothing seen yet')

Dia()
box = Frame()
assert(box.texts[2] == 'Effect 134' and box.texts[3]:match('^%d+s$') or box.texts[3]:match('^%d+:%d%d$'), 'Dia listed with its time left')
Paralyze()
local rows = debufflist.Rows(900, { })
assert(#rows == 2 and rows[1].left <= rows[2].left, 'the soonest to run out first')
assert((rows[1].id == 4 and rows[2].id == 134) or (rows[1].id == 134 and rows[2].id == 4), 'both listed')
assert(tracker.Get(900, 'dia'), 'tracked while the list alone is on')

o.clickThrough[1] = true
box = Frame()
assert(Has(box.flags, ImGuiWindowFlags_NoMove) and Has(box.flags, ImGuiWindowFlags_NoInputs), 'Lock Windows: held still, the mouse through it')
o.showConfig[1] = true -- organizing goes with the settings window open
organize.SetActive(true)
box = Frame()
assert(not Has(box.flags, ImGuiWindowFlags_NoMove), 'organizing: dragged, Lock Windows or not')
assert(box.texts[1] == 'Sample Target' and box.texts[2] == 'Effect 4' and box.texts[3] == '12s'
    and box.texts[6] == 'Effect 134' and box.texts[7] == '1:35', 'the sample: Paralyze, Slow and Dia with times of their own')
organize.SetActive(false)
o.showConfig[1], o.clickThrough[1] = false, false

-- the box is placed by the settings, and where it is dragged to is written back
local pos = o.target.debuffListPos
pos[1], pos[2] = 50, 60
local placed = H.calls.SetNextWindowPos or 0
Frame()
assert((H.calls.SetNextWindowPos or 0) == placed + 1, 'put where the settings say when they change')
assert(pos[1] == 100 and pos[2] == 200, 'where it is, written back to the settings')
placed = H.calls.SetNextWindowPos or 0
Frame()
assert((H.calls.SetNextWindowPos or 0) == placed, 'not placed again while only a drag moves it')

mainIndex = 0
assert(Frame() == nil, 'no target: no plain box')
mainIndex = 10

-- Winxi Theme: one of the addon's windows, with the theme's chrome and moved by Shift as the others are
o.target.debuffListTheme[1] = true
box = Frame()
assert(box ~= nil and Has(box.flags, ImGuiWindowFlags_NoDecoration), 'themed: drawn as the target windows are')
assert(Has(box.flags, ImGuiWindowFlags_NoMove), 'themed: held still without Shift')
windows.ShiftHeld = function() return true end
box = Frame()
assert(not Has(box.flags, ImGuiWindowFlags_NoMove), 'themed: moved with Shift held, as the other windows are')
windows.ShiftHeld = function() return false end
assert(box.texts[1] == 'Goblin' and box.texts[2] == 'Effect 4' or box.texts[2] == 'Effect 134', 'the same rows')
assert(not require('positioning').Managed('debuffs') and require('positioning').Managed('main'), 'never placed by Automatic Positioning')

-- off again, nothing else showing debuffs: the count is let go
o.target.debuffList[1] = false
assert(Frame() == nil, 'off: no box')
assert(not tracker.Get(900, 'dia'), 'nothing showing debuffs: tracking cleared')

local found, under = nil, { }
for _, tab in ipairs(require('options').Tabs) do
    for _, entry in ipairs(tab.entries) do
        if entry.kind == 'header' then found = tab.name .. ' -> ' .. entry.label end
        if entry.key == 'debuffList' or entry.key == 'debuffListTheme' or entry.key == 'debuffListPos' then
            assert(found == 'Target -> Debuff List', entry.key .. ' under Target -> Debuff List')
            under[entry.key] = entry
        end
    end
end
assert(under.debuffListTheme.under(o) == false, 'Winxi Theme greyed while the list is off')
o.target.debuffList[1] = true
assert(under.debuffListTheme.under(o) == true)
assert(under.debuffListPos.window == 'debuffs' and windows.List.debuffs.pos == 'debuffListPos', 'the Position row moves the box')
H.print('debuff list: a plain box dragged by its body, held by Lock Windows, the sample while organizing, placed and written back, Winxi Theme as the other windows, tracked alone, under Target -> Debuff List', true)
