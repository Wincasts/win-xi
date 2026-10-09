require('common')
local bit = require('bit')
local ffi = require('ffi')
local d3d8 = require('d3d8')
local d3d8_device = d3d8.get_device()
local imgui = require('imgui')
local ui = require('ui')

local ffxi = require('utils/ffxi')

-- The lists are arranged as the Windower addon XivParty's compact layout arranges them, with its bars,
-- in this addon's own windows
local xivparty = require('xivparty')

-- The pets, listed under the player's party
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
---@field name             string
---@field isPlayer         boolean? the player themself
---@field serverId         integer
---@field isInZone         boolean
---@field isActive         boolean
---@field isPartyLeader    boolean
---@field isAllianceLeader boolean
---@field isTarget         boolean
---@field isSubTarget      boolean
---@field isPartyTarget    boolean
---@field job              string
---@field zoneId           integer
---@field hpp              integer
---@field mpp              integer
---@field hp               integer
---@field mp               integer
---@field noMp             boolean  the most MP they can have is none
---@field tp               integer
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
        print('xiframes error: no icon for status ' .. tostring(statusId))
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

-- Empties a list, to be filled again
local function Clear(list)
    for index = #list, 1, -1 do
        list[index] = nil
    end
end

-- The buffs of another member of the player's own party, read into buffs. The game keeps them for
-- the five other members of that party, and for nobody in the other two.
local function ReadMemberBuffs(buffs, serverId)
    local ptrPartyBuffs = ashita.memory.read_uint32(ptrStatusIcons)
    for memberIndex = 0, 4 do
        local memberPtr = ptrPartyBuffs + (0x30 * memberIndex)
        local playerId = ashita.memory.read_uint32(memberPtr)

        if playerId == serverId then
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

                if buff ~= 255 and buff > 0 then
                    buffs[#buffs + 1] = buff
                end
            end
            return
        end
    end
end

-- The player's own buffs, read into buffs
local function ReadOwnBuffs(buffs)
    for _, buff in ipairs(AshitaCore:GetMemoryManager():GetPlayer():GetBuffs()) do
        if buff ~= nil and buff > 0 then
            buffs[#buffs + 1] = buff
        end
    end
end

-- Whether the most MP a member can have is none. The game tells the player their own, and for anyone
-- else only how much they have now and what part of their most that is, which for a member at 0 MP
-- says nothing: none of none and none of a thousand look alike. So for the others it is worked out:
-- anyone seen with MP has MP for as long as they keep their jobs, and of those never seen with any,
-- those whose job or sub job is one that has MP are taken to have run out, and the rest to have none.
local mpJobs = { [3] = true, [4] = true, [5] = true, [7] = true, [8] = true, [15] = true, [16] = true, [20] = true, [21] = true, [22] = true } -- WHM BLM RDM PLD DRK SMN BLU SCH GEO RUN
local seenWithMp = { } -- server id -> the jobs they had when last seen with MP: main * 100 + sub

local function HasNoMp(place, party, serverId, mp, mpp)
    if place == 0 then
        return AshitaCore:GetMemoryManager():GetPlayer():GetMPMax() == 0
    end

    local main, sub = party:GetMemberMainJob(place), party:GetMemberSubJob(place)
    local jobs = main * 100 + sub
    if mp > 0 or mpp > 0 then
        seenWithMp[serverId] = jobs
        return false
    end
    if seenWithMp[serverId] == jobs then
        return false
    end
    return not (mpJobs[main] or mpJobs[sub])
end

-- A member is read into a table kept for their place in the alliance (0 is the player, 1 to 5 the
-- rest of their party, 6 to 17 the other two), the same table each time: members are read ten times
-- a second, and a new table for each of eighteen every time is a good deal to throw away.
local places = { }

-- What is the same for every member read in one go: who is targeted
local targeted = { subActive = false, first = 0, second = 0 }

local function ReadTargets(target)
    targeted.subActive = target:GetIsSubTargetActive() == 1
    targeted.first = target:GetServerId(0)
    targeted.second = targeted.subActive and target:GetServerId(1) or 0
end

---@return PartyMember
local function ReadMember(place, party, stal)
    local member = places[place]
    if member == nil then
        member = { statusIds = { }, isPlayer = place == 0 }
        places[place] = member
    end

    local serverId = party:GetMemberServerId(place)
    local zone = party:GetMemberZone(place)
    local flags = party:GetMemberFlagMask(place)

    member.targetIndex = party:GetMemberTargetIndex(place)
    member.name = party:GetMemberName(place)
    member.serverId = serverId
    member.isInZone = place == 0 or zone == party:GetMemberZone(0)
    member.isActive = place == 0 or party:GetMemberIsActive(place) == 1
    member.isPartyLeader = bit.band(flags, 4) == 4
    member.isAllianceLeader = bit.band(flags, 8) == 8
    -- with a sub-target out, the game holds it first and the target second
    if targeted.subActive then
        member.isTarget = serverId == targeted.second
        member.isSubTarget = serverId == targeted.first
    else
        member.isTarget = serverId == targeted.first
        member.isSubTarget = false
    end
    member.isPartyTarget = stal ~= nil and stal == place
    member.job = ffxi.GetJobAbbr(party:GetMemberMainJob(place))
    member.zoneId = zone
    member.hpp = party:GetMemberHPPercent(place)
    member.mpp = party:GetMemberMPPercent(place)
    member.hp = party:GetMemberHP(place)
    member.mp = party:GetMemberMP(place)
    member.tp = party:GetMemberTP(place)
    member.noMp = HasNoMp(place, party, serverId, member.mp, member.mpp)
    member.entity = nil

    -- buffs are shown for the player's own party alone
    local buffs = member.statusIds
    Clear(buffs)
    if place == 0 then
        ReadOwnBuffs(buffs)
    elseif place <= 5 then
        ReadMemberBuffs(buffs, serverId)
    end

    return member
end

local sampleJobs = { 'WAR', 'WHM', 'BLM', 'THF', 'RDM', 'BRD' }

-- A made-up party member for the sample windows, standing in for an empty slot
---@return PartyMember
local function GetSampleMember(slot, place)
    return {
        targetIndex = nil,
        name = ('Sample %d'):format(slot),
        serverId = 0,
        isInZone = true,
        isActive = true,
        isPartyLeader = slot == 1,
        isAllianceLeader = place == 6, -- the second party's leader leads the alliance, to show the mark
        isTarget = false,
        isSubTarget = false,
        isPartyTarget = false,
        job = sampleJobs[slot] or 'WAR',
        zoneId = 0,
        hpp = 100 - (slot - 1) * 15,
        mpp = 100 - (slot - 1) * 12,
        hp = 1400 - (slot - 1) * 210,
        mp = 800 - (slot - 1) * 96,
        tp = (slot - 1) * 500,
        noMp = slot == 4, -- the thief: a grey MP bar
        statusIds = { 40, 41, 33 }, -- Protect, Shell, Haste
    }
end

-- A status icon's texture as the number imgui takes, or nil where the game has no icon for it
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

-- How the lists are to be drawn, from the settings, as xivparty.Draw takes it: one table, filled in
-- afresh for each list
local styleSettings = { }

local function StyleSettings()
    local options, settings = usOptions, styleSettings
    settings.scale = options.xivScale ~= nil and options.xivScale[1] or 100
    settings.valueSize = options.xivValueSize ~= nil and options.xivValueSize[1] or 100
    settings.nameSize = options.xivNameSize ~= nil and options.xivNameSize[1] or 100
    settings.buffSize = options.xivBuffSize ~= nil and options.xivBuffSize[1] or 100
    settings.buffDistance = options.xivBuffDistance ~= nil and options.xivBuffDistance[1] or 0
    settings.buffSpacing = options.xivBuffSpacing ~= nil and options.xivBuffSpacing[1] or 0
    settings.hpOffset, settings.mpOffset, settings.tpOffset = options.xivHpOffset, options.xivMpOffset, options.xivTpOffset
    settings.nameChars = nil
    settings.trimLast = nil
    settings.outline = options.xivOutline == nil or options.xivOutline[1]
    settings.bookends = options.xivBookends == nil or options.xivBookends[1]
    settings.showMp = options.xivShowMp == nil or options.xivShowMp[1]
    settings.showTp = options.xivShowTp == nil or options.xivShowTp[1]
    settings.tpFlash = options.xivTpFlash == nil or options.xivTpFlash[1]
    return settings
end

-- The pets as lines of the list: HP as a percentage unless the figure itself is known, and MP and TP
-- for the player's own alone. They are read as the members are: at most so often, and the same lines
-- drawn in between (see memberRefreshInterval, which this is). The lines are kept and filled in
-- afresh, and a percentage is only made into words again when it changes.
local petRefreshInterval = 0.1
local petLines = { time = -1, sample = false, lines = { }, kept = { } }

local function PetLines(sample)
    local now = os.clock()
    if petLines.sample == sample and now - petLines.time < petRefreshInterval then
        return petLines.lines
    end

    local lines, kept = petLines.lines, petLines.kept
    local pets = petTool.List(sample)
    for index, info in ipairs(pets) do
        local line = kept[index]
        if line == nil then
            line = { isInZone = true }
            kept[index] = line
        end
        -- what is kept for a line between frames goes by its id: a pet's is its place in the list,
        -- not its name, which two pets may share
        line.name, line.serverId = info.name, -(1000 + index)
        line.hp, line.mp, line.mpp, line.tp = info.hp, info.mp, info.mpp, info.tp

        if line.hpp ~= info.hpp or line.hpWords == nil then
            line.hpp = info.hpp
            line.hpWords = ('%d%%'):format(info.hpp)
        end
        line.hpText = info.hp == nil and line.hpWords or nil

        if info.mpp ~= nil and info.mp == nil then
            if line.mpWordsFor ~= info.mpp then
                line.mpWordsFor, line.mpWords = info.mpp, ('%d%%'):format(info.mpp)
            end
            line.mpText = line.mpWords
        else
            line.mpText = nil
        end
        lines[index] = line
    end
    for index = #lines, #pets + 1, -1 do
        lines[index] = nil
    end

    petLines.time, petLines.sample = now, sample
    return lines
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

local function ByRole(a, b)
    if a.sortRank ~= b.sortRank then
        return a.sortRank < b.sortRank
    end
    return a.sortOrder < b.sortOrder
end

-- Sorts members by role. Members with the same job keep their party order.
---@param members PartyMember[]
local function SortByRole(members)
    for order, member in ipairs(members) do
        member.sortRank = member.isPlayer and 0 or roleRank[member.job] or unknownRank
        member.sortOrder = order
    end

    table.sort(members, ByRole)
end

-- Reading a member means a couple of dozen memory calls and a search for their buffs, so the members of
-- each window are read at most this often and the same list is drawn in between. Fast enough that HP,
-- buffs and the target marker do not visibly lag.
local memberRefreshInterval = 0.1
local memberCache = { } -- window name -> { time, sample, sortByRole, members }: the list is emptied and filled, not replaced

-- The members to list in an alliance window, in the order to list them.
-- With sample set, every empty slot is filled with a made-up member, so the window shows at its full size.
-- With sortByRole set, the members are listed by role rather than in party order.
---@return PartyMember[]
local function GetMembers(alliance, sample, sortByRole, target, party, stal)
    local now = os.clock()
    local cached = memberCache[alliance.name]
    if cached == nil then
        cached = { time = -1, members = { } }
        memberCache[alliance.name] = cached
    elseif cached.sample == sample
    and cached.sortByRole == sortByRole
    and now - cached.time < memberRefreshInterval then
        return cached.members
    end

    local members = cached.members
    Clear(members)
    ReadTargets(target)
    for slot, place in ipairs(Alliances[alliance.name]) do
        local person = ReadMember(place, party, stal)
        if sample and not (person.isActive and person.name ~= '') then
            person = GetSampleMember(slot, place)
        end

        if person.isActive and person.name ~= '' then
            members[#members + 1] = person
        end
    end

    if sortByRole then
        SortByRole(members)
    end

    cached.time, cached.sample, cached.sortByRole = now, sample, sortByRole
    return members
end

-- An invitation waiting for an answer: to a party, or for the player's party to an alliance. The
-- server sends one packet to say there is one, and nothing more until it is answered: it is over when
-- the player answers it (a packet of the client's own), when the inviter withdraws it, or when the
-- player changes area, which drops it.
local invite = nil -- { alliance = whether it is to an alliance }

local packetInvite = 0x0DC          -- in: an invitation
local packetInviteWithdrawn = 0x0DE -- in: the invitation is no more
local packetZoneIn = 0x00A          -- in: the player has arrived in an area
local packetInviteAnswer = 0x074    -- out: the player's answer
local kindAlliance = 5              -- the kind of an invitation to an alliance; a party's is 0

local function HandleInvitePacket(e)
    if e.id == packetInvite then
        invite = { alliance = struct.unpack('B', e.data, 0x0B + 1) == kindAlliance }
    elseif e.id == packetInviteWithdrawn or e.id == packetZoneIn then
        invite = nil
    end
end

local function HandleInviteAnswer(e)
    if e.id == packetInviteAnswer then
        invite = nil
    end
end

-- Whether there is anything in the treasure pool, which has ten places. Looked at twice a second,
-- not every frame.
local treasureChecked, treasureWaiting = -1, false

local function TreasureWaiting()
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

-- The icons beside a corner of the party's window: an envelope for an invitation, yellow for a
-- party's and red for an alliance's (the colours of their leaders' marks), pulsing gently; and a
-- chest while there is something in the treasure pool. They are outside the window, above its top
-- corners or below its bottom ones, so nothing in the list moves for them, and where there are both
-- the chest is beside the envelope, further from the corner. They are drawn over every window, not
-- among them, so that another window lying across them does not hide them.
local inviteEnvelope = { width = 13, height = 9, gap = 5 } -- in the lists' own units
local treasureChest = { width = 12, height = 10 }
local iconSpacing = 4 -- between one icon and the next
local iconOpacity = 0.85 -- neither is quite solid
local inviteTint = { 0, 0, 0, 1 }
local inviteLine = { 0.05, 0.05, 0.05, 1 }
local chestWood = { 0.62, 0.40, 0.18, 1 }
local chestTrim = { 0.95, 0.80, 0.30, 1 }
local inviteMin, inviteMax, inviteMid = { 0, 0 }, { 0, 0 }, { 0, 0 }
local inviteClipMin, inviteClipMax = { 0, 0 }, { 0, 0 }
local sampleInvite = { alliance = false }

-- The corners they can go beside, for the setting: the first is the one used when none is chosen
local inviteCorners = {
    { key = 'TopRight', label = 'Top Right' }, { key = 'TopLeft', label = 'Top Left' },
    { key = 'BottomRight', label = 'Bottom Right' }, { key = 'BottomLeft', label = 'Bottom Left' },
}
for _, corner in ipairs(inviteCorners) do
    corner.ids = ('%s##us.inviteCorner'):format(corner.label)
end

-- The envelope: its body, its edge, and the two lines of its flap meeting in the middle. Between about
-- two thirds of its strength and all of it, once every second and a half.
local function DrawEnvelope(drawList, left, top, width, height, shown)
    local color = shown.alliance and ui.Colors.Alliance or ui.Colors.Party
    local pulse = 0.83 + 0.17 * math.cos(os.clock() / 1.5 * 2 * math.pi)
    inviteTint[1], inviteTint[2], inviteTint[3], inviteTint[4] = color[1], color[2], color[3], pulse * iconOpacity
    local packed = imgui.GetColorU32(inviteTint)
    inviteTint[1], inviteTint[2], inviteTint[3], inviteTint[4] = inviteLine[1], inviteLine[2], inviteLine[3], iconOpacity
    local dark = imgui.GetColorU32(inviteTint)

    inviteMin[1], inviteMin[2] = left, top
    inviteMax[1], inviteMax[2] = left + width, top + height
    drawList:AddRectFilled(inviteMin, inviteMax, packed, 2)
    drawList:AddRect(inviteMin, inviteMax, dark, 2, 0, 1)
    inviteMid[1], inviteMid[2] = left + width / 2, top + height * 0.55
    drawList:AddLine(inviteMin, inviteMid, dark, 1)
    inviteMin[1] = left + width
    drawList:AddLine(inviteMin, inviteMid, dark, 1)
end

-- The chest: a wooden box with a band of trim where its lid meets it, a clasp in the middle of the
-- band, and an edge
local function DrawChest(drawList, left, top, width, height)
    inviteTint[4] = iconOpacity
    inviteTint[1], inviteTint[2], inviteTint[3] = chestWood[1], chestWood[2], chestWood[3]
    local wood = imgui.GetColorU32(inviteTint)
    inviteTint[1], inviteTint[2], inviteTint[3] = chestTrim[1], chestTrim[2], chestTrim[3]
    local trim = imgui.GetColorU32(inviteTint)
    inviteTint[1], inviteTint[2], inviteTint[3] = inviteLine[1], inviteLine[2], inviteLine[3]
    local dark = imgui.GetColorU32(inviteTint)

    inviteMin[1], inviteMin[2] = left, top
    inviteMax[1], inviteMax[2] = left + width, top + height
    drawList:AddRectFilled(inviteMin, inviteMax, wood, 2)

    -- the band, a little above the middle, and the clasp across it
    local band = math.max(1, math.floor(height * 0.16 + 0.5))
    local seam = math.floor(top + height * 0.38)
    inviteMin[2], inviteMax[2] = seam, seam + band
    drawList:AddRectFilled(inviteMin, inviteMax, trim, 0)
    local clasp = math.max(2, math.floor(width * 0.22 + 0.5))
    inviteMin[1], inviteMin[2] = math.floor(left + (width - clasp) / 2), seam - 1
    inviteMax[1], inviteMax[2] = inviteMin[1] + clasp, seam + band + math.max(2, math.floor(height * 0.2))
    drawList:AddRectFilled(inviteMin, inviteMax, trim, 1)
    drawList:AddRect(inviteMin, inviteMax, dark, 1, 0, 1)

    inviteMin[1], inviteMin[2] = left, top
    inviteMax[1], inviteMax[2] = left + width, top + height
    drawList:AddRect(inviteMin, inviteMax, dark, 2, 0, 1)
end

-- Draws whichever icons there are to show: invitation is the one waiting, if any, and treasure
-- whether there is something in the pool
local function DrawIcons(invitation, treasure)
    local windowX, windowY = imgui.GetWindowPos()
    local display = imgui.GetIO().DisplaySize
    -- a list laid out off screen to be measured has no icons
    if windowX < 0 or windowY < 0 or windowX > display.x or windowY > display.y then
        return
    end

    local options = usOptions
    local scale = 1.2 * (options.xivScale ~= nil and options.xivScale[1] or 100) / 100
    local gap = inviteEnvelope.gap * scale

    -- beside the corner chosen, and from there as far as they have been moved: the first at the
    -- corner, the next beyond it, their feet on one line
    local corner = options.inviteCorner or inviteCorners[1].key
    local onRight = corner == 'TopRight' or corner == 'BottomRight'
    local below = corner == 'BottomRight' or corner == 'BottomLeft'
    local windowWidth, windowHeight = imgui.GetWindowSize()
    local offset = options.inviteOffset
    local edge = (onRight and windowX + windowWidth or windowX) + (offset and tonumber(offset[1]) or 0) * scale
    local tallest = math.max(inviteEnvelope.height, treasureChest.height) * scale
    local foot = (below and windowY + windowHeight + gap + tallest or windowY - gap) + (offset and tonumber(offset[2]) or 0) * scale

    -- over every window where that can be done, and otherwise in the party's own, opened up to the
    -- whole screen
    local overAll = imgui.GetForegroundDrawList ~= nil
    local drawList = overAll and imgui.GetForegroundDrawList() or imgui.GetWindowDrawList()
    if not overAll then
        inviteClipMax[1], inviteClipMax[2] = display.x, display.y
        drawList:PushClipRect(inviteClipMin, inviteClipMax, false)
    end

    if invitation ~= nil then
        local width, height = inviteEnvelope.width * scale, inviteEnvelope.height * scale
        local left = onRight and edge - width or edge
        DrawEnvelope(drawList, math.floor(left), math.floor(foot - height), width, height, invitation)
        edge = onRight and left - iconSpacing * scale or left + width + iconSpacing * scale
    end
    if treasure then
        local width, height = treasureChest.width * scale, treasureChest.height * scale
        local left = onRight and edge - width or edge
        DrawChest(drawList, math.floor(left), math.floor(foot - height), math.floor(width), math.floor(height))
    end

    if not overAll then
        drawList:PopClipRect()
    end
end

-- What a list's window holds, drawn by one function for whichever list is being drawn: which is said
-- beforehand, here, so that no function need be made afresh for each list every frame
local drawing = { alliance = nil, sample = false, sortByRole = false, ownParty = false, pets = nil }

local function DrawAllianceContent()
    local alliance, ownParty, pets = drawing.alliance, drawing.ownParty, drawing.pets
    local target = AshitaCore:GetMemoryManager():GetTarget()
    local party = AshitaCore:GetMemoryManager():GetParty()
    local stal = ffxi.GetStPartyIndex()

    local members = GetMembers(alliance, drawing.sample, drawing.sortByRole, target, party, stal)

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
    end

    -- a list's last line is only as tall as what is on it: so the window ends where its content
    -- does, and what follows a list is a known distance under it
    local hasPets = pets ~= nil and #pets > 0
    local settings = StyleSettings()
    settings.trimLast = true
    xivparty.Draw(members, ownParty and 'party' or 'alliance', StatusTexture, settings)

    -- the pets, under a line, with as much room above the line and below it as there is between the
    -- window's edge and its first member: the window's padding
    if hasPets then
        local room = ui.Styles.WindowPadding[2] - ui.Styles.ItemSpacing[2] -- imgui puts the spacing in itself
        imgui.SetCursorPosY(imgui.GetCursorPosY() + room)
        imgui.Separator()
        imgui.SetCursorPosY(imgui.GetCursorPosY() + room)
        xivparty.Draw(pets, 'pets', nil, settings)
    end

    -- an invitation waiting for an answer, and anything in the treasure pool, have icons beside the
    -- player's own party; both are shown while the windows are arranged, to see where they go
    if ownParty then
        local invitation, treasure = nil, false
        if usOptions.showInvite == nil or usOptions.showInvite[1] then
            invitation = invite or (drawing.sample and sampleInvite) or nil
        end
        if usOptions.showTreasure == nil or usOptions.showTreasure[1] then
            treasure = drawing.sample or TreasureWaiting()
        end
        if invitation ~= nil or treasure then
            DrawIcons(invitation, treasure)
        end
    end
end

-- ownParty is set for the player's own party: its list keeps its bottom edge where it is and grows
-- upwards as members join, has its buffs beside it, and has the pets under it. The other two lists
-- grow downwards.
local function DrawAlliance(alliance, gOptions, sample, sortByRole, ownParty)
    drawing.alliance = alliance
    drawing.sample = sample and true or false
    drawing.sortByRole = sortByRole and true or false
    drawing.ownParty = ownParty and true or false
    drawing.pets = nil
    if ownParty and petTool.IsEnabled() then
        drawing.pets = PetLines(drawing.sample)
    end

    ui.DrawUiWindow(alliance, gOptions, DrawAllianceContent, nil, ownParty and 'BottomLeft' or nil)
end

local function SortsByRole(options)
    return options.sortByRole ~= nil and options.sortByRole[1]
end

-- Each list's places in the alliance, in the game's order
Alliances['xiframes.us.1'] = { 0, 1, 2, 3, 4, 5 }
Alliances['xiframes.us.2'] = { 6, 7, 8, 9, 10, 11 }
Alliances['xiframes.us.3'] = { 12, 13, 14, 15, 16, 17 }

local function UpdateAlliances(options)
    usOptions = options
    memberCache = { }
end

-- The sliders that move the HP, MP and TP values: two for each, across and down
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

-- A place as two sliders side by side, across and down, under one name. offset is the { x, y } they set.
local function OffsetSliders(label, ids, offset, reach, tooltip)
    ui.Label(label)
    for axis = 1, 2 do
        if axis == 2 then
            imgui.SameLine()
        end
        xivOffsetBox[1] = tonumber(offset[axis]) or 0
        imgui.PushItemWidth(xivOffsetSliderWidth)
        if imgui.SliderInt(ids[axis], xivOffsetBox, -reach, reach, axis == 1 and 'X %d' or 'Y %d') then
            offset[axis] = xivOffsetBox[1]
        end
        imgui.PopItemWidth()
        if imgui.IsItemHovered() then
            imgui.SetTooltip(tooltip)
        end
    end
end

local inviteOffsetIds = { '##us.inviteOffsetX', '##us.inviteOffsetY' }
local inviteOffsetReach = 300

---@type xitool
local us = {
    Name = 'us',
    DefaultSettings = T{
        isEnabled = T{ true },
        isVisible = T{ true },
        hideWhenSolo = T{ false },
        sortByRole = T{ false },
        showInvite = T{ true },      -- an icon for an invitation that is waiting for an answer, beside the party's window
        showTreasure = T{ true },    -- and one while there is something in the treasure pool
        inviteCorner = 'TopRight',   -- the corner of the window the icons go beside
        inviteOffset = T{ 0, 0 },    -- and how far from there they are moved: right, down
        xivScale = T{ 100 },   -- the lists' size, as a percentage
        xivValueSize = T{ 100 }, -- the size of the HP, MP and TP figures, as a percentage
        xivNameSize = T{ 100 },  -- and of the names
        xivBuffSize = T{ 100 },  -- and of the buff icons
        xivBuffDistance = T{ 0 }, -- how much further from the party's window than usual the buffs start
        xivBuffSpacing = T{ 0 },  -- the room between one buff icon and the next
        xivHpOffset = T{ 0, 0 }, -- how far the HP figure is moved from its place: right, down
        xivMpOffset = T{ 0, 0 }, -- and the MP figure
        xivTpOffset = T{ 0, 0 }, -- and the TP figure
        xivOutline = T{ true }, -- whether the names and the HP, MP and TP figures have a dark edge
        xivBookends = T{ true }, -- whether the HP and MP bars have a small silver cap at each end
        xivShowMp = T{ true }, -- whether the MP figure is written beside its bar
        xivShowTp = T{ true }, -- whether TP is written
        xivTpFlash = T{ true }, -- whether TP at 1000 and over pulses between a light blue and a deeper one
        alliance1 = T{
            isVisible = T{ true },
            name = 'xiframes.us.1',
            pos = T{ 392, 628 },
            flags = bit.bor(ImGuiWindowFlags_NoDecoration),
        },
        alliance2 = T{
            isVisible = T{ true },
            name = 'xiframes.us.2',
            pos = T{ 107, 628 },
            flags = bit.bor(ImGuiWindowFlags_NoDecoration),
        },
        alliance3 = T{
            isVisible = T{ true },
            name = 'xiframes.us.3',
            pos = T{ 000, 628 },
            flags = bit.bor(ImGuiWindowFlags_NoDecoration),
        },
    },
    UpdateSettings = UpdateAlliances,
    Load = UpdateAlliances,
    HandlePacket = HandleInvitePacket,
    HandlePacketOut = HandleInviteAnswer,
    DrawConfig = function(options, gOptions)
        if imgui.BeginTabItem('us') then
            ui.BeginLabels('xiframes.us')
            ui.Label('Enabled')
            imgui.Checkbox('##us.1', options.isEnabled)

            ui.Gap()
            ui.Label('Hide When Solo')
            imgui.Checkbox('##us.2', options.hideWhenSolo)

            -- Settings saved before this option existed have no value for it
            if options.sortByRole == nil then
                options.sortByRole = T{ false }
            end
            if options.showInvite == nil then
                options.showInvite = T{ true }
            end
            ui.Label('Show Invites')
            imgui.Checkbox('##us.showInvite', options.showInvite)
            if imgui.IsItemHovered() then
                imgui.SetTooltip('Marks an invitation that is waiting for your answer with an envelope beside your party\'s window: yellow for a party invite, red for an alliance invite.\nWith Hide When Solo on, the window shows while an invitation is waiting.')
            end
            if options.showTreasure == nil then
                options.showTreasure = T{ true }
            end
            ui.Label('Show Treasure Pool')
            imgui.Checkbox('##us.showTreasure', options.showTreasure)
            if imgui.IsItemHovered() then
                imgui.SetTooltip('Shows a chest beside your party\'s window while there is anything in the treasure pool. With an invite waiting too, it goes beside the envelope.')
            end
            if options.showInvite[1] or options.showTreasure[1] then
                if type(options.inviteOffset) ~= 'table' then
                    options.inviteOffset = T{ 0, 0 }
                end
                -- the corners two to a line, the top ones then the bottom ones
                ui.Label('Icon Corner')
                local column = imgui.GetCursorPosX()
                for index, corner in ipairs(inviteCorners) do
                    if index % 2 == 0 then
                        imgui.SameLine()
                    elseif index > 1 then
                        imgui.SetCursorPosX(column)
                    end
                    local chosen = options.inviteCorner == corner.key or (index == 1 and options.inviteCorner == nil)
                    if imgui.RadioButton(corner.ids, chosen) then
                        options.inviteCorner = corner.key
                    end
                    if imgui.IsItemHovered() then
                        imgui.SetTooltip('The corner of your party\'s window the invite and treasure icons go beside: above a top corner, below a bottom one.')
                    end
                end
                OffsetSliders('Icon Offset', inviteOffsetIds, options.inviteOffset, inviteOffsetReach,
                    'Moves the invite and treasure icons from their corner: X to the right, Y down. Less than 0 moves them left or up.\nThe numbers are in the list\'s own units, so the icons keep their place as the scale changes.')
            end
            ui.Label('Sort By Role')
            imgui.Checkbox('##us.3', options.sortByRole)
            if imgui.IsItemHovered() then
                imgui.SetTooltip('Off lists members in the game\'s own party order.\nOn lists you first, then tanks (PLD, NIN, WAR, RUN), melee damage (MNK, SAM, DRK, DRG, THF, DNC, BLU, BST, PUP),\nranged damage (RNG), support (BRD, COR, GEO), mages (BLM, SMN, SCH) and healers (RDM, WHM).\nEach party of the alliance is sorted on its own.')
            end
            -- Settings saved before these options existed have no value for them
            if options.xivScale == nil or options.xivScale[1] < 50 then
                options.xivScale = T{ 100 }
            end
            if options.xivShowMp == nil then
                options.xivShowMp = T{ true }
            end
            if options.xivOutline == nil then
                options.xivOutline = T{ true }
            end
            if options.xivBookends == nil then
                options.xivBookends = T{ true }
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
            if options.xivBuffDistance == nil then
                options.xivBuffDistance = T{ 0 }
            end
            if options.xivBuffSpacing == nil then
                options.xivBuffSpacing = T{ 0 }
            end
            for _, key in ipairs({ 'xivHpOffset', 'xivMpOffset', 'xivTpOffset' }) do
                if type(options[key]) ~= 'table' then
                    options[key] = T{ 0, 0 }
                end
            end
            if options.xivShowTp == nil then
                options.xivShowTp = T{ true }
            end
            if options.xivTpFlash == nil then
                options.xivTpFlash = T{ true }
            end
            usOptions = options
            ui.Gap()
            ui.Label('Scale (%)')
            imgui.SliderInt('##us.xivScale', options.xivScale, 50, 200, '%d%%')
            if imgui.IsItemHovered() then
                imgui.SetTooltip('How big the party lists and the target windows are drawn: the bars, the text and the buffs together.')
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
            ui.Label('Buff Spacing')
            imgui.SliderInt('##us.xivBuffSpacing', options.xivBuffSpacing, -5, 20)
            if imgui.IsItemHovered() then
                imgui.SetTooltip('How much room there is between one buff icon and the next. At 0 they touch; less than 0 overlaps them.\nThe number is in the list\'s own units, so the spacing keeps its proportion as the scale changes.')
            end
            ui.Label('Buff Distance')
            imgui.SliderInt('##us.xivBuffDistance', options.xivBuffDistance, -60, 200)
            if imgui.IsItemHovered() then
                imgui.SetTooltip('How far from your party\'s window the buff icons start. 0 is just clear of its left edge; more moves them further left, and less than 0 brings them right, over the window.\nThe number is in the list\'s own units, so the distance keeps its proportion as the scale changes.')
            end
            ui.Label('Value Text Size (%)')
            imgui.SliderInt('##us.xivValueSize', options.xivValueSize, 50, 200, '%d%%')
            if imgui.IsItemHovered() then
                imgui.SetTooltip('How big the HP, MP and TP values are written, apart from everything else.')
            end
            -- each value's place: a slider across and a slider down, side by side
            for _, value in ipairs(xivOffsetControls) do
                OffsetSliders(value.label, value.ids, options[value.key], xivOffsetReach, value.tooltip)
            end
            ui.Label('Outline Text')
            imgui.Checkbox('##us.xivOutline', options.xivOutline)
            if imgui.IsItemHovered() then
                imgui.SetTooltip('Gives the names and the HP, MP and TP values a dark edge, so they can be read where they are written over a bar.')
            end
            ui.Label('Bar Bookends')
            imgui.Checkbox('##us.xivBookends', options.xivBookends)
            if imgui.IsItemHovered() then
                imgui.SetTooltip('Puts a small silver cap at each end of the HP and MP bars, like the ones on the game\'s own party list.')
            end
            ui.Label('Show MP Values')
            imgui.Checkbox('##us.xivShowMp', options.xivShowMp)
            if imgui.IsItemHovered() then
                imgui.SetTooltip('Writes each member\'s MP beside their MP bar. Off leaves the bar alone.')
            end
            ui.Label('Show TP Values')
            imgui.Checkbox('##us.xivShowTp', options.xivShowTp)
            if imgui.IsItemHovered() then
                imgui.SetTooltip('Writes each member\'s TP on their line. TP has no bar, so off leaves TP out altogether.')
            end
            ui.Label('Flash TP When Ready')
            imgui.Checkbox('##us.xivTpFlash', options.xivTpFlash)
            if imgui.IsItemHovered() then
                imgui.SetTooltip('A TP value of 1000 or over pulses between a light blue and a deeper one. Off, it is simply blue.')
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

        -- hidden while solo if that is set, but not while there is an invitation to be seen
        local waiting = invite ~= nil and (options.showInvite == nil or options.showInvite[1])
        if (options.hideWhenSolo[1] and (alliCount1 > 1 or (waiting and alliCount1 > 0)))
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

-- How the lists are set to be drawn, for another tool that draws in the same style (the target
-- windows): the table xivparty.Draw takes, to be used at once, or nil before the
-- party's settings are known
function us.StyleSettings()
    if usOptions == nil then
        return nil
    end
    return StyleSettings()
end

return us
