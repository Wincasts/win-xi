-- Who is where in the zone the player is in: the player, their party and alliance, and their target.
--
--   markers.Refresh(zone)      looks again, no more than every tenth of a second: whether it did
--   markers.List()             what was found: each { kind, x, y, z, heading, name, near }, x and y
--                              across the ground, z the height; kind 'player', 'party', 'alliance'
--                              or 'target'; heading nil where it is not known; near false for a
--                              member placed by the server's word alone
--   markers.Packet(id, data)   the server's word on where the party is (0x0A0)
--   markers.Ask(zone)          asks the server where the party is, as the game's map does when it is
--                              open (0x0D2), no more than every few seconds, and only while someone
--                              of the party is in the zone and out of sight
--   markers.Forget()           drops what the server said, as the player changes zone, and looks
--                              again at once
--
-- A member the client is showing is where the client has them. One it is not, further off, is where
-- the server last said, for as long as that is fresh: the server tells the zone's party members'
-- places when asked, which the game's own map does while it is open.
local bit = require('bit');
local markers = {};

local SPAWNED = 0x200;    -- GetRenderFlags0: the client is showing this entity
local LOOK_EVERY = 0.1;   -- seconds between looks
local ASK_EVERY = 3;      -- seconds between asks of the server
local FRESH = 10;         -- seconds the server's word is good for
local MEMBERS = 18;       -- the party (0 to 5) and the alliance's two others (6 to 17)

local list = {};
local told = {};          -- server id -> { x, y, z, zone, at }: the server's word
local nextLook, nextAsk = 0, 0;
local unseen = false;     -- someone of the party is in the zone, out of sight

local function Finite(n)
    return type(n) == 'number' and n == n and n ~= math.huge and n ~= -math.huge;
end

local function Add(count, kind, x, y, z, heading, name, near)
    count = count + 1;
    local marker = list[count];
    if marker == nil then
        marker = {};
        list[count] = marker;
    end
    marker.kind, marker.x, marker.y, marker.z, marker.heading, marker.name, marker.near = kind, x, y, z, heading, name, near;
    return count;
end

-- An entity the client is showing: where it is, the way it faces
local function Seen(entities, index)
    if index == nil or index == 0 or bit.band(entities:GetRenderFlags0(index) or 0, SPAWNED) == 0 then
        return nil;
    end
    local x, y, z = entities:GetLocalPositionX(index), entities:GetLocalPositionY(index), entities:GetLocalPositionZ(index);
    if not Finite(x) or not Finite(y) or not Finite(z) then
        return nil;
    end
    return x, y, z, entities:GetHeading(index);
end

function markers.Refresh(zone)
    local now = os.clock();
    if now < nextLook then
        return false;
    end
    nextLook = now + LOOK_EVERY;
    local count = 0;
    unseen = false;
    local ok = pcall(function()
        local memory = AshitaCore:GetMemoryManager();
        local party, entities = memory:GetParty(), memory:GetEntity();
        for i = 0, MEMBERS - 1 do
            if (i == 0 or party:GetMemberIsActive(i) == 1) and party:GetMemberZone(i) == zone then
                local kind = i == 0 and 'player' or (i < 6 and 'party' or 'alliance');
                local name = party:GetMemberName(i);
                local x, y, z, heading = Seen(entities, party:GetMemberTargetIndex(i));
                if x ~= nil then
                    count = Add(count, kind, x, y, z, heading, name, true);
                elseif i > 0 then
                    unseen = true;
                    local word = told[party:GetMemberServerId(i)];
                    if word ~= nil and word.zone == zone and now - word.at <= FRESH then
                        count = Add(count, kind, word.x, word.y, word.z, nil, name, false);
                    end
                end
            end
        end
        local target = memory:GetTarget();
        local index = target and target:GetTargetIndex(0) or 0;
        if index ~= party:GetMemberTargetIndex(0) then
            local x, y, z, heading = Seen(entities, index);
            if x ~= nil then
                count = Add(count, 'target', x, y, z, heading, entities:GetName(index), true);
            end
        end
    end);
    if not ok then
        count = 0;
    end
    for i = #list, count + 1, -1 do
        list[i] = nil;
    end
    return true;
end

function markers.List()
    return list;
end

-- 0x0A0: the member's server id, their zone, and where they are as the server has it: x across,
-- y the height, z the other way across
function markers.Packet(id, data)
    if id ~= 0x0A0 or data == nil or #data < 0x18 then
        return;
    end
    local who = struct.unpack('I', data, 0x04 + 1);
    local zone = struct.unpack('h', data, 0x08 + 1);
    local x, height, y = struct.unpack('f', data, 0x0C + 1), struct.unpack('f', data, 0x10 + 1), struct.unpack('f', data, 0x14 + 1);
    if not Finite(x) or not Finite(y) or not Finite(height) then
        return;
    end
    told[who] = { x = x, y = y, z = height, zone = zone, at = os.clock() };
end

function markers.Ask(zone)
    local now = os.clock();
    if not unseen or now < nextAsk or zone == nil or zone == 0 then
        return false;
    end
    nextAsk = now + ASK_EVERY;
    pcall(function()
        AshitaCore:GetPacketManager():AddOutgoingPacket(0x0D2, struct.pack('LL', 0, zone):totable());
    end);
    return true;
end

-- After a zone change, nothing the server said before holds
function markers.Forget()
    for who in pairs(told) do
        told[who] = nil;
    end
    nextLook, nextAsk = 0, 0;
end

return markers;
