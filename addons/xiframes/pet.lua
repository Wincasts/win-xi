require('common')
local imgui = require('imgui')
local ui = require('ui')

local jobPup = 18
local partySize = 6

-- The automaton's HP and MP as last reported by the server, which sends them to its master only.
-- Nothing is known until the first report arrives (on zoning, job change, or when the automaton's state changes).
local automaton = { hp = nil, maxHp = 0, mp = nil, maxMp = 0 }

-- An exact value for a bar: the reported one while it still agrees with the percentage on screen,
-- otherwise worked out from the maximum, in case the server has not sent a fresh report.
local function ExactValue(reported, max, percent)
    if reported == nil or max <= 0 then
        return nil
    end

    if math.abs(reported / max * 100 - percent) <= 1 then
        return reported
    end
    return math.floor(max * percent / 100 + 0.5)
end

local function IsPuppetmaster()
    local player = AshitaCore:GetMemoryManager():GetPlayer()
    return player:GetMainJob() == jobPup or player:GetSubJob() == jobPup
end

---@class PetInfo
---@field name     string
---@field owner    string?  the party member it belongs to; nil for the player's own pet
---@field distance number
---@field hpp      integer
---@field mpp      integer? only known for the player's own pet
---@field tp       integer? only known for the player's own pet
---@field hp       integer? exact HP, shown in place of the percentage when known
---@field mp       integer? exact MP, shown in place of the percentage when known

-- The entity of the pet belonging to the entity at ownerIndex, if it has one the client knows about
local function GetPetEntity(ownerIndex)
    if ownerIndex == nil or ownerIndex == 0 then
        return nil
    end

    local owner = GetEntity(ownerIndex)
    if owner == nil or owner.PetTargetIndex == nil or owner.PetTargetIndex == 0 then
        return nil
    end

    local pet = GetEntity(owner.PetTargetIndex)
    if pet == nil or pet.Name == nil then
        return nil
    end
    return pet
end

---@return PetInfo?
local function GetOwnPet(options)
    local party = AshitaCore:GetMemoryManager():GetParty()
    local entity = GetPetEntity(party:GetMemberTargetIndex(0))
    if entity == nil then
        return nil
    end

    local player = AshitaCore:GetMemoryManager():GetPlayer()
    local pet = {
        name = entity.Name,
        distance = math.sqrt(entity.Distance),
        hpp = entity.HPPercent,
        mpp = player:GetPetMPPercent(),
        tp = player:GetPetTP(),
    }

    -- Exact HP and MP are only known for a puppetmaster's automaton. On unless switched off.
    if (options.exactAutomaton == nil or options.exactAutomaton[1]) and IsPuppetmaster() then
        pet.hp = ExactValue(automaton.hp, automaton.maxHp, pet.hpp)
        pet.mp = ExactValue(automaton.mp, automaton.maxMp, pet.mpp)
    end

    return pet
end

-- The pets of the other members of the player's party who are in the same zone, in party order
---@return PetInfo[]
local function GetPartyPets()
    local party = AshitaCore:GetMemoryManager():GetParty()
    local pets = { }

    for i = 1, partySize - 1 do
        if party:GetMemberIsActive(i) == 1 and party:GetMemberZone(i) == party:GetMemberZone(0) then
            local entity = GetPetEntity(party:GetMemberTargetIndex(i))
            if entity ~= nil then
                table.insert(pets, {
                    name = entity.Name,
                    owner = party:GetMemberName(i),
                    distance = math.sqrt(entity.Distance),
                    hpp = entity.HPPercent,
                })
            end
        end
    end

    return pets
end

local function ShowsPartyPets(options)
    return options.showParty == nil or options.showParty[1]
end

-- The pets to list: the player's own, then the other party members' where those are shown
---@return PetInfo[]
local function GatherPets(options)
    local pets = { }
    local own = GetOwnPet(options)
    if own ~= nil then
        table.insert(pets, own)
    end
    if ShowsPartyPets(options) then
        for _, partyPet in ipairs(GetPartyPets()) do
            table.insert(pets, partyPet)
        end
    end
    return pets
end

-- How many pets there are to see while the windows are arranged, counting made-up ones: enough to
-- show the player's own and how another member's looks, without a list of six
local samplePetCount = 2

-- Real pets where there are any, and made-up ones to make their number up: the player's own, and
-- another member's when party pets are shown
---@return PetInfo[]
local function GatherSamplePets(options)
    local pets = { }
    table.insert(pets, GetPlayerEntity() and GetOwnPet(options) or { name = 'Sample Pet', distance = 4, hpp = 80, mpp = 60, tp = 1200 })

    if ShowsPartyPets(options) then
        if GetPlayerEntity() then
            for _, partyPet in ipairs(GetPartyPets()) do
                table.insert(pets, partyPet)
            end
        end
        for i = #pets + 1, samplePetCount do
            table.insert(pets, {
                name = ('Sample Pet %d'):format(i),
                owner = ('Sample %d'):format(i),
                distance = 4 + i * 2,
                hpp = 100 - i * 15,
            })
        end
    end
    return pets
end

-- The tool's settings as last handed to it, for the party window, which lists the pets
local settings = nil

local function Remember(options)
    settings = options
end

---@type xitool
local pet = {
    Name = 'pet',
    DefaultSettings = T{
        isEnabled = T{ true },
        exactAutomaton = T{ true },
        showParty = T{ true },
    },
    Load = Remember,
    UpdateSettings = Remember,
    HandlePacket = function(e, options, gOptions)
        -- Extended job info for puppetmaster: the automaton's current and maximum HP and MP
        if e.id == 0x044 and struct.unpack('B', e.data, 0x04 + 1) == jobPup then
            automaton.hp = struct.unpack('H', e.data, 0x68 + 1)
            automaton.maxHp = struct.unpack('H', e.data, 0x6A + 1)
            automaton.mp = struct.unpack('H', e.data, 0x6C + 1)
            automaton.maxMp = struct.unpack('H', e.data, 0x6E + 1)
        end
    end,
    DrawConfig = function(options, gOptions)
        if imgui.BeginTabItem('pet') then
            ui.BeginLabels('xiframes.pet')
            -- Settings saved before these options existed have no value for them
            if options.exactAutomaton == nil then
                options.exactAutomaton = T{ true }
            end
            if options.showParty == nil then
                options.showParty = T{ true }
            end

            ui.Label('Enabled')
            imgui.Checkbox('##pet.1', options.isEnabled)
            if imgui.IsItemHovered() then
                imgui.SetTooltip('Lists the pets under your party, below a line.')
            end

            ui.Gap()
            ui.Label('Show Party Members\' Pets')
            imgui.Checkbox('##pet.2', options.showParty)
            if imgui.IsItemHovered() then
                imgui.SetTooltip('Lists the pets of the other members of your party under your own, with their owner\'s name.\nOnly their HP is shown: a pet\'s MP and TP are sent to its owner alone.')
            end
            ui.Label('Exact HP And MP (Puppetmaster)')
            imgui.Checkbox('##pet.3', options.exactAutomaton)
            if imgui.IsItemHovered() then
                imgui.SetTooltip('Shows your automaton\'s HP and MP as numbers rather than percentages.\nOnly applies while you are a puppetmaster; other pets always show percentages.')
            end
            imgui.EndTabItem()
        end
    end,
    -- The pets are listed by the party window, under the party: there is no window here to draw
    NoWindow = true,
    DrawMain = function(options, gOptions)
        settings = options
    end,
}

-- Whether the tool is switched on, as far as is known: its settings are seen when they are loaded
function pet.IsEnabled()
    return settings ~= nil and settings.isEnabled[1] == true
end

-- The pets the tool would show now; with sample set, as it shows them while its window is arranged
---@return PetInfo[]
function pet.List(sample)
    if settings == nil then
        return { }
    end
    if sample then
        return GatherSamplePets(settings)
    end
    return GetPlayerEntity() ~= nil and GatherPets(settings) or { }
end

return pet
