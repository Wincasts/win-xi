-- Live entity resolution is isolated from decoding/accounting and never falls back to
-- entity zero. A packet gets one roster snapshot; pets are checked before mob flags.
local bit = require('bit')
local M = {}
function M.Resolver(memory, epoch)
    local entities, party = memory:GetEntity(), memory:GetParty()
    local roster, companions, cache = {}, {}, {}
    local function key(id) return tostring(epoch) .. ':' .. string.format('%.0f', id) end
    for i = 0, 17 do
        -- Slot zero is the local player even when solo; its party-active flag
        -- is not required (the party overlay follows the same rule).
        if i == 0 or party:GetMemberIsActive(i) == 1 then
            local id, index = party:GetMemberServerId(i), party:GetMemberTargetIndex(i)
            if id and id ~= 0 and index and index > 0 then
                local name = party:GetMemberName(i)
                local kind = i == 0 and 'me' or i > 5 and 'alliance' or 'party'
                if entities:GetTrustOwnerTargetIndex(index) ~= 0 then kind = 'trust' end
                roster[id] = { kind = kind, name = name }
                for _, companion in ipairs({
                    { entities:GetPetTargetIndex(index), 'pet' },
                    { entities:GetFellowTargetIndex(index), 'fellow' },
                }) do
                    local companionIndex = companion[1]
                    if companionIndex and companionIndex > 0 then
                        local companionId = entities:GetServerId(companionIndex)
                        if companionId and companionId ~= 0 then
                            companions[companionId] = { kind = companion[2], owner_id = id,
                                owner_key = key(id), owner_name = name }
                        end
                    end
                end
            end
        end
    end
    return function(id)
        if cache[id] then return cache[id] end
        local info = { id = id, key = key(id), name = ('Unknown [%08X]'):format(id), kind = 'other' }
        local index = bit.band(id, 0x7FF)
        if index == 0 or entities:GetServerId(index) ~= id then
            index = nil
            for at = 1, 2303 do
                if entities:GetServerId(at) == id then index = at; break end
            end
        end
        if index then
            info.name = entities:GetName(index) or info.name
            local known = roster[id] or companions[id]
            if known then
                for field, value in pairs(known) do info[field] = value end
            elseif bit.band(entities:GetSpawnFlags(index), 0x10) ~= 0 then
                info.kind = 'mob'
            end
        end
        cache[id] = info
        return info
    end
end
return M
