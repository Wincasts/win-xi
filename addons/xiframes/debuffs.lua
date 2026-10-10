-- debuffs: a row of letters under a target for the debuffs worth knowing about on it. What is on each
-- enemy is winxi.debuffs' to keep count of; this hands it the packets and draws what it says.
--
--     debuffs.HandlePacket(e)     every packet in goes by this while debuffs are shown anywhere
--     debuffs.Draw(serverId)      the row for one enemy, in the window being drawn
require('common')
local imgui = require('imgui')
local tracker = require('winxi.debuffs')
local packets = require('packets')
local colors = require('colors')

local debuffs = { }

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

local function DrawSeparator()
    imgui.PopStyleVar()
    imgui.Text('')
    imgui.SameLine()
    imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, { 0, 0 })
end

local function DrawStatusEntry(text, isActive, color)
    if isActive then
        imgui.PushStyleColor(ImGuiCol_Text, color)
    else
        imgui.PushStyleColor(ImGuiCol_Text, colors.StatusGrey)
    end

    imgui.Text(text)
    imgui.SameLine()
    imgui.PopStyleColor()
end

-- The row for one enemy: a letter for each debuff, lit while it is on
local function DrawStatus(serverId)
    local function on(kind)
        return tracker.Get(serverId, kind) ~= nil
    end

    imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, { 0, 0 })
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
    -- the action is parsed once for every tool of xiframes that wants it
    if e.id == packets.inbound.action.id then
        tracker.Action(packets.inbound.action.shared(e))
    else
        tracker.HandlePacket(e)
    end
end

function debuffs.Draw(serverId)
    DrawStatus(serverId)
end

return debuffs
