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
--         resizable   = true,                     -- optional: no auto-fit/NoResize flags; caller owns initial size and content layout
--         configTitle = 'Example Settings',
--         command     = '/example',
--         aliases     = { '/ex' },                -- optional: other commands that do the same
--         help        = '/example shows or hides the window; /example config opens the settings.',
--         drawSettings   = function(options) ... end,   -- the Settings tab, above the hiding rules
--         drawAppearance = function(options) ... end,   -- optional: more for the Winxi Theme tab's Addon section
--         hideAppearance = true,                 -- optional: omit the Winxi Theme tab
--         visibility  = function(options) ... end,  -- optional: more for the Visibility tab, after Fade In And Out
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
pcall(require, 'winxi.perf');   -- the addon's handlers timed for the perf addon; before any is registered

local shell = {};

local App = {};
App.__index = App;

local itemSpacing = { 8, 4 };
local framePadding = { 4, 2 };
local tabAir = { 0, 5 }; -- between a tab bar and what is under it, and after the last row

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
-- flags = additional ImGui window flags,
-- locked = true for a window held where it is, clickThrough = true for one the mouse goes through
-- (winxi.window's options of those names: an addon's Lock Window setting, widgets.Lock),
-- pos = { x, y } to force a position this frame (otherwise the saved first-use position),
-- size = { width, height } to apply this frame (after the fade/visibility check),
-- alpha = 0 to 1, how much of the window shows beside its fading in and out (the addon's own fade).
function App:Window(wanted, draw, extra)
    local options = self.options;
    local isWanted = wanted[1] and true or false;
    local alpha = isWanted and 1 or 0;
    if options.fadeInOut[1] then
        alpha = fade.Presence(self.spec.window, isWanted);
    end
    if extra ~= nil and extra.alpha ~= nil then
        alpha = alpha * extra.alpha;
    end
    if alpha <= 0.01 then
        return false;
    end

    if extra ~= nil and extra.pos ~= nil then
        imgui.SetNextWindowPos(extra.pos, ImGuiCond_Always);
    else
        imgui.SetNextWindowPos(options.pos, ImGuiCond_FirstUseEver);
    end;
    if extra ~= nil and extra.size ~= nil then
        imgui.SetNextWindowSize(extra.size, ImGuiCond_Always);
    end
    if extra ~= nil and extra.constraints ~= nil then
        imgui.SetNextWindowSizeConstraints(extra.constraints[1], extra.constraints[2]);
    end

    self.windowStyle.alpha = alpha;
    self.windowStyle.locked = extra ~= nil and extra.locked or nil;
    self.windowStyle.clickThrough = extra ~= nil and extra.clickThrough or nil;
    self.lingering[1] = true;
    self.draw = draw;

    imgui.PushStyleVar(ImGuiStyleVar_ItemSpacing, itemSpacing);
    local baseFlags = self.spec.resizable and style.ResizableFlags() or style.TitlelessFlags();
    local flags = bit.bor(baseFlags, extra ~= nil and extra.flags or 0);
    local drawn = window.Full(self.spec.window, isWanted and wanted or self.lingering, flags, self.drawWindow, self.windowStyle);
    imgui.PopStyleVar();
    return drawn;
end

local noTabs = { }; -- what an addon with no tabs of its own has

local function DrawTabs(tabs, options)
    for _, tab in ipairs(tabs or noTabs) do
        if imgui.BeginTabItem(tab.label) then
            widgets.BeginLabels(tab.label);
            imgui.Dummy(tabAir);
            tab.draw(options);
            widgets.EndSub();
            imgui.Dummy(tabAir);
            imgui.EndTabItem();
        end
    end
end

-- The settings window: the addon's Settings tab, whatever tabs the addon has of its own, a Visibility
-- tab for an addon with a window (Fade In And Out, whatever the addon adds, then the rules for hiding),
-- and the Winxi Theme tab with winxi's Theme, Window, Font and Styles sections and
-- the addon's own under Addon. Every tab is a column of described rows (winxi.widgets).
local function DrawConfigContent(app)
    local options = app.options;
    local spec = app.spec;

    imgui.PushStyleVar(ImGuiStyleVar_FramePadding, framePadding);
    if imgui.BeginTabBar(app.ids.tabs, ImGuiTabBarFlags_NoCloseWithMiddleMouseButton) then
        DrawTabs(spec.leadingTabs, options);
        if spec.drawSettings ~= nil and imgui.BeginTabItem(spec.settingsLabel or 'Settings') then
            widgets.BeginLabels(app.ids.labels);
            -- the addon's settings are set a little apart from the tabs over them, as from what is under them
            imgui.Dummy(tabAir);
            spec.drawSettings(options);
            widgets.EndSub();
            imgui.Dummy(tabAir);
            imgui.EndTabItem();
        end
        -- the addon's own tabs, each with its own column of names
        DrawTabs(spec.tabs, options);
        if spec.window ~= nil and imgui.BeginTabItem('Visibility') then
            widgets.BeginLabels(app.ids.visibility);
            imgui.Dummy(tabAir);
            if widgets.Header('Visibility', true) then
                widgets.Check('Fade In And Out', 'The window fades in and out instead of popping.', options.fadeInOut, app.ids.fade);
                if spec.visibility ~= nil then
                    spec.visibility(options);
                end
                widgets.EndSub();
                widgets.Gap();
                widgets.Hide(options.hide, app.save);
            end
            widgets.EndSub();
            imgui.Dummy(tabAir);
            imgui.EndTabItem();
        end
        if spec.hideAppearance ~= true and widgets.BeginThemeTab() then
            widgets.Appearance(app.appearanceHooks);

            if spec.drawAppearance ~= nil and widgets.Header('Addon') then
                spec.drawAppearance(options);
                widgets.EndSub();
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
    -- no one logged in: nothing is drawn, the settings window neither. Ashita's settings library gives
    -- every addon the defaults as the character logs out, in which a window is open and at its first
    -- place, and the addons run on for half a second more as the game shuts down: without this, a
    -- window kept closed showed in that time, and at the title screen.
    if self.loggedOut then
        return false;
    end
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

-- The controller settings an addon's Settings tab has: the switch, and under it, while it is on, the
-- sounds and the kind of controller. tooltip, the addon's account of what the buttons do, is kept for
-- its README: a settings window has no notes.
-- between, if given, draws the addon's own controller settings after the sounds. The settings are
-- controller and controllerSounds (tables holding true or false) and controllerType (a layout's key).
local controllerIds = nil; -- the hidden labels of the controls below: made once
local controllerSpec = { experimental = true };
local controllerDependent = { parent = true };

function shell.ControllerSettings(options, tooltip, between)
    local controller = require('winxi.controller');
    local ids = controllerIds;
    if ids == nil then
        ids = {
            controller = ('##%s.controller'):format(addon.name),
            sounds = ('##%s.controllerSounds'):format(addon.name),
            type = ('##%s.controllerType'):format(addon.name),
        };
        controllerIds = ids;
    end

    if type(options.controller) ~= 'table' then
        options.controller = T{ false };
    end
    if type(options.controllerSounds) ~= 'table' then
        options.controllerSounds = T{ false };
    end

    widgets.Check('Controller Navigation', 'Use a controller to move about this window.', options.controller, ids.controller, controllerSpec);
    if not options.controller[1] then
        return;
    end

    widgets.Check('Controller Sounds', 'Plays a sound as the highlight moves or you pick something.', options.controllerSounds, ids.sounds, controllerDependent);

    if between ~= nil then
        between(options);
    end

    local chosen = widgets.Dropdown('Controller Type', 'XInput is an Xbox controller, or one set up to act as one. DirectInput is any other.',
        controller.Layouts, controller.GetLayout(), ids.type, controllerDependent);
    if chosen ~= nil then
        options.controllerType = chosen;
    end
    -- the game reads one kind of controller: with the other chosen, no button is taken
    if controller.LayoutMismatch() then
        imgui.PushTextWrapPos(0);
        imgui.TextColored(widgets.ExperimentalColor, controller.Heard() == 'xinput'
            and 'Your controller is pressing XInput buttons: choose XInput, or no button reaches this addon.'
            or 'Your controller is pressing DirectInput buttons: choose the DirectInput make that matches it, or no button reaches this addon.');
        imgui.PopTextWrapPos();
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
        loggedOut = not settings.logged_in, -- loaded at the title screen: nothing drawn until a character's settings come
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
            visibility = ('%s.visibility'):format(addon.name),
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
        -- the defaults, as the character logs out: held closed until a character's settings come
        app.loggedOut = not settings.logged_in;
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
