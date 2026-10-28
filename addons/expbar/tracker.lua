-- Packet gains, rather than differences in memory, survive level-ups and deaths.
-- A session starts at its first gain; idle time after that counts towards the rate.
local tracker = {}
local messages = { [8] = true, [253] = true }
local function u16(s, at)
    local a, b = s:byte(at + 1, at + 2)
    return a + b * 256
end
local function u32(s, at) return u16(s, at) + u16(s, at + 2) * 65536 end

function tracker.New()
    local self = { total = 0 }
    function self:Reset()
        self.total, self.started = 0, nil
    end
    function self:Identity(id, job)
        if id == nil or id == 0 then return false end
        if self.id ~= id or self.job ~= job then
            self:Reset()
            self.id, self.job = id, job
        end
        return true
    end
    function self:Packet(id, data, playerId, job, now)
        if not self:Identity(playerId, job) then return false end
        if id ~= 0x02D or type(data) ~= 'string' or #data < 0x1A then return false end
        if not messages[u16(data, 0x18) % 1024] or u32(data, 0x04) ~= playerId then return false end
        local amount = u32(data, 0x10)
        if amount == 0 then return false end
        self.started = self.started or now
        self.total = self.total + amount
        return true
    end
    function self:Rate(now)
        if not self.started then return 0 end
        return math.floor(self.total * 3600 / math.max(60, now - self.started) + 0.5)
    end
    return self
end
return tracker
