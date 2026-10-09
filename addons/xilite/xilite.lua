addon.name    = 'xilite'
addon.author  = 'lin, jbutt'
addon.version = '0.1'
addon.desc    = 'The player, party, target and pet windows of xitools, and nothing else'

require('common')
local bit = require('bit')
local imgui = require('imgui')
local settings = require('settings')
local ui = require('ui')
local packets = require('utils/packets')
local winxiFade = require('winxi.fade')
local winxiGame = require('winxi.game')
local winxiLegacy = require('winxi.legacy')
local winxiOrganize = require('winxi.organize')
local winxiTheme = require('winxi.theme')
local winxiWidgets = require('winxi.widgets')
local winxiWindow = require('winxi.window')

---@class xitool
---@field Name            string
---@field DefaultSettings table
---@field UpdateSettings  function?
---@field Load            function?
---@field HandlePacket    function?
---@field DrawConfig      function
---@field DrawMain        function
---@field DrawSample      function? draws the tool's windows filled with sample data; only called while it is enabled

local me = require('me')
local us = require('us')
local tgt = require('tgt')
local pet = require('pet')

local tools = T{ me, us, tgt, pet }

local defaultOptions = T{
    -- whether xitools' settings have been brought over for this character
    importedFromXitools = false,
    showConfig = T{ false },
    globals = T{
        -- when the windows get out of the way: winxi.game's rules, filled in by ApplyGlobals
        hide = T{ },
        isClickThru = T{ false },
        -- The look of every window (colours, padding, drop shadow) is winxi's theme. useSharedTheme says
        -- whether that is the one shared with other addons; theme holds this addon's own for when it is not.
        useSharedTheme = true,
        theme = T{ },
        hpBarColor = T{ 0.83, 0.33, 0.28, 1.0 },
        mpBarColor = T{ 0.82, 0.60, 0.27, 1.0 },
        tpBarColor = T{ 1.00, 1.00, 1.00, 1.0 },       -- while TP is building
        tpBarReadyColor = T{ 0.23, 0.67, 0.91, 1.0 },  -- once a weaponskill can be used
        tpBarFlash = T{ false },                       -- experimental: pulse between the two when ready
        -- Fading while idle. The settings themselves are winxi's (see winxi.fade) and are filled in by
        -- ApplyGlobals; tools is this addon's: tool name -> whether its windows fade.
        fade = T{
            tools = T{ },
        },
        -- which window is held against which while organizing: winxi.organize's
        links = T{ },
    },
    tools = T{
        me = me.DefaultSettings,
        us = us.DefaultSettings,
        tgt = tgt.DefaultSettings,
        pet = pet.DefaultSettings,
    },
}

local options = settings.load(defaultOptions)

local function Say(text)
    print(('\30\81[%s]\30\01 %s'):format(addon.name, text))
end

-- Bringing a character's settings over from xitools, once: the four tools as they were set there (where
-- each window is, what it shows), and of xitools' own settings those this addon has too. Windows are
-- named for the addon they belong to, so every name is changed on the way.
local function Renamed(value)
    if type(value) == 'string' then
        return (value:gsub('^xitools%.', 'xilite.'))
    end
    return value
end

local function Copy(from)
    local copy = T{ }
    for key, value in pairs(from) do
        copy[key] = type(value) == 'table' and Copy(value) or Renamed(value)
    end
    return copy
end

-- Takes from over into, keeping what into has that from lacks, and never changing the kind of a value
local function Merge(into, from)
    for key, value in pairs(from) do
        local present = into[key]
        if type(value) == 'table' then
            if type(present) == 'table' then
                Merge(present, value)
            elseif present == nil then
                into[key] = Copy(value)
            end
        elseif present == nil or type(present) == type(value) then
            into[key] = Renamed(value)
        end
    end
end

local hideRules = {
    UnderMap = 'hideUnderMap', UnderChat = 'hideUnderChat', WhileLoading = 'hideWhileLoading',
    DuringEvent = 'hideDuringEvent', WithInterface = 'hideWithInterface',
}
local sharedGlobals = { 'isClickThru', 'theme', 'hpBarColor', 'mpBarColor', 'tpBarColor', 'tpBarReadyColor', 'tpBarFlash' }

local function ImportFromXitools()
    local old = winxiLegacy.ReadSettings('xitools')
    if old == nil or type(old.tools) ~= 'table' then
        return false
    end

    local found = false
    local kept = { } -- the windows this addon has, by the names xitools gave them
    for _, tool in ipairs(tools) do
        local saved = old.tools[tool.Name]
        if type(saved) == 'table' then
            Merge(options.tools[tool.Name], saved)
            found = true
        end
        kept[('xitools.%s'):format(tool.Name)] = true
    end

    local oldGlobals = old.globals
    if type(oldGlobals) ~= 'table' then
        return found
    end

    local globals = options.globals
    if oldGlobals.useSharedTheme ~= nil then
        globals.useSharedTheme = oldGlobals.useSharedTheme and true or false
    end
    for _, key in ipairs(sharedGlobals) do
        if type(oldGlobals[key]) == 'table' then
            globals[key] = Copy(oldGlobals[key])
        end
    end
    for rule, key in pairs(hideRules) do
        if type(oldGlobals[key]) == 'table' then
            globals.hide[rule] = oldGlobals[key][1] and true or false
        end
    end

    -- the fade settings, and of the tools chosen to fade those there are here
    if type(oldGlobals.fade) == 'table' then
        for key, value in pairs(oldGlobals.fade) do
            if type(value) ~= 'table' then
                globals.fade[key] = value
            end
        end
        if type(oldGlobals.fade.tools) == 'table' then
            for _, tool in ipairs(tools) do
                local chosen = oldGlobals.fade.tools[tool.Name]
                if type(chosen) == 'table' then
                    globals.fade.tools[tool.Name] = T{ chosen[1] and true or false }
                end
            end
        end
    end

    -- a link is kept when both of its windows are
    if type(oldGlobals.links) == 'table' then
        local function IsKept(name)
            return type(name) == 'string' and kept[name:match('^xitools%.%a+')] == true
        end

        globals.links = T{ }
        for _, link in ipairs(oldGlobals.links) do
            if type(link) == 'table' and IsKept(link.child) and IsKept(link.parent) then
                globals.links:append(Copy(link))
            end
        end
    end

    return found
end

-- Settings saved before an option existed have no value for it: give those their defaults, then hand the
-- bar colours to ui.Colors, which is where every tool reads its HP and MP bar colour from.
-- Run when the settings are loaded or replaced, not every frame: everything it hands over is a table
-- that the config window then changes in place.
local function ApplyGlobals()
    local globals = options.globals

    -- not before the character is known: the settings then are nobody's
    if not options.importedFromXitools and settings.logged_in then
        options.importedFromXitools = true
        if ImportFromXitools() then
            Say('Settings brought over from xitools.')
        end
        settings.save()
    end

    if type(globals.hide) ~= 'table' then
        globals.hide = T{ }
    end
    winxiGame.CompleteHide(globals.hide)

    if type(globals.theme) ~= 'table' then
        globals.theme = T{ }
    end
    if type(globals.links) ~= 'table' then
        globals.links = T{ }
    end

    if type(globals.fade) ~= 'table' then
        globals.fade = T{ }
    end
    local fade = globals.fade
    winxiFade.Complete(fade)

    if type(fade.tools) ~= 'table' then
        fade.tools = T{ }
    end
    for _, tool in ipairs(tools) do
        if fade.tools[tool.Name] == nil then
            fade.tools[tool.Name] = T{ true }
        end
    end

    ui.Colors.HpBar = globals.hpBarColor
    ui.Colors.MpBar = globals.mpBarColor
    ui.Colors.TpBar = globals.tpBarColor
    ui.Colors.TpBarActive = globals.tpBarReadyColor
    ui.TpBarFlash = globals.tpBarFlash
    winxiOrganize.SetLinks(globals.links)
end

ApplyGlobals()

local function Save()
    settings.save()
end

-- Each setting's name is to the left of its control and followed by a colon, with every word
-- capitalised, and one family of settings is set a little apart from the next (see winxi.widgets)
local function DrawGlobalSettings()
    ui.BeginLabels('xilite.global')
    winxiWidgets.Hide(options.globals.hide, Save)

    ui.Gap()
    ui.Label('Clickthrough')
    imgui.Checkbox('##xilite.isClickThru', options.globals.isClickThru)
    if imgui.IsItemHovered() then
        imgui.SetTooltip('The windows let the mouse through to the game. Ignored while organizing, so they can be dragged.')
    end
end

-- What winxi's theme controls call: to keep the choice of theme, and to save this addon's own theme
local appearanceHooks = {
    onUseShared = function(useShared)
        options.globals.useSharedTheme = useShared
        settings.save()
    end,
    onOwnChanged = Save,
}

-- The Theme and Window sections are winxi's; the Addon section is what is this addon's own
local function DrawAppearance()
    winxiWidgets.Appearance(appearanceHooks)

    -- This addon's own: the bar colours, then fading while idle and which windows it applies to
    winxiWidgets.Header('Addon')
    winxiWidgets.PushControlWidth()
    winxiWidgets.Label('HP Bar Color')
    imgui.ColorEdit4('##xilite.hpBarColor', options.globals.hpBarColor)
    winxiWidgets.Label('MP Bar Color')
    imgui.ColorEdit4('##xilite.mpBarColor', options.globals.mpBarColor)
    winxiWidgets.Label('TP Bar Color')
    imgui.ColorEdit4('##xilite.tpBarColor', options.globals.tpBarColor)
    if imgui.IsItemHovered() then
        imgui.SetTooltip('The TP bar while TP is building.')
    end
    winxiWidgets.Label('TP Bar Ready Color')
    imgui.ColorEdit4('##xilite.tpBarReadyColor', options.globals.tpBarReadyColor)
    if imgui.IsItemHovered() then
        imgui.SetTooltip('The TP bar once a weaponskill can be used (1000 TP).')
    end
    winxiWidgets.Label('Flash TP Bar When Ready', true)
    imgui.Checkbox('##xilite.tpBarFlash', options.globals.tpBarFlash)
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Your own TP bar pulses once a weaponskill can be used, fading from the TP Bar Color to the TP Bar Ready Color and back.\nOther players\' and pets\' bars simply take the ready colour.')
    end

    winxiWidgets.Gap()
    local fade = options.globals.fade
    winxiWidgets.Fade(fade, Save)

    -- A chosen window fades out while idle, and fades in and out as it appears and goes (the target
    -- window as a target is taken and dropped)
    if fade.Enabled then
        winxiWidgets.Label('Windows That Fade')
        for i, tool in ipairs(tools) do
            if i > 1 then
                imgui.SameLine()
            end
            imgui.Checkbox(('%s##fade'):format(tool.Name), fade.tools[tool.Name])
            if imgui.IsItemHovered() then
                imgui.SetTooltip('Fades out while you are idle, and fades in and out as it appears and goes.')
            end
        end
    end
    winxiWidgets.PopControlWidth()
end

-- The config window is never narrower than this, so it does not jump about as the tabs are switched
local configMinSize, configMaxSize = { 780, 0 }, { 10000, 10000 }

-- The config window keeps a padding of its own, whatever the theme's: the padding slider must not
-- squeeze the window it is in
local configStyle = { padding = 11 }
local configFlags = bit.bor(ImGuiWindowFlags_AlwaysAutoResize, ImGuiWindowFlags_NoSavedSettings)

local function DrawConfigContent()
    imgui.PushStyleVar(ImGuiStyleVar_FramePadding, ui.Styles.FramePaddingSome)

    if imgui.BeginTabBar('##xilite.config', ImGuiTabBarFlags_NoCloseWithMiddleMouseButton) then
        if imgui.BeginTabItem('Global Settings') then
            DrawGlobalSettings()
            imgui.EndTabItem()
        end

        if imgui.BeginTabItem('Appearance') then
            DrawAppearance()
            imgui.EndTabItem()
        end

        -- one inner tab for each window, drawn by the tool itself
        if imgui.BeginTabItem('Windows') then
            if imgui.BeginTabBar('##xilite.config.ui', ImGuiTabBarFlags_NoCloseWithMiddleMouseButton) then
                for _, tool in ipairs(tools) do
                    tool.DrawConfig(options.tools[tool.Name], options.globals)
                end
                imgui.EndTabBar()
            end
            imgui.EndTabItem()
        end

        imgui.EndTabBar()
    end

    -- the strip along the bottom, below whichever tab is showing: winxi's Organize button against the
    -- right edge, with its grid option to the left while it is switched on
    imgui.Separator()
    winxiOrganize.Controls(ui.Styles.FramePaddingSome[1])

    imgui.PopStyleVar()
end

local function DrawConfig()
    -- only while the window is showing: the constraint goes to whichever window is drawn next
    if not options.showConfig[1] then
        return
    end

    imgui.SetNextWindowSizeConstraints(configMinSize, configMaxSize)
    imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, ui.Styles.ItemSpacing)
    winxiWindow.Full('xilite Settings', options.showConfig, configFlags, DrawConfigContent, configStyle)
    imgui.PopStyleVar()

    if not options.showConfig[1] then
        -- closed by its own button: what was set in it is kept
        settings.save()
    end
end

local function UpdateTools()
    for _, tool in ipairs(tools) do
        if tool.UpdateSettings ~= nil then
            tool.UpdateSettings(options.tools[tool.Name], options.globals)
        end
    end
end

settings.register('settings', 'settings_update', function (s)
    if s ~= nil then
        options = s
    end
    ApplyGlobals()
    settings.save()
    UpdateTools()
end)

ashita.events.register('load', 'load_handler', function()
    for _, tool in ipairs(tools) do
        if tool.Load ~= nil then
            tool.Load(options.tools[tool.Name], options.globals)
        end
    end
end)

ashita.events.register('unload', 'unload_handler', function()
    settings.save()
end)

ashita.events.register('d3d_present', 'd3d_present_handler', function()
    -- Every frame, cheaply: nothing happens unless the choice of theme or the settings table has changed
    winxiTheme.Configure(options.globals.useSharedTheme, options.globals.theme)

    DrawConfig()

    if winxiGame.IsHidden(options.globals.hide) then
        return
    end

    -- Organizing ends when the config window is closed. While it is on, each enabled window is drawn
    -- filled with sample data, so that every one is there to be arranged.
    if not options.showConfig[1] then
        winxiOrganize.SetActive(false)
    end
    local organizing = winxiOrganize.IsActive()
    winxiOrganize.BeginFrame()
    ui.UpdateFade(options.globals)

    for _, tool in ipairs(tools) do
        -- only the tools that are enabled, whether as themselves or filled with sample data
        -- and none that has faded right out: it would only be prepared and then not drawn
        local toolOptions = options.tools[tool.Name]
        if toolOptions.isEnabled[1] and not ui.IsFadedOut(tool.Name, options.globals) then
            if organizing and tool.DrawSample ~= nil then
                tool.DrawSample(toolOptions, options.globals)
            else
                tool.DrawMain(toolOptions, options.globals)
            end
        end
    end

    winxiOrganize.EndFrame()
end)

ashita.events.register('packet_in', 'packet_in_handler', function(e)
    packets.inbound.action.reset()

    for _, tool in ipairs(tools) do
        if tool.HandlePacket ~= nil and options.tools[tool.Name].isEnabled[1] then
            tool.HandlePacket(e, options.tools[tool.Name], options.globals)
        end
    end
end)

ashita.events.register('command', 'command_handler', function(e)
    local cmd = e.command:match('%S+')
    if cmd == nil then
        return
    end
    cmd = cmd:lower()
    if cmd ~= '/xilite' and cmd ~= '/xil' then
        return
    end
    e.blocked = true

    options.showConfig[1] = not options.showConfig[1]
end)
