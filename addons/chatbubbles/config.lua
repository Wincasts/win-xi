-- The settings: what is kept for each character, made good as it is loaded, and the two tabs of the
-- settings window, drawn in winxi's style. The window, the command and the saving are winxi.shell's,
-- which chatbubbles.lua makes with what is here.
--
--   config.Defaults()                 the settings a new character starts with
--   config.Settle(options)            the settings have been loaded: each made good, and kept here
--   config.Attach(app)                the shell's app, for saving and the settings window
--   config.options                    the settings as they are: another table after a change of character
--   config.preview                    whether a sample bubble is shown over the player, while the settings are open
--   config.Enabled(), config.SetEnabled(on)
--   config.Allows(mode)               whether a player chat packet mode makes bubbles
--   config.AllowsNpc(mode)            whether an NPC text channel does
--   config.Toggle()                   opens or closes the settings
--   config.Preset(white), config.Parchment()   the three presets
--   config.DrawAppearance(options)    the Appearance tab
--   config.DrawModes(options)         the Chat Modes tab
local imgui = require('imgui');
local widgets = require('winxi.widgets');
local modes = require('modes');
local skin = require('skin');

local config = { options = nil, preview = { false }, app = nil };

function config.Defaults()
    local channels = T{ };
    for _, mode in ipairs(modes.All) do channels[mode.key] = T{ mode.default == true }; end
    return T{ enabled = T{ true }, modes = channels, appearance = T{
        background = T{ 1, 1, 1, 0.96 }, text = T{ 0.05, 0.05, 0.05, 1 },
        gameTextColors = T{ true },
        onScreen = T{ false }, -- drawn on the screen over everything, not in the world
        skin = T{ 'plain' },   -- one of skin.Keys: the rounded rectangle, or the parchment
        skinTop = T{ unpack(skin.Top) }, skinBottom = T{ unpack(skin.Bottom) }, -- the parchment's gradient
        border = T{ 'none' },  -- one of skin.Borders' keys
        borderColor = T{ 1, 1, 1, 1 }, -- the art's tint, or the plain line's colour
        font = '',             -- a file of C:\Windows\Fonts, or '' for the font everything else is in
        fontSize = T{ 0 },     -- pixels, or 0 for the size everything else is
        padding = T{ 10 },     -- pixels round the text
        arrow = T{ true },     -- the click-through arrow on an NPC's line that waits for a key
    } };
end

-- Each setting a file may have otherwise is made its default, and a number kept within its bounds
function config.Settle(options)
    local base = config.Defaults();
    if (type(options.enabled) ~= 'table' or type(options.enabled[1]) ~= 'boolean') then options.enabled = base.enabled; end
    if (type(options.modes) ~= 'table') then options.modes = base.modes; end
    for _, mode in ipairs(modes.All) do
        local value = options.modes[mode.key];
        if (type(value) ~= 'table' or type(value[1]) ~= 'boolean') then options.modes[mode.key] = base.modes[mode.key]; end
    end
    if (type(options.appearance) ~= 'table') then options.appearance = base.appearance; end
    local appearance = options.appearance;
    for _, key in ipairs({ 'gameTextColors', 'onScreen', 'arrow' }) do
        local switch = appearance[key];
        if (type(switch) ~= 'table' or type(switch[1]) ~= 'boolean') then appearance[key] = base.appearance[key]; end
    end
    if (type(appearance.skin) ~= 'table' or skin.Labels[appearance.skin[1]] == nil) then appearance.skin = base.appearance.skin; end
    if (type(appearance.border) ~= 'table' or skin.BorderLabels[appearance.border[1]] == nil) then appearance.border = base.appearance.border; end
    -- the font was a table of one up to 0.93; it is a string, as widgets.FontFile keeps one
    if (type(appearance.font) == 'table') then appearance.font = appearance.font[1]; end
    if (type(appearance.font) ~= 'string') then appearance.font = base.appearance.font; end
    for _, number in ipairs({ { 'fontSize', 0, 72 }, { 'padding', 0, 40 } }) do
        local key, value = number[1], appearance[number[1]];
        if (type(value) ~= 'table' or type(value[1]) ~= 'number' or value[1] ~= value[1]) then value = base.appearance[key]; appearance[key] = value; end
        value[1] = math.max(number[2], math.min(number[3], math.floor(value[1])));
    end
    for _, key in ipairs({ 'background', 'text', 'skinTop', 'skinBottom', 'borderColor' }) do
        local color = appearance[key];
        if (type(color) ~= 'table') then color = base.appearance[key]; end
        for i = 1, 4 do
            local value = color[i];
            color[i] = type(value) == 'number' and value == value and math.max(0, math.min(1, value)) or base.appearance[key][i];
        end
        appearance[key] = color;
    end
    config.options = options;
    return options;
end

function config.Attach(app)
    config.app = app;
end

local function Save()
    if (config.app ~= nil) then config.app:Save(); end
end
config.Save = Save;

function config.Enabled() return config.options.enabled[1]; end
function config.SetEnabled(value) config.options.enabled[1] = value; Save(); end
function config.Allows(mode)
    local value = config.options.modes[tostring(mode)];
    return value ~= nil and value[1] == true;
end
function config.AllowsNpc(mode)
    local value = config.options.modes['npc:' .. tostring(mode)];
    return value ~= nil and value[1] == true;
end
function config.Toggle()
    if (config.app ~= nil) then config.app:ToggleConfig(); end
end

-- The presets: white or dark bubbles, plain, or the parchment with its own colours and dark text
function config.Preset(white)
    local appearance = config.options.appearance;
    local bg = white and { 1, 1, 1, 0.96 } or { 0.08, 0.09, 0.12, 0.92 };
    local text = white and { 0.05, 0.05, 0.05, 1 } or { 1, 1, 1, 1 };
    for i = 1, 4 do
        appearance.background[i] = bg[i];
        appearance.text[i] = text[i];
    end
    appearance.skin[1] = 'plain';
    appearance.border[1] = 'none';
    Save();
end

function config.Parchment()
    local appearance = config.options.appearance;
    for i = 1, 4 do
        appearance.skinTop[i], appearance.skinBottom[i], appearance.text[i] = skin.Top[i], skin.Bottom[i], skin.Text[i];
        appearance.borderColor[i] = 1;
    end
    appearance.skin[1] = 'parchment';
    appearance.border[1] = 'ffxi';
    Save();
end

-- The rows: each setting is one described row (winxi.widgets), its name, a sentence under it, and the
-- control at the right. A colour, a dropdown and a checkbox are saved as they change; a slider when it
-- is let go. The spec tables are made once here, never a new one per frame.
local function Checkbox(name, sentence, id, value, spec)
    local changed = widgets.Check(name, sentence, value, id, spec);
    if (changed) then Save(); end
    return changed;
end

-- A colour is saved once the mouse is up after a change: a picker's popup is not the swatch that opened it
local colourChanged = false;

local function Colour(name, sentence, id, value)
    if (widgets.Color(name, sentence, value, id)) then colourChanged = true; end
end

local function SaveColours()
    if (colourChanged and not imgui.IsMouseDown(0)) then
        colourChanged = false;
        Save();
    end
end

-- One of choices ({ key, label } each, or plain keys) as a dropdown, value[1] the chosen key
local function Choice(name, sentence, id, value, choices)
    local chosen = widgets.Dropdown(name, sentence, choices, value[1], id);
    if (chosen ~= nil) then
        value[1] = chosen;
        Save();
    end
end

local fontSpec = { theme = 'Default', description = 'The font the bubbles are written in.' };
local sizeSpec = { theme = 'Default Size', max = 72, description = 'How big the text is.' };

function config.DrawAppearance(options)
    local appearance = options.appearance;
    if (widgets.Header('Bubbles', true)) then
        Checkbox('Show Bubbles', 'Shows a bubble over whoever speaks. /chatbubbles on and off switch it too.', '##chatbubbles.enabled', options.enabled);
        widgets.Check('Preview', 'Shows a sample bubble over you while this window is open.', config.preview, '##chatbubbles.preview');
    end
    if (widgets.Header('Presets')) then
        if (widgets.Action('White', 'White bubbles with dark text and no border.', 'Apply##chatbubbles.preset.white')) then config.Preset(true); end
        if (widgets.Action('Dark', 'Dark bubbles with white text and no border.', 'Apply##chatbubbles.preset.dark')) then config.Preset(false); end
        if (widgets.Action('Parchment', 'Parchment bubbles with the FFXI-inspired border and dark text.', 'Apply##chatbubbles.preset.parchment')) then config.Parchment(); end
    end
    if (widgets.Header('Skin')) then
        Choice('Skin', 'Plain is one colour. Parchment shades from Skin Top to Skin Bottom.', '##chatbubbles.skin', appearance.skin, skin.Keys);
        if (appearance.skin[1] == 'parchment') then
            Colour('Skin Top', 'The parchment\'s colour at the top of the bubble.', '##chatbubbles.skinTop', appearance.skinTop);
            Colour('Skin Bottom', 'Its colour at the bottom of the bubble.', '##chatbubbles.skinBottom', appearance.skinBottom);
        else
            Colour('Background', 'The plain skin\'s colour.', '##chatbubbles.background', appearance.background);
        end
        Choice('Border', 'A Winxi Theme border round the bubble, a thin line, or none.', '##chatbubbles.border', appearance.border, skin.Borders);
        if (appearance.border[1] ~= 'none') then
            Colour('Border Colour', 'The tint on the border art, white for the art as it is, or the plain line\'s colour.', '##chatbubbles.borderColor', appearance.borderColor);
        end
    end
    if (widgets.Header('Text')) then
        Checkbox('Match Game Text Colours', 'Writes the text in the colour the game gives that channel.', '##chatbubbles.gameTextColors', appearance.gameTextColors);
        Colour('Text Colour', 'The text\'s colour when the game\'s colours are not matched.', '##chatbubbles.text', appearance.text);
        if (widgets.FontFile(appearance, 'font', '##chatbubbles.font', fontSpec)) then Save(); end
        local _, done = widgets.FontSize(appearance, 'fontSize', '##chatbubbles.fontSize', sizeSpec);
        if (done) then Save(); end
        local _, let = widgets.Slider('Padding', 'The room between the text and the bubble\'s edge.', appearance.padding, 0, 40, '##chatbubbles.padding', widgets.Pixels);
        if (let) then Save(); end
    end
    if (widgets.Header('Behaviour')) then
        Checkbox('Click-Through Arrow', 'A small flashing arrow on an NPC line that waits for a key.', '##chatbubbles.arrow', appearance.arrow);
        Checkbox('Draw On Screen', 'Draws the bubbles over everything on the screen, at one size. Off, they sit in the world, where walls hide them.', '##chatbubbles.onScreen', appearance.onScreen);
    end
    SaveColours();
end

-- The Chat Modes tab: a row for each channel, from modes.lua, the player chat ones under the
-- sub-section their group names
local modeIds = {}; -- key -> the control's id, made once

local function ModeRow(options, mode)
    local id = modeIds[mode.key];
    if (id == nil) then
        id = ('##chatbubbles.mode.%s'):format(mode.key);
        modeIds[mode.key] = id;
    end
    Checkbox(mode.label, mode.sentence, id, options.modes[mode.key]);
end

local function SetAll(options, on)
    for _, mode in ipairs(modes.All) do options.modes[mode.key][1] = on; end
    Save();
end

function config.DrawModes(options)
    if (widgets.Header('Channels', true)) then
        if (widgets.Action('Enable All', 'Turns on bubbles for every channel.', 'Enable##chatbubbles.modes.all')) then SetAll(options, true); end
        if (widgets.Action('Disable All', 'Turns off bubbles for every channel.', 'Disable##chatbubbles.modes.none')) then SetAll(options, false); end
    end
    if (widgets.Header('Player Chat')) then
        for _, group in ipairs(modes.Groups) do
            if (widgets.SubHeader(group, false, group == 'Unknown')) then -- the unknown ones collapsed to start
                for _, mode in ipairs(modes.All) do
                    if (mode.source == nil and mode.group == group) then ModeRow(options, mode); end
                end
            end
        end
        widgets.EndSub();
    end
    if (widgets.Header('NPC Text')) then
        for _, mode in ipairs(modes.All) do
            if (mode.source == 'text') then ModeRow(options, mode); end
        end
    end
end

return config;
