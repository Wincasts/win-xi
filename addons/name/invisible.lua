-- Who is under Invisible, by server id, as the server says it: a name over them is never drawn,
-- whatever Visibility, the whitelist or Always Show Target would have.
--
-- Phoenix sets the flag for Invisible (and a GM's hiding) in two packets, sent again whenever a status
-- effect comes or goes:
--   0x0D (another player): the u32 at 0x20 has bit 29, sent with the general update (send flags at
--        0x0A have 0x04); 0x20 in those flags is the player gone
--   0x37 (yourself): the u32 at 0x2C has bit 15
-- A player already invisible when the addon is loaded is known from their next update.
local bit = require('bit');

local invisible = {};

local hidden = {};

local PLAYER_INVISIBLE = 0x20000000;
local SELF_INVISIBLE   = 0x8000;
local GENERAL, DESPAWN = 0x04, 0x20;

local function u32(data, at)
    local a, b, c, d = data:byte(at + 1, at + 4);
    return a + b * 256 + c * 65536 + d * 16777216;
end

function invisible.HandlePacket(e)
    if e.id == 0x0A then hidden = {}; return; end -- another area
    if e.data == nil then return; end
    if e.id == 0x0D and #e.data >= 0x24 then
        local id, mask = u32(e.data, 0x04), e.data:byte(0x0A + 1);
        if bit.band(mask, DESPAWN) ~= 0 then hidden[id] = nil; return; end
        if bit.band(mask, GENERAL) ~= 0 then
            hidden[id] = bit.band(u32(e.data, 0x20), PLAYER_INVISIBLE) ~= 0 or nil;
        end
    elseif e.id == 0x37 and #e.data >= 0x30 then
        hidden[u32(e.data, 0x24)] = bit.band(u32(e.data, 0x2C), SELF_INVISIBLE) ~= 0 or nil;
    end
end

function invisible.Is(serverId)
    return serverId ~= 0 and hidden[serverId] == true;
end

return invisible;
