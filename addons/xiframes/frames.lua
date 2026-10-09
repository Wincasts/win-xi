-- frames: draws lines of bars. A list of members, of pets, or a target is a list of lines, and each
-- line is a name, an HP bar and a smaller MP bar with their figures, and TP as a figure alone, set out
-- the way XivParty, a party list addon for Windower 4 by Tylas, sets out its compact layout
-- (https://github.com/Tylas11/XivParty; its layouts/ffxi2.xml). The bars are that addon's images, in
-- assets/bars with its licence. What is XivParty's and is not here: its background, job icons and cursor;
-- its glow over a bar that changes; buffs sorted debuffs first; a mark for the quartermaster; and
-- anything happening on hovering or clicking a member. What is here and is not XivParty's: a soft
-- shadow under each bar, silver bookends at its ends, and circles for leaders.
--
--     frames.Draw(lines, kind, StatusTexture, style)
--
-- is called inside a window. It takes up the room the list needs and draws into it; buffs are drawn
-- beyond that room, beside the window. StatusTexture(id) gives the texture for a status icon, or nil.
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
--     isTarget, isSubTarget, isPartyTarget     ">> " before the name in blue, or "> " in green
--     isPlayer, targetIndex, entity            for how far away they are: bars dim with distance
--     statusIds                their buffs
--
-- style says how (options.lua makes one from the settings), each left out for the usual:
--     scale, nameSize, valueSize, buffSize     percentages: of everything, and of each alone
--     buffSpacing, buffDistance                room between buff icons, and between them and the window
--     hpOffset, mpOffset, tpOffset             { x, y } to move that figure from its place
--     outline, bookends, tpFlash               false to leave each out
--     showMp, showTp           false to leave the MP or the TP figure out; the MP bar is drawn either way
--     nameChars                how many characters of a name are written before it is cut short
--     trimLast                 true for a list that is the last thing in its window: its last line is
--                              then only as tall as what is on it
require('common')
local imgui = require('imgui')
local theme = require('winxi.theme')
local outlinedText = require('winxi.text')
local draw = require('draw')
local colors = require('colors')

local frames = { }

local castRange = 20.79       -- beyond this a member's bars are dimmed, and beyond targetRange dimmed further
local targetRange = 50

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

local barShadowReach = 3 -- how far below a bar its shadow goes
local hpColor, mpColor = Hex('FF9597'), Hex('FFFF9C') -- what the bars' images, which are grey, are tinted

-- The bookends: a small silver cap at each end of a bar, as tall as the whole bar, frame and all, and
-- standing half on it, after the ones the bars of the game's own party list have
local bookend = { width = 3.6, over = 1.8 } -- how wide a cap is, and how far past the bar's inside its frame goes, above and below
local bookendSilver = { 0.78, 0.80, 0.84, 1 }
local bookendShade = { 0.52, 0.54, 0.60, 1 } -- towards its top and bottom, as a bar's frame darkens towards its own
local bookendHalfShade = { 0.65, 0.67, 0.72, 1 } -- and between that and the silver
local bookendShine = { 0.97, 0.97, 1.00, 1 }
local bookendEdge = { 0.20, 0.21, 0.25, 1 }

-- The layout: where everything on a line is, from the line's top left, and how big, in pixels at a
-- scale of 100. It began as XivParty's own numbers, a fifth larger, without the job icon and cursor
-- that layout has to the left of the name: the name starts the line.
--
-- A bar is three images, a back, a fill and a front, tinted its colour. frame is where the back and
-- the front go; the fill starts at fill.x, on the frame's top and of its height, and is fill.width
-- long when the bar is full. body is the inside of the bar: its ends are where the bookends go, and
-- its bottom is what a line's height is reckoned from. figure is where the bar's value is written:
-- with alignRight its right end goes there.
local layout = {
    width = 163.2, rowHeight = 38.4,
    valueSize = 14.72, -- the HP, MP and TP figures are written at one size, in pixels as the names' is
    hp = { value = 'hp', color = hpColor,
           back = 'bars/hp_back.png', fillImage = 'bars/hp_fill.png', front = 'bars/hp_front.png',
           frame = { x = 18, y = 9.6, width = 132, height = 16.8 },
           fill = { x = 22.8, width = 122.4 },
           body = { left = 21.6, top = 13.2, right = 146.4, bottom = 22.8 },
           figure = { x = 144, y = 4.8, alignRight = true } },
    mp = { value = 'mp', color = mpColor,
           back = 'bars/mp_back.png', fillImage = 'bars/mp_fill.png', front = 'bars/mp_front.png',
           frame = { x = 66, y = 21.6, width = 98.4, height = 14.4 },
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
    name = { x = 0, y = 0, size = 18.4, maxChars = 9 },
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
local bookends = true     -- whether the bars have their silver caps
local valueOffsets = { }  -- hp, mp, tp -> { x, y }: how far that figure is moved from its place, if at all
local outlined = true     -- whether the names and figures have winxi's dark edge
local nameChars = nil     -- how much of a name is written, where it is not the layout's own

-- An image, by its file or the number of a texture, at a place in the layout's units
local function Image(image, x, y, width, height, color, alpha)
    local handle = type(image) == 'number' and image or draw.Texture(image)
    if not handle or width == 0 then
        return
    end

    local left, top = itemX + x * scale, itemY + y * scale
    draw.Image(handle, left, top, left + width * scale, top + height * scale, draw.Packed(color or white, alpha or 1))
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

-- An area's name as it is written, in brackets and cut short, by the area's number: the game's own
-- name for it, asked for once. False where the game has none.
local zoneTexts = { }

local function ZoneText(id, maxChars)
    local text = zoneTexts[id]
    if text == nil then
        local name = AshitaCore:GetResourceManager():GetString('zones.names', id)
        text = (type(name) == 'string' and name ~= '') and Trimmed(('(%s)'):format(name), maxChars) or false
        zoneTexts[id] = text
    end
    return text
end

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

local function Front(place, bar)
    local frame = place.frame
    Image(place.front, frame.x, frame.y, frame.width, frame.height, bar.color or place.color)
end

-- A bar's two bookends. Each is a silver cap, darker towards its top and bottom in two steps as the
-- bars themselves are, with a dark edge and a line of shine down the left of its bright middle.
local function Cap(centre, top, bottom)
    -- every cap is the same whole number of pixels wide, wherever its bar's end falls
    local width = math.max(2, math.floor(bookend.width * scale + 0.5))
    local left = math.floor(itemX + centre * scale - width / 2 + 0.5)
    local right = left + width
    top, bottom = math.floor(itemY + top * scale + 0.5), math.floor(itemY + bottom * scale + 0.5)

    draw.Rect(left, top, right, bottom, draw.Packed(bookendSilver, 1), 1)

    -- the shading: a band at the top and one at the bottom, each darkest at the very end
    local band = math.max(1, math.floor((bottom - top) * 0.14 + 0.5))
    draw.Rect(left, top, right, top + 2 * band, draw.Packed(bookendHalfShade, 1), 0)
    draw.Rect(left, top, right, top + band, draw.Packed(bookendShade, 1), 0)
    draw.Rect(left, bottom - 2 * band, right, bottom, draw.Packed(bookendHalfShade, 1), 0)
    draw.Rect(left, bottom - band, right, bottom, draw.Packed(bookendShade, 1), 0)

    draw.Outline(left, top, right, bottom, draw.Packed(bookendEdge, 1), 1)
    if bottom - 2 * band - 1 > top + 2 * band then
        draw.Line(left + 1, top + 2 * band, left + 1, bottom - 2 * band - 1, draw.Packed(bookendShine, 1))
    end
end

-- the top and bottom of a cap are those of the bar's frame
local function Bookends(place)
    local body = place.body
    local top, bottom = body.top - bookend.over, body.bottom + bookend.over
    Cap(body.left, top, bottom)
    Cap(body.right, top, bottom)
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
        mark, color = '> ', colors.Green
    elseif member.isTarget then
        mark, color = '>> ', colors.Blue
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

    return math.min(layout.rowHeight, bottom + 1.2)
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

function frames.Draw(members, kind, StatusTexture, style)
    local count = #members
    if count == 0 then
        return
    end

    style = style or usual
    scale = Percent(style.scale)
    valueScale = Percent(style.valueSize)
    nameScale = Percent(style.nameSize)
    buffScale = Percent(style.buffSize)
    buffSpacing = tonumber(style.buffSpacing) or 0
    bookends = style.bookends ~= false
    valueOffsets.hp, valueOffsets.mp, valueOffsets.tp = style.hpOffset, style.mpOffset, style.tpOffset
    outlined = style.outline ~= false
    nameChars = style.nameChars
    local showMp, showTp = style.showMp ~= false, style.showTp ~= false
    textColor = theme.Get().TextColor

    -- where the pulse of a TP figure at 1000 and over has got to: 0 at the light blue, 1 at the deeper
    -- one, moving smoothly from one to the other and back; or kept at the deeper one
    local blend = 1
    if style.tpFlash ~= false then
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
    if style.trimLast then
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
    local drawList = imgui.GetWindowDrawList()
    clipMax[1], clipMax[2] = displayWidth, displayHeight
    drawList:PushClipRect(clipMin, clipMax, false)
    draw.Use(drawList)

    outlineEdge = math.max(1, math.floor(scale + 0.5))
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
            local text = not member.isInZone and ZoneText(member.zoneId, zone.maxChars)
            if text then
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
        local buffsX = (imgui.GetWindowPos() - layout.buffs.gap - itemX) / scale - (tonumber(style.buffDistance) or 0)
        for index = 1, count do
            if lineStates[index].inZone then
                itemY = lineY[index]
                DrawBuffs(members[index], buffsX, StatusTexture)
            end
        end
    end

    drawList:PopClipRect()
end

return frames
