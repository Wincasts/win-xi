addon.name    = 'name';
addon.author  = 'win';
addon.version = '1.86-pre1';
addon.desc    = 'Shows and hides the names over characters\' heads by what they are over, and draws them in winxi\'s style, through the namehook plugin.';

-- The winxi this addon was made with, or a newer one: each addon is released with its own copy, so an
-- older one may have been put over it (winxi.version)
local winxiNeeded = 64; -- winxi.partystatus (58: nameplates.Dropped, 55: Generation)
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
local customSettings = require('custom_settings');
local statuses   = require('statuses');
local controls   = require('controls');
local diag       = require('diag');
local castbar    = require('castbar');
local levels     = require('levels');
local general    = require('general');
local nameColours = require('name_colours');
local readability = require('readability');
local invisible  = require('invisible');

local Category = nameplates.Category;

-- The categories as they are set out in the settings: the setting each is kept in, its name there,
-- what it covers, and the group it is under.
local rows = {
    { key = 'showSelf',     category = Category.Self,     label = 'Own Name',         group = 'Players',
      sentence = 'The name over your own head.' },
    { key = 'showParty',    category = Category.Party,    label = 'Party Members',
      sentence = 'The others of your party, trusts among them.' },
    { key = 'showAlliance', category = Category.Alliance, label = 'Alliance Members',
      sentence = 'The other parties of your alliance.' },
    { key = 'showPlayers',  category = Category.Player,   label = 'Other Players',
      sentence = 'Every player outside your party and alliance. A whitelisted player is shown all the same.' },
    { key = 'showMyPet',    category = Category.MyPet,    label = 'My Pet',           group = 'Pets',
      sentence = 'Your own pet.' },
    { key = 'showPets',     category = Category.Pet,      label = 'Other Pets',
      sentence = 'Anyone else\'s pet, trust or adventuring fellow.' },
    { key = 'showNpcs',     category = Category.Npc,      label = 'NPCs',             group = 'NPCs & Monsters',
      sentence = 'What cannot be fought: townspeople, doors, and the rest.' },
    { key = 'showMonsters', category = Category.Monster,  label = 'Monsters',
      sentence = 'What can be fought, charmed players among them.' },
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
local function Prefer(into, from)
    for key, value in pairs(from) do
        if (type(value) == 'table' and value[1] == nil and type(into[key]) == 'table') then
            Prefer(into[key], value);
        else
            into[key] = value;
        end
    end
end
Prefer(defaults, preferredDefaults);

-- The settings are this addon's, kept for each character; what the plugin does with names is the
-- plugin's, and can be changed there by its own command or by another addon. The two are kept the
-- same: the settings are given to the plugin when it is first found and whenever they change here,
-- and a change made there is taken into the settings.
local connected = false;
local featureWarned = false;

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

-- The Visibility tab: which kinds of name are shown, the target whatever it is, and the crowd
local function DrawSettings(options)
    local problem = nameplates.Problem();
    if (problem ~= nil) then
        controls.Note(problem);
    end

    local changed = false;
    if (controls.Section('Names Shown', true)) then
        local first, open = true, true;
        for _, row in ipairs(rows) do
            if (row.group ~= nil) then
                open = controls.Sub(row.group, first);
                first = false;
            end
            if (open and controls.Checkbox(row.label, row.id, options[row.key], row.sentence)) then
                changed = true;
            end
        end
        controls.EndSub();
        widgets.Gap();
        if (controls.Checkbox('Always Show Target', '##name.alwaysTarget', options.alwaysTarget,
                'Shows your target\'s name even when names of its kind are hidden. Your own stays hidden while Own Name is off.')) then
            changed = true;
        end
    end

    if (changed) then
        Push(options);
        app:Save();
    end

    readability.DrawCrowd(options);
end

-- Troubleshooting is separate from visibility controls and collapsed until needed.
local function DrawDiagnostics(options)
    local hooked = nameplates.Hook() ~= nil;
    if (controls.Section('Diagnostics', false, true)) then
        if (controls.Checkbox('Enable Diagnostics', '##name.diagnosticsEnabled', options.diagnostics,
                'Keeps a record of drawing problems, and writes a log when the names stop. /name diag switches it too.')) then
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
            widgets.BeginRow('Names In View', 'The names the game drew last frame: close enough, and on screen.');
            imgui.Text(('%d shown, %d hidden'):format(shown, hidden));
            widgets.EndRow();
        end

        if widgets.Action('Support Report', 'Writes a report for sharing to config\\addons\\name\\logs: versions, counts and what the plugin can do, with no names, chat or paths. /name report does the same.', 'Write Report##name.diag.report') then
            local path, problem = diag.Report();
            app:Say(path and ('Support report written to ' .. path) or ('Could not write support report: ' .. tostring(problem)));
        end
        if diag.LastReportPath() then
            widgets.BeginRow('Last Report', 'The report written last.');
            imgui.Text(diag.LastReportPath():match('[^\\]+$'));
            widgets.EndRow();
        end
        if (diag.Enabled()) then
            widgets.BeginRow('Custom Names', 'Whether the names are being drawn now. When they stop, the reason is said once in the chat log and a log is written.');
            imgui.Text(diag.Status());
            widgets.EndRow();

            if widgets.Action('Diagnostic Log', 'Writes what this addon and namehook are doing to config\\addons\\name\\logs. It can hold character names, paths and errors.', 'Write Log##name.diag.write') then
                local path, problem = diag.Write('written from the settings');
                app:Say(path and ('Log written to ' .. path) or ('The log could not be written: ' .. tostring(problem)));
            end
            if (diag.LastPath() ~= nil) then
                widgets.BeginRow('Last Log', 'The log written last.');
                imgui.Text(diag.LastPath():match('[^\\]+$'));
                widgets.EndRow();
            end
        end
    end
end

-- Leave tabs navigable while Name is off, but only Enable Name can be edited.
local function WhenEnabled(draw)
    return function (options)
        imgui.BeginDisabled(not general.Drawing(options));
        draw(options, app.save);
        imgui.EndDisabled();
    end;
end

-- NM Tracking is a tab only after /name dev, for the session
local trackingTab = { label = 'NM Tracking', draw = WhenEnabled(customSettings.DrawTracking) };

-- The settings, the settings window and the command are the shell's
app = shell.New({
    defaults     = defaults,
    configTitle  = 'Name Settings',
    hideAppearance = true,
    menuOnlyCommands = true,
    command      = '/name',
    help         = 'Use /name to open General, Names, Bars, Check Details, Statuses and Visibility. Diagnostics is under General.',
    drawSettings = WhenEnabled(DrawSettings),
    settingsLabel = 'Visibility',
    leadingTabs  = {
        { label = 'General', draw = function (options)
            general.DrawSettings(options, app.save);
            DrawDiagnostics(options);
        end },
        { label = 'Names', draw = WhenEnabled(customSettings.DrawSettings) },
        { label = 'Bars', draw = WhenEnabled(customSettings.DrawBars) },
        { label = 'Check Details', draw = WhenEnabled(customSettings.DrawCheck) },
        { label = 'Statuses', draw = WhenEnabled(statuses.DrawSettings) },
    },
    tabs         = { },

    -- for testers: /name diag on or off, /name diag log; /name dev shows or hides NM Tracking
    commands     = {
        report = function ()
            local path, problem = diag.Report();
            app:Say(path and ('Support report written to ' .. path) or ('Could not write support report: ' .. tostring(problem)));
        end,
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
        custom.Deactivate();
        custom.Settle(options);
        statuses.Settle(options);
        if (type(options.diagnostics) ~= 'table') then
            options.diagnostics = T{ false };
        end
        diag.Options = options;
        diag.Runtime = custom.Diagnostics;
        diag.Enable(options.diagnostics[1]);
        diag.Note('Settings loaded');
    end,
});
-- A Lua error in drawing the names is kept for the log, then raised as before
local function failed(message)
    diag.Error(message, debug.traceback(tostring(message), 2));
    return message;
end

-- Lua-owned textures can be finalized as soon as unload completes. Unpublish them
-- before native code can consume the last submission, even before its first scene.
ashita.events.register('unload', 'name_render_unload', function ()
    custom.Deactivate();
end);

-- Every packet in, handed to each part that reads them: the area entered, checks and deaths for
-- levels and the diagnostics' history; which monsters were called for help on, for their colour; and
-- what lands on an enemy, kept count of only while statuses are shown over names
ashita.events.register('packet_in', 'name_packet_in', function (e)
    castbar.HandlePacket(e, app.options);
    levels.HandlePacket(e);
    diag.HandlePacket(e);
    if e.id == 0x00A then custom.ResetReadability(); end
    nameColours.HandlePacket(e);
    invisible.HandlePacket(e);
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
        connected, featureWarned = false, false;
        custom.Deactivate();
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
        custom.Deactivate();
        nameplates.Claim(0, hook);
        diag.Frame('off');
        return;
    end

    if not nameplates.Supports(nameplates.Feature.IconOutline, hook) then
        custom.Deactivate();
        nameplates.Claim(0, hook);
        if not featureWarned then
            app:Say(nameplates.Problem(nameplates.Feature.IconOutline));
            featureWarned = true;
        end
        diag.Frame('features');
        return;
    end
    featureWarned = false;

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
