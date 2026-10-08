addon.name    = 'xitools'
addon.author  = 'lin'
addon.version = '0.26'
addon.desc    = 'A humble UI toolkit'

require('common')
local ffxi = require('utils/ffxi')
local packets = require('utils/packets')
local imgui = require('imgui')
local settings = require('settings')
local ui = require('ui')
local migrations = require('migrations')
local winxiFade = require('winxi.fade')
local winxiOrganize = require('winxi.organize')
local winxiTheme = require('winxi.theme')
local winxiWidgets = require('winxi.widgets')

---@class xitool
---@field Name            string
---@field Aliases         string[]?
---@field DefaultSettings table
---@field UpdateSettings  function?
---@field Load            function?
---@field HandlePacket    function?
---@field HandlePacketOut function?
---@field HandleCommand   function?
---@field DrawConfig      function
---@field DrawMain        function
---@field DrawSample      function? draws the tool's windows filled with sample data; only called while it is enabled

local me = require('me')
local us = require('us')
local tgt = require('tgt')
local pet = require('pet')
local treas = require('treas')
local inv = require('inv')
local tracker = require('tracker')
local cast = require('cast')
local crafty = require('crafty')
local fishe = require('fishe')
local week = require('week')

local uiWindows = {
    me,
    us,
    tgt,
    pet,
    tracker,
    cast,
}

local normalWindows = {
    inv,
    treas,
    crafty,
    fishe,
    week,
}

local tools = T{}:extend(uiWindows):extend(normalWindows)

-- The tools that are UI components: these alone fade with the player's idling
local isComponent = { }
for _, tool in ipairs(uiWindows) do
    isComponent[tool.Name] = true
end

local defaultOptions = T{
    version = nil,
    globals = T{
        showDemo = T{ false },
        hideUnderMap = T{ true },
        hideUnderChat = T{ true },
        hideWhileLoading = T{ true },
        hideDuringEvent = T{ true },
        hideWithInterface = T{ true },
        isClickThru = T{ false },
        -- The look of every window (colours, padding, drop shadow) is winxi's theme. useSharedTheme says
        -- whether that is the one shared with other addons; theme holds this addon's own for when it is not.
        useSharedTheme = true,
        theme = T{ },
        hpBarColor = T{ 0.83, 0.33, 0.28, 1.0 },
        mpBarColor = T{ 0.82, 0.60, 0.27, 1.0 },
        baseW = 7,
        baseH = 14,
        -- Fading while idle. The settings themselves are winxi's (see winxi.fade) and are filled in by
        -- ApplyGlobals; tools is this addon's: tool name -> whether its windows fade.
        fade = T{
            tools = T{ },
        },
    },
    tools = T{
        config = T{
            isEnabled = T{ true },
            isVisible = T{ false },
            name = 'xitools.config',
            size = T{ -1, -1 },
            pos = T{ 100, 100 },
            flags = ImGuiWindowFlags_AlwaysAutoResize,
        },
        me = me.DefaultSettings,
        us = us.DefaultSettings,
        tgt = tgt.DefaultSettings,
        pet = pet.DefaultSettings,
        treas = treas.DefaultSettings,
        inv = inv.DefaultSettings,
        tracker = tracker.DefaultSettings,
        cast = cast.DefaultSettings,
        crafty = crafty.DefaultSettings,
        fishe = fishe.DefaultSettings,
        week = week.DefaultSettings,
    },
}

local options = settings.load(defaultOptions)

-- Settings saved before an option existed have no value for it: give those their defaults, then hand the
-- bar colours to ui.Colors, which is where every tool reads its HP and MP bar colour from.
-- Run when the settings are loaded or replaced, not every frame: everything it hands over is a table
-- that the config window then changes in place.
local function ApplyGlobals()
    local globals = options.globals

    -- The window colours, padding and drop shadow were this addon's own settings before the theme moved
    -- to winxi. What was saved then is kept as this addon's own theme, for use with "Use Shared Theme"
    -- off, and the old settings are dropped.
    if globals.useSharedTheme == nil then
        globals.useSharedTheme = true
    end
    if type(globals.theme) ~= 'table' then
        globals.theme = T{ }
    end
    local own = globals.theme
    for old, new in pairs({ backgroundColor = 'BackgroundColor', borderColor = 'BorderColor', textColor = 'TextColor' }) do
        local color = globals[old]
        if type(color) == 'table' then
            if own[new] == nil and color[1] and color[2] and color[3] and color[4] then
                own[new] = T{ color[1], color[2], color[3], color[4] }
            end
            globals[old] = nil
        end
    end
    if type(globals.padding) == 'table' then
        if own.Padding == nil then
            own.Padding = tonumber(globals.padding[1])
        end
        globals.padding = nil
    end
    if type(globals.shadow) == 'table' then
        for old, new in pairs({ enabled = 'ShadowEnabled', offset = 'ShadowOffset', blur = 'ShadowBlur', opacity = 'ShadowOpacity' }) do
            if type(globals.shadow[old]) == 'table' and own[new] == nil then
                own[new] = globals.shadow[old][1]
            end
        end
        globals.shadow = nil
    end

    if globals.hpBarColor == nil then
        globals.hpBarColor = T{ unpack(defaultOptions.globals.hpBarColor) }
    end
    if globals.mpBarColor == nil then
        globals.mpBarColor = T{ unpack(defaultOptions.globals.mpBarColor) }
    end

    if globals.links == nil then
        globals.links = T{ }
    end

    if globals.fade == nil then
        globals.fade = T{ }
    end
    local fade = globals.fade

    -- Settings saved before the fade moved to winxi hold each value in a table of its own, under a
    -- lower-case name: carry those over to winxi's names, then let winxi fill in whatever is missing
    for old, new in pairs({ enabled = 'Enabled', delay = 'Delay', duration = 'Duration', opacity = 'Opacity',
                            combat = 'Combat', target = 'Target', missingHp = 'MissingHp', resting = 'Resting' }) do
        if type(fade[old]) == 'table' then
            if fade[new] == nil then
                fade[new] = fade[old][1]
            end
            fade[old] = nil
        end
    end
    winxiFade.Complete(fade)

    if fade.tools == nil then
        fade.tools = T{ }
    end
    -- every tool can fade in and out as it appears and goes; only the components also fade with idling
    for _, tool in ipairs(tools) do
        if fade.tools[tool.Name] == nil then
            fade.tools[tool.Name] = T{ true }
        end
    end

    ui.Colors.HpBar = globals.hpBarColor
    ui.Colors.MpBar = globals.mpBarColor
    winxiOrganize.SetLinks(globals.links)
end

ApplyGlobals()

-- The config window is never narrower than this, so it does not jump about as the tabs are switched
local configMinWidth = 780

-- The config window keeps a padding of its own, whatever the theme's: the padding slider must not
-- squeeze the window it is in
local configPadding = { 11, 11 }

-- Each setting's name is to the left of its control and followed by a colon, with every word
-- capitalised, and one family of settings is set a little apart from the next (see winxi.widgets)
local function DrawGlobalSettings()
    ui.BeginLabels('xitools.global')

    ui.Label('Hide While Map Open')
    imgui.Checkbox('##xitools.hideUnderMap', options.globals.hideUnderMap)
    ui.Label('Hide While Chat Open')
    imgui.Checkbox('##xitools.hideUnderChat', options.globals.hideUnderChat)
    ui.Label('Hide While Loading')
    imgui.Checkbox('##xitools.hideWhileLoading', options.globals.hideWhileLoading)
    ui.Label('Hide During Events')
    imgui.Checkbox('##xitools.hideDuringEvent', options.globals.hideDuringEvent)
    ui.Label('Hide With Game Interface')
    imgui.Checkbox('##xitools.hideWithInterface', options.globals.hideWithInterface)

    ui.Gap()
    ui.Label('Clickthrough')
    imgui.Checkbox('##xitools.isClickThru', options.globals.isClickThru)
    if imgui.IsItemHovered() then
        imgui.SetTooltip('The components let the mouse through to the game. Ignored while organizing, so they can be dragged.')
    end
end

-- What winxi's theme controls call: to keep the choice of theme, and to save this addon's own theme
local appearanceHooks = {
    onUseShared = function(useShared)
        options.globals.useSharedTheme = useShared
        settings.save()
    end,
    onOwnChanged = function()
        settings.save()
    end,
}

-- The Theme and Window sections are winxi's; the Addon section is what is this addon's own
local function DrawAppearance()
    winxiWidgets.Appearance(appearanceHooks)

    -- This addon's own: the bar colours, then fading while idle and which components it applies to
    winxiWidgets.Header('Addon')
    winxiWidgets.PushControlWidth()
    winxiWidgets.Label('HP Bar Color')
    imgui.ColorEdit4('##xitools.hpBarColor', options.globals.hpBarColor)
    winxiWidgets.Label('MP Bar Color')
    imgui.ColorEdit4('##xitools.mpBarColor', options.globals.mpBarColor)

    winxiWidgets.Gap()
    local fade = options.globals.fade
    winxiWidgets.Fade(fade)

    -- A chosen component fades out while idle, and fades in and out as it appears and goes (the target
    -- window as a target is taken and dropped). A chosen tool only does the second: it is never faded
    -- by idling, but fades in and out as it is shown and hidden.
    if fade.Enabled then
        local function Choices(label, toolList, tooltip)
            winxiWidgets.Label(label)
            for i, tool in ipairs(toolList) do
                if i > 1 then
                    imgui.SameLine()
                end
                imgui.Checkbox(('%s##fade'):format(tool.Name), fade.tools[tool.Name])
                if imgui.IsItemHovered() then
                    imgui.SetTooltip(tooltip)
                end
            end
        end

        Choices('Components That Fade', uiWindows,
            'Fades out while you are idle, and fades in and out as it appears and goes.')
        Choices('Tools That Fade', normalWindows,
            'Fades in and out as it is shown and hidden. Tools are never faded by idling.')
    end
    winxiWidgets.PopControlWidth()
end

-- One inner tab for each of the given tools, drawn by the tool itself
local function DrawToolTabs(id, toolList)
    if imgui.BeginTabBar(id, ImGuiTabBarFlags_NoCloseWithMiddleMouseButton) then
        for _, tool in ipairs(toolList) do
            tool.DrawConfig(options.tools[tool.Name], options.globals)
        end

        imgui.EndTabBar()
    end
end

-- The strip along the bottom of the config window, below whichever tab is showing: winxi's Organize
-- button against the right edge, with its grid option to the left while it is switched on
local function DrawFooter()
    imgui.Separator()
    winxiOrganize.Controls(ui.Styles.FramePaddingSome[1])
end

local function DrawConfig()
    -- only while the window is showing: the constraint goes to whichever window is drawn next
    if not options.tools.config.isVisible[1] then
        return
    end

    -- Styled like the tools' windows, but it keeps its title bar and close button, and its own padding
    -- rather than the one being chosen inside it
    imgui.SetNextWindowSizeConstraints({ configMinWidth, 0 }, { 10000, 10000 })

    ui.DrawStyledWindow(options.tools.config, options.globals, function()
        imgui.PushStyleVar(ImGuiStyleVar_FramePadding, ui.Styles.FramePaddingSome)

        if imgui.BeginTabBar('##xitools.config', ImGuiTabBarFlags_NoCloseWithMiddleMouseButton) then
            if imgui.BeginTabItem('Global Settings') then
                DrawGlobalSettings()
                imgui.EndTabItem()
            end

            if imgui.BeginTabItem('Appearance') then
                DrawAppearance()
                imgui.EndTabItem()
            end

            if imgui.BeginTabItem('Components') then
                DrawToolTabs('##xitools.config.ui', uiWindows)
                imgui.EndTabItem()
            end

            if imgui.BeginTabItem('Tools') then
                DrawToolTabs('##xitools.config.normal', normalWindows)
                imgui.EndTabItem()
            end

            imgui.EndTabBar()
        end

        DrawFooter()

        imgui.PopStyleVar()
    end, configPadding)
end

settings.register('settings', 'settings_update', function (s)
    if s ~= nil then
        options = s
        migrations.run(options, addon.version)
        ApplyGlobals()
    end

    settings.save()

    for _, tool in ipairs(tools) do
        if tool.UpdateSettings ~= nil then
            tool.UpdateSettings(options.tools[tool.Name], options.globals)
        end
    end
end)

ashita.events.register('load', 'load_handler', function()
    if migrations.run(options, addon.version) then
        settings.save()
    end

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
    if options.globals.showDemo[1] then
        imgui.ShowDemoWindow(options.globals.showDemo)
    end

    -- Every frame, cheaply: nothing happens unless the choice of theme or the settings table has changed
    winxiTheme.Configure(options.globals.useSharedTheme, options.globals.theme)

    DrawConfig()

    if (options.globals.hideUnderChat[1] and ffxi.IsChatExpanded())
    or (options.globals.hideUnderMap[1] and ffxi.IsMapOpen())
    or (options.globals.hideWhileLoading[1] and GetPlayerEntity() == nil)
    or (options.globals.hideDuringEvent[1] and ffxi.IsEventHappening())
    or (options.globals.hideWithInterface[1] and ffxi.IsInterfaceHidden()) then
        return
    end

    -- Organizing ends when the config window is closed. While it is on, each enabled component is
    -- drawn filled with sample data, so that every window is there to be arranged.
    if not options.tools.config.isVisible[1] then
        winxiOrganize.SetActive(false)
    end
    local organizing = winxiOrganize.IsActive()
    winxiOrganize.BeginFrame()
    ui.UpdateFade(options.globals)

    for i, tool in ipairs(tools) do
        -- only the tools that are enabled, whether as themselves or filled with sample data
        -- and none that has faded right out: it would only be prepared and then not drawn
        if options.tools[tool.Name].isEnabled[1]
        and not (isComponent[tool.Name] and ui.IsFadedOut(tool.Name, options.globals)) then
            if organizing and tool.DrawSample ~= nil then
                tool.DrawSample(options.tools[tool.Name], options.globals)
            else
                tool.DrawMain(options.tools[tool.Name], options.globals)
            end
        end
    end

    winxiOrganize.EndFrame()
end)

ashita.events.register('packet_out', 'packet_out_handler', function(e)
    for _, tool in ipairs(tools) do
        if options.tools[tool.Name].isEnabled[1] and tool.HandlePacketOut ~= nil then
            tool.HandlePacketOut(e, options.tools[tool.Name], options.globals)
        end
    end
end)

ashita.events.register('packet_in', 'packet_in_handler', function(e)
    packets.inbound.action.reset()

    for _, tool in ipairs(tools) do
        if options.tools[tool.Name].isEnabled[1] and tool.HandlePacket ~= nil then
            tool.HandlePacket(e, options.tools[tool.Name], options.globals)
        end
    end
end)

ashita.events.register('command', 'command_handler', function(e)
    local args = e.command:args()
    local cmd = args[1]
    local verb = args[2]

    if cmd == nil or (cmd ~= '/xit' and cmd ~= '/xitools') then
        return
    end

    if verb == nil or verb == 'config' then
        options.tools.config.isVisible[1] = not options.tools.config.isVisible[1]
    end

    if verb == 'demo' then
        options.globals.showDemo[1] = true
    end

    for _, tool in ipairs(tools) do
        if tool.HandleCommand ~= nil and (verb == tool.Name or (tool.Aliases and tool.Aliases:contains(verb))) then
            local remainder = args:slice(3, #args - 2)
            tool.HandleCommand(remainder, options.tools[tool.Name], options.globals)
        end
    end
end)
