-- XivParty Style: the party lists arranged the way XivParty, a party list addon for Windower 4 by
-- Tylas, arranges them in its compact layout (https://github.com/Tylas11/XivParty; its
-- layouts/ffxi2.xml), inside one of this addon's own windows. The bars and the leader's mark are that
-- addon's images, in assets/xivparty with its licence; the window around them, with its background,
-- border, padding and shadow, is the theme's.
--
-- A member is a line: the name, an HP bar and a smaller MP bar with their figures, and TP as a figure
-- alone. Each bar has a soft shadow under it, which XivParty's do not, and glows for a moment over
-- what it has lost, but not as XivParty's do over what it has gained. The member targeted is marked as in the party window's own view: ">> " before the name, both
-- in blue, and "> " in green for one a sub-target or the party cursor is on. A small mark sits under
-- the name of the party's leader, and the buffs of a member of the player's own party run leftwards
-- from the window.
--
--     xivparty.Draw(members, kind, StatusTexture, settings)
--
-- kind is 'party' for the player's own party, 'alliance' for another, and 'pets' for lines set out as
-- the party's are but with no buffs. settings says how, each left out for the usual:
--     scale       a percentage for the whole list (see below)
--     valueSize   a percentage for the size of the HP, MP and TP figures alone
--     nameSize    a percentage for the size of the names alone
--     buffSize    a percentage for the size of the buff icons alone
--     showMp, showTp   false to leave the MP or the TP figure out; the MP bar is drawn either way
--     glow        false for bars that simply change, with no glow over what was lost
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
-- same fields: us.lua lists pets this way and tgt.lua draws a target, giving hpText, mpText and tpText
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
local barAnimSpeed = 0.1      -- how much of the way a bar's glow closes every animFrame seconds
local glowOpacity = 0.85      -- how strong the glow over what a bar has lost is
-- XivParty's glow images fade out a long way above and below the bar, into the lines either side.
-- Only this much of their height is drawn, from the top: the bar and half its height again each way.
local glowTop, glowBottom = 0.375, 0.625
local animFrame = 0.03
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
local tpFull = Hex('50B4FA')   -- a TP figure at 1000 and over

-- The images of a bar: a back, the fill that is as long as the bar is full (it starts fillX across
-- and is fillWidth long when full), a front, and the glow that covers a change with its two ends.
-- color tints the back, fill and front; glowColor the glow.
local hpImages = { width = 128, height = 64, fillX = 13, fillWidth = 102, glowSidesWidth = 2,
    back = 'ffxi/BarBG.png', fill = 'ffxi/Bar.png', front = 'ffxi/BarFG.png', glow = 'ffxi/BarGlow.png', glowSides = 'ffxi/BarGlowSides.png',
    color = Hex('FF9597'), glowColor = Hex('FFF2F2') }
local mpImages = { width = 128, height = 64, fillX = 27, fillWidth = 74, glowSidesWidth = 2,
    back = 'ffxi/AllyBarBgMP.png', fill = 'ffxi/AllyBarMP.png', front = 'ffxi/AllyBarFgMP.png', glow = 'ffxi/AllyBarGlowMP.png', glowSides = 'ffxi/AllyBarGlowSidesMP.png',
    color = Hex('FFFF9C'), glowColor = Hex('FFFFF2') }

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
    -- TP is a figure alone: to the left of the MP bar for the player's party, and for the others
    -- under the start of the name. XivParty writes it smaller than HP and MP; here the three are one
    -- size (valueSize), and TP is a little higher to stay level with the MP bar.
    tp = {
        party = { value = 'tp', x = 0, y = 0, figure = { x = 56, y = 18, alignRight = true } },
        alliance = { value = 'tp', x = 0, y = 0, figure = { x = 24, y = 18 } },
    },
    leader = { x = 2, y = 21, width = 7, height = 5, file = 'ffxi/Leader.png',
               partyColor = Hex('E6E159'), allianceX = 7 },
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
local valueOffsets = { }  -- hp, mp, tp -> { x, y }: how far that figure is moved from its place, if at all
local outlined = true     -- whether the names and figures have winxi's dark edge
local barGlow = true      -- whether a change to a bar is covered by a glow for a moment
local nameChars = nil     -- how much of a name is written, where it is not the layout's own

local cornerA, cornerB = { 0, 0 }, { 0, 0 }
local uvA, uvB = { 0, 0 }, { 1, 1 }
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

-- An image, by its file or the number of a texture, at a place in the layout's units. flipped draws it
-- mirrored left to right. With top and bottom (0 to 1) only that much of its height is drawn, where
-- it would have been.
local function Image(image, x, y, width, height, color, alpha, flipped, top, bottom)
    local handle = type(image) == 'number' and image or Texture(image)
    if not handle or width == 0 then
        return
    end

    top, bottom = top or 0, bottom or 1
    cornerA[1], cornerA[2] = itemX + x * scale, itemY + (y + height * top) * scale
    cornerB[1], cornerB[2] = cornerA[1] + width * scale, itemY + (y + height * bottom) * scale
    uvA[1], uvB[1] = flipped and 1 or 0, flipped and 0 or 1
    uvA[2], uvB[2] = top, bottom
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

-- What is kept for each line between frames, by member: where each bar's glow has got to (a bar jumps
-- to a new value at once, and a glow covers what it lost and closes over a moment), and each figure
-- as it was last written, so that it is only made into words and measured again when it changes
local animations = { }
local animationCount = 0
local lastFrame = os.clock()
local animStep = 1 -- how much of the way a glow closes this frame
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

-- Moves a bar on for this frame: how full it is, and where its glow has got to. A loss is covered by a
-- glow that closes on the bar's new value; a gain simply shows. While dimmed there is no glow and the
-- bar itself moves, down or up.
local function Advance(bar, percent, opacity)
    local fraction = math.max(0, math.min(1, (percent or 0) / 100))
    local shown = bar.shown or fraction
    if fraction > shown and opacity >= 1 then
        shown = fraction
    else
        shown = shown + (fraction - shown) * animStep
        if math.abs(fraction - shown) < 0.001 then
            shown = fraction
        end
    end
    bar.fraction, bar.shown = fraction, shown
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

local function Back(place)
    local images = place.images
    Image(images.back, place.x, place.y, images.width, images.height, images.color)
end

local function Fill(place, bar, opacity)
    local images = place.images
    local full = opacity < 1 and bar.shown or bar.fraction
    Image(images.fill, place.x + images.fillX, place.y, images.fillWidth * full, images.height, images.color, opacity)
end

local function Front(place)
    local images = place.images
    Image(images.front, place.x, place.y, images.width, images.height, images.color)
end

-- The glow over what a bar has just lost, and its two ends. Only the band about the bar is drawn of
-- each (see glowTop).
local function Glows(bar, opacity)
    return opacity >= 1 and bar.shown - bar.fraction > 0.01
end

local function Glow(place, bar, opacity)
    if Glows(bar, opacity) then
        local images = place.images
        Image(images.glow, place.x + images.fillX + images.fillWidth * bar.fraction, place.y,
            images.fillWidth * (bar.shown - bar.fraction), images.height, images.glowColor, glowOpacity, false, glowTop, glowBottom)
    end
end

local function GlowEnds(place, bar, opacity)
    if Glows(bar, opacity) then
        local images = place.images
        local sides = images.glowSidesWidth
        local left = place.x + images.fillX + images.fillWidth * bar.fraction
        local right = place.x + images.fillX + images.fillWidth * bar.shown
        Image(images.glowSides, left - sides, place.y, sides, images.height, images.glowColor, glowOpacity, false, glowTop, glowBottom)
        Image(images.glowSides, right, place.y, sides, images.height, images.glowColor, glowOpacity, true, glowTop, glowBottom)
    end
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
    if barGlow then
        Layer(count, kind, place, Glow)
        Layer(count, kind, place, GlowEnds)
    end
end

-- A member's name, marked as the party window's own view marks it: "> " in green on the member a
-- sub-target or the party cursor is on, ">> " in blue on the one targeted. The marked name is kept
-- while the name and the mark stay as they are.
local function DrawName(member, state)
    local name = layout.name
    local shown = Trimmed(member.name or '???', nameChars or name.maxChars)

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
    Write(shown, name.x, name.y, color)
end

-- A bar's figure, or for TP, which has no bar, the figure that is all there is of it. fontSize is the
-- size it is written at, which its width goes with.
local function DrawFigure(place, member, kept, fontSize)
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
            color = tpFull
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

    local figure = place.figure
    local x, y = place.x + figure.x, place.y + figure.y
    local offset = valueOffsets[kind]
    if offset ~= nil then
        x, y = x + (tonumber(offset[1]) or 0), y + (tonumber(offset[2]) or 0)
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
            Image(texture, x - shown * size, y, size, size)
        end
    end
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
    valueOffsets.hp, valueOffsets.mp, valueOffsets.tp = settings.hpOffset, settings.mpOffset, settings.tpOffset
    outlined = settings.outline ~= false
    barGlow = settings.glow ~= false
    nameChars = settings.nameChars
    local showMp, showTp = settings.showMp ~= false, settings.showTp ~= false
    textColor = theme.Get().TextColor

    -- once a frame, whichever list is drawn first: the others are drawn a moment later in the same one
    local now = os.clock()
    local elapsed = now - lastFrame
    if elapsed >= 0.004 or displayWidth == nil then
        lastFrame = now
        animStep = 1 - (1 - barAnimSpeed) ^ (math.max(0, math.min(elapsed, 0.25)) / animFrame)
        local display = imgui.GetIO().DisplaySize
        displayWidth, displayHeight = display.x, display.y
    end

    -- the room the list itself needs. The buffs go beyond it, beside the window.
    local windowX, windowY = imgui.GetCursorScreenPos()
    room[1] = math.ceil(layout.width * scale)
    room[2] = math.ceil(count * layout.rowHeight * scale)
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

    -- each line: where it is, and its bars moved on for this frame
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
            Advance(state.hp, member.hpp, state.opacity)
            if state.hasMp then
                Advance(state.mp, member.mpp, state.opacity)
            end
        else
            anyElsewhere = true
        end
    end

    -- from the bottom up: the bars, the names, and last the figures, which stay readable where a long
    -- or large name runs into them
    DrawBars(count, 'hp', layout.hp)
    DrawBars(count, 'mp', layout.mp)

    imgui.PushFont(nil, FontSize(layout.name.size * nameScale))
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
    local tpPlace = layout.tp[kind] or layout.tp.party
    imgui.PushFont(nil, valueFont)
    for index = 1, count do
        local member, state = members[index], lineStates[index]
        if state.inZone then
            itemY = lineY[index]
            DrawFigure(layout.hp, member, state.hp, valueFont)
            if state.hasMp and showMp then
                DrawFigure(layout.mp, member, state.mp, valueFont)
            end
            if showTp and member.tp ~= nil then
                DrawFigure(tpPlace, member, state.tp, valueFont)
            end
        end
    end
    imgui.PopFont()

    -- the leader's marks: the party's, and beside it the alliance's
    local leader = layout.leader
    for index = 1, count do
        local member = members[index]
        if member.isPartyLeader or member.isAllianceLeader then
            itemY = lineY[index]
            if member.isPartyLeader then
                Image(leader.file, leader.x, leader.y, leader.width, leader.height, leader.partyColor)
            end
            if member.isAllianceLeader then
                Image(leader.file, leader.x + leader.allianceX, leader.y, leader.width, leader.height)
            end
        end
    end

    -- only the player's own party shows buffs: they start a little clear of the window's left edge
    if kind == 'party' then
        local buffsX = (imgui.GetWindowPos() - layout.buffs.gap - itemX) / scale
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
