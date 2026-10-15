-- debuffs: the debuffs on a target, by its window. What is on each enemy is winxi.debuffs' to
-- keep count of; this hands it the packets and draws what it says.
--
--     debuffs.HandlePacket(e)        every packet in goes by this while debuffs are shown anywhere
--     debuffs.Draw(serverId)         the row of letters for one enemy, in the window being drawn
--     debuffs.Ids(serverId, ids)     every status seen to take hold on it, by number, into ids: for
--                                    the icons beside its window, drawn as a party member's buffs are
--
-- debuffs.Styles are the ways of showing them: 'letters', a letter under the window for each debuff
-- worth knowing about, lit while it is on; or 'icons', an icon for each status beside the window.
require('common')
local imgui = require('imgui')
local tracker = require('winxi.debuffs')
local packets = require('packets')
local colors = require('colors')

local debuffs = { }

debuffs.Styles = { { key = 'letters', label = 'Letters' }, { key = 'icons', label = 'Icons' } }

local function GetThrenodyColor(element)
    if element == 'light' then
        return colors.StatusWhite
    elseif element == 'dark' then
        return colors.StatusBlack
    elseif element == 'fire' then
        return colors.StatusRed
    elseif element == 'ice' then
        return colors.StatusCyan
    elseif element == 'wind' then
        return colors.StatusGreen
    elseif element == 'earth' then
        return colors.StatusBrown
    elseif element == 'lightning' then
        return colors.StatusYellow
    elseif element == 'water' then
        return colors.StatusBlue
    end
end

local noSpacing = { 0, 0 }
local hoverEnabled, hoverServer, hoverKind
local details = require('details')

local function DrawSeparator()
    imgui.PopStyleVar()
    imgui.Text('')
    imgui.SameLine()
    imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, noSpacing)
end

local function DrawStatusEntry(text, isActive, color)
    if isActive then
        imgui.PushStyleColor(ImGuiCol_Text, color)
    else
        imgui.PushStyleColor(ImGuiCol_Text, colors.StatusGrey)
    end

    imgui.Text(text)
    if hoverEnabled and imgui.IsItemHovered() then
        local id = tracker.StatusIds[hoverKind]
        if id then details.Status(id, hoverServer) end
    end
    imgui.SameLine()
    imgui.PopStyleColor()
end

-- Draw sets the current server once; no per-row closure allocation.
local function on(kind)
    hoverKind = kind
    return tracker.Get(hoverServer, kind) ~= nil
end

-- The row for one enemy: a letter for each debuff, lit while it is on
local function DrawStatus(serverId)
    imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, noSpacing)
    DrawStatusEntry('D',  on('dia'), colors.StatusWhite)
    DrawStatusEntry('B',  on('bio'), colors.StatusBlack)
    DrawSeparator()
    DrawSeparator()
    DrawStatusEntry('P',  on('para'), colors.StatusWhite)
    DrawStatusEntry('S',  on('slow'), colors.StatusWhite)
    DrawStatusEntry('E',  on('elegy'), colors.StatusBrown)
    DrawStatusEntry('G',  on('grav'), colors.StatusBlack)
    DrawStatusEntry('B',  on('blind'), colors.StatusBlack)
    DrawStatusEntry('F',  on('flash'), colors.StatusWhite)
    DrawSeparator()
    DrawSeparator()
    DrawStatusEntry('Si', on('silence'), colors.StatusWhite)
    DrawSeparator()
    DrawStatusEntry('Sl', on('sleep'), colors.StatusBlack)
    DrawSeparator()
    DrawStatusEntry('Bi', on('bind'), colors.StatusBlack)
    DrawSeparator()
    DrawStatusEntry('Po', on('poison'), colors.StatusBlack)
    DrawSeparator()
    DrawStatusEntry('Rq', on('requiem'), colors.StatusWhite)
    DrawSeparator()
    DrawSeparator()
    DrawStatusEntry('S',  on('shock'), colors.StatusYellow)
    DrawStatusEntry('R',  on('rasp'), colors.StatusBrown)
    DrawStatusEntry('C',  on('choke'), colors.StatusGreen)
    DrawStatusEntry('F',  on('frost'), colors.StatusCyan)
    DrawStatusEntry('B',  on('burn'), colors.StatusRed)
    DrawStatusEntry('D',  on('drown'), colors.StatusBlue)

    local threnody = tracker.Get(serverId, 'threnody')
    if threnody and threnody.element then
        imgui.NewLine()
        imgui.Text('Threnody: ')
        imgui.SameLine()
        imgui.PushStyleColor(ImGuiCol_Text, GetThrenodyColor(threnody.element))
        imgui.Text(threnody.element)
        imgui.PopStyleColor()
    end

    imgui.PopStyleVar()
end

function debuffs.HandlePacket(e)
    -- the action is parsed once for every tool of the party addon that wants it
    if e.id == packets.inbound.action.id then
        tracker.Action(packets.inbound.action.shared(e))
    else
        tracker.HandlePacket(e)
    end
end

-- The statuses on an enemy, by number, into ids (emptied first): in that order so that none moves
-- about as others come and go
local none = { }

function debuffs.Ids(serverId, ids)
    local count = 0
    local now = os.time()
    for id, entry in pairs(tracker.Statuses(serverId) or none) do
        if entry.expires > now then
            count = count + 1
            ids[count] = id
        end
    end
    for index = #ids, count + 1, -1 do
        ids[index] = nil
    end
    table.sort(ids)
    return ids
end

function debuffs.Draw(serverId, hover)
    hoverEnabled, hoverServer = hover, serverId
    DrawStatus(serverId)
end

return debuffs
