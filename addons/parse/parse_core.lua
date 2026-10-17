-- Pure accounting. Entity keys, never display names, own the data. Presentation grouping
-- is reversible: changing pet/skillchain options cannot change recorded observations.
local M = {}
local Core = {}; Core.__index = Core
local function bucket()
    return { damage = 0, hits = 0, misses = 0, excluded = 0, criticals = 0, count = 0 }
end
local function add(to, from)
    for key, value in pairs(from) do to[key] = (to[key] or 0) + value end
end
function M.New()
    return setmetatable({ actors = {}, unknown = {}, history = {}, history_next = 1, running = true,
        elapsed = 0, revision = 0, event_count = 0 }, Core)
end
function Core:Reset(now)
    self.actors, self.unknown, self.history = {}, {}, {}
    self.history_next, self.elapsed, self.since, self.event_count = 1, 0, nil, 0
    self.running, self.revision = true, self.revision + 1
end
function Core:Pause(now)
    if not self.running then return end
    if self.since then self.elapsed = self.elapsed + math.max(0, now - self.since) end
    self.since, self.running, self.revision = nil, false, self.revision + 1
end
function Core:Resume(now)
    if self.running then return end
    self.running = true
    if self.event_count > 0 then self.since = now end
    self.revision = self.revision + 1
end
function Core:Duration(now)
    return self.elapsed + (self.running and self.since and math.max(0, now - self.since) or 0)
end
function Core:Record(events, unknown, now)
    if not self.running then return end
    for key, count in pairs(unknown or {}) do self.unknown[key] = (self.unknown[key] or 0) + count end
    for _, event in ipairs(events) do
        if not self.since then self.since = now end
        local id = event.actor.key
        local actor = self.actors[id]
        if not actor then
            actor = { info = event.actor, targets = {} }
            self.actors[id] = actor
        end
        local target = actor.targets[event.target.key]
        if not target then
            target = { info = event.target, categories = {}, abilities = {} }
            actor.targets[event.target.key] = target
        end
        local stat = bucket()
        stat.damage, stat.count = event.damage or 0, event.count or 1
        stat.hits = event.hits or (event.outcome == 'hit' and 1 or 0)
        stat.misses = event.misses or (event.outcome == 'miss' and 1 or 0)
        stat.excluded = event.excluded or (event.outcome == 'excluded' and 1 or 0)
        stat.criticals = event.critical and 1 or 0
        local cat = event.category
        target.categories[cat] = target.categories[cat] or bucket()
        add(target.categories[cat], stat)
        local ability = cat .. ':' .. tostring(event.ability_category) .. ':' .. tostring(event.ability)
        target.abilities[ability] = target.abilities[ability] or bucket()
        add(target.abilities[ability], stat)
        -- Bounded diagnostic history, including both identities and the exact result.
        self.history[self.history_next] = { time = now, event = event }
        self.history_next = self.history_next % 128 + 1
        self.event_count = self.event_count + 1
    end
    self.revision = self.revision + 1
end
function M.Rate(stat)
    local trials = stat.hits + stat.misses
    return trials > 0 and stat.hits / trials * 100 or nil
end
function M.MeleeRate(row)
    local melee, ws = row.categories.melee or {}, row.categories.ws_hits or {}
    return M.Rate({ hits = (melee.hits or 0) + (ws.hits or 0), misses = (melee.misses or 0) + (ws.misses or 0) })
end
function Core:Snapshot(now, options)
    options = options or {}
    local rows, total = {}, 0
    for key, actor in pairs(self.actors) do
        local info = actor.info
        local group = options.combinePets and info.owner_key or key
        local row = rows[group]
        if not row then
            row = { key = group, name = group ~= key and (info.owner_name or tostring(info.owner_id)) or info.name,
                damage = 0, categories = {}, abilities = {}, members = {} }
            rows[group] = row
        end
        row.members[key] = true
        for targetKey, target in pairs(actor.targets) do
            if not options.target or targetKey == options.target then
                for category, stat in pairs(target.categories) do
                    if options.includeSkillchains ~= false or category ~= 'skillchain' then
                        row.categories[category] = row.categories[category] or bucket()
                        add(row.categories[category], stat)
                        row.damage = row.damage + stat.damage
                    end
                end
                for ability, stat in pairs(target.abilities) do
                    if options.includeSkillchains ~= false or ability:sub(1, 11) ~= 'skillchain:' then
                        row.abilities[ability] = row.abilities[ability] or bucket()
                        add(row.abilities[ability], stat)
                    end
                end
            end
        end
    end
    local list, duration = {}, self:Duration(now)
    for _, row in pairs(rows) do
        total = total + row.damage
        row.dps = duration > 0 and row.damage / duration or nil
        list[#list + 1] = row
    end
    for _, row in ipairs(list) do row.share = total > 0 and row.damage / total * 100 or nil end
    table.sort(list, function(a, b) return a.damage == b.damage and a.key < b.key or a.damage > b.damage end)
    return { rows = list, total = total, duration = duration, running = self.running }
end
return M
