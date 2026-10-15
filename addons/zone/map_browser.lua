-- Browsing is independent of live detection. Used by UI and pure tests.
local M = {};
function M.new(catalog)
    local b = { catalog = catalog, follow = { true }, zone_id = nil, map_key = nil };
    function b:choose_zone(zone)
        if not self.catalog[zone] then return false; end
        self.follow[1], self.zone_id, self.map_key = false, zone, self.catalog[zone].key;
        return true;
    end
    function b:choose_map(key)
        local map = self.catalog.maps[key];
        if not map then return false; end
        self.follow[1], self.zone_id, self.map_key = false, map.zone_id, key;
        return true;
    end
    function b:sync(zone, key)
        if self.follow[1] then
            local map = self.catalog.maps[key or ''] or self.catalog[zone];
            self.zone_id, self.map_key = zone, map and map.key or nil;
        elseif not self.map_key then
            self:choose_zone(self.catalog.zones[1].id);
        end
        return self.catalog.maps[self.map_key or ''];
    end
    function b:is_live(state)
        local key = state.map_key or (self.catalog[state.zone] and self.catalog[state.zone].key);
        return self.map_key ~= nil and self.map_key == key;
    end
    return b;
end
return M;
