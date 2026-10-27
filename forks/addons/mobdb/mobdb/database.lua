-- An area's monsters are winxi's (winxi.mobs: winxi's mobs set, made from the server by
-- tools/build_winxi_data.py), not a folder of mobdb's own.
local mobs = require('winxi.mobs');
local database = {};

database.Load = function(self, zone, subZone)
    -- Upper bound isn't verified in client but currently legit subzones are around 1000-1030~
    -- Just an extra safety check in case signature breaks.
    if subZone < 1000 or subZone > 1299 then
        subZone = nil;
    end

    if (zone == self.CurrentZone) and (subZone == self.SubZone) then
        return;
    end

    self.CurrentZone = zone;
    self.SubZone = subZone;
    self.Names = T{};
    self.Indices = T{};
    if (zone == 0) then
        return;
    end

    local output = mobs.Zone(zone, self.SubZone);
    if (output ~= nil) then
        self.Indices = output.Indices or T{};
        self.Names = output.Names or T{};
    end
end

do
    local playerIndex = AshitaCore:GetMemoryManager():GetParty():GetMemberTargetIndex(0);
    if playerIndex ~= 0 then
        --Initialize zone/subzone. Credit to atom0s for locating signature and offsets.
        local zonePointer = ashita.memory.find(0, 0, 'A1????????668B88????????668B90????????5152E8????????A3', 0x00, 0x00);
        local offset1 = ashita.memory.read_uint32(zonePointer + 0x08);
        local offset2 = ashita.memory.read_uint32(zonePointer + 0x0F);
        local pointer = ashita.memory.read_uint32(zonePointer + 0x01);
        if (pointer ~= 0) then
            pointer = ashita.memory.read_uint32(pointer);
            if (pointer ~= 0) then
                database:Load(ashita.memory.read_uint32(pointer + offset2), ashita.memory.read_uint16(pointer + offset1));
            end
        end
    end
end

return database;