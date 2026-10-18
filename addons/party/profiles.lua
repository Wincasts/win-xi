-- Profiles deliberately exclude window positions, corners, links and the shared theme.
local options = require('options')
local profiles = {}
local nameLists = setmetatable({}, { __mode = 'k' })
-- Called only while the dropdown is open. Detect external edits as well as our own saves/deletes.
function profiles.Names(saved)
    local source = saved.profiles
    local kept = nameLists[source]
    if not kept then
        kept = { names = {}, members = {} }
        nameLists[source] = kept
    end
    local count, changed = 0, false
    for name in pairs(source) do
        count = count + 1
        if not kept.members[name] then changed = true end
    end
    if changed or count ~= #kept.names then
        for i = #kept.names, 1, -1 do kept.names[i] = nil end
        for name in pairs(kept.members) do kept.members[name] = nil end
        for name in pairs(source) do
            kept.names[#kept.names + 1], kept.members[name] = name, true
        end
        table.sort(kept.names)
    end
    return kept.names
end
profiles.Presets = { 'Compact', 'Healer', 'Pet job', 'Minimal' }
local presets = {
    Compact = { style = { scale = { 85 }, buffRows = { 1 } }, party = { allianceScale = { 75 } }, pets = { showParty = { false } } },
    Healer = { style = { buffSize = { 110 }, buffRows = { 2 }, buffLimit = { 32 }, debuffsFirst = { true },
        priorityStatuses = { '0,2,7,6,4,5,1' }, lowHp = { 25 } } },
    ['Pet job'] = { pets = { enabled = { true }, showParty = { true }, reserve = { 6 }, nameFormat = 'ownerPet' } },
    Minimal = { style = { barShadows = 'off', showMp = { false }, showTp = { false },
        tpFlash = { false }, buffLimit = { 8 }, buffRows = { 1 } }, pets = { showParty = { false } } },
}
local function Copy(value)
    if type(value) ~= 'table' then return value end
    local copy = T{}
    for k, v in pairs(value) do copy[k] = Copy(v) end
    return copy
end
local function Entries(fn)
    for _, tab in ipairs(options.Tabs) do
        for _, entry in ipairs(tab.entries) do
            if entry.key and entry.kind ~= 'place' then fn(entry) end
        end
    end
end
function profiles.Capture(saved)
    local snapshot = T{}
    Entries(function(entry)
        snapshot[entry.section] = snapshot[entry.section] or T{}
        snapshot[entry.section][entry.key] = Copy(saved[entry.section][entry.key])
    end)
    return snapshot
end
function profiles.Apply(saved, snapshot)
    if type(snapshot) ~= 'table' then return false end
    Entries(function(entry)
        local section = snapshot[entry.section]
        if type(section) == 'table' and section[entry.key] ~= nil then
            saved[entry.section][entry.key] = Copy(section[entry.key])
        end
    end)
    options.Complete(saved)
    require('roster').Forget()
    require('pets').Forget()
    return true
end
function profiles.Preset(saved, name) return profiles.Apply(saved, presets[name]) end
function profiles.Reset(saved, section)
    local defaults = options.Defaults()
    return profiles.Apply(saved, { [section] = defaults[section] })
end
function profiles.Save(saved, name, overwrite)
    name = (name or ''):match('^%s*(.-)%s*$')
    if name == '' or #name > 40 or name:find('[%c]') then return false, 'Use a name of 1–40 characters.' end
    saved.profiles = saved.profiles or T{}
    if saved.profiles[name] and not overwrite then return false, 'Name exists; enable overwrite to replace it.' end
    local count = 0
    for _ in pairs(saved.profiles) do count = count + 1 end
    if not saved.profiles[name] and count >= 20 then return false, 'Maximum 20 profiles; delete one first.' end
    saved.profiles[name] = profiles.Capture(saved)
    return true, 'Saved ' .. name
end
return profiles
