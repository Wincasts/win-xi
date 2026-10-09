-- XivParty Style: the party lists drawn the way XivParty, a party list addon for Windower 4 by Tylas,
-- draws them (https://github.com/Tylas11/XivParty). The images are that addon's own, in
-- assets/xivparty with its licence. Two of its layouts are here:
--
--   compact  its ffxi2 layout, in the manner of the game's own party list: a line a member, with a
--            small job icon, the name, an HP bar and a smaller MP bar with their figures, TP as a
--            figure alone, and the buffs running leftwards from the list. The other two alliance
--            parties are drawn the same way, without buffs.
--   full     its default xiv layout: a taller row a member, with the job and sub job, bars for HP, MP
--            and TP with their figures under them, and the buffs to the right. Each of the other two
--            alliance parties is a grid of small cells, three across.
--
--     xivparty.Draw(members, 'party' or 'alliance', scale, StatusTexture, 'compact' or 'full')
--
-- is called inside a window with no padding or background of its own. It takes up the room the list
-- itself needs and draws into it; the buffs are drawn beyond that room, beside the list. members are
-- the party window's own (see us.lua). scale is a percentage, or 0 for XivParty's own choice: full
-- size on a screen 1440 high, and in proportion on any other. StatusTexture(id) gives the texture for
-- a status icon, or nil.
--
-- What is XivParty's and is not here: the buffs are in the game's order, not sorted debuffs first; there
-- is no mark for the quartermaster; and nothing happens on hovering or clicking a member.
require('common')
local ffi = require('ffi')
local d3d8 = require('d3d8')
local imgui = require('imgui')
local zones = require('utils/zones')

local xivparty = { }

local baseScreenHeight = 1440 -- the screen XivParty's sizes are for
local castRange = 20.79       -- beyond this a member's bars are dimmed, and beyond targetRange dimmed further
local targetRange = 50
local barAnimSpeed = 0.1      -- how much of the way a bar's glow closes every animFrame seconds
local animFrame = 0.03
local pointsToPixels = 4 / 3  -- XivParty's text sizes are in points

local white = { 1, 1, 1, 1 }
local textColor = { 0.94, 1.00, 1.00, 1.00 }       -- #F0FFFFFF
local strokeColor = { 0.02, 0.18, 0.33, 0.78 }     -- #062D54C8
local hpYellow = { 0.95, 0.95, 0.49, 1.00 }        -- #F3F37CFF, below 75%
local hpOrange = { 0.97, 0.73, 0.50, 1.00 }        -- #F8BA80FF, below 50%
local hpRed = { 0.99, 0.51, 0.51, 1.00 }           -- #FC8182FF, below 25%
local tpFull = { 0.31, 0.71, 0.98, 1.00 }          -- #50B4FAFF, at 1000 and over

-- The colour behind a job's icon says what the job is for
local roleColors = {
    dd      = { 0.40, 0.21, 0.21, 1 }, -- #663535
    healer  = { 0.23, 0.40, 0.16, 1 }, -- #3B6529
    tank    = { 0.21, 0.27, 0.59, 1 }, -- #364597
    support = { 0.85, 0.70, 0.00, 1 }, -- #DAB200
}
local jobRoles = {
    WAR = 'dd', MNK = 'dd', WHM = 'healer', BLM = 'dd', RDM = 'healer', THF = 'dd', PLD = 'tank', DRK = 'dd',
    BST = 'dd', BRD = 'support', RNG = 'dd', SAM = 'dd', NIN = 'dd', DRG = 'dd', SMN = 'dd', BLU = 'dd',
    COR = 'support', PUP = 'tank', DNC = 'dd', SCH = 'healer', GEO = 'support', RUN = 'tank',
}

-- A colour as XivParty's layouts write it
local function Hex(code)
    return { tonumber(code:sub(1, 2), 16) / 255, tonumber(code:sub(3, 4), 16) / 255, tonumber(code:sub(5, 6), 16) / 255, 1 }
end

-- The images of a bar: a back, the fill that is as long as the bar is full (it starts fillX across
-- and is fillWidth long when full), a front, and the glow that covers a change with its two ends.
-- color tints the back, fill and front; glowColor the glow.
local xivBar = { width = 128, height = 64, fillX = 13, fillWidth = 102, glowSidesWidth = 2,
    back = 'xiv/BarBG.png', fill = 'xiv/Bar.png', front = 'xiv/BarFG.png', glow = 'xiv/BarGlow.png', glowSides = 'xiv/BarGlowSides.png' }
local xivAllyHp = { width = 64, height = 64, fillX = 4, fillWidth = 56, glowSidesWidth = 3,
    back = 'xiv/AllyBarBG.png', fill = 'xiv/AllyBarHP.png', front = 'xiv/AllyBarFG.png', glow = 'xiv/AllyBarGlowHP.png', glowSides = 'xiv/AllyBarGlowSidesHP.png' }
local xivAllyMp = { width = 64, height = 64, fillX = 4, fillWidth = 56, glowSidesWidth = 3,
    fill = 'xiv/AllyBarMP.png', front = 'xiv/AllyBarFG.png', glow = 'xiv/AllyBarGlowMP.png', glowSides = 'xiv/AllyBarGlowSidesMP.png' }
local ffxiHp = { width = 128, height = 64, fillX = 13, fillWidth = 102, glowSidesWidth = 2,
    back = 'ffxi/BarBG.png', fill = 'ffxi/Bar.png', front = 'ffxi/BarFG.png', glow = 'ffxi/BarGlow.png', glowSides = 'ffxi/BarGlowSides.png',
    color = Hex('FF9597'), glowColor = Hex('FFF2F2') }
local ffxiMp = { width = 128, height = 64, fillX = 27, fillWidth = 74, glowSidesWidth = 2,
    back = 'ffxi/AllyBarBgMP.png', fill = 'ffxi/AllyBarMP.png', front = 'ffxi/AllyBarFgMP.png', glow = 'ffxi/AllyBarGlowMP.png', glowSides = 'ffxi/AllyBarGlowSidesMP.png',
    color = Hex('FFFF9C'), glowColor = Hex('FFFFF2') }

-- The compact list is the same for the player's party and the others, but for the buffs and where TP goes
local function CompactList(buffs, tpFigure)
    return {
        columns = 1, columnWidth = 168, rowHeight = 32,
        margin = { 24, 6 },
        background = { x = 7, y = -6, width = 160, topHeight = 6, bottomHeight = 4, alpha = 1,
                       top = 'ffxi/AllyBgTop.png', mid = 'ffxi/AllyBgMid.png', bottom = 'ffxi/AllyBgBottom.png' },
        cursor = { file = 'ffxi/Cursor.png', x = -24, y = 7, width = 37 * 0.75, height = 24 * 0.75 },
        bars = {
            { value = 'hp', x = 30, y = -17, images = ffxiHp, hideOutsideZone = true,
              figure = { x = 114, y = 22, size = 8, alignRight = true } },
            { value = 'mp', x = 56, y = -8, images = ffxiMp, hideOutsideZone = true,
              figure = { x = 100, y = 22, size = 8, alignRight = true } },
            { value = 'tp', x = 0, y = 0, hideOutsideZone = true, figure = tpFigure }, -- a figure alone
        },
        jobIcon = { x = -6, y = 2, size = 36 * 0.75 },
        leader = { x = 26, y = 21, width = 7, height = 5,
                   party = { file = 'ffxi/Leader.png', x = 0, y = 0, color = Hex('E6E159') },
                   alliance = { file = 'ffxi/Leader.png', x = 7, y = 0 } },
        name = { x = 24, y = 0, size = 10, maxChars = 9 },
        zone = { x = 160, y = 14, size = 10, maxChars = 16, alignRight = true },
        buffs = buffs,
    }
end

-- The layouts, in XivParty's own numbers: places and sizes are in its units, from the top left of a
-- member's row or cell. margin is how far the list itself reaches left of and above the first member.
-- A figure's place is from its bar's; with alignRight its right end goes there.
local layouts = {
    compact = {
        -- the buffs run leftwards from beside the cursor, sixteen at most
        party = CompactList({ x = -25, y = 5, size = 20, gap = 1, rows = { 16 }, offsets = { 0 }, alignRight = true },
                            { x = 80, y = 20, size = 6, alignRight = true }),
        alliance = CompactList(nil, { x = 48, y = 20, size = 6 }),
    },
    full = {
        party = {
            columns = 1, columnWidth = 410, rowHeight = 46,
            margin = { 24, 21 },
            background = { x = 0, y = -21, width = 377, topHeight = 21, bottomHeight = 21, alpha = 0.87,
                           top = 'xiv/BgTop.png', mid = 'xiv/BgMid.png', bottom = 'xiv/BgBottom.png' },
            cursor = { file = 'xiv/Cursor.png', x = 20, y = -8, width = 390, height = 60 },
            bars = {
                { value = 'hp', x = 19, y = -7, images = xivBar, figure = { x = 120, y = 35, size = 11, alignRight = true } },
                { value = 'mp', x = 150, y = -7, images = xivBar, figure = { x = 120, y = 35, size = 11, alignRight = true } },
                { value = 'tp', x = 281, y = -7, images = xivBar, figure = { x = 120, y = 35, size = 11, alignRight = true } },
            },
            jobIcon = { x = -11, y = -2, size = 36 },
            leader = { x = -24, y = -8, width = 24, height = 24,
                       party = { file = 'xiv/Leader.png', x = 0, y = 0 },
                       alliance = { file = 'xiv/AllianceLeader.png', x = 0, y = 12 } },
            name = { x = 95, y = 1, size = 15, maxChars = 17 },
            zone = { x = 292, y = 1, size = 13 },
            job = { x = 30, y = 0, size = 8 },
            sub = { x = 39, y = 9, size = 8 },
            buffs = { x = 293, y = 0, size = 20, gap = 1, rows = { 19, 13 }, offsets = { 0, 6 } },
        },
        alliance = {
            columns = 3, columnWidth = 105, rowHeight = 42,
            margin = { 6, 6 },
            background = { x = -6, y = -6, width = 327, topHeight = 5, bottomHeight = 5, alpha = 0.75,
                           top = 'xiv/AllyBgTop.png', mid = 'xiv/AllyBgMid.png', bottom = 'xiv/AllyBgBottom.png' },
            cursor = { file = 'xiv/AllyCursor.png', x = -6, y = -6, width = 116, height = 53 },
            bars = { -- one over the other: each image has its bar at its own height
                { value = 'hp', x = 37, y = -12, images = xivAllyHp, hideOutsideZone = true },
                { value = 'mp', x = 37, y = -12, images = xivAllyMp, hideOutsideZone = true },
            },
            jobIcon = { x = 4, y = 4, size = 36 * 0.9 },
            leader = { x = -6, y = 0, width = 24 * 0.8, height = 24 * 0.8,
                       party = { file = 'xiv/Leader.png', x = 0, y = 0 },
                       alliance = { file = 'xiv/AllianceLeader.png', x = 0, y = 12 * 0.8 } },
            name = { x = 41, y = 1, size = 8, maxChars = 9 },
            zone = { x = 8, y = 18, size = 9, maxChars = 14 },
        },
    },
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

local jobIconFiles = { } -- job -> its icon's file: made once

local function JobIconFile(job)
    local file = jobIconFiles[job]
    if file == nil then
        file = ('jobIcons/%s.png'):format(job:lower())
        jobIconFiles[job] = file
    end
    return file
end

-- What is being drawn: set by Draw and by each member's turn, and read by the helpers below
local drawList = nil
local scale = 1
local itemX, itemY = 0, 0 -- the top left of the member being drawn, on screen

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

-- A line of text with a dark edge, at a place in the layout's units. size is in points. With alignRight
-- its right end goes at x.
local function Text(text, x, y, size, color, alignRight)
    imgui.PushFont(nil, size * pointsToPixels * scale)

    local left, top = itemX + x * scale, itemY + y * scale
    if alignRight then
        left = left - imgui.CalcTextSize(text)
    end
    left, top = math.floor(left), math.floor(top)

    -- the edge is the text again, behind itself and a little to each corner
    local edge = math.max(1, math.floor(scale + 0.5))
    local stroke = imgui.GetColorU32(strokeColor)
    for dx = -edge, edge, 2 * edge do
        for dy = -edge, edge, 2 * edge do
            textPos[1], textPos[2] = left + dx, top + dy
            drawList:AddText(textPos, stroke, text)
        end
    end
    textPos[1], textPos[2] = left, top
    drawList:AddText(textPos, imgui.GetColorU32(color or textColor), text)

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
local animations = { } -- server id -> { hp, mp, tp = where the glow has got to (0 to 1), seen = when last drawn }
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

local function DrawBar(place, member, state, opacity)
    local kind = place.value
    local known = member.isInZone
    if not known and place.hideOutsideZone then
        return
    end

    local amount, fraction = -1, 0
    if known then
        if kind == 'hp' then
            amount, fraction = member.hp, (member.hpp or 0) / 100
        elseif kind == 'mp' then
            amount, fraction = member.mp, (member.mpp or 0) / 100
        else
            amount, fraction = member.tp, (member.tp or 0) / 3000
        end
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

        local color = images.color
        if images.back ~= nil then
            Image(images.back, x, y, images.width, images.height, color)
        end
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

    local figure = place.figure
    if figure ~= nil then
        local color = textColor
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
        Text(amount < 0 and '?' or tostring(amount), x + figure.x, y + figure.y, figure.size, color, figure.alignRight)
    end
end

-- The buffs in rows, each row so many and starting so many icons across. With alignRight they run
-- leftwards, the first with its right edge at the buffs' place.
local function DrawBuffs(buffs, member, StatusTexture)
    local ids = member.statusIds
    if ids == nil or StatusTexture == nil then
        return
    end

    local row, column = 1, 0
    for _, id in ipairs(ids) do
        if column >= buffs.rows[row] then
            row, column = row + 1, 0
            if buffs.rows[row] == nil then
                return -- no room for the rest
            end
        end

        local texture = StatusTexture(id)
        if texture ~= nil then
            local across = (buffs.offsets[row] + column) * buffs.size
            local x = buffs.alignRight and (buffs.x - across - buffs.size) or (buffs.x + across)
            Image(texture, x, buffs.y + (row - 1) * (buffs.size + buffs.gap), buffs.size, buffs.size)
            column = column + 1
        end
    end
end

local function DrawMember(layout, member, StatusTexture)
    local inZone = member.isInZone
    local selected = member.isTarget
    local state = Animation(member)

    -- the cursor: on the member targeted, and fainter on one a sub-target or the party cursor is on
    if inZone and (selected or member.isSubTarget or member.isPartyTarget) then
        local cursor = layout.cursor
        Image(cursor.file, cursor.x, cursor.y, cursor.width, cursor.height, white, selected and 1 or 0.5)
    end

    local opacity = RangeOpacity(member)
    for _, place in ipairs(layout.bars) do
        DrawBar(place, member, state, opacity)
    end

    -- the job icon, front to back: frame, icon, gradient, a background in the colour of the job's role,
    -- and a highlight behind them all on the member targeted
    local job = member.job
    if inZone and job ~= nil then
        local icon = layout.jobIcon
        local unit = icon.size / 36
        if selected then
            Image('jobIcons/highlight.png', icon.x - 13 * unit, icon.y - 13 * unit, 62 * unit, 62 * unit)
        end
        Image('jobIcons/bg.png', icon.x, icon.y, icon.size, icon.size, roleColors[jobRoles[job]] or white)
        Image('jobIcons/gradient.png', icon.x, icon.y, icon.size, icon.size)
        Image(JobIconFile(job), icon.x, icon.y, icon.size, icon.size)
        Image('jobIcons/frame.png', icon.x, icon.y, icon.size, icon.size)
    end

    local name = layout.name
    Text(Trimmed(member.name or '???', name.maxChars), name.x, name.y, name.size)

    if not inZone then
        local zone = layout.zone
        local zoneName = zones[member.zoneId]
        if zoneName ~= nil then
            Text(Trimmed(('(%s)'):format(zoneName), zone.maxChars), zone.x, zone.y, zone.size, nil, zone.alignRight)
        end
    elseif layout.job ~= nil and job ~= nil then
        Text(('%s %d'):format(job, member.jobLevel or 0), layout.job.x, layout.job.y, layout.job.size)
        if member.sub ~= nil and (member.subLevel or 0) > 0 then
            Text(('%s %d'):format(member.sub, member.subLevel), layout.sub.x, layout.sub.y, layout.sub.size)
        end
    end

    -- the leader's marks: the party's and the alliance's
    local leader = layout.leader
    if member.isPartyLeader then
        local mark = leader.party
        Image(mark.file, leader.x + mark.x, leader.y + mark.y, leader.width, leader.height, mark.color)
    end
    if member.isAllianceLeader then
        local mark = leader.alliance
        Image(mark.file, leader.x + mark.x, leader.y + mark.y, leader.width, leader.height, mark.color)
    end

    if inZone and layout.buffs ~= nil then
        DrawBuffs(layout.buffs, member, StatusTexture)
    end
end

-- The scale XivParty gives itself on this screen
function xivparty.AutoScale()
    local display = imgui.GetIO().DisplaySize
    local auto = display.y / baseScreenHeight
    return math.floor(auto * 100 + 0.5) / 100
end

local room = { 0, 0 }

-- The layouts there are, for a setting to choose between: the first is the one used when none is given
xivparty.Layouts = { { key = 'compact', label = 'Compact' }, { key = 'full', label = 'Full' } }

local clipMin, clipMax = { 0, 0 }, { 0, 0 }

function xivparty.Draw(members, kind, scalePercent, StatusTexture, layoutName)
    local set = layouts[layoutName] or layouts.compact
    local layout = set[kind] or set.party
    local count = #members
    if count == 0 then
        return
    end

    scale = (scalePercent ~= nil and scalePercent > 0) and scalePercent / 100 or xivparty.AutoScale()

    -- once a frame, whichever list is drawn first: the others are drawn a moment later in the same one
    local now = os.clock()
    local elapsed = now - lastFrame
    if elapsed >= 0.004 then
        lastFrame = now
        animStep = 1 - (1 - barAnimSpeed) ^ (math.min(elapsed, 0.25) / animFrame)
    end

    local rows = math.floor((count - 1) / layout.columns) + 1
    local contentHeight = rows * layout.rowHeight
    local background = layout.background

    -- the room the list itself needs: its members and what of the background reaches past them. The
    -- buffs go beyond it, beside the list.
    local width = math.max(layout.columns * layout.columnWidth, background.x + background.width)
    local height = background.y + background.topHeight + contentHeight + background.bottomHeight

    local windowX, windowY = imgui.GetCursorScreenPos()
    room[1] = math.ceil((layout.margin[1] + width) * scale)
    room[2] = math.ceil((layout.margin[2] + height) * scale)
    imgui.Dummy(room)

    -- a list laid out off screen to be measured needs its room and nothing else
    local display = imgui.GetIO().DisplaySize
    if windowX + room[1] < 0 or windowY + room[2] < 0 or windowX > display.x or windowY > display.y then
        return
    end

    -- the window's own list, so the list sits with the window among the others and fades with it,
    -- opened up to the whole screen (and no further) for what goes beside the list
    drawList = imgui.GetWindowDrawList()
    clipMax[1], clipMax[2] = display.x, display.y
    drawList:PushClipRect(clipMin, clipMax, false)

    local originX = math.floor(windowX + layout.margin[1] * scale)
    local originY = math.floor(windowY + layout.margin[2] * scale)

    -- the background: a top and a bottom, and a middle as tall as the members
    itemX, itemY = originX, originY
    Image(background.top, background.x, background.y, background.width, background.topHeight, white, background.alpha)
    Image(background.mid, background.x, background.y + background.topHeight, background.width, contentHeight, white, background.alpha)
    Image(background.bottom, background.x, background.y + background.topHeight + contentHeight, background.width, background.bottomHeight, white, background.alpha)

    for index, member in ipairs(members) do
        local row = math.floor((index - 1) / layout.columns)
        local column = (index - 1) % layout.columns
        itemX = math.floor(originX + column * layout.columnWidth * scale)
        itemY = math.floor(originY + row * layout.rowHeight * scale)
        DrawMember(layout, member, StatusTexture)
    end

    drawList:PopClipRect()
    drawList = nil
end

return xivparty
