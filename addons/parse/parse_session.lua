local packet = require('parse_packet')
local classify = require('parse_classify')
local core = require('parse_core')
local capture = require('parse_capture')
local M = {}
local Session = {}; Session.__index = Session
function M.New()
    return setmetatable({ core = core.New(), diagnostics = { packets = 0, malformed = 0, unresolved = 0 }, epoch = 1 }, Session)
end
function Session:Write(text)
    if not self.file then return false end
    local ok, err = self.file:write(text)
    if ok then ok, err = self.file:flush() end
    if not ok then self.error = tostring(err); self:CloseCapture() end
    return ok ~= nil and ok ~= false
end
function Session:CloseCapture()
    if self.file then self.file:close(); self.file = nil end
end
function Session:EndCapture(now)
    -- Freeze the offline timeline at capture-off without stopping live accounting.
    if self.file then self:Write(capture.Control('S', now)) end
    self:CloseCapture()
end
function Session:StartCapture(file, now)
    self:EndCapture(now)
    self.file = file
    if self:Write(capture.Header) then self:Reset(now) end
end
function Session:Reset(now)
    self.core:Reset(now)
    self.diagnostics = { packets = 0, malformed = 0, unresolved = 0 }
    self.error = nil
    self:Write(capture.Control('R', now))
end
function Session:Pause(now)
    self.core:Pause(now)
    self:Write(capture.Control('S', now))
end
function Session:Resume(now)
    self.core:Resume(now)
    self:Write(capture.Control('U', now))
end
function Session:Zone(now)
    self:Pause(now)
    self.epoch = self.epoch + 1
end
function Session:Process(data, now, resolve)
    if not self.core.running then return false end
    local action, err = packet.Decode(data)
    if not action then
        self.diagnostics.malformed = self.diagnostics.malformed + 1
        self.error = err
        return false
    end
    self.diagnostics.packets = self.diagnostics.packets + 1
    local identities = {}
    local function identity(id)
        if not identities[id] then
            local info = resolve(id)
            if not info then
                info = { id = id, key = tostring(self.epoch) .. ':' .. tostring(id), kind = 'other', name = 'Unresolved' }
            end
            identities[id] = info
            if info.kind == 'other' then self.diagnostics.unresolved = self.diagnostics.unresolved + 1 end
        end
        return identities[id]
    end
    local events, unknown = classify.Events(action, identity)
    self.core:Record(events, unknown, now)
    if self.file then self:Write(capture.Data(now, data, identities)) end
    return true, action, events
end
function Session:WSResult(result, now)
    if not self.core.running then return end
    local event = { actor = result.actor, target = result.target, ability = result.ability, ability_category = 3,
        category = result.hits ~= nil and 'ws_hits' or 'ws_unknown', damage = 0,
        hits = result.hits or 0, misses = result.misses or 0, excluded = result.hits == nil and 1 or 0,
        reason = result.reason, tp = result.tp, calibration = result.profile }
    self.core:Record({ event }, {}, now)
    if self.file then self:Write(capture.WS(now, result)) end
end
function Session:Replay(record)
    if record.kind == 'R' then self:Reset(record.time)
    elseif record.kind == 'S' then self:Pause(record.time)
    elseif record.kind == 'U' then self:Resume(record.time)
    elseif record.kind == 'W' then
        if not self.core.running then return false end
        local actor = self.core.actors[record.actor_key]
        local target = actor and actor.targets[record.target_key]
        if not target then return false end
        local result = { actor = actor.info, target = target.info, ability = record.ability,
            tp = record.tp >= 0 and record.tp or nil, profile = { base = record.base, store = record.store, attempts = record.attempts } }
        if record.reason == '' then
            local hits, misses = require('parse_ws').Solve(record.tp, result.profile, record.hits > 0)
            if hits == nil or hits ~= record.hits or misses ~= record.misses then return false end
            result.hits, result.misses = hits, misses
        else
            if record.hits ~= -1 or record.misses ~= -1 then return false end
            result.reason = record.reason
        end
        self:WSResult(result, record.time)
    else
        return self:Process(record.data, record.time, function(id) return record.identities[id] end)
    end
    return true
end
return M
