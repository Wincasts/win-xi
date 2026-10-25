-- A sign of each party and alliance member's place in it, drawn where a format has [party] (with
-- replace, in place of the game's icons). The game writes nothing of it over a name; the party's
-- memory has the members' server ids, the slots 0-5 being the player's own party and 6-17 the
-- alliance's other two, and the ids of the parties' leaders and the alliance's.
--
--   roles.Begin(memory, needed)  each frame: whether any name can have a sign; needed, whether a
--                                format has [party]
--   roles.Of(id)                 the sign (special.lua) of the player with this server id, or nil
local special = require('special');

local roles = {};

local signs = {}; -- server id -> sign, filled again each frame they are wanted

local function id(party, read)
    local value = party[read] ~= nil and party[read](party) or 0;
    return type(value) == 'number' and value or 0;
end

function roles.Begin(memory, needed)
    for key in pairs(signs) do signs[key] = nil; end
    if not needed then return false; end
    local party = memory ~= nil and memory.GetParty ~= nil and memory:GetParty() or nil;
    if (party == nil or party.GetMemberServerId == nil) then
        return false;
    end
    local leader = id(party, 'GetAlliancePartyLeaderServerId1');
    local second, third = id(party, 'GetAlliancePartyLeaderServerId2'), id(party, 'GetAlliancePartyLeaderServerId3');
    local alliance = (second ~= 0 or third ~= 0) and id(party, 'GetAllianceLeaderServerId') or 0;
    local count = 0;
    for slot = 0, 17 do
        local active = party.GetMemberIsActive == nil or party:GetMemberIsActive(slot);
        local member = (active == true or active == 1) and party:GetMemberServerId(slot) or 0;
        if (type(member) == 'number' and member ~= 0) then
            local sign;
            if (member == alliance) then
                sign = special.AllianceLeader;
            elseif (member == leader) then
                sign = special.PartyLeader;
            elseif (member == second or member == third) then
                sign = special.AlliancePartyLeader;
            else
                sign = slot < 6 and special.PartyMember or special.AllianceMember;
            end
            signs[member] = sign;
            count = count + 1;
        end
    end
    -- alone, the player is in a party of one: no sign
    if (count < 2) then
        for key in pairs(signs) do signs[key] = nil; end
    end
    return next(signs) ~= nil;
end

function roles.Of(serverId)
    return signs[serverId];
end

return roles;
