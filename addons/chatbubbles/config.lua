-- Settings/UI boundary: rendering consumes appearance, packet readers consume modes.
local imgui = require('imgui');
local settings = require('settings');
local modes = require('modes');
local skin = require('skin');
local M = { open = { false }, preview = { false } }; -- preview: a sample bubble over the player while the settings are open
local function defaults()
    local channels = T{};
    for _, mode in ipairs(modes.All) do channels[mode.key] = T{ mode.default == true }; end
    return T{ enabled = T{ true }, modes = channels, appearance = T{
        background = T{ 1, 1, 1, 0.96 }, text = T{ 0.05, 0.05, 0.05, 1 },
        gameTextColors = T{ true },
        onScreen = T{ false }, -- drawn on the screen over everything, not in the world
        skin = T{ 'plain' },   -- one of skin.Keys: the rounded rectangle, or the parchment
        skinTop = T{ unpack(skin.Top) }, skinBottom = T{ unpack(skin.Bottom) }, -- the parchment's gradient
        border = T{ 'none' },  -- one of skin.Borders' keys
        borderColor = T{ 1, 1, 1, 1 }, -- the art's tint, or the plain line's colour
        font = T{ '' },        -- a file of C:\Windows\Fonts, or '' for the font everything else is in
        fontSize = T{ 0 },     -- pixels, or 0 for the size everything else is
        padding = T{ 10 },     -- pixels round the text
        arrow = T{ true },     -- the click-through arrow on an NPC's line that waits for a key
    } };
end
local function settle(options)
    local base = defaults();
    if (type(options) ~= 'table') then options = base; end
    if (type(options.enabled) ~= 'table' or type(options.enabled[1]) ~= 'boolean') then options.enabled = base.enabled; end
    if (type(options.modes) ~= 'table') then options.modes = base.modes; end
    for _, mode in ipairs(modes.All) do
        local value = options.modes[mode.key];
        if (type(value) ~= 'table' or type(value[1]) ~= 'boolean') then options.modes[mode.key] = base.modes[mode.key]; end
    end
    if (type(options.appearance) ~= 'table') then options.appearance = base.appearance; end
    for _, key in ipairs({ 'gameTextColors', 'onScreen' }) do
        local switch = options.appearance[key];
        if (type(switch) ~= 'table' or type(switch[1]) ~= 'boolean') then
            options.appearance[key] = base.appearance[key];
        end
    end
    local appearance = options.appearance;
    if (type(appearance.skin) ~= 'table' or skin.Labels[appearance.skin[1]] == nil) then appearance.skin = base.appearance.skin; end
    if (type(appearance.border) ~= 'table' or skin.BorderLabels[appearance.border[1]] == nil) then appearance.border = base.appearance.border; end
    if (type(appearance.font) ~= 'table' or type(appearance.font[1]) ~= 'string') then appearance.font = base.appearance.font; end
    if (type(appearance.arrow) ~= 'table' or type(appearance.arrow[1]) ~= 'boolean') then appearance.arrow = base.appearance.arrow; end
    for _, number in ipairs({ { 'fontSize', 0, 72 }, { 'padding', 0, 40 } }) do
        local key, value = number[1], appearance[number[1]];
        if (type(value) ~= 'table' or type(value[1]) ~= 'number' or value[1] ~= value[1]) then value = base.appearance[key]; appearance[key] = value; end
        value[1] = math.max(number[2], math.min(number[3], math.floor(value[1])));
    end
    for _, key in ipairs({ 'background', 'text', 'skinTop', 'skinBottom', 'borderColor' }) do
        local color = options.appearance[key];
        if (type(color) ~= 'table') then color = base.appearance[key]; end
        for i = 1, 4 do
            local value = color[i];
            color[i] = type(value) == 'number' and value == value and math.max(0, math.min(1, value)) or base.appearance[key][i];
        end
        options.appearance[key] = color;
    end
    return options;
end
M.options = settle(settings.load(defaults()));
function M.Save() settings.save(); end
function M.Enabled() return M.options.enabled[1]; end
function M.SetEnabled(value) M.options.enabled[1] = value; M.Save(); end
function M.Allows(mode)
    local value = M.options.modes[tostring(mode)];
    return value ~= nil and value[1] == true;
end
function M.AllowsNpc(mode)
    local value = M.options.modes['npc:' .. tostring(mode)];
    return value ~= nil and value[1] == true;
end
function M.Toggle() M.open[1] = not M.open[1]; end
function M.Preset(white)
    local bg = white and { 1, 1, 1, 0.96 } or { 0.08, 0.09, 0.12, 0.92 };
    local text = white and { 0.05, 0.05, 0.05, 1 } or { 1, 1, 1, 1 };
    for i = 1, 4 do
        M.options.appearance.background[i] = bg[i];
        M.options.appearance.text[i] = text[i];
    end
    M.options.appearance.skin[1] = 'plain';
    M.options.appearance.border[1] = 'none';
    M.Save();
end
-- The parchment skin with its own colours, and dark text
function M.Parchment()
    local appearance = M.options.appearance;
    for i = 1, 4 do
        appearance.skinTop[i], appearance.skinBottom[i], appearance.text[i] = skin.Top[i], skin.Bottom[i], skin.Text[i];
    end
    appearance.skin[1] = 'parchment';
    appearance.border[1] = 'ffxi';
    for i = 1, 4 do appearance.borderColor[i] = 1; end
    M.Save();
end

-- One of choices ({ key, label } each) as a dropdown, value[1] the chosen key; returns whether changed
local function Choice(id, value, choices, labels)
    local changed = false;
    if (imgui.BeginCombo(id, labels[value[1]] or value[1])) then
        for _, choice in ipairs(choices) do
            local key = type(choice) == 'table' and choice.key or choice;
            if (imgui.Selectable((labels[key] or key) .. id .. '.' .. key, value[1] == key) and value[1] ~= key) then
                value[1] = key;
                changed = true;
            end
        end
        imgui.EndCombo();
    end
    return changed;
end
settings.register('settings', 'chatbubbles_config', function(options)
    M.options = settle(options or M.options);
end);
ashita.events.register('unload', 'chatbubbles_save', M.Save);

function M.Draw()
    if (not M.open[1]) then M.preview[1] = false; return; end
    if (imgui.Begin('Chat Bubbles Settings', M.open)) then
        if (imgui.Checkbox('Enable bubbles', M.options.enabled)) then M.Save(); end
        if (imgui.BeginTabBar('##chatbubbles.settings')) then
            if (imgui.BeginTabItem('Appearance')) then
                imgui.Text('Presets');
                if (imgui.Button('White bubbles')) then M.Preset(true); end
                imgui.SameLine();
                if (imgui.Button('Dark bubbles')) then M.Preset(false); end
                imgui.SameLine();
                if (imgui.Button('Parchment bubbles')) then M.Parchment(); end
                imgui.Separator();
                local appearance = M.options.appearance;
                imgui.Text('Skin');
                imgui.SameLine();
                if (Choice('##chatbubbles.skin', appearance.skin, skin.Keys, skin.Labels)) then M.Save(); end
                imgui.SameLine();
                if (imgui.Button(M.preview[1] and 'Stop Preview' or 'Preview')) then M.preview[1] = not M.preview[1]; end
                if (M.preview[1]) then
                    imgui.TextWrapped('A sample bubble over your character while these settings are open, with the click-through arrow if it is on, drawn as the settings say.');
                end
                if (appearance.skin[1] == 'parchment') then
                    if (imgui.ColorEdit4('Skin Top', appearance.skinTop)) then M.Save(); end
                    if (imgui.ColorEdit4('Skin Bottom', appearance.skinBottom)) then M.Save(); end
                    imgui.TextWrapped('Parchment is winxi\'s FFXI-inspired window look round the bubble: a gradient from Skin Top to Skin Bottom with the fine dark lines over it. Background is the plain skin\'s.');
                else
                    if (imgui.ColorEdit4('Background', appearance.background)) then M.Save(); end
                end
                imgui.Text('Border');
                imgui.SameLine();
                if (Choice('##chatbubbles.border', appearance.border, skin.Borders, skin.BorderLabels)) then M.Save(); end
                if (appearance.border[1] ~= 'none') then
                    if (imgui.ColorEdit4('Border Colour', appearance.borderColor)) then M.Save(); end
                    imgui.TextWrapped('The theme\'s border art round the bubble, tinted Border Colour (white is the art as it is), or a line of a pixel in that colour.');
                end
                imgui.Separator();
                imgui.Text('Font');
                imgui.SameLine();
                local fonts = require('winxi.fonts');
                if (imgui.BeginCombo('##chatbubbles.font', appearance.font[1] ~= '' and appearance.font[1] or 'Default')) then
                    if (imgui.Selectable('Default##chatbubbles.font.', appearance.font[1] == '') and appearance.font[1] ~= '') then
                        appearance.font[1] = '';
                        M.Save();
                    end
                    for _, file in ipairs(fonts.Files()) do
                        if (imgui.Selectable(file .. '##chatbubbles.font.' .. file, appearance.font[1] == file) and appearance.font[1] ~= file) then
                            appearance.font[1] = file;
                            M.Save();
                        end
                    end
                    imgui.EndCombo();
                end
                if (imgui.InputInt('Font Size (px)', appearance.fontSize)) then
                    appearance.fontSize[1] = math.max(0, math.min(72, appearance.fontSize[1]));
                    M.Save();
                end
                if (imgui.InputInt('Padding (px)', appearance.padding)) then
                    appearance.padding[1] = math.max(0, math.min(40, appearance.padding[1]));
                    M.Save();
                end
                imgui.TextWrapped('A font of Windows\' own, by its file in C:\\Windows\\Fonts; Default is the font everything else is written in. A size of 0 is the size everything else is. Padding is the room between the text and the bubble\'s edge.');
                if (imgui.Checkbox('Click-Through Arrow', appearance.arrow)) then M.Save(); end
                imgui.TextWrapped('A small arrow in the bubble\'s bottom right, flashing as the game\'s dialogue cursor does, on an NPC\'s line that waits for you to press a key; the bubble stays while it waits.');
                if (imgui.Checkbox('Match in-game chat text colors', M.options.appearance.gameTextColors)) then M.Save(); end
                if (imgui.ColorEdit4('Text (manual / fallback)', M.options.appearance.text)) then M.Save(); end
                imgui.TextWrapped('Game colors follow FFXI Config > Font Colors and update while bubbles are visible. Manual RGB applies when matching is off, to local tests, or if lookup is unavailable. Text opacity always applies. Game-colored text gets a dark outline on light backgrounds.');
                imgui.Separator();
                if (imgui.Checkbox('Draw On Screen', M.options.appearance.onScreen)) then M.Save(); end
                imgui.TextWrapped('Off: bubbles are drawn in the world by namehook, where walls and characters in front hide them, as names are. On: they are drawn over everything on the screen, at one size whatever the distance, as chatbubbles drew them up to 0.3.');
                imgui.EndTabItem();
            end
            if (imgui.BeginTabItem('Chat Modes')) then
                imgui.TextWrapped('Only enabled modes generate bubbles. NPC text channels are separate from player packet modes; dialogue 150/151 is enabled by default. Speakers still need a namehook anchor. Unattributed narration is skipped.');
                if (imgui.Button('Enable all')) then
                    for _, mode in ipairs(modes.All) do M.options.modes[mode.key][1] = true; end
                    M.Save();
                end
                imgui.SameLine();
                if (imgui.Button('Disable all')) then
                    for _, mode in ipairs(modes.All) do M.options.modes[mode.key][1] = false; end
                    M.Save();
                end
                for _, mode in ipairs(modes.All) do
                    if (imgui.Checkbox(('%02d: %s##chatbubbles.mode.%d'):format(mode.id, mode.label, mode.id), M.options.modes[mode.key])) then M.Save(); end
                end
                imgui.EndTabItem();
            end
            imgui.EndTabBar();
        end
    end
    imgui.End();
end
return M;
