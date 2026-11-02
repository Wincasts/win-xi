local imgui = require('imgui')
local statustimes = require('winxi.statustimes')
local statusFlags = require('winxi.statuses')
local tooltip = require('winxi.tooltip')
local details = {}
local names = {}
local mouseX, mouseY
-- Called once by Present, not once per member/icon (including measurement passes). Hovering is a test of
-- the mouse against each rect, not imgui's, so it works through windows the mouse goes through
-- (Clickthrough): those are never imgui's hovered window, so one that wants the mouse is another, drawn
-- over them, and nothing here is hovered.
function details.BeginFrame(enabled, clickThrough)
    mouseX, mouseY = nil, nil
    if enabled and not (clickThrough and imgui.GetIO().WantCaptureMouse) then
        mouseX, mouseY = imgui.GetMousePos()
    end
end
function details.StatusName(id)
    if names[id] == nil then
        names[id] = AshitaCore:GetResourceManager():GetString('buffs.names', id) or ('Status ' .. id)
    end
    return names[id]
end
-- Who someone is, by server id: an entity the client knows, its name kept once found; one not found
-- is looked for again after a few seconds, not every frame the mouse rests on the icon
local whoNames, whoMissed = {}, {}
local function Who(serverId)
    local known = whoNames[serverId]
    if known ~= nil then return known end
    if whoMissed[serverId] and os.clock() - whoMissed[serverId] < 2 then return nil end
    local ok, entities = pcall(function() return AshitaCore:GetMemoryManager():GetEntity() end)
    local found = false
    if ok and entities ~= nil then
        for index = 0, 2303 do
            if entities:GetServerId(index) == serverId then
                local name = entities:GetName(index)
                found = (type(name) == 'string' and name ~= '') and name or false
                break
            end
        end
    end
    if found then whoNames[serverId] = found else whoMissed[serverId] = os.clock() end
    return found or nil
end

-- What put a status there, by the action that did: a spell's name, or a monster's move's
local function ActionName(category, param)
    if param == nil then return nil end
    local resources = AshitaCore:GetResourceManager()
    local ok, name = pcall(function()
        if category == 4 then return resources:GetSpellById(param).Name[1] end
        if category == 11 and param > 256 then return resources:GetString('monsters.abilities', param - 256, 2) end
        if category == 6 or category == 14 or category == 15 then return resources:GetAbilityById(param + 512).Name[1] end
        if category == 3 then return resources:GetAbilityById(param).Name[1] end
        return nil
    end)
    return ok and type(name) == 'string' and name ~= '' and name or nil
end

local REMOVED_BY = { erase = 'Removed by Erase, a -na spell or a waltz.', waltz = 'Removed by a -na spell or a waltz.',
    dispel = 'Removed by Dispel.' }

-- A status's tooltip: its name, its time left, what put it there and who, and what takes it off. serverId
-- is who it is on (nil for none known), nth which of its kind it is
function details.Status(id, serverId, nth)
    local text = details.StatusName(id) .. ' (' .. id .. ')'
    local estimated = false
    if serverId then
        local words, estimate, _, seconds = statustimes.Text(serverId, id, nth)
        estimated = estimate == true
        if seconds ~= nil then
            text = text .. (estimate and '\nEstimated remaining: %ds' or '\nRemaining: %ds'):format(math.max(0, math.floor(seconds)))
        elseif words ~= nil then
            text = text .. '\nDuration unknown'
        end
        local landing = statustimes.Landing(serverId, id)
        if landing ~= nil then
            local action, who = ActionName(landing.category, landing.param), landing.by and Who(landing.by)
            if action and who then text = text .. '\n' .. action .. ', by ' .. who
            elseif action then text = text .. '\n' .. action
            elseif who then text = text .. '\nBy ' .. who end
        end
    end
    local kind = statusFlags.Removable(id)
    if REMOVED_BY[kind] then text = text .. '\n' .. REMOVED_BY[kind] end
    if estimated then
        text = text .. '\nObserved effects only; resists and duration bonuses may differ.'
    end
    tooltip.Show(text)
end
function details.Hover(left, top, right, bottom)
    return type(mouseX) == 'number' and type(mouseY) == 'number'
        and mouseX >= left and mouseX < right and mouseY >= top and mouseY < bottom
end
function details.Member(member)
    local text = member.petName or member.name or 'Unknown'
    if member.owner then text = text .. '\nOwner: ' .. member.owner end
    if member.jobText then text = text .. '\n' .. member.jobText end
    tooltip.Show(text)
end
return details
