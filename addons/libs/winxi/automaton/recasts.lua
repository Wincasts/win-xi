-- Observed automaton timers for the cooldowns addon. No IPC or dependency on Puppet being loaded.
local predict = require('winxi.automaton.predict')
local tracker = require('winxi.automaton.tracker')
local packets = require('winxi.packets')
local recasts = {}
local petId, ownerId
local spellTimers = {
    { kind = 'magic', name = 'Magic' },
    { kind = 'heal', name = 'Healing', element = 'light' },
    { kind = 'enfeeble', name = 'Enfeebling' },
    { kind = 'elemental', name = 'Elemental', element = 'ice' },
    { kind = 'status', name = 'Status removal', element = 'water' },
}
local elements = { [300] = 'fire', [301] = 'ice', [302] = 'wind', [303] = 'earth',
    [304] = 'thunder', [305] = 'water', [306] = 'light', [307] = 'dark' }

function recasts.Clear()
    tracker.Clear()
    petId, ownerId = nil, nil
end

local function Pet()
    local memory = AshitaCore:GetMemoryManager()
    local owner = memory:GetParty():GetMemberServerId(0)
    local pet
    if memory:GetPlayer():GetMainJob() == 18 and type(GetEntity) == 'function' then
        local me = GetEntity(memory:GetParty():GetMemberTargetIndex(0))
        if me and me.PetTargetIndex and me.PetTargetIndex ~= 0 then pet = GetEntity(me.PetTargetIndex) end
    end
    local id = pet and pet.ServerId
    if owner ~= ownerId or id ~= petId then
        tracker.Clear()
        ownerId, petId = owner, id
    end
    return pet
end

-- Parts are cached in character settings, just as in Puppet: the server does not resend them on load.
-- Return true only when that cache changed.
function recasts.Packet(e, parts)
    if e.id == 0x00A then recasts.Clear(); return false end
    if e.id ~= 0x044 and e.id ~= packets.inbound.action.id then return false end
    local pet = Pet()
    local data = e.data_modified or e.data
    if e.id == 0x044 and type(data) == 'string' and #data >= 0x7A
        and struct.unpack('B', data, 0x04 + 1) == 18 then
        local head = struct.unpack('B', data, 0x08 + 1)
        local frame = struct.unpack('B', data, 0x09 + 1)
        local attachments = {}
        for slot = 0, 11 do
            local id = struct.unpack('B', data, 0x0A + slot + 1)
            if id ~= 0 then attachments[#attachments + 1] = id end
        end
        local changed = parts.head ~= head or parts.frame ~= frame
            or table.concat(parts.attachments or {}, ',') ~= table.concat(attachments, ',')
        parts.head, parts.frame, parts.attachments = head, frame, attachments
        return changed
    elseif pet and e.id == packets.inbound.action.id and e.data_raw ~= nil then
        -- The action bit parser requires Ashita's raw packet buffer, not data/data_modified strings.
        local action = packets.inbound.action.parse(e.data_raw)
        if action then tracker.Action(action, pet.ServerId) end
    end
    return false
end

function recasts.Timers(parts)
    local pet = Pet()
    if not pet then return {} end
    local player = AshitaCore:GetMemoryManager():GetPlayer()
    local maneuvers, fitted = {}, {}
    for _, status in pairs(player:GetBuffs() or {}) do
        local element = elements[status]
        if element then maneuvers[element] = (maneuvers[element] or 0) + 1 end
    end
    for _, id in ipairs(parts.attachments or {}) do fitted[id] = true end
    local state = { head = parts.head, frame = parts.frame, attachments = fitted,
        maneuvers = maneuvers, hpp = pet.HPPercent, mpp = player:GetPetMPPercent(), since = tracker.Since }
    local rows = predict.Priority(state)
    local timers = {}
    local durations = predict.SpellTimers(state)
    if durations then
        for _, spell in ipairs(spellTimers) do
            local since = tracker.Since(spell.kind)
            local duration = durations[spell.kind]
            if since ~= nil and duration and duration > since then
                timers[#timers + 1] = { name = spell.name, kind = 'spell', element = spell.element,
                    timer = math.ceil((duration - since) * 60) }
            end
        end
    end
    for _, row in ipairs(rows) do
        if row.section == 'cooldown' and row.state == 'waiting' then
            timers[#timers + 1] = { name = row.name, timer = math.ceil(row.wait * 60), element = row.element }
        end
    end
    return timers
end

function recasts.Samples()
    return { { name = 'Magic', timer = 1080, kind = 'spell' },
        { name = 'Healing', timer = 420, kind = 'spell', element = 'light' },
        { name = 'Enfeebling', timer = 1560, kind = 'spell' },
        { name = 'Bash', timer = 8520, element = 'earth' },
        { name = 'Shot', timer = 420, element = 'wind' },
        { name = 'Provoke', timer = 1440, element = 'fire' },
        { name = 'Flash', timer = 240, element = 'light' } }
end

return recasts
