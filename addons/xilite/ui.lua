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

local txtW, txtH = imgui.CalcTextSize('HP 100%')

-- The window padding the fixed window widths were laid out for
local basePadding = 10

local ui = {
    Styles = {
        ItemSpacing       = { 8, 4 },
        WindowPadding     = { 10, 10 },
        FramePaddingNone  = { 0, 0 },
        FramePaddingSome  = { 4, 2 },
        BarSize           = { 248 - txtW, txtH }, -- 276 std width, 20 std padding, 8 spacing
        ShortBarSize      = {  80, txtH },
    },
    Colors = {
        White          = { 1.00, 1.00, 1.00, 1.0 },
        Yellow         = { 1.00, 1.00, 0.00, 1.0 },
        Orange         = { 1.00, 0.64, 0.00, 1.0 },
        Red            = { 0.95, 0.20, 0.20, 1.0 },

        HpBar          = { 0.83, 0.33, 0.28, 1.0 },
        MpBar          = { 0.82, 0.60, 0.27, 1.0 },
        Blue           = { 0.23, 0.67, 0.91, 1.0 },

        -- The TP bar while TP is building, and once a weaponskill can be used. Both are settings
        -- (Appearance tab): xilite points these at the chosen colours when its settings are loaded.
        TpBar          = { 1.00, 1.00, 1.00, 1.0 },
        TpBarActive    = { 0.23, 0.67, 0.91, 1.0 },
        XpBar          = { 0.01, 0.67, 0.07, 1.0 },
        LpBar          = { 0.61, 0.32, 0.71, 1.0 },
        BarBorder      = { 0.07, 0.07, 0.07, 1.0 }, --#13131f
        BarBackground  = { 0.16, 0.17, 0.20, 1.0 }, --#292b33

        StatusGrey     = { 1.00, 1.00, 1.00, 0.5 },
        StatusWhite    = { 0.98, 0.92, 0.84, 1.0 },
        StatusBlack    = { 0.60, 0.20, 0.80, 1.0 },
        StatusYellow   = { 0.80, 0.80, 0.80, 1.0 },
        StatusBrown    = { 1.00, 0.96, 0.56, 1.0 },
        StatusGreen    = { 0.60, 0.80, 0.20, 1.0 },
        StatusBlue     = { 0.28, 0.46, 1.00, 1.0 },
        StatusRed      = { 0.80, 0.22, 0.00, 1.0 },
        StatusCyan     = { 0.59, 0.80, 0.80, 1.0 },

        FfxiAmber      = { 0.81, 0.81, 0.50, 1.0 },
    },
}

-- What each UI window is called on its label while organizing
organize.SetLabels({
    ['xilite.me'] = 'Me',
    ['xilite.us.1'] = 'Party',
    ['xilite.us.2'] = 'Alliance 2',
    ['xilite.us.3'] = 'Alliance 3',
    ['xilite.tgt.main'] = 'Target',
    ['xilite.tgt.sub'] = 'Sub-target',
    ['xilite.tgt.tot'] = 'Target of Target',
    ['xilite.pet'] = 'Pet',
})

-- A fixed window width, widened or narrowed so the content keeps its size whatever the padding is.
-- Automatic widths (-1) are left alone. Uses the padding of the UI window being drawn.
function ui.PaddedWidth(width)
    if width > 0 then
        return width + 2 * (ui.Styles.WindowPadding[1] - basePadding)
    end
    return width
end

-- TP at which a weaponskill can be used
local tpReady = 1000

-- Experimental, a setting (Appearance tab): the player's own TP bar pulses once a weaponskill can be
-- used, fading from the building colour to the ready colour and back, once every tpFlashPeriod seconds.
-- xilite points this at the setting's { true or false } when its settings are loaded.
ui.TpBarFlash = { false }

local tpFlashPeriod = 1.2
local tpFlashColor = { 0, 0, 0, 0 } -- reused: the colour is handed to imgui and copied there at once

-- The colour of a TP bar showing the given TP. isOwn is true for the player's own bar, which is the one
-- that flashes when that is switched on; anyone else's simply takes the ready colour.
function ui.TpBarColor(tp, isOwn)
    if tp < tpReady then
        return ui.Colors.TpBar
    end
    if not isOwn or not ui.TpBarFlash[1] then
        return ui.Colors.TpBarActive
    end

    -- 0 at the building colour, 1 at the ready colour, moving smoothly from one to the other and back
    local phase = (os.clock() % tpFlashPeriod) / tpFlashPeriod
    local blend = 0.5 - 0.5 * math.cos(phase * 2 * math.pi)

    local from, to, color = ui.Colors.TpBar, ui.Colors.TpBarActive, tpFlashColor
    for channel = 1, 4 do
        color[channel] = from[channel] + (to[channel] - from[channel]) * blend
    end
    return color
end

-- How full a bar is. A bar with no maximum (the MP of a job without any) is empty, not 0 / 0.
local function BarFraction(cur, max)
    if max > 0 then
        return cur / max
    end
    return 0
end

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

-- The tool a window belongs to, from its name (xilite.us.1 belongs to us). Worked out once per window.
local windowTools = { }

local function WindowTool(config)
    local tool = windowTools[config.name]
    if tool == nil then
        tool = config.name:match('^xilite%.(%a+)') or false
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

---@param title   string
---@param cur     integer
---@param max     integer
---@param overlay string?
function ui.DrawBar(title, cur, max, size, overlay)
    local fraction = BarFraction(cur, max)

    imgui.PushStyleColor(ImGuiCol_FrameBg, ui.Colors.BarBackground)
    imgui.PushStyleColor(ImGuiCol_Border, ui.Colors.BarBorder)

    imgui.AlignTextToFramePadding()
    imgui.Text(title)
    imgui.SameLine()
    imgui.ProgressBar(fraction, size, overlay)

    imgui.PopStyleColor(2)
end

---@param cur     integer
---@param max     integer
---@param size    Vec2
---@param overlay string?
function ui.DrawBar2(cur, max, size, overlay)
    local fraction = BarFraction(cur, max)

    imgui.PushStyleColor(ImGuiCol_FrameBg, ui.Colors.BarBackground)
    imgui.PushStyleColor(ImGuiCol_Border, ui.Colors.BarBorder)

    imgui.AlignTextToFramePadding()
    imgui.ProgressBar(fraction, size, overlay)

    imgui.PopStyleColor(2)
end

---@param cur     integer
---@param max     integer
---@param size    Vec2
---@param overlay string?
function ui.DrawBar3(cur, max, size, overlay)
    local fraction = BarFraction(cur, max)
    local borderColor = ui.Colors.BarBorder

    if max > 0 and fraction <= 0.25 then
        borderColor = ui.Colors.Red
    elseif max > 0 and fraction <= 0.50 then
        borderColor = ui.Colors.Orange
    elseif max > 0 and fraction <= 0.75 then
        borderColor = ui.Colors.Yellow
    end

    imgui.PushStyleColor(ImGuiCol_FrameBg, ui.Colors.BarBackground)
    imgui.PushStyleColor(ImGuiCol_Border, borderColor)

    imgui.AlignTextToFramePadding()
    imgui.ProgressBar(fraction, size, overlay)

    imgui.PopStyleColor(2)
end

-- For the settings tabs, winxi's own: a setting's name to the left of its control and followed by a
-- colon (ui.Label), the gap between one family of settings and the next (ui.Gap), and the start of a
-- group of settings whose controls line up with each other (ui.BeginLabels, once per tab).
ui.Label = widgets.Label
ui.Gap = widgets.Gap
ui.BeginLabels = widgets.BeginLabels

local windowSize = { 0, 0 } -- reused for every UI window, every frame

-- wanted is false for a window that is being drawn only to fade out (see ui.Lingers); otherwise leave it out
---@param config table
---@param drawStuff function
---@param wanted boolean?
function ui.DrawUiWindow(config, gConfig, drawStuff, wanted)
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

    -- Kept in ui.Styles so the tools' own right-alignment sums see the padding in use
    local look = theme.Get()
    local padding = look.Padding
    ui.Styles.WindowPadding[1] = padding
    ui.Styles.WindowPadding[2] = padding

    windowSize[1], windowSize[2] = ui.PaddedWidth(config.size[1]), config.size[2]
    imgui.SetNextWindowSize(windowSize)
    organize.Place(config.name, config.pos)

    imgui.PushStyleVar(ImGuiStyleVar_Alpha, alpha)
    imgui.PushStyleColor(ImGuiCol_WindowBg, look.BackgroundColor)
    imgui.PushStyleColor(ImGuiCol_Border, look.BorderColor)
    imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, ui.Styles.ItemSpacing)
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, ui.Styles.WindowPadding)

    local isOpen = imgui.Begin(config.name, config.isVisible, flags)
    imgui.PopStyleColor(2)

    if isOpen then
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
