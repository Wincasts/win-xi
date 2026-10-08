local imgui = require('imgui');
local chat = require('chat');
local settings = require('settings');

local defaultSettings = T {
    filter = 'All',
    mobBrief = false, -- /targetlines persistentmob off: mob lines show briefly on a new target, like player lines
    mobThreat = true, -- /targetlines threatmode new: mob lines follow who the mob is on while it stays engaged
    petLine = true, -- /targetlines petline on: draw a line from your pet to what it is attacking
    aggroSound = true -- /targetlines sound on: play assets/aggro.wav when a mob line or someone else's green line is drawn to you or your pet
};

local s = settings.load(defaultSettings);

-- The settings table is replaced when the character changes, so follow it
settings.register('settings', 'targetlines_settings_update', function(newSettings)
    if (newSettings ~= nil) then
        s = newSettings;
    end
end);

local filters = T {
    'All',
    'Alliance',
    'Party'
};

local showConfig = { false };
local config = T {};

config.drawWindow = function()
    if (showConfig[1]) then
        imgui.PushStyleColor(ImGuiCol_WindowBg, { 0, 0.06, .16, .9 });
        imgui.PushStyleColor(ImGuiCol_TitleBg, { 0, 0.06, .16, .7 });
        imgui.PushStyleColor(ImGuiCol_TitleBgActive, { 0, 0.06, .16, .9 });
        imgui.PushStyleColor(ImGuiCol_TitleBgCollapsed, { 0, 0.06, .16, .5 });
        imgui.PushStyleColor(ImGuiCol_Header, { 0, 0.06, .16, .7 });
        imgui.PushStyleColor(ImGuiCol_HeaderHovered, { 0, 0.06, .16, .9 });
        imgui.PushStyleColor(ImGuiCol_HeaderActive, { 0, 0.06, .16, 1 });
        imgui.PushStyleColor(ImGuiCol_FrameBg, { 0, 0.06, .16, 1 });
        imgui.SetNextWindowSize({ 400, 260 }, ImGuiCond_FirstUseEver);

        if (imgui.Begin(('Targetlines Config'):fmt(addon.version), showConfig, bit.bor(ImGuiWindowFlags_NoSavedSettings))) then
            imgui.BeginChild("Config Options", { 0, 0 }, ImGuiChildFlags_Borders or ImGuiChildFlags_Border or true);
            if (imgui.BeginCombo('Filters', s.filter)) then
                for i = 1, 3 do
                    local isSelected = filters[i] == s.filter;

                    if (imgui.Selectable(filters[i], isSelected) and filters[i] ~= s.filter) then
                        s.filter = filters[i];
                        settings.save();
                    end

                    if (isSelected) then
                        imgui.SetItemDefaultFocus();
                    end
                end
                imgui.EndCombo();
            end

            local persistentMob = { not s.mobBrief };
            if (imgui.Checkbox('Persistent mob lines', persistentMob)) then
                s.mobBrief = not persistentMob[1];
                settings.save();
            end
            if (imgui.IsItemHovered()) then
                imgui.SetTooltip('On keeps a mob\'s line up for as long as it applies.\nOff shows it for a few seconds when the mob changes target, like player lines.\n/targetlines persistentmob [on|off]');
            end

            local newThreatMode = { s.mobThreat and true or false };
            if (imgui.Checkbox('New threat mode', newThreatMode)) then
                s.mobThreat = newThreatMode[1];
                settings.save();
            end
            if (imgui.IsItemHovered()) then
                imgui.SetTooltip('On draws mob lines to whoever the mob is judged to be on while it stays engaged.\nOff (old mode) draws them only when the mob takes an action.\n/targetlines threatmode [old|new]');
            end

            local petLine = { s.petLine and true or false };
            if (imgui.Checkbox('Pet line', petLine)) then
                s.petLine = petLine[1];
                settings.save();
            end
            if (imgui.IsItemHovered()) then
                imgui.SetTooltip('Draws a pink line from your pet to whatever it is attacking.\n/targetlines petline [on|off]');
            end

            local aggroSound = { s.aggroSound and true or false };
            if (imgui.Checkbox('Line sound', aggroSound)) then
                s.aggroSound = aggroSound[1];
                settings.save();
            end
            if (imgui.IsItemHovered()) then
                imgui.SetTooltip('Plays a sound when a mob turns on you or your pet, and when someone else newly switches to you or your pet with a green line (a heal or buff).\nAt most once a second.\n/targetlines sound [on|off]');
            end
            imgui.EndChild();
        end
        imgui.PopStyleColor(8);
        imgui.End();
    end
end

local function printHelp()
    local function line(command, description)
        print(chat.header(addon.name) .. chat.color1(2, command) .. chat.message(' - ' .. description));
    end

    print(chat.header(addon.name) .. chat.message('Commands:'));
    line('/targetlines', 'Open or close the config window.');
    line('/targetlines persistentmob [on|off]', 'Short form: pmob. On keeps a mob\'s line up for as long as it applies. Off shows it for a few seconds when the mob changes target, like player lines. No option toggles.');
    line('/targetlines threatmode [old|new]', 'Short form: t. New draws mob lines to whoever the mob is judged to be on while it stays engaged. Old draws them only when the mob takes an action. No option toggles.');
    line('/targetlines petline [on|off]', 'Short form: pl. Draw a line from your pet to whatever it is attacking. No option toggles.');
    line('/targetlines sound [on|off]', 'Short form: s. Play a sound when a mob turns on you or your pet, or someone else newly switches to you or your pet with a green line (a heal or buff). At most once a second. No option toggles.');
    line('/targetlines help', 'Short form: h. Show this list.');
end

ashita.events.register('command', 'command_cb', function(e)
    -- Parse the command arguments
    local command_args = e.command:lower():args()
    if table.contains({ '/targetlines' }, command_args[1]) then
        local command = command_args[2];
        local option = command_args[3];

        if (command == 'persistentmob' or command == 'pmob') then
            -- Stored as its opposite: mobBrief is true when mob lines are not persistent
            if (option == 'on') then
                s.mobBrief = false;
            elseif (option == 'off') then
                s.mobBrief = true;
            elseif (option == nil) then
                s.mobBrief = not s.mobBrief;
            else
                print(chat.header(addon.name) .. chat.error('Unknown option. Use: /targetlines persistentmob [on|off]'));
                e.blocked = true;
                return;
            end
            settings.save();
            print(chat.header(addon.name) .. chat.message('Persistent mob lines: ') .. chat.success(s.mobBrief and 'off (shown briefly on a new target)' or 'on'));
        elseif (command == 'threatmode' or command == 't') then
            if (option == 'new') then
                s.mobThreat = true;
            elseif (option == 'old') then
                s.mobThreat = false;
            elseif (option == nil) then
                s.mobThreat = not s.mobThreat;
            else
                print(chat.header(addon.name) .. chat.error('Unknown option. Use: /targetlines threatmode [old|new]'));
                e.blocked = true;
                return;
            end
            settings.save();
            print(chat.header(addon.name) .. chat.message('Threat mode: ') .. chat.success(s.mobThreat and 'new (follows the mob\'s target while engaged)' or 'old (mob actions only)'));
        elseif (command == 'petline' or command == 'pl') then
            if (option == 'on') then
                s.petLine = true;
            elseif (option == 'off') then
                s.petLine = false;
            elseif (option == nil) then
                s.petLine = not s.petLine;
            else
                print(chat.header(addon.name) .. chat.error('Unknown option. Use: /targetlines petline [on|off]'));
                e.blocked = true;
                return;
            end
            settings.save();
            print(chat.header(addon.name) .. chat.message('Pet line: ') .. chat.success(s.petLine and 'on' or 'off'));
        elseif (command == 'sound' or command == 's') then
            if (option == 'on') then
                s.aggroSound = true;
            elseif (option == 'off') then
                s.aggroSound = false;
            elseif (option == nil) then
                s.aggroSound = not s.aggroSound;
            else
                print(chat.header(addon.name) .. chat.error('Unknown option. Use: /targetlines sound [on|off]'));
                e.blocked = true;
                return;
            end
            settings.save();
            print(chat.header(addon.name) .. chat.message('Line sound: ') .. chat.success(s.aggroSound and 'on' or 'off'));
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
