addon.name    = 'name';
addon.author  = 'win';
addon.version = '1.30';
addon.desc    = 'Shows and hides the names over characters\' heads by what they are over, and draws them in winxi\'s style, through the namehook plugin.';

require('common');

local bit        = require('bit');
local imgui      = require('imgui');
local shell      = require('winxi.shell');
local widgets    = require('winxi.widgets');
local nameplates = require('winxi.nameplates');
local custom     = require('custom');
local statuses   = require('statuses');
local controls   = require('controls');

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
    { key = 'showNpcs',     category = Category.Npc,      label = 'NPCs',             group = 'NPCs And Monsters',
      tooltip = 'What cannot be fought: townspeople, doors, and the rest.' },
    { key = 'showMonsters', category = Category.Monster,  label = 'Monsters',
      tooltip = 'What can be fought, charmed players among them.' },
};

local defaults = T{
    alwaysTarget = T{ false }, -- the target's name is shown whatever it is over
};
for _, row in ipairs(rows) do
    defaults[row.key] = T{ true };
    row.id = ('##name.%s'):format(row.key);
end
custom.Defaults(defaults);
statuses.Defaults(defaults);
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

    -- what the plugin has to say of the frame just drawn
    if (nameplates.Hook() ~= nil) then
        local shown, hidden = 0, 0;
        for _, name in nameplates.Each() do
            if (nameplates.Has(name, nameplates.Flag.Wanted)) then
                shown = shown + 1;
            else
                hidden = hidden + 1;
            end
        end

        controls.EndSection();
        if (controls.Section('Status', '##name.filter.status')) then
            widgets.Label('Names In View');
            imgui.Text(('%d shown, %d hidden'):format(shown, hidden));
            controls.Mark('The names the game had to draw last frame: near enough, and on screen.');
        end
    end
    controls.EndSection();
    controls.EndLayout();
end

-- The settings, the settings window and the command are the shell's
app = shell.New({
    defaults     = defaults,
    configTitle  = 'Nameplate Settings',
    hideAppearance = true,
    menuOnlyCommands = true,
    command      = '/name',
    help         = 'Use /name to open the Nameplates, Filters, Statuses and NM Tracking menu.',
    drawSettings = DrawSettings,
    settingsLabel = 'Filters',
    leadingTabs  = {
        { label = 'Nameplates', draw = function (options) custom.DrawSettings(options, app.save); end },
    },
    tabs         = {
        { label = 'Statuses', draw = function (options) statuses.DrawSettings(options, app.save); end },
        { label = 'NM Tracking', draw = function (options) custom.DrawTracking(options, app.save); end },
    },

    -- another character's settings are given to the plugin afresh
    onSettings   = function (options) connected = false; custom.Settle(options); end,
});

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
    local hook = nameplates.Hook();
    if (hook == nil) then
        connected = false;
        return;
    end

    if (not connected) then
        connected = true;
        Push(options);
    elseif (Pull(options, hook)) then
        app:Save();
    end

    custom.Frame(options, hook, preferredDefaults);
end);
