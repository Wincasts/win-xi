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

local PLAYER = '[party: space=2][icons: space=4][name]';
local NPC = '[vendor: space=4][name]';
general.Presets = {
    { key = 'default', label = 'Default',
        values = { nameFormat = PLAYER, monsterFormat = '[aggro] [name] [letters]', npcFormat = NPC,
            showHealthBar = false, healthBarsCombatOnly = false, showStatuses = true, showCheckDetails = true } },
    { key = 'minimal', label = 'Minimal',
        values = { nameFormat = '[name]', monsterFormat = '[name]', npcFormat = '[name]',
            showHealthBar = false, healthBarsCombatOnly = false, showStatuses = false, showCheckDetails = false } },
    { key = 'robust', label = 'Robust',
        values = { nameFormat = PLAYER, monsterFormat = '[aggro: space=4]Lv [level]. [name] [letters] ([distance: decimals=1]y)', npcFormat = NPC,
            showHealthBar = true, healthBarsCombatOnly = false, showStatuses = true, showCheckDetails = true } },
    { key = 'immersive', label = 'Immersive',
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

local presets = nil; -- the choices as the dropdown takes them, made once

local function PresetChoices()
    if (presets == nil) then
        presets = {};
        for index, preset in ipairs(general.Presets) do
            presets[index] = { key = preset.key, label = preset.label };
        end
        presets[#presets + 1] = { key = 'custom', label = 'Custom' };
    end
    return presets;
end

local presetSpec = {};

function general.DrawSettings(options, save)
    local changed = false;
    if (controls.Section('General', true)) then
        if (controls.Checkbox('Enable Name', '##name.drawNames', options.drawNames,
                'Draws the names over heads in this addon\'s style. Off, the game draws its own and the other tabs wait.')) then
            changed = true;
        end
        local matching = general.Matching(options);
        presetSpec.parent = options.drawNames;
        local chosen = widgets.Dropdown('Preset',
            'A ready-made look for the formats, bars, statuses and check details, or Custom for none. Font, sizes and colours are kept.',
            PresetChoices(), matching ~= nil and matching.key or 'custom', '##name.preset', presetSpec);
        if (chosen ~= nil and chosen ~= 'custom') then
            changed = general.Apply(options, chosen) or changed;
        end
    end
    if (changed and save ~= nil) then
        save();
    end
end

return general;
