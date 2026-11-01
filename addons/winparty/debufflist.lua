-- debufflist: a box listing the debuffs seen to land on the target, each with the time it has left,
-- that the player drags where they like. Plain, it is an imgui window of its own with nothing of the
-- theme about it, dragged by its body; with Winxi Theme it is one of the addon's windows
-- (windows.List.debuffs), drawn, moved and faded as the target windows are.
--
--     debufflist.Draw(saved, entity, sample)   once a frame: the target's entity, or nil for none; sample
--                                              lists the sample statuses, while organizing
--     debufflist.Rows(serverId, rows)          the statuses on it into rows: { id, left }, the soonest
--                                              to run out first
--
-- The statuses are what winxi.debuffs has seen take hold, by number, as the icons beside a target
-- window show them; the time left is its estimate. Either box is placed by Target → Debuff List
-- Position, and a drag sets that too.
require('common')
local bit = require('bit')
local imgui = require('imgui')
local tracker = require('winxi.debuffs')
local windows = require('windows')
local details = require('details')
local target = require('target')

local debufflist = { }

local window = windows.List.debuffs

-- the sample, while organizing: Paralyze, Slow and Dia, as the icons' sample, with times of their own
local sampleRows = { { id = 4, left = 12 }, { id = 13, left = 48 }, { id = 134, left = 95 } }

local none = { }
local rows = { }
local function ByTime(a, b)
    if a.left ~= b.left then return a.left < b.left end
    return a.id < b.id
end

function debufflist.Rows(serverId, into)
    into = into or rows
    local count = 0
    local now = os.time()
    for id, entry in pairs(tracker.Statuses(serverId) or none) do
        if entry.expires > now then
            count = count + 1
            local row = into[count]
            if row == nil then
                row = { }
                into[count] = row
            end
            row.id, row.left = id, entry.expires - now
        end
    end
    for index = #into, count + 1, -1 do
        into[index] = nil
    end
    table.sort(into, ByTime)
    return into
end

-- The time left, as 48s or 1:35, made once for each count of seconds
local timeTexts = { }
local function TimeText(left)
    local text = timeTexts[left]
    if text == nil then
        text = left >= 60 and ('%d:%02d'):format(math.floor(left / 60), left % 60) or ('%ds'):format(left)
        timeTexts[left] = text
    end
    return text
end

-- What the box holds: the target's name, then a row for each debuff, its name at the left and its time
-- in a column at the right of the widest name
local listName, listRows = '', rows
local function Content()
    imgui.Text(listName)
    if #listRows == 0 then
        imgui.TextDisabled('No debuffs seen')
        return
    end
    local widest = 0
    for _, row in ipairs(listRows) do
        local width = imgui.CalcTextSize(details.StatusName(row.id))
        if type(width) == 'number' and width > widest then widest = width end
    end
    local style = imgui.GetStyle()
    local spacing = style and style.ItemSpacing and style.ItemSpacing.x or 8
    local column = widest + 2 * spacing
    for _, row in ipairs(listRows) do
        imgui.Text(details.StatusName(row.id))
        imgui.SameLine(column)
        imgui.Text(TimeText(row.left))
    end
end

-- The plain box: imgui's own window, sized to its rows and dragged by its body, unless Lock Windows
-- keeps the mouse from it (while organizing it is dragged either way). It is put where the settings say
-- whenever they have changed by other means than a drag: on loading, a change of character, or the
-- Position row; and where it is dragged to is written back to them.
local open = { true }
local plainFlags = nil
local lastX, lastY = nil, nil
local function DrawPlain(saved, organizing)
    plainFlags = plainFlags or bit.bor(ImGuiWindowFlags_NoTitleBar, ImGuiWindowFlags_NoResize, ImGuiWindowFlags_NoCollapse,
        ImGuiWindowFlags_AlwaysAutoResize, ImGuiWindowFlags_NoScrollbar, ImGuiWindowFlags_NoSavedSettings,
        ImGuiWindowFlags_NoFocusOnAppearing)
    local flags = plainFlags
    if saved.clickThrough[1] and not organizing then
        flags = bit.bor(flags, ImGuiWindowFlags_NoInputs, ImGuiWindowFlags_NoMove)
    end
    local pos = saved.target.debuffListPos
    if pos[1] ~= lastX or pos[2] ~= lastY then
        imgui.SetNextWindowPos(pos, ImGuiCond_Always)
    end
    open[1] = true
    if imgui.Begin(window.name, open, flags) then
        Content()
        local x, y = imgui.GetWindowPos()
        if type(x) == 'number' and type(y) == 'number' then
            pos[1], pos[2] = x, y
        end
        lastX, lastY = pos[1], pos[2]
    end
    imgui.End()
end

local lastServerId, lastName = nil, nil

function debufflist.Draw(saved, entity, sample)
    local themed = saved.target.debuffListTheme[1]
    local wanted = true
    if sample then
        listName, listRows = target.Samples.main.Name, sampleRows
    elseif entity ~= nil then
        lastServerId, lastName = entity.ServerId, entity.Name
        listName, listRows = entity.Name, debufflist.Rows(entity.ServerId, rows)
    elseif themed and lastServerId ~= nil and windows.Lingers(window) then
        -- fading out: what it last showed
        listName, listRows = lastName, debufflist.Rows(lastServerId, rows)
        wanted = false
    else
        return
    end
    if themed then
        windows.Draw(window, Content, wanted)
    else
        DrawPlain(saved, sample)
    end
end

return debufflist
