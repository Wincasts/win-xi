local imgui = require('imgui')
local tracker = require('winxi.debuffs')
local tooltip = require('winxi.tooltip')
local details = {}
local names = {}
local mouseX, mouseY
-- Called once by Present, not once per member/icon (including measurement passes).
function details.BeginFrame(enabled)
    mouseX, mouseY = nil, nil
    if enabled then mouseX, mouseY = imgui.GetMousePos() end
end
function details.StatusName(id)
    if names[id] == nil then
        names[id] = AshitaCore:GetResourceManager():GetString('buffs.names', id) or ('Status ' .. id)
    end
    return names[id]
end
function details.Status(id, serverId)
    local text = details.StatusName(id) .. ' (' .. id .. ')'
    if serverId then
        local remaining = tracker.StatusRemaining(serverId, id)
        text = text .. (remaining and ('\nEstimated remaining: %ds'):format(math.max(0, remaining)) or '\nDuration unknown')
        text = text .. '\nObserved effects only; resists and duration bonuses may differ.'
    end
    tooltip.Show(text)
end
function details.Hover(left, top, right, bottom)
    return type(mouseX) == 'number' and type(mouseY) == 'number'
        and mouseX >= left and mouseX < right and mouseY >= top and mouseY < bottom
end
function details.Job(member)
    if member.jobText then tooltip.Show(member.jobText) end
end
function details.Member(member)
    local text = member.petName or member.name or 'Unknown'
    if member.owner then text = text .. '\nOwner: ' .. member.owner end
    if member.jobText then text = text .. '\n' .. member.jobText end
    if member.statusIds and #member.statusIds > 0 then
        text = text .. '\nStatuses:'
        for _, id in ipairs(member.statusIds) do text = text .. '\n' .. details.StatusName(id) end
        if member.statusServerId then text = text .. '\nEnemy effects are observed estimates, not a complete status list.' end
    end
    tooltip.Show(text)
end
return details
