-- windows: the addon's windows. Each is one of winxi's themed windows with no title bar, as big as what
-- is drawn in it, that can be arranged with winxi.organize, fades with winxi.fade, and may be held by
-- a corner other than its top left so that it grows away from there. Its label is its title, on its
-- top edge, where the theme has Frame Titles (winxi.titles).
--
--     windows.Use(options)                             the settings in use: after loading, or a change of character
--     windows.UpdateFade(rearranging)                  once a frame, before any window
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
local backgrounds = require('winxi.backgrounds')
local clearColor = { 0, 0, 0, 0 }
local shadow = require('winxi.shadow')
local organize = require('winxi.organize')
local anchor = require('winxi.anchor')
local fade = require('winxi.fade')
local borders = require('winxi.borders')
local fonts = require('winxi.fonts')
local titles = require('winxi.titles')

local positioning = require('positioning')
local nativePlacement = require('nativeposition')
local windows = { }
local automaticLayout, currentMainTop, currentAllianceBottom
local automaticWindows = {} -- managed windows returning to saved manual positions
local nativeTrackPosition = { 0, 0 }

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
local automaticPosition = { 0, 0 }
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
-- rearranging is whether that cursor is out.
function windows.UpdateFade(rearranging)
    fade.Update(options.fade, organize.IsActive() or rearranging)
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
    if windows.FollowNative and windows.FollowNative(window) then return wanted and 1 or 0 end
    if organize.IsActive() or not Fades(window.group) then
        return wanted and 1 or 0
    end
    return fade.Presence(window.name, wanted) * fade.Alpha()
end

function windows.Lingers(window)
    if windows.FollowNative and windows.FollowNative(window) then return false end
    if organize.IsActive() or not Fades(window.group) then
        return false
    end
    return fade.Lingering(window.name)
end

function windows.IsFadedOut(group)
    if windows.NativeBehaviorGroups and windows.NativeBehaviorGroups[group] then return false end
    return Fades(group) and fade.Alpha() <= 0.01
end

-- The windows whose saved corner has been handed to winxi.anchor: once for each settings table, so a
-- character's own are used after a change of character
local cornerGiven = setmetatable({ }, { __mode = 'k' })

function windows.UpdatePositions(mainHeight, targetHeight, allianceHeight)
    automaticLayout=nil
    if options.automaticPositioning[1] and mainHeight then
        local display=imgui.GetIO().DisplaySize
        automaticLayout=positioning.Layout(display.x,display.y,mainHeight,targetHeight,allianceHeight)
    end
    currentMainTop, currentAllianceBottom = nil, nil
end

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
    local nativeWindow = windows.Native and windows.Native(window)
    if (options.clickThrough[1] or (nativeWindow and windows.BlockNativeInputs)) and not organize.IsActive() then
        flags = bit.bor(flags, ImGuiWindowFlags_NoInputs)
    end

    local look = theme.Get()
    local padding = look.Padding
    windowPadding[1], windowPadding[2] = padding, padding

    -- held by a corner other than its top left, unless a link places it: its size is then measured
    -- before it is drawn (below), and it is given exactly that
    local key = window == windows.List.party1 and 'party1'
        or window == windows.List.party2 and 'party2'
        or window == windows.List.party3 and 'party3'
        or window == windows.List.main and 'main'
        or window == windows.List.sub and 'sub'
        or window == windows.List.tot and 'tot'
    local nativeRect = nativeWindow and nativePlacement.Enabled(options,key) and windows.NativeRect and windows.NativeRect(window) or nil
    local defaultAnchored = nativeRect ~= nil
    local automatic = not defaultAnchored and not nativePlacement.ManualOverride(options,key)
        and automaticLayout ~= nil and positioning.Managed(key)
    local held = not automatic and not defaultAnchored and growFrom ~= nil and not organize.IsLinked(window.name)
    if not held then
        flags = bit.bor(flags, ImGuiWindowFlags_AlwaysAutoResize)
    end
    imgui.SetNextWindowSize(windowSize)

    local section = options[window.section]
    if automatic or defaultAnchored then
        automaticWindows[window.name] = true
        if defaultAnchored then flags=bit.bor(flags,ImGuiWindowFlags_NoMove) end
    else
        organize.Place(window.name, section[window.pos])
        if automaticWindows[window.name] then
            imgui.SetNextWindowPos(section[window.pos], ImGuiCond_Always)
            anchor.Reset(window.name)
            cornerGiven[section] = nil
            automaticWindows[window.name] = nil
        end
    end

    -- the theme's font: the frames write their names and values in it, at sizes of their own
    local font = fonts.Push()
    imgui.PushStyleVar(ImGuiStyleVar_Alpha, alpha)
    -- the theme's background style, if it has one, is drawn in place of the window's own
    local background = backgrounds.For(nil)
    imgui.PushStyleColor(ImGuiCol_WindowBg, background and clearColor or look.BackgroundColor)
    imgui.PushStyleColor(ImGuiCol_Border, theme.GameBorderColor())
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
    elseif not automatic and not defaultAnchored and window.corner ~= nil and section[window.corner] ~= nil then
        windows.ForgetCorner(window)
    end

    -- the theme's border art, if it has any, in place of the window's own border: the plain border
    -- stays where the art could not be loaded
    local borderTexture = borders.Texture(look.BorderStyle)
    local bordered = borders.Push(borderTexture, titles.Breaks(window.label))
    open[1] = true
    local isOpen = imgui.Begin(window.name, open, flags)
    imgui.PopStyleVar(bordered)
    imgui.PopStyleColor(2)

    if isOpen then
        if defaultAnchored then
            local width,height=imgui.GetWindowSize()
            local display=imgui.GetIO().DisplaySize
            local x,y=nativePlacement.Place(key,nativeRect,display.x or display[1],display.y or display[2],width,height,
                windows.FollowNative and windows.FollowNative(window))
            if x then
                automaticPosition[1],automaticPosition[2]=x,y
                imgui.SetWindowPos(window.name,automaticPosition)
            end
        elseif automatic then
            local width, height = imgui.GetWindowSize()
            local left, top = positioning.Place(key, width, height, automaticLayout, currentMainTop, currentAllianceBottom)
            automaticPosition[1], automaticPosition[2] = left, top
            imgui.SetWindowPos(window.name, automaticPosition)
            if key == 'party1' then currentMainTop = top end
            if key == 'party2' then currentAllianceBottom = top + height end
        end
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

        -- winxi's window shadow uses the shared BACKGROUND draw list, not this window's list.
        -- Do not leave an uncaptured shadow over the game while the window itself is native-rendered.
        -- Bar shadows are window geometry and are still captured normally.
        if not nativeWindow then shadow.Draw() end
        backgrounds.Draw(background, look.BackgroundColor)

        imgui.PushStyleColor(ImGuiCol_Text, look.TextColor)
        imgui.PushStyleVar(ImGuiStyleVar_FramePadding, noFramePadding)

        organize.Label(window.name)

        content()

        borders.Draw(borderTexture, titles.Gap(window.label))
        titles.Draw(window.label)
        if defaultAnchored then
            -- Linked manual children may follow the live parent, but never write native coordinates
            -- over the user's saved manual position/corner. Alliances have separate parent rectangles.
            organize.Track(window.name,nativeTrackPosition)
        elseif not automatic then organize.Track(window.name, section[window.pos]) end

        imgui.PopStyleVar()
        imgui.PopStyleColor()
    end

    -- Only opted-in real HUD windows are captured, never off-screen anchor measurements,
    -- tooltips or settings. Capture synchronously while this is still ImGui's current window.
    if isOpen and nativeWindow and windows.Capture then windows.Capture(window) end
    imgui.PopStyleVar(2)
    imgui.End()
    imgui.PopStyleVar()
    fonts.Pop(font)
end

return windows
