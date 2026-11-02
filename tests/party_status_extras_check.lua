-- winparty's Low Time Warning (the icon fading out and in), Removable Marks and the status tooltip's caster, spell and what removes it
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
local texts, circles, images = {}, {}, {}
statustimes.Blink = function() return 0.5 end -- the blink, held at half
draw.Texture = function() return 1 end
-- a colour as given, or, faded, its alpha with it
draw.Packed = function(color, alpha) if alpha ~= nil and alpha < 1 then return { faded = alpha } end return color end
draw.Image = function(texture, x1, y1, x2, y2, packed) if texture >= 1000 then images[texture - 1000] = { x1 = x1, y1 = y1, x2 = x2, y2 = y2, packed = packed } end end
draw.Text = function(x, y, color, words) texts[words] = color end
draw.Circle = function(x, y, radius, color) circles[#circles + 1] = { x = x, y = y, radius = radius, color = color } end
imgui.CalcTextSize = function(text) return #text * 8, 14 end
local function paint()
    texts, circles, images = {}, {}, {}
    local style = options.Style(o)
    style.bookends, style.barGlow, style.buffDirection, style.buffFitScreen, style.buffLimit = false, 0, 'right', false, 8
    frames.Draw({ member }, 'party', function(id) return 1000 + id, false end, style)
    return style
end

o.style.showDurations[1] = true
local style = paint()
local function faded(id) local image = images[id] return image ~= nil and type(image.packed) == 'table' and image.packed.faded end
H.print('under 10 s: the icon fading, yours and an estimate alike', faded(40) == 0.5, faded(4) == 0.5)
H.print('their times keep their colours', texts['5'] == style.mineColor, texts['3'] == style.estimateColor)
H.print('50 s: not fading', not faded(33))
o.style.lowTime[1] = 0
style = paint()
H.print('at 0, no warning: nothing fades', not faded(40) and not faded(4))
o.style.lowTime[1] = 10

H.print('marks off: none', #circles == 0)
o.style.removableMarks[1] = true
style = paint()
-- each mark is an edge and a dot: Protect and Haste dispellable, Paralysis curable, Sleep neither
local cure, dispel, inside = 0, 0, true
for index, circle in ipairs(circles) do
    if circle.color == style.cureMarkColor then cure = cure + 1 elseif circle.color == style.dispelMarkColor then dispel = dispel + 1 end
    -- each with its border inside its icon: the border is drawn first, then the dot in it
    if index % 2 == 1 then
        local any = false
        for _, image in pairs(images) do
            if circle.x - circle.radius >= image.x1 and circle.x + circle.radius <= image.x2
                and circle.y - circle.radius >= image.y1 and circle.y + circle.radius <= image.y2 then any = true end
        end
        inside = inside and any
    end
end
H.print('marks on a party member: Paralysis curable; Protect and Haste, a friend\'s, none; Sleep none', cure == 1, dispel == 0, #circles == 2)
H.print('each mark, its border too, inside its icon', inside)
local icon = images[4]
H.print('and small: under a quarter of the icon across', circles[1].radius * 2 < (icon.x2 - icon.x1) / 4)
-- on a monster: its buffs Dispel removes, and not its debuffs
member.isMonster = true
style = paint()
cure, dispel = 0, 0
for _, circle in ipairs(circles) do
    if circle.color == style.cureMarkColor then cure = cure + 1 elseif circle.color == style.dispelMarkColor then dispel = dispel + 1 end
end
H.print('marks on a monster: Protect and Haste dispellable; Paralysis, its debuff, none', dispel == 2, cure == 0, #circles == 4)
-- Only What You Can Remove: the player can take Protect off and nothing else
local cleanse = require('winxi.cleanse')
local realCan = cleanse.Can
cleanse.Can = function(id) return id == 40 end
o.style.removableOnlyMine[1] = true
style = paint()
H.print('only what you can remove, on a monster: Protect alone', #circles == 2, circles[2] and circles[2].color == style.dispelMarkColor)
member.isMonster = nil
style = paint()
H.print('on a party member: Paralysis, which you cannot cure, unmarked', #circles == 0)
cleanse.Can = function(id) return id == 4 end
style = paint()
H.print('learn to: marked', #circles == 2)
cleanse.Can, o.style.removableOnlyMine[1] = realCan, false
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
    local spellNames = { [58] = 'Paralyze', [15] = 'Paralyna', [95] = 'Esuna', [260] = 'Dispel', [360] = 'Dispelga',
        [462] = 'Magic Finale', [592] = 'Blank Gaze', [605] = 'Geist Wall' }
    return setmetatable({ GetSpellById = function(_, id) return { Name = { spellNames[id] or '?' } } end,
        GetString = function(_, _, id) return id == 4 and 'paralysis' or 'Status' end }, { __index = base })
end
details.Status(4, 123, 1)
H.print('tooltip: an estimate, the spell and who cast it, and what removes it', shown:find('Estimated remaining: 3s', 1, true) ~= nil,
    shown:find('Paralyze, by Caster', 1, true) ~= nil, shown:find('Removed by Paralyna or Esuna.', 1, true) ~= nil)
details.Status(40, 123, 1)
H.print('your own Protect: remaining, not estimated; Dispel and the like remove it', shown:find('\nRemaining: 5s', 1, true) ~= nil,
    shown:find('Removed by Dispel, Dispelga, Magic Finale, Blank Gaze or Geist Wall.', 1, true) ~= nil, shown:find('Observed effects only', 1, true) == nil)
local cleanseNow = require('winxi.cleanse')
local canBefore = cleanseNow.Can
cleanseNow.Can = function() return true end
details.Status(4, 123, 1)
H.print('tooltip: when you can cast one of them, it says so', shown:find('You can cast one now.', 1, true) ~= nil)
cleanseNow.Can = canBefore
details.Status(2, nil)
H.print('no one known: the name alone', shown:find('\n', 1, true) == nil, shown)
tooltip.Show, statustimes.Text, statustimes.Landing = realShow, realText, realLanding
AshitaCore.GetMemoryManager, AshitaCore.GetResourceManager = manager, resources

-- the target window knows a monster from its spawn flags: its marks are Dispel's; the samples are monsters
local target = require('target')
local monster = target.Line('main', { Name = 'Goblin', ServerId = 0x1000123, SpawnFlags = 0x10, HPPercent = 100, Distance = 4 })[1].isMonster
local player = target.Line('sub', { Name = 'Someone', ServerId = 0x456, SpawnFlags = 0x01, HPPercent = 100, Distance = 4 })[1].isMonster
local sample = target.Line('tot', target.Samples.tot)[1].isMonster
H.print('target: a monster is one, a player is not, the sample target is', monster == true, player == false, sample == true)

-- the Style tab: Status Display, Status Durations, Removable Marks, Status Filtering, in that order, each
-- with its own settings
local order, under = {}, {}
for _, tab in ipairs(options.Tabs) do
    if tab.name == 'Style' then
        local header
        for _, entry in ipairs(tab.entries) do
            if entry.kind == 'header' then header = entry.label; order[#order + 1] = header
            elseif entry.key then under[entry.key] = header end
        end
    end
end
local statusOrder = {}
for _, label in ipairs(order) do if label:find('Status') or label == 'Removable Marks' then statusOrder[#statusOrder + 1] = label end end
H.print('status groups in order', table.concat(statusOrder, '|') == 'Status Display|Status Durations|Removable Marks|Status Filtering|Advanced: Status IDs', table.concat(statusOrder, '|'))
H.print('each setting in its group', under.buffSize == 'Status Display', under.showDurations == 'Status Durations', under.lowTime == 'Status Durations',
    under.durationFont == 'Status Durations', under.removableMarks == 'Removable Marks', under.dispelMarkColor == 'Removable Marks')
