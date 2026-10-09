-- windows: the addon's windows. Each is one of winxi's themed windows with no title, as big as what
-- is drawn in it, that can be arranged with winxi.organize, fades with winxi.fade, and may be held by
-- a corner other than its top left so that it grows away from there.
--
--     windows.Use(options)                             the settings in use: after loading, or a change of character
--     windows.UpdateFade()                             once a frame, before any window
--     windows.Draw(window, content, wanted, growFrom)  draws one; content draws what it holds
--     windows.Lingers(window)                          true while a window no longer wanted is still fading out
--     windows.IsFadedOut(group)                        true while a group's windows are faded right out by idling
--     windows.ForgetCorner(window)                     for a window that has been moved by other means than dragging
--     windows.Padding()                                the padding of the window being drawn
--
-- wanted is false for a window that is being drawn only to fade out; otherwise leave it out. growFrom,
-- if given, is the corner that stays where it is as the window's content changes size (one of
-- winxi.anchor's: 'BottomLeft' for a window that grows upwards). content is then called twice a
-- frame, once to measure. A window linked to another while organizing is placed by its link instead.
--
-- A window is one of windows.List: its name for imgui, the group it fades with, and where in the
-- settings its place is kept, and its corner if it is held by one.
local bit = require('bit')
local imgui = require('imgui')
local theme = require('winxi.theme')
local shadow = require('winxi.shadow')
local organize = require('winxi.organize')
local anchor = require('winxi.anchor')
local fade = require('winxi.fade')
local game = require('game')

local windows = { }

windows.List = {
    party1 = { name = 'xiframes.us.1', label = 'Party', group = 'party', section = 'party', pos = 'pos1', corner = 'corner1' },
    party2 = { name = 'xiframes.us.2', label = 'Alliance 2', group = 'party', section = 'party', pos = 'pos2' },
    party3 = { name = 'xiframes.us.3', label = 'Alliance 3', group = 'party', section = 'party', pos = 'pos3' },
    main = { name = 'xiframes.tgt.main', label = 'Target', group = 'target', section = 'target', pos = 'mainPos' },
    sub = { name = 'xiframes.tgt.sub', label = 'Sub-target', group = 'target', section = 'target', pos = 'subPos' },
    tot = { name = 'xiframes.tgt.tot', label = 'Target of Target', group = 'target', section = 'target', pos = 'totPos' },
}

-- The groups of windows that can be chosen to fade, for the setting
windows.Groups = { { key = 'party', label = 'Party' }, { key = 'target', label = 'Target' } }

-- What each window is called on its label while organizing
local labels = { }
for _, window in pairs(windows.List) do
    labels[window.name] = window.label
end
organize.SetLabels(labels)

windows.ItemSpacing = { 8, 4 }
local windowPadding = { 10, 10 }
local noFramePadding = { 0, 0 }
local windowSize = { -1, -1 } -- every window sizes itself
local open = { true }
local baseFlags = nil

local options = nil

function windows.Use(newOptions)
    options = newOptions
    organize.SetLinks(options.links)
end

function windows.Padding()
    return windowPadding[2]
end

-- Fading while idle is winxi's: it works out one opacity a frame from the fade settings, and here that
-- is applied to the windows of the groups chosen to fade. Suspended while the windows are arranged,
-- and while the game's party cursor is out (a member is being picked from the party list, in the
-- party menu or as a sub-target): the party windows are being read then, however still the player is.
function windows.UpdateFade()
    fade.Update(options.fade, organize.IsActive() or game.StPartyIndex() ~= nil)
end

-- Whether a group's windows fade: fading is switched on, and the group is one of those chosen for it
local function Fades(group)
    local settings = options.fade
    if not settings.Enabled then
        return false
    end
    local chosen = settings.windows[group]
    return chosen ~= nil and chosen[1] and true or false
end

-- How opaque a window is this frame. A window of a group that fades fades in when it appears and out
-- when it is no longer wanted, and fades with the player's idling as well. Any other window is simply
-- there or not. wanted is whether the window should be showing.
local function Alpha(window, wanted)
    if organize.IsActive() or not Fades(window.group) then
        return wanted and 1 or 0
    end
    return fade.Presence(window.name, wanted) * fade.Alpha()
end

function windows.Lingers(window)
    if organize.IsActive() or not Fades(window.group) then
        return false
    end
    return fade.Lingering(window.name)
end

function windows.IsFadedOut(group)
    return Fades(group) and fade.Alpha() <= 0.01
end

-- The windows whose saved corner has been handed to winxi.anchor: once for each settings table, so a
-- character's own are used after a change of character
local cornerGiven = setmetatable({ }, { __mode = 'k' })

function windows.ForgetCorner(window)
    anchor.Reset(window.name)
    if window.corner ~= nil then
        local section = options[window.section]
        section[window.corner] = nil
        cornerGiven[section] = nil
    end
end

function windows.Draw(window, content, wanted, growFrom)
    -- faded right out: nothing to draw
    local alpha = Alpha(window, wanted ~= false)
    if alpha <= 0.01 then
        return
    end

    baseFlags = baseFlags or bit.bor(ImGuiWindowFlags_NoDecoration)
    local flags = baseFlags
    if options.clickThrough[1] and not organize.IsActive() then
        flags = bit.bor(flags, ImGuiWindowFlags_NoInputs)
    end

    local look = theme.Get()
    local padding = look.Padding
    windowPadding[1], windowPadding[2] = padding, padding

    -- held by a corner other than its top left, unless a link places it: its size is then measured
    -- before it is drawn (below), and it is given exactly that
    local held = growFrom ~= nil and not organize.IsLinked(window.name)
    if not held then
        flags = bit.bor(flags, ImGuiWindowFlags_AlwaysAutoResize)
    end
    imgui.SetNextWindowSize(windowSize)

    local section = options[window.section]
    organize.Place(window.name, section[window.pos])

    imgui.PushStyleVar(ImGuiStyleVar_Alpha, alpha)
    imgui.PushStyleColor(ImGuiCol_WindowBg, look.BackgroundColor)
    imgui.PushStyleColor(ImGuiCol_Border, look.BorderColor)
    imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, windows.ItemSpacing)
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, windowPadding)

    if held then
        if not cornerGiven[section] then
            cornerGiven[section] = true
            local corner = section[window.corner]
            if type(corner) == 'table' and corner[1] ~= nil and corner[2] ~= nil then
                anchor.Set(window.name, growFrom, corner[1], corner[2])
            else
                anchor.Reset(window.name)
            end
        end

        -- laid out off screen first, as it will be drawn, so the window can be put where its new size
        -- leaves the corner alone
        imgui.PushStyleVar(ImGuiStyleVar_FramePadding, noFramePadding)
        anchor.Measure(window.name, growFrom, content, padding)
        imgui.PopStyleVar()
        anchor.Place(window.name, growFrom)
    elseif window.corner ~= nil and section[window.corner] ~= nil then
        windows.ForgetCorner(window)
    end

    open[1] = true
    local isOpen = imgui.Begin(window.name, open, flags)
    imgui.PopStyleColor(2)

    if isOpen then
        if held then
            anchor.Track(window.name, growFrom)
            local x, y = anchor.Point(window.name)
            if x ~= nil then
                local corner = section[window.corner]
                if type(corner) ~= 'table' then
                    corner = T{ }
                    section[window.corner] = corner
                end
                corner[1], corner[2] = x, y
            end
        end

        shadow.Draw()

        imgui.PushStyleColor(ImGuiCol_Text, look.TextColor)
        imgui.PushStyleVar(ImGuiStyleVar_FramePadding, noFramePadding)

        organize.Label(window.name)

        content()

        organize.Track(window.name, section[window.pos])

        imgui.PopStyleVar()
        imgui.PopStyleColor()
    end

    imgui.PopStyleVar(2)
    imgui.End()
    imgui.PopStyleVar()
end

return windows
