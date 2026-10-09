-- XivParty Style: the party lists arranged the way XivParty, a party list addon for Windower 4 by
-- Tylas, arranges them in its compact layout (https://github.com/Tylas11/XivParty; its
-- layouts/ffxi2.xml), inside one of this addon's own windows. The bars are that addon's images, in
-- assets/xivparty with its licence; the window around them, with its background, border, padding and
-- shadow, is the theme's.
--
-- A member is a line: the name, an HP bar and a smaller MP bar with their figures, and TP as a figure
-- alone, which pulses in blue at 1000 and over. Each bar has a soft shadow under it, which XivParty's
-- do not, and simply shows its value: XivParty's glow over a change is not here. The member targeted
-- is marked as in the party window's own view: ">> " before the name, both in blue, and "> " in green
-- for one a sub-target or the party cursor is on. A leader has a circle in front of their name (two,
-- one over the other, for an alliance's), and the buffs of a member of the player's own party run
-- leftwards from the window.
--
--     xivparty.Draw(members, kind, StatusTexture, settings)
--
-- kind is 'party' for the player's own party, 'alliance' for another, 'pets' for lines set out as
-- the party's are but with no buffs, and 'target' for a line like a pet's whose HP figure is under
-- its bar, level with the TP figure (tgt.lua writes a target's HP percentage and distance there). settings says how, each left out for the usual:
--     scale       a percentage for the whole list (see below)
--     valueSize   a percentage for the size of the HP, MP and TP figures alone
--     nameSize    a percentage for the size of the names alone
--     buffSize    a percentage for the size of the buff icons alone
--     buffSpacing how much room there is between one buff icon and the next, in the layout's units
--     buffDistance  how much further from the window than usual the buffs start, in the layout's
--                 units: less than nothing brings them closer, and over it
--     showMp, showTp   false to leave the MP or the TP figure out; the MP bar is drawn either way
--     bookends    false for bars without the small silver caps at their ends, which are after the ones
--                 on the game's own party list and are not XivParty's
--     trimLast    true for a list that is the last thing in its window: its last line is then only
--                 as tall as what is on it, where every other is a full row. Without it the room
--                 under a line that does not fill its row (a pet with an HP bar alone) shows as
--                 padding at the foot of the window.
--     tpFlash     false for a TP figure at 1000 and over that is simply blue, and does not pulse
--     nameChars   how many characters of a name are written before it is cut short, in place of the
--                 nine a party member's is allowed
--     outline     false to leave the dark edge off the names and the HP, MP and TP figures: winxi's
--                 way of writing over bars (winxi.text), without which the figures are hard to read
--     hpOffset, mpOffset, tpOffset   { x, y } to move that figure from its place in the layout, in the
--                 layout's units: right and down, or left and up for less than nothing
--
-- is called inside the window. It takes up the room the list needs and draws into it; the buffs are
-- drawn beyond that room, beside the window. members are the party window's own (see us.lua). A scale
-- of 100 is the size this style is meant to be seen at, a fifth larger than XivParty's own.
-- StatusTexture(id) gives the texture for a status icon, or nil. A member may be anything with the
-- same fields, and a member with noMp set (one whose most MP is none) has a grey, full MP bar and no
-- MP figure: us.lua lists pets this way and tgt.lua draws a target, giving hpText, mpText and tpText
-- for figures in words of their own, leaving mpp and tp out for a line with no MP bar or TP, and
-- setting plainHp for an HP figure that keeps its colour however low the HP is.
--
-- What is XivParty's and is not here: its background, job icons and cursor, left out for the theme's
-- window and this addon's own way of marking a target; the buffs are in the game's order, not sorted
-- debuffs first; there is no mark for the quartermaster; and nothing happens on hovering or clicking
-- a member.
require('common')
local ffi = require('ffi')
local d3d8 = require('d3d8')
local imgui = require('imgui')
local theme = require('winxi.theme')
local outlinedText = require('winxi.text')
local ui = require('ui')
local zones = require('utils/zones')

local xivparty = { }

local castRange = 20.79       -- beyond this a member's bars are dimmed, and beyond targetRange dimmed further
local targetRange = 50
local pointsToPixels = 4 / 3  -- XivParty's text sizes are in points
local baseScale = 1.2         -- how much larger than XivParty's own sizes the lists are at a scale of 100
local textScale = 1.15        -- and how much larger again the text is, to be read more easily

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
local tpPulse = { 0, 0, 0, 1 } -- the colour it is this frame
local noMpGrey = { 0.55, 0.55, 0.55, 1 } -- the MP bar of a member with no MP to have: grey, and full

-- The images of a bar: a back, the fill that is as long as the bar is full (it starts fillX across
-- and is fillWidth long when full), and a front. color tints all three. Each image is a good deal
-- taller than the bar drawn in it: bottom is how far down the image the bar itself ends.
-- body is where in the image the bar itself is, left, top, right and bottom: its ends are where the
-- bookends go.
local hpImages = { width = 128, height = 64, fillX = 13, fillWidth = 102, bottom = 36, body = { 12, 28, 116, 36 },
    back = 'ffxi/BarBG.png', fill = 'ffxi/Bar.png', front = 'ffxi/BarFG.png', color = Hex('FF9597') }
local mpImages = { width = 128, height = 64, fillX = 27, fillWidth = 74, bottom = 35, body = { 26, 29, 102, 35 },
    back = 'ffxi/AllyBarBgMP.png', fill = 'ffxi/AllyBarMP.png', front = 'ffxi/AllyBarFgMP.png', color = Hex('FFFF9C') }
local barShadowReach = 2.5 -- how far below a bar its shadow goes

-- The bookends: a thin silver cap at each end of a bar, as tall as the whole bar, frame and all, and
-- standing half on it, after the ones the bars of the game's own party list have
local bookend = { width = 2, over = 1.5 } -- how wide a cap is, and how far past the bar's inside its frame goes, above and below
local bookendSilver = { 0.78, 0.80, 0.84, 1 }
local bookendShade = { 0.52, 0.54, 0.60, 1 } -- towards its top and bottom, as a bar's frame darkens towards its own
local bookendHalfShade = { 0.65, 0.67, 0.72, 1 } -- and between that and the silver
local bookendShine = { 0.97, 0.97, 1.00, 1 }
local bookendEdge = { 0.20, 0.21, 0.25, 1 }

-- The layout, in XivParty's own numbers: places and sizes are in its units, from the top left of a
-- member's line. A figure's place is from its bar's; with alignRight its right end goes there.
-- XivParty has a job icon and a cursor to the left of the name. Neither is drawn here, and everything
-- is that much further left: the name starts the line. The two figures are a unit further apart than
-- XivParty has them, for the larger text.
local layout = {
    width = 136, rowHeight = 32,
    valueSize = 8, -- the HP, MP and TP figures are written at one size
    hp = { value = 'hp', x = 6, y = -17, images = hpImages, figure = { x = 114, y = 21, alignRight = true } },
    mp = { value = 'mp', x = 32, y = -8, images = mpImages, figure = { x = 100, y = 23, alignRight = true } },
    -- a target's HP figure, in place of the one above: under the bar, level with the TP figure, its
    -- right end at the bar's. It goes up and down with the TP figure, wherever that has been moved to
    -- (levelWithTp), and is not moved as the HP figure on a bar is.
    targetHpFigure = { x = 115, y = 35, alignRight = true, levelWithTp = true },
    -- TP is a figure alone, to the left of the MP bar: in the same place on every line, the player's
    -- party, the other two and the pets alike. XivParty puts it elsewhere for the other parties, and
    -- writes it smaller than HP and MP; here the three are one size (valueSize), and TP is a little
    -- higher to stay level with the MP bar.
    tp = { value = 'tp', x = 0, y = 0, figure = { x = 56, y = 18, alignRight = true } },
    name = { x = 0, y = 0, size = 10, maxChars = 9 },
    zone = { x = 136, y = 14, size = 10, maxChars = 16 }, -- its right end goes at x
    -- the buffs run leftwards from the window's edge, sixteen at most
    buffs = { y = 5, size = 20, gap = 4, most = 16 },
}

-- The images, each loaded the first time it is wanted. A texture is kept for as long as the addon is
-- loaded; imgui takes it as a number.
local handles = { }  -- file -> the number, or false where the image could not be loaded
local kept = { }

local function Texture(file)
    local handle = handles[file]
    if handle == nil then
        handle = false
        local device = d3d8.get_device()
        if device ~= nil then
            local pointer = ffi.new('IDirect3DTexture8*[1]')
            local path = string.format('%sassets/xivparty/%s', addon.path, file)
            if ffi.C.D3DXCreateTextureFromFileA(device, path, pointer) == ffi.C.S_OK then
                local texture = d3d8.gc_safe_release(ffi.cast('IDirect3DTexture8*', pointer[0]))
                kept[#kept + 1] = texture
                handle = tonumber(ffi.cast('uint32_t', texture))
            end
        end
        handles[file] = handle
    end
    return handle
end

-- What is being drawn: set by Draw and by each member's turn, and read by the helpers below
local drawList = nil
local scale = 1
local itemX, itemY = 0, 0 -- the top left of the member being drawn, on screen
local textColor = white   -- the theme's
local valueScale = 1      -- how much larger or smaller than the layout's the HP, MP and TP figures are
local nameScale = 1       -- and the names
local buffScale = 1       -- and the buff icons
local buffSpacing = 0     -- the room between one buff icon and the next
local bookends = true     -- whether the bars have their silver caps
local valueOffsets = { }  -- hp, mp, tp -> { x, y }: how far that figure is moved from its place, if at all
local outlined = true     -- whether the names and figures have winxi's dark edge
local nameChars = nil     -- how much of a name is written, where it is not the layout's own

local cornerA, cornerB = { 0, 0 }, { 0, 0 }
local uvA, uvB = { 0, 0 }, { 1, 1 } -- the whole of an image
local tint = { 1, 1, 1, 1 }

-- A colour as imgui's draw lists take it, with the window's fade in it. A list is drawn a layer at a
-- time, so one colour is asked for many times running: the last is kept. Forgotten for each list,
-- as the fade may have changed and a colour table may have been changed in place.
local lastColor, lastAlpha, lastPacked = nil, nil, nil

local function Packed(color, alpha)
    if color ~= lastColor or alpha ~= lastAlpha then
        tint[1], tint[2], tint[3], tint[4] = color[1], color[2], color[3], color[4] * alpha
        lastPacked = imgui.GetColorU32(tint)
        lastColor, lastAlpha = color, alpha
    end
    return lastPacked
end

-- An image, by its file or the number of a texture, at a place in the layout's units
local function Image(image, x, y, width, height, color, alpha)
    local handle = type(image) == 'number' and image or Texture(image)
    if not handle or width == 0 then
        return
    end

    cornerA[1], cornerA[2] = itemX + x * scale, itemY + y * scale
    cornerB[1], cornerB[2] = cornerA[1] + width * scale, cornerA[2] + height * scale
    drawList:AddImage(handle, cornerA, cornerB, uvA, uvB, Packed(color or white, alpha or 1))
end

local textPos = { 0, 0 }
local outlineEdge = 1     -- how thick winxi's dark edge is, for this list
local outlinePacked = 0   -- and its colour

-- The size of font, in pixels, for text of a size in points
local function FontSize(points)
    return points * pointsToPixels * textScale * scale
end

-- A line of text at a place in the layout's units, in the font in use: the font is pushed by whoever
-- writes a run of text of one size. With width, the text's own, its right end goes at x.
local function Write(text, x, y, color, width)
    local left = math.floor(itemX + x * scale - (width or 0))
    local top = math.floor(itemY + y * scale)
    local packed = Packed(color or textColor, 1)

    if outlined then
        outlinedText.Packed(drawList, left, top, packed, text, outlineEdge, outlinePacked)
    else
        textPos[1], textPos[2] = left, top
        drawList:AddText(textPos, packed, text)
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

local zoneTexts = { } -- zone id -> its name as it is written, in brackets and cut short

-- What is kept for each line between frames, by member: each figure as it was last written, so that
-- it is only made into words and measured again when it changes
local animations = { }
local animationCount = 0
local lastFrame = os.clock() -- when a list was last drawn in a frame of its own
local displayWidth, displayHeight = nil, nil -- the screen's size, asked for once a frame

local function Animation(member)
    local key = member.serverId or 0
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

-- How far away a member is: 1 within casting range, 0.5 within targeting range, 0.25 beyond or unknown.
-- A member made up to fill the list while it is being arranged is taken to be beside the player.
local function RangeOpacity(member)
    if member.isPlayer or (member.targetIndex == nil and member.isInZone) then
        return 1
    end
    local entity = member.entity
    if entity == nil or entity.Distance == nil then
        return 0.25
    end

    local distance = math.sqrt(entity.Distance)
    if distance <= castRange then
        return 1
    elseif distance <= targetRange then
        return 0.5
    end
    return 0.25
end

-- The lines of the list being drawn: what is kept for each, and where each is on screen
local lineStates, lineY = { }, { }

-- The layers of a bar, each drawn for every line before the next: a list is drawn a layer at a time
-- and not a line at a time, so that what is drawn with one image, or in one font, is drawn together.
-- Under a bar goes a soft shadow, down and to the right, to lift it off the window: the bar's own back
-- in black, twice, the further one fainter.
local function ShadowNear(place)
    local images = place.images
    Image(images.back, place.x + 1, place.y + 1.5, images.width, images.height, black, 0.45)
end

local function ShadowFar(place)
    local images = place.images
    Image(images.back, place.x + 2, place.y + 2.5, images.width, images.height, black, 0.2)
end

-- A line's bar is in the bar's own colour unless the line has another for it (bar.color)
local function Back(place, bar)
    local images = place.images
    Image(images.back, place.x, place.y, images.width, images.height, bar.color or images.color)
end

local function Fill(place, bar, opacity)
    local images = place.images
    Image(images.fill, place.x + images.fillX, place.y, images.fillWidth * bar.fraction, images.height, bar.color or images.color, opacity)
end

local function Front(place, bar)
    local images = place.images
    Image(images.front, place.x, place.y, images.width, images.height, bar.color or images.color)
end

-- A bar's two bookends. Each is a silver cap, darker towards its top and bottom in two steps as the
-- bars themselves are, with a dark edge and a line of shine down the left of its bright middle.
local capMin, capMax = { 0, 0 }, { 0, 0 }

local function Cap(centre, top, bottom)
    -- every cap is the same whole number of pixels wide, wherever its bar's end falls: worked out
    -- from each side separately, one cap in four came out a pixel wider than the rest
    local width = math.max(2, math.floor(bookend.width * scale + 0.5))
    local left = math.floor(itemX + centre * scale - width / 2 + 0.5)
    local right = left + width
    top, bottom = math.floor(itemY + top * scale + 0.5), math.floor(itemY + bottom * scale + 0.5)

    capMin[1], capMin[2], capMax[1], capMax[2] = left, top, right, bottom
    drawList:AddRectFilled(capMin, capMax, Packed(bookendSilver, 1), 1)

    -- the shading: a band at the top and one at the bottom, each darkest at the very end
    local band = math.max(1, math.floor((bottom - top) * 0.14 + 0.5))
    capMax[2] = top + 2 * band
    drawList:AddRectFilled(capMin, capMax, Packed(bookendHalfShade, 1), 0)
    capMax[2] = top + band
    drawList:AddRectFilled(capMin, capMax, Packed(bookendShade, 1), 0)
    capMin[2], capMax[2] = bottom - 2 * band, bottom
    drawList:AddRectFilled(capMin, capMax, Packed(bookendHalfShade, 1), 0)
    capMin[2] = bottom - band
    drawList:AddRectFilled(capMin, capMax, Packed(bookendShade, 1), 0)

    capMin[1], capMin[2], capMax[1], capMax[2] = left, top, right, bottom
    drawList:AddRect(capMin, capMax, Packed(bookendEdge, 1), 1, 0, 1)
    capMin[1], capMin[2], capMax[1], capMax[2] = left + 1, top + 2 * band, left + 1, bottom - 2 * band - 1
    if capMax[2] > capMin[2] then
        drawList:AddLine(capMin, capMax, Packed(bookendShine, 1), 1)
    end
end

-- the top and bottom of a cap are those of the bar's frame
local function Bookends(place)
    local body = place.images.body
    local top, bottom = place.y + body[2] - bookend.over, place.y + body[4] + bookend.over
    Cap(place.x + body[1], top, bottom)
    Cap(place.x + body[3], top, bottom)
end

-- One layer of a bar, for every line that has the bar: every line in the area has an HP bar, and an
-- MP bar unless it has no MP to show (another player's pet)
local function Layer(count, kind, place, draw)
    for index = 1, count do
        local state = lineStates[index]
        if state.inZone and (kind == 'hp' or state.hasMp) then
            itemY = lineY[index]
            draw(place, state[kind], state.opacity)
        end
    end
end

local function DrawBars(count, kind, place)
    Layer(count, kind, place, ShadowNear)
    Layer(count, kind, place, ShadowFar)
    Layer(count, kind, place, Back)
    Layer(count, kind, place, Fill)
    Layer(count, kind, place, Front)
    if bookends then
        Layer(count, kind, place, Bookends)
    end
end

-- A leader's mark: a circle in front of the name, where the name's first letter would be, in the
-- party's colour for a party's leader. An alliance's leader has two, one over the other: the
-- alliance's above and the party's below. Drawn in the names' font, whose size on screen is nameFont.
-- Returns how much room it took, in the layout's units, for the name to start after it.
local nameFont = 0
local circleAt = { 0, 0 }

local function Circle(x, y, radius, color)
    circleAt[1], circleAt[2] = x, y
    if outlined then
        drawList:AddCircleFilled(circleAt, radius + outlineEdge, outlinePacked, 12)
    end
    drawList:AddCircleFilled(circleAt, radius, Packed(color, 1), 12)
end

local function DrawLeaderMarks(member)
    local name = layout.name
    local radius = nameFont * 0.19
    local centre = math.floor(itemX + name.x * scale) + radius + 1
    local top = math.floor(itemY + name.y * scale)

    if member.isAllianceLeader then
        -- a little smaller than one alone, and a little apart
        local small = nameFont * 0.17
        Circle(centre, top + nameFont * 0.26, small, ui.Colors.Alliance)
        Circle(centre, top + nameFont * 0.78, small, ui.Colors.Party)
    else
        Circle(centre, top + nameFont * 0.52, radius, ui.Colors.Party)
    end
    return (2 * radius + 1 + nameFont * 0.22) / scale
end

-- A member's name, after their leader's mark if they have one, and marked as the party window's own
-- view marks it: "> " in green on the member a sub-target or the party cursor is on, ">> " in blue on
-- the one targeted. The marked name is kept while the name and the mark stay as they are.
local function DrawName(member, state)
    local name = layout.name
    local shown = Trimmed(member.name or '???', nameChars or name.maxChars)
    local x = name.x
    if member.isPartyLeader or member.isAllianceLeader then
        x = x + DrawLeaderMarks(member)
    end

    local mark, color = nil, nil
    if member.isSubTarget or member.isPartyTarget then
        mark, color = '> ', ui.Colors.Green
    elseif member.isTarget then
        mark, color = '>> ', ui.Colors.Blue
    end
    if mark ~= nil then
        if state.markedFrom ~= shown or state.mark ~= mark then
            state.markedFrom, state.mark, state.marked = shown, mark, mark .. shown
        end
        shown = state.marked
    end
    Write(shown, x, name.y, color)
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
    local x, y = place.x + figure.x, place.y + figure.y
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
        if kept.measured ~= words or kept.fontSize ~= fontSize then
            kept.measured, kept.fontSize, kept.width = words, fontSize, imgui.CalcTextSize(words)
        end
        width = kept.width
    end
    Write(words, x, y, color, width)
end

-- A member's buffs, running leftwards: the first has its right edge at x
local function DrawBuffs(member, x, StatusTexture)
    local ids = member.statusIds
    if ids == nil or StatusTexture == nil then
        return
    end

    -- whatever their size, the icons stay centred on the height they have in the layout
    local buffs = layout.buffs
    local size = buffs.size * buffScale
    local y = buffs.y + (buffs.size - size) / 2
    local shown = 0
    for _, id in ipairs(ids) do
        if shown >= buffs.most then
            return -- no room for the rest
        end
        local texture = StatusTexture(id)
        if texture ~= nil then
            shown = shown + 1
            Image(texture, x - shown * size - (shown - 1) * buffSpacing, y, size, size)
        end
    end
end

-- How far down its row the lowest thing on a line is, in the layout's units: the line's height when
-- it is the last in its window. Never more than a row.
local function LineHeight(member, kind, showMp, showTp)
    local name = layout.name
    local bottom = name.y + name.size * pointsToPixels * textScale * nameScale

    if not member.isInZone then
        -- the area's name is all there is under the member's own
        local zone = layout.zone
        bottom = math.max(bottom, zone.y + zone.size * pointsToPixels * textScale)
    else
        local valueHeight = layout.valueSize * pointsToPixels * textScale * valueScale
        local tpOffset = valueOffsets.tp
        local tpOffsetY = tpOffset and tonumber(tpOffset[2]) or 0

        local hp = layout.hp
        bottom = math.max(bottom, hp.y + hp.images.bottom + barShadowReach)
        if kind == 'target' then
            bottom = math.max(bottom, hp.y + layout.targetHpFigure.y + tpOffsetY + valueHeight)
        else
            local offset = valueOffsets.hp
            bottom = math.max(bottom, hp.y + hp.figure.y + (offset and tonumber(offset[2]) or 0) + valueHeight)
        end

        if member.mpp ~= nil then
            local mp = layout.mp
            bottom = math.max(bottom, mp.y + mp.images.bottom + barShadowReach)
            if showMp and not member.noMp then
                local offset = valueOffsets.mp
                bottom = math.max(bottom, mp.y + mp.figure.y + (offset and tonumber(offset[2]) or 0) + valueHeight)
            end
        end

        if showTp and member.tp ~= nil then
            local tp = layout.tp
            bottom = math.max(bottom, tp.y + tp.figure.y + tpOffsetY + valueHeight)
        end
    end

    return math.min(layout.rowHeight, bottom + 1)
end

local room = { 0, 0 }
local clipMin, clipMax = { 0, 0 }, { 0, 0 }

-- A percentage as a multiplier: 1 where there is none, or none that makes sense
local function Percent(value)
    return (type(value) == 'number' and value > 0) and value / 100 or 1
end

local noSettings = { }

function xivparty.Draw(members, kind, StatusTexture, settings)
    local count = #members
    if count == 0 then
        return
    end

    settings = settings or noSettings
    scale = baseScale * Percent(settings.scale)
    valueScale = Percent(settings.valueSize)
    nameScale = Percent(settings.nameSize)
    buffScale = Percent(settings.buffSize)
    buffSpacing = tonumber(settings.buffSpacing) or 0
    bookends = settings.bookends ~= false
    valueOffsets.hp, valueOffsets.mp, valueOffsets.tp = settings.hpOffset, settings.mpOffset, settings.tpOffset
    outlined = settings.outline ~= false
    nameChars = settings.nameChars
    local showMp, showTp = settings.showMp ~= false, settings.showTp ~= false
    textColor = theme.Get().TextColor

    -- where the pulse of a TP figure at 1000 and over has got to: 0 at the light blue, 1 at the deeper
    -- one, moving smoothly from one to the other and back; or kept at the deeper one
    local blend = 1
    if settings.tpFlash ~= false then
        local phase = (os.clock() % tpPulsePeriod) / tpPulsePeriod
        blend = 0.5 - 0.5 * math.cos(phase * 2 * math.pi)
    end
    for channel = 1, 3 do
        tpPulse[channel] = tpFullLight[channel] + (tpFull[channel] - tpFullLight[channel]) * blend
    end

    -- once a frame, whichever list is drawn first: the others are drawn a moment later in the same one
    local now = os.clock()
    if now - lastFrame >= 0.004 or displayWidth == nil then
        lastFrame = now
        local display = imgui.GetIO().DisplaySize
        displayWidth, displayHeight = display.x, display.y
    end

    -- the room the list itself needs. The buffs go beyond it, beside the window.
    local windowX, windowY = imgui.GetCursorScreenPos()
    room[1] = math.ceil(layout.width * scale)
    local lastHeight = layout.rowHeight
    if settings.trimLast then
        lastHeight = LineHeight(members[count], kind, showMp, showTp)
    end
    room[2] = math.ceil(((count - 1) * layout.rowHeight + lastHeight) * scale)
    imgui.Dummy(room)

    -- a list laid out off screen to be measured needs its room and nothing else
    if windowX + room[1] < 0 or windowY + room[2] < 0 or windowX > displayWidth or windowY > displayHeight then
        return
    end

    -- the window's own list, so the list sits with the window among the others and fades with it,
    -- opened up to the whole screen (and no further) for what goes beside the window
    drawList = imgui.GetWindowDrawList()
    clipMax[1], clipMax[2] = displayWidth, displayHeight
    drawList:PushClipRect(clipMin, clipMax, false)

    lastColor = nil
    outlineEdge = math.max(1, math.floor(scale / baseScale + 0.5))
    if outlined then
        outlinePacked = imgui.GetColorU32(outlinedText.OutlineColor)
    end

    itemX = math.floor(windowX)
    local originY = math.floor(windowY)

    -- each line: where it is, and how full its bars are
    local anyElsewhere = false
    for index = 1, count do
        local member = members[index]
        local state = Animation(member)
        lineStates[index] = state
        lineY[index] = math.floor(originY + (index - 1) * layout.rowHeight * scale)

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

    nameFont = FontSize(layout.name.size * nameScale)
    imgui.PushFont(nil, nameFont)
    for index = 1, count do
        itemY = lineY[index]
        DrawName(members[index], lineStates[index])
    end
    imgui.PopFont()

    -- a member in another area has that area's name where the bars would be
    if anyElsewhere then
        local zone = layout.zone
        imgui.PushFont(nil, FontSize(zone.size))
        for index = 1, count do
            local member = members[index]
            if not member.isInZone and zones[member.zoneId] ~= nil then
                local text = zoneTexts[member.zoneId]
                if text == nil then
                    text = Trimmed(('(%s)'):format(zones[member.zoneId]), zone.maxChars)
                    zoneTexts[member.zoneId] = text
                end
                itemY = lineY[index]
                Write(text, zone.x, zone.y, nil, imgui.CalcTextSize(text))
            end
        end
        imgui.PopFont()
    end

    local valueFont = FontSize(layout.valueSize * valueScale)
    local tpPlace = layout.tp
    local hpFigure = kind == 'target' and layout.targetHpFigure or nil
    imgui.PushFont(nil, valueFont)
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

    -- only the player's own party shows buffs: they start a little clear of the window's left edge
    if kind == 'party' then
        local buffsX = (imgui.GetWindowPos() - layout.buffs.gap - itemX) / scale - (tonumber(settings.buffDistance) or 0)
        for index = 1, count do
            if lineStates[index].inZone then
                itemY = lineY[index]
                DrawBuffs(members[index], buffsX, StatusTexture)
            end
        end
    end

    drawList:PopClipRect()
    drawList = nil
end

return xivparty
