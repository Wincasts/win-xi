local chat = require('chat');
local settings = require('settings');
local window = require('winxi.window');
local widgets = require('winxi.widgets');

local defaultSettings = T {
    filter = 'All', -- /targetlines filters: All, Alliance or Party
    quietMode = false, -- /targetlines quietmode on: draw only the lines to or from you and your pet, and from the mob you are targeting
    mobBrief = false, -- /targetlines persistentenemy off: mob lines show briefly on a new target, like player lines
    mobThreat = true, -- /targetlines enmitymode on: mob lines follow who the mob is on while it stays engaged
    -- Line colours as red, green, blue, alpha from 0 to 1. Alpha is unused; opacity is set separately.
    colors = T {
        player = { 0, 0.533, 1, 1 },
        enemy = { 1, 0.067, 0.2, 1 },
        playerFriendly = { 0, 1, 0.4, 1 },
        enemyFriendly = { 1, 0.533, 0, 1 },
        pet = { 0.98, 0.502, 0.447, 1 } -- salmon
    },
    curve = 100, -- /targetlines curve 100: how far a line bows out from the straight way between its ends, as a percentage
    orbScale = 80, -- /targetlines orbsize 80: size of the orb at the tip of a line as it draws in, as a percentage
    transparency = 20, -- /targetlines opacity 80: stored as how see-through the lines are, 0-90 percent
    nameplateAnchor = false, -- /targetlines nameplate on: lines start and end where the game puts each name, and stop short of each end
    nameplateRaise = 0, -- /targetlines anchorheight 0: how far above (or, below 0, under) the name a line starts and ends, in tenths of a yalm
    nameplateInset = 5, -- /targetlines anchorgap 5: how far short of each anchor a line starts and ends, in tenths of a yalm
    occlude = false, -- /targetlines occlude on: lines are hidden where a wall, the ground or a character is in front of them
    petLine = true, -- /targetlines petenmity on: draw a line from your pet to what it is attacking
    aggroSound = true -- /targetlines alertsound on: play assets/aggro.wav when a mob line or someone else's green line is drawn to you or your pet
};

local s = settings.load(defaultSettings);

-- Changes made in the config window are held here, by setting name, and take effect only when the
-- Save Settings button applies and writes them. Text commands apply and save straight away.
local pending = {};
local pendingColors = {}; -- by line type

-- The settings table is replaced when the character changes, so follow it
settings.register('settings', 'targetlines_settings_update', function(newSettings)
    if (newSettings ~= nil) then
        s = newSettings;
        pending = {};
        pendingColors = {};
    end
end);

local filters = T {
    'All',
    'Alliance',
    'Party'
};

local showConfig = { false };

-- The value the config window shows for a setting: the pending one if there is one
local function shown(key)
    local value = pending[key];
    if (value == nil) then
        return s[key];
    end
    return value;
end

-- Holds a value chosen in the config window until it is saved
local function stage(key, value)
    if (value == s[key]) then
        pending[key] = nil;
    else
        pending[key] = value;
    end
end

local function hasPending()
    return next(pending) ~= nil or next(pendingColors) ~= nil;
end

-- Applies everything pending and writes the settings to disk
local function saveSettings()
    for key, value in pairs(pending) do
        s[key] = value;
    end
    if (next(pendingColors) ~= nil) then
        if (type(s.colors) ~= 'table') then
            s.colors = T {};
        end
        for key, value in pairs(pendingColors) do
            s.colors[key] = value;
        end
    end
    pending = {};
    pendingColors = {};
    settings.save();
end

-- A text command has set this setting: save it, dropping any pending value the window held for it
local function commit(key)
    pending[key] = nil;
    settings.save();
end

local minOrbScale, maxOrbScale = 25, 300;
local minCurve, maxCurve = 10, 300;

-- The test line: one drawn from the player to the player's target, over and over, for as long as this
-- is on, so that how the lines look can be set with a line to look at. It is not a setting and is
-- not saved. While it is on, the lines are drawn as the config window has them, saved or not.
local testLine = { false };

-- The settings as the config window shows them: what is pending where there is any, and what is
-- saved where there is not
local previewColors = setmetatable({}, {
    __index = function(_, key)
        return pendingColors[key] or (type(s.colors) == 'table' and s.colors[key]) or nil;
    end
});
local preview = setmetatable({}, {
    __index = function(_, key)
        if (key == 'colors') then
            return previewColors;
        end
        return shown(key);
    end
});
local minNameplateRaise, maxNameplateRaise = -30, 30;
local minNameplateInset, maxNameplateInset = 0, 50;

-- The kinds of line the addon draws, in the order their colours are listed in the settings window
local lineTypes = T {
    { key = 'player', label = 'Player', id = '##color.player', sentence = 'A player\'s line to the enemy it acts on.' },
    { key = 'enemy', label = 'Enemy', id = '##color.enemy', sentence = 'An enemy\'s line to the player it acts on.' },
    { key = 'playerFriendly', label = 'Friendly', id = '##color.playerFriendly', sentence = 'A player\'s line to another player it helps.' },
    { key = 'pet', label = 'Pet', id = '##color.pet', sentence = 'Your pet\'s line to what it is attacking.' },
    { key = 'enemyFriendly', label = 'Other', id = '##color.enemyFriendly', sentence = 'An enemy\'s line to another enemy it acts on.' }
};
local maxTransparency = 90; -- 100 would make the lines invisible
local config = T {};

-- Whether the test line is on, and the settings to draw by while it is
config.isTesting = function()
    return testLine[1];
end

config.preview = function()
    return preview;
end

-- The settings window: described rows (winxi 65) in sections, in a settings window of winxi's.
-- Every control shows what is pending where there is anything, and stages what is chosen; the Save
-- Settings row applies and writes it all.

-- A control's value on its way in and out: one table a setting, made once
local boxes = {};

local function box(key, value)
    local held = boxes[key];
    if (held == nil) then
        held = { value };
        boxes[key] = held;
    else
        held[1] = value;
    end
    return held;
end

-- Stages a checkbox's new value when it was ticked or unticked
local function stagedCheck(name, sentence, key, id, spec)
    local held = box(key, shown(key) and true or false);
    if (widgets.Check(name, sentence, held, id, spec)) then
        stage(key, held[1]);
    end
end

local function stagedSlider(name, sentence, key, default, low, high, id, spec)
    local held = box(key, tonumber(shown(key)) or default);
    if (widgets.Slider(name, sentence, held, low, high, id, spec)) then
        stage(key, held[1]);
    end
end

local experimentalSpec = { experimental = true };
local anchorSpec = { parent = false }; -- Anchor Height and Anchor Gap, under Anchor To Nameplate
local pickedColors = {}; -- by line type: the swatch's colour this frame, the picker's changes read from it
local configStyle = { kind = window.Settings };
local configFlags = nil;

local function drawLines()
    if (widgets.Header('Lines', true)) then
        local chosen = widgets.Dropdown('Filters', 'Draws everyone\'s lines, or only those tied to your party or alliance. /targetlines filters sets it too.',
            filters, shown('filter'), '##filters');
        if (chosen ~= nil) then
            stage('filter', chosen);
        end
        stagedCheck('Quiet Mode', 'Draws only the lines to or from you, your pet and your target. /targetlines quietmode switches it too.',
            'quietMode', '##quietmode');

        -- Stored as its opposite: mobBrief is true when mob lines are not persistent
        local persistentMob = box('persistentMob', not shown('mobBrief'));
        if (widgets.Check('Persistent Enemy Targets', 'Keeps a mob\'s line up for as long as it applies. Off, it shows for a few seconds.',
                persistentMob, '##persistentenemy')) then
            stage('mobBrief', not persistentMob[1]);
        end
        stagedCheck('Show Pet Enmity', 'Draws a line from your pet to whatever it is attacking. /targetlines petenmity switches it too.',
            'petLine', '##petenmity');
        stagedCheck('Enmity Mode', 'Draws a mob\'s line to whoever it is fighting. Off, only when it acts.',
            'mobThreat', '##enmitymode', experimentalSpec);
        widgets.Gap();
        stagedCheck('Enmity Alert Sound', 'Plays a sound when a mob turns on you or your pet, or someone starts helping you.',
            'aggroSound', '##alertsound');
    end
end

local function drawLook()
    if (widgets.Header('Look')) then
        -- the test line's own box, not a setting: nothing to stage
        widgets.Check('Show Test Line', 'Draws a line from you to your target, using the settings as they are here.',
            testLine, '##testline');

        -- Shown as opacity (80% by default); stored as its complement, transparency
        local opacity = box('opacity', 100 - (tonumber(shown('transparency')) or 20));
        if (widgets.Slider('Opacity', 'How solid the lines are.', opacity, 100 - maxTransparency, 100, '##opacity', widgets.Percent)) then
            stage('transparency', 100 - opacity[1]);
        end
        stagedSlider('Curve', 'How far each line bows out. 100 is the usual curve.',
            'curve', 100, minCurve, maxCurve, '##curve', widgets.Percent);
        stagedSlider('Orb Size', 'How big the orb at the tip of a line is while it draws in.',
            'orbScale', 80, minOrbScale, maxOrbScale, '##orbscale', widgets.Percent);
        widgets.Gap();
        stagedCheck('Anchor To Nameplate', 'Starts and ends each line at the character\'s name instead of its body.',
            'nameplateAnchor', '##nameplateanchor', experimentalSpec);
        anchorSpec.parent = shown('nameplateAnchor') and true or false;
        stagedSlider('Anchor Height', 'How far above the name each line starts and ends. Below 0 is under it.',
            'nameplateRaise', 0, minNameplateRaise, maxNameplateRaise, '##nameplateraise', anchorSpec);
        stagedSlider('Anchor Gap', 'How far short of each name a line stops. 0 runs it the whole way.',
            'nameplateInset', 5, minNameplateInset, maxNameplateInset, '##nameplateinset', anchorSpec);
        stagedCheck('Hide Behind Objects', 'Hides any part of a line that is behind a wall, the ground or a character.',
            'occlude', '##occlude', experimentalSpec);
    end
end

local function drawColours()
    if (widgets.Header('Colours')) then
        -- One swatch per kind of line; the picker opens on it
        local savedColors = type(s.colors) == 'table' and s.colors or {};
        for _, lineType in ipairs(lineTypes) do
            local key = lineType.key;
            local current = pendingColors[key] or savedColors[key] or defaultSettings.colors[key];
            local picked = pickedColors[key];
            if (picked == nil) then
                picked = { 0, 0, 0, 1 };
                pickedColors[key] = picked;
            end
            picked[1], picked[2], picked[3], picked[4] = current[1], current[2], current[3], 1;
            if (widgets.Color(lineType.label, lineType.sentence, picked, lineType.id)) then
                pendingColors[key] = { picked[1], picked[2], picked[3], 1 };
            end
        end
        if (widgets.Action('Reset Colours', 'Puts every line colour back to its default.', 'Reset##resetcolours')) then
            for _, lineType in ipairs(lineTypes) do
                local default = defaultSettings.colors[lineType.key];
                pendingColors[lineType.key] = { default[1], default[2], default[3], 1 };
            end
        end
    end
end

local function drawSaving()
    if (widgets.Header('Saving')) then
        if (widgets.Action('Save Settings', 'Applies and saves the changes made here. /targetlines save does the same.', 'Save##save')) then
            saveSettings();
        end
    end
end

local function drawContent()
    drawLines();
    drawLook();
    drawColours();
    drawSaving();
    if (not hasPending()) then
        widgets.Status('Everything here is saved.');
    elseif (testLine[1]) then
        widgets.Status('Unsaved changes. The lines are drawn with them while the test line is on.');
    else
        widgets.Status('Unsaved changes. Nothing changed here takes effect until it is saved.');
    end
end

config.drawWindow = function()
    if (showConfig[1]) then
        configFlags = configFlags or ImGuiWindowFlags_NoSavedSettings;
        window.Full('Targetlines Settings', showConfig, configFlags, drawContent, configStyle);
    end
end

local function printHelp()
    local function line(command, description)
        print(chat.header(addon.name) .. chat.color1(2, command) .. chat.message(' - ' .. description));
    end

    print(chat.header(addon.name) .. chat.message('Commands:'));
    line('/targetlines', 'Open or close the config window.');
    line('/targetlines filters|f [all|alliance|party]', 'Whose lines are drawn: everyone\'s, or only those connected to your alliance or party. No option shows the current filter.');
    line('/targetlines quietmode|q [on|off]', 'Draw only the lines to or from you and your pet, and the line from the mob you are targeting. No option toggles.');
    line('/targetlines persistentenemy|pe [on|off]', 'On keeps a mob\'s line up for as long as it applies. Off shows it for a few seconds when the mob changes target, like player lines. No option toggles.');
    line('/targetlines enmitymode|em [on|off]', 'On draws mob lines to whoever the mob is judged to be on while it stays engaged. Off draws them only when the mob takes an action. No option toggles.');
    line('/targetlines petenmity|p [on|off]', 'Draw a line from your pet to whatever it is attacking. No option toggles.');
    line('/targetlines nameplate|n [on|off]', 'Start and end each line where the game puts the name of the character at that end, in place of the middle of the body, and stop the line a little short of each end. No option toggles.');
    line('/targetlines occlude|oc [on|off]', 'Hide each part of a line that has a wall, the ground or a character in front of it. No option toggles.');
    line('/targetlines anchorheight|ah <' .. minNameplateRaise .. ' to ' .. maxNameplateRaise .. '>', 'With nameplate anchoring on, how far above the name each line starts and ends, or below it for less than 0, in tenths of a yalm. No option shows the current value.');
    line('/targetlines anchorgap|ag <' .. minNameplateInset .. '-' .. maxNameplateInset .. '>', 'With nameplate anchoring on, how far short of each anchor a line starts and ends, in tenths of a yalm. No option shows the current value.');
    line('/targetlines opacity|o <10-100>', 'How solid the lines are, as a percentage. 100 is fully solid. No option shows the current value.');
    line('/targetlines curve|c <' .. minCurve .. '-' .. maxCurve .. '>', 'How far each line bows out from the straight way between its ends, as a percentage. 100 is the normal curve. No option shows the current value.');
    line('/targetlines test|t [on|off]', 'Draw a line from you to your target, over and over, to set the look of the lines by. Not saved. No option toggles.');
    line('/targetlines orbsize|os <' .. minOrbScale .. '-' .. maxOrbScale .. '>', 'Size of the orb at the tip of a line while it draws in, as a percentage. 100 is the normal size. No option shows the current value.');
    line('/targetlines alertsound|as [on|off]', 'Play a sound when a mob turns on you or your pet, or someone else newly switches to you or your pet with a green line (a heal or buff). At most once a second. No option toggles.');
    line('/targetlines save', 'Apply and save the changes made in the config window, the same as its Save Settings button.');
    line('/targetlines help|h', 'Show this list.');
end

ashita.events.register('command', 'command_cb', function(e)
    -- Parse the command arguments
    local command_args = e.command:lower():args()
    if table.contains({ '/targetlines' }, command_args[1]) then
        local command = command_args[2];
        local option = command_args[3];

        if (command == 'persistentenemy' or command == 'pe') then
            -- Stored as its opposite: mobBrief is true when mob lines are not persistent
            if (option == 'on') then
                s.mobBrief = false;
            elseif (option == 'off') then
                s.mobBrief = true;
            elseif (option == nil) then
                s.mobBrief = not s.mobBrief;
            else
                print(chat.header(addon.name) .. chat.error('Unknown option. Use: /targetlines persistentenemy|pe [on|off]'));
                e.blocked = true;
                return;
            end
            commit('mobBrief');
            print(chat.header(addon.name) .. chat.message('Persistent Enemy Targets: ') .. chat.success(s.mobBrief and 'off (shown briefly on a new target)' or 'on'));
        elseif (command == 'filters' or command == 'f') then
            if (option == nil) then
                print(chat.header(addon.name) .. chat.message('Filters: ') .. chat.success(tostring(s.filter)));
            else
                -- Arguments arrive lower-cased; match them to the dropdown's names
                local chosen;
                for _, name in ipairs(filters) do
                    if (name:lower() == option) then
                        chosen = name;
                    end
                end
                if (not chosen) then
                    print(chat.header(addon.name) .. chat.error('Unknown option. Use: /targetlines filters|f [all|alliance|party]'));
                    e.blocked = true;
                    return;
                end
                s.filter = chosen;
                commit('filter');
                print(chat.header(addon.name) .. chat.message('Filters: ') .. chat.success(s.filter));
            end
        elseif (command == 'quietmode' or command == 'q') then
            if (option == 'on') then
                s.quietMode = true;
            elseif (option == 'off') then
                s.quietMode = false;
            elseif (option == nil) then
                s.quietMode = not s.quietMode;
            else
                print(chat.header(addon.name) .. chat.error('Unknown option. Use: /targetlines quietmode|q [on|off]'));
                e.blocked = true;
                return;
            end
            commit('quietMode');
            print(chat.header(addon.name) .. chat.message('Quiet Mode: ') .. chat.success(s.quietMode and 'on' or 'off'));
        elseif (command == 'enmitymode' or command == 'em') then
            if (option == 'on') then
                s.mobThreat = true;
            elseif (option == 'off') then
                s.mobThreat = false;
            elseif (option == nil) then
                s.mobThreat = not s.mobThreat;
            else
                print(chat.header(addon.name) .. chat.error('Unknown option. Use: /targetlines enmitymode|em [on|off]'));
                e.blocked = true;
                return;
            end
            commit('mobThreat');
            print(chat.header(addon.name) .. chat.message('Experimental Enmity Mode: ') .. chat.success(s.mobThreat and 'on (follows the mob\'s target while engaged)' or 'off (mob actions only)'));
        elseif (command == 'opacity' or command == 'o') then
            -- Given and shown as opacity; stored as its complement, transparency
            local minOpacity = 100 - maxTransparency;
            if (option == nil) then
                print(chat.header(addon.name) .. chat.message('Line opacity: ') .. chat.success(tostring(100 - (tonumber(s.transparency) or 20)) .. ' percent'));
            else
                local value = tonumber(option);
                if (not value or value < minOpacity or value > 100) then
                    print(chat.header(addon.name) .. chat.error('Unknown option. Use: /targetlines opacity|o <' .. minOpacity .. '-100>'));
                    e.blocked = true;
                    return;
                end
                s.transparency = 100 - math.floor(value);
                commit('transparency');
                print(chat.header(addon.name) .. chat.message('Line opacity: ') .. chat.success(tostring(100 - s.transparency) .. ' percent'));
            end
        elseif (command == 'curve' or command == 'c') then
            if (option == nil) then
                print(chat.header(addon.name) .. chat.message('Curve: ') .. chat.success(tostring(tonumber(s.curve) or 100) .. ' percent'));
            else
                local value = tonumber(option);
                if (not value or value < minCurve or value > maxCurve) then
                    print(chat.header(addon.name) .. chat.error('Unknown option. Use: /targetlines curve|c <' .. minCurve .. '-' .. maxCurve .. '>'));
                    e.blocked = true;
                    return;
                end
                s.curve = math.floor(value);
                commit('curve');
                print(chat.header(addon.name) .. chat.message('Curve: ') .. chat.success(tostring(s.curve) .. ' percent'));
            end
        elseif (command == 'test' or command == 't') then
            if (option == 'on') then
                testLine[1] = true;
            elseif (option == 'off') then
                testLine[1] = false;
            elseif (option == nil) then
                testLine[1] = not testLine[1];
            else
                print(chat.header(addon.name) .. chat.error('Unknown option. Use: /targetlines test|t [on|off]'));
                e.blocked = true;
                return;
            end
            print(chat.header(addon.name) .. chat.message('Test line: ') .. chat.success(testLine[1] and 'on (from you to your target)' or 'off'));
        elseif (command == 'orbsize' or command == 'os') then
            if (option == nil) then
                print(chat.header(addon.name) .. chat.message('Orb size: ') .. chat.success(tostring(tonumber(s.orbScale) or 80) .. ' percent'));
            else
                local value = tonumber(option);
                if (not value or value < minOrbScale or value > maxOrbScale) then
                    print(chat.header(addon.name) .. chat.error('Unknown option. Use: /targetlines orbsize|os <' .. minOrbScale .. '-' .. maxOrbScale .. '>'));
                    e.blocked = true;
                    return;
                end
                s.orbScale = math.floor(value);
                commit('orbScale');
                print(chat.header(addon.name) .. chat.message('Orb size: ') .. chat.success(tostring(s.orbScale) .. ' percent'));
            end
        elseif (command == 'petenmity' or command == 'p') then
            if (option == 'on') then
                s.petLine = true;
            elseif (option == 'off') then
                s.petLine = false;
            elseif (option == nil) then
                s.petLine = not s.petLine;
            else
                print(chat.header(addon.name) .. chat.error('Unknown option. Use: /targetlines petenmity|p [on|off]'));
                e.blocked = true;
                return;
            end
            commit('petLine');
            print(chat.header(addon.name) .. chat.message('Show Pet Enmity: ') .. chat.success(s.petLine and 'on' or 'off'));
        elseif (command == 'occlude' or command == 'oc') then
            if (option == 'on') then
                s.occlude = true;
            elseif (option == 'off') then
                s.occlude = false;
            elseif (option == nil) then
                s.occlude = not s.occlude;
            else
                print(chat.header(addon.name) .. chat.error('Unknown option. Use: /targetlines occlude|oc [on|off]'));
                e.blocked = true;
                return;
            end
            commit('occlude');
            print(chat.header(addon.name) .. chat.message('Experimental Hide Behind Objects: ') .. chat.success(s.occlude and 'on' or 'off'));
        elseif (command == 'nameplate' or command == 'n') then
            if (option == 'on') then
                s.nameplateAnchor = true;
            elseif (option == 'off') then
                s.nameplateAnchor = false;
            elseif (option == nil) then
                s.nameplateAnchor = not s.nameplateAnchor;
            else
                print(chat.header(addon.name) .. chat.error('Unknown option. Use: /targetlines nameplate|n [on|off]'));
                e.blocked = true;
                return;
            end
            commit('nameplateAnchor');
            print(chat.header(addon.name) .. chat.message('Experimental Anchor To Nameplate: ') .. chat.success(s.nameplateAnchor and 'on' or 'off'));
        elseif (command == 'anchorheight' or command == 'ah') then
            if (option == nil) then
                print(chat.header(addon.name) .. chat.message('Anchor height: ') .. chat.success(tostring(tonumber(s.nameplateRaise) or 0)));
            else
                local value = tonumber(option);
                if (not value or value < minNameplateRaise or value > maxNameplateRaise) then
                    print(chat.header(addon.name) .. chat.error('Unknown option. Use: /targetlines anchorheight|ah <' .. minNameplateRaise .. ' to ' .. maxNameplateRaise .. '>'));
                    e.blocked = true;
                    return;
                end
                s.nameplateRaise = math.floor(value);
                commit('nameplateRaise');
                print(chat.header(addon.name) .. chat.message('Anchor height: ') .. chat.success(tostring(s.nameplateRaise)));
            end
        elseif (command == 'anchorgap' or command == 'ag') then
            if (option == nil) then
                print(chat.header(addon.name) .. chat.message('Anchor gap: ') .. chat.success(tostring(tonumber(s.nameplateInset) or 5)));
            else
                local value = tonumber(option);
                if (not value or value < minNameplateInset or value > maxNameplateInset) then
                    print(chat.header(addon.name) .. chat.error('Unknown option. Use: /targetlines anchorgap|ag <' .. minNameplateInset .. '-' .. maxNameplateInset .. '>'));
                    e.blocked = true;
                    return;
                end
                s.nameplateInset = math.floor(value);
                commit('nameplateInset');
                print(chat.header(addon.name) .. chat.message('Anchor gap: ') .. chat.success(tostring(s.nameplateInset)));
            end
        elseif (command == 'alertsound' or command == 'as') then
            if (option == 'on') then
                s.aggroSound = true;
            elseif (option == 'off') then
                s.aggroSound = false;
            elseif (option == nil) then
                s.aggroSound = not s.aggroSound;
            else
                print(chat.header(addon.name) .. chat.error('Unknown option. Use: /targetlines alertsound|as [on|off]'));
                e.blocked = true;
                return;
            end
            commit('aggroSound');
            print(chat.header(addon.name) .. chat.message('Enmity Alert Sound: ') .. chat.success(s.aggroSound and 'on' or 'off'));
        elseif (command == 'save') then
            saveSettings();
            print(chat.header(addon.name) .. chat.message('Settings saved.'));
        elseif (command == 'help' or command == 'h') then
            printHelp();
        elseif (command == nil) then
            -- Toggle the config menu
            showConfig[1] = not showConfig[1];
        else
            print(chat.header(addon.name) .. chat.error('Unknown command: ' .. command));
            printHelp();
        end
        e.blocked = true;
    end
end);

ashita.events.register('d3d_present', 'config_cb', function()
    config.drawWindow();
end);

return config;
