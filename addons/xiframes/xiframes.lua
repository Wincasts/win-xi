addon.name    = 'xiframes'
addon.author  = 'lin, jbutt'
addon.version = '0.2'
addon.desc    = 'Party, target and pet frames in the style of XivParty'

-- The addon in outline:
--   party, pets, target   read the game, and hand back lists of lines
--   frames                draws a list of lines: the bars, names and figures
--   notices               invitations and treasure waiting, and their icons
--   debuffs               what is on each enemy, shown under a target
--   windows               the windows the lists are drawn in
--   options, config       the settings, and the window they are changed in
-- This file puts them together: what goes in which window each frame, and which packets go where.
require('common')
local imgui = require('imgui')
local settings = require('settings')
local winxiFade = require('winxi.fade')
local winxiGame = require('winxi.game')
local winxiOrganize = require('winxi.organize')
local winxiTheme = require('winxi.theme')
local options = require('options')
local config = require('config')
local windows = require('windows')
local frames = require('frames')
local party = require('party')
local pets = require('pets')
local target = require('target')
local notices = require('notices')
local debuffs = require('debuffs')
local packets = require('packets')

local saved = settings.load(options.Defaults())

-- Brings the settings up to date, and hands winxi what is its to fill in. Run when the settings are
-- loaded or replaced, not every frame: everything handed over is a table that is then changed in place.
local function UseSettings()
    options.Complete(saved)
    winxiGame.CompleteHide(saved.hide)
    winxiFade.Complete(saved.fade)
    for _, group in ipairs(windows.Groups) do
        if type(saved.fade.windows[group.key]) ~= 'table' then
            saved.fade.windows[group.key] = T{ true }
        end
    end
    windows.Use(saved)
    party.Forget()
end

UseSettings()

-- What a party's window holds, drawn by one function for whichever party is being drawn: which is
-- said beforehand, so that no function need be made afresh for each window every frame
local drawing = { list = 1, sample = false, pets = nil }

local function DrawPartyContent()
    local own = drawing.list == 1
    local members = party.Members(drawing.list, drawing.sample, saved.party.sortByRole[1])
    local petLines = drawing.pets
    local hasPets = petLines ~= nil and #petLines > 0

    -- a list's last line is only as tall as what is on it: so the window ends where its content
    -- does, and what follows a list is a known distance under it
    local style = options.Style(saved)
    style.trimLast = true
    frames.Draw(members, own and 'party' or 'alliance', party.StatusTexture, style)

    -- the pets, under a line, with as much room above the line and below it as there is between the
    -- window's edge and its first member: the window's padding
    if hasPets then
        local room = windows.Padding() - windows.ItemSpacing[2] -- imgui puts the spacing in itself
        imgui.SetCursorPosY(imgui.GetCursorPosY() + room)
        imgui.Separator()
        imgui.SetCursorPosY(imgui.GetCursorPosY() + room)
        frames.Draw(petLines, 'pets', nil, style)
    end

    -- an invitation waiting for an answer, and anything in the treasure pool, have icons beside the
    -- player's own party; both are shown while the windows are arranged, to see where they go
    if own then
        local invitation, treasure = nil, false
        if saved.party.showInvites[1] then
            invitation = notices.Invitation() or (drawing.sample and notices.SampleInvitation) or nil
        end
        if saved.party.showTreasure[1] then
            treasure = drawing.sample or notices.TreasureWaiting()
        end
        if invitation ~= nil or treasure then
            notices.DrawIcons(invitation, treasure, saved.party.iconCorner, saved.party.iconOffset, frames.Scale(style))
        end
    end
end

-- The player's own party keeps its bottom edge where it is and grows upwards as members join, has
-- its buffs beside it, and has the pets under it. The other two grow downwards.
local partyWindows = { windows.List.party1, windows.List.party2, windows.List.party3 }

local function DrawParty(list, sample)
    drawing.list, drawing.sample = list, sample
    drawing.pets = nil
    if list == 1 and saved.pets.enabled[1] then
        drawing.pets = pets.Lines(sample, saved.pets)
    end
    windows.Draw(partyWindows[list], DrawPartyContent, nil, list == 1 and 'BottomLeft' or nil)
end

local function DrawParties(sample)
    if sample then
        for list = 1, 3 do
            DrawParty(list, true)
        end
        return
    end

    -- the player's own is hidden while solo if that is set, but not while there is an invitation to be seen
    local count1, count2, count3 = party.Counts()
    local waiting = notices.Invitation() ~= nil and saved.party.showInvites[1]
    if (saved.party.hideWhenSolo[1] and (count1 > 1 or (waiting and count1 > 0)))
    or (not saved.party.hideWhenSolo[1] and count1 > 0) then
        DrawParty(1, false)
    end
    if count2 > 0 then
        DrawParty(2, false)
    end
    if count3 > 0 then
        DrawParty(3, false)
    end
end

-- A target's window: its line, set as the party's are but for what is the line's own (more of the
-- name, and the distance always, whatever is set for TP), and its debuffs under it if those are shown
local targetKeys = { 'main', 'sub', 'tot' }
local drawingKey, drawingEntity = nil, nil

local function DrawTargetContent()
    local showDebuffs = saved.target[drawingKey .. 'Debuffs'][1]
    local style = options.Style(saved)
    style.nameChars = target.NameChars
    style.showTp = true
    style.trimLast = not showDebuffs
    frames.Draw(target.Line(drawingKey, drawingEntity), 'target', nil, style)

    if showDebuffs then
        debuffs.Draw(drawingEntity.ServerId)
    end
end

-- Draws one of the target windows for the entity at index, if there is one (the client can hold an
-- index for an entity it no longer knows about, so the entity is fetched and checked first). When there
-- is none, the window goes on showing the entity it last showed for as long as it is fading out.
local lastShown = { } -- key -> the index of the entity the window last showed

local function DrawTarget(key, index)
    local window = windows.List[key]
    local entity = index ~= 0 and GetEntity(index) or nil
    local wanted = entity ~= nil

    if wanted then
        lastShown[key] = index
    elseif lastShown[key] and windows.Lingers(window) then
        entity = GetEntity(lastShown[key])
    end

    if entity ~= nil then
        drawingKey, drawingEntity = key, entity
        windows.Draw(window, DrawTargetContent, wanted)
    end
end

local function DrawTargets(sample)
    -- filled with sample data, each window only if it is one that is switched on
    if sample then
        local shown = { main = saved.target.showMain[1], sub = saved.target.showSub[1], tot = saved.target.showTot[1] }
        for _, key in ipairs(targetKeys) do
            if shown[key] then
                drawingKey, drawingEntity = key, target.Samples[key]
                windows.Draw(windows.List[key], DrawTargetContent)
            end
        end
        return
    end

    local main, sub, tot = target.Indexes(saved.target)
    DrawTarget('main', main)
    DrawTarget('sub', sub)
    DrawTarget('tot', tot)
end

-- Whether any target window shows debuffs: nothing is tracked unless one does
local function ShowsDebuffs()
    return saved.target.mainDebuffs[1] or saved.target.subDebuffs[1] or saved.target.totDebuffs[1]
end

-- another character's settings have been loaded, or these have been changed from outside
settings.register('settings', 'settings_update', function(s)
    if s ~= nil then
        saved = s
    end
    UseSettings()
    settings.save()
end)

ashita.events.register('unload', 'unload_handler', function()
    settings.save()
end)

ashita.events.register('d3d_present', 'd3d_present_handler', function()
    -- Every frame, cheaply: nothing happens unless the choice of theme or the settings table has changed
    winxiTheme.Configure(saved.useSharedTheme, saved.theme)

    config.Draw(saved)

    if winxiGame.IsHidden(saved.hide) then
        return
    end

    -- Organizing ends when the settings window is closed. While it is on, every window that is
    -- switched on is drawn filled with sample data, so that each is there to be arranged.
    if not saved.showConfig[1] then
        winxiOrganize.SetActive(false)
    end
    local organizing = winxiOrganize.IsActive()
    winxiOrganize.BeginFrame()
    windows.UpdateFade()

    -- none that has faded right out: it would only be prepared and then not drawn
    if saved.party.enabled[1] and not windows.IsFadedOut('party') then
        DrawParties(organizing)
    end
    if saved.target.enabled[1] and not windows.IsFadedOut('target') then
        DrawTargets(organizing)
    end

    winxiOrganize.EndFrame()
end)

ashita.events.register('packet_in', 'packet_in_handler', function(e)
    packets.inbound.action.reset()

    if saved.party.enabled[1] then
        notices.HandlePacket(e)
    end
    if saved.target.enabled[1] and ShowsDebuffs() then
        debuffs.HandlePacket(e)
    end
    if saved.pets.enabled[1] then
        pets.HandlePacket(e)
    end
end)

ashita.events.register('packet_out', 'packet_out_handler', function(e)
    if saved.party.enabled[1] then
        notices.HandlePacketOut(e)
    end
end)

ashita.events.register('command', 'command_handler', function(e)
    local cmd = e.command:match('%S+')
    if cmd == nil then
        return
    end
    cmd = cmd:lower()
    if cmd ~= '/xiframes' and cmd ~= '/xif' then
        return
    end
    e.blocked = true

    config.Toggle(saved)
end)
