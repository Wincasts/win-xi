-- Throttled polling is owned by zone.lua; this controller tracks one valid sample at a time.
local geometry = require('area_geometry');
local definitions = require('map_catalog');
local M = {};
local EXACT_DELAY = 0.3;

function M.new(reader)
    local controller = {
        reader = reader, tracker = geometry.new_tracker(1.0),
        state = { enabled = false, debug = false, zone = 0, approach_yalms = 30, approach_pixels = 0 },
        quiet_until = 0, announce_after = 0, queued = nil, next_map_retry = 0,
    };

    function controller:reset(now)
        geometry.reset(self.tracker);
        self.state.position, self.state.entry, self.state.map_x, self.state.map_y = nil, nil, nil, nil;
        self.state.raw_area, self.state.area, self.state.error = nil, nil, nil;
        self.state.approach_pixels, self.state.map_key, self.state.definition = 0, nil, nil;
        self.queued, self.next_map_retry = nil, 0;
        self.quiet_until = now or 0;
    end

    function controller:set_zone(zone, now, settle)
        self.state.zone = zone;
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
        s.raw_area = geometry.classify(definition.areas, x, y, nil, 0, s.approach_pixels, position.z);
        local candidate = geometry.classify(definition.areas, x, y, self.tracker.current, 3.0, s.approach_pixels, position.z);
        -- A doorway is walked through in a moment: a building is taken on the next sample but one,
        -- where open country waits a full second for the player to settle.
        local changed, stable_id = geometry.update(self.tracker, candidate and candidate.id or nil, now,
            candidate and candidate.exact and EXACT_DELAY or nil);
        s.area = nil;
        for _, area in ipairs(definition.areas) do
            if (area.id == stable_id) then s.area = area; break; end
        end
        if (changed) then
            self.queued = s.enabled and s.area or nil; -- A stable exit clears without inventing an area name.
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
