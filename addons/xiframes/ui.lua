local bit = require('bit')
local imgui = require('imgui')

-- The look of every window (colours, padding, drop shadow) is winxi's theme: the one shared with other
-- addons, or this addon's own, as chosen in the Appearance tab
local theme = require('winxi.theme')
local shadow = require('winxi.shadow')
local widgets = require('winxi.widgets')

-- Arranging the windows (the Organize button: sample data, labels, the grid, and linking one window to
-- another) is winxi's too. Here its windows are the UI windows.
local organize = require('winxi.organize')

-- A window that grows from a corner other than its top left (the party list grows upwards) is held by
-- that corner by winxi.anchor
local anchor = require('winxi.anchor')

local ui = {
    Styles = {
        ItemSpacing       = { 8, 4 },
        WindowPadding     = { 10, 10 },
        FramePaddingNone  = { 0, 0 },
        FramePaddingSome  = { 4, 2 },
    },
    Colors = {
        Blue           = { 0.23, 0.67, 0.91, 1.0 }, -- the member targeted
        Party          = { 0.90, 0.88, 0.35, 1.0 }, -- a party's: its leader's mark, and an invitation to one
        Alliance       = { 0.90, 0.25, 0.22, 1.0 }, -- an alliance's: the same two
        Green          = { 0.01, 0.67, 0.07, 1.0 }, -- the member a sub-target or the party cursor is on

        StatusGrey     = { 1.00, 1.00, 1.00, 0.5 },
        StatusWhite    = { 0.98, 0.92, 0.84, 1.0 },
        StatusBlack    = { 0.60, 0.20, 0.80, 1.0 },
        StatusYellow   = { 0.80, 0.80, 0.80, 1.0 },
        StatusBrown    = { 1.00, 0.96, 0.56, 1.0 },
        StatusGreen    = { 0.60, 0.80, 0.20, 1.0 },
        StatusBlue     = { 0.28, 0.46, 1.00, 1.0 },
        StatusRed      = { 0.80, 0.22, 0.00, 1.0 },
        StatusCyan     = { 0.59, 0.80, 0.80, 1.0 },
    },
}

-- What each UI window is called on its label while organizing
organize.SetLabels({
    ['xiframes.us.1'] = 'Party',
    ['xiframes.us.2'] = 'Alliance 2',
    ['xiframes.us.3'] = 'Alliance 3',
    ['xiframes.tgt.main'] = 'Target',
    ['xiframes.tgt.sub'] = 'Sub-target',
    ['xiframes.tgt.tot'] = 'Target of Target',
})

-- Fading while idle is winxi's: it works out one opacity a frame from the fade settings, and here that
-- is applied to the UI windows of the tools chosen to fade. Suspended while the windows are arranged,
-- and while the game's party cursor is out (a member is being picked from the party list, in the
-- party menu or as a sub-target): the party windows are being read then, however still the player is.
local winxiFade = require('winxi.fade')
local ffxiUtils = require('utils/ffxi')

-- Call once a frame, before any UI window is drawn
function ui.UpdateFade(gConfig)
    winxiFade.Update(gConfig.fade, organize.IsActive() or ffxiUtils.GetStPartyIndex() ~= nil)
end

-- Whether the given tool is one whose windows fade: fading is switched on, and the tool is one of those
-- chosen for it
local function ToolFades(tool, gConfig)
    local settings = gConfig.fade
    if tool == nil or settings == nil or not settings.Enabled then
        return false
    end

    local chosen = settings.tools[tool]
    return chosen ~= nil and chosen[1] and true or false
end

-- The tool a window belongs to, from its name (xiframes.us.1 belongs to us). Worked out once per window.
local windowTools = { }

local function WindowTool(config)
    local tool = windowTools[config.name]
    if tool == nil then
        tool = config.name:match('^xiframes%.(%a+)') or false
        windowTools[config.name] = tool
    end
    return tool or nil
end

-- How opaque a window is this frame. A window of a tool that fades fades in when it appears and out
-- when it is no longer wanted, and (with idle set, for the UI windows) fades with the player's idling
-- as well. Any other window is simply there or not. wanted is whether the window should be showing.
local function WindowAlpha(config, gConfig, wanted, idle)
    if organize.IsActive() or not ToolFades(WindowTool(config), gConfig) then
        return wanted and 1 or 0
    end

    local alpha = winxiFade.Presence(config.name, wanted)
    if idle then
        alpha = alpha * winxiFade.Alpha()
    end
    return alpha
end

-- True while a window that is no longer wanted has not finished fading out. A tool that can still draw
-- such a window's content goes on drawing it, passing wanted as false, until this is false.
function ui.Lingers(config, gConfig)
    if organize.IsActive() or not ToolFades(WindowTool(config), gConfig) then
        return false
    end
    return winxiFade.Lingering(config.name)
end

-- True while the given tool's UI windows are faded right out by idling, so that it need not be drawn
-- or even prepared
function ui.IsFadedOut(tool, gConfig)
    return ToolFades(tool, gConfig) and winxiFade.Alpha() <= 0.01
end

-- For the settings tabs, winxi's own: a setting's name to the left of its control and followed by a
-- colon (ui.Label), the gap between one family of settings and the next (ui.Gap), and the start of a
-- group of settings whose controls line up with each other (ui.BeginLabels, once per tab).
ui.Label = widgets.Label
ui.Gap = widgets.Gap
ui.BeginLabels = widgets.BeginLabels

local windowSize = { -1, -1 } -- every window sizes itself

-- The windows whose saved corner has been handed to winxi.anchor: once for each settings table, so a
-- character's own are used after a change of character
local cornerGiven = setmetatable({ }, { __mode = 'k' })

-- Forgets the corner a window is held by, so that it stays wherever it is put next: for a window that
-- has been moved by other means than dragging it
function ui.ForgetCorner(config)
    anchor.Reset(config.name)
    config.corner = nil
    cornerGiven[config] = nil
end

-- wanted is false for a window that is being drawn only to fade out (see ui.Lingers); otherwise leave it out
-- growFrom, if given, is the corner that stays where it is as the window's content changes size (one of
-- winxi.anchor's: 'BottomLeft' for a window that grows upwards). The corner is kept in the window's
-- settings as corner, beside pos. drawStuff is then called twice a frame, once to measure. A window
-- linked to another while organizing is placed by its link instead.
-- Every window is as big as what is drawn in it.
---@param config table
---@param drawStuff function
---@param wanted boolean?
---@param growFrom string?
function ui.DrawUiWindow(config, gConfig, drawStuff, wanted, growFrom)
    if not config.isVisible[1] then
        return
    end

    -- faded right out: nothing to draw
    local alpha = WindowAlpha(config, gConfig, wanted ~= false, true)
    if alpha <= 0.01 then
        return
    end

    local flags = config.flags
    if gConfig.isClickThru[1] and not organize.IsActive() then
        flags = bit.bor(flags, ImGuiWindowFlags_NoInputs)
    end

    local look = theme.Get()
    local padding = look.Padding
    ui.Styles.WindowPadding[1] = padding
    ui.Styles.WindowPadding[2] = padding

    -- held by a corner other than its top left, unless a link places it: its size is then measured
    -- before it is drawn (below), and it is given exactly that
    local held = growFrom ~= nil and not organize.IsLinked(config.name)

    if not held then
        flags = bit.bor(flags, ImGuiWindowFlags_AlwaysAutoResize)
    end
    imgui.SetNextWindowSize(windowSize)
    organize.Place(config.name, config.pos)

    imgui.PushStyleVar(ImGuiStyleVar_Alpha, alpha)
    imgui.PushStyleColor(ImGuiCol_WindowBg, look.BackgroundColor)
    imgui.PushStyleColor(ImGuiCol_Border, look.BorderColor)
    imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, ui.Styles.ItemSpacing)
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, ui.Styles.WindowPadding)

    if held then
        if not cornerGiven[config] then
            cornerGiven[config] = true
            local corner = config.corner
            if type(corner) == 'table' and corner[1] ~= nil and corner[2] ~= nil then
                anchor.Set(config.name, growFrom, corner[1], corner[2])
            else
                anchor.Reset(config.name)
            end
        end

        -- laid out off screen first, as it will be drawn, so the window can be put where its new size
        -- leaves the corner alone
        imgui.PushStyleVar(ImGuiStyleVar_FramePadding, ui.Styles.FramePaddingNone)
        anchor.Measure(config.name, growFrom, drawStuff, padding)
        imgui.PopStyleVar()
        anchor.Place(config.name, growFrom)
    elseif config.corner ~= nil then
        ui.ForgetCorner(config)
    end

    local isOpen = imgui.Begin(config.name, config.isVisible, flags)
    imgui.PopStyleColor(2)

    if isOpen then
        if held then
            anchor.Track(config.name, growFrom)
            local x, y = anchor.Point(config.name)
            if x ~= nil then
                if type(config.corner) ~= 'table' then
                    config.corner = T{ }
                end
                config.corner[1], config.corner[2] = x, y
            end
        end

        shadow.Draw()

        imgui.PushStyleColor(ImGuiCol_Text, look.TextColor)
        imgui.PushStyleVar(ImGuiStyleVar_FramePadding, ui.Styles.FramePaddingNone)

        organize.Label(config.name)

        drawStuff()

        organize.Track(config.name, config.pos)

        imgui.PopStyleVar()
        imgui.PopStyleColor()
    end

    imgui.PopStyleVar(2)
    imgui.End()
    imgui.PopStyleVar()
end

return ui
