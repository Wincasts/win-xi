-- XivParty Style: the party lists arranged the way XivParty, a party list addon for Windower 4 by
-- Tylas, arranges them in its compact layout (https://github.com/Tylas11/XivParty; its
-- layouts/ffxi2.xml), inside one of this addon's own windows. The bars and the leader's mark are that
-- addon's images, in assets/xivparty with its licence; the window around them, with its background,
-- border, padding and shadow, is the theme's.
--
-- A member is a line: the name, an HP bar and a smaller MP bar with their figures, and TP as a figure
-- alone. Each bar has a soft shadow under it, which XivParty's do not. The member targeted is marked as in the party window's own view: ">> " before the name, both
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
--     outline     false to leave the dark edge off the names and the HP, MP and TP figures: winxi's
--                 way of writing over bars (winxi.text), without which the figures are hard to read
--     hpOffset, mpOffset, tpOffset   { x, y } to move that figure from its place in the layout, in the
--                 layout's units: right and down, or left and up for less than nothing
--
-- is called inside the window. It takes up the room the list needs and draws into it; the buffs are
-- drawn beyond that room, beside the window. members are the party window's own (see us.lua). A scale
-- of 100 is the size this style is meant to be seen at, a fifth larger than XivParty's own.
-- StatusTexture(id) gives the texture for a status icon, or nil. A member may be anything with the
-- same fields: us.lua lists pets this way, giving hpText and mpText for figures in words of its own
-- and leaving mpp and tp out for a line with no MP bar or TP.
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
    hp = { value = 'hp', x = 6, y = -17, images = hpImages, figure = { x = 114, y = 21, size = 8, alignRight = true } },
    mp = { value = 'mp', x = 32, y = -8, images = mpImages, figure = { x = 100, y = 23, size = 8, alignRight = true } },
    -- TP is a figure alone: to the left of the MP bar for the player's party, and for the others
    -- under the start of the name. XivParty writes it smaller than HP and MP; here the three are one
    -- size, and TP is a little higher to stay level with the MP bar.
    tp = {
        party = { value = 'tp', x = 0, y = 0, figure = { x = 56, y = 18, size = 8, alignRight = true } },
        alliance = { value = 'tp', x = 0, y = 0, figure = { x = 24, y = 18, size = 8 } },
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

local cornerA, cornerB = { 0, 0 }, { 0, 0 }
local uvA, uvB = { 0, 0 }, { 1, 1 }
local tint = { 1, 1, 1, 1 }

-- An image, by its file or the number of a texture, at a place in the layout's units. flipped draws it
-- mirrored left to right.
local function Image(image, x, y, width, height, color, alpha, flipped)
    local handle = type(image) == 'number' and image or Texture(image)
    if not handle or width == 0 then
        return
    end

    color = color or white
    tint[1], tint[2], tint[3], tint[4] = color[1], color[2], color[3], color[4] * (alpha or 1)
    cornerA[1], cornerA[2] = itemX + x * scale, itemY + y * scale
    cornerB[1], cornerB[2] = cornerA[1] + width * scale, cornerA[2] + height * scale
    uvA[1], uvB[1] = flipped and 1 or 0, flipped and 0 or 1
    drawList:AddImage(handle, cornerA, cornerB, uvA, uvB, imgui.GetColorU32(tint))
end

local textPos = { 0, 0 }

-- A line of text at a place in the layout's units. size is in points. With alignRight its right end
-- goes at x.
local function Text(text, x, y, size, color, alignRight)
    imgui.PushFont(nil, size * pointsToPixels * textScale * scale)

    local left = itemX + x * scale
    if alignRight then
        left = left - imgui.CalcTextSize(text)
    end
    left = math.floor(left)
    local top = math.floor(itemY + y * scale)

    -- winxi's dark edge, a pixel or so thick: thicker as the lists are drawn larger
    if outlined then
        outlinedText.Draw(drawList, left, top, color or textColor, text, math.max(1, math.floor(scale / baseScale + 0.5)))
    else
        textPos[1], textPos[2] = left, top
        drawList:AddText(textPos, imgui.GetColorU32(color or textColor), text)
    end

    imgui.PopFont()
end

local function Trimmed(text, maxChars)
    if maxChars ~= nil and #text > maxChars then
        return text:sub(1, math.max(1, maxChars - 1)) .. '...'
    end
    return text
end

-- Where each bar's glow has got to, by member: a bar jumps to a new value at once, and a glow covers
-- the difference and closes over a moment
local animations = { } -- server id -> { hp, mp = where the glow has got to (0 to 1) }
local animationCount = 0
local lastFrame = os.clock()
local animStep = 1 -- how much of the way a glow closes this frame

local function Animation(member)
    local key = member.serverId or 0
    local state = animations[key]
    if state == nil then
        -- members come and go: start afresh now and then rather than keep every one ever seen
        if animationCount > 64 then
            animations, animationCount = { }, 0
        end
        state = { }
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

-- A bar with its figure, or for one with no images its figure alone; without the figure where
-- showFigure is false. Nothing for a member in another area.
local function DrawBar(place, member, state, opacity, showFigure)
    if not member.isInZone then
        return
    end

    local kind = place.value
    local amount, fraction
    if kind == 'hp' then
        amount, fraction = member.hp, (member.hpp or 0) / 100
    elseif kind == 'mp' then
        amount, fraction = member.mp, (member.mpp or 0) / 100
    else
        amount, fraction = member.tp, 0
    end
    amount = amount or -1
    fraction = math.max(0, math.min(1, fraction))

    local x, y = place.x, place.y
    local images = place.images
    if images ~= nil then
        -- the glow closes on the bar's value; while dimmed there is no glow and the bar itself moves
        local dimmed = opacity < 1
        local shown = state[kind] or fraction
        shown = shown + (fraction - shown) * animStep
        if math.abs(fraction - shown) < 0.001 then
            shown = fraction
        end
        state[kind] = shown

        -- a soft shadow under the bar, down and to the right, to lift it off the window: the bar's own
        -- back in black, twice, the further one fainter
        Image(images.back, x + 1, y + 1.5, images.width, images.height, black, 0.45)
        Image(images.back, x + 2, y + 2.5, images.width, images.height, black, 0.2)

        local color = images.color
        Image(images.back, x, y, images.width, images.height, color)
        Image(images.fill, x + images.fillX, y, images.fillWidth * (dimmed and shown or fraction), images.height, color, opacity)
        Image(images.front, x, y, images.width, images.height, color)

        if not dimmed and math.abs(fraction - shown) > 0.01 then
            local glowX = x + images.fillX + images.fillWidth * math.min(fraction, shown)
            local glowWidth = images.fillWidth * math.abs(fraction - shown)
            local sides = images.glowSidesWidth
            Image(images.glow, glowX, y, glowWidth, images.height, images.glowColor)
            Image(images.glowSides, glowX - sides, y, sides, images.height, images.glowColor)
            Image(images.glowSides, glowX + glowWidth, y, sides, images.height, images.glowColor, 1, true)
        end
    end

    if not showFigure then
        return
    end

    local figure = place.figure
    local color = nil
    if amount >= 0 then
        if kind == 'hp' then
            local percent = member.hpp or 0
            if percent < 25 then
                color = hpRed
            elseif percent < 50 then
                color = hpOrange
            elseif percent < 75 then
                color = hpYellow
            end
        elseif kind == 'tp' and amount >= 1000 then
            color = tpFull
        end
    end
    -- a line may give a figure in its own words: a pet's HP is known only as a percentage
    local words = (kind == 'hp' and member.hpText) or (kind == 'mp' and member.mpText)
        or (amount < 0 and '?' or tostring(amount))
    local offset = valueOffsets[kind]
    local figureX, figureY = x + figure.x, y + figure.y
    if offset ~= nil then
        figureX, figureY = figureX + (tonumber(offset[1]) or 0), figureY + (tonumber(offset[2]) or 0)
    end
    Text(words, figureX, figureY, figure.size * valueScale, color, figure.alignRight)
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

local function DrawMember(member, kind, buffsX, StatusTexture, showMp, showTp)
    local inZone = member.isInZone
    local state = Animation(member)

    local opacity = RangeOpacity(member)
    DrawBar(layout.hp, member, state, opacity, true)
    -- a line with no MP or TP to show has neither: another player's pet
    if member.mpp ~= nil then
        DrawBar(layout.mp, member, state, opacity, showMp)
    end
    if showTp and member.tp ~= nil then
        DrawBar(layout.tp[kind] or layout.tp.party, member, state, opacity, true)
    end

    -- the name, marked as the party window's own view marks it: "> " in green on the member a
    -- sub-target or the party cursor is on, ">> " in blue on the one targeted
    local name = layout.name
    local shown = Trimmed(member.name or '???', name.maxChars)
    if member.isSubTarget or member.isPartyTarget then
        Text('> ' .. shown, name.x, name.y, name.size * nameScale, ui.Colors.XpBar)
    elseif member.isTarget then
        Text('>> ' .. shown, name.x, name.y, name.size * nameScale, ui.Colors.Blue)
    else
        Text(shown, name.x, name.y, name.size * nameScale)
    end

    if not inZone then
        local zone = layout.zone
        local zoneName = zones[member.zoneId]
        if zoneName ~= nil then
            Text(Trimmed(('(%s)'):format(zoneName), zone.maxChars), zone.x, zone.y, zone.size, nil, true)
        end
    end

    -- the leader's marks: the party's, and beside it the alliance's
    local leader = layout.leader
    if member.isPartyLeader then
        Image(leader.file, leader.x, leader.y, leader.width, leader.height, leader.partyColor)
    end
    if member.isAllianceLeader then
        Image(leader.file, leader.x + leader.allianceX, leader.y, leader.width, leader.height)
    end

    if inZone and buffsX ~= nil then
        DrawBuffs(member, buffsX, StatusTexture)
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
    local showMp, showTp = settings.showMp ~= false, settings.showTp ~= false
    textColor = theme.Get().TextColor

    -- once a frame, whichever list is drawn first: the others are drawn a moment later in the same one
    local now = os.clock()
    local elapsed = now - lastFrame
    if elapsed >= 0.004 then
        lastFrame = now
        animStep = 1 - (1 - barAnimSpeed) ^ (math.min(elapsed, 0.25) / animFrame)
    end

    -- the room the list itself needs. The buffs go beyond it, beside the window.
    local windowX, windowY = imgui.GetCursorScreenPos()
    room[1] = math.ceil(layout.width * scale)
    room[2] = math.ceil(count * layout.rowHeight * scale)
    imgui.Dummy(room)

    -- a list laid out off screen to be measured needs its room and nothing else
    local display = imgui.GetIO().DisplaySize
    if windowX + room[1] < 0 or windowY + room[2] < 0 or windowX > display.x or windowY > display.y then
        return
    end

    -- the window's own list, so the list sits with the window among the others and fades with it,
    -- opened up to the whole screen (and no further) for what goes beside the window
    drawList = imgui.GetWindowDrawList()
    clipMax[1], clipMax[2] = display.x, display.y
    drawList:PushClipRect(clipMin, clipMax, false)

    local originX = math.floor(windowX)
    local originY = math.floor(windowY)

    -- only the player's own party shows buffs: they start a little clear of the window's left edge
    local buffsX = nil
    if kind == 'party' then
        buffsX = (imgui.GetWindowPos() - layout.buffs.gap - originX) / scale
    end

    itemX = originX
    for index, member in ipairs(members) do
        itemY = math.floor(originY + (index - 1) * layout.rowHeight * scale)
        DrawMember(member, kind, buffsX, StatusTexture, showMp, showTp)
    end

    drawList:PopClipRect()
    drawList = nil
end

return xivparty
