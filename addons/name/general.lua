-- The General tab: a premade look to start from, and the switches for what Name draws.
--
--   general.Defaults(defaults)        what is kept: drawNames
--   general.Drawing(options)          whether Name draws the names, or leaves them to the game and namehook
--   general.Matching(options)         the preset the settings are, or nil where they are none of them
--   general.Apply(options, key)       gives the settings the preset's values
--   general.DrawSettings(options, save)
--
-- A preset sets the formats and the switches below, and nothing else: font, sizes, colours,
-- visibility and the statuses chosen are left as they are.
local imgui = require('imgui');
local widgets = require('winxi.widgets');
local controls = require('controls');

local general = {};

local settings = {
    drawNames = function () return T{ true }; end, -- off: the game draws its names, as namehook sizes them
};

function general.Defaults(defaults)
    for key, make in pairs(settings) do
        defaults[key] = make();
    end
    return defaults;
end

function general.Drawing(options)
    return options.drawNames == nil or options.drawNames[1] ~= false;
end

local PLAYER = '[icons: space=4][name]';
general.Presets = {
    { key = 'default', label = 'Default', help = 'Player icons, enemy aggro and level, status icons and check details; no health bars.',
        values = { nameFormat = PLAYER, monsterFormat = '[aggro] Lv [level]. [name]', npcFormat = '[name]', checkFormat = '',
            showHealthBar = false, healthBarsCombatOnly = false, showStatuses = true, showCheckDetails = true } },
    { key = 'minimal', label = 'Minimal', help = 'Names alone: no icons, levels, bars, statuses or check details.',
        values = { nameFormat = '[name]', monsterFormat = '[name]', npcFormat = '[name]', checkFormat = '',
            showHealthBar = false, healthBarsCombatOnly = false, showStatuses = false, showCheckDetails = false } },
    { key = 'hunter', label = 'Hunter', help = 'Enemy aggro, level and spawn letters, health bars in combat, status icons and check details.',
        values = { nameFormat = PLAYER, monsterFormat = '[aggro: space=4]Lv [level]. [name] [letters]', npcFormat = '[name]', checkFormat = '',
            showHealthBar = true, healthBarsCombatOnly = true, showStatuses = true, showCheckDetails = true } },
    { key = 'retail', label = 'Retail-Like', help = 'As the game writes them: names, with player icons; nothing else.',
        values = { nameFormat = PLAYER, monsterFormat = '[name]', npcFormat = '[name]', checkFormat = '',
            showHealthBar = false, healthBarsCombatOnly = false, showStatuses = false, showCheckDetails = false } },
};

function general.Matching(options)
    for _, preset in ipairs(general.Presets) do
        local same = true;
        for key, value in pairs(preset.values) do
            if (type(options[key]) ~= 'table' or options[key][1] ~= value) then
                same = false;
                break;
            end
        end
        if (same) then
            return preset;
        end
    end
    return nil;
end

function general.Apply(options, key)
    for _, preset in ipairs(general.Presets) do
        if (preset.key == key) then
            for name, value in pairs(preset.values) do
                options[name] = options[name] or T{ };
                options[name][1] = value;
            end
            return true;
        end
    end
    return false;
end

local presetIds = {};

function general.DrawSettings(options, save)
    local changed = false;
    controls.BeginLayout('general', 360, 'Custom Nameplates');
    if (controls.Section('General', '##name.generalOptions', true)) then
        local matching = general.Matching(options);
        widgets.Label('Preset');
        controls.Width();
        if (imgui.BeginCombo('##name.preset', matching ~= nil and matching.label or 'Custom')) then
            for index, preset in ipairs(general.Presets) do
                presetIds[index] = presetIds[index] or (preset.label .. '##name.preset.' .. preset.key);
                if (imgui.Selectable(presetIds[index], preset == matching) and preset ~= matching) then
                    changed = general.Apply(options, preset.key) or changed;
                end
                if (imgui.IsItemHovered()) then
                    imgui.SetTooltip(preset.help);
                end
            end
            imgui.EndCombo();
        end
        controls.Mark('A premade look: it sets the formats, health bars, status icons and check details. Font, sizes, colours, visibility and the chosen statuses are kept. Custom: the settings are none of these.');

        if (controls.Checkbox('Custom Nameplates', '##name.drawNames', options.drawNames,
                'Name draws the names. Off: the game draws its own, as namehook sizes them (/namehook fontsize), unstretched; Visibility still says which are shown. Health bars and status icons are Name\'s and are not drawn while it is off.')) then
            changed = true;
        end
        imgui.BeginDisabled(not general.Drawing(options));
        if (controls.Checkbox('Health Bars', '##name.general.showHealthBar', options.showHealthBar,
                'A bar under each damaged name. Its size and Combat Only are in the Health Bars tab.')) then
            changed = true;
        end
        if (controls.Checkbox('Status Icons', '##name.general.showStatuses', options.showStatuses,
                'The row of status icons over names. Which statuses, their size and their icons are in the Statuses tab.')) then
            changed = true;
        end
        imgui.EndDisabled();
    end
    controls.EndSection();
    controls.EndLayout();
    if (changed and save ~= nil) then
        save();
    end
end

return general;
