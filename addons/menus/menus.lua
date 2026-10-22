addon.name    = 'menus'
addon.author  = 'win'
addon.version = '0.5'
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
local winxiNeeded = 36
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
local ffi = require('ffi')
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

-- The menus that can be mirrored, as the settings list them, in groups: the game's name for each window, and ours.
-- Each prints its words through the game's text routines, which uihook hears. The item lists share one drawer in
-- the game, as the ability, emote and mount lists share another. The status and config windows also draw labels
-- as pictures, which come through as the game's art where they are drawn with the contents; they start off, to
-- be looked at in Outline first.
local CHECK_FIRST = ' Some of its labels are pictures the game draws; look at it in Outline before replacing it.'
local Groups = {
    { title = 'Items', on = true, menus = {
        { name = 'inventor', label = 'Inventory', tip = 'The list of what you carry.' },
        { name = 'iteminfo', label = 'Item Info', tip = 'The box under an item list that describes the item the cursor is on.' },
        { name = 'bank', label = 'Mog Safe', tip = 'The list of what is in your Mog Safe and the other places items are kept.' },
        { name = 'shop', label = 'Shop', tip = 'A shop\'s list of what it sells.' },
    } },
    { title = 'Lists', on = true, menus = {
        { name = 'ability', label = 'Abilities And Spells', tip = 'The lists of your job abilities, spells and traits.' },
        { name = 'emote', label = 'Emotes', tip = 'The list of emotes.' },
        { name = 'mount', label = 'Mounts', tip = 'The list of mounts.' },
        { name = 'evitem', label = 'Currencies', tip = 'The lists of conquest points, seals, crests and the other currencies.' },
        { name = 'miss00', label = 'Missions', tip = 'A nation\'s missions, current and completed.' },
        { name = 'quest01', label = 'Quests', tip = 'The quests of an area, current and completed.' },
        { name = 'quest00', label = 'Quest Pages', tip = 'The pages before the quest lists: Unity and the like.' },
        { name = 'friend', label = 'Friend List', tip = 'Your friends and where they are.' },
        { name = 'arealist', label = 'Area List', tip = 'The list of areas and groups to choose from, as for the Unity and search.' },
        { name = 'scresult', label = 'Search Results', tip = 'Who a search found.' },
        { name = 'faqsub', label = 'Help Desk', tip = 'The help desk\'s questions and answers.' },
    } },
    { title = 'Status', on = false, menus = {
        { name = 'persona', label = 'Status', tip = 'Your status: level, HP, MP and attributes.' .. CHECK_FIRST },
        { name = 'level', label = 'Level And EXP', tip = 'Your level and experience points.' .. CHECK_FIRST },
        { name = 'profile', label = 'Profile', tip = 'Your profile: race, nation and rank.' .. CHECK_FIRST },
        { name = 'joblevel', label = 'Job Levels', tip = 'Every job\'s level.' .. CHECK_FIRST },
        { name = 'btlskill', label = 'Combat Skills', tip = 'Your combat and magic skills.' .. CHECK_FIRST },
        { name = 'trdskill', label = 'Crafting Skills', tip = 'Your crafting skills.' .. CHECK_FIRST },
        { name = 'money', label = 'Gil', tip = 'Your gil.' .. CHECK_FIRST },
    } },
    -- Their words are pictures the game draws as the window's elements (uihook's Element quads): drawn here as
    -- the game's own art, in a winxi panel, with the cursor's row lit. Experimental.
    { title = 'Picture Label Menus', on = false, labels = true, menus = {
        { name = 'menuwind', label = 'Main Menu', tip = 'The main menu: Status, Equipment, Items and the rest.' },
        { name = 'playermo', label = 'Command Menu', tip = 'The command menu: Attack, Magic, Abilities and the rest.' },
        { name = 'magselec', label = 'Magic Categories', tip = 'The kinds of magic to choose from.' },
        { name = 'abiselec', label = 'Ability Categories', tip = 'The kinds of ability to choose from.' },
        { name = 'statcom2', label = 'Status Menu', tip = 'The menu beside your status.' },
        { name = 'configwi', label = 'Config Menu', tip = 'The config menu.' },
        { name = 'mogcont', label = 'Mog House Menu', tip = 'The Mog House menu.' },
        { name = 'myroom', label = 'Mog House Options', tip = 'The Mog House\'s own options.' },
        { name = 'itmsortw', label = 'Item Sort', tip = 'The item list\'s sorting and its other choices.' },
        { name = 'mcrmenu', label = 'Macro Menu', tip = 'The macro menu.' },
        { name = 'missionm', label = 'Mission Menu', tip = 'The nations and campaigns to see the missions of.' },
        { name = 'flistmai', label = 'Friend List Menu', tip = 'The friend list\'s choices.' },
        { name = 'commenu', label = 'Communication Menu', tip = 'The communication menu.' },
        { name = 'ut_menu', label = 'Unity Menu', tip = 'The Unity menu.' },
        { name = 'bazaar', label = 'Bazaar Menu', tip = 'The bazaar\'s choices.' },
    } },
    { title = 'Config', on = false, menus = {
        { name = 'cfilter', label = 'Chat Filters', tip = 'Which chat is shown.' .. CHECK_FIRST },
        { name = 'fxfilter', label = 'Battle Message Filters', tip = 'Which battle messages are shown.' .. CHECK_FIRST },
        { name = 'textcol1', label = 'Chat Colors', tip = 'The colours of the kinds of chat.' .. CHECK_FIRST },
    } },
}
local Menus = {} -- every menu of every group, in order
for _, group in ipairs(Groups) do
    for _, menu in ipairs(group.menus) do
        menu.on, menu.labels = group.on, group.labels
        Menus[#Menus + 1] = menu
    end
end
local byName = {}
for _, menu in ipairs(Menus) do byName[menu.name] = menu end
local Modes = { 'Replace', 'Outline' }

local SCALE_LOW, SCALE_HIGH = 0.75, 2
local defaults = T{
    mode = 'Replace',
    scale = T{ 1 },
    blockMouse = T{ false },
    lockMenus = T{ false },
    offsets = T{},
}
for _, menu in ipairs(Menus) do
    defaults['mirror_' .. menu.name] = T{ menu.on }
end

local app
local mirror = nativemirror.new()

-- A window left undrawn whose place, or whose text's, could not be measured is given back to the game for a
-- while, so a menu is never left unseen or half drawn: its name -> the time until which it is the game's, and
-- why, for the settings
local nativeUntil, nativeWhy = {}, {}
local FALLBACK_SECONDS = 2

---------------------------------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------------------------------

local function Save() app:Save() end

-- The settings window's place as last drawn, and when: presses there are its own, though the mouse is kept from
-- the game's menus under it (imgui's own word for it goes stale while moves are kept from the game)
local settingsRect, settingsAt = nil, -1

local modeIds = {}
for _, mode in ipairs(Modes) do modeIds[mode] = mode .. '##menus.mode' end

local function DrawSettings(options)
    local x, y = imgui.GetWindowPos()
    local w, h = imgui.GetWindowSize()
    if type(x) == 'table' then x, y = x.x or x[1], x.y or x[2] end
    if type(w) == 'table' then w, h = w.x or w[1], w.y or w[2] end
    if x and y and w and h then settingsRect, settingsAt = { x, y, x + w, y + h }, os.clock() end
    for index, group in ipairs(Groups) do
        if widgets.Header(group.title, index == 1) then
            for _, menu in ipairs(group.menus) do
                widgets.Label(menu.label, menu.labels)
                if imgui.Checkbox('##menus.' .. menu.name, options['mirror_' .. menu.name]) then Save() end
                tooltip.Hover(menu.tip .. ' Off, the game draws its own.')
            end
        end
    end
    if widgets.Header('Mouse') then
        widgets.Label('Keep Mouse From Game Menus')
        if imgui.Checkbox('##menus.blockMouse', options.blockMouse) then Save() end
        tooltip.Hover('Over a menu drawn here, or where the game\'s own is under it, the game is given no mouse: no moving its cursor, no clicks, no wheel. The controller works as ever. With it on, a menu can be dragged where it is wanted.')
        widgets.Label('Lock Menu Positions')
        if imgui.Checkbox('##menus.lockMenus', options.lockMenus) then Save() end
        tooltip.Hover('Menus cannot be dragged. Off, a menu is moved by dragging it with the left button, while the mouse is kept from the game\'s menus.')
        widgets.Label('Positions')
        if imgui.Button('Reset Positions##menus.reset') then
            options.offsets = T{}
            Save()
        end
        tooltip.Hover('Every menu back where the game puts it.')
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
        widgets.PushControlWidth()
        widgets.Label('Menu Scale')
        imgui.SliderFloat('##menus.scale', options.scale, SCALE_LOW, SCALE_HIGH, '%.2fx')
        if imgui.IsItemDeactivatedAfterEdit() then Save() end
        widgets.PopControlWidth()
        tooltip.Hover('How large the menus are drawn, each grown from the corner of the screen it is nearest, so it stays on the screen. The controller works as ever; the mouse still clicks where the game\'s own would be, so at any scale but 1 it does not line up yet.')
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
    if type(options.scale) ~= 'table' or type(options.scale[1]) ~= 'number' then options.scale = T{ 1 } end
    options.scale[1] = math.max(SCALE_LOW, math.min(SCALE_HIGH, options.scale[1]))
    for _, key in ipairs({ 'blockMouse', 'lockMenus' }) do
        if type(options[key]) ~= 'table' or type(options[key][1]) ~= 'boolean' then options[key] = T{ false } end
    end
    -- each menu's place, as an offset from where the game puts it, in pixels
    if type(options.offsets) ~= 'table' then options.offsets = T{} end
    for name, offset in pairs(options.offsets) do
        if type(offset) ~= 'table' or type(offset[1]) ~= 'number' or type(offset[2]) ~= 'number' then options.offsets[name] = nil end
    end
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
    -- the row the cursor is on, lit across the window, under everything else: found from the cursor, or the game's
    -- own highlight where that is the shape of a row (in some windows its draws cover the whole window)
    local row = CursorRow(window)
    local lit = window.selection
    if not row and lit and Height(lit) < Height(r) / 2 then row = lit end
    if row then
        local highlight = theme.Get().HighlightColor
        list:AddRectFilled({ r[1] + pad, row[2] - 1 }, { r[3] - pad, row[4] + 1 }, imgui.GetColorU32(highlight), 3)
    end
    -- the game's art in the contents (icons), as the game drew it; and in a menu whose words are pictures, its
    -- elements, the labels, in their own colours (the cursor's tint left to the row lit under it; a greyed one kept
    -- faint)
    local labels = byName[window.name] and byName[window.name].labels
    -- the labels spelled from the game's menu font read back as words, drawn in the theme's; their letters not drawn
    local words, spelled = {}, {}
    if labels then words, spelled = nativemirror.Words(window.quads) end
    for i, quad in ipairs(window.quads) do
        local element = quad.phase == nativemirror.Element
        if spelled[i] then
            -- read as a letter of a word below
        elseif element and labels and quad.texture then
            local q, uv, faint = quad.rect, quad.uv, quad.color[4]
            list:AddImage(quad.texture, { q[1], q[2] }, { q[3], q[4] }, { uv[1], uv[2] }, { uv[3], uv[4] }, imgui.GetColorU32({ 1, 1, 1, faint }))
        elseif not element and quad.texture then
            local q, uv = quad.rect, quad.uv
            list:AddImage(quad.texture, { q[1], q[2] }, { q[3], q[4] }, { uv[1], uv[2] }, { uv[3], uv[4] }, imgui.GetColorU32(quad.color))
        end
    end
    for _, word in ipairs(words) do
        local t = word.rect
        local size = math.max(8, math.floor(word.tall + 0.5))
        imgui.PushFont(nil, size)
        text.Draw(list, t[1], t[2], TextColor({ 1, 1, 1, word.color[4] }), word.text)
        imgui.PopFont()
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
    -- the hand where the game drew its own: at the art's own shape, as tall as the row it points at (the game's
    -- cursor draws cover more than the hand), from the left of where the game drew it, on its middle
    local c = window.cursor
    if c then
        local handle, art = cursorArt.Get()
        if handle then
            local tall = row and Height(row) + 2 or math.min(Height(c), 18)
            local wide = tall * art[5] / art[6]
            local middle = (c[2] + c[4]) / 2
            list:AddImage(handle, { c[1], middle - tall / 2 }, { c[1] + wide, middle + tall / 2 },
                { art[1], art[2] }, { art[3], art[4] }, imgui.GetColorU32(white))
        end
    end
end

-- The window grown or shrunk by scale about the corner of the display it is nearest, then moved by dx, dy
-- (kept on the display): every place in it moved with it, so what the game measured keeps its shape. A copy;
-- the bridge's table is left as it is.
local function Placed(window, scale, dx, dy, width, height)
    if scale == 1 and dx == 0 and dy == 0 then return window, 0, 0 end
    local r = window.rect
    local ax = (r[1] + r[3]) / 2 < width / 2 and r[1] or r[3]
    local ay = (r[2] + r[4]) / 2 < height / 2 and r[2] or r[4]
    local left, top = ax + (r[1] - ax) * scale, ay + (r[2] - ay) * scale
    local right, bottom = ax + (r[3] - ax) * scale, ay + (r[4] - ay) * scale
    dx = math.max(-left, math.min(width - right, dx))
    dy = math.max(-top, math.min(height - bottom, dy))
    local function Move(rect)
        if not rect then return nil end
        return { ax + (rect[1] - ax) * scale + dx, ay + (rect[2] - ay) * scale + dy, ax + (rect[3] - ax) * scale + dx, ay + (rect[4] - ay) * scale + dy }
    end
    local out = {}
    for key, value in pairs(window) do out[key] = value end
    out.rect, out.cursor, out.selection, out.scroll = Move(r), Move(window.cursor), Move(window.selection), Move(window.scroll)
    out.runs, out.quads = {}, {}
    for i, run in ipairs(window.runs) do
        out.runs[i] = { text = run.text, raw = run.raw, route = run.route, color = run.color, rect = Move(run.rect), x = run.x, y = run.y, phase = run.phase }
    end
    for i, quad in ipairs(window.quads) do
        out.quads[i] = { rect = Move(quad.rect), uv = quad.uv, texture = quad.texture, color = quad.color, phase = quad.phase }
    end
    return out, dx, dy
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
    for _, quad in ipairs(window.quads) do
        Box(quad.rect, quad.phase == nativemirror.Element and { 0.75, 0.45, 1, 0.9 } or { 0.3, 0.8, 1, 0.9 })
    end
    Box(window.cursor, { 1, 0.3, 0.3, 1 })
    Box(window.selection, { 1, 0.3, 1, 1 })
    Box(window.scroll, { 1, 1, 1, 0.8 })
end

---------------------------------------------------------------------------------------------------
-- The mouse
---------------------------------------------------------------------------------------------------

-- Where the mouse is kept from the game this frame: each mirrored menu's place as drawn and the game's own
-- place under it, by name. Empty while Keep Mouse From Game Menus is off.
local areas = {}
local drag = nil -- { name, x, y, dx, dy }: the menu being dragged, where the drag began and its offset then
local MOUSE_BUTTON = { [0x0201] = 1, [0x0202] = 1, [0x0203] = 1, [0x0204] = 2, [0x0205] = 2, [0x0206] = 2,
    [0x0207] = 3, [0x0208] = 3, [0x0209] = 3, [0x020b] = 4, [0x020c] = 4, [0x020d] = 4 }
local MOUSE_UP = { [0x0202] = true, [0x0205] = true, [0x0208] = true, [0x020c] = true }
local MOVE, WHEEL, HWHEEL = 0x0200, 0x020a, 0x020e
local kept = { false, false, false, false } -- by button: its press kept from the game, so its release is too

local function Inside(x, y, r) return r and x >= r[1] and x < r[3] and y >= r[2] and y < r[4] end

-- Where the mouse is, in imgui's display pixels: Windows' own cursor, in the game window's client area, scaled
-- to the display. imgui's MousePos is not used while a drag is on: it is fed by the very messages kept from the
-- game, so it stops where the first kept move was. imgui's is the fallback where Windows' cannot be had.
pcall(ffi.cdef, [[
    typedef struct { long x, y; } menus_point_t;
    typedef struct { long left, top, right, bottom; } menus_rect_t;
    int __stdcall GetCursorPos(menus_point_t*);
    int __stdcall ScreenToClient(void*, menus_point_t*);
    int __stdcall GetClientRect(void*, menus_rect_t*);
]])
local point, client = nil, nil
local function Pointer(io)
    local ok, x, y = pcall(function()
        local window = AshitaCore:GetProperties():GetFinalFantasyHwnd()
        if not window or window == 0 then return nil end
        local handle = ffi.cast('void*', window)
        point = point or ffi.new('menus_point_t')
        client = client or ffi.new('menus_rect_t')
        if ffi.C.GetCursorPos(point) == 0 or ffi.C.ScreenToClient(handle, point) == 0 or ffi.C.GetClientRect(handle, client) == 0 then return nil end
        local width, height = client.right - client.left, client.bottom - client.top
        local display = io.DisplaySize
        local dw, dh = display.x or display[1], display.y or display[2]
        if width <= 0 or height <= 0 or not dw or not dh then return nil end
        return tonumber(point.x) * dw / width, tonumber(point.y) * dh / height
    end)
    if ok and x and y then return x, y end
    local mouse = io.MousePos
    return mouse and (mouse.x or mouse[1]), mouse and (mouse.y or mouse[2])
end
-- The area under the mouse, and whether it is over the menu as drawn (which can be dragged)
local function Over(x, y)
    for _, area in ipairs(areas) do
        if Inside(x, y, area.drawn) then return area, true end
    end
    for _, area in ipairs(areas) do
        if Inside(x, y, area.native) then return area, false end
    end
    return nil
end

ashita.events.register('mouse', 'menus_mouse', function(e)
    local message = e.message
    local button = MOUSE_BUTTON[message]
    -- a release of a press kept from the game is kept too, whatever has changed since; and ends a drag
    if MOUSE_UP[message] then
        if kept[button] then
            kept[button] = false
            e.blocked = true
            if button == 1 and drag then
                drag = nil
                app:Save()
            end
        end
        return
    end
    if e.blocked or #areas == 0 then return end
    local io = imgui.GetIO()
    local x, y = Pointer(io)
    if not x or not y then return end
    if message == MOVE then
        if drag then
            local offsets = app.options.offsets
            offsets[drag.name] = T{ drag.dx + x - drag.x, drag.dy + y - drag.y }
            e.blocked = true
        elseif Over(x, y) then
            e.blocked = true
        end
        return
    end
    -- the settings window under the mouse has it, while it is open
    if settingsRect and os.clock() - settingsAt < 0.5 and Inside(x, y, settingsRect) then return end
    if button then
        local area, drawn = Over(x, y)
        if not area then return end
        e.blocked = true
        kept[button] = true
        if button == 1 and drawn and not app.options.lockMenus[1] then
            local offset = app.options.offsets[area.name]
            drag = { name = area.name, x = x, y = y, dx = offset and offset[1] or 0, dy = offset and offset[2] or 0 }
        end
    elseif (message == WHEEL or message == HWHEEL) and Over(x, y) then
        e.blocked = true
    end
end)

---------------------------------------------------------------------------------------------------
-- Each frame
---------------------------------------------------------------------------------------------------

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
    local blockMouse = replace and options.blockMouse[1]
    areas = {}
    if not blockMouse then drag = nil end
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
                -- moved only while the mouse is kept from the game's menus: else the game's, unseen where it is,
                -- would still take the clicks
                local offset = blockMouse and options.offsets[window.name]
                local placed, dx, dy = Placed(window, options.scale[1], offset and offset[1] or 0, offset and offset[2] or 0, width, height)
                -- the offset kept to what keeps it on the screen, so a drag back from past the edge moves it at once
                if offset and (dx ~= offset[1] or dy ~= offset[2]) then options.offsets[window.name] = T{ dx, dy } end
                local r = placed.rect
                frame.Draw({ left = r[1], top = r[2], width = Width(r), height = Height(r) }, function() DrawMirror(list, placed) end)
                if blockMouse then areas[#areas + 1] = { name = window.name, drawn = r, native = window.rect } end
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
        areas, drag = {}, nil
        return
    end
    local ok, err = pcall(Frame)
    if not ok then
        mirror.Stop()
        areas, drag = {}, nil
        failedUntil = os.clock() + 10
        print(('\30\68[menus]\30\01 %s; the game draws its own menus for ten seconds.'):format(tostring(err)))
    end
end)

ashita.events.register('unload', 'menus_unload', function()
    mirror.Stop()
    areas, drag = {}, nil
end)
