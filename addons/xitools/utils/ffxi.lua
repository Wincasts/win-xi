local bit = require('bit')
local game = require('winxi.game')
local ffxi = {}

-- Fetch an entity by its server ID. Helpful when looking up information from
-- packets, which tend to not include the entity index (since that's a client
-- thing only). Returns nil if no matching entity is found.
---@param id number
---@return Entity?
function ffxi.GetEntityByServerId(id)
    -- The entity array is 2304 items long
    for x = 0, 2303 do
        ---@type Entity
        local e = GetEntity(x)

        -- Ensure the entity is valid
        if e ~= nil and e.WarpPointer ~= 0 then
            if e.ServerId == id then
                return e
            end
        end
    end

    return nil
end

-- Shorthand method to grab an entity's name (by server id, obviously) or a
-- placeholder string if the entity can't be found.
---@param id number
---@param default_name string?
---@return string
function ffxi.GetEntityNameByServerId(id, default_name)
    local e = ffxi.GetEntityByServerId(id)

    if e ~= nil and e.Name ~= nil then
        return e.Name
    else
        return default_name or '[unknown]'
    end
end

-- Determines if a particular entity (given as a server ID) belongs to the
-- player's alliance.
---@param id number
---@return boolean
function ffxi.IsServerIdInParty(id)
    local party = AshitaCore:GetDataManager():GetParty()

    for i = 0, 17 do
        if party:GetMemberActive(i) == 1
        and party:GetMemberServerId(i) ~= 0 then
            local party_mem = GetEntity(party:GetMemberTargetIndex(i))

            if party_mem ~= nil and party_mem.ServerId == id then
                return true
            end
        end
    end

    return false
end

-- Determines if a particular pet (given as a server ID) belongs to the
-- player's alliance.
---@param id number
---@return boolean
function ffxi.IsPetServerIdInParty(id)
    local party = AshitaCore:GetDataManager():GetParty()

    for i = 0, 17 do
        if party:GetMemberActive(i) == 1
        and party:GetMemberServerId(i) ~= 0 then
            local party_mem = GetEntity(party:GetMemberTargetIndex(i))

            if party_mem ~= nil and party_mem.PetTargetIndex ~= nil then
                local party_pet = GetEntity(party_mem.PetTargetIndex)

                if party_pet ~= nil and party_pet.ServerId == id then
                    return true
                end
            end
        end
    end

    return false
end

-- What is asked of the game itself (the menu on top, whether the chat log is opened out, whether the
-- map is open, an event running, the interface hidden, and which bags the player has) is winxi's:
-- the places in memory are searched for once, there, for every addon's use.
ffxi.IsChatExpanded = game.IsChatExpanded
ffxi.GetMenuName = game.MenuName
ffxi.IsMapOpen = game.IsMapOpen
ffxi.IsEventHappening = game.IsEventHappening
ffxi.IsInterfaceHidden = game.IsInterfaceHidden
ffxi.HasBagAccess = game.HasBagAccess

--- Fetches the party index of your <stpt> target, if it exists.
---@return integer?
function ffxi.GetStPartyIndex()
    -- Courtesy of Thorny from the Ashita discord
    -- any step of the way can be empty before the game has made the party list (at the title screen)
    local ptr = AshitaCore:GetPointerManager():Get('party')
    if ptr == nil or ptr == 0 then return nil end
    ptr = ashita.memory.read_uint32(ptr)
    if ptr == 0 then return nil end
    ptr = ashita.memory.read_uint32(ptr)
    if ptr == 0 then return nil end
    local isActive = (ashita.memory.read_uint32(ptr + 0x54) ~= 0)
    if isActive then
        return ashita.memory.read_uint8(ptr + 0x50)
    else
        return nil
    end
end

local jobs = {
    [ 1] = 'WAR',
    [ 2] = 'MNK',
    [ 3] = 'WHM',
    [ 4] = 'BLM',
    [ 5] = 'RDM',
    [ 6] = 'THF',
    [ 7] = 'PLD',
    [ 8] = 'DRK',
    [ 9] = 'BST',
    [10] = 'BRD',
    [11] = 'RNG',
    [12] = 'SAM',
    [13] = 'NIN',
    [14] = 'DRG',
    [15] = 'SMN',
    [16] = 'BLU',
    [17] = 'COR',
    [18] = 'PUP',
    [19] = 'DNC',
    [20] = 'SCH',
    [21] = 'GEO',
    [22] = 'RUN',
}

---@param id integer
---@return 'WAR'|'MNK'|'WHM'|'BLM'|'RDM'|'THF'|'PLD'|'DRK'|'BST'|'BRD'|'RNG'|'SAM'|'NIN'|'DRG'|'SMN'|'BLU'|'COR'|'PUP'|'DNC'|'SCH'|'GEO'|'RUN'|nil
function ffxi.GetJobAbbr(id)
    return jobs[id]
end

---@param number integer
---@param include_unit boolean
---@return string
function ffxi.FormatXp(number, include_unit)
    if number < 10000 then
        return string.format('%4i', number)
    elseif include_unit then
        return string.format('%4.1fk', number / 1000)
    else
        return string.format('%4.1f', number / 1000)
    end
end

return ffxi
