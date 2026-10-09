require('common')
local bit = require('bit')
local ffi = require('ffi')
local d3d8 = require('d3d8')
local d3d8_device = d3d8.get_device()
local imgui = require('imgui')
local ui = require('ui')

local ffxi = require('utils/ffxi')
local zones = require('utils/zones')

-- XivParty Style, an experimental setting: the lists arranged as the Windower addon XivParty's compact
-- layout arranges them, with its bars, in this addon's own windows
local xivparty = require('xivparty')

-- The pets, listed under the player's party in place of the pet tool's own window
local petTool = require('pet')

local Textures = { }
local Alliances = { }

-- notes on PartyMemberFlagMask
-- bit 0: ? maybe party 2?
-- bit 1: ?
-- bit 2: party leader
-- bit 3: alli leader
-- bit 4: ?
-- bit 5: ?
-- bit 6: ?
-- bit 7: level sync target

---@class PartyMember
---@field targetIndex      integer? entity index, from which entity is looked up each frame
---@field entity           table?
---@field name            string
---@field showCastbar      boolean
---@field serverId         integer
---@field isInZone         boolean
---@field isActive         boolean
---@field isPartyLeader    boolean
---@field isAllianceLeader boolean
---@field isSyncTarget     boolean
---@field isTarget         boolean
---@field isSubTarget      boolean
---@field isPartyTarget    boolean
---@field job              string
---@field sub              string?
---@field jobLevel         integer
---@field subLevel         integer
---@field zoneId           integer
---@field hpp              integer
---@field mpp              integer
---@field hp               integer
---@field mp               integer
---@field tp               integer
---@field windowName       string
---@field windowSize       integer[]
---@field windowPos        integer[]
---@field statusIds        integer[]

local function setAlpha(bitmap)
    -- the in-game bitmap data excludes the 14-byte BMP file header,
    -- and instead begins at the 40-byte DIB header. add 1 to account
    -- for lua's 1-based indexes
    local bmpStart = 40 + 1
    local bytes = bitmap:totable()

    -- each icon is 32x32 pixels and we're going to iterate over the
    -- bytes one pixel at a time (ie, 4 bytes). start at 0 since we're
    -- doing offset maths
    for i = 0, (32 * 32) - 1 do
        local pixelStart = i * 4
        local alpha = bytes[bmpStart + pixelStart + 3]

        -- any fully-transparent pixel should be banished to the colorkey realm
        if alpha < 0x01 then
            bytes[bmpStart + pixelStart + 0] = 0
            bytes[bmpStart + pixelStart + 1] = 0
            bytes[bmpStart + pixelStart + 2] = 0
        end
    end

    -- turn our bytes back into chars, and our chars into a string
    return bytes:map(string.char):join()
end

---@param statusId number
---@param icon userdata
local function CreateTexture(statusId, icon)
    if icon == nil then
        print('xilite error: no icon for status ' .. tostring(statusId))
        return 'missing'
    end

    -- Courtesy of Thorny's partybuffs
    local dx_texture_ptr = ffi.new('IDirect3DTexture8*[1]')
    if ffi.C.D3DXCreateTextureFromFileInMemoryEx(d3d8_device, setAlpha(icon.Bitmap), icon.ImageSize, 0xFFFFFFFF, 0xFFFFFFFF, 1, 0, ffi.C.D3DFMT_A8R8G8B8, ffi.C.D3DPOOL_MANAGED, ffi.C.D3DX_DEFAULT, ffi.C.D3DX_DEFAULT, 0xFF000000, nil, nil, dx_texture_ptr) == ffi.C.S_OK then
        return d3d8.gc_safe_release(ffi.cast('IDirect3DTexture8*', dx_texture_ptr[0]))
    else
        return 'missing'
    end
end

local ptrStatusIcons = AshitaCore:GetPointerManager():Get('party.statusicons')
local function GetBuffs2(party, serverId)
    local ptrPartyBuffs = ashita.memory.read_uint32(ptrStatusIcons)
    for memberIndex = 0, 4 do
        local memberPtr = ptrPartyBuffs + (0x30 * memberIndex)
        local playerId = ashita.memory.read_uint32(memberPtr)

        if playerId == serverId then
            local buffs = { }

            -- each byte of high bits serves four buffs, so it is read once for the four
            local highByte = 0
            for buffIndex = 0, 31 do
                local fMod = math.fmod(buffIndex, 4) * 2
                if fMod == 0 then
                    highByte = ashita.memory.read_uint8(memberPtr + 8 + (math.floor(buffIndex / 4)))
                end

                local lowBits = ashita.memory.read_uint8(memberPtr + 16 + buffIndex)
                local highBits = bit.lshift(bit.band(bit.rshift(highByte, fMod), 0x03), 8)
                local buff = highBits + lowBits

                if buff ~= 255 then
                    table.insert(buffs, buff)
                end
            end
            return buffs
        end
    end

    return { }
end

local function GetBuffs(party, serverId)
    -- courtesy of Thorny and Heals
    for i = 0, 4 do
        local sId = party:GetStatusIconsServerId(i)
        if sId == serverId then
            local icons_lo = party:GetStatusIcons(i)
            local icons_hi = party:GetStatusIconsBitMask(i)
            local effects = { }

            for b = 0, 31 do
                --[[ FIXME: lua doesn't handle 64bit return values properly..
                --   FIXME: the next lines are a workaround by Thorny that cover most but not all cases..
                --   FIXME: .. to try and retrieve the high bits of the buff id.
                --   TODO:  revesit this once atom0s adjusted the API.
                --]]
                local high_bits
                if b < 16 then
                    high_bits = bit.lshift(bit.band(bit.rshift(icons_hi, 2 * b), 3), 8)
                else
                    local buffer = math.floor(icons_hi / 0xffffffff)
                    high_bits = bit.lshift(bit.band(bit.rshift(buffer, 2 * (b - 16)), 3), 8)
                end

                local buff_id = icons_lo[b + 1] + high_bits
                if buff_id ~= 255 then
                    table.insert(effects, buff_id)
                end
             end

             return effects
        end
    end

    return { }
end

local function FilterBuffs(buffList)
    local buffs = {}

    for i, buff in ipairs(buffList) do
        if buff ~= nil and buff > 0 then
            table.insert(buffs, buff)
        end
    end

    return buffs
end

local function IsSubTargetActive(target)
    local flags = target:GetSubTargetFlags()
    if flags == 0xFFFFFFFF then
        return target:GetIsActive(1) == 1
    else
        return target:GetIsActive(0) == 1
    end
end

local function GetPlayer(options, target, party, stal)
    local player = AshitaCore:GetMemoryManager():GetPlayer()

    local serverId = party:GetMemberServerId(0)
    local buffs = FilterBuffs(player:GetBuffs())

    return {
        targetIndex = party:GetMemberTargetIndex(0),
        name = party:GetMemberName(0),
        isPlayer = true,
        showCastbar = options.showCastbar[1],
        serverId = serverId,
        isInZone = true,
        isActive = true,
        isPartyLeader = bit.band(party:GetMemberFlagMask(0), 4) == 4,
        isAllianceLeader = bit.band(party:GetMemberFlagMask(0), 8) == 8,
        isSyncTarget = bit.band(party:GetMemberFlagMask(0), 256) == 256,
        -- isQuartermaster = 144
        isTarget = (target:GetIsSubTargetActive() == 0 and serverId == target:GetServerId(0)) or (target:GetIsSubTargetActive() == 1 and serverId == target:GetServerId(1)),
        isSubTarget = target:GetIsSubTargetActive() == 1 and serverId == target:GetServerId(0),
        isPartyTarget = stal ~= nil and stal == 0,
        job = ffxi.GetJobAbbr(party:GetMemberMainJob(0)),
        sub = ffxi.GetJobAbbr(party:GetMemberSubJob(0)),
        jobLevel = party:GetMemberMainJobLevel(0),
        subLevel = party:GetMemberSubJobLevel(0),
        zoneId = party:GetMemberZone(0),
        hpp = party:GetMemberHPPercent(0),
        mpp = party:GetMemberMPPercent(0),
        hp = party:GetMemberHP(0),
        mp = party:GetMemberMP(0),
        tp = party:GetMemberTP(0),
        windowName = options.alliance1.name,
        windowSize = options.alliance1.size,
        windowPos = options.alliance1.pos,
        statusIds = buffs
    }
end

---@return PartyMember
local function GetMember(i, window, target, party, stal)
    local serverId = party:GetMemberServerId(i)
    local buffs = FilterBuffs(GetBuffs2(party, serverId))

    return {
        targetIndex = party:GetMemberTargetIndex(i),
        name = party:GetMemberName(i),
        showCastbar = false,
        serverId = serverId,
        isInZone = party:GetMemberZone(i) == party:GetMemberZone(0),
        isActive = party:GetMemberIsActive(i) == 1,
        isPartyLeader = bit.band(party:GetMemberFlagMask(i), 4) == 4,
        isAllianceLeader = bit.band(party:GetMemberFlagMask(i), 8) == 8,
        isSyncTarget = bit.band(party:GetMemberFlagMask(i), 256) == 256,
        isTarget = (target:GetIsSubTargetActive() == 0 and serverId == target:GetServerId(0)) or (target:GetIsSubTargetActive() == 1 and serverId == target:GetServerId(1)),
        isSubTarget = target:GetIsSubTargetActive() == 1 and serverId == target:GetServerId(0),
        isPartyTarget = stal ~= nil and stal == i,
        job = ffxi.GetJobAbbr(party:GetMemberMainJob(i)),
        sub = ffxi.GetJobAbbr(party:GetMemberSubJob(i)),
        jobLevel = party:GetMemberMainJobLevel(i),
        subLevel = party:GetMemberSubJobLevel(i),
        zoneId = party:GetMemberZone(i),
        hpp = party:GetMemberHPPercent(i),
        mpp = party:GetMemberMPPercent(i),
        hp = party:GetMemberHP(i),
        mp = party:GetMemberMP(i),
        tp = party:GetMemberTP(i),
        windowName = window.name,
        windowSize = window.size,
        windowPos = window.pos,
        statusIds = buffs
    }
end

local sampleJobs = { 'WAR', 'WHM', 'BLM', 'THF', 'RDM', 'BRD' }

-- A made-up party member for the sample windows, standing in for an empty slot
---@return PartyMember
local function GetSampleMember(slot, window)
    return {
        targetIndex = nil,
        name = ('Sample %d'):format(slot),
        showCastbar = false,
        serverId = 0,
        isInZone = true,
        isActive = true,
        isPartyLeader = slot == 1,
        isAllianceLeader = false,
        isSyncTarget = false,
        isTarget = false,
        isSubTarget = false,
        isPartyTarget = false,
        job = sampleJobs[slot] or 'WAR',
        sub = 'NIN',
        jobLevel = 75,
        subLevel = 37,
        zoneId = 0,
        hpp = 100 - (slot - 1) * 15,
        mpp = 100 - (slot - 1) * 12,
        hp = 1400 - (slot - 1) * 210,
        mp = 800 - (slot - 1) * 96,
        tp = (slot - 1) * 500,
        windowName = window.name,
        windowSize = window.size,
        windowPos = window.pos,
        statusIds = { 40, 41, 33 }, -- Protect, Shell, Haste
    }
end

---@param pos Vec2
---@param color Vec4
local function DrawDot(pos, color)
    local realColor = imgui.GetColorU32(color)
    imgui.GetWindowDrawList():AddCircleFilled(pos, 3, realColor, 0)
end

---@param player PartyMember
---@param showDist boolean
local function DrawName(player, showDist)
    -- the "party status dots" are intended to be a prefix to the player's name,
    -- so we want any target indicators to come beforehand.
    if player.isSubTarget or player.isPartyTarget then
        imgui.PushStyleColor(ImGuiCol_Text, ui.Colors.XpBar)
        imgui.Text('>')
        imgui.SameLine()
    elseif player.isTarget then
        imgui.PushStyleColor(ImGuiCol_Text, ui.Colors.Blue)
        imgui.Text('>>')
        imgui.SameLine()
    else
        imgui.PushStyleColor(ImGuiCol_Text, ui.Colors.White)
    end

    -- unfortunately, we can't draw circles inline (without using images, that
    -- is). instead, we have to manually place them on the screen, and manually
    -- offset the succeeding text.
    local originX, originY = imgui.GetCursorScreenPos()
    local offsetX = 0

    if player.isAllianceLeader then
        DrawDot({originX + offsetX + 3, originY + 6}, ui.Colors.Blue)
        offsetX = offsetX + 6
    end

    if player.isPartyLeader then
        DrawDot({originX + offsetX + 3, originY + 6}, ui.Colors.FfxiAmber)
        offsetX = offsetX + 6
    end

    if player.isSyncTarget then
        DrawDot({originX + offsetX + 3, originY + 6}, ui.Colors.Red)
        offsetX = offsetX + 6
    end

    local windowX = imgui.GetCursorPosX()
    imgui.SetCursorPosX(windowX + offsetX)

    imgui.Text(player.name)
    imgui.PopStyleColor()

    -- we can use the top right corner for more cool stuff, but imgui doesn't do
    -- right-alignment (as far as i'm aware). again, we must do it ourselves:
    -- calculate the width of our displayed item, and offset it from the width
    -- of the window. this probably won't work with a dynamically-sized window.
    local castbar = AshitaCore:GetMemoryManager():GetCastBar()
    if player.showCastbar and castbar:GetCount() ~= 0 then
        imgui.SameLine()
        imgui.SetCursorPosX(ui.PaddedWidth(player.windowSize[1]) - (80 + ui.Styles.WindowPadding[1]))
        ui.DrawBar2(castbar:GetPercent() * 100, 100, { 80, 8 }, '')
    elseif showDist and player.entity then
        local dist = string.format('%.1fm', math.sqrt(player.entity.Distance))
        local width = imgui.CalcTextSize(dist) + ui.Styles.WindowPadding[1]

        imgui.SameLine()
        imgui.SetCursorPosX(ui.PaddedWidth(player.windowSize[1]) - width)
        imgui.Text(dist)
    elseif player.job ~= nil then
        local jobStr = ''
        if player.sub ~= nil then
            jobStr = string.format('%s%i/%s%i', player.job, player.jobLevel, player.sub, player.subLevel)
        else
            jobStr = string.format('%s%i', player.job, player.jobLevel)
        end

        local width = imgui.CalcTextSize(jobStr) + ui.Styles.WindowPadding[1]

        imgui.SameLine()
        imgui.SetCursorPosX(ui.PaddedWidth(player.windowSize[1]) - width)
        imgui.Text(jobStr)
    end
end

---@param player PartyMember
local function DrawZone(player)
    local zone = zones[player.zoneId] or string.format('??? ZONEID %s', tostring(player.zoneId))
    imgui.TextDisabled(zone)
end

---@param player PartyMember
local function DrawHp(player)
    local textColor = ui.Colors.White
    local barColor = ui.Colors.HpBar
    local overlay = string.format('%i', player.hp)

    imgui.PushStyleColor(ImGuiCol_Text, textColor)
    imgui.PushStyleColor(ImGuiCol_PlotHistogram, barColor)
    ui.DrawBar3(player.hpp, 100, ui.Styles.ShortBarSize, overlay)
    imgui.PopStyleColor(2)
end

---@param player PartyMember
local function DrawMp(player)
    local textColor = ui.Colors.White
    local barColor = ui.Colors.MpBar
    local overlay = string.format('%i', player.mp)

    imgui.PushStyleColor(ImGuiCol_Text, textColor)
    imgui.PushStyleColor(ImGuiCol_PlotHistogram, barColor)
    imgui.SameLine()
    ui.DrawBar2(player.mpp, 100, ui.Styles.ShortBarSize, overlay)
    imgui.PopStyleColor(2)
end

---@param player PartyMember
local function DrawTp(player)
    local textColor = ui.Colors.White
    local barColor = ui.TpBarColor(player.tp, player.isPlayer)
    local overlay = string.format('%i', player.tp)

    imgui.PushStyleColor(ImGuiCol_Text, textColor)
    imgui.PushStyleColor(ImGuiCol_PlotHistogram, barColor)
    imgui.SameLine()
    ui.DrawBar2(player.tp, 3000, ui.Styles.ShortBarSize, overlay)
    imgui.PopStyleColor(2)
end

---@param player PartyMember
local function DrawBuffs(player)
    imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, { 2, 2 })
    imgui.NewLine()

    for _, buffId in ipairs(player.statusIds) do
        if Textures[buffId] == nil then
            local icon = AshitaCore:GetResourceManager():GetStatusIconByIndex(buffId)
            Textures[buffId] = CreateTexture(buffId, icon)
        end

        local buffIcon = Textures[buffId]
        if buffIcon ~= 'missing' then
            imgui.SameLine()
            local img = tonumber(ffi.cast("uint32_t", buffIcon))
            imgui.Image(img, { ui.Styles.ShortBarSize[2], ui.Styles.ShortBarSize[2] })
        end
    end

    imgui.PopStyleVar()
end

-- A status icon's texture as the number imgui takes, or nil where the game has no icon for it. For
-- XivParty Style, which places the icons itself.
local textureHandles = { }

local function StatusTexture(buffId)
    local handle = textureHandles[buffId]
    if handle == nil then
        if Textures[buffId] == nil then
            local icon = AshitaCore:GetResourceManager():GetStatusIconByIndex(buffId)
            Textures[buffId] = CreateTexture(buffId, icon)
        end
        local texture = Textures[buffId]
        handle = texture ~= 'missing' and tonumber(ffi.cast("uint32_t", texture)) or false
        textureHandles[buffId] = handle
    end
    return handle or nil
end

-- The settings of the party windows as a whole, kept when they are loaded: how the lists are drawn is
-- asked for each list, every frame
local usOptions = nil

local function XivPartyStyle()
    return usOptions ~= nil and usOptions.xivParty ~= nil and usOptions.xivParty[1] == true
end

-- How XivParty Style is to draw, from the settings, as xivparty.Draw takes it: one table, filled in
-- afresh for each list
local xivSettings = { }

local function XivSettings()
    local options, settings = usOptions, xivSettings
    settings.scale = options.xivScale ~= nil and options.xivScale[1] or 100
    settings.valueSize = options.xivValueSize ~= nil and options.xivValueSize[1] or 100
    settings.nameSize = options.xivNameSize ~= nil and options.xivNameSize[1] or 100
    settings.buffSize = options.xivBuffSize ~= nil and options.xivBuffSize[1] or 100
    settings.hpOffset, settings.mpOffset, settings.tpOffset = options.xivHpOffset, options.xivMpOffset, options.xivTpOffset
    settings.showMp = options.xivShowMp == nil or options.xivShowMp[1]
    settings.showTp = options.xivShowTp == nil or options.xivShowTp[1]
    return settings
end

-- Whether the pets are listed under the player's party: the setting is on, and so is the pet tool
local function PetsInList()
    return usOptions ~= nil and (usOptions.showPets == nil or usOptions.showPets[1]) and petTool.IsEnabled()
end

-- A pet as a line of XivParty Style: its HP as a percentage unless the figure itself is known, and
-- MP and TP for the player's own alone
local function PetLine(info)
    return {
        name = info.name, serverId = info.name, isInZone = true,
        hp = info.hp, hpp = info.hpp, hpText = info.hp == nil and ('%d%%'):format(info.hpp) or nil,
        mp = info.mp, mpp = info.mpp, mpText = (info.mpp ~= nil and info.mp == nil) and ('%d%%'):format(info.mpp) or nil,
        tp = info.tp,
    }
end

---@param player PartyMember
---@param showDist boolean
local function DrawPartyMember(player, showDist)
    DrawName(player, showDist)

    if player.isInZone then
        DrawHp(player)
        DrawMp(player)
        DrawTp(player)
        DrawBuffs(player)
    else
        DrawZone(player)
    end
end

-- In the compact view TP is a figure, not a bar, and it goes outside the window: to the left of the
-- member it belongs to, on their line, in the colour their TP bar would be. y is the top of that line
-- on screen.
local compactTpGap = 6 -- between the figure and the window's edge
local compactTpShadow = { 0, 0, 0, 1 }
local compactTpPos = { 0, 0 }
local compactTpClipMin, compactTpClipMax = { 0, 0 }, { 0, 0 }

---@param player PartyMember
---@param y number
local function DrawCompactTp(player, y)
    local text = string.format('%i', player.tp)
    local windowX = imgui.GetWindowPos()
    local width, height = imgui.CalcTextSize(text)
    local x = windowX - compactTpGap - width

    -- Only what is on screen is drawn, and the space opened for it never reaches past the screen's
    -- edge. A list that grows upwards is first laid out far off screen to measure it, and a figure
    -- drawn out there, in a space of its own making, came out huge in the middle of the screen.
    local display = imgui.GetIO().DisplaySize
    local left, top = math.max(0, x - 1), math.max(0, y - 1)
    local right, bottom = math.min(display.x, windowX), math.min(display.y, y + height + 2)
    if right <= left or bottom <= top then
        return
    end

    -- the window's own list, so the figure sits with the window among the others and fades with it,
    -- opened up to take in the space beside the window
    local drawList = imgui.GetWindowDrawList()
    compactTpClipMin[1], compactTpClipMin[2] = left, top
    compactTpClipMax[1], compactTpClipMax[2] = right, bottom
    drawList:PushClipRect(compactTpClipMin, compactTpClipMax, false)

    -- with nothing behind it but the game, a dark copy a pixel down and across keeps it readable
    compactTpPos[1], compactTpPos[2] = x + 1, y + 1
    drawList:AddText(compactTpPos, imgui.GetColorU32(compactTpShadow), text)
    compactTpPos[1], compactTpPos[2] = x, y
    drawList:AddText(compactTpPos, imgui.GetColorU32(ui.TpBarColor(player.tp, player.isPlayer)), text)

    drawList:PopClipRect()
end

-- A member on one line: the start of their name, then their HP and MP bars, with their TP to the
-- left of the window
---@param player PartyMember
local function DrawCompactPartyMember(player)
    local _, lineY = imgui.GetCursorScreenPos()

    -- There is no room for the full view's arrows, so the member the cursor is on has their name in
    -- the arrows' colours instead: green under the party cursor or a sub-target, blue as the target
    local color = nil
    if player.isSubTarget or player.isPartyTarget then
        color = ui.Colors.XpBar
    elseif player.isTarget then
        color = ui.Colors.Blue
    end

    if color ~= nil then
        imgui.TextColored(color, player.name:slice(0, 3))
    elseif player.isInZone then
        imgui.Text(player.name:slice(0, 3))
    else
        imgui.TextDisabled(player.name:slice(0, 3))
    end

    if player.isInZone then
        imgui.SameLine()
        DrawHp(player)
        DrawMp(player)
        DrawCompactTp(player, lineY)
    end
end

-- The order members are listed in when sorting by role: tanks, then damage dealers (melee before
-- ranged), then support, then mages, then healers. The player always comes first, and a member whose
-- job is not known comes last.
local roleOrder = {
    'PLD', 'NIN', 'WAR', 'RUN',                                      -- tanks
    'MNK', 'SAM', 'DRK', 'DRG', 'THF', 'DNC', 'BLU', 'BST', 'PUP',   -- melee damage
    'RNG',                                                           -- ranged damage
    'BRD', 'COR', 'GEO',                                             -- support
    'BLM', 'SMN', 'SCH',                                             -- mages
    'RDM', 'WHM',                                                    -- healers
}

local roleRank = { }
for rank, job in ipairs(roleOrder) do
    roleRank[job] = rank
end
local unknownRank = #roleOrder + 1

-- Sorts members by role. Members with the same job keep their party order.
---@param members PartyMember[]
local function SortByRole(members)
    for order, member in ipairs(members) do
        member.sortRank = member.isPlayer and 0 or roleRank[member.job] or unknownRank
        member.sortOrder = order
    end

    table.sort(members, function(a, b)
        if a.sortRank ~= b.sortRank then
            return a.sortRank < b.sortRank
        end
        return a.sortOrder < b.sortOrder
    end)
end

-- Reading a member means a couple of dozen memory calls and a search for their buffs, so the members of
-- each window are read at most this often and the same list is drawn in between. Fast enough that HP,
-- buffs and the target marker do not visibly lag.
local memberRefreshInterval = 0.1
local memberCache = { } -- window name -> { time, sample, sortByRole, members }

-- The members to list in an alliance window, in the order to list them.
-- With sample set, every empty slot is filled with a made-up member, so the window shows at its full size.
-- With sortByRole set, the members are listed by role rather than in party order.
---@return PartyMember[]
local function GetMembers(alliance, sample, sortByRole, target, party, stal)
    local now = os.clock()
    local cached = memberCache[alliance.name]
    if cached ~= nil
    and cached.sample == sample
    and cached.sortByRole == sortByRole
    and now - cached.time < memberRefreshInterval then
        return cached.members
    end

    local members = { }
    for slot, getMember in ipairs(Alliances[alliance.name]) do
        local person = getMember(target, party, stal)
        if sample and not (person.isActive and person.name ~= '') then
            person = GetSampleMember(slot, alliance)
        end

        -- While arranging, the corner of every member shows their job, never a cast bar or a distance
        if sample then
            person.showCastbar = false
        end

        if person.isActive and person.name ~= '' then
            table.insert(members, person)
        end
    end

    if sortByRole then
        SortByRole(members)
    end

    memberCache[alliance.name] = { time = now, sample = sample, sortByRole = sortByRole, members = members }
    return members
end

-- growsUp is set for the player's own party: its compact list, and its list in XivParty Style, keeps
-- its bottom edge where it is and grows upwards as members join, where every other list grows downwards
local function DrawAlliance(alliance, gOptions, sample, sortByRole, growsUp)
    sample = sample and true or false
    sortByRole = sortByRole and true or false
    local xivStyle = XivPartyStyle()
    local growFrom = (growsUp and (xivStyle or alliance.isCompact[1])) and 'BottomLeft' or nil

    -- the pets go under the player's own party, and the pet tool then leaves its own window out
    local pets = nil
    if growsUp and PetsInList() then
        petTool.inPartyList = true
        pets = petTool.List(sample)
    end

    ui.DrawUiWindow(alliance, gOptions, function()
        local target = AshitaCore:GetMemoryManager():GetTarget()
        local party = AshitaCore:GetMemoryManager():GetParty()
        local stal = ffxi.GetStPartyIndex()
        -- Distances are for choosing a sub-target. The party cursor on its own (stal) is also what the
        -- game's menus move over the list, as when rearranging the party, and jobs stay up for that.
        local showDist = IsSubTargetActive(target)

        local members = GetMembers(alliance, sample, sortByRole, target, party, stal)

        for _, person in ipairs(members) do
            -- The member list is kept between frames but an entity must not be: it is looked up
            -- afresh for each frame it is drawn in, in case it has gone since the list was read
            local entity = person.targetIndex and GetEntity(person.targetIndex) or nil
            -- and it must be the member's own: one in another zone, or whose place has been taken, would
            -- give the distance to whatever has that index here
            if entity ~= nil and (not person.isInZone or entity.ServerId ~= person.serverId) then
                entity = nil
            end
            person.entity = entity

            if xivStyle then
                -- drawn together, below
            elseif alliance.isCompact[1] then
                DrawCompactPartyMember(person)
            else
                DrawPartyMember(person, showDist and not sample)
            end
        end

        -- the player's own party has its buffs beside it
        if xivStyle then
            xivparty.Draw(members, growsUp and 'party' or 'alliance', StatusTexture, XivSettings())
        end

        -- the pets, under a line, each in the manner of the list above
        if pets ~= nil and #pets > 0 then
            imgui.Separator()
            if xivStyle then
                local lines = { }
                for index, info in ipairs(pets) do
                    lines[index] = PetLine(info)
                end
                xivparty.Draw(lines, 'pets', nil, XivSettings())
            else
                for _, info in ipairs(pets) do
                    if alliance.isCompact[1] then
                        local _, lineY = imgui.GetCursorScreenPos()
                        petTool.DrawCompact(info)
                        if info.tp ~= nil then
                            DrawCompactTp(info, lineY)
                        end
                    else
                        petTool.Draw(info, alliance)
                    end
                end
            end
        end
    end, nil, growFrom, xivStyle)
end

local function SortsByRole(options)
    return options.sortByRole ~= nil and options.sortByRole[1]
end

local function UpdateAlliances(options)
    usOptions = options
    memberCache = { }
    Alliances['xilite.us.1'] = {
        GetPlayer:bindn(options),
        GetMember:bindn(1, options.alliance1),
        GetMember:bindn(2, options.alliance1),
        GetMember:bindn(3, options.alliance1),
        GetMember:bindn(4, options.alliance1),
        GetMember:bindn(5, options.alliance1),
    }
    Alliances['xilite.us.2'] = {
        GetMember:bindn(6, options.alliance2),
        GetMember:bindn(7, options.alliance2),
        GetMember:bindn(8, options.alliance2),
        GetMember:bindn(9, options.alliance2),
        GetMember:bindn(10, options.alliance2),
        GetMember:bindn(11, options.alliance2),
    }
    Alliances['xilite.us.3'] = {
        GetMember:bindn(12, options.alliance3),
        GetMember:bindn(13, options.alliance3),
        GetMember:bindn(14, options.alliance3),
        GetMember:bindn(15, options.alliance3),
        GetMember:bindn(16, options.alliance3),
        GetMember:bindn(17, options.alliance3),
    }
end

-- The sliders that move the HP, MP and TP values in XivParty Style: two for each, across and down
local xivOffsetReach = 40        -- how far either way, in the list's own units
local xivOffsetSliderWidth = 130
local xivOffsetBox = { 0 }       -- a number on its way in and out of a slider
local xivOffsetControls = { }
for _, name in ipairs({ 'HP', 'MP', 'TP' }) do
    table.insert(xivOffsetControls, {
        key = ('xiv%s%sOffset'):format(name:sub(1, 1), name:sub(2):lower()),
        label = ('%s Value Offset'):format(name),
        ids = { ('##us.xiv%sOffsetX'):format(name), ('##us.xiv%sOffsetY'):format(name) },
        tooltip = ('Moves the %s value from its usual place: X to the right, Y down. Less than 0 moves it left or up.\nThe numbers are in the list\'s own units, so the value keeps its place as the scale changes.'):format(name),
    })
end

---@type xitool
local us = {
    Name = 'us',
    DefaultSettings = T{
        isEnabled = T{ true },
        isVisible = T{ true },
        hideWhenSolo = T{ false },
        sortByRole = T{ false },
        showCastbar = T{ true },
        showPets = T{ true },  -- list the pets under the party, in place of the pet tool's own window
        xivParty = T{ false }, -- experimental: arrange the lists as the Windower addon XivParty's compact layout does
        xivScale = T{ 100 },   -- their size, as a percentage
        xivValueSize = T{ 100 }, -- the size of the HP, MP and TP figures, as a percentage
        xivNameSize = T{ 100 },  -- and of the names
        xivBuffSize = T{ 100 },  -- and of the buff icons
        xivHpOffset = T{ 0, 0 }, -- how far the HP figure is moved from its place: right, down
        xivMpOffset = T{ 0, 0 }, -- and the MP figure
        xivTpOffset = T{ 0, 0 }, -- and the TP figure
        xivShowMp = T{ true }, -- whether the MP figure is written beside its bar
        xivShowTp = T{ true }, -- whether TP is written
        alliance1 = T{
            isCompact = T{ false },
            isVisible = T{ true },
            name = 'xilite.us.1',
            fullSize = T{ 276, -1 },
            compactSize = T{ -1, -1 },
            size = T{ 276, -1 },
            pos = T{ 392, 628 },
            flags = bit.bor(ImGuiWindowFlags_NoDecoration),
        },
        alliance2 = T{
            isCompact = T{ false },
            isVisible = T{ true },
            name = 'xilite.us.2',
            fullSize = T{ 276, -1 },
            compactSize = T{ -1, -1 },
            size = T{ 276, -1 },
            pos = T{ 107, 628 },
            flags = bit.bor(ImGuiWindowFlags_NoDecoration),
        },
        alliance3 = T{
            isCompact = T{ false },
            isVisible = T{ true },
            name = 'xilite.us.3',
            fullSize = T{ 276, -1 },
            compactSize = T{ -1, -1 },
            size = T{ 276, -1 },
            pos = T{ 000, 628 },
            flags = bit.bor(ImGuiWindowFlags_NoDecoration),
        },
    },
    UpdateSettings = UpdateAlliances,
    Load = UpdateAlliances,
    DrawConfig = function(options, gOptions)
        if imgui.BeginTabItem('us') then
            ui.BeginLabels('xilite.us')
            ui.Label('Enabled')
            imgui.Checkbox('##us.1', options.isEnabled)

            ui.Gap()
            ui.Label('Hide When Solo')
            imgui.Checkbox('##us.2', options.hideWhenSolo)

            -- Settings saved before this option existed have no value for it
            if options.sortByRole == nil then
                options.sortByRole = T{ false }
            end
            ui.Label('Sort By Role')
            imgui.Checkbox('##us.3', options.sortByRole)
            if imgui.IsItemHovered() then
                imgui.SetTooltip('Off lists members in the game\'s own party order.\nOn lists you first, then tanks (PLD, NIN, WAR, RUN), melee damage (MNK, SAM, DRK, DRG, THF, DNC, BLU, BST, PUP),\nranged damage (RNG), support (BRD, COR, GEO), mages (BLM, SMN, SCH) and healers (RDM, WHM).\nEach party of the alliance is sorted on its own.')
            end
            ui.Label('Display Cast Bar')
            imgui.Checkbox('##us.4', options.showCastbar)

            -- Settings saved before this option existed have no value for it
            if options.showPets == nil then
                options.showPets = T{ true }
            end
            ui.Label('Show Pets In Party List')
            imgui.Checkbox('##us.showPets', options.showPets)
            if imgui.IsItemHovered() then
                imgui.SetTooltip('Lists the pets under your party, below a line, in place of the pet window.\nWhich pets are listed, and whether pets are shown at all, is still set on the pet tab.\nWhile the party window is not showing, the pet window shows as usual.')
            end

            -- Settings saved before these options existed have no value for them
            if options.xivParty == nil then
                options.xivParty = T{ false }
            end
            if options.xivScale == nil or options.xivScale[1] < 50 then
                options.xivScale = T{ 100 }
            end
            if options.xivShowMp == nil then
                options.xivShowMp = T{ true }
            end
            if options.xivValueSize == nil then
                options.xivValueSize = T{ 100 }
            end
            if options.xivNameSize == nil then
                options.xivNameSize = T{ 100 }
            end
            if options.xivBuffSize == nil then
                options.xivBuffSize = T{ 100 }
            end
            for _, key in ipairs({ 'xivHpOffset', 'xivMpOffset', 'xivTpOffset' }) do
                if type(options[key]) ~= 'table' then
                    options[key] = T{ 0, 0 }
                end
            end
            if options.xivShowTp == nil then
                options.xivShowTp = T{ true }
            end
            usOptions = options
            ui.Label('XivParty Style', true)
            imgui.Checkbox('##us.xivParty', options.xivParty)
            if imgui.IsItemHovered() then
                imgui.SetTooltip('Arranges the party lists the way the Windower addon XivParty\'s compact layout does, with its bars: a line a member with the name, an HP bar and a smaller MP bar with their values, TP as a value, and buffs running leftwards from your own party\'s window.\nThe window is the theme\'s. The compact options and the cast bar do not apply to lists drawn this way.')
            end
            if options.xivParty[1] then
                ui.Label('XivParty Scale (%)')
                imgui.SliderInt('##us.xivScale', options.xivScale, 50, 200, '%d%%')
                if imgui.IsItemHovered() then
                    imgui.SetTooltip('How big the lists are drawn: the bars, the text and the buffs together.')
                end
                ui.Label('Name Text Size (%)')
                imgui.SliderInt('##us.xivNameSize', options.xivNameSize, 50, 200, '%d%%')
                if imgui.IsItemHovered() then
                    imgui.SetTooltip('How big the names are written, apart from everything else.')
                end
                ui.Label('Buff Icon Size (%)')
                imgui.SliderInt('##us.xivBuffSize', options.xivBuffSize, 50, 200, '%d%%')
                if imgui.IsItemHovered() then
                    imgui.SetTooltip('How big the buff and debuff icons beside your party are drawn, apart from everything else.')
                end
                ui.Label('Value Text Size (%)')
                imgui.SliderInt('##us.xivValueSize', options.xivValueSize, 50, 200, '%d%%')
                if imgui.IsItemHovered() then
                    imgui.SetTooltip('How big the HP, MP and TP values are written, apart from everything else.')
                end
                -- each value's place: a slider across and a slider down, side by side
                for _, value in ipairs(xivOffsetControls) do
                    local offset = options[value.key]
                    ui.Label(value.label)
                    for axis = 1, 2 do
                        if axis == 2 then
                            imgui.SameLine()
                        end
                        xivOffsetBox[1] = tonumber(offset[axis]) or 0
                        imgui.PushItemWidth(xivOffsetSliderWidth)
                        if imgui.SliderInt(value.ids[axis], xivOffsetBox, -xivOffsetReach, xivOffsetReach, axis == 1 and 'X %d' or 'Y %d') then
                            offset[axis] = xivOffsetBox[1]
                        end
                        imgui.PopItemWidth()
                        if imgui.IsItemHovered() then
                            imgui.SetTooltip(value.tooltip)
                        end
                    end
                end
                ui.Label('Show MP Values')
                imgui.Checkbox('##us.xivShowMp', options.xivShowMp)
                if imgui.IsItemHovered() then
                    imgui.SetTooltip('Writes each member\'s MP beside their MP bar. Off leaves the bar alone.')
                end
                ui.Label('Show TP Values')
                imgui.Checkbox('##us.xivShowTp', options.xivShowTp)
                if imgui.IsItemHovered() then
                    imgui.SetTooltip('Writes each member\'s TP on their line. TP has no bar in this style, so off leaves TP out altogether.')
                end
            end

            ui.Label('Compact Alliance 1', true)
            if imgui.Checkbox('##us.5', options.alliance1.isCompact) then
                if options.alliance1.isCompact[1] then
                    options.alliance1.size = options.alliance1.compactSize
                else
                    options.alliance1.size = options.alliance1.fullSize
                end
            end
            ui.Label('Compact Alliance 2', true)
            if imgui.Checkbox('##us.6', options.alliance2.isCompact) then
                if options.alliance2.isCompact[1] then
                    options.alliance2.size = options.alliance2.compactSize
                else
                    options.alliance2.size = options.alliance2.fullSize
                end
            end
            ui.Label('Compact Alliance 3', true)
            if imgui.Checkbox('##us.7', options.alliance3.isCompact) then
                if options.alliance3.isCompact[1] then
                    options.alliance3.size = options.alliance3.compactSize
                else
                    options.alliance3.size = options.alliance3.fullSize
                end
            end

            ui.Gap()
            ui.Label('Alliance 1 Position')
            if imgui.InputInt2('##us.8', options.alliance1.pos) then
                imgui.SetWindowPos(options.alliance1.name, options.alliance1.pos)
                ui.ForgetCorner(options.alliance1)
            end
            ui.Label('Alliance 2 Position')
            if imgui.InputInt2('##us.9', options.alliance2.pos) then
                imgui.SetWindowPos(options.alliance2.name, options.alliance2.pos)
            end
            ui.Label('Alliance 3 Position')
            if imgui.InputInt2('##us.10', options.alliance3.pos) then
                imgui.SetWindowPos(options.alliance3.name, options.alliance3.pos)
            end

            imgui.EndTabItem()
        end
    end,
    DrawMain = function(options, gOptions)
        local party = AshitaCore:GetMemoryManager():GetParty()
        local alliCount1 = party:GetAlliancePartyMemberCount1()
        local alliCount2 = party:GetAlliancePartyMemberCount2()
        local alliCount3 = party:GetAlliancePartyMemberCount3()

        if (options.hideWhenSolo[1] and alliCount1 > 1)
        or (not options.hideWhenSolo[1] and alliCount1 > 0) then
            DrawAlliance(options.alliance1, gOptions, false, SortsByRole(options), true)
        end
        if alliCount2 > 0 then
            DrawAlliance(options.alliance2, gOptions, false, SortsByRole(options))
        end
        if alliCount3 > 0 then
            DrawAlliance(options.alliance3, gOptions, false, SortsByRole(options))
        end
    end,
    DrawSample = function(options, gOptions)
        DrawAlliance(options.alliance1, gOptions, true, SortsByRole(options), true)
        DrawAlliance(options.alliance2, gOptions, true, SortsByRole(options))
        DrawAlliance(options.alliance3, gOptions, true, SortsByRole(options))
    end,
}

return us
