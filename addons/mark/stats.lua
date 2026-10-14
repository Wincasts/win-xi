-- Per-character hunting database. Persist aggregates; discard unfinished samples on any tracking gap.
-- Counts are observations, not ownership/party credit. Loot packets identify their source exactly.
local stats = {};
local function key(zone, name) return ('%d:%s'):format(zone, name); end
local function number(value) return type(value) == 'number' and value >= 0 and value < math.huge; end
local function aggregate() return { count = 0, total = 0, phTotal = 0 }; end

function stats.Prepare(db)
    if type(db) ~= 'table' or db.version ~= 1 or type(db.monsters) ~= 'table' then
        db = { version = 1, monsters = {} };
    end
    for k, row in pairs(db.monsters) do
        if type(row) ~= 'table' or not number(row.zone) or row.zone % 1 ~= 0 or row.zone == 0 or row.zone > 4095
            or type(row.name) ~= 'string' or k ~= key(row.zone, row.name) then
            db.monsters[k] = nil;
        else
            for _, field in ipairs({ 'phKills', 'nmKills', 'sightings', 'lootKills' }) do
                if not number(row[field]) then row[field] = 0; end
            end
            for _, field in ipairs({ 'pops', 'returns' }) do
                local sample = row[field];
                if type(sample) ~= 'table' or not number(sample.count) or not number(sample.total)
                    or not number(sample.phTotal) or (sample.count > 0 and (not number(sample.min) or not number(sample.max))) then
                    row[field] = aggregate();
                end
            end
            for _, field in ipairs({ 'lastKill', 'lastSeen' }) do
                if not number(row[field]) or row[field] > 32503680000 then row[field] = nil; end
            end
            for _, field in ipairs({ 'items', 'placeholders' }) do
                if type(row[field]) ~= 'table' then row[field] = {}; end
            end
            for id, item in pairs(row.items) do
                if type(item) ~= 'table' or not number(item.quantity) or not number(item.kills)
                    or type(id) ~= 'string' or not number(tonumber(id)) or tonumber(id) <= 0 or tonumber(id) > 65535
                    or tonumber(id) % 1 ~= 0 then row.items[id] = nil; end
            end
            for id, count in pairs(row.placeholders) do
                local index = tonumber(id);
                if type(id) ~= 'string' or not number(index) or index < 1 or index > 4095 or index % 1 ~= 0 or not number(count) then
                    row.placeholders[id] = nil;
                end
            end
        end
    end
    return db;
end

local Tracker = {};
Tracker.__index = Tracker;
function stats.New(db)
    return setmetatable({ db = db, states = {}, cycles = {}, watching = {}, presence = {}, changed = false }, Tracker);
end
function Tracker:Row(zone, name)
    local k = key(zone, name);
    local row = self.db.monsters[k];
    if row == nil then
        row = { zone = zone, name = name, phKills = 0, nmKills = 0, sightings = 0, lootKills = 0,
            pops = aggregate(), returns = aggregate(), items = {}, placeholders = {} };
        self.db.monsters[k] = row;
    end
    return row;
end
function Tracker:Reset()
    self.states, self.cycles, self.watching, self.presence = {}, {}, {}, {};
end

-- Targets is a list of { zone, name, record }. Shared PHs are read once, credited to each associated hunt.
function Tracker:Watch(zone, targets)
    if self.zone ~= zone then self:Reset(); self.zone = zone; end
    local watching = {};
    for _, target in ipairs(targets) do
        local k = key(zone, target.name);
        local function add(index, ph)
            local entries = watching[index] or {};
            watching[index] = entries;
            entries[k] = { zone = zone, name = target.name, ph = ph };
        end
        for _, index in ipairs(target.record.indices) do add(index, false); end
        for _, ph in ipairs(target.record.placeholders or {}) do add(ph.index, true); end
    end
    -- A record no longer being watched cannot produce an uninterrupted timing sample.
    local kept = {};
    for index, entries in pairs(watching) do
        for k in pairs(entries) do
            kept[k] = true;
            if not (self.watching[index] and self.watching[index][k]) then self.cycles[k] = nil; end
        end
    end
    for k in pairs(self.cycles) do if not kept[k] then self.cycles[k] = nil; end end
    for index in pairs(self.states) do if not watching[index] then self.states[index] = nil; end end
    for k in pairs(self.presence) do if not kept[k] then self.presence[k] = nil; end end
    self.watching = watching;
end

function Tracker:Death(index, now, confirmed)
    local entries = self.watching[index];
    if entries == nil then return; end
    local state = self.states[index] or {};
    self.states[index] = state;
    -- Initial corpses are not kills. A battle/loot packet can subsequently confirm that death.
    if state.kill ~= nil or (not confirmed and not state.alive) then state.dead = true; return; end
    state.alive, state.dead = false, true;
    local kill = { at = now, items = {}, loot = false };
    state.kill = kill;
    for k, target in pairs(entries) do
        local row = self:Row(target.zone, target.name);
        if target.ph then
            row.phKills = row.phKills + 1;
            local id = tostring(index);
            row.placeholders[id] = (tonumber(row.placeholders[id]) or 0) + 1;
            if not self.presence[k] then
                local cycle = self.cycles[k] or { at = now, kills = 0 };
                self.cycles[k] = cycle;
                cycle.kills = cycle.kills + 1;
            end
        else
            row.nmKills, row.lastKill = row.nmKills + 1, now;
            self.cycles[k] = nil;
        end
    end
    self.changed = true;
end

function Tracker:Observe(sights, now)
    -- Deaths first: a PH death and NM appearance in the same poll form one deterministic sample.
    for index in pairs(self.watching) do
        local sight = sights[index];
        if sight and not sight.up then self:Death(index, now, false); end
    end
    local present = {};
    for index, entries in pairs(self.watching) do
        local sight = sights[index];
        local state = self.states[index] or {};
        self.states[index] = state;
        if sight and sight.up then
            -- A death packet can precede the memory update. Do not reopen that kill immediately.
            if not state.kill or now - state.kill.at > 2 then
                for k, target in pairs(entries) do
                    if not target.ph then
                        present[k] = target;
                        if state.kill then
                            local elapsed, sample = math.max(0, now - state.kill.at), self:Row(target.zone, target.name).returns;
                            sample.count, sample.total = sample.count + 1, sample.total + elapsed;
                            sample.min, sample.max = math.min(sample.min or elapsed, elapsed), math.max(sample.max or elapsed, elapsed);
                            self.changed = true;
                        end
                    end
                end
                state.alive, state.dead, state.kill = true, false, nil;
            end
        elseif not sight then
            -- Losing an entity must not turn a rediscovered corpse into a new witnessed kill.
            state.alive = false;
        end
    end
    for k, target in pairs(present) do
        if not self.presence[k] then
            local row = self:Row(target.zone, target.name);
            row.sightings, row.lastSeen = row.sightings + 1, now;
            local cycle = self.cycles[k];
            if cycle then
                local elapsed, pop = math.max(0, now - cycle.at), row.pops;
                pop.count, pop.total, pop.phTotal = pop.count + 1, pop.total + elapsed, pop.phTotal + cycle.kills;
                pop.min, pop.max = math.min(pop.min or elapsed, elapsed), math.max(pop.max or elapsed, elapsed);
                self.cycles[k] = nil;
            end
            self.changed = true;
        end
    end
    self.presence = present;
end

function Tracker:Drop(index, item, quantity, token, now)
    if item <= 0 or quantity <= 0 or quantity > 9999 then return; end
    local entries = self.watching[index];
    if not entries then return; end
    local nm = false;
    for _, target in pairs(entries) do if not target.ph then nm = true; end end
    if not nm then return; end
    self:Death(index, now, true);
    local state = self.states[index];
    local kill = state and state.kill;
    if not kill then return; end
    -- Old pool entries are excluded by the parser. Duplicate notifications must not inflate items.
    kill.tokens = kill.tokens or {};
    if kill.tokens[token] then return; end
    kill.tokens[token] = true;
    local id = tostring(item);
    for _, target in pairs(entries) do
        if not target.ph then
            local row = self:Row(target.zone, target.name);
            local drop = row.items[id] or { quantity = 0, kills = 0 };
            row.items[id] = drop;
            drop.quantity = drop.quantity + quantity;
            if not kill.items[id] then drop.kills = drop.kills + 1; end
            if not kill.loot then row.lootKills = row.lootKills + 1; end
        end
    end
    kill.items[id], kill.loot = true, true;
    self.changed = true;
end

-- Little-endian fields from Phoenix's 0x029 battle message and 0x0D2 trophy list layouts.
local function uint(data, offset, length)
    if type(data) ~= 'string' or #data < offset + length then return nil; end
    local value = 0;
    for i = length, 1, -1 do value = value * 256 + data:byte(offset + i); end
    return value;
end
function stats.Packet(id, data)
    if id == 0x029 then
        local message = uint(data, 0x18, 2);
        if message == 6 or message == 20 or message == 113 or message == 406 or message == 605 or message == 646 then
            return { kind = 'death', index = uint(data, 0x16, 2), source = uint(data, 8, 4) };
        end
    elseif id == 0x0D2 and type(data) == 'string' and #data >= 0x1C then
        if uint(data, 0x15, 1) ~= 0 or uint(data, 0x16, 1) ~= 0 then return nil; end -- old item / container
        return { kind = 'drop', index = uint(data, 0x12, 2), source = uint(data, 8, 4),
            item = uint(data, 0x10, 2), quantity = uint(data, 4, 4),
            token = ('%d:%d:%d:%d'):format(uint(data, 8, 4), uint(data, 0x18, 4), uint(data, 0x14, 1), uint(data, 0x10, 2)) };
    end
end
return stats;
