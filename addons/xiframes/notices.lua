-- notices: what is waiting for the player's attention, and the icons that say so beside the party's
-- window: an envelope for an invitation to a party or an alliance, and a chest while there is
-- something in the treasure pool.
--
--     notices.HandlePacket(e), notices.HandlePacketOut(e)     every packet in and out goes by these
--     notices.Invitation()          the invitation waiting, { alliance = whether it is to an alliance }, or nil
--     notices.TreasureWaiting()     whether there is anything in the pool
--     notices.DrawIcons(invitation, treasure, corner, offset, scale)     inside the party's window
--
-- An invitation is over when the player answers it (a packet of the client's own), when the inviter
-- withdraws it, or when the player changes area, which drops it: the server sends one packet to say
-- there is one, and nothing more.
local imgui = require('imgui')
local draw = require('draw')
local colors = require('colors')

local notices = { }

local invitation = nil

local packetInvite = 0x0DC          -- in: an invitation
local packetInviteWithdrawn = 0x0DE -- in: the invitation is no more
local packetZoneIn = 0x00A          -- in: the player has arrived in an area
local packetInviteAnswer = 0x074    -- out: the player's answer
local kindAlliance = 5              -- the kind of an invitation to an alliance; a party's is 0

function notices.HandlePacket(e)
    if e.id == packetInvite then
        invitation = { alliance = struct.unpack('B', e.data, 0x0B + 1) == kindAlliance }
    elseif e.id == packetInviteWithdrawn or e.id == packetZoneIn then
        invitation = nil
    end
end

function notices.HandlePacketOut(e)
    if e.id == packetInviteAnswer then
        invitation = nil
    end
end

function notices.Invitation()
    return invitation
end

-- A made-up invitation, to see where the envelope goes while the windows are arranged
notices.SampleInvitation = { alliance = false }

-- Whether there is anything in the treasure pool, which has ten places. Looked at twice a second,
-- not every frame.
local treasureChecked, treasureWaiting = -1, false

function notices.TreasureWaiting()
    local now = os.clock()
    if now - treasureChecked >= 0.5 then
        treasureChecked, treasureWaiting = now, false
        local inventory = AshitaCore:GetMemoryManager():GetInventory()
        for place = 0, 9 do
            local item = inventory:GetTreasurePoolItem(place)
            if item ~= nil and item.ItemId > 0 then
                treasureWaiting = true
                break
            end
        end
    end
    return treasureWaiting
end

-- The corners the icons can go beside, for the setting: the first is the one used when none is chosen
notices.Corners = {
    { key = 'TopRight', label = 'Top Right' }, { key = 'TopLeft', label = 'Top Left' },
    { key = 'BottomRight', label = 'Bottom Right' }, { key = 'BottomLeft', label = 'Bottom Left' },
}

-- The icons are outside the window, above its top corners or below its bottom ones, so nothing in the
-- list moves for them, and where there are both the chest is beside the envelope, further from the
-- corner. They are drawn over every window, not among them, so that another window lying across them
-- does not hide them. Sizes are in the frames' own units.
local envelope = { width = 13, height = 9 }
local chest = { width = 12, height = 10 }
local gap = 5       -- between the window and the icons
local spacing = 4   -- between one icon and the next
local opacity = 0.85 -- neither is quite solid
local edgeColor = { 0.05, 0.05, 0.05, 1 }
local chestWood = { 0.62, 0.40, 0.18, 1 }
local chestTrim = { 0.95, 0.80, 0.30, 1 }
local clipMin, clipMax = { 0, 0 }, { 0, 0 }

-- The envelope: its body, its edge, and the two lines of its flap meeting in the middle. Yellow for a
-- party's and red for an alliance's (the colours of their leaders' marks), between about two thirds of
-- its strength and all of it, once every second and a half.
local function DrawEnvelope(left, top, width, height, shown)
    local pulse = 0.83 + 0.17 * math.cos(os.clock() / 1.5 * 2 * math.pi)
    local body = draw.Packed(shown.alliance and colors.Alliance or colors.Party, pulse * opacity)
    local dark = draw.Packed(edgeColor, opacity)

    draw.Rect(left, top, left + width, top + height, body, 2)
    draw.Outline(left, top, left + width, top + height, dark, 2)
    local middleX, middleY = left + width / 2, top + height * 0.55
    draw.Line(left, top, middleX, middleY, dark)
    draw.Line(left + width, top, middleX, middleY, dark)
end

-- The chest: a wooden box with a band of trim where its lid meets it, a clasp in the middle of the
-- band, and an edge
local function DrawChest(left, top, width, height)
    local wood = draw.Packed(chestWood, opacity)
    local trim = draw.Packed(chestTrim, opacity)
    local dark = draw.Packed(edgeColor, opacity)

    draw.Rect(left, top, left + width, top + height, wood, 2)

    -- the band, a little above the middle, and the clasp across it
    local band = math.max(1, math.floor(height * 0.16 + 0.5))
    local seam = math.floor(top + height * 0.38)
    draw.Rect(left, seam, left + width, seam + band, trim, 0)
    local clasp = math.max(2, math.floor(width * 0.22 + 0.5))
    local claspLeft = math.floor(left + (width - clasp) / 2)
    local claspBottom = seam + band + math.max(2, math.floor(height * 0.2))
    draw.Rect(claspLeft, seam - 1, claspLeft + clasp, claspBottom, trim, 1)
    draw.Outline(claspLeft, seam - 1, claspLeft + clasp, claspBottom, dark, 1)

    draw.Outline(left, top, left + width, top + height, dark, 2)
end

-- Draws whichever icons there are to show, beside the window being drawn: shown is the invitation
-- waiting, if any, and treasure whether there is something in the pool. corner is one of
-- notices.Corners' keys, offset { x, y } how far from there they are moved, and scale how many pixels
-- one of the frames' units is.
function notices.DrawIcons(shown, treasure, corner, offset, scale)
    local windowX, windowY = imgui.GetWindowPos()
    local display = imgui.GetIO().DisplaySize
    -- a list laid out off screen to be measured has no icons
    if windowX < 0 or windowY < 0 or windowX > display.x or windowY > display.y then
        return
    end

    -- beside the corner chosen, and from there as far as they have been moved: the first at the
    -- corner, the next beyond it, their feet on one line
    corner = corner or notices.Corners[1].key
    local onRight = corner == 'TopRight' or corner == 'BottomRight'
    local below = corner == 'BottomRight' or corner == 'BottomLeft'
    local windowWidth, windowHeight = imgui.GetWindowSize()
    local edge = (onRight and windowX + windowWidth or windowX) + (offset and tonumber(offset[1]) or 0) * scale
    local tallest = math.max(envelope.height, chest.height) * scale
    local foot = (below and windowY + windowHeight + gap * scale + tallest or windowY - gap * scale) + (offset and tonumber(offset[2]) or 0) * scale

    -- over every window where that can be done, and otherwise in the party's own, opened up to the
    -- whole screen
    local overAll = imgui.GetForegroundDrawList ~= nil
    local drawList = overAll and imgui.GetForegroundDrawList() or imgui.GetWindowDrawList()
    if not overAll then
        clipMax[1], clipMax[2] = display.x, display.y
        drawList:PushClipRect(clipMin, clipMax, false)
    end
    draw.Use(drawList)

    if shown ~= nil then
        local width, height = envelope.width * scale, envelope.height * scale
        local left = onRight and edge - width or edge
        DrawEnvelope(math.floor(left), math.floor(foot - height), width, height, shown)
        edge = onRight and left - spacing * scale or left + width + spacing * scale
    end
    if treasure then
        local width, height = chest.width * scale, chest.height * scale
        local left = onRight and edge - width or edge
        DrawChest(math.floor(left), math.floor(foot - height), math.floor(width), math.floor(height))
    end

    if not overAll then
        drawList:PopClipRect()
    end
end

return notices
