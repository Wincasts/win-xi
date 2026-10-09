-- pets: the player's pet and the pets of the rest of their party, as lines for frames.lua to draw.
--
--     pets.Lines(sample, settings)     the lines, the player's own first; settings are the pets' own
--     pets.HandlePacket(e)             every packet in goes by this while pets are listed
--
-- A pet's HP is known as a percentage. Only its owner is told its MP and TP, so another member's pet
-- has an HP bar alone; and only a puppetmaster is told their automaton's HP and MP as figures.
--
-- With sample set, the lines are made up to two with made-up pets (the player's own, and another
-- member's if those are listed), to show how each looks while the windows are arranged.
--
-- The pets are read at most ten times a second, as the party's members are, and the same lines handed
-- back in between. The lines are kept and filled in afresh, and a percentage is only made into words
-- again when it changes.
require('common')

local pets = { }

local jobPup = 18
local partySize = 6

-- The automaton's HP and MP as last reported by the server, which sends them to its master only.
-- Nothing is known until the first report arrives (on zoning, job change, or when the automaton's state changes).
local automaton = { hp = nil, maxHp = 0, mp = nil, maxMp = 0 }

function pets.HandlePacket(e)
    -- Extended job info for puppetmaster: the automaton's current and maximum HP and MP
    if e.id == 0x044 and struct.unpack('B', e.data, 0x04 + 1) == jobPup then
        automaton.hp = struct.unpack('H', e.data, 0x68 + 1)
        automaton.maxHp = struct.unpack('H', e.data, 0x6A + 1)
        automaton.mp = struct.unpack('H', e.data, 0x6C + 1)
        automaton.maxMp = struct.unpack('H', e.data, 0x6E + 1)
    end
end

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
local function GetOwnPet(settings)
    local party = AshitaCore:GetMemoryManager():GetParty()
    local entity = GetPetEntity(party:GetMemberTargetIndex(0))
    if entity == nil then
        return nil
    end

    local player = AshitaCore:GetMemoryManager():GetPlayer()
    local pet = {
        name = entity.Name,
        hpp = entity.HPPercent,
        mpp = player:GetPetMPPercent(),
        tp = player:GetPetTP(),
    }

    -- Exact HP and MP are only known for a puppetmaster's automaton
    if settings.exactAutomaton[1] and IsPuppetmaster() then
        pet.hp = ExactValue(automaton.hp, automaton.maxHp, pet.hpp)
        pet.mp = ExactValue(automaton.mp, automaton.maxMp, pet.mpp)
    end

    return pet
end

-- The pets of the other members of the player's party who are in the same zone, added to list in party order
local function AddPartyPets(list)
    local party = AshitaCore:GetMemoryManager():GetParty()
    for i = 1, partySize - 1 do
        if party:GetMemberIsActive(i) == 1 and party:GetMemberZone(i) == party:GetMemberZone(0) then
            local entity = GetPetEntity(party:GetMemberTargetIndex(i))
            if entity ~= nil then
                list[#list + 1] = { name = entity.Name, owner = party:GetMemberName(i), hpp = entity.HPPercent }
            end
        end
    end
end

-- The pets there are: the player's own, then the other party members' where those are listed
---@return PetInfo[]
local function Gather(settings)
    local list = { }
    if GetPlayerEntity() == nil then
        return list
    end

    local own = GetOwnPet(settings)
    if own ~= nil then
        list[#list + 1] = own
    end
    if settings.showParty[1] then
        AddPartyPets(list)
    end
    return list
end

-- How many pets there are to see while the windows are arranged, counting made-up ones: enough to
-- show the player's own and how another member's looks, without a list of six
local sampleCount = 2

-- Real pets where there are any, and made-up ones to make their number up
---@return PetInfo[]
local function GatherSample(settings)
    local list = { }
    list[1] = GetPlayerEntity() and GetOwnPet(settings) or { name = 'Sample Pet', hpp = 80, mpp = 60, tp = 1200 }

    if settings.showParty[1] then
        if GetPlayerEntity() then
            AddPartyPets(list)
        end
        for i = #list + 1, sampleCount do
            list[i] = { name = ('Sample Pet %d'):format(i), owner = ('Sample %d'):format(i), hpp = 100 - i * 15 }
        end
    end
    return list
end

local refreshInterval = 0.1
local cache = { time = -1, sample = false, lines = { }, kept = { } }

function pets.Lines(sample, settings)
    local now = os.clock()
    if cache.sample == sample and now - cache.time < refreshInterval then
        return cache.lines
    end

    local lines, kept = cache.lines, cache.kept
    local list = sample and GatherSample(settings) or Gather(settings)
    for index, info in ipairs(list) do
        local line = kept[index]
        if line == nil then
            line = { isInZone = true }
            kept[index] = line
        end
        -- what is kept for a line between frames goes by its id: a pet's is its place in the list,
        -- not its name, which two pets may share
        line.name, line.serverId = info.name, -(1000 + index)
        line.hp, line.mp, line.mpp, line.tp = info.hp, info.mp, info.mpp, info.tp

        -- HP as a percentage unless the figure itself is known, and MP the same
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
    for index = #lines, #list + 1, -1 do
        lines[index] = nil
    end

    cache.time, cache.sample = now, sample
    return lines
end

return pets
