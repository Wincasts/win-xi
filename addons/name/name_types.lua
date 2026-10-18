-- Shared name sizes / health bars. Per-type tables remain legacy migration archives.
local plates = require('winxi.nameplates');
local controls = require('controls');
local imgui = require('imgui');
local types = {};
types.List = { 'playerNames', 'enemyNames', 'npcNames' };

local function fresh()
    return T{ showHealthBar = T{ false },
        healthBarWidth = T{ 60 }, healthBarHeight = T{ 6 } };
end

function types.Defaults(defaults)
    for _, key in ipairs(types.List) do defaults[key] = fresh(); end
    defaults.nameTypesVersion = 0;
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
    local migrate = options.nameTypesVersion ~= 1;
    for _, key in ipairs(types.List) do
        local style = options[key];
        if (type(style) ~= 'table') then style = fresh(); options[key] = style; end
        -- Obsolete per-category sizes must never override the shared General settings.
        style.fontSize, style.minSize = nil, nil;
        if (migrate) then
            -- NPCs had no bars before per-type controls; do not enable a new feature on migration.
            style.showHealthBar = T{ key ~= 'npcNames' and type(options.showHealthBar) == 'table' and options.showHealthBar[1] == true };
            style.healthBarWidth = T{ number(options.healthBarWidth, 60, 12, 300) };
            style.healthBarHeight = T{ number(options.healthBarHeight, 6, 3, 40) };
        end
        style.healthBarWidth = T{ number(style.healthBarWidth, 60, 12, 300) };
        style.healthBarHeight = T{ number(style.healthBarHeight, 6, 3, 40) };
        if (type(style.showHealthBar) ~= 'table' or type(style.showHealthBar[1]) ~= 'boolean') then
            style.showHealthBar = T{ false };
        end
    end
    options.nameTypesVersion = 1;
    if options.sharedHealthBarsVersion ~= 1 then
        local enabled, source = false, options.enemyNames;
        for _, key in ipairs({ 'enemyNames', 'playerNames', 'npcNames' }) do
            if options[key].showHealthBar[1] then
                if not enabled then source = options[key]; end
                enabled = true;
            end
        end
        options.showHealthBar = T{ enabled };
        options.healthBarWidth = T{ source.healthBarWidth[1] };
        options.healthBarHeight = T{ source.healthBarHeight[1] };
        options.sharedHealthBarsVersion = 1;
    end
end

function types.Key(category)
    return category == plates.Category.Monster and 'enemyNames'
        or category == plates.Category.Npc and 'npcNames' or 'playerNames';
end

function types.Get(options, category)
    return options[types.Key(category)]; -- legacy archive; rendering uses shared health-bar settings
end

function types.Maximum(options)
    local maximum = types.Bounds(options);
    return maximum;
end

function types.Draw(options)
    controls.Checkbox('Health Bars', '##name.showHealthBar', options.showHealthBar,
        'One shared health-bar setting for every entity, including pets/trusts and NPCs. Requires valid HP data; full-health entities have no bar.');
    imgui.BeginDisabled(not options.showHealthBar[1]);
    controls.Checkbox('Combat Only', '##name.healthBarsCombatOnly', options.healthBarsCombatOnly,
        'Show bars only for the entity whose status is Engaged (1) and HP is above zero. Being targeted or claimed alone is not combat. Missing status data hides the bar. Applies to every type.');
    controls.Input('Health Bar Width (px)', '##name.healthBarWidth', options.healthBarWidth, 12, 300,
        'Shared width including the border, independent of name size.');
    controls.Input('Health Bar Height (px)', '##name.healthBarHeight', options.healthBarHeight, 3, 40,
        'Shared height including the border, independent of name size.');
    imgui.EndDisabled();
end

return types;
