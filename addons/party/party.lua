addon.name    = 'party'
addon.author  = 'lin, win'
addon.version = '0.4.0-pre1'
addon.desc    = 'Party, target and pet frames in the style of XivParty'

-- The addon in outline:
--   roster, pets, target  read the game, and hand back lists of lines
--   frames                draws a list of lines: the bars, names and figures
--   notices               invitations and treasure waiting, and their icons
--   debuffs               what is on each enemy, shown under a target
--   windows               the windows the lists are drawn in
--   options, config       the settings, and the window they are changed in
-- This file puts them together: what goes in which window each frame, and which packets go where.

-- The winxi this addon was made with, or a newer one: each addon is released with its own copy, so an
-- older one may have been put over it (winxi.version)
local winxiNeeded = 64 -- winxi.partystatus (57: abi, 56: presence)
do
    local ok, found = pcall(require, 'winxi.version')
    local number = ok and type(found) == 'table' and found.Number or 0
    if number < winxiNeeded then
        local text = ('%s needs winxi %d or newer, and addons/libs/winxi is %d: install the newest release of any winxi addon.'):format(addon.name, winxiNeeded, number)
        print(('\30\68[%s]\30\01 %s'):format(addon.name, text))
        error(text, 0)
    end
end

require('common')
pcall(require, 'winxi.perf')   -- the handlers timed for the perf addon; before any is registered
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
local roster = require('roster')
local pets = require('pets')
local target = require('target')
local namecolors = require('namecolors')
local fishing = require('fishing')
local notices = require('notices')
local debuffs = require('debuffs')
local packets = require('packets')
local game = require('game')
local perf = require('perf')
local geometry = require('geometry')
local details = require('details')

local saved = settings.load(options.Defaults())
local nativeHook -- loaded only when the experimental mode is requested
local nativeBehaviorGroups = { party=false, target=false }
local function FollowNative(window)
    return saved.nativeBehavior[1] and nativeHook and nativeHook.Uses(window) or false
end

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
    require('winxi.debuffs').Clear()
    roster.Forget()
    pets.Forget(true)
end

UseSettings()

-- What a party's window holds, drawn by one function for whichever party is being drawn: which is
-- said beforehand, so that no function need be made afresh for each window every frame
local drawing = { list = 1, sample = false, pets = nil }
-- the member the game's party cursor is on, or nil while it is not out: read once a frame for all
-- that asks. While it is out the party's order is being rearranged.
local partyCursor = nil
local rearranging = false

local function DrawPartyContent()
    local own = drawing.list == 1
    local members = roster.Members(drawing.list, drawing.sample, saved.party.sortByRole[1] and not rearranging and not nativeBehaviorGroups.party, partyCursor)
    local petLines = drawing.pets
    local hasPets = petLines ~= nil and #petLines > 0

    -- a list's last line is only as tall as what is on it: so the window ends where its content
    -- does, and what follows a list is a known distance under it
    local style = options.Style(saved)
    style.trimLast = true
    style.showJobs = rearranging
    -- the alliance's other two parties, both at the Alliance Scale on top of the Scale
    if not own then
        style.scale = style.scale * (tonumber(saved.party.allianceScale[1]) or 100) / 100
    end
    frames.Draw(members, own and 'party' or 'alliance', saved.style.showStatuses[1] and roster.StatusTexture or nil, style)

    -- the pets, under a line, with as much room above the line and below it as there is between the
    -- window's edge and its first member: the window's padding
    if hasPets then
        local room = windows.Padding() - windows.ItemSpacing[2] -- imgui puts the spacing in itself
        imgui.SetCursorPosY(imgui.GetCursorPosY() + room)
        imgui.Separator()
        imgui.SetCursorPosY(imgui.GetCursorPosY() + room)
        style.showJobs = false
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
            local offset = saved.party.iconOffset
            notices.DrawIcons(invitation, treasure, saved.party.iconCorner, offset[1] * options.Unit, offset[2] * options.Unit, frames.Scale(style))
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
    local count1,count2,count3,inParty=roster.Counts()
    inParty=inParty or count1>1 or count2>0 or count3>0
    windows.List.party1.label = (sample or count2 > 0 or count3 > 0) and 'Alliance'
        or (inParty and 'Party' or 'Solo')
    if sample then
        for list = 1, 3 do
            DrawParty(list, true)
        end
        return
    end

    -- the player's own is hidden while solo if that is set, but not while there is an invitation to be seen
    local waiting = notices.Invitation() ~= nil and saved.party.showInvites[1]
    if (nativeBehaviorGroups.party and count1 > 0)
    or (saved.party.hideWhenSolo[1] and count1 > 0 and (inParty or waiting))
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
-- name, and the distance always, whatever is set for TP), and its debuffs if those are shown: under it as
-- letters, or beside it as icons
local targetKeys = { 'main', 'sub', 'tot' }
local drawingKey, drawingEntity, drawingIndex = nil, nil, nil

local targetStatuses = { }
local sampleStatuses = { 4, 13, 134 } -- Paralyze, Slow and Dia, to show where they go

local function DrawTargetContent()
    local showDebuffs = saved.target[drawingKey .. 'Debuffs'][1]
    local icons = showDebuffs and saved.target.debuffStyle == 'icons'
    local style = options.Style(saved)
    style.showTp = true
    style.trimLast = not showDebuffs or icons
    local lines = target.Line(drawingKey, drawingEntity)
    lines[1].nameColor = saved.target.gameNameColors[1] and drawingIndex ~= nil
        and namecolors.For(drawingEntity, drawingIndex) or nil
    -- a monster's spawn letter after its name (the sample's A, to see it by)
    lines[1].letter = saved.target.monsterLetters[1]
        and (drawingIndex == nil and (drawingKey == 'main' and 'A' or nil) or target.Letter(drawingEntity, drawingIndex)) or nil
    -- the main target's window is bracketed while the player is locked on to it (the sample always, to see them by)
    lines[1].lockedOn = drawingKey == 'main' and saved.target.lockBrackets[1] and (drawingIndex == nil or target.LockedOn())
    -- as icons, they are beside the window as a party member's buffs are; as letters, under it
    if icons then
        lines[1].statusIds = drawingEntity == target.Samples[drawingKey] and sampleStatuses or debuffs.Ids(drawingEntity.ServerId, targetStatuses)
    else
        lines[1].statusIds = nil
    end
    frames.Draw(lines, 'target', roster.StatusTexture, style)

    if showDebuffs and not icons then
        debuffs.Draw(drawingEntity.ServerId, style.hoverDetails)
    end
end

-- Draws one of the target windows for the entity at index, if there is one (the client can hold an
-- index for an entity it no longer knows about, so the entity is fetched and checked first). When there
-- is none, the window goes on showing the entity it last showed for as long as it is fading out.
local lastShown = { } -- key -> the index of the entity the window last showed
local lastServerId = { } -- an index may be reused while the window is fading

local function DrawTarget(key, index)
    local window = windows.List[key]
    local entity = index ~= 0 and perf.Entity(index) or nil
    local wanted = entity ~= nil
    local at = index

    if wanted then
        lastShown[key], lastServerId[key] = index, entity.ServerId
    elseif lastShown[key] and windows.Lingers(window) then
        at = lastShown[key]
        entity = perf.Entity(at)
        if entity ~= nil and entity.ServerId ~= lastServerId[key] then
            entity = nil
        end
    end

    if entity ~= nil then
        drawingKey, drawingEntity, drawingIndex = key, entity, at
        windows.Draw(window, DrawTargetContent, wanted)
    end
end

local function DrawTargets(sample)
    -- filled with sample data, each window only if it is one that is switched on
    if sample then
        local shown = { main = saved.target.showMain[1], sub = saved.target.showSub[1], tot = saved.target.showTot[1] }
        for _, key in ipairs(targetKeys) do
            if shown[key] then
                drawingKey, drawingEntity, drawingIndex = key, target.Samples[key], nil
                windows.Draw(windows.List[key], DrawTargetContent)
            end
        end
        return
    end

    namecolors.BeginFrame()
    local main, sub, tot = target.Indexes(saved.target)
    DrawTarget('main', main)
    DrawTarget('sub', sub)
    DrawTarget('tot', tot)
end

-- Whether any target window shows debuffs: nothing is tracked unless one does
local function ShowsDebuffs()
    return (saved.target.showMain[1] and saved.target.mainDebuffs[1])
        or (saved.target.showSub[1] and saved.target.subDebuffs[1])
        or (saved.target.showTot[1] and saved.target.totDebuffs[1])
end

local tracking = false
local function UpdateTracking()
    local wanted = saved.target.enabled[1] and ShowsDebuffs()
    if wanted ~= tracking then
        require('winxi.debuffs').Clear()
        tracking = wanted
    end
    return wanted
end

-- another character's settings have been loaded, or these have been changed from outside
-- The window border, bar texture, bookends and status icons were the addon's own before they were
-- winxi's theme's: what was set of them, carried into the addon's own theme by options.Complete, goes
-- to the shared theme as well if the addon follows it, once
local function CarryTheme()
    if winxiTheme.IsShared() then
        local look = winxiTheme.Get()
        for key, value in pairs(saved.carriedTheme) do
            look[key] = value
        end
        winxiTheme.Touch()
        winxiTheme.Save()
    end
    saved.carriedTheme = nil
    settings.save()
end

settings.register('settings', 'settings_update', function(s)
    if s ~= nil then
        saved = s
    end
    UseSettings()
    settings.save()
end)

ashita.events.register('unload', 'unload_handler', function()
    if nativeHook then nativeHook.Stop() end
    settings.save()
end)

-- All the addon does in a frame
local function Present()
    -- Every frame, cheaply: nothing happens unless the choice of theme or the settings table has changed
    winxiTheme.Configure(saved.useSharedTheme, saved.theme)
    if saved.carriedTheme ~= nil then
        CarryTheme()
    end

    partyCursor = game.StPartyIndex()
    rearranging = partyCursor ~= nil
    config.Draw(saved)
    UpdateTracking()
    -- Keep settings and lifecycle current, but do no layout or pet polling while hidden.
    if not saved.showConfig[1] then winxiOrganize.SetActive(false) end
    windows.Capture, windows.Native, windows.NativeRect, windows.FollowNative, windows.BlockNativeInputs = nil, nil, nil, nil, false
    nativeBehaviorGroups.party,nativeBehaviorGroups.target=false,false
    windows.NativeBehaviorGroups=nativeBehaviorGroups
    local organizing = winxiOrganize.IsActive()
    local hooking = saved.nativeHook[1]
    if hooking and (saved.nativeParty[1] or saved.nativeTarget[1]) and not nativeHook then nativeHook = require('hook') end
    -- Renew empty replacements BEFORE the hiding rules, for each independently enabled group.
    -- Expanded chat/maps hide the replacement too, rather than allowing stock HUD frames back.
    -- The game draws a hooked fish's stamina gauge with its party list, in the middle of the screen: for the
    -- fight uihook lets what the list draws outside itself through, or, where it cannot, the list is given back.
    local hooked = fishing.Hooked()
    local replaceParty = hooking and saved.nativeParty[1] and saved.party.enabled[1] and not organizing
    local native = nativeHook and nativeHook.Begin(replaceParty,
        hooking and saved.nativeTarget[1] and saved.target.enabled[1] and not organizing, hooked)
    local listBack = hooked and replaceParty and not (nativeHook and nativeHook.Passing())
    local hidden=winxiGame.IsHidden(saved.hide)
    if native then
        nativeBehaviorGroups.party=saved.nativeBehavior[1] and nativeHook.Uses(windows.List.party1)
        nativeBehaviorGroups.target=saved.nativeBehavior[1] and nativeHook.Uses(windows.List.main)
    end
    -- Native behavior follows the client's HUD lifecycle. Hard guards affect native groups only;
    -- ordinary groups still obey their own saved hide rules (including any explicit overrides).
    local followsNative=nativeBehaviorGroups.party or nativeBehaviorGroups.target
    local nativeHidden=followsNative
        and (winxiGame.IsLoading() or winxiGame.IsInterfaceHidden() or winxiGame.IsEventHappening())
    if hidden and (not followsNative or nativeHidden) then return end
    if native then
        windows.Capture,windows.Native,windows.NativeRect,windows.FollowNative=nativeHook.Capture,nativeHook.Uses,nativeHook.Rect,FollowNative
        local menu = winxiGame.MenuName():match('^menu%s+(%S+)%s*$')
        windows.BlockNativeInputs = hidden or (menu ~= nil and menu ~= 'inline')
    end
    winxiOrganize.BeginFrame()
    windows.UpdateFade(rearranging)
    local showParty = saved.party.enabled[1] and (not hidden or nativeBehaviorGroups.party)
        and not (nativeHidden and nativeBehaviorGroups.party) and not windows.IsFadedOut('party')
        and not listBack -- the game's own party list is back for the fight: not doubled
    local showTarget = saved.target.enabled[1] and (not hidden or nativeBehaviorGroups.target)
        and not (nativeHidden and nativeBehaviorGroups.target) and not windows.IsFadedOut('target')
    if not showParty and not showTarget then
        winxiOrganize.EndFrame()
        return
    end

    -- Native menus block clicks, not read-only buff/debuff hover (including in combat).
    -- Every tooltip on the windows waits for Show Tooltips; with Clickthrough they are still hovered for
    -- them, just not clicked or dragged.
    details.BeginFrame(saved.style.hoverDetails[1] and not hidden, saved.clickThrough[1])
    if saved.automaticPositioning[1] then
        local count = 0
        if saved.pets.enabled[1] then
            -- A target drawn without the party still needs its configured layout reservation,
            -- but does not need a live pet scan for a party that will not be drawn.
            count = saved.pets.showParty[1] and saved.pets.reserve[1] or 1
            if showParty then count = math.max(count, #pets.Lines(organizing, saved.pets)) end
        end
        windows.UpdatePositions(geometry.Reserve(saved, winxiTheme.Get().Padding,
            imgui.GetFontSize(), windows.ItemSpacing[2], count))
    else
        windows.UpdatePositions()
    end

    -- Every enabled window is filled with sample data while organizing.
    if showParty then DrawParties(organizing) end
    if showTarget then DrawTargets(organizing) end

    winxiOrganize.EndFrame()
end

ashita.events.register('d3d_present', 'd3d_present_handler', function()
    perf.Run(Present)
end)

local function PacketIn(e)
    packets.inbound.action.reset()

    -- Keep transient state current even while its frames are disabled; otherwise an answered
    -- invitation or a previous zone's automaton can reappear when the frames are enabled again.
    notices.HandlePacket(e)
    pets.HandlePacket(e)
    namecolors.HandlePacket(e)
    fishing.HandlePacket(e)
    if e.id == 0x00A or e.id == 0x00B then
        roster.Forget()
        lastShown, lastServerId = { }, { }
        require('winxi.debuffs').Clear()
    end
    if UpdateTracking() then debuffs.HandlePacket(e) end
end
ashita.events.register('packet_in', 'packet_in_handler', function(e)
    perf.Packet(PacketIn, e)
end)

local function PacketOut(e)
    notices.HandlePacketOut(e)
    fishing.HandlePacketOut(e)
end
ashita.events.register('packet_out', 'packet_out_handler', function(e)
    perf.Packet(PacketOut, e)
end)

ashita.events.register('command', 'command_handler', function(e)
    local cmd = e.command:match('%S+')
    if cmd == nil then
        return
    end
    cmd = cmd:lower()
    if cmd ~= '/pt' and cmd ~= '/xif' then
        return
    end
    e.blocked = true

    local subcommand = (e.command:match('^%s*%S+%s+(%S+)') or ''):lower()
    if subcommand == 'native' then
        local choice = (e.command:match('^%s*%S+%s+%S+%s+(%S+)') or 'status'):lower()
        local isTarget = choice == 'target'
        if isTarget then choice = (e.command:match('^%s*%S+%s+%S+%s+%S+%s+(%S+)') or 'status'):lower() end
        if choice == 'on' or choice == 'off' then
            saved[isTarget and 'nativeTarget' or 'nativeParty'][1] = choice == 'on'
            if choice == 'on' then saved.nativeHook[1] = true end
            if nativeHook and choice == 'off' then nativeHook.Disable(isTarget) end
            settings.save()
            print(('[party] Native %s replacement %s. Unload hideparty before enabling; /pt native status for diagnostics.'):format(isTarget and 'target' or 'party', choice))
        elseif choice ~= 'status' then
            print('[party] Usage: /pt native [target] on|off|status')
            return
        end
        nativeHook = nativeHook or require('hook')
        print('[party] ' .. nativeHook.Status())
        return
    elseif subcommand == 'menu' then
        print(('[party] Current native menu: %q'):format(winxiGame.MenuName()))
        return
    elseif subcommand == 'perf' then
        print('[party] Measuring for five seconds...')
        perf.Start(function(words)
            print('[party] ' .. words .. (saved.showConfig[1] and ' (the settings window was open)' or ''))
        end, e.command:lower():match('%s+counters%s*$') ~= nil)
        return
    elseif subcommand == 'cursor' then
        local ok, handle, detail = pcall(require('winxi.cursor').Get, true)
        if not ok then
            print('[party] Native cursor error: ' .. tostring(handle))
        elseif handle then
            print(('[party] Native cursor loaded: %dx%d sprite from ROM/119/51.DAT'):format(detail[5], detail[6]))
        else
            print('[party] Native cursor unavailable: ' .. tostring(detail))
        end
        return
    end

    config.Toggle(saved)
end)
