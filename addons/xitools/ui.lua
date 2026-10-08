local bit = require('bit')
local imgui = require('imgui')

-- The look of every window (colours, padding, drop shadow) is winxi's theme: the one shared with other
-- addons, or this addon's own, as chosen in the Appearance tab
local theme = require('winxi.theme')
local shadow = require('winxi.shadow')

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

-- Set by xitools while its sample windows are showing. Click-through is ignored then, so that the
-- windows can be dragged into place.
ui.IsSampleMode = false

-- What each UI window is called on its label while the sample windows are showing
local sampleLabels = {
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
}

-- Names the window being drawn while the sample windows are showing. The name goes just above the
-- window, outside it, so the window keeps its real size; below it when there is no room above.
local function DrawSampleLabel(config)
    local text = sampleLabels[config.name] or config.name

    -- Older builds cannot draw outside a window: there the name becomes the window's first line
    if imgui.GetForegroundDrawList == nil then
        imgui.PushStyleColor(ImGuiCol_Text, ui.Colors.FfxiAmber)
        imgui.Text(('[ %s ]'):format(text))
        imgui.PopStyleColor()
        return
    end

    local x, y = imgui.GetWindowPos()
    local _, windowHeight = imgui.GetWindowSize()
    local textWidth, textHeight = imgui.CalcTextSize(text)

    local labelY = y - textHeight - 6
    if labelY < 0 then
        labelY = y + windowHeight + 2
    end

    local drawList = imgui.GetForegroundDrawList()
    drawList:AddRectFilled({ x, labelY }, { x + textWidth + 8, labelY + textHeight + 4 }, imgui.GetColorU32(ui.Colors.FfxiGreyBg), 2)
    drawList:AddText({ x + 4, labelY + 2 }, imgui.GetColorU32(ui.Colors.FfxiAmber), text)
end

local gridSpacing = 25
local gridColor = { 1.0, 1.0, 1.0, 0.12 }
local gridCenterColor = { 1.0, 1.0, 1.0, 0.45 }
local gridVisible = { true }

-- A grid over the whole screen for lining windows up against, with bold lines through the centre.
-- The lines are spaced outwards from the centre, so the grid is the same on both sides of it.
-- Drawn in a see-through window of its own that takes no input and stays behind the others.
function ui.DrawGrid()
    local display = imgui.GetIO().DisplaySize
    local width, height = display.x, display.y
    local centerX, centerY = math.floor(width / 2), math.floor(height / 2)

    local flags = bit.bor(
        ImGuiWindowFlags_NoDecoration,
        ImGuiWindowFlags_NoInputs,
        ImGuiWindowFlags_NoSavedSettings,
        ImGuiWindowFlags_NoBackground or 0,
        ImGuiWindowFlags_NoBringToFrontOnFocus or 0,
        ImGuiWindowFlags_NoFocusOnAppearing or 0)

    imgui.SetNextWindowPos({ 0, 0 })
    imgui.SetNextWindowSize({ width, height })
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, { 0, 0 })

    if imgui.Begin('xitools.grid', gridVisible, flags) then
        local drawList = imgui.GetWindowDrawList()
        local thin = imgui.GetColorU32(gridColor)
        local bold = imgui.GetColorU32(gridCenterColor)

        for offset = gridSpacing, math.max(centerX, centerY), gridSpacing do
            if offset <= centerX then
                drawList:AddLine({ centerX - offset, 0 }, { centerX - offset, height }, thin, 1)
                drawList:AddLine({ centerX + offset, 0 }, { centerX + offset, height }, thin, 1)
            end
            if offset <= centerY then
                drawList:AddLine({ 0, centerY - offset }, { width, centerY - offset }, thin, 1)
                drawList:AddLine({ 0, centerY + offset }, { width, centerY + offset }, thin, 1)
            end
        end

        drawList:AddLine({ centerX, 0 }, { centerX, height }, bold, 3)
        drawList:AddLine({ 0, centerY }, { width, centerY }, bold, 3)
    end

    imgui.End()
    imgui.PopStyleVar()
    gridVisible[1] = true
end

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

-- Linked windows. A link holds one UI window (the child) against a side of another (the parent), a fixed
-- gap away, and keeps it there as the parent moves or changes size. Links are made by dropping one window
-- onto another while organizing, and are saved with the settings.
local linkGap = 5
local links = { }      -- { child = window name, parent = window name, side = 'below'|'above'|'right'|'left' }
local rects = { }      -- window name -> where it was last drawn: { x, y, w, h, frame }
local frame = 0
local dragging = nil   -- the window the mouse went down on, and where it was then: { name, x, y }
local unlinkVisible = { true }
local linkedPos = { 0, 0 }

-- Hands over the saved list of links, which is then added to and removed from in place
function ui.SetLinks(savedLinks)
    links = savedLinks
end

local function FindLink(child)
    for i, link in ipairs(links) do
        if link.child == child then
            return link, i
        end
    end
    return nil
end

-- True when ancestor is the parent of name, or its parent's parent, and so on
local function IsLinkedUnder(name, ancestor)
    local link = FindLink(name)
    local steps = 0
    while link ~= nil and steps < 32 do
        if link.parent == ancestor then
            return true
        end
        link = FindLink(link.parent)
        steps = steps + 1
    end
    return false
end

-- Where a linked window belongs, from where its parent was last drawn. Nothing when it has no link,
-- or when there is not yet enough to go on.
local function LinkedPos(name)
    local link = FindLink(name)
    if link == nil then
        return nil
    end

    local parent = rects[link.parent]
    if parent == nil then
        return nil
    end

    -- the same table is handed back each time, to be used at once: this runs for every window, every frame
    local pos = linkedPos
    if link.side == 'below' then
        pos[1], pos[2] = parent.x, parent.y + parent.h + linkGap
        return pos
    elseif link.side == 'right' then
        pos[1], pos[2] = parent.x + parent.w + linkGap, parent.y
        return pos
    end

    -- above and to the left depend on the window's own size as well
    local own = rects[name]
    if own == nil then
        return nil
    end

    if link.side == 'above' then
        pos[1], pos[2] = parent.x, parent.y - linkGap - own.h
    else
        pos[1], pos[2] = parent.x - linkGap - own.w, parent.y
    end
    return pos
end

-- Positions the window about to be drawn: against its parent if it is linked, unless it is the one
-- being dragged, otherwise wherever it was left
local function PlaceWindow(config)
    local pos = nil
    if dragging == nil or dragging.name ~= config.name then
        pos = LinkedPos(config.name)
    end

    if pos ~= nil then
        config.pos[1] = pos[1]
        config.pos[2] = pos[2]
        imgui.SetNextWindowPos(pos, ImGuiCond_Always)
    else
        imgui.SetNextWindowPos(config.pos, ImGuiCond_FirstUseEver)
    end
end

-- Notes where the window being drawn is, and whether a drag has just started on it
local function TrackWindow(config)
    local x, y = imgui.GetWindowPos()
    local w, h = imgui.GetWindowSize()

    config.pos[1] = x
    config.pos[2] = y

    local rect = rects[config.name]
    if rect == nil then
        rect = { }
        rects[config.name] = rect
    end
    rect.x, rect.y, rect.w, rect.h, rect.frame = x, y, w, h, frame

    if ui.IsSampleMode and dragging == nil and imgui.IsWindowHovered() and imgui.IsMouseClicked(0) then
        dragging = { name = config.name, x = x, y = y }
    end
end

-- A dragged window has been let go. If it was dropped overlapping another UI window it is linked to
-- that one (the one it overlaps most), on whichever side it was dropped towards.
local function ResolveDrop(drag)
    local own = rects[drag.name]
    if own == nil then
        return
    end

    -- a click, not a drag
    if math.abs(own.x - drag.x) < 3 and math.abs(own.y - drag.y) < 3 then
        return
    end

    local target, targetArea = nil, 0
    for name, other in pairs(rects) do
        -- only windows on screen now, and never one that is itself held against the dragged window
        if name ~= drag.name and other.frame >= frame - 1 and not IsLinkedUnder(name, drag.name) then
            local overlapW = math.min(own.x + own.w, other.x + other.w) - math.max(own.x, other.x)
            local overlapH = math.min(own.y + own.h, other.y + other.h) - math.max(own.y, other.y)
            if overlapW > 0 and overlapH > 0 and overlapW * overlapH > targetArea then
                target, targetArea = name, overlapW * overlapH
            end
        end
    end

    if target == nil then
        return
    end

    -- which side: compare the two centres, scaled so a wide window does not always win sideways
    local other = rects[target]
    local dx = ((own.x + own.w / 2) - (other.x + other.w / 2)) / ((own.w + other.w) / 2)
    local dy = ((own.y + own.h / 2) - (other.y + other.h / 2)) / ((own.h + other.h) / 2)

    local side
    if math.abs(dy) >= math.abs(dx) then
        side = dy >= 0 and 'below' or 'above'
    else
        side = dx >= 0 and 'right' or 'left'
    end

    local link = FindLink(drag.name)
    if link ~= nil then
        link.parent = target
        link.side = side
    else
        table.insert(links, { child = drag.name, parent = target, side = side })
    end
end

-- Call once a frame, before any UI window is drawn
function ui.BeginFrame()
    frame = frame + 1

    if dragging ~= nil and not imgui.IsMouseDown(0) then
        if ui.IsSampleMode then
            ResolveDrop(dragging)
        end
        dragging = nil
    end
end

-- A small floating Unlink button beside each linked window, for breaking its link. Call after the UI
-- windows have been drawn, while organizing.
function ui.DrawLinkButtons()
    local flags = bit.bor(
        ImGuiWindowFlags_NoDecoration,
        ImGuiWindowFlags_AlwaysAutoResize,
        ImGuiWindowFlags_NoSavedSettings,
        ImGuiWindowFlags_NoMove or 0,
        ImGuiWindowFlags_NoFocusOnAppearing or 0)

    for i = #links, 1, -1 do
        local link = links[i]
        local rect = rects[link.child]

        if rect ~= nil and rect.frame == frame then
            -- beside the window's top corner, on the side away from its parent
            if link.side == 'left' then
                imgui.SetNextWindowPos({ rect.x - 4, rect.y }, ImGuiCond_Always, { 1, 0 })
            else
                imgui.SetNextWindowPos({ rect.x + rect.w + 4, rect.y }, ImGuiCond_Always)
            end

            imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, { 4, 4 })
            if imgui.Begin('xitools.unlink.' .. link.child, unlinkVisible, flags) then
                if imgui.Button('Unlink') then
                    table.remove(links, i)
                end
                if imgui.IsItemHovered() then
                    imgui.SetTooltip(('Stop holding %s against %s.'):format(
                        sampleLabels[link.child] or link.child, sampleLabels[link.parent] or link.parent))
                end
            end
            imgui.End()
            imgui.PopStyleVar()
            unlinkVisible[1] = true
        end
    end
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
    winxiFade.Update(gConfig.fade, ui.IsSampleMode)
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
    if gConfig.isClickThru[1] and not ui.IsSampleMode then
        flags = bit.bor(flags, ImGuiWindowFlags_NoInputs)
    end

    -- Kept in ui.Styles so the tools' own right-alignment sums see the padding in use
    local look = theme.Get()
    local padding = look.Padding
    ui.Styles.WindowPadding[1] = padding
    ui.Styles.WindowPadding[2] = padding

    windowSize[1], windowSize[2] = ui.PaddedWidth(config.size[1]), config.size[2]
    imgui.SetNextWindowSize(windowSize)
    PlaceWindow(config)

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

        if ui.IsSampleMode then
            DrawSampleLabel(config)
        end

        drawStuff()

        TrackWindow(config)

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
    if gConfig.isClickThru[1] and not ui.IsSampleMode then
        flags = bit.bor(flags, ImGuiWindowFlags_NoInputs)
    end

    imgui.SetNextWindowSize(config.size)
    PlaceWindow(config)

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

        if ui.IsSampleMode then
            DrawSampleLabel(config)
        end

        drawStuff()

        TrackWindow(config)

        imgui.PopStyleVar()
        imgui.PopStyleColor()
    end

    imgui.End()
    imgui.PopStyleVar(3)
end

return ui
