-- frames: draws lines of bars. A list of members, of pets, or a target is a list of lines, and each
-- line is a name, an HP bar and a smaller MP bar with their figures, and TP as a figure alone, set out
-- the way XivParty, a party list addon for Windower 4 by Tylas, sets out its compact layout
-- (https://github.com/Tylas11/XivParty; its layouts/ffxi2.xml). The bars are that addon's images, in
-- assets/bars with its licence. What is XivParty's and is not here: its background, job icons and cursor;
-- its glow over a bar that changes; a mark for the quartermaster; and click-to-target behavior.
-- Status filtering and optional hover details are implemented locally. What is here and is not XivParty's: a soft
-- shadow under each bar, silver bookends at its ends, and circles for leaders.
--
--     frames.Draw(lines, kind, StatusTexture, style)
--
-- is called inside a window. It takes up the room the list needs and draws into it; buffs are drawn
-- beyond that room, beside the window. StatusTexture(id, useOwn) gives the texture for a status icon,
-- or nil, and whether it is one of winxi's own, which are narrower than they are tall.
--
-- kind is 'party' for the player's own party (its lines have buffs), 'alliance' or 'pets' for lines
-- without, and 'target' for a line whose HP figure is under its bar, level with the TP figure.
--
-- A line is a table of:
--     name, serverId           what is kept for a line between frames goes by its serverId
--     isInZone, zoneId         isInZone false for a member in another area: the line is their name and its
--     hp, hpp, mp, mpp, tp     mpp left out for a line with no MP bar, tp for one with no TP
--     hpText, mpText, tpText   a figure in words of the line's own, in place of the number
--     noMp                     the most MP they can have is none: a grey, full MP bar and no MP figure
--     plainHp                  an HP figure that keeps its colour however low the HP is
--     isPartyLeader, isAllianceLeader          a circle before the name, or two
--     isTarget, isSubTarget, isPartyTarget     native DAT cursor before the name; text markers on load failure
--     isPlayer, targetIndex, entity            for how far away they are: bars dim with distance
--     statusIds                their buffs
--
-- style says how (options.lua makes one from the settings), each left out for the usual:
--     scale, nameSize, valueSize, buffSize     percentages: of everything, and of each alone
--     buffSpacing, buffDistance                room between buff icons, and between them and the window
--     ffxivIcons               false for the game's own status icons in place of winxi's
--     hpOffset, mpOffset, tpOffset             { x, y } to move that figure from its place
--     bookends, tpFlash                        false to leave each out
--     nameFont, valueFont      a font file of C:\Windows\Fonts for the names or the values; nil or '' for the theme's
--     bookendOpacity                           0 to 100: how solid the bookends are (100 unless given)
--     barGlow                  0 to 100: how bright the light at the end of each fill is (none unless given)
--     barBackdrop              a colour for the empty part of the bars, over their back; nil for none
--     barFrame                 'capsule' or 'capsule_silver' for a capsule's rim in place of the texture's frame
--     showMp, showTp           false to leave the MP or the TP figure out; the MP bar is drawn either way
--     nameChars                at most this many characters of a name, as well as what fits (nil: no limit)
--     trimLast                 true for a list that is the last thing in its window: its last line is
--                              then only as tall as what is on it
require('common')
local imgui = require('imgui')
local theme = require('winxi.theme')
local fonts = require('winxi.fonts')
local outlinedText = require('winxi.text')
local draw = require('draw')
local colors = require('colors')
local statusicons = require('winxi.statusicons')
local cursor = require('winxi.cursor')
local statuses = require('statuses')
local details = require('details')
local perf = require('perf')
local function TextSize(text)
    perf.Count('text measurements')
    return imgui.CalcTextSize(text)
end

local frames = { }

local castRange = 20.79       -- beyond this a member's bars are dimmed, and beyond targetRange dimmed further
local targetRange = 50
local beyondCastOpacity = 0.7    -- how much of a bar's colour is left beyond casting range
local beyondTargetOpacity = 0.45 -- and beyond targeting range, or where the distance is not known

-- A colour as XivParty's layouts write it
local function Hex(code)
    return { tonumber(code:sub(1, 2), 16) / 255, tonumber(code:sub(3, 4), 16) / 255, tonumber(code:sub(5, 6), 16) / 255, 1 }
end

local white = { 1, 1, 1, 1 }
local black = { 0, 0, 0, 1 }
local hpYellow = Hex('F3F37C') -- an HP figure below 75%
local hpOrange = Hex('F8BA80') -- below 50%
local hpRed = Hex('FC8182')    -- below 25%
-- A TP figure at 1000 and over pulses between a light blue and a deeper one, so that TP that can be
-- used is noticed: there and back once every tpPulsePeriod seconds
local tpFull = Hex('50B4FA')
local tpFullLight = Hex('C4E6FF')
local tpPulsePeriod = 1.2
local tpPulse = { 0, 0, 0, 1 } -- the colour it is, for the list being drawn
local tpPulseBlend = 1          -- how far from the light blue towards the deeper one the pulse is this frame
local noMpGrey = { 0.55, 0.55, 0.55, 1 } -- the MP bar of a member with no MP to have: grey, and full

local barShadowReach = 3 -- how far below a bar its shadow goes
local hpColor, mpColor = Hex('FF9597'), Hex('FFFF9C') -- what the bars' images, which are grey, are tinted

-- The bookends: a small silver cap at each end of a bar, as tall as the whole bar, frame and all, and
-- standing half on it, after the ones the bars of the game's own party list have. A cap is an image:
-- it shares the bar's front image, to the right of the front, so that the two are drawn as one batch.
local bookend = { width = 3.6, over = 1.8 } -- how wide a cap is, and how far past the bar's inside its frame goes, above and below
-- Rounded caps (after the game's own) are not on the bar's ends but beyond them, carrying the bar on: as
-- tall as its frame, which is edge past its inside above and below, and width times as wide as that. The
-- image is the left one; the right is the same turned about.
local rounded = { edge = 1.2, width = 0.55 }
local roundedStyles = { rounded = true, rounded_silver = true }

-- A capsule's rim, in place of the texture's frame: along the bar above and below its inside, as far out
-- as a rounded cap reaches, its outer part (outer of it) in the rim's dark colour and the rest in its
-- light one, as the rounded caps are. Where the caps are not rounded, its ends are closed square.
local capsuleFrames = {
    capsule = { dark = { 10 / 255, 52 / 255, 150 / 255, 1 }, light = { 40 / 255, 214 / 255, 1, 0.85 } },
    capsule_silver = { dark = { 40 / 255, 46 / 255, 60 / 255, 1 }, light = { 184 / 255, 194 / 255, 210 / 255, 0.85 } },
}
local capsuleOuter = 0.58

-- The light at the end of a fill: an image as tall as the fill's, brightest at its right edge, glow
-- times the frame's height long, drawn over the fill's end in white
local glowFile = 'bars/glow.png'
local glow = 0.55

-- The layout: where everything on a line is, from the line's top left, and how big, in pixels at a
-- scale of 100. It began as XivParty's own numbers, a fifth larger, without the job icon and cursor
-- that layout has to the left of the name: the name starts the line.
--
-- A bar is three images, a back, a fill and a front, tinted its colour. frame is where the back and
-- the front go; the fill starts at fill.x, on the frame's top and of its height, and is fill.width
-- long when the bar is full. body is the inside of the bar: its ends are where the bookends go, and
-- its bottom is what a line's height is reckoned from. figure is where the bar's value is written:
-- with alignRight its right end goes there. The front's image has the bar's cap in it as well:
-- frontPart is how far across the image the front itself goes, and cap the part that is the cap, as
-- left, top, right and bottom, each from 0 to 1.
local barTextureSets = { glass = true, detailed = true, crystal = true, satin = true, runic = true, classic = true, radiant = true,
    chrome = true, flat = true, segmented = true, ember = true,
    kingdom = true, magitek = true, aether = true, elven = true, gothic = true,
    enamel = true, enamel_rim = true, enamel_gradient = true, tube = true, tube_deep = true, glass_enamel = true }
local bookendFiles = {}  -- one to match each of winxi's window borders, by its name
for _, style in ipairs({ 'silver', 'bronze', 'ffxi', 'crystal', 'royal', 'obsidian', 'royal_silver', 'royal_platinum',
    'mythril', 'adaman', 'jade', 'amethyst', 'kingdom', 'magitek', 'aether', 'elven', 'gothic', 'rounded', 'rounded_silver' }) do
    bookendFiles[style] = 'bookends/' .. style .. '.png'
end
bookendFiles.obsidian_plain = bookendFiles.obsidian -- Plain Obsidian's border matches Obsidian's bookends
local wholeCap = { 0, 0, 1, 1 }
local barKinds = { 'hp', 'mp' }
local barTextureSet = false -- the set the bars' paths below were last made for: none yet (nil is the usual set)
local layout = {
    width = 163.2, rowHeight = 38.4,
    valueSize = 14.72, -- the HP, MP and TP figures are written at one size, in pixels as the names' is
    hp = { value = 'hp', color = hpColor,
           back = 'bars/hp_back.png', fillImage = 'bars/hp_fill.png', front = 'bars/hp_front.png',
           frame = { x = 18, y = 9.6, width = 132, height = 16.8 },
           frontPart = 220 / 226, cap = { 222 / 226, 0, 1, 14 / 28 },
           fill = { x = 22.8, width = 122.4 },
           body = { left = 21.6, top = 13.2, right = 146.4, bottom = 22.8 },
           figure = { x = 144, y = 4.8, alignRight = true } },
    mp = { value = 'mp', color = mpColor,
           back = 'bars/mp_back.png', fillImage = 'bars/mp_fill.png', front = 'bars/mp_front.png',
           frame = { x = 66, y = 21.6, width = 98.4, height = 14.4 },
           frontPart = 164 / 170, cap = { 166 / 170, 0, 1, 11 / 24 },
           fill = { x = 70.8, width = 88.8 },
           body = { left = 69.6, top = 25.2, right = 160.8, bottom = 32.4 },
           figure = { x = 158.4, y = 18, alignRight = true } },
    -- a target's HP figure, in place of the one above: under the bar, level with the TP figure, its
    -- right end at the bar's. It goes up and down with the TP figure, wherever that has been moved to
    -- (levelWithTp), and is not moved as the HP figure on a bar is.
    targetHpFigure = { x = 145.2, y = 21.6, alignRight = true, levelWithTp = true },
    -- TP is a figure alone, to the left of the MP bar: in the same place on every line, the player's
    -- party, the other two and the pets alike, and level with the MP bar
    tp = { value = 'tp', figure = { x = 67.2, y = 21.6, alignRight = true } },
    name = { x = 0, y = 0, size = 18.4 }, -- as much of it as fits before the HP bar's right end
    zone = { x = 163.2, y = 16.8, size = 18.4, maxChars = 16 }, -- its right end goes at x
    -- the buffs run leftwards from the window's edge, sixteen at most; gap is between the two, whatever the scale
    buffs = { y = 6, size = 24, gap = 4, most = 16 },
}

-- What is being drawn: set by Draw and by each member's turn, and read by the helpers below
local scale = 1
local itemX, itemY = 0, 0 -- the top left of the member being drawn, on screen
local textColor = white   -- the theme's
local valueScale = 1      -- how much larger or smaller than the layout's the HP, MP and TP figures are
local nameScale = 1       -- and the names
local buffScale = 1       -- and the buff icons
local buffSpacing = 0     -- the room between one buff icon and the next
local ownIcons = true     -- winxi's status icons, where it has one, in place of the game's
local bookends = true     -- whether the bars have caps
local bookendFile = nil   -- separate ornamental cap, or the selected bar's atlas
local bookendAlpha = 1    -- how solid the caps are, 0 to 1
local roundedCaps = false -- whether the caps are rounded, beyond the bar's ends
local glowAlpha = 0       -- how bright the light at a fill's end is, 0 to 1
local backdropColor = nil -- the empty part of a bar's colour, or nil to leave its back as it is
local capsuleFrame = nil  -- the capsule's rim (capsuleFrames), or nil for the texture's own frame
local valueOffsets = { }  -- hp, mp, tp -> { x, y }: how far that figure is moved from its place, if at all
local outlined = true     -- whether the names and figures have winxi's dark edge
local nameChars = nil     -- how much of a name is written, where it is not the layout's own
local activeStyle = {}
local rowHeight = layout.rowHeight
local function RowHeight(style, kind)
    if (kind == 'party' or kind == 'target') and (style.buffRows or 1) > 1 then
        return math.max(layout.rowHeight, layout.buffs.y + 2 * layout.buffs.size * (style.buffSize or 100) / 100 + 3)
    end
    return layout.rowHeight
end

-- An image, by its file or the number of a texture, at a place in the layout's units; u2, if given,
-- is how far across the image the part to draw goes, from its left (0 to 1)
local function Image(image, x, y, width, height, color, alpha, u2, u1)
    local handle = type(image) == 'number' and image or draw.Texture(image)
    if not handle or width == 0 then
        return
    end

    local left, top = itemX + x * scale, itemY + y * scale
    draw.Image(handle, left, top, left + width * scale, top + height * scale, draw.Packed(color or white, alpha or 1), u1 or 0, 0, u2, 1)
end

local outlineEdge = 1     -- how thick winxi's dark edge is, for this list
local outlinePacked = 0   -- and its colour

-- The size of font on screen for text of a size in the layout
local function FontSize(size)
    return size * scale
end

-- A line of text at a place in the layout's units, in the font in use: the font is pushed by whoever
-- writes a run of text of one size. With width, the text's own, its right end goes at x.
local function Write(text, x, y, color, width)
    local left = math.floor(itemX + x * scale - (width or 0))
    local top = math.floor(itemY + y * scale)
    if outlined then
        draw.Text(left, top, draw.Packed(color or textColor, 1), text, outlineEdge, outlinePacked)
    else
        draw.Text(left, top, draw.Packed(color or textColor, 1), text)
    end
end

-- Names cut short, kept: by how many characters, then by name
local trimmed = { }
local trimmedCount = 0

local function Trimmed(text, maxChars)
    if maxChars == nil or #text <= maxChars then
        return text
    end

    local byLength = trimmed[maxChars]
    if byLength == nil then
        byLength = { }
        trimmed[maxChars] = byLength
    end
    local short = byLength[text]
    if short == nil then
        -- targets come and go: start afresh now and then rather than keep every name ever seen
        if trimmedCount > 256 then
            trimmed, trimmedCount = { [maxChars] = { } }, 0
            byLength = trimmed[maxChars]
        end
        short = text:sub(1, math.max(1, maxChars - 1)) .. '...'
        byLength[text] = short
        trimmedCount = trimmedCount + 1
    end
    return short
end

-- A name as much of it as fits in room pixels, in the font and size pushed: all of it if it fits, or
-- as many of its first letters as fit with '...' after them. At least one letter, whatever the room.
local ellipsis = '...'

local function Fitted(text, room)
    if TextSize(text) <= room then
        return text
    end
    local low, high = 1, #text - 1
    while low < high do
        local middle = math.floor((low + high + 1) / 2)
        if TextSize(text:sub(1, middle) .. ellipsis) <= room then
            low = middle
        else
            high = middle - 1
        end
    end
    return text:sub(1, low) .. ellipsis
end

-- An area's name as it is written, in brackets and cut short, by the area's number: the game's own
-- name for it, or with Short Zone Names its short form (the whole name where it has none), asked for
-- once each. False where the game has neither.
local zoneTexts = { [true] = { }, [false] = { } }

local function ZoneText(id, maxChars)
    local short = activeStyle.zoneAbbr == true
    local known = zoneTexts[short]
    local text = known[id]
    if text == nil then
        local resources = AshitaCore:GetResourceManager()
        local name = short and resources:GetString('zones.names_abbr', id)
        if type(name) ~= 'string' or name == '' then name = resources:GetString('zones.names', id) end
        text = (type(name) == 'string' and name ~= '') and Trimmed(('(%s)'):format(name), maxChars) or false
        known[id] = text
    end
    return text
end

-- What is kept for each line between frames, by member: each figure as it was last written, so that
-- it is only made into words and measured again when it changes
local animations = { }
local animationCount = 0
local lastFrame = os.clock() -- when a list was last drawn in a frame of its own
local displayWidth, displayHeight = nil, nil -- the screen's size, asked for once a frame

-- A line with no id yet (a member the game has not finished telling of) goes by its place in the
-- list: lines that shared one would be drawn with one another's bars.
local function Animation(member, index)
    local key = member.serverId
    if key == nil or key == 0 then
        key = -(4000 + index)
    end
    local state = animations[key]
    if state == nil then
        -- members come and go: start afresh now and then rather than keep every one ever seen
        if animationCount > 64 then
            animations, animationCount = { }, 0
        end
        state = { hp = { }, mp = { }, tp = { } }
        animations[key] = state
        animationCount = animationCount + 1
    end
    return state
end

-- How far away a member is, as how strongly their bars are drawn: 1 within casting range, less within
-- targeting range, and less again beyond it or where the distance is not known.
-- A member made up to fill the list while it is being arranged is taken to be beside the player.
local function RangeOpacity(member)
    if member.isPlayer or (member.targetIndex == nil and member.isInZone) then
        return 1
    end
    local entity = member.entity
    if entity == nil or entity.Distance == nil then
        return beyondTargetOpacity
    end

    local distance = math.sqrt(entity.Distance)
    if distance <= castRange then
        return 1
    elseif distance <= targetRange then
        return beyondCastOpacity
    end
    return beyondTargetOpacity
end

-- The lines of the list being drawn: what is kept for each, and where each is on screen
local lineStates, lineY = { }, { }

-- The layers of a bar, each drawn for every line before the next: a list is drawn a layer at a time
-- and not a line at a time, so that what is drawn with one image, or in one font, is drawn together.
-- Under a bar goes a soft shadow, down and to the right, to lift it off the window: the bar's own back
-- in black, twice, the further one fainter.
local function ShadowNear(place)
    local frame = place.frame
    Image(place.back, frame.x + 1.2, frame.y + 1.8, frame.width, frame.height, black, 0.45)
end

local function ShadowFar(place)
    local frame = place.frame
    Image(place.back, frame.x + 2.4, frame.y + 3, frame.width, frame.height, black, 0.2)
end

-- A line's bar is in the bar's own colour unless the line has another for it (bar.color)
local function Back(place, bar)
    local frame = place.frame
    Image(place.back, frame.x, frame.y, frame.width, frame.height, bar.color or place.color)
end

local function Fill(place, bar, opacity)
    local frame, fill = place.frame, place.fill
    Image(place.fillImage, fill.x, frame.y, fill.width * bar.fraction, frame.height, bar.color or place.color, opacity)
end

-- The empty part of a bar, in a colour of its own: over the back and under the fill, on the bar's inside
local function Backdrop(place)
    local body = place.body
    draw.Rect(math.floor(itemX + body.left * scale + 0.5), math.floor(itemY + body.top * scale + 0.5),
        math.floor(itemX + body.right * scale + 0.5), math.floor(itemY + body.bottom * scale + 0.5), draw.Packed(backdropColor, 1))
end

-- The light at the end of a fill, over its last part: all of the image where the fill is longer than
-- it, and as much of its right end as fits where it is not
local function Glow(place, bar, opacity)
    local length = place.fill.width * bar.fraction
    if length <= 0 then
        return
    end
    local frame = place.frame
    local full = frame.height * glow
    local width = math.min(length, full)
    Image(glowFile, place.fill.x + length - width, frame.y, width, frame.height, white, glowAlpha * opacity, 1, 1 - width / full)
end

local function Front(place, bar)
    local frame = place.frame
    Image(place.front, frame.x, frame.y, frame.width, frame.height, bar.color or place.color, 1, place.frontPart)
end

-- A bar's two bookends. Each is the cap's image, put on whole pixels: at a scale of 100 that is the
-- image's own size, so it is drawn as it is, pixel for pixel, and at any other it is stretched to fit.
-- Every cap is the same whole number of pixels wide, wherever its bar's end falls.
local function Cap(texture, part, centre, top, bottom)
    local width = math.max(2, math.floor(bookend.width * scale + 0.5))
    local left = math.floor(itemX + centre * scale - width / 2 + 0.5)
    top, bottom = math.floor(itemY + top * scale + 0.5), math.floor(itemY + bottom * scale + 0.5)
    draw.Image(texture, left, top, left + width, bottom, draw.Packed(white, bookendAlpha), part[1], part[2], part[3], part[4])
end

-- The capsule's rim, on whole pixels: a band above and below the bar's inside, reaching as far out as a
-- rounded cap does, each its dark outer part and its light inner one; and, unless rounded caps close
-- them, the same at each end
-- How much of a rim edge pixels deep is its dark outer part
local function Outer(edge)
    return edge > 1 and math.max(1, math.min(edge - 1, math.floor(edge * capsuleOuter + 0.5))) or 0
end

-- A band of the rim, where it has room
local function Band(x1, y1, x2, y2, packed)
    if x2 > x1 and y2 > y1 then draw.Rect(x1, y1, x2, y2, packed) end
end

local function CapsuleRim(place)
    local body = place.body
    local top = math.floor(itemY + (body.top - rounded.edge) * scale + 0.5)
    local bottom = math.floor(itemY + (body.bottom + rounded.edge) * scale + 0.5)
    local inTop = math.floor(itemY + body.top * scale + 0.5)
    local inBottom = math.floor(itemY + body.bottom * scale + 0.5)
    local left = math.floor(itemX + body.left * scale + 0.5)
    local right = math.floor(itemX + body.right * scale + 0.5)
    -- each side its own, as it rounds: a rim of one pixel is all light, which shows; of more, at
    -- least one pixel of each
    top, bottom = math.min(top, inTop - 1), math.max(bottom, inBottom + 1)
    local above, below = Outer(inTop - top), Outer(bottom - inBottom)
    local dark, light = draw.Packed(capsuleFrame.dark, 1), draw.Packed(capsuleFrame.light, 1)
    Band(left, top, right, top + above, dark)
    Band(left, top + above, right, inTop, light)
    Band(left, inBottom, right, bottom - below, light)
    Band(left, bottom - below, right, bottom, dark)
    if not (bookends and roundedCaps) then
        local edge = inTop - top
        local outer = Outer(edge)
        Band(left - edge, top, left - edge + outer, bottom, dark)
        Band(left - edge + outer, top + above, left, bottom - below, light)
        Band(right + edge - outer, top, right + edge, bottom, dark)
        Band(right, top + above, right + edge - outer, bottom - below, light)
    end
end

-- A rounded cap at each end, beyond it: the left one with its flat side on the bar's left end, the right
-- turned about with its flat side on the right end. Both on whole pixels, of one width.
local function RoundedCaps(place, texture)
    local body = place.body
    local top = math.floor(itemY + (body.top - rounded.edge) * scale + 0.5)
    local bottom = math.floor(itemY + (body.bottom + rounded.edge) * scale + 0.5)
    local width = math.max(2, math.floor((bottom - top) * rounded.width + 0.5))
    local packed = draw.Packed(white, bookendAlpha)
    local left = math.floor(itemX + body.left * scale + 0.5)
    draw.Image(texture, left - width, top, left, bottom, packed, 0, 0, 1, 1)
    local right = math.floor(itemX + body.right * scale + 0.5)
    draw.Image(texture, right, top, right + width, bottom, packed, 1, 0, 0, 1)
end

-- the top and bottom of a cap are those of the bar's frame
local function Bookends(place)
    local texture = bookendFile and draw.Texture(bookendFile)
    if texture and roundedCaps then
        RoundedCaps(place, texture)
        return
    end
    local part = texture and wholeCap or place.cap
    texture = texture or draw.Texture(place.front)
    if not texture then
        return
    end
    local body = place.body
    local top, bottom = body.top - bookend.over, body.bottom + bookend.over
    Cap(texture, part, body.left, top, bottom)
    Cap(texture, part, body.right, top, bottom)
end

-- One layer of a bar, for every line that has the bar: every line in the area has an HP bar, and an
-- MP bar unless it has no MP to show (another player's pet)
local function Layer(count, kind, place, paint)
    for index = 1, count do
        local state = lineStates[index]
        if state.inZone and (kind == 'hp' or state.hasMp) then
            itemY = lineY[index]
            paint(place, state[kind], state.opacity)
        end
    end
end

local function DrawBars(count, kind, place)
    if activeStyle.barShadows ~= 'off' then Layer(count, kind, place, ShadowNear) end
    if activeStyle.barShadows == nil or activeStyle.barShadows == 'full' then Layer(count, kind, place, ShadowFar) end
    Layer(count, kind, place, Back)
    if backdropColor then Layer(count, kind, place, Backdrop) end
    Layer(count, kind, place, Fill)
    if glowAlpha > 0 then Layer(count, kind, place, Glow) end
    if capsuleFrame then
        Layer(count, kind, place, CapsuleRim)
    else
        Layer(count, kind, place, Front)
    end
    if bookends then
        Layer(count, kind, place, Bookends)
    end
end

-- A leader's mark: a circle in front of the name, where the name's first letter would be, in the
-- party's colour for a party's leader. An alliance's leader has two, one over the other: the
-- alliance's above and the party's below. Drawn in the names' font, whose size on screen is nameFont.
-- Returns how much room it took, in the layout's units, for the name to start after it.
local nameFont = 0
local nameFontFile = nil  -- the names' font, as chosen: a name is fitted again when it changes
local valueFontFile = nil -- the values' font, as chosen: a value's width is measured again when it changes

local function Circle(x, y, radius, color)
    if outlined then
        draw.Circle(x, y, radius + outlineEdge, outlinePacked)
    end
    draw.Circle(x, y, radius, draw.Packed(color, 1))
end

local function DrawLeaderMarks(member)
    local name = layout.name
    local radius = nameFont * 0.19
    local centre = math.floor(itemX + name.x * scale) + radius + 1
    local top = math.floor(itemY + name.y * scale)

    if member.isAllianceLeader then
        -- a little smaller than one alone, and a little apart
        local small = nameFont * 0.17
        Circle(centre, top + nameFont * 0.26, small, colors.Alliance)
        Circle(centre, top + nameFont * 0.78, small, colors.Party)
    else
        Circle(centre, top + nameFont * 0.52, radius, colors.Party)
    end
    return (2 * radius + 1 + nameFont * 0.22) / scale
end

-- A member's name after their leader's mark and the game's animated DAT cursor when selected.
-- Names retain blue/green selection colours. Text markers are the fallback if the DAT cannot load.
local function DrawName(member, state)
    local name = layout.name
    local full = Trimmed(member.name or '???', nameChars)
    local x = name.x
    if member.isPartyLeader or member.isAllianceLeader then
        x = x + DrawLeaderMarks(member)
    end
    if member.isInZone and member.hpp and member.hpp <= (activeStyle.lowHp or 0) and (activeStyle.lowHp or 0) > 0 then
        Write('!', x, name.y, hpRed)
        x = x + TextSize('! ') / scale
    end

    local mark, color = nil, nil
    if member.isSubTarget or member.isPartyTarget then
        mark, color = '> ', colors.Green
    elseif member.isTarget then
        mark, color = '>> ', colors.Blue
    end

    if mark then
        local handle, uv = cursor.Get()
        if handle then
            -- Use the horizontal anc_s sprite, preserving the DAT's colours and aspect ratio.
            local height = nameFont
            local width = height * uv[5] / uv[6]
            local left = math.floor(itemX + x * scale - width - 3 * scale)
            local top = math.floor(itemY + name.y * scale)
            draw.Image(handle, left, top, left + width, top + height, draw.Packed(white, 1),
                uv[1], uv[2], uv[3], uv[4])
        else
            -- Text fallback overlays in the same place; selection never shifts the name.
            Write(mark, x, name.y, color, TextSize(mark))
        end
    end

    -- as much of the name as fits between where it starts and the right end of the HP bar, worked out
    -- again only when the name, its room, its mark or its font has changed
    local hpFrame = layout.hp.frame
    local room = math.floor((hpFrame.x + hpFrame.width - x) * scale + 0.5)
    if state.fitFrom ~= full or state.fitRoom ~= room or state.fitFont ~= nameFont or state.fitFace ~= nameFontFile then
        state.fitFrom, state.fitRoom, state.fitFont, state.fitFace = full, room, nameFont, nameFontFile
        state.fitted = Fitted(full, room)
    end
    Write(state.fitted, x, name.y, color)
end

-- A bar's figure, or for TP, which has no bar, the figure that is all there is of it. fontSize is the
-- size it is written at, which its width goes with. figure is where it goes, if not the bar's usual.
local function DrawFigure(place, member, kept, fontSize, figure)
    local kind = place.value
    local amount = (kind == 'hp' and member.hp) or (kind == 'mp' and member.mp) or (kind == 'tp' and member.tp) or -1

    local color = nil
    if amount >= 0 then
        if kind == 'hp' and not member.plainHp then
            local percent = member.hpp or 0
            if percent < 25 then
                color = hpRed
            elseif percent < 50 then
                color = hpOrange
            elseif percent < 75 then
                color = hpYellow
            end
        elseif kind == 'tp' and amount >= 1000 and not member.tpText then
            color = tpPulse
        end
    end

    -- a line may give a figure in its own words: a pet's HP is known only as a percentage
    local words = (kind == 'hp' and member.hpText) or (kind == 'mp' and member.mpText) or (kind == 'tp' and member.tpText)
    if not words then
        if kept.amount ~= amount then
            kept.amount = amount
            kept.words = amount < 0 and '?' or tostring(amount)
        end
        words = kept.words
    end

    figure = figure or place.figure
    local x, y = figure.x, figure.y
    if figure.levelWithTp then
        local tpOffset = valueOffsets.tp
        y = y + (tpOffset and tonumber(tpOffset[2]) or 0)
    else
        local offset = valueOffsets[kind]
        if offset ~= nil then
            x, y = x + (tonumber(offset[1]) or 0), y + (tonumber(offset[2]) or 0)
        end
    end

    local width = nil
    if figure.alignRight then
        if kept.measured ~= words or kept.fontSize ~= fontSize or kept.font ~= valueFontFile then
            kept.measured, kept.fontSize, kept.font, kept.width = words, fontSize, valueFontFile, TextSize(words)
        end
        width = kept.width
    end
    Write(words, x, y, color, width)
end

-- A member's buffs, running leftwards: the first has its right edge at x
local function DrawBuffs(member, x, StatusTexture)
    if member.statusIds == nil or StatusTexture == nil then return end
    local ids = statuses.Select(member.statusIds, activeStyle)
    local buffs = layout.buffs
    local size = buffs.size * buffScale
    local y = buffs.y + (buffs.size - size) / 2
    local windowLeft = imgui.GetWindowPos()
    local windowWidth = imgui.GetWindowSize()
    local distance = buffs.gap + (tonumber(activeStyle.buffDistance) or 0) * scale
    local direction, anchor, columns, capacity = statuses.Plan(activeStyle,
        itemX + x * scale, windowLeft + windowWidth + distance, displayWidth, size * scale, buffSpacing * scale)
    local start = (anchor - itemX) / scale
    x = start
    local shown = 0
    local iconCapacity = capacity
    if activeStyle.buffOverflow ~= false and #ids > capacity then iconCapacity = math.max(0, capacity - 1) end
    for _, id in ipairs(ids) do
        if shown >= iconCapacity then break end
        local texture, own = StatusTexture(id, ownIcons)
        if texture ~= nil then
            if shown > 0 and shown % columns == 0 then x = start; y = y + size + 2 end
            local width = own and size * statusicons.OwnAspect or size
            if direction == 'left' then x = x - width end
            Image(texture, x, y, width, size, nil, nil, own and statusicons.OwnRight or nil, own and statusicons.OwnLeft or nil)
            if details.Hover(itemX + x * scale, itemY + y * scale,
                itemX + (x + width) * scale, itemY + (y + size) * scale) then
                details.Status(id, member.statusServerId)
            end
            x = direction == 'left' and x - buffSpacing or x + width + buffSpacing
            shown = shown + 1
        end
    end
    if activeStyle.buffOverflow ~= false and #ids > shown then
        -- Reserve the last status slot for the badge rather than covering HP/name text.
        if capacity > 0 then
            if shown > 0 and shown % columns == 0 then x = start; y = y + size + 2 end
            if direction == 'left' then x = x - size end
        else
            -- No external room at all: a compact badge in the otherwise empty lower-left corner.
            x, y = 0, layout.tp.figure.y
        end
        imgui.PushFont(nil, math.min(14, size * 0.6) * scale)
        Write('+' .. (#ids - shown), x, y, textColor)
        imgui.PopFont()
    end
end

-- How far down its row the lowest thing on a line is, in the layout's units: the line's height when
-- it is the last in its window. Never more than a row.
local function LineHeight(member, kind, showMp, showTp)
    local name = layout.name
    local bottom = name.y + name.size * nameScale

    if not member.isInZone then
        -- the area's name is all there is under the member's own
        local zone = layout.zone
        bottom = math.max(bottom, zone.y + zone.size)
    else
        local valueHeight = layout.valueSize * valueScale
        local tpOffset = valueOffsets.tp
        local tpOffsetY = tpOffset and tonumber(tpOffset[2]) or 0

        local hp = layout.hp
        bottom = math.max(bottom, hp.body.bottom + barShadowReach)
        if kind == 'target' then
            bottom = math.max(bottom, layout.targetHpFigure.y + tpOffsetY + valueHeight)
        else
            local offset = valueOffsets.hp
            bottom = math.max(bottom, hp.figure.y + (offset and tonumber(offset[2]) or 0) + valueHeight)
        end

        if member.mpp ~= nil then
            local mp = layout.mp
            bottom = math.max(bottom, mp.body.bottom + barShadowReach)
            if showMp and not member.noMp then
                local offset = valueOffsets.mp
                bottom = math.max(bottom, mp.figure.y + (offset and tonumber(offset[2]) or 0) + valueHeight)
            end
        end

        if showTp and member.tp ~= nil then
            local tp = layout.tp
            bottom = math.max(bottom, tp.figure.y + tpOffsetY + valueHeight)
        end
    end

    if kind == 'party' or kind == 'target' then bottom = math.max(bottom, rowHeight > layout.rowHeight and rowHeight - 1.2 or 0) end
    return math.min(rowHeight, bottom + 1.2)
end

local room = { 0, 0 }
local clipMin, clipMax = { 0, 0 }, { 0, 0 }

-- A percentage as a multiplier: 1 where there is none, or none that makes sense
local function Percent(value)
    return (type(value) == 'number' and value > 0) and value / 100 or 1
end

local usual = { }

-- How much larger or smaller than the layout a style draws: for whatever else is drawn at the frames' size
function frames.Scale(style)
    return Percent((style or usual).scale)
end

local fullLine = { }

-- Maximum configured line geometry for a fully populated list, independent of current membership.
-- Used to reserve a stable alliance block above the fully expanded main party.
function frames.FullSize(count, kind, style)
    style = style or usual
    rowHeight = RowHeight(style, kind)
    nameScale, valueScale = Percent(style.nameSize), Percent(style.valueSize)
    valueOffsets.hp, valueOffsets.mp, valueOffsets.tp = style.hpOffset, style.mpOffset, style.tpOffset
    local full = fullLine
    full.isInZone, full.mpp, full.tp = true, 100, 1000
    -- The owner's pet is first; other members' pets have HP only and are always in-zone.
    if kind == 'pets' and count > 1 then full.mpp, full.tp = nil, nil end
    local last = LineHeight(full, kind, style.showMp ~= false, style.showTp ~= false)
    if kind ~= 'pets' then
        full.isInZone = false
        last = math.max(last, LineHeight(full, kind, style.showMp ~= false, style.showTp ~= false))
    end
    if style.trimLast == false then last = rowHeight end
    local factor = Percent(style.scale)
    return math.ceil(layout.width * factor), math.ceil(((count - 1) * rowHeight + last) * factor)
end

local function ConfigureExtras(style, kind)
    activeStyle = style
    rowHeight = RowHeight(style, kind)
    castRange = style.castRange or 20.79
    targetRange = math.max(castRange, style.targetRange or 50)
    beyondCastOpacity, beyondTargetOpacity = style.nearOpacity or 0.7, style.farOpacity or 0.45
end

-- The bars' look: their texture, the caps at their ends, the light at a fill's end and the backdrop
local function ConfigureBars(style)
    bookendAlpha = math.max(0, math.min(100, tonumber(style.bookendOpacity) or 100)) / 100
    bookends = style.bookends ~= false and bookendAlpha > 0
    local capStyle = style.bookendStyle == 'match' and style.borderStyle or style.bookendStyle
    bookendFile = bookendFiles[capStyle]
    roundedCaps = roundedStyles[capStyle] == true
    glowAlpha = math.max(0, math.min(100, tonumber(style.barGlow) or 0)) / 100
    backdropColor = style.barBackdrop
    capsuleFrame = capsuleFrames[style.barFrame]
    -- Only known sets can select asset paths; the original remains the fallback. The paths are made
    -- again only when the set changes.
    local textureSet = style.barTexture
    if textureSet ~= barTextureSet then
        barTextureSet = textureSet
        local textureRoot = barTextureSets[textureSet]
            and ('bars/' .. textureSet .. '/') or 'bars/'
        for _, kind in ipairs(barKinds) do
            local place = layout[kind]
            place.back = textureRoot .. kind .. '_back.png'
            place.fillImage = textureRoot .. kind .. '_fill.png'
            place.front = textureRoot .. kind .. '_front.png'
        end
    end
end

local function HoverMembers(members)
    for index, member in ipairs(members) do
        if details.Hover(itemX, lineY[index], itemX + room[1], lineY[index] + rowHeight * scale) then
            if activeStyle.hoverDetails then
                details.Member(member)
            else
                details.Job(member)
            end
            break
        end
    end
end

function frames.Draw(members, kind, StatusTexture, style)
    local count = #members
    if count == 0 then
        return
    end

    style = style or usual
    ConfigureExtras(style, kind)
    scale = Percent(style.scale)
    valueScale = Percent(style.valueSize)
    nameScale = Percent(style.nameSize)
    buffScale = Percent(style.buffSize)
    buffSpacing = tonumber(style.buffSpacing) or 0
    ownIcons = style.ffxivIcons ~= false
    ConfigureBars(style)
    valueOffsets.hp, valueOffsets.mp, valueOffsets.tp = style.hpOffset, style.mpOffset, style.tpOffset
    outlined = outlinedText.Edge() > 0 -- the theme's Text Outline
    nameChars = style.nameChars
    local showMp, showTp = style.showMp ~= false, style.showTp ~= false
    textColor = theme.Get().TextColor


    -- once a frame, whichever list is drawn first: the others are drawn a moment later in the same one
    local now = os.clock()
    if now - lastFrame >= 0.004 or displayWidth == nil then
        lastFrame = now
        local display = imgui.GetIO().DisplaySize
        displayWidth, displayHeight = display.x, display.y

        -- where the pulse of a TP figure at 1000 and over has got to: 0 at the light blue, 1 at the
        -- deeper one, moving smoothly from one to the other and back
        local phase = (now % tpPulsePeriod) / tpPulsePeriod
        tpPulseBlend = 0.5 - 0.5 * math.cos(phase * 2 * math.pi)
    end

    -- the colour of such a figure for this list: pulsing, or kept at the deeper blue
    local blend = style.tpFlash ~= false and tpPulseBlend or 1
    for channel = 1, 3 do
        tpPulse[channel] = tpFullLight[channel] + (tpFull[channel] - tpFullLight[channel]) * blend
    end

    -- the room the list itself needs. The buffs go beyond it, beside the window.
    local windowX, windowY = imgui.GetCursorScreenPos()
    room[1] = math.ceil(layout.width * scale)
    local lastHeight = rowHeight
    if style.trimLast then
        lastHeight = LineHeight(members[count], kind, showMp, showTp)
    end
    room[2] = math.ceil(((count - 1) * rowHeight + lastHeight) * scale)
    imgui.Dummy(room)

    -- a list laid out off screen to be measured needs its room and nothing else
    if windowX + room[1] < 0 or windowY + room[2] < 0 or windowX > displayWidth or windowY > displayHeight then
        return
    end

    -- the window's own list, so the list sits with the window among the others and fades with it,
    -- opened up to the whole screen (and no further) for what goes beside the window
    local drawList = imgui.GetWindowDrawList()
    clipMax[1], clipMax[2] = displayWidth, displayHeight
    drawList:PushClipRect(clipMin, clipMax, false)
    draw.Use(drawList)

    -- the theme's Text Outline, scaled with the frames; at least a pixel where anything is outlined
    outlineEdge = math.max(1, math.floor(outlinedText.Edge() * scale + 0.5))
    if outlined then
        outlinePacked = draw.Packed(outlinedText.EdgeColor(), 1)
    end

    itemX = math.floor(windowX)
    local originY = math.floor(windowY)

    -- each line: where it is, and how full its bars are
    local anyElsewhere = false
    for index = 1, count do
        local member = members[index]
        local state = Animation(member, index)
        lineStates[index] = state
        lineY[index] = math.floor(originY + (index - 1) * rowHeight * scale)

        state.inZone = member.isInZone
        state.hasMp = member.mpp ~= nil
        if state.inZone then
            state.opacity = RangeOpacity(member)
            state.hp.fraction = math.max(0, math.min(1, (member.hpp or 0) / 100))
            if state.hasMp then
                -- no MP to have is not an empty bar: it is a grey one, full
                if member.noMp then
                    state.mp.fraction, state.mp.color = 1, noMpGrey
                else
                    state.mp.fraction, state.mp.color = math.max(0, math.min(1, (member.mpp or 0) / 100)), nil
                end
            end
        else
            anyElsewhere = true
        end
    end

    -- from the bottom up: the bars, the names, and last the figures, which stay readable where a long
    -- or large name runs into them
    DrawBars(count, 'hp', layout.hp)
    DrawBars(count, 'mp', layout.mp)

    -- each written in its own font where one is chosen, or the theme's (nil keeps the one in use)
    local nameFace, valueFace = fonts.Get(style.nameFont), fonts.Get(style.valueFont)
    nameFont = FontSize(layout.name.size * nameScale)
    imgui.PushFont(nameFace, nameFont)
    nameFontFile = nameFace or theme.Get().FontFile or ''
    for index = 1, count do
        itemY = lineY[index]
        DrawName(members[index], lineStates[index])
    end
    imgui.PopFont()

    -- a member in another area has that area's name where the bars would be
    if anyElsewhere then
        local zone = layout.zone
        imgui.PushFont(nameFace, FontSize(zone.size))
        for index = 1, count do
            local member = members[index]
            local text = not member.isInZone and ZoneText(member.zoneId, zone.maxChars)
            if text then
                itemY = lineY[index]
                Write(text, zone.x, zone.y, nil, TextSize(text))
            end
        end
        imgui.PopFont()
    end

    local valueFont = FontSize(layout.valueSize * valueScale)
    local tpPlace = layout.tp
    local hpFigure = kind == 'target' and layout.targetHpFigure or nil
    imgui.PushFont(valueFace, valueFont)
    valueFontFile = valueFace or theme.Get().FontFile or ''
    for index = 1, count do
        local member, state = members[index], lineStates[index]
        if state.inZone then
            itemY = lineY[index]
            DrawFigure(layout.hp, member, state.hp, valueFont, hpFigure)
            if state.hasMp and showMp and not member.noMp then
                DrawFigure(layout.mp, member, state.mp, valueFont)
            end
            if showTp and member.tp ~= nil then
                DrawFigure(tpPlace, member, state.tp, valueFont)
            end
        end
    end
    imgui.PopFont()

    -- Native party-order rearrangement replaces the buff area with job information,
    -- including alliance members and members in another zone. Always outline these labels.
    if style.showJobs and (kind == 'party' or kind == 'alliance') then
        local right = imgui.GetWindowPos() - layout.buffs.gap - (tonumber(style.buffDistance) or 0) * scale
        local dark = draw.Packed(outlinedText.EdgeColor(), 1)
        imgui.PushFont(nameFace, nameFont)
        for index, member in ipairs(members) do
            local words = member.jobText or '[---/---]'
            local width = TextSize(words)
            draw.Text(math.floor(right - width), math.floor(lineY[index] + layout.buffs.y * scale),
                draw.Packed(textColor, 1), words, outlineEdge, dark)
        end
        imgui.PopFont()
    -- Otherwise only the player's own party shows buffs, and targets their debuff icons.
    elseif kind == 'party' or kind == 'target' then
        local buffsX = (imgui.GetWindowPos() - layout.buffs.gap - itemX) / scale - (tonumber(style.buffDistance) or 0)
        for index = 1, count do
            if lineStates[index].inZone then
                itemY = lineY[index]
                DrawBuffs(members[index], buffsX, StatusTexture)
            end
        end
    end

    if style.hoverDetails or kind == 'party' or kind == 'alliance' then HoverMembers(members) end
    drawList:PopClipRect()
end

return frames
