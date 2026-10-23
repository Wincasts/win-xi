addon.name    = 'nativeui'
addon.author  = 'win'
addon.version = '0.2'
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
-- Sides: the bar across the top that many pixels shorter at each end, staying centred, and every window on either
-- half of the screen moved in with it, keeping their size and their places to each other (/uihook native inset).
-- The chat log and the menus stacked on it stay where they are.
--
-- Needs uihook 1.40 or newer.

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

local NONE = 'None'
local OFFSET_LIMIT = 4000   -- pixels either way
local INSET_LIMIT = 800     -- pixels in from each side, at most

local defaults = T{
    skin = 'winxi',          -- a folder of config\uihook\skins, or None
    offset = T{ 0, 0 },      -- the menus over the chat log: pixels right and down from where the game puts them
    inset = T{ 0 },          -- the sides brought in, pixels at each
}

local app
-- What uihook was last given: sent again only as it changes, and all of it once the game draws (uihook may load
-- after this, and a skin needs the game's device)
local sent = { skin = nil, offset = nil, inset = nil }

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

local function Apply(force)
    local options = app and app.options
    if not options or not Uihook() then return end
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
    if widgets.Header('Sides') then
        widgets.PushControlWidth()
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
    if type(options.inset) ~= 'table' then options.inset = T{ 0 } end
    options.inset[1] = math.max(0, math.min(INSET_LIMIT, math.floor((tonumber(options.inset[1]) or 0) + 0.5)))
    -- another character's settings: all of it given again
    sent.skin, sent.offset, sent.inset = nil, nil, nil
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

ashita.events.register('d3d_present', 'nativeui_present', function()
    Apply()
    app:BeginFrame()
end)

-- unloaded: the game's own menus, where it puts them
ashita.events.register('unload', 'nativeui_unload', function()
    if Uihook() and sent.offset and sent.offset ~= '0,0' then Send('/uihook native group off quiet') end
    if Uihook() and sent.inset and sent.inset ~= 0 then Send('/uihook native inset 0 quiet') end
end)
