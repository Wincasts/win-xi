-- Small things asked of the game that winxi.game does not answer: where the party cursor is, and
-- what a job is called for short
local game = {}

-- Use exactly the party-cursor state that hideparty uses to restore the native frames.
-- MenuName reports the chat box while typing a diagnostic, not the party-order state.
-- This state also covers selecting a party member with <stpt>/<stal>.
function game.IsPartyRearranging()
    return game.StPartyIndex() ~= nil
end

--- Fetches the party index of your <stpt> target, if it exists.
---@return integer?
function game.StPartyIndex()
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
function game.JobAbbr(id)
    return jobs[id]
end

-- Unknown halves stay explicit; do not guess levels or reuse data from another member.
function game.JobText(main, mainLevel, sub, subLevel)
    local function part(job, level)
        if type(job) ~= 'string' or job == '' or type(level) ~= 'number'
            or level <= 0 or level ~= math.floor(level) then return '---' end
        return job .. tostring(level)
    end
    return '[' .. part(main, mainLevel) .. '/' .. part(sub, subLevel) .. ']'
end

return game
