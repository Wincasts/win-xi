local ffxi = {}

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

return ffxi
