H.load()
local roster, statuses = require('roster'), require('statuses')
local memoryManager = AshitaCore.GetMemoryManager
AshitaCore.GetMemoryManager = function(...)
    local memory = memoryManager(...)
    memory.GetParty = function() return { GetMemberIsActive = function() return 0 end } end
    memory.GetTarget = function() return {
        GetIsSubTargetActive = function() return 0 end, GetServerId = function() return 0 end,
    } end
    return memory
end
local members = roster.Members(3, true, false)
assert(#members == 6, 'organize fills the alliance with sample members')
local affected = 0
local style = { hiddenStatuses = '', priorityStatuses = '', debuffsFirst = false }
for _, member in ipairs(members) do
    if member.serverId < 0 then
        local ids = member.statusIds
        if #ids > 3 then
            affected = affected + 1
            style.debuffsFirst = false
            assert(statuses.Select(ids, style)[1] == 40, 'normal order keeps Protect first')
            style.debuffsFirst = true
            assert(statuses.Select(ids, style)[1] == ids[4], 'Debuffs First moves sample ailments ahead of buffs')
            style.debuffsFirst = false
            assert(statuses.Select(ids, style)[1] == 40, 'turning the toggle off restores sample order')
            assert(ids[1] == 40, 'preview ordering never mutates source statuses')
        end
    end
end
assert(affected == 3, 'three sample members have debuffs; the others remain buff-only')
H.print('organize sample ailments follow Debuffs First in both directions', true)
