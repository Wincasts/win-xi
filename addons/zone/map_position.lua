-- Standard client-map transforms and guarded Boussole-style floor selection.
local geometry = require('area_geometry');
local catalog = require('map_catalog');
local M = {};
local MAP_TABLE_SIG = '8A0D????????5333C05684C95774??8A5424188B7424148B7C2410B9';
local ENTRY_SIZE = 0x0E;
local function signed(value, size)
    local sign = 2 ^ (size - 1);
    return value >= sign and value - 2 ^ size or value;
end
function M.valid_transform(scale, offset_x, offset_y)
    return geometry.finite(scale) and scale ~= 0 and math.abs(scale) <= 128
        and geometry.finite(offset_x) and math.abs(offset_x) <= 32768
        and geometry.finite(offset_y) and math.abs(offset_y) <= 32768;
end
function M.new(memory)
    local reader = { memory = memory, table_ptr = 0, entries = {}, overrides = {}, floor_retry = 0 };
    function reader:refresh() self.table_ptr, self.entries, self.floor_retry, self.floor_func = 0, {}, 0, nil; end
    function reader:get_floor(position)
        local ok, floor, err = pcall(function()
            if not self.floor_func then
                if os.clock() < self.floor_retry then return nil, 'Floor selection unavailable; retrying shortly.'; end
                self.floor_retry = os.clock() + 5;
                local fn = memory.find('FFXiMain.dll', 0, '8B542408568D4424108BF18B4C2410508B44240C', 0, 0);
                local ptr = memory.find('FFXiMain.dll', 0, '8B7424148B4424108B7C240C8B0D', 0x0E, 0);
                if not fn or fn == 0 or not ptr or ptr == 0 then return nil, 'Floor signatures unavailable; multi-floor classification disabled.'; end
                local ffi = require('ffi');
                self.floor_func = ffi.cast('int32_t (__thiscall *)(void*, float, float, float)', fn);
                self.floor_pointer, self.ffi = ptr, ffi;
            end
            local pointer = memory.read_uint32(self.floor_pointer);
            if not pointer or pointer == 0 then return nil, 'Floor object pointer unavailable.'; end
            local object = memory.read_uint32(pointer);
            if not object or object == 0 then return nil, 'Floor object is null.'; end
            return tonumber(self.floor_func(self.ffi.cast('void*', object), position.x, position.z, position.y));
        end);
        if not ok then return nil, 'Floor selection failed; refusing to guess a floor.'; end
        return floor, err;
    end
    function reader:get_definition(zone, position)
        if self.live_map and catalog.maps[self.live_map] and catalog.maps[self.live_map].zone_id == zone then
            return catalog.maps[self.live_map]; -- Explicit live map override, saved per zone; never set by browsing.
        end
        local floors = catalog.primary_by_floor[zone];
        if not floors then return nil, 'No supplied maps for this zone.'; end
        local count, only = 0, nil;
        for _, map in pairs(floors) do count, only = count + 1, map; end
        -- Preserve the already-tested outdoor POC path despite extra reference-table entries.
        if count == 1 and (only.poc or (only.client_floor_count or 1) <= 1) then return only; end
        if count == 0 then return nil, 'No verified client-table index for these maps (editor only).'; end
        local floor, err = self:get_floor(position);
        if floor == nil then return nil, err; end
        if not floors[floor] then return nil, 'Current client floor has no indexed raster in the supplied pack.'; end
        return floors[floor];
    end
    function reader:set_override(zone, scale, ox, oy, key)
        local definition = key and catalog.maps[key] or (self.live_map and catalog.maps[self.live_map]) or catalog[zone];
        if not definition or definition.zone_id ~= zone or not M.valid_transform(scale, ox, oy) then return false; end
        self.overrides[definition.key] = { scale = scale, offset_x = ox, offset_y = oy,
            floor_id = definition.floor_id, source = 'manual override (unverified)' };
        return true;
    end
    function reader:get_entry(zone, key)
        local definition = key and catalog.maps[key] or catalog[zone];
        if not definition or definition.zone_id ~= zone then return nil, 'No supplied maps for this zone.'; end
        if self.overrides[definition.key] then return self.overrides[definition.key]; end
        if self.entries[definition.key] then return self.entries[definition.key]; end
        if not definition.table_index then return nil, 'No matching client table index: editor-only map.'; end
        local ok, entry, err = pcall(function()
            if self.table_ptr == 0 then
                local address = memory.find('FFXiMain.dll', 0, MAP_TABLE_SIG, 0, 0);
                if not address or address == 0 then return nil, 'Map-table signature not found.'; end
                self.table_ptr = memory.read_uint32(address + 0x1C);
                if not self.table_ptr or self.table_ptr == 0 then self.table_ptr = 0; return nil, 'Map-table pointer is null.'; end
            end
            local base = self.table_ptr + definition.table_index * ENTRY_SIZE;
            local actual_zone, floor = memory.read_uint16(base), memory.read_uint8(base + 2);
            if actual_zone ~= zone or floor ~= definition.floor_id then
                return nil, 'Client map entry does not match the expected zone/floor; refusing transform.';
            end
            local scale = signed(memory.read_uint8(base + 5), 8);
            local ox, oy = signed(memory.read_uint16(base + 10), 16), signed(memory.read_uint16(base + 12), 16);
            if not M.valid_transform(scale, ox, oy) then return nil, 'Client map transform has an invalid scale/offset.'; end
            return { scale = scale, offset_x = ox, offset_y = oy, floor_id = floor, table_index = definition.table_index,
                source = 'client map table (alignment unverified)' };
        end);
        if not ok then return nil, 'Map-table memory read failed.'; end
        if entry then self.entries[definition.key] = entry; end
        return entry, err;
    end
    return reader;
end
local function read_position()
    local player = GetPlayerEntity();
    if not player or not player.Movement or not player.Movement.LocalPosition then return nil; end
    local p = player.Movement.LocalPosition;
    return p.X, p.Y, p.Z;
end
function M.player_position()
    local ok, x, y, z = pcall(read_position);
    if not ok or not geometry.finite(x) or not geometry.finite(y) or not geometry.finite(z) then return nil, 'Player position unavailable.'; end
    return { x = x, y = y, z = z }; -- X/Y horizontal, Z elevation, matching Boussole.
end
return M;
