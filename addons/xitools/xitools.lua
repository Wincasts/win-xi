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
        textColor = T{ 1.00, 1.00, 1.00, 1.0 },
        backgroundColor = T{ 0.08, 0.08, 0.08, 0.8 },
        borderColor = T{ 0.69, 0.68, 0.78, 1.0 },
        padding = T{ 10 },
        hpBarColor = T{ 0.83, 0.33, 0.28, 1.0 },
        mpBarColor = T{ 0.82, 0.60, 0.27, 1.0 },
        baseW = 7,
        baseH = 14,
        shadow = T{
            enabled = T{ false },
            offset = T{ 4 },    -- pixels down and to the right
            blur = T{ 6 },      -- pixels of soft edge
            opacity = T{ 50 },  -- percent
        },
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

-- The "Organize" button at the bottom of the config window. Not saved: it is for arranging
-- the windows, and switches itself off when the config window is closed.
local showSamples = T{ false }
local showGrid = T{ true }

-- Settings saved before an option existed have no value for it: give those their defaults, then hand the
-- bar colours to ui.Colors, which is where every tool reads its HP and MP bar colour from.
-- Run when the settings are loaded or replaced, not every frame: everything it hands over is a table
-- that the config window then changes in place.
local function ApplyGlobals()
    local globals = options.globals

    if globals.padding == nil then
        globals.padding = T{ ui.GetPadding(globals) }
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

    if globals.shadow == nil then
        globals.shadow = T{ }
    end
    for _, key in ipairs({ 'enabled', 'offset', 'blur', 'opacity' }) do
        if globals.shadow[key] == nil then
            globals.shadow[key] = T{ defaultOptions.globals.shadow[key][1] }
        end
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
    for _, tool in ipairs(uiWindows) do
        if fade.tools[tool.Name] == nil then
            fade.tools[tool.Name] = T{ true }
        end
    end

    ui.Colors.HpBar = globals.hpBarColor
    ui.Colors.MpBar = globals.mpBarColor
    ui.SetLinks(globals.links)
end

ApplyGlobals()

-- The config window is never narrower than this, so it does not jump about as the tabs are switched
local configMinWidth = 780

-- Extra space between the config window's border and its content, on top of the usual window padding
local configExtraPadding = 3
local defaultWindowPadding = 8

local function DrawGlobalSettings()
    imgui.Checkbox('Hide while map open', options.globals.hideUnderMap)
    imgui.Checkbox('Hide while chat open', options.globals.hideUnderChat)
    imgui.Checkbox('Hide while loading', options.globals.hideWhileLoading)
    imgui.Checkbox('Hide during events', options.globals.hideDuringEvent)
    imgui.Checkbox('Hide with game interface', options.globals.hideWithInterface)
end

local function DrawUiSettings()
    imgui.Checkbox('Clickthrough', options.globals.isClickThru)
    imgui.ColorEdit4("Text Color", options.globals.textColor)
    imgui.ColorEdit4("Background Color", options.globals.backgroundColor)
    imgui.ColorEdit4("Border Color", options.globals.borderColor)
    imgui.ColorEdit4("HP Bar Color", options.globals.hpBarColor)
    imgui.ColorEdit4("MP Bar Color", options.globals.mpBarColor)
    imgui.SliderInt('Padding', options.globals.padding, 0, ui.MaxPadding)
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Space between a window\'s border and its content, the same on every side.')
    end

    imgui.Separator()

    local shadow = options.globals.shadow
    imgui.Checkbox('Drop shadow', shadow.enabled)
    if imgui.IsItemHovered() then
        imgui.SetTooltip('Draws a soft shadow behind each component, down and to the right of it.')
    end
    if shadow.enabled[1] then
        imgui.SliderInt('Shadow offset', shadow.offset, 0, 20)
        imgui.SliderInt('Shadow softness', shadow.blur, 0, 20)
        imgui.SliderInt('Shadow opacity (%)', shadow.opacity, 0, 100)
    end

    imgui.Separator()

    -- winxi's own controls for the fade; which components it applies to is this addon's
    local fade = options.globals.fade
    winxiWidgets.Fade(fade)

    if fade.Enabled then
        imgui.Text('Components that fade:')
        for i, tool in ipairs(uiWindows) do
            if i > 1 then
                imgui.SameLine()
            end
            imgui.Checkbox(('%s##fade'):format(tool.Name), fade.tools[tool.Name])
        end
    end
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

-- The strip along the bottom of the config window, below whichever tab is showing: the Organize
-- button against the right edge, with its grid option to the left while it is switched on.
local function DrawFooter()
    imgui.Separator()

    if showSamples[1] then
        imgui.Checkbox('Alignment grid', showGrid)
        if imgui.IsItemHovered() then
            imgui.SetTooltip('Draws a grid over the screen while the sample windows are showing, with bold lines through the centre.')
        end
        imgui.SameLine()
    end

    -- right-aligned by hand: the button is as wide as its label and the frame padding either side of it
    local label = 'Organize'
    local width = imgui.CalcTextSize(label) + 2 * ui.Styles.FramePaddingSome[1]
    local available = imgui.GetContentRegionAvail()
    imgui.SetCursorPosX(imgui.GetCursorPosX() + math.max(0, available - width))

    -- lit while it is switched on
    local isOn = showSamples[1]
    if isOn then
        imgui.PushStyleColor(ImGuiCol_Button, ui.Colors.TpBarActive)
    end
    if imgui.Button(label) then
        showSamples[1] = not showSamples[1]
    end
    if isOn then
        imgui.PopStyleColor()
    end

    if imgui.IsItemHovered() then
        imgui.SetTooltip('Shows every enabled component filled with sample data, so they can be dragged into place and compared.\nEach window is labelled, and party windows show a full six members.\nDrop one window onto another to link them: it snaps against the side it was dropped towards and stays there. Unlink with the button beside it.\nPress again to finish. Switches off when this window is closed.')
    end
end

-- The window padding in use, from the style where the build exposes it
local function GetWindowPadding()
    local style = imgui.GetStyle ~= nil and imgui.GetStyle() or nil
    local padding = style ~= nil and style.WindowPadding or nil
    if padding ~= nil and padding.x ~= nil and padding.y ~= nil then
        return padding.x, padding.y
    end
    return defaultWindowPadding, defaultWindowPadding
end

local function DrawConfig()
    -- only while the window is showing: the constraint goes to whichever window is drawn next
    if not options.tools.config.isVisible[1] then
        return
    end

    -- Styled like the tools' windows, but it keeps its title bar and close button, and its own padding
    -- rather than the one being chosen inside it
    local paddingX, paddingY = GetWindowPadding()
    local padding = { paddingX + configExtraPadding, paddingY + configExtraPadding }
    imgui.SetNextWindowSizeConstraints({ configMinWidth, 0 }, { 10000, 10000 })

    ui.DrawStyledWindow(options.tools.config, options.globals, function()
        imgui.PushStyleVar(ImGuiStyleVar_FramePadding, ui.Styles.FramePaddingSome)

        if imgui.BeginTabBar('##xitools.config', ImGuiTabBarFlags_NoCloseWithMiddleMouseButton) then
            if imgui.BeginTabItem('Global Settings') then
                DrawGlobalSettings()
                imgui.EndTabItem()
            end

            if imgui.BeginTabItem('UI Settings') then
                DrawUiSettings()
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
    end, padding)
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

    DrawConfig()

    if (options.globals.hideUnderChat[1] and ffxi.IsChatExpanded())
    or (options.globals.hideUnderMap[1] and ffxi.IsMapOpen())
    or (options.globals.hideWhileLoading[1] and GetPlayerEntity() == nil)
    or (options.globals.hideDuringEvent[1] and ffxi.IsEventHappening())
    or (options.globals.hideWithInterface[1] and ffxi.IsInterfaceHidden()) then
        return
    end

    if not options.tools.config.isVisible[1] then
        showSamples[1] = false
    end
    ui.IsSampleMode = showSamples[1]
    ui.BeginFrame()
    ui.UpdateFade(options.globals)

    if showSamples[1] and showGrid[1] then
        ui.DrawGrid()
    end

    for i, tool in ipairs(tools) do
        -- only the tools that are enabled, whether as themselves or filled with sample data
        -- and none that has faded right out: it would only be prepared and then not drawn
        if options.tools[tool.Name].isEnabled[1] and not ui.IsFadedOut(tool.Name, options.globals) then
            if showSamples[1] and tool.DrawSample ~= nil then
                tool.DrawSample(options.tools[tool.Name], options.globals)
            else
                tool.DrawMain(options.tools[tool.Name], options.globals)
            end
        end
    end

    if showSamples[1] then
        ui.DrawLinkButtons()
    end
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
