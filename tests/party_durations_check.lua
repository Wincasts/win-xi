-- winparty's Show Durations: the time left written under each status icon, its middle under the icon's,
-- an estimate in Estimate Color; the icon smaller, so icon and time fit the room the icon had, and the
-- rows as tall as without
H.load()
local o = H.options()
local options, frames, draw, imgui = require('options'), require('frames'), require('draw'), require('imgui')
local statustimes = require('winxi.statustimes')

local entries = {}
for _, tab in ipairs(options.Tabs) do
    for _, entry in ipairs(tab.entries) do if entry.key then entries[entry.key] = entry end end
end
H.print('Duration Font to begin with: Value Font\'s default', o.style.durationFont == 'ubuntu-bi.ttf')
H.print('settings: Show Durations off to begin with', o.style.showDurations[1] == false,
    '| Duration Text Size', o.style.durationSize[1], '| Estimate Color', table.concat(o.style.estimateColor, ','))
H.print('greyed while Show Durations is off', entries.durationSize.under(o) == false and entries.estimateColor.under(o) == false
    and entries.mineColor.under(o) == false, '| Your Color', table.concat(o.style.mineColor, ','))

-- what the module says of each status: 40 exact, 33 an estimate, 4 not known, 253 nothing written
local said = { [40] = { '1m', false }, [33] = { '30m', true }, [4] = { '-', true }, [41] = { '2m', true, true } }
local asked = {}
statustimes.Text = function(serverId, id, nth)
    asked[#asked + 1] = ('%s:%d:%d'):format(tostring(serverId), id, nth or 0)
    local entry = said[id]
    if entry then return entry[1], entry[2], entry[3] end
    return nil
end

local member = { name = 'Member', serverId = 123, hp = 500, hpp = 50, mp = 200, mpp = 50,
    tp = 0, isInZone = true, isPlayer = true, statusIds = { 40, 33, 4, 253 } }
local style = options.Style(o)
style.bookends, style.barGlow, style.buffDirection, style.buffFitScreen, style.buffLimit = false, 0, 'right', false, 8
local icons, texts = {}, {}
draw.Texture = function() return 1 end
draw.Packed = function(color) return color end
draw.Image = function(texture, x1, y1, x2, y2) if texture >= 1000 then icons[#icons + 1] = { id = texture - 1000, x1 = x1, y1 = y1, x2 = x2, y2 = y2 } end end
draw.Text = function(x, y, color, words) texts[#texts + 1] = { x = x, y = y, color = color, words = words } end
imgui.CalcTextSize = function(text) return #text * 8, 14 end
local function paint()
    icons, texts, asked = {}, {}, {}
    frames.Draw({ member }, 'party', function(id) return 1000 + id, false end, style)
end
local function under()
    local found = {}
    -- each text with the icon whose foot it is at and whose middle is nearest its own
    for _, text in ipairs(texts) do
        local middle, best, distance = text.x + #text.words * 8 / 2, nil, math.huge
        for _, icon in ipairs(icons) do
            local away = math.abs(middle - (icon.x1 + icon.x2) / 2)
            if math.abs(text.y - icon.y2) <= 1 and away < distance then best, distance = icon, away end
        end
        if best then found[#found + 1] = { text = text, icon = best } end
    end
    return found
end

paint()
local _, plainHeight = frames.FullSize(6, 'party', style)
local plainTop, plainFoot = icons[1].y1, icons[1].y2
H.print('off: nothing under the icons, nothing asked', #under() == 0, #asked == 0)

o.style.showDurations[1] = true
style = options.Style(o)
style.bookends, style.barGlow, style.buffDirection, style.buffFitScreen, style.buffLimit = false, 0, 'right', false, 8
paint()
local found = under()
local words = {}
for _, pair in ipairs(found) do words[#words + 1] = pair.text.words end
H.print('on: a duration under each icon that has one, none under 253', #found == 3, table.concat(words, ' '))
H.print('asked by the member\'s server id, each the first of its kind', asked[1] == '123:40:1', table.concat(asked, ' '))
local centred = true
for _, pair in ipairs(found) do
    local textMiddle = pair.text.x + #pair.text.words * 8 / 2
    centred = centred and math.abs(textMiddle - (pair.icon.x1 + pair.icon.x2) / 2) <= 1
end
H.print('each one\'s middle under its icon\'s', centred)
-- Duration Font: the durations' letters asked of it, apart from Value Font
local fonts = require('winxi.fonts')
local realGet = fonts.Get
local fontAsked = {}
fonts.Get = function(file) fontAsked[#fontAsked + 1] = file; return realGet(file) end
o.style.durationFont = 'georgia.ttf'
style = options.Style(o)
style.bookends, style.barGlow, style.buffDirection, style.buffFitScreen, style.buffLimit = false, 0, 'right', false, 8
paint()
local wanted = false
for _, file in ipairs(fontAsked) do if file == 'georgia.ttf' then wanted = true end end
H.print('Duration Font: the durations in it', wanted)
fonts.Get = realGet
o.style.durationFont = 'ubuntu-bi.ttf'
style = options.Style(o)
style.bookends, style.barGlow, style.buffDirection, style.buffFitScreen, style.buffLimit = false, 0, 'right', false, 8
local colours = {}
for _, pair in ipairs(found) do colours[pair.text.words] = pair.text.color end
H.print('exact in the text colour, estimates and - in Estimate Color', colours['1m'] ~= style.estimateColor,
    colours['30m'] == style.estimateColor, colours['-'] == style.estimateColor)
-- 41 cast by the player: Your Color, an estimate or not
member.statusIds = { 40, 41 }
paint()
colours = {}
for _, pair in ipairs(under()) do colours[pair.text.words] = pair.text.color end
H.print('one you cast: Your Color', colours['2m'] == style.mineColor, colours['1m'] ~= style.mineColor)
member.statusIds = { 40, 33, 4, 253 }
local _, timedHeight = frames.FullSize(6, 'party', style)
H.print('the windows no taller', timedHeight == plainHeight, plainHeight, timedHeight)
local iconTall, textTall = icons[1].y2 - icons[1].y1, (plainFoot - plainTop) - (icons[1].y2 - icons[1].y1)
H.print('the icon smaller, from the same top; it and the time as tall as the icon was', icons[1].y1 == plainTop,
    iconTall < plainFoot - plainTop, math.abs(textTall - iconTall * o.style.durationSize[1] / 100) <= 1, iconTall, textTall)

-- the player's own repeats: each asked for by its place among its kind
member.statusIds = { 214, 214 }
said[214] = { '30', false }
paint()
H.print('two of one kind: the first and the second', table.concat(asked, ' ') == '123:214:1 123:214:2', table.concat(asked, ' '))

-- a made-up member in the sample windows: sample durations, nothing asked
member.serverId, member.statusIds = -2001, { 40, 41, 33, 4 }
paint()
words = {}
for _, pair in ipairs(under()) do words[#words + 1] = pair.text.words end
H.print('a sample member: sample durations, nothing asked', #words == 4 and #asked == 0, table.concat(words, ' '))

-- two rows: the second under the first's durations
member.serverId, member.statusIds = 123, { 40, 33, 4, 40 }
style.buffRows, style.buffLimit = 2, 4
paint()
table.sort(icons, function(a, b) return a.y1 < b.y1 end)
local firstFoot = icons[1].y2
local lowestText = 0
for _, pair in ipairs(under()) do if pair.icon.y2 == firstFoot then lowestText = math.max(lowestText, pair.text.y + 1) end end
H.print('two rows: the second starts below the first\'s durations', icons[#icons].y1 > firstFoot + 1, icons[#icons].y1 - firstFoot)
local _, twoRows = frames.FullSize(6, 'party', style)
o.style.showDurations[1] = false
local untimed = options.Style(o)
untimed.bookends, untimed.barGlow, untimed.buffDirection, untimed.buffFitScreen, untimed.buffRows, untimed.buffLimit = false, 0, 'right', false, 2, 4
local _, twoRowsPlain = frames.FullSize(6, 'party', untimed)
H.print('two rows as tall with durations as without', twoRows == twoRowsPlain, twoRows, twoRowsPlain)
o.style.showDurations[1] = false
