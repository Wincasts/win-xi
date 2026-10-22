addon.name    = 'menus'
addon.author  = 'win'
addon.version = '0.1'
addon.desc    = 'Draws the game\'s menus in the winxi look, mirroring the real ones, which keep working as they are.'
addon.link    = 'https://github.com/Wincasts/win-xi'

-- The game's own menus stay open and do everything they do: the controller moves their cursor, Confirm
-- and Cancel are theirs, and what they show is what the game shows. uihook leaves them undrawn and says
-- what they would have drawn (where each piece of text went, the icons, the cursor, the scrollbar), and
-- this draws them again in the winxi theme, each piece where the game put it, so the game's cursor and
-- hit-tests still line up with what is seen.
--
--   /menus    opens or closes the settings
--
-- Needs uihook 0.96 or newer, for its menu mirror. Which menus are mirrored, and whether in their place
-- or as outlines over the game's (to check what is measured), is in the settings.

-- The winxi this addon was made with, or a newer one: each addon is released with its own copy, so an
-- older one may have been put over it (winxi.version)
local winxiNeeded = 33
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
local bit = require('bit')
local imgui = require('imgui')
local widgets = require('winxi.widgets')
local tooltip = require('winxi.tooltip')
local shell = require('winxi.shell')
local theme = require('winxi.theme')
local frame = require('winxi.frame')
local fonts = require('winxi.fonts')
local text = require('winxi.text')
local cursorArt = require('winxi.cursor')
local nativemirror = require('winxi.nativemirror')

-- The menus that can be mirrored, as the settings list them: the game's name for each window, and ours.
-- The item lists share one drawer in the game, so what works for one works for the others.
local Menus = {
    { name = 'inventor', label = 'Inventory', tip = 'The list of what you carry.' },
    { name = 'iteminfo', label = 'Item Info', tip = 'The box under an item list that describes the item the cursor is on.' },
    { name = 'bank', label = 'Mog Safe', tip = 'The list of what is in your Mog Safe and the other places items are kept.' },
    { name = 'shop', label = 'Shop', tip = 'A shop\'s list of what it sells.' },
}
local Modes = { 'Replace', 'Outline' }

local defaults = T{
    mode = 'Replace',
}
for _, menu in ipairs(Menus) do
    defaults['mirror_' .. menu.name] = T{ true }
end

local app
local mirror = nativemirror.new()

---------------------------------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------------------------------

local function Save() app:Save() end

local modeIds = {}
for _, mode in ipairs(Modes) do modeIds[mode] = mode .. '##menus.mode' end

local function DrawSettings(options)
    if widgets.Header('Menus', true) then
        for _, menu in ipairs(Menus) do
            widgets.Label(menu.label)
            if imgui.Checkbox('##menus.' .. menu.name, options['mirror_' .. menu.name]) then Save() end
            tooltip.Hover(menu.tip .. ' Off, the game draws its own.')
        end
    end
    if widgets.Header('Mirror') then
        widgets.Label('Mirror Mode')
        for index, mode in ipairs(Modes) do
            if index > 1 then imgui.SameLine() end
            if imgui.RadioButton(modeIds[mode], options.mode == mode) and options.mode ~= mode then
                options.mode = mode
                Save()
            end
        end
        tooltip.Hover('Replace: the game\'s menus are left undrawn and drawn again in the winxi look. Outline: the game draws its own, with what is measured of it outlined over it, to check by.')
        widgets.Label('Status')
        imgui.TextWrapped(mirror.Status())
        local now = os.clock()
        for _, menu in ipairs(Menus) do
            if nativeUntil[menu.name] and now < nativeUntil[menu.name] + 10 then
                imgui.TextWrapped(('%s was given back to the game: %s.'):format(menu.label, nativeWhy[menu.name] or 'not measured'))
            end
        end
    end
end

local function Complete(options)
    options.useSharedTheme = true
    for _, menu in ipairs(Menus) do
        local key = 'mirror_' .. menu.name
        if type(options[key]) ~= 'table' or type(options[key][1]) ~= 'boolean' then options[key] = T{ true } end
    end
    local known = false
    for _, mode in ipairs(Modes) do known = known or options.mode == mode end
    if not known then options.mode = 'Replace' end
end

app = shell.New({
    defaults = defaults,
    configTitle = 'Menus Settings',
    command = '/menus',
    help = '/menus opens or closes the settings.',
    drawSettings = DrawSettings,
    hideAppearance = true,
    onSettings = Complete,
})

---------------------------------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------------------------------

-- A window left undrawn whose place, or whose text's, could not be measured is given back to the game for a
-- while, so a menu is never left unseen or half drawn: its name -> the time until which it is the game's, and
-- why, for the settings
local nativeUntil, nativeWhy = {}, {}
local FALLBACK_SECONDS = 2
local function GiveBack(name, why, now)
    nativeUntil[name] = now + FALLBACK_SECONDS
    nativeWhy[name] = why
end
-- How much of a window's text has no measured place: the game printed it, but not with the draws uihook
-- measures, so it could not be drawn where it goes
local function Unplaced(window)
    local missing = 0
    for _, run in ipairs(window.runs) do
        if not run.rect and run.text ~= '' then missing = missing + 1 end
    end
    return missing
end

local white = { 1, 1, 1, 1 }
-- The game's plain text colour (0x80808080) is the theme's; any other, the game's own (an item's rarity)
local function TextColor(color)
    if color[1] == 1 and color[2] == 1 and color[3] == 1 then
        local themed = theme.Get().TextColor
        return { themed[1], themed[2], themed[3], themed[4] * color[4] }
    end
    return color
end

local function Width(r) return r[3] - r[1] end
local function Height(r) return r[4] - r[2] end

-- The row the game's cursor is on: the run whose middle is nearest the cursor's, in the same window
local function CursorRow(window)
    local c = window.cursor
    if not c then return nil end
    local middle, best, row = (c[2] + c[4]) / 2, math.huge, nil
    for _, run in ipairs(window.runs) do
        local r = run.rect
        if r then
            local distance = math.abs((r[2] + r[4]) / 2 - middle)
            if distance < best then best, row = distance, r end
        end
    end
    return best < 12 and row or nil
end

local function DrawContents(list, window)
    local r = window.rect
    local pad = 4
    -- the row the cursor is on, lit across the window, under everything else
    local row = window.selection or CursorRow(window)
    if row then
        local highlight = theme.Get().HighlightColor
        list:AddRectFilled({ r[1] + pad, row[2] - 1 }, { r[3] - pad, row[4] + 1 }, imgui.GetColorU32(highlight), 3)
    end
    -- the game's art in the contents (icons), as the game drew it
    for _, quad in ipairs(window.quads) do
        if quad.texture then
            local q, uv = quad.rect, quad.uv
            list:AddImage(quad.texture, { q[1], q[2] }, { q[3], q[4] }, { uv[1], uv[2] }, { uv[3], uv[4] }, imgui.GetColorU32(quad.color))
        end
    end
    -- the text, each run where the game printed it, in the theme's font at the height of the game's letters
    for _, run in ipairs(window.runs) do
        local t = run.rect
        if t and run.text ~= '' then
            local size = math.max(8, math.floor(Height(t) + 0.5))
            imgui.PushFont(nil, size)
            text.Draw(list, t[1], t[2] + (Height(t) - size) / 2, TextColor(run.color), run.text)
            imgui.PopFont()
        end
    end
    -- the scrollbar: the rows shown against them all, where there are more than fit
    local s = window.scroll
    if s and window.scrollCount > window.scrollPage and window.scrollCount > 0 then
        local track = theme.Get().BorderColor or white
        local thumb = theme.Get().HighlightColor
        local width = math.max(3, math.min(6, Width(s)))
        local left = s[3] - width
        list:AddRectFilled({ left, s[2] }, { s[3], s[4] }, imgui.GetColorU32({ track[1], track[2], track[3], 0.25 }), 2)
        local top = s[2] + Height(s) * window.scrollTop / window.scrollCount
        local bottom = s[2] + Height(s) * math.min(1, (window.scrollTop + window.scrollPage) / window.scrollCount)
        list:AddRectFilled({ left, top }, { s[3], bottom }, imgui.GetColorU32({ thumb[1], thumb[2], thumb[3], 1 }), 2)
    end
    -- the game's hand where the game drew it
    local c = window.cursor
    if c then
        local handle, art = cursorArt.Get()
        if handle then
            list:AddImage(handle, { c[1], c[2] }, { c[3], c[4] }, { art[1], art[2] }, { art[3], art[4] }, imgui.GetColorU32(white))
        end
    end
end

local function DrawMirror(list, window)
    local r = window.rect
    list:PushClipRect({ r[1] - 24, r[2] - 24 }, { r[3] + 24, r[4] + 24 }, true)
    local ok, err = pcall(DrawContents, list, window)
    list:PopClipRect()
    if not ok then error(err, 0) end
end

-- What is measured of a window, outlined over the game's own: its frame, its text, its art, its cursor
local function DrawOutline(list, window)
    local function Box(r, color) if r then list:AddRect({ r[1], r[2] }, { r[3], r[4] }, imgui.GetColorU32(color), 0, 0, 1) end end
    Box(window.rect, { 1, 0.85, 0.2, 1 })
    for _, run in ipairs(window.runs) do Box(run.rect, { 0.3, 1, 0.4, 0.9 }) end
    for _, quad in ipairs(window.quads) do Box(quad.rect, { 0.3, 0.8, 1, 0.9 }) end
    Box(window.cursor, { 1, 0.3, 0.3, 1 })
    Box(window.selection, { 1, 0.3, 1, 1 })
    Box(window.scroll, { 1, 1, 1, 0.8 })
end

local hostFlags = bit.bor(ImGuiWindowFlags_NoDecoration, ImGuiWindowFlags_NoInputs, ImGuiWindowFlags_NoBackground,
    ImGuiWindowFlags_NoSavedSettings, ImGuiWindowFlags_NoFocusOnAppearing, ImGuiWindowFlags_NoBringToFrontOnFocus,
    ImGuiWindowFlags_NoNav, ImGuiWindowFlags_NoMove)

local function Frame()
    local options = app.options
    local replace = options.mode == 'Replace'
    local now = os.clock()
    local wanted = {}
    for _, menu in ipairs(Menus) do
        if options['mirror_' .. menu.name][1] then
            wanted[#wanted + 1] = { name = menu.name, hide = replace and not (nativeUntil[menu.name] and now < nativeUntil[menu.name]) }
        end
    end
    if #wanted == 0 then mirror.Stop(); return end
    if not mirror.Request(wanted) then return end

    local display = imgui.GetIO().DisplaySize
    local width, height = display.x or display[1], display.y or display[2]
    local windows = mirror.Windows(width, height)
    if not windows or #windows == 0 then return end

    imgui.SetNextWindowPos({ 0, 0 })
    imgui.SetNextWindowSize({ width, height })
    local pushed = fonts.Push()
    if imgui.Begin('##menus.host', true, hostFlags) then
        local list = imgui.GetWindowDrawList()
        for _, window in ipairs(windows) do
            local missing = window.hidden and Unplaced(window) or 0
            if window.hidden and not window.rect then
                -- nothing measured of it: the game's to draw again for a while, never unseen
                GiveBack(window.name, 'its place could not be measured', now)
            elseif window.hidden and missing > 0 then
                GiveBack(window.name, ('%d of its %d pieces of text could not be placed'):format(missing, #window.runs), now)
            elseif not window.rect then
                -- watched, and nothing to outline
            elseif window.hidden then
                local r = window.rect
                frame.Draw({ left = r[1], top = r[2], width = Width(r), height = Height(r) }, function() DrawMirror(list, window) end)
            elseif not replace then
                DrawOutline(list, window)
            end
        end
    end
    imgui.End()
    fonts.Pop(pushed)
end

-- After an error the game's menus are its own for a while, the error said once
local failedUntil = 0
ashita.events.register('d3d_present', 'menus_present', function()
    if not app:BeginFrame() or os.clock() < failedUntil then
        mirror.Stop()
        return
    end
    local ok, err = pcall(Frame)
    if not ok then
        mirror.Stop()
        failedUntil = os.clock() + 10
        print(('\30\68[menus]\30\01 %s; the game draws its own menus for ten seconds.'):format(tostring(err)))
    end
end)

ashita.events.register('unload', 'menus_unload', function()
    mirror.Stop()
end)
