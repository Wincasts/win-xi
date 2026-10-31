-- Settings-only effect picker. Saved values stay comma-separated IDs for backwards compatibility.
local imgui = require('imgui')
local picker = {}
local states = setmetatable({}, { __mode = 'k' })
local catalog, names
local tick, listSize = { false }, { 0, 180 }

function picker.Parse(text)
    local ids, selected = {}, {}
    for word in (text or ''):gmatch('%d+') do
        local id = tonumber(word)
        if id <= 1023 and not selected[id] then
            ids[#ids + 1], selected[id] = id, true
        end
    end
    return ids, selected
end

local function State(value)
    local state = states[value]
    if not state then state = { search = { '' } }; states[value] = state end
    if state.raw ~= value[1] then
        state.raw = value[1]
        state.ids, state.selected = picker.Parse(value[1])
    end
    return state
end

function picker.Set(value, id, enabled)
    if type(id) ~= 'number' or id < 0 or id > 1023 or id % 1 ~= 0 then return end
    local state = State(value)
    if enabled and not state.selected[id] then
        state.ids[#state.ids + 1] = id
    elseif not enabled then
        for at, found in ipairs(state.ids) do
            if found == id then table.remove(state.ids, at); break end
        end
    else
        return
    end
    value[1] = table.concat(state.ids, ',')
    state.raw = nil
end

function picker.Move(value, id, delta)
    local state = State(value)
    for at, found in ipairs(state.ids) do
        if found == id then
            local to = at + delta
            if to >= 1 and to <= #state.ids then
                state.ids[at], state.ids[to] = state.ids[to], state.ids[at]
                value[1] = table.concat(state.ids, ',')
                state.raw = nil
            end
            return
        end
    end
end

local function Catalog()
    if catalog then return catalog end
    catalog, names = {}, {}
    local resources = AshitaCore:GetResourceManager()
    if type(resources.GetString) == 'function' then
        for id = 0, 1023 do
            local name = resources:GetString('buffs.names', id)
            if id ~= 255 and type(name) == 'string' and name ~= '' then
                names[id] = name
                catalog[#catalog + 1] = { id = id, name = name, lower = name:lower() }
            end
        end
    end
    table.sort(catalog, function(a, b)
        if a.lower ~= b.lower then return a.lower < b.lower end
        return a.id < b.id
    end)
    return catalog
end

function picker.Matches(effect, query)
    return query == '' or effect.lower:find(query:lower(), 1, true) ~= nil or tostring(effect.id) == query
end

function picker.Draw(key, value, ordered)
    local state = State(value)
    if not imgui.BeginCombo('##party.effects.' .. key, ('%d selected — choose effects'):format(#state.ids)) then return end
    local known = Catalog()
    imgui.TextDisabled(ordered and 'Priority order: first effect has highest priority.' or 'Hidden effects override priorities.')
    -- The selected list remains available even for unknown IDs entered in Advanced settings.
    if #state.ids > 0 then
        local visible = imgui.BeginChild('##party.selected.' .. key, listSize, ImGuiChildFlags_Borders or 1)
        if visible then
            for at, id in ipairs(state.ids) do
                local suffix = '##party.' .. key .. '.' .. id
                local name = names[id] or ('Status ' .. id)
                tick[1] = true
                if imgui.Checkbox(('%d. %s (%d)%s'):format(at, name, id, suffix), tick) then
                    picker.Set(value, id, false)
                    break
                end
                if ordered then
                    imgui.SameLine()
                    if imgui.SmallButton('Up' .. suffix) then picker.Move(value, id, -1); break end
                    imgui.SameLine()
                    if imgui.SmallButton('Down' .. suffix) then picker.Move(value, id, 1); break end
                end
            end
        end
        imgui.EndChild()
    end
    imgui.InputText('Search name or ID##party.search.' .. key, state.search, 128)
    local visible = imgui.BeginChild('##party.catalog.' .. key, listSize, ImGuiChildFlags_Borders or 1)
    if visible then
        state = State(value)
        local matches = 0
        for _, effect in ipairs(known) do
            if picker.Matches(effect, state.search[1]) then
                matches = matches + 1
                tick[1] = state.selected[effect.id] == true
                if imgui.Checkbox(('%s (%d)##party.pick.%s.%d'):format(effect.name, effect.id, key, effect.id), tick) then
                    picker.Set(value, effect.id, tick[1])
                    state = State(value)
                end
            end
        end
        if matches == 0 then imgui.TextDisabled('No matching effects. Numeric IDs are available under Advanced: Status IDs.') end
    end
    imgui.EndChild()
    imgui.EndCombo()
end
return picker
