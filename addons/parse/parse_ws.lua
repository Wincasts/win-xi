-- Experimental, single-weapon physical WS inference. A profile explicitly assumes
-- a known attempt count and no DA/TA/QA, Conserve/Save TP or other hidden TP source.
local M = {}
function M.Valid(profile)
    if type(profile) ~= 'table' then return false end
    for _, key in ipairs({ 'base', 'store', 'attempts' }) do
        if type(profile[key]) ~= 'number' or profile[key] ~= math.floor(profile[key]) then return false end
    end
    return profile.base >= 1 and profile.base <= 1000 and profile.store >= 0 and profile.store <= 300
        and profile.attempts >= 1 and profile.attempts <= 8
end
function M.Solve(tp, profile, success)
    if not M.Valid(profile) or type(tp) ~= 'number' or tp < 0 or tp >= 1000 or tp ~= math.floor(tp) then return nil, 'invalid TP/profile' end
    local candidates = {}
    for first = 0, 1 do
        for extra = 0, profile.attempts - 1 do
            local hits = first + extra
            local predicted = first * profile.base + math.floor(extra * 10 * (1 + profile.store / 100) + 0.000001)
            if predicted == tp and ((success and hits > 0) or (not success and hits == 0)) then candidates[hits] = true end
        end
    end
    local result
    for hits in pairs(candidates) do
        if result ~= nil then return nil, 'ambiguous hit count' end
        result = hits
    end
    if result == nil then return nil, 'TP does not match profile' end
    return result, profile.attempts - result
end
local Tracker = {}; Tracker.__index = Tracker
function M.New(callback) return setmetatable({ callback = callback, deaths = {} }, Tracker) end
function Tracker:Clear() self.pending, self.start, self.deaths = nil, nil, {} end
function Tracker:Finish(reason)
    local p = self.pending
    if not p then return end
    self.pending = nil
    local hits, misses
    if not reason then
        hits, misses = M.Solve(p.tp, p.profile, p.event.outcome == 'hit')
        if hits == nil then reason = misses; misses = nil end
    end
    self.callback({ actor = p.event.actor, target = p.event.target, ability = p.event.ability,
        hits = hits, misses = misses, reason = reason, tp = p.tp, profile = p.profile }, self.now)
end
function Tracker:Action(action, events, now, context, profiles)
    self.now = now
    local own = context.id
    if self.pending then
        local involved = action.actor == own
        for _, target in ipairs(action.targets) do involved = involved or target.id == own end
        if involved then self:Finish('intervening action') end
    end
    if action.actor ~= own then return end
    if action.category == 7 then
        self.start = { time = now, context = context, ability = action.targets[1] and action.targets[1].results[1] and action.targets[1].results[1].value }
        return
    end
    if action.category ~= 3 then return end
    local start = self.start; self.start = nil
    local ws
    for _, event in ipairs(events) do if event.category == 'ws' then ws = event; break end end
    if not ws then return end
    local profile = profiles[tostring(action.ability)]
    self.pending = { event = ws, time = now, context = context, profile = profile }
    if not M.Valid(profile) then self:Finish('no calibrated profile'); return end
    -- Copy settings so editing a profile cannot reinterpret an in-flight WS.
    self.pending.profile = { base = profile.base, store = profile.store, attempts = profile.attempts }
    if not start or now - start.time > 5 or start.ability ~= action.ability then self:Finish('missing/faded WS start'); return end
    if not context.safe or not start.context.safe or context.signature ~= start.context.signature then
        self:Finish(context.reason or start.context.reason or 'unsafe or changed WS context'); return
    end
    if #action.targets ~= 1 or #action.targets[1].results ~= 1 then self:Finish('multi-target/result WS'); return end
    if ws.damage <= 0 and ws.outcome ~= 'miss' then self:Finish('zero/absorbed damage'); return end
    if context.hp ~= start.context.hp then self:Finish('HP changed'); return end
    if self.deaths[ws.target.id] and now - self.deaths[ws.target.id] <= 2 then self:Finish('death/killing blow'); return end
end
function Tracker:TP(id, tp, hp, now)
    self.now = now
    local p = self.pending
    if not p or p.event.actor.id ~= id then return end
    -- Actor.id is a server ID in Parse, never a target index.
    if now <= p.time or now - p.time > 2 then self:Finish('stale/late TP update'); return end
    if hp ~= p.context.hp then self:Finish('HP changed'); return end
    if p.tp ~= nil and p.tp ~= tp then self:Finish('TP changed during observation'); return end
    if p.tp == nil then p.tp, p.tpTime = tp, now end
end
function Tracker:Death(id, now)
    self.now = now
    local count = 0
    for key, time in pairs(self.deaths) do
        if now - time > 3 then self.deaths[key] = nil else count = count + 1 end
    end
    if count >= 128 then self.deaths = {} end
    if id then self.deaths[id] = now end
    if self.pending and (id == self.pending.event.target.id or id == self.pending.event.actor.id) then self:Finish('death/killing blow') end
end
function Tracker:Tick(now, context)
    self.now = now
    local p = self.pending
    if not p then return end
    if not context.safe or context.signature ~= p.context.signature or context.hp ~= p.context.hp then self:Finish('context changed'); return end
    if now - p.time > 2 then self:Finish('TP observation timeout'); return end
    -- Wait for follow-up TP, damage and death packets rather than accepting a single
    -- immediate memory read. This remains a correlation heuristic, not server hit data.
    if p.tpTime and now - p.tpTime >= 0.4 then self:Finish() end
end
return M
