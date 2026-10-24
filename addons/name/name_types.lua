-- Shared name sizes / health bars. Each type had its own bars once: a character's are brought over
-- once, and the per-type tables they were kept in let go of.
local plates = require('winxi.nameplates');
local controls = require('controls');
local tips = require('winxi.tips');
local imgui = require('imgui');
local types = {};
types.List = { 'playerNames', 'enemyNames', 'npcNames' };

function types.Defaults(defaults)
    defaults.sharedHealthBarsVersion = 0;
end

local function number(value, fallback, low, high)
    local n = type(value) == 'table' and value[1] or nil;
    if (type(n) ~= 'number' or n ~= n) then n = fallback; end
    return math.max(low, math.min(high, math.floor(n)));
end

function types.Bounds(options)
    local maximum = number(options.fontSize, 15, 6, 48);
    return maximum, number(options.minSize, 10, 6, maximum);
end

function types.Settle(options)
    local maximum, minimum = types.Bounds(options);
    options.fontSize, options.minSize = T{ maximum }, T{ minimum };
    -- Bars kept for each type (nameTypesVersion 1) become the shared ones: on if any type's were,
    -- the size the first of those had, enemies before players before NPCs, or the enemies' size.
    -- Without them, the shared settings were the bars all along.
    if (options.sharedHealthBarsVersion ~= 1 and options.nameTypesVersion == 1) then
        local enabled, source = false, nil;
        for _, key in ipairs({ 'enemyNames', 'playerNames', 'npcNames' }) do
            local style = options[key];
            if (type(style) == 'table' and type(style.showHealthBar) == 'table' and style.showHealthBar[1] == true) then
                if (not enabled) then source = style; end
                enabled = true;
            end
        end
        source = source or (type(options.enemyNames) == 'table' and options.enemyNames) or {};
        options.showHealthBar = T{ enabled };
        options.healthBarWidth = T{ number(source.healthBarWidth, 60, 12, 300) };
        options.healthBarHeight = T{ number(source.healthBarHeight, 6, 3, 40) };
    end
    options.sharedHealthBarsVersion = 1;
    for _, key in ipairs(types.List) do
        options[key] = nil;
    end
    options.nameTypesVersion = nil;
end

function types.Key(category)
    return category == plates.Category.Monster and 'enemyNames'
        or category == plates.Category.Npc and 'npcNames' or 'playerNames';
end

function types.Draw(options)
    controls.Checkbox('Enabled', '##name.showHealthBar', options.showHealthBar,
        tips.Get('name.health_bars.enabled'));
    imgui.BeginDisabled(not options.showHealthBar[1]);
    controls.Checkbox('Combat Only', '##name.healthBarsCombatOnly', options.healthBarsCombatOnly,
        tips.Get('name.health_bars.combat_only'));
    imgui.EndDisabled();
end

function types.DrawSize(options)
    imgui.BeginDisabled(not options.showHealthBar[1] and not options.showCastBar[1]);
    controls.Input('Bar Width (px)', '##name.healthBarWidth', options.healthBarWidth, 12, 300,
        tips.Get('name.health_bars.width'));
    controls.Input('Bar Height (px)', '##name.healthBarHeight', options.healthBarHeight, 3, 40,
        tips.Get('name.health_bars.height'));
    imgui.EndDisabled();
end

return types;
