-- winxi.shell: what every winxi addon with one main window would otherwise write out for itself.
--
-- The addon keeps what is its own (its settings, what goes in its window, what its buttons do), and
-- the shell does the rest: loading and saving the settings for each character, the theme, the rules
-- for hiding, fading in and out, the window's place, a settings window with a Winxi Theme tab, and
-- the addon's command.
--
--     local shell = require('winxi.shell');
--
--     local app = shell.New({
--         defaults    = T{ isVisible = T{ true }, pos = T{ 100, 100 }, ... },   -- the addon's own settings
--         window      = 'winxi.example',          -- the main window's name
--         title       = 'Example',                -- optional: the words on the main window's top edge (winxi.titles)
--         configTitle = 'Example Settings',
--         command     = '/example',
--         aliases     = { '/ex' },                -- optional: other commands that do the same
--         help        = '/example shows or hides the window; /example config opens the settings.',
--         drawSettings   = function(options) ... end,   -- the Settings tab, above the hiding rules
--         drawAppearance = function(options) ... end,   -- optional: more for the Winxi Theme tab's Addon section
--         hideAppearance = true,                 -- optional: omit the Winxi Theme tab
--         hideHeader  = 'Visibility',             -- optional: put the hiding rules under a section of this title
--         menuOnlyCommands = true,               -- optional: only the bare command opens the menu; other
--                                                --   verbs say the help, but for those in commands
--         bareOpensConfig = true,                -- optional: the bare command opens or closes the settings,
--                                                --   and 'toggle' shows or hides the window
--         settingsLabel = 'Settings',             -- optional: label of the main settings tab
--         leadingTabs = { { label = 'Names', draw = function(options) ... end } }, -- optional: tabs before the main settings tab
--         tabs        = { { label = 'More', draw = function(options) ... end } },   -- optional: tabs of the addon's own, between Settings and Winxi Theme
--         commands    = { focus = function(options, args) ... end },   -- optional: more verbs
--         onSettings  = function(options) ... end,      -- optional: the settings have been loaded, or swapped for another character's
--         toggleSays  = { shown = '...', hidden = '...' },   -- optional: said in the chat log as the command shows or hides the window
--         import      = { tool = 'example', keys = { 'isVisible', 'pos' } },   -- optional: bring these over from xitools, once
--         formerName  = 'ex',                    -- optional: the addon's name before it was renamed: its settings
--                                                --   under that name are brought over, once for each character
--     });
--
--     ashita.events.register('d3d_present', 'example_present', function()
--         if not app:BeginFrame() then return end        -- the settings window is drawn; false while the addon is hidden
--         app:Window(app.options.isVisible, Draw);       -- the main window, with Draw for its content
--     end);
--
-- app.options is the settings table: the shell adds fadeInOut, hide, useSharedTheme, theme and
-- importedFromXitools to the addon's defaults, and expects isVisible (a table holding true or false)
-- and pos among them. It is a different table after a change of character: read it from app each
-- time rather than keeping it.
--
-- The command with no verb shows or hides the window, and 'config' opens or closes the settings;
-- with bareOpensConfig, the command with no verb opens the settings and 'toggle' the window.
--
-- An addon with no window of its own, only settings, leaves window out: the command alone then opens
-- or closes the settings, which have nothing in them about hiding or fading, and isVisible and pos
-- are not looked for. It calls app:BeginFrame() each frame all the same, for the settings window.
local bit = require('bit');
local imgui = require('imgui');
local settings = require('settings');
local theme = require('winxi.theme');
local style = require('winxi.style');
local window = require('winxi.window');
local widgets = require('winxi.widgets');
local fade = require('winxi.fade');
local game = require('winxi.game');
local legacy = require('winxi.legacy');
local tips = require('winxi.tooltip');

local shell = {};

local App = {};
App.__index = App;

local itemSpacing = { 8, 4 };
local framePadding = { 4, 2 };

function App:Say(text)
    print(('\30\81[%s]\30\01 %s'):format(addon.name, text));
end

function App:Save()
    settings.save();
end

-- Makes good whatever the settings lack, and brings xitools' over where that is still to do
local function Prepare(app)
    local options = app.options;
    if type(options.hide) ~= 'table' then
        options.hide = T{ };
    end
    if type(options.theme) ~= 'table' then
        options.theme = T{ };
    end
    if type(options.fadeInOut) ~= 'table' then
        options.fadeInOut = T{ true };
    end

    -- not before the character is known: the settings then are nobody's. An addon that has been renamed
    -- takes what it saved under its old name first, which says whether xitools' have been brought over.
    local former = app.spec.formerName;
    if former ~= nil and not options.importedFromFormer and settings.logged_in then
        options.importedFromFormer = true;
        local saved = legacy.ReadSettings(former);
        if saved ~= nil then
            for key, value in pairs(saved) do
                if key ~= 'importedFromFormer' then
                    options[key] = value;
                end
            end
            app:Say(('Settings brought over from %s.'):format(former));
        end
        settings.save();
    end

    local import = app.spec.import;
    if import ~= nil and not options.importedFromXitools and settings.logged_in then
        options.importedFromXitools = true;
        if legacy.FromXitools(import.tool, options, import.keys) then
            app:Say('Settings brought over from xitools.');
        end
        settings.save();
    end

    game.CompleteHide(options.hide);
    if app.spec.onSettings ~= nil then
        app.spec.onSettings(options);
    end
end

-- The main window, drawn with the theme. wanted is the window's own switch (a table holding true or
-- false): switched off, the window goes on being drawn until it has faded out. draw draws its content.
-- extra, if given: constraints = { min, max } for imgui's size constraints,
-- flags = additional ImGui window flags (for example, NoMove).
function App:Window(wanted, draw, extra)
    local options = self.options;
    local isWanted = wanted[1] and true or false;
    local alpha = isWanted and 1 or 0;
    if options.fadeInOut[1] then
        alpha = fade.Presence(self.spec.window, isWanted);
    end
    if alpha <= 0.01 then
        return false;
    end

    imgui.SetNextWindowPos(options.pos, ImGuiCond_FirstUseEver);
    if extra ~= nil and extra.constraints ~= nil then
        imgui.SetNextWindowSizeConstraints(extra.constraints[1], extra.constraints[2]);
    end

    self.windowStyle.alpha = alpha;
    self.lingering[1] = true;
    self.draw = draw;

    imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, itemSpacing);
    local flags = bit.bor(style.TitlelessFlags(), extra ~= nil and extra.flags or 0);
    local drawn = window.Full(self.spec.window, isWanted and wanted or self.lingering, flags, self.drawWindow, self.windowStyle);
    imgui.PopStyleVar();
    return drawn;
end

local noTabs = { }; -- what an addon with no tabs of its own has

local function DrawTabs(tabs, options)
    for _, tab in ipairs(tabs or noTabs) do
        if imgui.BeginTabItem(tab.label) then
            widgets.BeginLabels(tab.label);
            widgets.Gap();
            tab.draw(options);
            widgets.Gap();
            imgui.EndTabItem();
        end
    end
end

-- The settings window: the addon's Settings tab with the hiding rules under it, whatever tabs the
-- addon has of its own, and the Winxi Theme tab with winxi's Theme, Window and Styles sections and the addon's
-- own under Addon
local function DrawConfigContent(app)
    local options = app.options;
    local spec = app.spec;

    imgui.PushStyleVar(ImGuiStyleVar_FramePadding, framePadding);
    if imgui.BeginTabBar(app.ids.tabs, ImGuiTabBarFlags_NoCloseWithMiddleMouseButton) then
        DrawTabs(spec.leadingTabs, options);
        if imgui.BeginTabItem(spec.settingsLabel or 'Settings') then
            widgets.BeginLabels(app.ids.labels);
            if spec.drawSettings ~= nil then
                -- the addon's settings are set a little apart from the tabs over them, as from what is under them
                widgets.Gap();
                spec.drawSettings(options);
                if spec.hideHeader == nil then
                    widgets.Gap();
                end
            end
            if spec.window ~= nil and (spec.hideHeader == nil or widgets.Header(spec.hideHeader)) then
                widgets.Hide(options.hide, app.save);
            end
            imgui.EndTabItem();
        end
        -- the addon's own tabs, each with its own column of names
        DrawTabs(spec.tabs, options);
        if spec.hideAppearance ~= true and widgets.BeginThemeTab() then
            widgets.Appearance(app.appearanceHooks);

            if (spec.window ~= nil or spec.drawAppearance ~= nil) and widgets.Header('Addon') then
                if spec.window ~= nil then
                    widgets.Label('Fade In And Out');
                    imgui.Checkbox(app.ids.fade, options.fadeInOut);
                    if imgui.IsItemHovered() then
                        tips.Show('The window fades in as it is shown and out as it is hidden, in place of appearing and going at once.');
                    end
                end
                if spec.drawAppearance ~= nil then
                    spec.drawAppearance(options);
                end
            end
            widgets.EndThemeTab();
        end
        imgui.EndTabBar();
    end
    imgui.PopStyleVar();
end

-- Once a frame, first: the theme, and the settings window if it is open. Returns false while the
-- addon's windows should not be drawn (the map is open, an event is running, and so on).
function App:BeginFrame()
    local options = self.options;

    -- every frame, cheaply: nothing happens unless the choice of theme or the settings table has changed
    theme.Configure(options.useSharedTheme, options.theme);

    if self.showConfig[1] then
        window.Full(self.ids.config, self.showConfig, self.configFlags, self.drawConfig, self.configStyle);
        if not self.showConfig[1] then
            -- closed by its own button: what was set in it is kept
            settings.save();
        end
    end

    -- with no window there is nothing to hide, and nothing of the game is asked
    return self.spec.window == nil or not game.IsHidden(options.hide);
end

function App:ToggleConfig()
    self.showConfig[1] = not self.showConfig[1];
end

local function OnCommand(app, e)
    local spec = app.spec;

    -- every command typed or sent comes by here: only this addon's is taken apart
    local command = tostring(e.command);
    local first = command:match('%S+');
    if first == nil or not app.commandNames[first:lower()] then
        return;
    end
    e.blocked = true;

    local args = {};
    for word in command:gmatch('%S+') do
        args[#args + 1] = word;
    end

    local options = app.options;
    local verb = args[2] and args[2]:lower() or nil;
    if verb == nil and (spec.window == nil or spec.bareOpensConfig) then
        app:ToggleConfig();
    elseif verb == nil or (verb == 'toggle' and spec.bareOpensConfig) then
        options.isVisible[1] = not options.isVisible[1];
        -- for a window that is not always there to be seen changing
        if spec.toggleSays ~= nil then
            app:Say(options.isVisible[1] and spec.toggleSays.shown or spec.toggleSays.hidden);
        end
    elseif spec.menuOnlyCommands and (spec.commands == nil or spec.commands[verb] == nil) then
        app:Say(spec.help or 'Use the settings menu.');
    elseif verb == 'config' then
        app:ToggleConfig();
    elseif spec.commands ~= nil and spec.commands[verb] ~= nil then
        spec.commands[verb](options, args);
    elseif spec.help ~= nil then
        app:Say(spec.help);
    end
end

-- The controller settings an addon's Settings tab has: the switch, with the addon's account of what
-- the buttons do as its tooltip, and under it, while it is on, the sounds and the kind of controller.
-- between, if given, draws the addon's own controller settings after the sounds. The settings are
-- controller and controllerSounds (tables holding true or false) and controllerType (a layout's key).
local controllerIds = nil; -- the hidden labels of the controls below: made once

function shell.ControllerSettings(options, tooltip, between)
    local controller = require('winxi.controller');
    local ids = controllerIds;
    if ids == nil then
        ids = {
            controller = ('##%s.controller'):format(addon.name),
            sounds = ('##%s.controllerSounds'):format(addon.name),
            layouts = {},
        };
        for index, layout in ipairs(controller.Layouts) do
            ids.layouts[index] = ('%s##%s.controllerType'):format(layout.label, addon.name);
        end
        controllerIds = ids;
    end

    if type(options.controller) ~= 'table' then
        options.controller = T{ false };
    end
    if type(options.controllerSounds) ~= 'table' then
        options.controllerSounds = T{ false };
    end

    widgets.Label('Controller Navigation', true);
    imgui.Checkbox(ids.controller, options.controller);
    if tooltip ~= nil and imgui.IsItemHovered() then
        tips.Show(tooltip);
    end
    if not options.controller[1] then
        return;
    end

    widgets.Label('Controller Sounds');
    imgui.Checkbox(ids.sounds, options.controllerSounds);
    if imgui.IsItemHovered() then
        tips.Show('Plays a sound as the window takes the controller, the highlight moves, a menu opens, a choice is made or backed out of.\nThe sounds are the wav files in libs\\winxi\\sounds: put others of the same names there to change them.');
    end

    if between ~= nil then
        between(options);
    end

    widgets.Label('Controller Type');
    local current = controller.GetLayout();
    local column = imgui.GetCursorPosX();
    for index, layout in ipairs(controller.Layouts) do
        if index > 1 then
            -- one to a line, under the first
            imgui.SetCursorPosX(column);
        end
        if imgui.RadioButton(ids.layouts[index], current == layout.key) then
            options.controllerType = layout.key;
        end
    end
    if imgui.IsItemHovered() then
        tips.Show('XInput is an Xbox controller, or one set to behave as one. DirectInput is anything else: pick the make whose buttons match.\nOn a DirectInput controller the buttons are read by position: the bottom face button is A, the right one B.');
    end
end

function shell.New(spec)
    local defaults = spec.defaults or T{ };
    -- what the shell keeps for every addon, beside the addon's own
    if defaults.fadeInOut == nil then defaults.fadeInOut = T{ true }; end -- the window fades in as it is shown and out as it is hidden
    if defaults.hide == nil then defaults.hide = T{ }; end                 -- when the window gets out of the way: winxi.game's rules
    if defaults.useSharedTheme == nil then defaults.useSharedTheme = true; end
    if defaults.theme == nil then defaults.theme = T{ }; end               -- the addon's own theme, used when it leaves the shared one
    if defaults.importedFromXitools == nil then defaults.importedFromXitools = false; end
    if spec.formerName ~= nil and defaults.importedFromFormer == nil then defaults.importedFromFormer = false; end

    local app = setmetatable({
        spec = spec,
        options = settings.load(defaults),
        showConfig = { false },
        windowStyle = { alpha = 1, title = spec.title },
        lingering = { true }, -- stands in for the window's own switch while it fades out
        draw = nil,           -- what the main window holds this frame
        -- the settings window has the theme's settings window values, apart from the game windows'
        configStyle = { kind = window.Settings },
        configFlags = ImGuiWindowFlags_NoSavedSettings, -- a settings window: winxi.window sizes it
        ids = {
            config = spec.configTitle or (addon.name .. ' Settings'),
            tabs = ('##%s.config'):format(addon.name),
            labels = ('%s.settings'):format(addon.name),
            fade = ('##%s.fadeInOut'):format(addon.name),
        },
    }, App);

    -- made once, for imgui and the widgets to call
    app.save = function()
        settings.save();
    end;
    app.appearanceHooks = {
        onUseShared = function(useShared)
            app.options.useSharedTheme = useShared;
            settings.save();
        end,
        onOwnChanged = app.save,
    };
    app.drawConfig = function()
        DrawConfigContent(app);
    end;
    app.drawWindow = function()
        app.draw(app.options);
        -- where the window is, kept in the settings
        local options = app.options;
        options.pos[1], options.pos[2] = imgui.GetWindowPos();
    end;

    Prepare(app);

    ashita.events.register('unload', addon.name .. '_shell_unload', function()
        settings.save();
    end);

    -- another character's settings have been loaded, or these have been changed from outside
    settings.register('settings', addon.name .. '_shell_settings', function(s)
        if s ~= nil then
            app.options = s;
        end
        Prepare(app);
        settings.save();
    end);

    if spec.command ~= nil then
        spec.command = spec.command:lower();
        app.commandNames = { [spec.command] = true };
        for _, alias in ipairs(spec.aliases or {}) do
            app.commandNames[alias:lower()] = true;
        end
        ashita.events.register('command', addon.name .. '_shell_command', function(e)
            OnCommand(app, e);
        end);
    end

    return app;
end

return shell;
