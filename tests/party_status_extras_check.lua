-- winparty's Low Time Warning, Removable Marks and the status tooltip's caster, spell and what removes it
H.load()
require('winxi.gamedata').Root('addons/libs/winxi/data/') -- the server's statuses and durations, from the repository's data
local o = H.options()
local options, frames, draw, imgui = require('options'), require('frames'), require('draw'), require('imgui')
local details, tooltip = require('details'), require('winxi.tooltip')
local statustimes = require('winxi.statustimes')

H.print('settings: Low Time Warning', o.style.lowTime[1], '| Removable Marks off', o.style.removableMarks[1] == false)

-- 40 Protect 5 s left, yours; 33 Haste 50 s; 4 Paralysis an estimate 3 s; 2 Sleep nothing written
local said = { [40] = { '5', false, true, 5 }, [33] = { '50', false, false, 50 }, [4] = { '3', true, false, 3 } }
local realText, realLanding = statustimes.Text, statustimes.Landing
statustimes.Text = function(_, id) local e = said[id]; if e then return e[1], e[2], e[3], e[4] end return nil end
local member = { name = 'Member', serverId = 123, hp = 500, hpp = 50, mp = 200, mpp = 50, tp = 0, isInZone = true, isPlayer = true,
    statusIds = { 40, 33, 4, 2 } }
local texts, circles = {}, {}
draw.Texture = function() return 1 end
draw.Packed = function(color) return color end
draw.Image = function() end
draw.Text = function(x, y, color, words) texts[words] = color end
draw.Circle = function(x, y, radius, color) circles[#circles + 1] = color end
imgui.CalcTextSize = function(text) return #text * 8, 14 end
local function paint()
    texts, circles = {}, {}
    local style = options.Style(o)
    style.bookends, style.barGlow, style.buffDirection, style.buffFitScreen, style.buffLimit = false, 0, 'right', false, 8
    frames.Draw({ member }, 'party', function(id) return 1000 + id, false end, style)
    return style
end

o.style.showDurations[1] = true
local style = paint()
H.print('under 10 s: Low Time Color, over your own colour and over an estimate\'s', texts['5'] == style.lowTimeColor, texts['3'] == style.lowTimeColor)
H.print('50 s: not low', texts['50'] ~= style.lowTimeColor)
o.style.lowTime[1] = 0
style = paint()
H.print('at 0, no warning: yours in Your Color, the estimate in Estimate Color', texts['5'] == style.mineColor, texts['3'] == style.estimateColor)
o.style.lowTime[1] = 10

H.print('marks off: none', #circles == 0)
o.style.removableMarks[1] = true
style = paint()
-- each mark is an edge and a dot: Protect and Haste dispellable, Paralysis curable, Sleep neither
local cure, dispel = 0, 0
for _, color in ipairs(circles) do
    if color == style.cureMarkColor then cure = cure + 1 elseif color == style.dispelMarkColor then dispel = dispel + 1 end
end
H.print('marks: Paralysis curable, Protect and Haste dispellable, Sleep none', cure == 1, dispel == 2, #circles == 6)
o.style.removableMarks[1], o.style.showDurations[1] = false, false

-- the tooltip: time left, the spell and who cast it, and what removes it
local shown
local realShow = tooltip.Show
tooltip.Show = function(text) shown = text end
statustimes.Landing = function(_, id) if id == 4 then return { by = 0x1234, category = 4, param = 58 } end return nil end
local manager = AshitaCore.GetMemoryManager
AshitaCore.GetMemoryManager = function() return { GetEntity = function() return {
    GetServerId = function(_, index) return index == 77 and 0x1234 or 0 end,
    GetName = function(_, index) return index == 77 and 'Caster' or '' end } end } end
local resources = AshitaCore.GetResourceManager
AshitaCore.GetResourceManager = function()
    local base = resources and resources() or {}
    return setmetatable({ GetSpellById = function(_, id) return { Name = { id == 58 and 'Paralyze' or '?' } } end,
        GetString = function(_, _, id) return id == 4 and 'paralysis' or 'Status' end }, { __index = base })
end
details.Status(4, 123, 1)
H.print('tooltip: an estimate, the spell and who cast it, and what removes it', shown:find('Estimated remaining: 3s', 1, true) ~= nil,
    shown:find('Paralyze, by Caster', 1, true) ~= nil, shown:find('Removed by a -na spell or a waltz', 1, true) ~= nil)
details.Status(40, 123, 1)
H.print('your own Protect: remaining, not estimated; Dispel removes it', shown:find('\nRemaining: 5s', 1, true) ~= nil,
    shown:find('Removed by Dispel', 1, true) ~= nil, shown:find('Observed effects only', 1, true) == nil)
details.Status(2, nil)
H.print('no one known: the name alone', shown:find('\n', 1, true) == nil, shown)
tooltip.Show, statustimes.Text, statustimes.Landing = realShow, realText, realLanding
AshitaCore.GetMemoryManager, AshitaCore.GetResourceManager = manager, resources
