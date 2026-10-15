-- roster: who is in the alliance, read from the game as lines for frames.lua to draw.
--
--     roster.Counts()                              how many members each of the three parties has
--     roster.Members(list, sample, sortByRole)     the lines of party 1, 2 or 3, in the order to list them
--     roster.StatusTexture(id, useOwn)             the texture for a status icon, or nil; and whether it is one of winxi's own
--     roster.Forget()                              reads everyone afresh: for when the settings change
--
-- With sample set, every empty place is filled with a made-up member, so that a list shows at its
-- full size while the windows are arranged. With sortByRole set, a party is listed by role, not in
-- the game's order.
--
-- Reading a member means a couple of dozen memory calls and a search for their buffs, so each party
-- is read at most ten times a second and the same lines are handed back in between; who is where
-- (for how far away they are) is looked up afresh every time, as an entity must not be kept, and so
-- is who is targeted, for the cursor before a name to keep up with the game's.
require('common')
local bit = require('bit')
local ffi = require('ffi')
local d3d8 = require('d3d8')
local statusicons = require('winxi.statusicons')
local d3d8_device = d3d8.get_device()
local game = require('game')

local roster = { }

local Textures = { }

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
        print('party error: no icon for status ' .. tostring(statusId))
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

local function HasNoMp(place, party, serverId, mp, mpp, main)
    if place == 0 then
        return AshitaCore:GetMemoryManager():GetPlayer():GetMPMax() == 0
    end

    local sub = party:GetMemberSubJob(place)
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

-- Whether each member is the one targeted, sub-targeted or under the party cursor. Looked at every
-- frame, not ten times a second as the rest is, so the cursor before a name keeps up with the game's.
-- A made-up member has no place, and is never selected.
local function MarkTargets(members, target, stal)
    ReadTargets(target)
    for _, member in ipairs(members) do
        local place = member.place
        if place ~= nil then
            local serverId = member.serverId
            -- with a sub-target out, the game holds it first and the target second
            if targeted.subActive then
                member.isTarget = serverId == targeted.second
                member.isSubTarget = serverId == targeted.first
            else
                member.isTarget = serverId == targeted.first
                member.isSubTarget = false
            end
            member.isPartyTarget = stal ~= nil and stal == place
        end
    end
end

---@return PartyMember
local function ReadMember(place, party)
    local member = places[place]
    if member == nil then
        member = { statusIds = { }, isPlayer = place == 0, place = place }
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
    local main = party:GetMemberMainJob(place)
    member.job = game.JobAbbr(main)
    member.jobLevel = party:GetMemberMainJobLevel(place)
    member.subJob = game.JobAbbr(party:GetMemberSubJob(place))
    member.subJobLevel = party:GetMemberSubJobLevel(place)
    member.jobText = game.JobText(member.job, member.jobLevel, member.subJob, member.subJobLevel)
    member.zoneId = zone
    member.hpp = party:GetMemberHPPercent(place)
    member.mpp = party:GetMemberMPPercent(place)
    member.hp = party:GetMemberHP(place)
    member.mp = party:GetMemberMP(place)
    member.tp = party:GetMemberTP(place)
    member.noMp = HasNoMp(place, party, serverId, member.mp, member.mpp, main)
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
        serverId = -(2000 + place), -- its own, apart from the other made-up members' and anyone real
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

-- A status icon's texture as the number imgui takes, or nil where the game has no icon for it. With
-- useOwn, winxi's own icon (FFXIV's) where it has one for the status: true is then returned as well,
-- for an icon of that shape.
local textureHandles = { }

function roster.StatusTexture(buffId, useOwn)
    if useOwn then
        local own = statusicons.Own(buffId)
        if own ~= nil then
            return own, true
        end
    end
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
    return handle or nil, false
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

-- Each party's places in the alliance, in the game's order: 0 is the player
local partyPlaces = {
    { 0, 1, 2, 3, 4, 5 },
    { 6, 7, 8, 9, 10, 11 },
    { 12, 13, 14, 15, 16, 17 },
}

local refreshInterval = 0.1
local cache = { } -- party -> { time, sample, sortByRole, members }: the list is emptied and filled, not replaced

function roster.Forget()
    cache = { }
end

function roster.Counts()
    local memory = AshitaCore:GetMemoryManager():GetParty()
    return memory:GetAlliancePartyMemberCount1(), memory:GetAlliancePartyMemberCount2(), memory:GetAlliancePartyMemberCount3()
end

-- An entity must not be kept from one frame to the next: each member's is looked up afresh, in case
-- it has gone since they were read. It must be the member's own, too: one in another area, or whose
-- place has been taken, would give the distance to whatever has that index here.
local function FindEntities(members)
    for _, member in ipairs(members) do
        local entity = member.targetIndex and GetEntity(member.targetIndex) or nil
        if entity ~= nil and (not member.isInZone or entity.ServerId ~= member.serverId) then
            entity = nil
        end
        member.entity = entity
    end
    return members
end

---@return PartyMember[]
function roster.Members(list, sample, sortByRole)
    local now = os.clock()
    local cached = cache[list]
    if cached == nil then
        cached = { time = -1, members = { } }
        cache[list] = cached
    elseif cached.sample == sample
    and cached.sortByRole == sortByRole
    and now - cached.time < refreshInterval then
        MarkTargets(cached.members, AshitaCore:GetMemoryManager():GetTarget(), game.StPartyIndex())
        return FindEntities(cached.members)
    end

    local memory = AshitaCore:GetMemoryManager()
    local partyMemory = memory:GetParty()

    local members = cached.members
    Clear(members)
    for slot, place in ipairs(partyPlaces[list]) do
        local member = ReadMember(place, partyMemory)
        if sample and not (member.isActive and member.name ~= '') then
            member = GetSampleMember(slot, place)
        end

        if member.isActive and member.name ~= '' then
            members[#members + 1] = member
        end
    end

    if sortByRole then
        SortByRole(members)
    end

    cached.time, cached.sample, cached.sortByRole = now, sample, sortByRole
    MarkTargets(members, memory:GetTarget(), game.StPartyIndex())
    return FindEntities(members)
end

return roster
