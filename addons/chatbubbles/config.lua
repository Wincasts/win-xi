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
local tooltip = require('winxi.tooltip');
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

-- The controls, each named on the left in line with winxi's, with a mark at its end that says what it
-- is for when hovered
local function Mark(text)
    imgui.SameLine();
    imgui.TextDisabled('(?)');
    tooltip.Hover(text);
end

local function Checkbox(label, id, value, help)
    widgets.Label(label);
    local changed = imgui.Checkbox(id, value);
    if (changed) then Save(); end
    Mark(help);
    return changed;
end

local function Colour(label, id, value, help)
    widgets.Label(label);
    widgets.PushControlWidth();
    imgui.ColorEdit4(id, value);
    widgets.PopControlWidth();
    if (imgui.IsItemDeactivatedAfterEdit()) then Save(); end
    Mark(help);
end

local function Number(label, id, value, low, high, help)
    widgets.Label(label);
    imgui.SetNextItemWidth(widgets.NumberWidth(1, 3));
    if (imgui.InputInt(id, value)) then
        value[1] = math.max(low, math.min(high, value[1]));
        Save();
    end
    Mark(help);
end

-- One of choices ({ key, label } each, or keys with labels apart) as a dropdown, value[1] the chosen key
local function Choice(label, id, value, choices, labels, help)
    widgets.Label(label);
    widgets.PushControlWidth();
    if (imgui.BeginCombo(id, labels[value[1]] or value[1])) then
        for _, choice in ipairs(choices) do
            local key = type(choice) == 'table' and choice.key or choice;
            if (imgui.Selectable((labels[key] or key) .. id .. '.' .. key, value[1] == key) and value[1] ~= key) then
                value[1] = key;
                Save();
            end
        end
        imgui.EndCombo();
    end
    widgets.PopControlWidth();
    Mark(help);
end

function config.DrawAppearance(options)
    local appearance = options.appearance;
    widgets.BeginLabels('chatbubbles.appearance');
    if (widgets.Header('Bubbles', true)) then
        Checkbox('Enable Bubbles', '##chatbubbles.enabled', options.enabled, 'Whether any bubble is drawn. Off clears those there are.');
        widgets.Label('Preset');
        if (imgui.Button('White##chatbubbles.preset.white')) then config.Preset(true); end
        imgui.SameLine();
        if (imgui.Button('Dark##chatbubbles.preset.dark')) then config.Preset(false); end
        imgui.SameLine();
        if (imgui.Button('Parchment##chatbubbles.preset.parchment')) then config.Parchment(); end
        Mark('A premade look: White and Dark are the plain skin in those colours with no border; Parchment is the parchment skin with the FFXI-inspired border and dark text. Font, size, padding and the channels are left as they are.');
        widgets.Label('Preview');
        if (imgui.Button((config.preview[1] and 'Stop Preview' or 'Preview') .. '##chatbubbles.preview')) then config.preview[1] = not config.preview[1]; end
        Mark('A sample bubble over your character while these settings are open, drawn as they say, with the click-through arrow if it is on. It goes with the settings window.');
    end
    if (widgets.Header('Skin')) then
        Choice('Skin', '##chatbubbles.skin', appearance.skin, skin.Keys, skin.Labels,
            'Plain is a rounded rectangle in the Background colour. Parchment is winxi\'s FFXI-inspired window look round the bubble, lighter: a gradient from Skin Top to Skin Bottom with the fine dark lines over it.');
        if (appearance.skin[1] == 'parchment') then
            Colour('Skin Top', '##chatbubbles.skinTop', appearance.skinTop, 'The parchment\'s colour at the top of the bubble.');
            Colour('Skin Bottom', '##chatbubbles.skinBottom', appearance.skinBottom, 'And at the bottom.');
        else
            Colour('Background', '##chatbubbles.background', appearance.background, 'The plain skin\'s colour, opacity and all.');
        end
        Choice('Border', '##chatbubbles.border', appearance.border, skin.Borders, skin.BorderLabels,
            'One of the theme\'s border arts round the bubble, a plain line of a pixel, or none. With either skin.');
        if (appearance.border[1] ~= 'none') then
            Colour('Border Colour', '##chatbubbles.borderColor', appearance.borderColor, 'The art\'s tint (white is the art as it is), or the plain line\'s colour.');
        end
    end
    if (widgets.Header('Text')) then
        Checkbox('Match Game Text Colours', '##chatbubbles.gameTextColors', appearance.gameTextColors,
            'The text in the colour the game gives that chat channel, as FFXI Config > Font Colors has it, changing as it changes. A game colour over a light bubble gets a dark edge.');
        Colour('Text Colour', '##chatbubbles.text', appearance.text,
            'The text\'s colour when the game\'s is not matched, for local tests, or when the game\'s cannot be read. Its opacity applies either way.');
        widgets.PushControlWidth();
        if (widgets.FontFile(appearance, 'font', '##chatbubbles.font', { theme = 'Default',
                tooltip = 'A font of Windows\' own, by its file in C:\\Windows\\Fonts. Default is the font everything else is written in.' })) then Save(); end
        local _, done = widgets.FontSize(appearance, 'fontSize', '##chatbubbles.fontSize', { theme = 'Default Size', max = 72,
            tooltip = 'The text\'s size in pixels. Default Size is the size everything else is.' });
        if (done) then Save(); end
        widgets.PopControlWidth();
        Number('Padding (px)', '##chatbubbles.padding', appearance.padding, 0, 40, 'The room between the text and the bubble\'s edge.');
    end
    if (widgets.Header('Behaviour')) then
        Checkbox('Click-Through Arrow', '##chatbubbles.arrow', appearance.arrow,
            'A small arrow in the bubble\'s bottom right, flashing as the game\'s dialogue cursor does, on an NPC\'s line that waits for you to press a key. The bubble stays while it waits.');
        Checkbox('Draw On Screen', '##chatbubbles.onScreen', appearance.onScreen,
            'Off: bubbles are drawn in the world by namehook, where walls and characters in front hide them, as names are. On: over everything on the screen, at one size whatever the distance.');
    end
end

local function DrawModeList(options, source)
    for _, mode in ipairs(modes.All) do
        if (mode.source == source) then
            widgets.Label(mode.label);
            if (imgui.Checkbox(('##chatbubbles.mode.%s'):format(mode.key), options.modes[mode.key])) then Save(); end
        end
    end
end

function config.DrawModes(options)
    widgets.BeginLabels('chatbubbles.modes');
    if (widgets.Header('Channels', true)) then
        widgets.Label('All Channels');
        if (imgui.Button('Enable All##chatbubbles.modes.all')) then
            for _, mode in ipairs(modes.All) do options.modes[mode.key][1] = true; end
            Save();
        end
        imgui.SameLine();
        if (imgui.Button('Disable All##chatbubbles.modes.none')) then
            for _, mode in ipairs(modes.All) do options.modes[mode.key][1] = false; end
            Save();
        end
        Mark('Only the channels ticked make bubbles. A speaker still needs a name namehook lists. Local tests pass these switches.');
    end
    if (widgets.Header('Player Chat')) then
        imgui.TextWrapped('The game\'s chat packet modes, incoming and outgoing. Say is on to begin with.');
        DrawModeList(options, nil);
    end
    if (widgets.Header('NPC Text')) then
        imgui.TextWrapped('The text channels an NPC\'s words come by, apart from the packet modes above. Dialogue, 150 and 151, is on to begin with; 152 carries prompts and menus as well. Narration with no speaker is skipped.');
        DrawModeList(options, 'text');
    end
end

return config;
