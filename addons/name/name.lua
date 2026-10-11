addon.name    = 'name';
addon.author  = 'win (and claude)';
addon.version = '1.18';
addon.desc    = 'Shows and hides the names over characters\' heads by what they are over, and draws them in winxi\'s style, through the namehook plugin.';

require('common');

local bit        = require('bit');
local imgui      = require('imgui');
local shell      = require('winxi.shell');
local widgets    = require('winxi.widgets');
local nameplates = require('winxi.nameplates');
local custom     = require('custom');

local Category = nameplates.Category;

-- The categories as they are set out in the settings: the setting each is kept in, its name there,
-- the words a command knows it by, and what it covers. A gap comes before those marked.
local rows = {
    { key = 'showSelf',     category = Category.Self,     label = 'Own Name',         words = { 'self' },
      tooltip = 'The name over your own head.' },
    { key = 'showParty',    category = Category.Party,    label = 'Party Members',    words = { 'party' },
      tooltip = 'The others of your party, trusts among them.' },
    { key = 'showAlliance', category = Category.Alliance, label = 'Alliance Members', words = { 'alliance' },
      tooltip = 'The other parties of your alliance.' },
    { key = 'showPlayers',  category = Category.Player,   label = 'Other Players',    words = { 'players', 'player' },
      tooltip = 'Every player who is not of your party or alliance. A player on the plugin\'s whitelist is shown all the same: /namehook whitelist add <name>' },
    { key = 'showMyPet',    category = Category.MyPet,    label = 'My Pet',           words = { 'mypet' }, gap = true,
      tooltip = 'Your own pet.' },
    { key = 'showPets',     category = Category.Pet,      label = 'Other Pets',       words = { 'pets', 'pet' },
      tooltip = 'Anyone else\'s pet, trust or adventuring fellow.' },
    { key = 'showNpcs',     category = Category.Npc,      label = 'NPCs',             words = { 'npcs', 'npc' }, gap = true,
      tooltip = 'What cannot be fought: townspeople, doors, and the rest.' },
    { key = 'showMonsters', category = Category.Monster,  label = 'Monsters',         words = { 'monsters', 'monster', 'mobs', 'mob' },
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

    local changed = false;
    for _, row in ipairs(rows) do
        if (row.gap) then
            widgets.Gap();
        end
        widgets.Label(row.label);
        if (imgui.Checkbox(row.id, options[row.key])) then
            changed = true;
        end
        if (imgui.IsItemHovered()) then
            imgui.SetTooltip(row.tooltip);
        end
    end

    widgets.Gap();
    widgets.Label('Always Show Target');
    if (imgui.Checkbox('##name.alwaysTarget', options.alwaysTarget)) then
        changed = true;
    end
    if (imgui.IsItemHovered()) then
        imgui.SetTooltip('Your target\'s name is shown though names like it are hidden. Your own is not: with Own Name off it stays hidden while you have yourself targeted.');
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

        widgets.Gap();
        widgets.Label('Names In View');
        imgui.Text(('%d shown, %d hidden'):format(shown, hidden));
        if (imgui.IsItemHovered()) then
            imgui.SetTooltip('The names the game had to draw last frame: near enough, and on screen.');
        end
    end
end

-- show, hide or toggle, then the categories by their words, or all
local function SetByWords(options, args, show)
    local chosen = {};
    for i = 3, #args do
        local word = args[i]:lower();
        local found = false;
        for _, row in ipairs(rows) do
            local named = word == 'all';
            for _, known in ipairs(row.words) do
                named = named or word == known;
            end
            if (named) then
                chosen[row] = true;
                found = true;
            end
        end
        if (not found) then
            app:Say(('"%s" is not a kind of name. They are: self, party, alliance, players, mypet, pets, npcs, monsters, and all.'):format(args[i]));
            return;
        end
    end

    if (next(chosen) == nil) then
        app:Say(app.spec.help);
        return;
    end

    for row in pairs(chosen) do
        if (show == nil) then
            options[row.key][1] = not options[row.key][1];
        else
            options[row.key][1] = show;
        end
    end
    Push(options);
    app:Save();
end

-- The settings, the settings window and the command are the shell's
app = shell.New({
    defaults     = defaults,
    configTitle  = 'Name Settings',
    command      = '/name',
    help         = '/name opens or closes the settings; /name show, hide and toggle, each followed by self, party, alliance, players, mypet, pets, npcs, monsters or all, show and hide names; /name custom switches whether this addon draws the names or the game does.',
    drawSettings = DrawSettings,
    tabs         = { { label = 'Custom Names', draw = function (options) custom.DrawSettings(options, app.save); end } },
    commands     = {
        show   = function (options, args) SetByWords(options, args, true); end,
        hide   = function (options, args) SetByWords(options, args, false); end,
        toggle = function (options, args) SetByWords(options, args, nil); end,
        custom = function (options, args)
            local word = args[3] and args[3]:lower() or nil;
            if (word == 'on') then
                options.customNames[1] = true;
            elseif (word == 'off') then
                options.customNames[1] = false;
            else
                options.customNames[1] = not options.customNames[1];
            end
            app:Save();
            app:Say(options.customNames[1] and 'Names are drawn by this addon.' or 'Names are drawn by the game.');
        end,
    },
    -- another character's settings are given to the plugin afresh
    onSettings   = function (options) connected = false; custom.Settle(options); end,
});

ashita.events.register('load', 'load_cb', function ()
    custom.Find();
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

    custom.Frame(options, hook);
end);
