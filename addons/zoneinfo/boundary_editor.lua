-- Editable feature polygons, validated text persistence (never executes saved Lua).
local geometry = require('area_geometry');
local M = {};
local function copy(polygon)
    local result = {};
    for i, p in ipairs(polygon) do result[i] = { p[1], p[2] }; end
    return result;
end
local function same(a, b)
    if #a ~= #b then return false; end
    for i, p in ipairs(a) do
        if math.abs(p[1] - b[i][1]) > 0.000001 or math.abs(p[2] - b[i][2]) > 0.000001 then return false; end
    end
    return true;
end
local function cross(a, b, c)
    return (b[1] - a[1]) * (c[2] - a[2]) - (b[2] - a[2]) * (c[1] - a[1]);
end
local function on(a, b, p)
    return math.abs(cross(a, b, p)) < 0.000001 and p[1] >= math.min(a[1], b[1])
        and p[1] <= math.max(a[1], b[1]) and p[2] >= math.min(a[2], b[2]) and p[2] <= math.max(a[2], b[2]);
end
local function intersects(a, b, c, d)
    return (cross(a, b, c) * cross(a, b, d) < 0 and cross(c, d, a) * cross(c, d, b) < 0)
        or on(a, b, c) or on(a, b, d) or on(c, d, a) or on(c, d, b);
end
function M.valid(polygon)
    if type(polygon) ~= 'table' or #polygon < 3 or #polygon > 64 then return false; end
    for _, p in ipairs(polygon) do
        if type(p) ~= 'table' or not geometry.finite(p[1]) or not geometry.finite(p[2]) then return false; end
    end
    local area = 0;
    for i, p in ipairs(polygon) do
        if not geometry.finite(p[1]) or not geometry.finite(p[2]) or p[1] < 0 or p[1] > 512 or p[2] < 0 or p[2] > 512 then return false; end
        local q = polygon[i % #polygon + 1];
        if not q or not geometry.finite(q[1]) or not geometry.finite(q[2]) then return false; end
        if math.abs(p[1] - q[1]) + math.abs(p[2] - q[2]) < 0.01 then return false; end
        area = area + p[1] * q[2] - q[1] * p[2];
        for j = i + 1, #polygon do
            if j ~= i + 1 and not (i == 1 and j == #polygon) then
                local r, s = polygon[j], polygon[j % #polygon + 1];
                if not r or not s or not geometry.finite(r[1]) or not geometry.finite(r[2])
                    or not geometry.finite(s[1]) or not geometry.finite(s[2]) then return false; end
                if intersects(p, q, r, s) then return false; end
            end
        end
    end
    return math.abs(area) >= 1;
end

local function info(area)
    return { name = area.name or area.id, enabled = area.enabled ~= false, z_min = area.z_min, z_max = area.z_max,
        exact = area.exact == true };
end
local function same_info(a, b)
    return a.name == b.name and a.enabled == b.enabled and a.z_min == b.z_min and a.z_max == b.z_max
        and (a.exact == true) == (b.exact == true);
end
-- A height limit is a finite number of yalms, or nil for none; the lower is never above the upper.
local function valid_heights(z_min, z_max)
    if z_min ~= nil and (not geometry.finite(z_min) or math.abs(z_min) > 10000) then return false; end
    if z_max ~= nil and (not geometry.finite(z_max) or math.abs(z_max) > 10000) then return false; end
    return z_min == nil or z_max == nil or z_min <= z_max;
end
local function snapshot(area)
    local result = info(area); result.polygon = copy(area.polygon); return result;
end
local function apply(area, value)
    area.name, area.enabled, area.polygon = value.name, value.enabled, copy(value.polygon);
    area.z_min, area.z_max = value.z_min, value.z_max;
    area.exact = value.exact == true or nil;
end
local function hex(text) return (text:gsub('.', function(c) return ('%02x'):format(c:byte()); end)); end
local function unhex(text)
    if not text or #text == 0 or #text > 512 or #text % 2 ~= 0 or text:find('[^%x]') then return nil; end
    local value = text:gsub('%x%x', function(c) return string.char(tonumber(c, 16)); end);
    if value:find('[%z\1-\31\127]') then return nil; end
    return value;
end
function M.new(definitions, path)
    local catalog = definitions.maps and definitions or nil;
    definitions = catalog and catalog.maps or definitions;
    local e = { definitions = definitions, catalog = catalog, path = path, defaults = {}, default_info = {},
        history = {}, selected = nil, saved_info = {}, new = {},
        revision = 0, preview_revision = 0, dragging = nil, edit_mode = { false }, status = '', saved = {} };
    function e:register(area, is_new)
        self.defaults[area], self.saved[area], self.history[area] = copy(area.polygon), copy(area.polygon), {};
        self.default_info[area], self.saved_info[area], self.new[area] = info(area), info(area), is_new or false;
    end
    for _, definition in pairs(definitions) do
        for _, area in ipairs(definition.areas) do e:register(area); end
    end
    function e:definition(key)
        if self.catalog and type(key) == 'number' then return self.catalog[key]; end
        return self.definitions[key];
    end
    function e:select(zone, id)
        self:cancel();
        self.selected, self.vertex = nil, 1;
        local definition = self:definition(zone);
        self.map_key = definition and definition.key or zone;
        for _, area in ipairs(definition and definition.areas or {}) do
            if area.id == id then self.selected = area; return true; end
        end
        return false;
    end
    function e:dirty()
        local stamp = self.revision .. ':' .. self.preview_revision;
        if self.dirty_stamp == stamp then return self.dirty_value; end
        self.dirty_stamp, self.dirty_value = stamp, false;
        for area, saved in pairs(self.saved) do
            if self.new[area] or not same(area.polygon, saved)
                or not same_info(info(area), self.saved_info[area]) then self.dirty_value = true; break; end
        end
        return self.dirty_value;
    end
    function e:begin(index)
        if self.dragging or not self.selected or not self.selected.polygon[index] then return false; end
        self.vertex = index;
        self.dragging = { area = self.selected, index = index, before = snapshot(self.selected) };
        return true;
    end
    function e:move(x, y)
        if not self.dragging or not geometry.finite(x) or not geometry.finite(y) then return false; end
        local d = self.dragging;
        local polygon = copy(d.area.polygon);
        polygon[d.index] = { math.max(0, math.min(512, x)), math.max(0, math.min(512, y)) };
        if not M.valid(polygon) then self.status = 'Move rejected: edges must not cross or collapse.'; return false; end
        if same(polygon, d.area.polygon) then return false; end
        d.area.polygon = polygon;
        self.preview_revision = self.preview_revision + 1;
        self.status = 'Dragging vertex ' .. d.index .. ' (release to apply).';
        return true;
    end
    function e:finish()
        if not self.dragging then return false; end
        local d = self.dragging;
        self.dragging = nil;
        if same(d.before.polygon, d.area.polygon) then return false; end
        local history = self.history[d.area];
        history[#history + 1] = d.before;
        if #history > 50 then table.remove(history, 1); end
        self.revision = self.revision + 1;
        self.changed_map = self.map_key;
        self.status = 'Boundary applied. Save to keep it after reload.';
        return true;
    end
    function e:cancel()
        if self.dragging then
            apply(self.dragging.area, self.dragging.before);
            self.dragging = nil;
            self.preview_revision = self.preview_revision + 1;
        end
    end
    function e:undo()
        self:cancel();
        local history = self.selected and self.history[self.selected];
        if not history or #history == 0 then self.status = 'Nothing to undo for this area.'; return false; end
        apply(self.selected, table.remove(history));
        self.vertex = math.min(self.vertex or 1, #self.selected.polygon);
        self.revision = self.revision + 1;
        self.changed_map = self.map_key;
        self.status = 'Undone; Save to persist this boundary.';
        return true;
    end
    function e:restore()
        self:cancel();
        if not self.selected then return false; end
        local current, default = info(self.selected), self.default_info[self.selected];
        if same(self.selected.polygon, self.defaults[self.selected]) and same_info(current, default) then return false; end
        local history = self.history[self.selected];
        history[#history + 1] = snapshot(self.selected);
        if #history > 50 then table.remove(history, 1); end
        apply(self.selected, { polygon = self.defaults[self.selected], name = default.name, enabled = default.enabled,
            z_min = default.z_min, z_max = default.z_max, exact = default.exact });
        self.vertex = math.min(self.vertex or 1, #self.selected.polygon);
        self.revision = self.revision + 1;
        self.changed_map = self.map_key;
        self.status = 'Default restored for selected area; Save to persist.';
        return true;
    end
    function e:vertices(insert)
        self:cancel();
        if not self.selected then return false; end
        local polygon = copy(self.selected.polygon);
        local index = math.max(1, math.min(self.vertex or 1, #polygon));
        if insert then
            if #polygon >= 64 then self.status = 'Maximum 64 vertices.'; return false; end
            local a, b = polygon[index], polygon[index % #polygon + 1];
            table.insert(polygon, index + 1, { (a[1] + b[1]) / 2, (a[2] + b[2]) / 2 });
            index = index + 1;
        else
            if #polygon <= 3 then self.status = 'A polygon needs at least three vertices.'; return false; end
            table.remove(polygon, index); index = math.min(index, #polygon);
        end
        if not M.valid(polygon) then self.status = 'Vertex change would cross or collapse edges.'; return false; end
        local history = self.history[self.selected]; history[#history + 1] = snapshot(self.selected);
        if #history > 50 then table.remove(history, 1); end
        self.selected.polygon, self.vertex = polygon, index;
        self.revision, self.changed_map = self.revision + 1, self.map_key;
        self.status = 'Vertices updated; Save to persist.';
        return true;
    end
    function e:configure(name, enabled)
        self:cancel();
        if not self.selected or type(name) ~= 'string' or #name == 0 or #name > 256 or name:find('[%z\1-\31\127]') then
            self.status = 'Use a nonempty name (maximum 256 bytes, no control characters).'; return false;
        end
        local previous = info(self.selected);
        if previous.name == name and previous.enabled == enabled then return false; end
        local history = self.history[self.selected]; history[#history + 1] = snapshot(self.selected);
        if #history > 50 then table.remove(history, 1); end
        self.selected.name, self.selected.enabled = name, enabled;
        self.revision = self.revision + 1;
        self.changed_map = self.map_key;
        self.status = 'Area name/detection updated; Save to persist.';
        return true;
    end
    -- The band of elevation the selected area is announced in; nil leaves that side open.
    -- A building is exact: announced on stepping inside it, with no approach distance.
    function e:set_exact(exact)
        self:cancel();
        exact = exact == true;
        if not self.selected or (self.selected.exact == true) == exact then return false; end
        local history = self.history[self.selected]; history[#history + 1] = snapshot(self.selected);
        if #history > 50 then table.remove(history, 1); end
        self.selected.exact = exact or nil;
        self.revision = self.revision + 1;
        self.changed_map = self.map_key;
        self.status = 'Boundary kind updated; Save to persist.';
        return true;
    end
    function e:limit(z_min, z_max)
        self:cancel();
        if not self.selected or not valid_heights(z_min, z_max) then
            self.status = 'Use finite heights, with the minimum no higher than the maximum.'; return false;
        end
        if self.selected.z_min == z_min and self.selected.z_max == z_max then return false; end
        local history = self.history[self.selected]; history[#history + 1] = snapshot(self.selected);
        if #history > 50 then table.remove(history, 1); end
        self.selected.z_min, self.selected.z_max = z_min, z_max;
        self.revision = self.revision + 1;
        self.changed_map = self.map_key;
        self.status = 'Height limits updated; Save to persist.';
        return true;
    end
    function e:add(key, name)
        local definition = self:definition(key);
        if not self.catalog or not definition or #definition.areas >= 256 or type(name) ~= 'string' or #name == 0 or #name > 256 or name:find('[%z\1-\31\127]') then return false; end
        self:cancel();
        local n, ids = 1, {};
        for _, area in ipairs(definition.areas) do ids[area.id] = true; end
        while ids['custom_' .. n] do n = n + 1; end
        local area = { id = 'custom_' .. n, name = name, enabled = true, custom = true,
            provenance = 'user_authored', polygon = { { 224, 224 }, { 288, 224 }, { 288, 288 }, { 224, 288 } } };
        definition.areas[#definition.areas + 1] = area; self:register(area, true);
        self.map_key, self.selected, self.vertex = definition.key, area, 1;
        self.revision = self.revision + 1; self.changed_map = self.map_key;
        self.status = 'Area added at map center; drag vertices and Save.';
        return true;
    end
    function e:encode()
        local lines, zones = { self.catalog and 'zoneinfo-boundaries-v2' or 'zoneinfo-boundaries-v1' }, {};
        for zone in pairs(self.definitions) do zones[#zones + 1] = zone; end
        table.sort(zones);
        for _, zone in ipairs(zones) do
            local ordered = {};
            for _, area in ipairs(self.definitions[zone].areas) do ordered[#ordered + 1] = area; end
            table.sort(ordered, function(a, b) return a.id < b.id; end);
            for _, area in ipairs(ordered) do
                local current, default = info(area), self.default_info[area];
                if area.custom or not same(area.polygon, self.defaults[area]) or (self.catalog and not same_info(current, default)) then
                    local fields = { tostring(zone), area.id };
                    if self.catalog then
                        fields[#fields + 1], fields[#fields + 2] = current.enabled and '1' or '0', hex(current.name);
                        -- Optional, and only written for an area that has a limit: h:<min>:<max>, ~ for an open side.
                        if current.z_min ~= nil or current.z_max ~= nil then
                            fields[#fields + 1] = ('h:%s:%s'):format(current.z_min and ('%.3f'):format(current.z_min) or '~',
                                current.z_max and ('%.3f'):format(current.z_max) or '~');
                        end
                        -- Optional too: e:1 or e:0, written where it is not the built-in kind (a hand-added
                        -- area has no built-in kind, and is written when exact).
                        if (area.custom and current.exact) or (not area.custom and current.exact ~= default.exact) then
                            fields[#fields + 1] = current.exact and 'e:1' or 'e:0';
                        end
                    end
                    for _, p in ipairs(area.polygon) do
                        fields[#fields + 1], fields[#fields + 2] = ('%.6f'):format(p[1]), ('%.6f'):format(p[2]);
                    end
                    lines[#lines + 1] = table.concat(fields, ' ');
                end
            end
        end
        return table.concat(lines, '\n') .. '\n';
    end
    function e:decode(text)
        local limit = self.catalog and 2097152 or 65536;
        if type(text) ~= 'string' or #text > limit then return false, 'Boundary file too large/invalid.'; end
        local lines = {};
        for line in text:gmatch('[^\r\n]+') do lines[#lines + 1] = line; end
        local v2 = lines[1] == 'zoneinfo-boundaries-v2';
        if lines[1] ~= 'zoneinfo-boundaries-v1' and not (v2 and self.catalog) then return false, 'Unsupported boundary file version.'; end
        local pending, seen, additions = {}, {}, {};
        for i = 2, #lines do
            local fields = {};
            for field in lines[i]:gmatch('%S+') do fields[#fields + 1] = field; end
            local definition = self:definition(v2 and fields[1] or tonumber(fields[1]));
            local selected;
            for _, area in ipairs(definition and definition.areas or {}) do if area.id == fields[2] then selected = area; end end
            local token = (fields[1] or '') .. ':' .. (fields[2] or '');
            if not definition or seen[token] then return false, 'Unknown/duplicate map or area.'; end
            seen[token] = true;
            if not selected then
                if not v2 or not fields[2] or not fields[2]:match('^custom_[1-9]%d*$') then return false, 'Unknown area.'; end
                additions[definition] = (additions[definition] or 0) + 1;
                if #definition.areas + additions[definition] > 256 then return false, 'Too many areas on one map.'; end
                selected = { id = fields[2], custom = true, provenance = 'user_authored' };
            end
            local start = v2 and 5 or 3;
            local z_min, z_max, exact;
            -- Without an e: field an area keeps its built-in kind; older files have none.
            if self.default_info[selected] then exact = self.default_info[selected].exact; end
            local seen = {};
            while v2 and fields[5] and fields[5]:match('^%a:') do
                local field = table.remove(fields, 5);
                local kind = field:sub(1, 1);
                if seen[kind] then return false, 'Repeated saved field.'; end
                seen[kind] = true;
                if kind == 'e' then
                    if field ~= 'e:1' and field ~= 'e:0' then return false, 'Invalid saved boundary kind.'; end
                    exact = field == 'e:1';
                elseif kind == 'h' then
                    local low, high = field:match('^h:([^:]+):([^:]+)$');
                    if not low then return false, 'Invalid saved height limits.'; end
                    if low ~= '~' then z_min = tonumber(low); if not z_min then return false, 'Invalid saved height limits.'; end end
                    if high ~= '~' then z_max = tonumber(high); if not z_max then return false, 'Invalid saved height limits.'; end end
                    if (z_min == nil and z_max == nil) or not valid_heights(z_min, z_max) then return false, 'Invalid saved height limits.'; end
                else
                    return false, 'Unknown saved field.';
                end
            end
            if (not v2 and #fields ~= 2 + 2 * #self.defaults[selected]) or (v2 and (#fields < 10 or (#fields - 4) % 2 ~= 0)) then
                return false, 'Incorrect vertex count.';
            end
            local polygon = {};
            for j = start, #fields, 2 do polygon[#polygon + 1] = { tonumber(fields[j]), tonumber(fields[j + 1]) }; end
            if not M.valid(polygon) then return false, 'Invalid saved polygon (crossing, collapsed or outside map).'; end
            local name = selected.name or selected.id;
            if v2 then name = unhex(fields[4]); end
            if not name or (v2 and fields[3] ~= '0' and fields[3] ~= '1') then return false, 'Invalid saved name/detection flag.'; end
            if not v2 and self.default_info[selected] then -- The first format had no heights: the built-in ones stand.
                z_min, z_max = self.default_info[selected].z_min, self.default_info[selected].z_max;
            end
            pending[selected] = { definition = definition, polygon = polygon, name = name, z_min = z_min, z_max = z_max, exact = exact,
                enabled = v2 and fields[3] == '1' or (not v2 and selected.enabled ~= false) };
        end
        -- Commit only after validating the entire file, so one bad record cannot partly load.
        self:cancel();
        for _, definition in pairs(self.definitions) do
            for i = #definition.areas, 1, -1 do
                local area = definition.areas[i];
                if area.custom and not pending[area] then
                    table.remove(definition.areas, i);
                    self.defaults[area], self.default_info[area], self.saved[area], self.saved_info[area], self.history[area], self.new[area] = nil, nil, nil, nil, nil, nil;
                end
            end
        end
        for area, value in pairs(pending) do
            if not self.defaults[area] then
                apply(area, value); value.definition.areas[#value.definition.areas + 1] = area; self:register(area);
            end
        end
        for area, default in pairs(self.defaults) do
            local original = self.default_info[area];
            apply(area, pending[area] or { polygon = default, name = original.name, enabled = original.enabled,
                z_min = original.z_min, z_max = original.z_max, exact = original.exact });
            self.saved[area], self.saved_info[area], self.history[area], self.new[area] = copy(area.polygon), info(area), {}, false;
        end
        self.last_loaded_version = v2 and 2 or 1;
        self.revision = self.revision + 1;
        return true;
    end
    function e:load()
        local file, open_err, open_code = io.open(self.path, 'r');
        if not file then
            if open_code == 2 then return true; end -- Missing overrides means built-in defaults.
            self.status = 'Load failed: ' .. tostring(open_err);
            return false, open_err;
        end
        local text = file:read((self.catalog and 2097152 or 65536) + 1);
        file:close();
        local ok, err = self:decode(text or '');
        self.status = ok and (self.catalog and self.last_loaded_version == 1 and 'Legacy zone edits imported; Save migrates them to per-map overrides.' or 'Saved boundaries loaded.') or ('Load failed: ' .. err);
        return ok, err;
    end
    function e:save()
        if self.dragging then return false, 'Release the vertex before saving.'; end
        local temp, backup = self.path .. '.tmp', self.path .. '.bak';
        local file, err = io.open(temp, 'w');
        if not file then self.status = 'Save failed: ' .. tostring(err); return false, err; end
        local written, write_err = file:write(self:encode());
        local closed, close_err = file:close();
        if not written or not closed then
            os.remove(temp);
            self.status = 'Save failed: ' .. tostring(write_err or close_err);
            return false, self.status;
        end
        local exists = io.open(self.path, 'r');
        if exists then
            exists:close();
            local old_backup = io.open(backup, 'r');
            if old_backup then
                old_backup:close();
                local removed, remove_err = os.remove(backup);
                if not removed then os.remove(temp); self.status = 'Save failed: ' .. tostring(remove_err); return false, self.status; end
            end
            local moved, move_err = os.rename(self.path, backup);
            if not moved then os.remove(temp); self.status = 'Save failed: ' .. tostring(move_err); return false, self.status; end
        end
        local installed, install_err = os.rename(temp, self.path);
        if not installed then
            local restored, restore_err = true, nil;
            if exists then restored, restore_err = os.rename(backup, self.path); end
            os.remove(temp);
            self.status = 'Save failed: ' .. tostring(install_err);
            if not restored then self.status = self.status .. '; restore failed: ' .. tostring(restore_err) .. '. Previous file is at ' .. backup; end
            return false, self.status;
        end
        for area in pairs(self.saved) do self.saved[area], self.saved_info[area], self.new[area] = copy(area.polygon), info(area), false; end
        self.dirty_stamp = nil;
        self.status = 'Saved boundary overrides (previous file retained as .bak).';
        return true;
    end
    return e;
end
return M;
