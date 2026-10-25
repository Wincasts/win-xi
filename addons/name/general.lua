-- The General tab: whether Name draws the names, and a premade look to start from. Each part a
-- name has (health bars, cast bars, check details, statuses) is turned on or off in its own tab.
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
local tips = require('winxi.tips');

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

local PLAYER = '[party: space=2][icons: space=4][name]';
local NPC = '[vendor: space=4][name]';
general.Presets = {
    { key = 'default', label = 'Default', help = tips.Get('name.presets.default'),
        values = { nameFormat = PLAYER, monsterFormat = '[aggro] [name] [letters]', npcFormat = NPC,
            showHealthBar = false, healthBarsCombatOnly = false, showStatuses = true, showCheckDetails = true } },
    { key = 'minimal', label = 'Minimal', help = tips.Get('name.presets.minimal'),
        values = { nameFormat = '[name]', monsterFormat = '[name]', npcFormat = '[name]',
            showHealthBar = false, healthBarsCombatOnly = false, showStatuses = false, showCheckDetails = false } },
    { key = 'robust', label = 'Robust', help = tips.Get('name.presets.robust'),
        values = { nameFormat = PLAYER, monsterFormat = '[aggro: space=4]Lv [level]. [name] [letters] ([distance: decimals=1]y)', npcFormat = NPC,
            showHealthBar = true, healthBarsCombatOnly = false, showStatuses = true, showCheckDetails = true } },
    { key = 'immersive', label = 'Immersive', help = tips.Get('name.presets.immersive'),
        values = { nameFormat = PLAYER, monsterFormat = '[name]', npcFormat = NPC,
            showHealthBar = true, healthBarsCombatOnly = true, showStatuses = false, showCheckDetails = false } },
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
    controls.BeginLayout('general', 360, 'Enable Name');
    if (controls.Section('General', '##name.generalOptions', true)) then
        if (controls.Checkbox('Enable Name', '##name.drawNames', options.drawNames,
                tips.Get('name.general.custom_names'))) then
            changed = true;
        end
        imgui.BeginDisabled(not general.Drawing(options));
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
        controls.Mark(tips.Get('name.general.preset'));
        imgui.EndDisabled();
    end
    controls.EndSection();
    controls.EndLayout();
    if (changed and save ~= nil) then
        save();
    end
end

return general;
