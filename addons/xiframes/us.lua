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
local function GetSampleMember(slot)
    return {
        targetIndex = nil,
        name = ('Sample %d'):format(slot),
        serverId = 0,
        isInZone = true,
        isActive = true,
        isPartyLeader = slot == 1,
        isAllianceLeader = false,
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
            person = GetSampleMember(slot)
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

    xivparty.Draw(members, ownParty and 'party' or 'alliance', StatusTexture, StyleSettings())

    -- the pets, under a line
    if pets ~= nil and #pets > 0 then
        imgui.Separator()
        xivparty.Draw(pets, 'pets', nil, StyleSettings())
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
