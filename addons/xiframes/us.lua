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
---@field name            string
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

local function GetPlayer(options, target, party, stal)
    local player = AshitaCore:GetMemoryManager():GetPlayer()

    local serverId = party:GetMemberServerId(0)
    local buffs = FilterBuffs(player:GetBuffs())

    return {
        targetIndex = party:GetMemberTargetIndex(0),
        name = party:GetMemberName(0),
        isPlayer = true,
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
    settings.hpOffset, settings.mpOffset, settings.tpOffset = options.xivHpOffset, options.xivMpOffset, options.xivTpOffset
    settings.nameChars = nil
    settings.outline = options.xivOutline == nil or options.xivOutline[1]
    settings.glow = options.xivGlow == nil or options.xivGlow[1]
    settings.showMp = options.xivShowMp == nil or options.xivShowMp[1]
    settings.showTp = options.xivShowTp == nil or options.xivShowTp[1]
    return settings
end

-- A pet as a line of the list: its HP as a percentage unless the figure itself is known, and
-- MP and TP for the player's own alone
local function PetLine(info)
    return {
        name = info.name, serverId = info.name, isInZone = true,
        hp = info.hp, hpp = info.hpp, hpText = info.hp == nil and ('%d%%'):format(info.hpp) or nil,
        mp = info.mp, mpp = info.mpp, mpText = (info.mpp ~= nil and info.mp == nil) and ('%d%%'):format(info.mpp) or nil,
        tp = info.tp,
    }
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

-- ownParty is set for the player's own party: its list keeps its bottom edge where it is and grows
-- upwards as members join, has its buffs beside it, and has the pets under it. The other two lists
-- grow downwards.
local function DrawAlliance(alliance, gOptions, sample, sortByRole, ownParty)
    sample = sample and true or false
    sortByRole = sortByRole and true or false

    local pets = nil
    if ownParty and petTool.IsEnabled() then
        pets = petTool.List(sample)
    end

    ui.DrawUiWindow(alliance, gOptions, function()
        local target = AshitaCore:GetMemoryManager():GetTarget()
        local party = AshitaCore:GetMemoryManager():GetParty()
        local stal = ffxi.GetStPartyIndex()

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
        end

        xivparty.Draw(members, ownParty and 'party' or 'alliance', StatusTexture, StyleSettings())

        -- the pets, under a line
        if pets ~= nil and #pets > 0 then
            imgui.Separator()
            local lines = { }
            for index, info in ipairs(pets) do
                lines[index] = PetLine(info)
            end
            xivparty.Draw(lines, 'pets', nil, StyleSettings())
        end
    end, nil, ownParty and 'BottomLeft' or nil)
end

local function SortsByRole(options)
    return options.sortByRole ~= nil and options.sortByRole[1]
end

local function UpdateAlliances(options)
    usOptions = options
    memberCache = { }
    Alliances['xiframes.us.1'] = {
        GetPlayer:bindn(options),
        GetMember:bindn(1, options.alliance1),
        GetMember:bindn(2, options.alliance1),
        GetMember:bindn(3, options.alliance1),
        GetMember:bindn(4, options.alliance1),
        GetMember:bindn(5, options.alliance1),
    }
    Alliances['xiframes.us.2'] = {
        GetMember:bindn(6, options.alliance2),
        GetMember:bindn(7, options.alliance2),
        GetMember:bindn(8, options.alliance2),
        GetMember:bindn(9, options.alliance2),
        GetMember:bindn(10, options.alliance2),
        GetMember:bindn(11, options.alliance2),
    }
    Alliances['xiframes.us.3'] = {
        GetMember:bindn(12, options.alliance3),
        GetMember:bindn(13, options.alliance3),
        GetMember:bindn(14, options.alliance3),
        GetMember:bindn(15, options.alliance3),
        GetMember:bindn(16, options.alliance3),
        GetMember:bindn(17, options.alliance3),
    }
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

---@type xitool
local us = {
    Name = 'us',
    DefaultSettings = T{
        isEnabled = T{ true },
        isVisible = T{ true },
        hideWhenSolo = T{ false },
        sortByRole = T{ false },
        xivScale = T{ 100 },   -- the lists' size, as a percentage
        xivValueSize = T{ 100 }, -- the size of the HP, MP and TP figures, as a percentage
        xivNameSize = T{ 100 },  -- and of the names
        xivBuffSize = T{ 100 },  -- and of the buff icons
        xivHpOffset = T{ 0, 0 }, -- how far the HP figure is moved from its place: right, down
        xivMpOffset = T{ 0, 0 }, -- and the MP figure
        xivTpOffset = T{ 0, 0 }, -- and the TP figure
        xivOutline = T{ true }, -- whether the names and the HP, MP and TP figures have a dark edge
        xivGlow = T{ true },    -- whether a bar glows for a moment over what it has lost
        xivShowMp = T{ true }, -- whether the MP figure is written beside its bar
        xivShowTp = T{ true }, -- whether TP is written
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
            if options.xivGlow == nil then
                options.xivGlow = T{ true }
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
            ui.Label('Outline Text')
            imgui.Checkbox('##us.xivOutline', options.xivOutline)
            if imgui.IsItemHovered() then
                imgui.SetTooltip('Gives the names and the HP, MP and TP values a dark edge, so they can be read where they are written over a bar.')
            end
            ui.Label('Bar Glow')
            imgui.Checkbox('##us.xivGlow', options.xivGlow)
            if imgui.IsItemHovered() then
                imgui.SetTooltip('An HP or MP bar glows for a moment over what it has just lost. Off, the bars simply change.')
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
