-- Throttled polling is owned by zone.lua; this controller tracks one valid sample at a time.
local geometry = require('area_geometry');
local definitions = require('map_catalog');
local gamedata = require('winxi.gamedata');
local kinds = gamedata.Lookup('zonekinds');      -- the chosen server's: each zone's kind
local entrances = gamedata.Lookup('entrances');  -- and its dungeon and town entrances
local M = {};
local EXACT_DELAY = 0.3;
-- An area come back to within this many seconds of leaving it is not announced again: out of a shop
-- into the square it stands in, or back over a boundary just crossed. 0 announces every return.
M.REANNOUNCE = 10;
-- How near a feature is announced, by the zone's kind: open country's features are wide, a city's
-- squares and a dungeon's rooms close together. A zone of no known kind is open country.
M.APPROACH = { outdoors = 50, city = 10, dungeon = 15 };
-- An entrance is a circle round the server's zone line, and only at about its height, so a path
-- above or below it is not taken for it. A dungeon's is tighter than open country's features; a
-- town's is wider, to be told of it as you come up to the gates.
M.ENTRANCE = { enabled = true, yalms = 20, towns = true, town_yalms = 40 };
local ENTRANCE_HEIGHT = 15;
local ENTRANCE_SLACK = 3; -- yalms kept on the way out
local ENTRANCE_SIDES = 16;

function M.kind(zone)
    local kind = kinds[zone or 0];
    return (kind == 'city' or kind == 'dungeon') and kind or 'outdoors';
end

function M.approach_yalms(state, zone)
    local by_kind = state.approach or M.APPROACH;
    return by_kind[M.kind(zone)] or M.APPROACH[M.kind(zone)];
end

-- 'Quicksand Caves Entrance 7', 'Outer Horutoto Ruins Entrance 6 (Lilac Tower)'.
function M.entrance_name(entrance)
    local name = entrance.to_name .. ' Entrance';
    if entrance.label then name = name .. ' ' .. entrance.label; end
    if entrance.place then name = name .. ' (' .. entrance.place .. ')'; end
    return name;
end

-- A zone's entrances as areas on one map, those wanted ({ enabled, yalms, towns, town_yalms }),
-- made again only when the map's transform or what is wanted changes. They are kept apart from the
-- map's own areas, which the editor saves.
local entrance_cache = setmetatable({}, { __mode = 'k' });
local function entrance_area(entry, entrance, yalms)
    local factor = math.abs(entry.scale) / 5.0;
    local radius = yalms * factor;
    local x, y = geometry.world_to_map(entry, entrance.x, entrance.y);
    local polygon = {};
    for i = 0, ENTRANCE_SIDES - 1 do
        local a = i * 2 * math.pi / ENTRANCE_SIDES;
        polygon[#polygon + 1] = { x + radius * math.cos(a), y + radius * math.sin(a) };
    end
    return { id = 'entrance_' .. entrance.id, name = M.entrance_name(entrance), enabled = true,
        entrance = entrance.kind or 'dungeon', approach = 0, margin = ENTRANCE_SLACK * factor, polygon = polygon,
        z_min = entrance.z - ENTRANCE_HEIGHT, z_max = entrance.z + ENTRANCE_HEIGHT,
        provenance = 'Phoenix server zone line' };
end
function M.entrance_areas(zone, entry, wanted)
    local list = entrances[zone or 0];
    if not list or not entry or not geometry.finite(entry.scale) or entry.scale == 0 then return nil; end
    local cached = entrance_cache[entry];
    if not (cached and cached.zone == zone and cached.enabled == wanted.enabled and cached.yalms == wanted.yalms
        and cached.towns == wanted.towns and cached.town_yalms == wanted.town_yalms) then
        local areas = {};
        for _, entrance in ipairs(list) do
            if entrance.kind == 'town' then
                if wanted.towns then areas[#areas + 1] = entrance_area(entry, entrance, wanted.town_yalms); end
            elseif wanted.enabled then
                areas[#areas + 1] = entrance_area(entry, entrance, wanted.yalms);
            end
        end
        cached = { zone = zone, enabled = wanted.enabled, yalms = wanted.yalms, towns = wanted.towns,
            town_yalms = wanted.town_yalms, areas = #areas > 0 and areas or nil };
        entrance_cache[entry] = cached;
    end
    return cached.areas;
end

-- The map's areas and, when they are wanted, the zone's entrances: one list, kept while neither changes.
local function with_entrances(state, definition, zone, entry)
    local wanted = state.entrances or M.ENTRANCE;
    local extra = M.entrance_areas(zone, entry, wanted);
    if not extra then return definition.areas; end
    local merged = state.merged;
    if merged and merged.areas == definition.areas and merged.count == #definition.areas and merged.extra == extra then
        return merged.list;
    end
    local list = {};
    for _, area in ipairs(definition.areas) do list[#list + 1] = area; end
    for _, area in ipairs(extra) do list[#list + 1] = area; end
    state.merged = { areas = definition.areas, count = #definition.areas, extra = extra, list = list };
    return list;
end

function M.new(reader)
    local controller = {
        reader = reader, tracker = geometry.new_tracker(1.0),
        state = { enabled = false, debug = false, zone = 0, approach_yalms = M.APPROACH.outdoors, approach_pixels = 0,
            approach = { outdoors = M.APPROACH.outdoors, city = M.APPROACH.city, dungeon = M.APPROACH.dungeon },
            entrances = { enabled = M.ENTRANCE.enabled, yalms = M.ENTRANCE.yalms, towns = M.ENTRANCE.towns,
                town_yalms = M.ENTRANCE.town_yalms }, reannounce = M.REANNOUNCE },
        left = {}, -- '<map key>:<area id>' -> when it was last left, for this zone
        quiet_until = 0, announce_after = 0, queued = nil, next_map_retry = 0,
    };

    function controller:reset(now)
        geometry.reset(self.tracker);
        self.state.position, self.state.entry, self.state.map_x, self.state.map_y = nil, nil, nil, nil;
        self.state.raw_area, self.state.area, self.state.error, self.state.left = nil, nil, nil, nil;
        self.state.approach_pixels, self.state.map_key, self.state.definition = 0, nil, nil;
        self.state.merged = nil;
        self.queued, self.next_map_retry = nil, 0;
        self.quiet_until = now or 0;
    end

    function controller:set_zone(zone, now, settle)
        self.state.zone = zone;
        self.left = {}; -- Arriving in a zone, its first area is always announced.
        self:reset(now);
        self.quiet_until = now + (settle or 1.0);
        self.announce_after = now + 6.0; -- Let the zone banner finish first.
    end

    function controller:invalidate(reason)
        geometry.reset(self.tracker);
        self.state.map_x, self.state.map_y, self.state.area, self.state.raw_area = nil, nil, nil, nil;
        self.state.error, self.queued = reason, nil;
    end

    function controller:sample(zone, position, now)
        if (zone ~= self.state.zone) then self:set_zone(zone, now); end
        local s = self.state;
        s.position = position;
        s.approach_yalms = M.approach_yalms(s, zone);
        if (not s.enabled and not s.debug) then return nil; end
        local definition = definitions[zone];
        if (not definition) then
            self:invalidate('No supplied maps for this zone.');
            s.entry = nil;
            return nil;
        end
        if (now < self.quiet_until) then
            self:invalidate('Waiting for zone-in position memory to settle.');
            return nil;
        end
        if (not position or not geometry.finite(position.x) or not geometry.finite(position.y)
            or not geometry.finite(position.z)) then
            self:invalidate('Player position unavailable.');
            s.position = nil;
            return nil;
        end
        if (self.reader.get_definition) then
            local err;
            definition, err = self.reader:get_definition(zone, position);
            if (not definition) then
                self:invalidate(err or 'Map/floor selection unavailable.');
                s.entry, s.map_key, s.definition = nil, nil, nil;
                return nil;
            end
        end
        if (s.map_key ~= definition.key) then
            geometry.reset(self.tracker);
            s.entry, s.area, s.raw_area, self.queued, self.next_map_retry = nil, nil, nil, nil, 0;
        end
        s.map_key, s.definition = definition.key, definition;
        if (not s.entry) then
            if (now < self.next_map_retry) then return nil; end
            local entry, err = self.reader:get_entry(zone, definition.key);
            s.entry = entry;
            if (not entry) then
                self:invalidate(err or 'Map transform unavailable.');
                self.next_map_retry = now + 5.0;
                return nil;
            end
        end
        local x, y = geometry.world_to_map(s.entry, position.x, position.y);
        if (not geometry.finite(x) or not geometry.finite(y)) then
            self:invalidate('Invalid map coordinates.');
            return nil;
        end
        s.map_x, s.map_y, s.error = x, y, nil;
        -- Convert the world-distance buffer into this map's reference pixels.
        s.approach_pixels = s.approach_yalms * math.abs(s.entry.scale) / 5.0;
        if (s.editing) then
            geometry.reset(self.tracker);
            s.area, s.raw_area, self.queued = nil, nil, nil;
            s.error = 'Dragging boundary: announcements paused until release.';
            return nil;
        end
        local areas = with_entrances(s, definition, zone, s.entry);
        s.raw_area = geometry.classify(areas, x, y, nil, 0, s.approach_pixels, position.z);
        local candidate = geometry.classify(areas, x, y, self.tracker.current, 3.0, s.approach_pixels, position.z);
        -- A doorway is walked through in a moment: a building is taken on the next sample but one,
        -- where open country waits a full second for the player to settle.
        local previous = self.tracker.initialized and self.tracker.current or nil;
        local changed, stable_id = geometry.update(self.tracker, candidate and candidate.id or nil, now,
            candidate and candidate.exact and EXACT_DELAY or nil);
        local was = s.area;
        s.area = nil;
        for _, area in ipairs(areas) do
            if (area.id == stable_id) then s.area = area; break; end
        end
        if (changed) then s.left = was; end -- The area just left, which the Edge Toast names.
        if (changed) then
            self.queued = s.enabled and s.area or nil; -- A stable exit clears without inventing an area name.
            -- Time away: an area is named again only once it has been left for long enough.
            if (previous ~= nil) then self.left[s.map_key .. ':' .. previous] = now; end
            local left = stable_id ~= nil and self.left[s.map_key .. ':' .. stable_id] or nil;
            if (left ~= nil and now - left < (s.reannounce or M.REANNOUNCE)) then self.queued = nil; end
        end
        if (self.queued and s.enabled and now >= self.announce_after) then
            local area = self.queued;
            self.queued = nil;
            return area;
        end
        return nil;
    end

    return controller;
end

return M;
