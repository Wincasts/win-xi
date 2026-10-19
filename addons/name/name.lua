addon.name    = 'name';
addon.author  = 'win';
addon.version = '1.41';
addon.desc    = 'Shows and hides the names over characters\' heads by what they are over, and draws them in winxi\'s style, through the namehook plugin.';

-- The winxi this addon was made with, or a newer one: each addon is released with its own copy, so an
-- older one may have been put over it (winxi.version)
local winxiNeeded = 4; -- fonts.Texture's mark, fonts.TextureDetail
do
    local ok, found = pcall(require, 'winxi.version');
    local number = ok and type(found) == 'table' and found.Number or 0;
    if number < winxiNeeded then
        local text = ('%s needs winxi %d or newer, and addons/libs/winxi is %d: install the newest release of any winxi addon.'):format(addon.name, winxiNeeded, number);
        print(('\30\68[%s]\30\01 %s'):format(addon.name, text));
        error(text, 0);
    end
end

require('common');

local bit        = require('bit');
local imgui      = require('imgui');
local shell      = require('winxi.shell');
local widgets    = require('winxi.widgets');
local nameplates = require('winxi.nameplates');
local custom     = require('custom');
local statuses   = require('statuses');
local controls   = require('controls');
local diag       = require('diag');
local general    = require('general');

local Category = nameplates.Category;

-- The categories as they are set out in the settings: the setting each is kept in, its name there,
-- and what it covers. Group headings match Trigger's menus.
local rows = {
    { key = 'showSelf',     category = Category.Self,     label = 'Own Name',         group = 'Players',
      tooltip = 'The name over your own head.' },
    { key = 'showParty',    category = Category.Party,    label = 'Party Members',
      tooltip = 'The others of your party, trusts among them.' },
    { key = 'showAlliance', category = Category.Alliance, label = 'Alliance Members',
      tooltip = 'The other parties of your alliance.' },
    { key = 'showPlayers',  category = Category.Player,   label = 'Other Players',
      tooltip = 'Every player who is not of your party or alliance. A player on the plugin\'s whitelist is shown all the same: /namehook whitelist add <name>' },
    { key = 'showMyPet',    category = Category.MyPet,    label = 'My Pet',           group = 'Pets',
      tooltip = 'Your own pet.' },
    { key = 'showPets',     category = Category.Pet,      label = 'Other Pets',
      tooltip = 'Anyone else\'s pet, trust or adventuring fellow.' },
    { key = 'showNpcs',     category = Category.Npc,      label = 'NPCs',             group = 'NPCs & Monsters',
      tooltip = 'What cannot be fought: townspeople, doors, and the rest.' },
    { key = 'showMonsters', category = Category.Monster,  label = 'Monsters',
      tooltip = 'What can be fought, charmed players among them.' },
};

local defaults = T{
    alwaysTarget = T{ false }, -- the target's name is shown whatever it is over
    diagnostics  = T{ false }, -- /name diag: why the names stopped, kept and written to logs
};
for _, row in ipairs(rows) do
    defaults[row.key] = T{ true };
    row.id = ('##name.%s'):format(row.key);
end
custom.Defaults(defaults);
statuses.Defaults(defaults);
general.Defaults(defaults);
-- Preferred baseline captured from the live profile; settings.load still gives
-- existing character settings precedence over these defaults.
local preferredDefaults = require('name_defaults');
for key, value in pairs(preferredDefaults) do defaults[key] = value; end

-- The settings are this addon's, kept for each character; what the plugin does with names is the
-- plugin's, and can be changed there by its own command or by another addon. The two are kept the
-- same: the settings are given to the plugin when it is first found and whenever they change here,
-- and a change made there is taken into the settings.
local connected = false;

-- What the plugin was last seen to have, so that the settings are only gone through when it changes
local seenHidden, seenOptions = nil, nil;

local function Push(options)
    local hidden = 0;
    for _, row in ipairs(rows) do
        if (not options[row.key][1]) then
            hidden = bit.bor(hidden, row.category);
        end
    end
    nameplates.SetAllHidden(hidden);
    nameplates.SetAlwaysTarget(options.alwaysTarget[1]);
    seenHidden, seenOptions = nil, nil;
    diag.Note('Settings given to the plugin: hidden 0x%02X, always target %s', hidden, tostring(options.alwaysTarget[1]));
end

-- Returns whether anything was different
local function Pull(options, hook)
    if (hook.Hidden == seenHidden and hook.Options == seenOptions) then
        return false;
    end
    seenHidden, seenOptions = hook.Hidden, hook.Options;

    local changed = false;
    for _, row in ipairs(rows) do
        local shown = bit.band(seenHidden, row.category) == 0;
        if (options[row.key][1] ~= shown) then
            options[row.key][1] = shown;
            changed = true;
        end
    end

    local alwaysTarget = bit.band(seenOptions, 1) ~= 0;
    if (options.alwaysTarget[1] ~= alwaysTarget) then
        options.alwaysTarget[1] = alwaysTarget;
        changed = true;
    end
    if (changed) then
        diag.Note('Settings taken from the plugin: hidden 0x%02X, options 0x%X', seenHidden, seenOptions);
    end
    return changed;
end

local app;

local warning = { 1.0, 0.6, 0.4, 1.0 };

local function DrawSettings(options)
    local problem = nameplates.Problem();
    if (problem ~= nil) then
        imgui.TextColored(warning, problem);
        widgets.Gap();
    end

    controls.BeginLayout('filters', nil, 'Always Show Target');
    local changed, first, open = false, true, true;
    for _, row in ipairs(rows) do
        if (row.group ~= nil) then
            if (not first) then controls.EndSection(); end
            open = controls.Section(row.group, '##name.filter.' .. row.group, first);
            first = false;
        end
        if (open) then
            widgets.Label(row.label);
            if (imgui.Checkbox(row.id, options[row.key])) then
                changed = true;
            end
            controls.Mark(row.tooltip);
        end
    end

    controls.EndSection();
    if (controls.Section('Target', '##name.filter.target')) then
        widgets.Label('Always Show Target');
        if (imgui.Checkbox('##name.alwaysTarget', options.alwaysTarget)) then
            changed = true;
        end
        controls.Mark('Your target\'s name is shown though names like it are hidden. Your own is not: with Own Name off it stays hidden while you have yourself targeted.');
    end

    if (changed) then
        Push(options);
        app:Save();
    end

    controls.EndSection();
    controls.EndLayout();
end

-- Troubleshooting is separate from visibility controls and collapsed until needed.
local function DrawDiagnostics(options)
    local hooked = nameplates.Hook() ~= nil;
    controls.BeginLayout('diagnostics', nil, 'Enable Diagnostics');
    if (controls.Section('Diagnostics', '##name.diagnostics', true, true)) then
        if (controls.Checkbox('Enable Diagnostics', '##name.diagnosticsEnabled', options.diagnostics,
                'Record renderer problems and write a log when custom names stop.')) then
            diag.Enable(options.diagnostics[1]);
            app:Save();
        end
        if (hooked) then
            local shown, hidden = 0, 0;
            for _, name in nameplates.Each() do
                if (nameplates.Has(name, nameplates.Flag.Wanted)) then
                    shown = shown + 1;
                else
                    hidden = hidden + 1;
                end
            end
            widgets.Label('Names In View');
            imgui.Text(('%d shown, %d hidden'):format(shown, hidden));
            controls.Mark('The names the game had to draw last frame: near enough, and on screen.');
        end

        if (diag.Enabled()) then
            widgets.Label('Custom Names');
            imgui.Text(diag.Status());
            controls.Mark('Whether Name is drawing the names. When it stops for more than half a second the game draws its own, the reason is said in the chat log once, and a log is written.');

            widgets.Label('Diagnostic Log');
            if (imgui.Button('Write Log##name.diag.write')) then
                local path, problem = diag.Write('written from the settings');
                app:Say(path and ('Log written to ' .. path) or ('The log could not be written: ' .. tostring(problem)));
            end
            controls.Mark('Writes what Name and the namehook plugin are doing now, and what happened lately, to a small text file in config\\addons\\name\\logs. Send it with a report of a problem.');
            if (diag.LastPath() ~= nil) then
                widgets.Label('Last Log');
                imgui.Text(diag.LastPath():match('[^\\]+$'));
            end
        end
    end
    controls.EndSection();
    controls.EndLayout();
end

-- NM Tracking is a tab only after /name dev, for the session
local trackingTab = { label = 'NM Tracking', draw = function (options) custom.DrawTracking(options, app.save); end };

-- The settings, the settings window and the command are the shell's
app = shell.New({
    defaults     = defaults,
    configTitle  = 'Name Settings',
    hideAppearance = true,
    menuOnlyCommands = true,
    command      = '/name',
    help         = 'Use /name to open General, Names, Health Bars, Statuses and Visibility. Diagnostics is under Names.',
    drawSettings = DrawSettings,
    settingsLabel = 'Visibility',
    leadingTabs  = {
        { label = 'General', draw = function (options) general.DrawSettings(options, app.save); end },
        { label = 'Names', draw = function (options)
            custom.DrawSettings(options, app.save);
            DrawDiagnostics(options);
        end },
        { label = 'Health Bars', draw = function (options) custom.DrawHealthBars(options); end },
        { label = 'Statuses', draw = function (options) statuses.DrawSettings(options, app.save); end },
    },
    tabs         = { },

    -- for testers: /name diag on or off, /name diag log; /name dev shows or hides NM Tracking
    commands     = {
        dev = function ()
            local tabs = app.spec.tabs;
            if (tabs[#tabs] == trackingTab) then
                tabs[#tabs] = nil;
                app:Say('NM Tracking hidden.');
            else
                tabs[#tabs + 1] = trackingTab;
                app:Say('NM Tracking is a tab in /name until the addon is reloaded; /name dev hides it.');
            end
        end,
        diag = function (options, args)
            local what = args[3] and args[3]:lower() or nil;
            if (what == 'log') then
                local path, problem = diag.Write('asked for by /name diag log');
                app:Say(path and ('Log written to ' .. path) or ('The log could not be written: ' .. tostring(problem)));
                return;
            end
            local on = not options.diagnostics[1];
            if (what == 'on' or what == 'off') then
                on = what == 'on';
            elseif (what ~= nil) then
                app:Say('/name diag turns diagnostics on or off; /name diag on, /name diag off; /name diag log writes a log.');
                return;
            end
            options.diagnostics[1] = on;
            diag.Enable(on);
            app:Save();
            app:Say(on and 'Diagnostics on: if the names Name draws stop, the reason is said and a log written to config\\addons\\name\\logs. /name diag log writes one now; /name diag off stops.'
                or 'Diagnostics off.');
        end,
    },

    -- another character's settings are given to the plugin afresh
    onSettings   = function (options)
        connected = false;
        custom.Settle(options);
        if (type(options.diagnostics) ~= 'table') then
            options.diagnostics = T{ false };
        end
        diag.Options = options;
        diag.Enable(options.diagnostics[1]);
        diag.Note('Settings loaded');
    end,
});
if (type(app.options.diagnostics) ~= 'table') then
    app.options.diagnostics = T{ false };
end
diag.Options = app.options;
diag.Enable(app.options.diagnostics[1]);

-- A Lua error in drawing the names is kept for the log, then raised as before
local function failed(message)
    diag.Error(message, debug.traceback(tostring(message), 2));
    return message;
end

ashita.events.register('load', 'load_cb', function ()
    custom.Find();
end);

-- what lands on an enemy is kept count of only while statuses are shown over names
ashita.events.register('packet_in', 'name_statuses_packet', function (e)
    if (app.options.showStatuses[1]) then
        statuses.HandlePacket(e);
    end
end);

ashita.events.register('d3d_present', 'present_cb', function ()
    -- the settings window, while it is open
    app:BeginFrame();
    local options = app.options;

    -- the one ask of the plugin this frame: what it gives is handed on
    local hook, why = nameplates.Hook();
    if (hook == nil) then
        if (connected) then
            diag.Note('Plugin lost: %s', tostring(why));
        end
        connected = false;
        diag.Frame(why or 'unloaded');
        return;
    end

    if (not connected) then
        connected = true;
        diag.Note('Plugin found');
        Push(options);
    elseif (Pull(options, hook)) then
        app:Save();
    end

    -- Custom Nameplates off: no claim, and the game draws its names as namehook sizes them
    if (not general.Drawing(options)) then
        nameplates.Claim(0, hook);
        diag.Frame('off');
        return;
    end

    -- with diagnostics off, nothing in the way
    if (not diag.Enabled()) then
        custom.Frame(options, hook);
        return;
    end
    local ok, result, detail = xpcall(custom.Frame, failed, options, hook);
    if (not ok) then
        diag.Frame('error');
        error(result, 0);
    end
    diag.Frame(result, detail);
end);
