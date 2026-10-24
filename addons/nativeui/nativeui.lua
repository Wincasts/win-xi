addon.name    = 'nativeui'
addon.author  = 'win'
addon.version = '0.7'
addon.desc    = 'The game\'s own interface in a uihook skin, and the menus it stacks over the chat log moved where you want them.'
addon.link    = 'https://github.com/Wincasts/win-xi'

-- The game's own menus, drawn by the game and worked as ever, changed by uihook as they are drawn: this keeps
-- the settings for it and gives them to uihook each time the game is started.
--
--   /nativeui    opens or closes the settings
--
-- Skin: a folder of config\uihook\skins (made by tools/uihook_skin.py), loaded with /uihook skin.
-- Menus Over The Chat Log: the windows the game stacks in the bottom left over its chat log (the command menu, a
-- shop's buy and sell, a yes or no, an item's description) drawn this far from where it puts them, together
-- (/uihook native group). Only their drawing is moved: the controller works them as ever, but the mouse clicks
-- where the game put them.
--
-- Fonts: the skin's two fonts (the menus' words, the windows' titles) drawn in a font of C:\Windows\Fonts by uihook as
-- the skin loads (/uihook skin font), following the winxi theme's Font and Title Font, the skin's own, or any chosen.
-- Menu Scale: every framed window of the game's drawn this much larger, each from its quarter's corner of the
-- screen so they keep their places to each other: the bar across the top from its ends, the menus over the chat
-- log from its top left (/uihook native size).
-- Sides: the bar across the top that many pixels shorter at each end, staying centred, and every window on either
-- half of the screen moved in with it, keeping their size and their places to each other (/uihook native inset).
-- The chat log and the menus stacked on it stay where they are.
--
-- Needs uihook 1.54 or newer.

local winxiNeeded = 41
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
local imgui = require('imgui')
local widgets = require('winxi.widgets')
local tooltip = require('winxi.tooltip')
local shell = require('winxi.shell')
local fonts = require('winxi.fonts')
local theme = require('winxi.theme')

local THEME_FONT, SKIN_FONT = 'Follow Winxi Theme', 'Skin\'s Own'
local WEIGHTS = { 'As The Font', 'Regular', 'Bold' }   -- the file's own weight, or one drawn so
-- each kind of the skin's fonts: its setting, its label, and the theme's font it follows
local FONT_KINDS = {
    { kind = 'menu', key = 'menuFont', weightKey = 'menuWeight', weightLabel = 'Menu Weight', label = 'Menu Font', themeKey = 'FontFile', tip = 'The menus\' words: their commands, lists and buttons.' },
    { kind = 'title', key = 'titleFont', weightKey = 'titleWeight', weightLabel = 'Title Weight', label = 'Title Font', themeKey = 'TitleFontFile', tip = 'The windows\' titles on their top edges, and the jobs\' and races\' names.' },
}

local NONE = 'None'
local OFFSET_LIMIT = 4000   -- pixels either way
local INSET_LIMIT = 800     -- pixels in from each side, at most
local SCALE_LOW, SCALE_HIGH = 0.75, 2

local defaults = T{
    skin = 'winxi',          -- a folder of config\uihook\skins, or None
    offset = T{ 0, 0 },      -- the menus over the chat log: pixels right and down from where the game puts them
    inset = T{ 0 },          -- the sides brought in, pixels at each
    scale = T{ 1 },          -- every framed window drawn this much larger
    menuFont = THEME_FONT,   -- the skin's menu font: the theme's Font, the skin's own, or a file of C:\Windows\Fonts
    titleFont = THEME_FONT,  -- the skin's title font: the theme's Title Font, the skin's own, or a file
    menuWeight = 'Bold',     -- one of WEIGHTS: at a menu's size a regular font's strokes are a pixel, and faint
    titleWeight = 'As The Font',
}

local app
-- What uihook was last given: sent again only as it changes, and all of it once the game draws (uihook may load
-- after this, and a skin needs the game's device)
local sent = { skin = nil, offset = nil, inset = nil, scale = nil, menu = nil, title = nil }

local function Uihook()
    local ok, loaded = pcall(function() return AshitaCore:GetPluginManager():IsLoaded('uihook') end)
    return ok and loaded
end

local function Send(command) AshitaCore:GetChatManager():QueueCommand(1, command) end

local function SkinsFolder() return AshitaCore:GetInstallPath() .. '\\config\\uihook\\skins\\' end

-- The skins there: its folders
local function Skins()
    local found = {}
    local ok, entries = pcall(ashita.fs.get_directory, SkinsFolder())
    for _, entry in ipairs(ok and type(entries) == 'table' and entries or {}) do
        entry = tostring(entry)
        if not entry:find('%.%w+$') then found[#found + 1] = entry end
    end
    table.sort(found)
    return found
end

-- The font file a kind is drawn in: the theme's (its font, '' where the theme has imgui's own), none for the skin's own,
-- or the one chosen
local function FontFile(options, f)
    local chosen = options[f.key]
    if chosen == SKIN_FONT then return '' end
    if chosen == THEME_FONT then
        local ok, t = pcall(theme.Get)
        local file = ok and type(t) == 'table' and t[f.themeKey] or ''
        return type(file) == 'string' and file or ''
    end
    return chosen
end

-- whether uihook was loaded at the last look: loaded again since, it has none of what was given it
local uihookWas = false
local function Apply(force)
    local options = app and app.options
    local loaded = Uihook()
    if loaded and not uihookWas then sent.skin, sent.offset, sent.inset, sent.scale, sent.menu, sent.title = nil, nil, nil, nil, nil, nil end
    uihookWas = loaded
    if not options or not loaded then return end
    local skin = options.skin
    if force or sent.skin ~= skin then
        Send(skin == NONE and '/uihook skin off' or ('/uihook skin %s'):format(skin))
        sent.skin = skin
    end
    local x, y = options.offset[1], options.offset[2]
    local offset = ('%d,%d'):format(x, y)
    if force or sent.offset ~= offset then
        Send((x == 0 and y == 0) and '/uihook native group off quiet' or ('/uihook native group %d %d quiet'):format(x, y))
        sent.offset = offset
    end
    -- the fonts before the skin's loading is asked again: uihook draws them as it loads, and on each change
    for _, f in ipairs(FONT_KINDS) do
        local file = FontFile(options, f)
        -- drawn in winxi's look: its weight, and the theme's Text Outline about its letters
        local weight = options[f.weightKey] == 'Bold' and ' bold' or options[f.weightKey] == 'Regular' and ' regular' or ''
        local ok, t = pcall(theme.Get)
        local width = ok and type(t) == 'table' and tonumber(t.TextOutline) or 1
        local c = ok and type(t) == 'table' and type(t.TextOutlineColor) == 'table' and t.TextOutlineColor or { 0, 0, 0, 0.9 }
        local byte = function(v) return math.max(0, math.min(255, math.floor((tonumber(v) or 0) * 255 + 0.5))) end
        local look = (' outline=%d outlinecolour=%02X%02X%02X%02X'):format(math.floor(width + 0.5), byte(c[4]), byte(c[1]), byte(c[2]), byte(c[3]))
        local command = file == '' and ('/uihook skin font %s off quiet'):format(f.kind) or ('/uihook skin font %s %s%s%s quiet'):format(f.kind, file, weight, look)
        if force or sent[f.kind] ~= command then
            Send(command)
            sent[f.kind] = command
        end
    end
    local scale = ('%.2f'):format(options.scale[1])
    if force or sent.scale ~= scale then
        Send(('/uihook native size %s quiet'):format(scale))
        sent.scale = scale
    end
    local inset = options.inset[1]
    if force or sent.inset ~= inset then
        Send(('/uihook native inset %d quiet'):format(inset))
        sent.inset = inset
    end
end

---------------------------------------------------------------------------------------------------
-- Settings
---------------------------------------------------------------------------------------------------

local skinList, skinListAt = nil, -10
local function DrawSettings(options)
    if widgets.Header('Skin', true) then
        -- the folders looked for again now and then, as skins are copied in while the game runs
        if os.clock() - skinListAt > 5 then skinList, skinListAt = Skins(), os.clock() end
        widgets.Label('Skin')
        widgets.PushControlWidth()
        if imgui.BeginCombo('##nativeui.skin', options.skin) then
            for _, name in ipairs({ NONE, unpack(skinList) }) do
                if imgui.Selectable(name .. '##nativeui.skin.' .. name, options.skin == name) then
                    options.skin = name
                    app:Save()
                    Apply()
                end
            end
            imgui.EndCombo()
        end
        widgets.PopControlWidth()
        tooltip.Hover('The pictures the game\'s menus are drawn with in place of its own: a folder of config\\uihook\\skins, as tools/uihook_skin.py makes them. None: the game\'s own.')
        widgets.Label('Reload Skin')
        if imgui.Button('Reload##nativeui.reload') and options.skin ~= NONE and Uihook() then Send('/uihook skin reload') end
        tooltip.Hover('The skin\'s pictures read again, after they have been changed.')
    end
    if widgets.Header('Fonts') then
        widgets.PushControlWidth()
        for _, f in ipairs(FONT_KINDS) do
            widgets.Label(f.label)
            if imgui.BeginCombo('##nativeui.' .. f.key, options[f.key]) then
                local choices = { THEME_FONT, SKIN_FONT }
                for _, file in ipairs(fonts.Files()) do choices[#choices + 1] = file end
                for _, choice in ipairs(choices) do
                    if imgui.Selectable(choice .. '##nativeui.' .. f.key .. '.' .. choice, options[f.key] == choice) then
                        options[f.key] = choice
                        app:Save()
                        Apply()
                    end
                end
                imgui.EndCombo()
            end
            tooltip.Hover(f.tip .. ' Follow Winxi Theme: the theme\'s ' .. (f.kind == 'menu' and 'Font' or 'Title Font') .. ', changing with it. Skin\'s Own: as the skin was made. Any other: that font of C:\\Windows\\Fonts, drawn by uihook as the skin loads.')
            widgets.Label(f.weightLabel)
            if imgui.BeginCombo('##nativeui.' .. f.weightKey, options[f.weightKey]) then
                for _, w in ipairs(WEIGHTS) do
                    if imgui.Selectable(w .. '##nativeui.' .. f.weightKey .. '.' .. w, options[f.weightKey] == w) then
                        options[f.weightKey] = w
                        app:Save()
                        Apply()
                    end
                end
                imgui.EndCombo()
            end
            tooltip.Hover('How heavy its letters are drawn. At a menu\'s size a regular font\'s strokes are a pixel wide and faint: Bold reads more like the game\'s own. As The Font: the file\'s own weight. A font chosen is drawn smoothed, with the winxi theme\'s Text Outline about its letters.')
        end
        widgets.PopControlWidth()
    end
    if widgets.Header('Screen') then
        widgets.PushControlWidth()
        widgets.Label('Menu Scale')
        if imgui.SliderFloat('##nativeui.scale', options.scale, SCALE_LOW, SCALE_HIGH, '%.2fx') then Apply() end
        if imgui.IsItemDeactivatedAfterEdit() then app:Save() end
        tooltip.Hover('Every window of the game\'s with a frame drawn this much larger, each from its corner of the screen so they keep their places to each other: the bar across the top from its ends, the menus over the chat log from its top left. The chat log stays as chatbox places it. Only the drawing grows: the mouse clicks where the game put them.')
        widgets.Label('Bring Sides In')
        if imgui.SliderInt('##nativeui.inset', options.inset, 0, INSET_LIMIT, '%d px') then Apply() end
        if imgui.IsItemDeactivatedAfterEdit() then app:Save() end
        widgets.PopControlWidth()
        tooltip.Hover('The bar across the top this many pixels shorter at each end, staying centred, and every window on either half of the screen moved in as far, keeping its size and its place next to the others. The chat log and the menus stacked on it stay where they are. 0: where the game puts them.')
    end
    if widgets.Header('Menus Over The Chat Log') then
        local changed = false
        widgets.PushControlWidth()
        widgets.Label('Move Right')
        if imgui.DragInt('##nativeui.x', options.offset, 1, -OFFSET_LIMIT, OFFSET_LIMIT, '%d px') then changed = true end
        if imgui.IsItemDeactivatedAfterEdit() then app:Save() end
        tooltip.Hover('Pixels right of where the game puts them (less than 0: left). Drag, or double-click to type.')
        local y = { options.offset[2] }
        widgets.Label('Move Down')
        if imgui.DragInt('##nativeui.y', y, 1, -OFFSET_LIMIT, OFFSET_LIMIT, '%d px') then options.offset[2] = y[1]; changed = true end
        if imgui.IsItemDeactivatedAfterEdit() then app:Save() end
        tooltip.Hover('Pixels below where the game puts them (less than 0: up). They are kept on the screen.')
        widgets.PopControlWidth()
        if changed then Apply() end
        widgets.Label('Position')
        if imgui.Button('Reset##nativeui.reset') then
            options.offset[1], options.offset[2] = 0, 0
            app:Save()
            Apply()
        end
        tooltip.Hover('Back where the game puts them.')
        imgui.TextWrapped('The command menu, a shop\'s buy and sell, a yes or no and an item\'s description, and every other window the game stacks there, move together. Only their drawing moves: the controller works them as ever, but the mouse clicks where the game put them.')
    end
end

local function Complete(options)
    options.useSharedTheme = true
    if type(options.skin) ~= 'string' or options.skin == '' then options.skin = defaults.skin end
    if type(options.offset) ~= 'table' then options.offset = T{ 0, 0 } end
    for i = 1, 2 do
        local v = tonumber(options.offset[i]) or 0
        options.offset[i] = math.max(-OFFSET_LIMIT, math.min(OFFSET_LIMIT, math.floor(v + 0.5)))
    end
    if type(options.scale) ~= 'table' or type(options.scale[1]) ~= 'number' then options.scale = T{ 1 } end
    options.scale[1] = math.max(SCALE_LOW, math.min(SCALE_HIGH, options.scale[1]))
    if type(options.inset) ~= 'table' then options.inset = T{ 0 } end
    options.inset[1] = math.max(0, math.min(INSET_LIMIT, math.floor((tonumber(options.inset[1]) or 0) + 0.5)))
    -- another character's settings: all of it given again
    for _, f in ipairs(FONT_KINDS) do
        if type(options[f.key]) ~= 'string' or options[f.key] == '' then options[f.key] = THEME_FONT end
        local known = false
        for _, w in ipairs(WEIGHTS) do known = known or options[f.weightKey] == w end
        if not known then options[f.weightKey] = defaults[f.weightKey] end
    end
    sent.skin, sent.offset, sent.inset, sent.scale, sent.menu, sent.title = nil, nil, nil, nil, nil, nil
end

app = shell.New({
    defaults = defaults,
    configTitle = 'Native UI Settings',
    command = '/nativeui',
    help = '/nativeui opens or closes the settings.',
    drawSettings = DrawSettings,
    hideAppearance = true,
    onSettings = Complete,
})

-- Looked at twice a second, not each frame (the commands were made again each frame to be compared, and the theme
-- and plugins asked for): a setting changed is given at once, by its own control; the theme's fonts and outline,
-- and uihook loaded again, within half a second
local LOOK_EVERY = 0.5
local nextLook = 0
ashita.events.register('d3d_present', 'nativeui_present', function()
    local now = os.clock()
    if now >= nextLook then
        nextLook = now + LOOK_EVERY
        Apply()
    end
    app:BeginFrame()
end)

-- unloaded: the game's own menus, where it puts them
ashita.events.register('unload', 'nativeui_unload', function()
    if Uihook() and sent.offset and sent.offset ~= '0,0' then Send('/uihook native group off quiet') end
    if Uihook() and sent.inset and sent.inset ~= 0 then Send('/uihook native inset 0 quiet') end
    if Uihook() and sent.scale and sent.scale ~= '1.00' then Send('/uihook native size 1 quiet') end
end)
