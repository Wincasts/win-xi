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

        FfxiGreyBg     = { 0.08, 0.08, 0.08, 0.8 },
        FfxiGreyBorder = { 0.69, 0.68, 0.78, 1.0 },
        FfxiAmber      = { 0.81, 0.81, 0.50, 1.0 },

        BorderShadow   = { 1.00, 0.00, 0.00, 1.0 },
    },
}

-- What each UI window is called on its label while organizing
organize.SetLabels({
    ['xitools.me'] = 'Me',
    ['xitools.us.1'] = 'Party',
    ['xitools.us.2'] = 'Alliance 2',
    ['xitools.us.3'] = 'Alliance 3',
    ['xitools.tgt.main'] = 'Target',
    ['xitools.tgt.sub'] = 'Sub-target',
    ['xitools.tgt.tot'] = 'Target of Target',
    ['xitools.pet'] = 'Pet',
    ['xitools.tracker'] = 'Tracker',
    ['xitools.cast'] = 'Cast Bar',
})

-- The theme's padding: the space between a UI window's border and its content, on every side
function ui.GetPadding()
    return theme.GetPadding()
end

-- A fixed window width, widened or narrowed so the content keeps its size whatever the padding is.
-- Automatic widths (-1) are left alone. Uses the padding of the UI window being drawn.
function ui.PaddedWidth(width)
    if width > 0 then
        return width + 2 * (ui.Styles.WindowPadding[1] - basePadding)
    end
    return width
end

-- How full a bar is. A bar with no maximum (the MP of a job without any) is empty, not 0 / 0.
local function BarFraction(cur, max)
    if max > 0 then
        return cur / max
    end
    return 0
end

-- Fading while idle is winxi's: it works out one opacity a frame from the fade settings, and here that
-- is applied to the UI windows of the tools chosen to fade. Suspended while the windows are arranged.
local winxiFade = require('winxi.fade')

-- Call once a frame, before any UI window is drawn
function ui.UpdateFade(gConfig)
    winxiFade.Update(gConfig.fade, organize.IsActive())
end

-- How opaque the given tool's UI windows are this frame: faded if it is one that fades, otherwise fully so.
-- Nothing is looked up unless a fade is actually under way.
local function ToolAlpha(tool, gConfig)
    local alpha = winxiFade.Alpha()
    if alpha >= 1 then
        return 1
    end

    local settings = gConfig.fade
    local fades = tool ~= nil and settings ~= nil and settings.tools[tool] or nil
    if fades ~= nil and fades[1] then
        return alpha
    end
    return 1
end

-- The tool a UI window belongs to, from its name (xitools.us.1 belongs to us). Worked out once per window.
local windowTools = { }

local function WindowAlpha(config, gConfig)
    if winxiFade.Alpha() >= 1 then
        return 1
    end

    local tool = windowTools[config.name]
    if tool == nil then
        tool = config.name:match('^xitools%.(%a+)') or false
        windowTools[config.name] = tool
    end
    return ToolAlpha(tool or nil, gConfig)
end

-- True while the given tool is faded right out, so that it need not be drawn or even prepared
function ui.IsFadedOut(tool, gConfig)
    return ToolAlpha(tool, gConfig) <= 0.01
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

function ui.DrawNormalWindow(config, gConfig, drawStuff)
    if not config.isVisible[1] then
        return
    end

    imgui.SetNextWindowSize(config.size, ImGuiCond_FirstUseEver)
    imgui.SetNextWindowPos(config.pos, ImGuiCond_FirstUseEver)

    if config.maxHeight then
        imgui.SetNextWindowSizeConstraints({ -1, 0 }, { -1, config.maxHeight[1] })
    end

    if imgui.Begin(config.name, config.isVisible, config.flags) then
        drawStuff()

        local x, y = imgui.GetWindowPos()
        config.pos[1] = x
        config.pos[2] = y
    end

    imgui.End()
end

-- The flags a tool's window takes for ui.DrawStyledWindow: no title bar, like the UI windows, but it
-- still scrolls. Tools set these as they draw, since the flags saved with earlier settings were for a
-- titled window. The second is for a window the player can resize.
-- For the settings tabs, winxi's own: a setting's name to the left of its control and followed by a
-- colon (ui.Label), the gap between one family of settings and the next (ui.Gap), and the start of a
-- group of settings whose controls line up with each other (ui.BeginLabels, once per tab).
ui.Label = widgets.Label
ui.Gap = widgets.Gap
ui.BeginLabels = widgets.BeginLabels

ui.StyledWindowFlags = bit.bor(
    ImGuiWindowFlags_NoTitleBar,
    ImGuiWindowFlags_NoResize,
    ImGuiWindowFlags_NoCollapse,
    ImGuiWindowFlags_AlwaysAutoResize)
ui.StyledResizableWindowFlags = bit.bor(
    ImGuiWindowFlags_NoTitleBar,
    ImGuiWindowFlags_NoCollapse)

-- A tool's own window given the look of the UI windows: the theme's background, border, text colour and
-- padding, with its tabs, tables, buttons and other controls tinted from the border colour. Unlike a UI
-- window it keeps its own flags and size, always takes the mouse, and is not linked, faded or shown
-- while organizing.
-- padding, if given, is used in place of the theme's: { x, y }.
local styledPadding = { 0, 0 } -- reused for every styled window, every frame

---@param config table
---@param drawStuff function
---@param padding number[]?
function ui.DrawStyledWindow(config, gConfig, drawStuff, padding)
    if not config.isVisible[1] then
        return
    end

    local look = theme.Get()
    if padding == nil then
        styledPadding[1], styledPadding[2] = look.Padding, look.Padding
        padding = styledPadding
    end

    imgui.SetNextWindowSize(config.size, ImGuiCond_FirstUseEver)
    imgui.SetNextWindowPos(config.pos, ImGuiCond_FirstUseEver)

    if config.maxHeight then
        imgui.SetNextWindowSizeConstraints({ -1, 0 }, { -1, config.maxHeight[1] })
    end

    -- kept until the window has ended: its scrollbar is drawn with these as well as its content
    local colors = theme.Palette()
    for _, entry in ipairs(colors) do
        imgui.PushStyleColor(entry[1], entry[2])
    end

    imgui.PushStyleColor(ImGuiCol_WindowBg, look.BackgroundColor)
    imgui.PushStyleColor(ImGuiCol_Border, look.BorderColor)
    imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, ui.Styles.ItemSpacing)
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, padding)

    local isOpen = imgui.Begin(config.name, config.isVisible, config.flags)
    imgui.PopStyleColor(2)

    if isOpen then
        shadow.Draw()

        imgui.PushStyleColor(ImGuiCol_Text, look.TextColor)
        drawStuff()
        imgui.PopStyleColor()

        local x, y = imgui.GetWindowPos()
        config.pos[1] = x
        config.pos[2] = y
    end

    imgui.PopStyleVar(2)
    imgui.End()
    imgui.PopStyleColor(#colors)
end

local windowSize = { 0, 0 } -- reused for every UI window, every frame

---@param config table
---@param drawStuff function
function ui.DrawUiWindow(config, gConfig, drawStuff)
    if not config.isVisible[1] then
        return
    end

    -- faded right out: nothing to draw
    local alpha = WindowAlpha(config, gConfig)
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

---@param config table
---@param drawStuff function
function ui.DrawInvisWindow(config, gConfig, drawStuff)
    if not config.isVisible[1] then
        return
    end

    -- faded right out: nothing to draw
    local alpha = WindowAlpha(config, gConfig)
    if alpha <= 0.01 then
        return
    end

    local flags = config.flags
    if gConfig.isClickThru[1] and not organize.IsActive() then
        flags = bit.bor(flags, ImGuiWindowFlags_NoInputs)
    end

    imgui.SetNextWindowSize(config.size)
    organize.Place(config.name, config.pos)

    imgui.PushStyleVar(ImGuiStyleVar_Alpha, alpha)
    imgui.PushStyleColor(ImGuiCol_WindowBg, { 0, 0, 0, 0 })
    imgui.PushStyleColor(ImGuiCol_Border, { 0, 0, 0, 0 })
    imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, { 1, 1 })
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, { 1, 1 })

    local isOpen = imgui.Begin(config.name, config.isVisible, flags)
    imgui.PopStyleColor(2)

    if isOpen then
        imgui.PushStyleColor(ImGuiCol_Text, theme.Get().TextColor)
        imgui.PushStyleVar(ImGuiStyleVar_FramePadding, ui.Styles.FramePaddingNone)

        organize.Label(config.name)

        drawStuff()

        organize.Track(config.name, config.pos)

        imgui.PopStyleVar()
        imgui.PopStyleColor()
    end

    imgui.End()
    imgui.PopStyleVar(3)
end

return ui
