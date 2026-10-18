-- winxi.theme: the look shared by every addon that draws with winxi.
--
-- There is one theme for the whole client: the background, border and text colours, the padding, the
-- drop shadow, the font every window is written in (winxi.fonts), the dark edge round text written over
-- a bar or the game (winxi.text), and the styles: the window border's art, window titles, its tabs' texture, the bars' texture and their bookends, and
-- the custom status icons (which set, if any). Tooltips (winxi.tooltip) have values of their own, the Tooltip
-- keys, and they are always the shared theme's: theme.Shared().
--
-- It is in two parts, for winxi.window's two kinds of window. Most of it is for the game's windows,
-- what is drawn on the screen as the game is played. A settings window has values of its own, each
-- named for the game window's it stands in place of with Settings before it (theme.SettingsKeys):
-- its colours, padding, font and font size. A settings window has none of the styles, and no shadow.
-- theme.For(key, settingsKind) is the value for either kind. It is kept in config\addons\winxi\theme.lua. Each addon runs on its own, so they
-- cannot share the theme in memory; instead each loads the file, and whichever addon changes it saves
-- the file and raises an event that tells the others to load it again.
--
-- An addon need not follow the shared theme. theme.Configure(useShared, own) says whether this addon
-- does, and gives a table of the addon's own to hold its values when it does not: the same values as
-- the shared theme, kept wherever the addon keeps its settings. Everything that draws asks theme.Get(),
-- so it follows whichever is in use.
--
-- theme.Get() hands back the theme in use. Its colour tables are changed in place, never replaced, so
-- they can be given straight to imgui and to colour pickers. After changing anything in it call
-- theme.Touch() (so that what is worked out from it is worked out again); when the change is final,
-- theme.Save() if it is the shared theme, or the addon's own save if it is the addon's.
local theme = {};

theme.MaxPadding = 40;

theme.Defaults = {
    BackgroundColor = { 0.153, 0.153, 0.263, 0.8 },
    BorderColor     = { 0.47, 0.469, 0.485, 1.0 },
    TextColor       = { 1.00, 1.00, 1.00, 1.0 },
    ThemeTabColor   = { 0.387, 0.274, 0.439, 1.0 }, -- the Winxi Theme tab, set apart from an addon's own tabs
    HighlightColor  = { 0.271, 0.421, 0.814, 0.624 }, -- the chosen tab, and the line under its tab bar
    Padding         = 12,  -- space between a window's border and its content, the same on every side
    ShadowEnabled   = true,
    ShadowOffset    = 2,   -- pixels down and to the right
    ShadowBlur      = 3,   -- pixels of soft edge
    ShadowOpacity   = 30,  -- percent
    BorderOpacity   = 40,  -- percent: a game window's border, plain or art
    FontFile        = '',     -- a font of C:\Windows\Fonts, or '' for imgui's own
    FontSize        = 0,      -- pixels, or 0 for the base size
    TextOutline     = 1,      -- pixels: the dark edge round text written over a bar, an image or the game (winxi.text); 0 for none
    TextOutlineColor = { 0, 0, 0, 0.9 },
    BorderStyle     = 'ffxi',     -- one of theme.BorderStyles: 'theme' is the plain border in BorderColor
    BackgroundStyle = 'ffxi',     -- one of theme.BackgroundStyles: 'plain' is the flat BackgroundColor
    TabStyle        = 'glass',    -- one of theme.TabStyles, over the tabs of a window (winxi.tabs): 'plain' is imgui's own
    BarTexture      = 'chrome',   -- one of theme.BarTextures, for an addon that draws HP and MP bars
    Bookends        = true,       -- a small cap at each end of those bars
    BookendStyle    = 'texture',  -- one of theme.BookendStyles
    BookendOpacity  = 65,         -- percent: how solid those caps are
    StatusIcons     = true,       -- custom icons (winxi.statusicons) for buffs and debuffs, where the set has one
    StatusIconSet   = 'ffxiv',    -- which set: a folder of libs\winxi\statusicons
    FrameTitles     = true,       -- a window's title on its top edge (winxi.titles), for a window that has one
    TitleStyle      = 'break',    -- one of theme.TitleStyles
    TitleColor      = { 0.979, 0.979, 0.979, 1.0 },
    TitleSize       = 14,         -- pixels, or 0 for the window's own size
    TitleFontFile   = 'trebucbi.ttf', -- a font of C:\Windows\Fonts, or '' for the window's own
    TitleOffsetX    = 24,         -- pixels from the window's right edge to the end of the words
    TitleOffsetY    = 0,          -- pixels down from sitting across the top edge; less than 0 is up
    TitleShadow     = true,       -- a soft dark copy of the words, down and to the right of them
    TitleShadowOffset  = 2,       -- pixels
    TitleShadowOpacity = 50,      -- percent
    TitleAllCaps    = false,      -- every title written in capitals

    -- a settings window's own (winxi.window's kinds)
    SettingsBackgroundColor = { 0.155, 0.155, 0.241, 0.8 },
    SettingsBorderColor     = { 0.47, 0.469, 0.485, 1.0 },
    SettingsTextColor       = { 1.00, 1.00, 1.00, 1.0 },
    SettingsHighlightColor  = { 0.271, 0.421, 0.814, 0.624 },
    SettingsHeaderColor     = { 0.469, 0.459, 0.667, 1.0 }, -- the titles of its sections (widgets.Header)
    SettingsPadding         = 10,
    SettingsFontFile        = '',
    SettingsFontSize        = 0,

    -- every tooltip's (winxi.tooltip), over either kind of window
    TooltipsEnabled         = true,
    TooltipDelay            = 0,    -- milliseconds the mouse rests before one shows
    TooltipMaxWidth         = 400,  -- pixels of text before it goes on to another line
    TooltipPadding          = 8,
    TooltipFontSize         = 0,    -- pixels, or 0 for the size of the window it is over
    TooltipBackgroundColor  = { 0.201, 0.205, 0.287, 0.95 },
    TooltipBorderColor      = { 0.69, 0.68, 0.78, 1.0 },
    TooltipTextColor        = { 1.00, 1.00, 1.00, 1.0 },
};

-- A game window's value, and the settings window's own in its place
theme.SettingsKeys = {
    BackgroundColor = 'SettingsBackgroundColor', BorderColor = 'SettingsBorderColor', TextColor = 'SettingsTextColor',
    HighlightColor = 'SettingsHighlightColor', Padding = 'SettingsPadding', FontFile = 'SettingsFontFile', FontSize = 'SettingsFontSize',
};
-- Every value that is a settings window's alone, and every value that is the game windows', for theme.Reset
theme.SettingsWindowKeys = { 'ThemeTabColor', 'SettingsHeaderColor' };
for _, key in pairs(theme.SettingsKeys) do
    theme.SettingsWindowKeys[#theme.SettingsWindowKeys + 1] = key;
end
table.sort(theme.SettingsWindowKeys);
-- The icons' values, which winxisettings has on a tab of their own
theme.IconKeys = { 'StatusIcons', 'StatusIconSet' };
theme.TooltipKeys = {};
for key in pairs(theme.Defaults) do
    if key:find('^Tooltip') then theme.TooltipKeys[#theme.TooltipKeys + 1] = key; end
end
table.sort(theme.TooltipKeys);
theme.GameWindowKeys = {};
do
    local settingsOnly = {};
    for _, key in ipairs(theme.SettingsWindowKeys) do settingsOnly[key] = true; end
    for _, key in ipairs(theme.TooltipKeys) do settingsOnly[key] = true; end
    for key in pairs(theme.Defaults) do
        if not settingsOnly[key] then theme.GameWindowKeys[#theme.GameWindowKeys + 1] = key; end
    end
    table.sort(theme.GameWindowKeys);
end
theme.MaxSettingsPadding = 20;
theme.MaxTitleOffsetX = 300;
theme.MaxTitleOffsetY = 30;
theme.MaxTooltipDelay = 2000;
theme.MaxTooltipPadding = 20;
theme.MinTooltipWidth, theme.MaxTooltipWidth = 150, 1000;

-- The choices of each style, as { key, label }: the key is what is kept
theme.BorderStyles = {
    { key = 'theme', label = 'Theme' }, { key = 'silver', label = 'Brushed Silver' },
    { key = 'bronze', label = 'Bronze' }, { key = 'ffxi', label = 'FFXI-inspired' },
    { key = 'crystal', label = 'Crystal' }, { key = 'royal', label = 'Royal Gold' },
    { key = 'obsidian', label = 'Obsidian' }, { key = 'royal_silver', label = 'Royal Silver' },
    { key = 'royal_platinum', label = 'Royal Platinum' }, { key = 'mythril', label = 'Mythril' },
    { key = 'adaman', label = 'Adaman' }, { key = 'jade', label = 'Jade' }, { key = 'amethyst', label = 'Amethyst' },
};
theme.BackgroundStyles = {
    { key = 'plain', label = 'Plain' }, { key = 'gradient', label = 'Gradient' },
    { key = 'ffxi', label = 'FFXI-inspired' }, { key = 'grain', label = 'Grain' },
    { key = 'marble', label = 'Marble' }, { key = 'weave', label = 'Weave' },
    { key = 'brushed', label = 'Brushed Metal' },
};
theme.TabStyles = {
    { key = 'plain', label = 'Plain' }, { key = 'sheen', label = 'Sheen' }, { key = 'glass', label = 'Glass' },
    { key = 'bevel', label = 'Bevel' }, { key = 'brushed', label = 'Brushed Metal' }, { key = 'grain', label = 'Grain' },
    { key = 'lined', label = 'FFXI-inspired' }, { key = 'satin', label = 'Satin' },
};
theme.BarTextures = {
    { key = 'original', label = 'Original' }, { key = 'glass', label = 'Glass' }, { key = 'detailed', label = 'Detailed' },
    { key = 'crystal', label = 'Crystal' }, { key = 'satin', label = 'Satin' },
    { key = 'runic', label = 'Runic' }, { key = 'classic', label = 'Classic FF' },
    { key = 'radiant', label = 'Radiant (Bright)' }, { key = 'chrome', label = 'Chrome' },
    { key = 'flat', label = 'Flat' }, { key = 'segmented', label = 'Segmented' }, { key = 'ember', label = 'Ember' },
    { key = 'kingdom', label = 'Kingdom' }, { key = 'magitek', label = 'Magitek' },
    { key = 'aether', label = 'Aether' }, { key = 'elven', label = 'Elven' }, { key = 'gothic', label = 'Gothic' },
};
theme.TitleStyles = {
    { key = 'outline', label = 'Outlined Text' }, { key = 'break', label = 'Break In Border' },
    { key = 'breakshadow', label = 'Break With Shadow' }, { key = 'plate', label = 'Plate' },
};
-- after Bar Texture and Match Border, one for each border but the theme's own, by the same key
theme.BookendStyles = { { key = 'texture', label = 'Bar Texture' }, { key = 'match', label = 'Match Border' } };
for index = 2, #theme.BorderStyles do
    theme.BookendStyles[#theme.BookendStyles + 1] = theme.BorderStyles[index];
end

for _, style in ipairs({ 'kingdom', 'magitek', 'aether', 'elven', 'gothic' }) do
    theme.BookendStyles[#theme.BookendStyles + 1] = { key = style, label = style:sub(1, 1):upper() .. style:sub(2) };
end

local colorKeys = { 'BackgroundColor', 'BorderColor', 'TextColor', 'ThemeTabColor', 'HighlightColor', 'TitleColor', 'TextOutlineColor',
    'SettingsBackgroundColor', 'SettingsBorderColor', 'SettingsTextColor', 'SettingsHighlightColor', 'SettingsHeaderColor',
    'TooltipBackgroundColor', 'TooltipBorderColor', 'TooltipTextColor' };
theme.MaxFontSize = 40;
theme.MaxTextOutline = 4;

local numberKeys = { FontSize = { 0, theme.MaxFontSize }, TextOutline = { 0, theme.MaxTextOutline }, Padding = { 0, theme.MaxPadding }, ShadowOffset = { 0, 20 }, ShadowBlur = { 0, 20 }, ShadowOpacity = { 0, 100 }, BorderOpacity = { 0, 100 }, BookendOpacity = { 0, 100 }, TitleSize = { 0, theme.MaxFontSize },
    TitleOffsetX = { -50, theme.MaxTitleOffsetX }, TitleOffsetY = { -theme.MaxTitleOffsetY, theme.MaxTitleOffsetY },
    TitleShadowOffset = { 1, 6 }, TitleShadowOpacity = { 0, 100 },
    SettingsPadding = { 0, theme.MaxSettingsPadding }, SettingsFontSize = { 0, theme.MaxFontSize },
    TooltipDelay = { 0, theme.MaxTooltipDelay }, TooltipMaxWidth = { theme.MinTooltipWidth, theme.MaxTooltipWidth },
    TooltipPadding = { 0, theme.MaxTooltipPadding }, TooltipFontSize = { 0, theme.MaxFontSize } };
local booleanKeys = { 'ShadowEnabled', 'Bookends', 'StatusIcons', 'FrameTitles', 'TitleShadow', 'TitleAllCaps', 'TooltipsEnabled' };
local choiceKeys = { BorderStyle = theme.BorderStyles, BackgroundStyle = theme.BackgroundStyles, TabStyle = theme.TabStyles, BarTexture = theme.BarTextures, BookendStyle = theme.BookendStyles, TitleStyle = theme.TitleStyles };

-- Whether a value is one of a style's choices
local function IsChoice(choices, value)
    for _, choice in ipairs(choices) do
        if choice.key == value then
            return true;
        end
    end
    return false;
end

local eventName = 'winxi_theme_changed';
local current = {};      -- the shared theme
local own = nil;         -- this addon's own theme, if it has given one
local useShared = true;
local active = current;  -- whichever of the two is in use
local version = 0;

local function IsColor(value)
    return type(value) == 'table'
        and type(value[1]) == 'number' and type(value[2]) == 'number'
        and type(value[3]) == 'number' and type(value[4]) == 'number';
end

-- A font file's name alone, not a path; or '' for imgui's own
local function IsFontFile(file)
    return type(file) == 'string' and (file == '' or (file:lower():match('%.ttf$') and not file:find('[\\/]')));
end

-- A theme kept before settings windows had values of their own: they had the game windows' colours
-- and font, and those they keep. Anything else is handed back as it is.
local function Migrated(saved)
    if saved.SettingsBackgroundColor ~= nil or saved.BackgroundColor == nil then
        return saved;
    end
    local moved = {};
    for key, value in pairs(saved) do moved[key] = value; end
    for _, key in ipairs({ 'BackgroundColor', 'BorderColor', 'TextColor', 'HighlightColor', 'FontFile' }) do
        moved[theme.SettingsKeys[key]] = saved[key];
    end
    return moved;
end

-- Copies what is usable from source into a theme, keeping that theme's tables
local function Apply(target, source)
    for _, key in ipairs(colorKeys) do
        local from = IsColor(source[key]) and source[key] or nil;
        if from then
            local to = target[key];
            if type(to) ~= 'table' then
                to = {};
                target[key] = to;
            end
            to[1], to[2], to[3], to[4] = from[1], from[2], from[3], from[4];
        end
    end

    for key, range in pairs(numberKeys) do
        local value = tonumber(source[key]);
        if value then
            target[key] = math.max(range[1], math.min(range[2], value));
        end
    end

    for _, key in ipairs(booleanKeys) do
        if type(source[key]) == 'boolean' then
            target[key] = source[key];
        end
    end

    for key, choices in pairs(choiceKeys) do
        if IsChoice(choices, source[key]) then
            target[key] = source[key];
        end
    end

    for _, key in ipairs({ 'FontFile', 'SettingsFontFile', 'TitleFontFile' }) do
        if IsFontFile(source[key]) then
            target[key] = source[key];
        end
    end

    -- a folder's name, not a path
    local set = source.StatusIconSet;
    if type(set) == 'string' and set ~= '' and not set:find('[\\/:]') then
        target.StatusIconSet = set;
    end

    version = version + 1;
end

-- Makes a table an addon has handed over into a whole theme: whatever it already holds is kept (if it
-- is usable), and the rest starts as the shared theme has it, so that leaving the shared theme does
-- not change how anything looks until something is changed.
local function Complete(target)
    local held = {};
    Apply(held, Migrated(target));

    for key in pairs(target) do
        if theme.Defaults[key] ~= nil then
            target[key] = nil;
        end
    end
    Apply(target, current);
    Apply(target, held);
end

local function Directory()
    return string.format('%sconfig\\addons\\winxi\\', AshitaCore:GetInstallPath());
end

local function Path()
    return Directory() .. 'theme.lua';
end

-- The theme in use: the shared one, or this addon's own
function theme.Get()
    return active;
end

-- The shared theme, whether or not this addon follows it: for what is everyone's alike, the tooltips
function theme.Shared()
    return current;
end

-- Whether this addon follows the shared theme
function theme.IsShared()
    return useShared;
end

-- Says whether this addon follows the shared theme, and gives the table that holds its own values for
-- when it does not. Cheap to call every frame: nothing happens unless one of the two has changed, which
-- matters to an addon whose settings tables are replaced when its settings are loaded again.
-- Without a table of its own an addon always follows the shared theme.
function theme.Configure(shared, ownTheme)
    if type(ownTheme) ~= 'table' then
        ownTheme = nil;
    end
    shared = (shared ~= false) or (ownTheme == nil);

    if shared == useShared and ownTheme == own then
        return;
    end

    if ownTheme ~= nil and ownTheme ~= own then
        Complete(ownTheme);
    end

    own, useShared = ownTheme, shared;
    active = useShared and current or own;
    version = version + 1;
end

-- Goes up whenever the theme changes; for knowing when something worked out from it is out of date
function theme.Version()
    return version;
end

-- Say that the live theme has been changed in place
function theme.Touch()
    version = version + 1;
end

function theme.GetPadding()
    return active.Padding;
end

-- The value of a game window's key (BackgroundColor, Padding and the rest), or the settings window's
-- own in its place
function theme.For(key, settingsKind)
    return active[settingsKind and theme.SettingsKeys[key] or key];
end

-- Puts every value of the theme in use, or just the named ones, back to its default
function theme.Reset(keys)
    if keys == nil then
        Apply(active, theme.Defaults);
        return;
    end

    local subset = {};
    for _, key in ipairs(keys) do
        subset[key] = theme.Defaults[key];
    end
    Apply(active, subset);
end

-- Loads the theme file over the shared theme. A missing or broken file leaves the theme as it is.
function theme.Load()
    local chunk = loadfile(Path());
    if not chunk then
        return false;
    end

    local ok, saved = pcall(chunk);
    if not ok or type(saved) ~= 'table' then
        return false;
    end

    Apply(current, Migrated(saved));
    return true;
end

-- Writes the shared theme to its file and tells every other addon using winxi to load it
function theme.Save()
    local directory = Directory();
    for position = 1, #directory do
        if directory:sub(position, position) == '\\' then
            ashita.fs.create_directory(directory:sub(1, position));
        end
    end

    local file = io.open(Path(), 'w');
    if not file then
        return false;
    end

    file:write('-- The look shared by every addon that draws with winxi. Written by winxi: edit it in game.\n');
    file:write('return {\n');
    for _, key in ipairs(colorKeys) do
        local color = current[key];
        file:write(string.format('    %s = { %f, %f, %f, %f },\n', key, color[1], color[2], color[3], color[4]));
    end
    for _, key in ipairs({ 'FontSize', 'TextOutline', 'Padding', 'ShadowOffset', 'ShadowBlur', 'ShadowOpacity', 'BorderOpacity', 'BookendOpacity', 'TitleSize', 'TitleOffsetX', 'TitleOffsetY', 'TitleShadowOffset', 'TitleShadowOpacity', 'SettingsPadding', 'SettingsFontSize', 'TooltipDelay', 'TooltipMaxWidth', 'TooltipPadding', 'TooltipFontSize' }) do
        file:write(string.format('    %s = %d,\n', key, math.floor(current[key] + 0.5)));
    end
    for _, key in ipairs(booleanKeys) do
        file:write(string.format('    %s = %s,\n', key, tostring(current[key])));
    end
    for _, key in ipairs({ 'FontFile', 'SettingsFontFile', 'TitleFontFile', 'BorderStyle', 'BackgroundStyle', 'TabStyle', 'BarTexture', 'BookendStyle', 'TitleStyle', 'StatusIconSet' }) do
        file:write(string.format('    %s = %q,\n', key, current[key]));
    end
    file:write('};\n');
    file:close();

    AshitaCore:GetPluginManager():RaiseEvent(eventName, {});
    return true;
end

-- The colours of everything inside a window that is tinted from the border colour: each slot, and how
-- strong the border colour is there (or a colour of its own, or the theme colour of that name).
-- There are two: a game window's, from its colours, and a settings window's, from its own.
local palettes = {};          -- kind ('game' or 'settings') -> { slot, colour } for each, made once and recoloured in place
local paletteStrengths = {};  -- by place in the palette; false where the colour is the slot's own
local paletteKeys = {};       -- by place in the palette: the theme colour it is, where it is one
local paletteVersions = {};   -- kind -> the theme's version it was coloured for

local function BuildPalette(kind)
    local palette = palettes[kind];
    if palette == nil then
        -- made here rather than as the file loads, by which point imgui's slots are certain to be defined;
        -- slots this build of imgui does not have are left out
        local slots = {
            { ImGuiCol_Tab,                  0.18 },
            { ImGuiCol_TabHovered,           0.55 },
            -- the chosen tab: imgui draws the line under the tab bar in the same colour. Named as imgui
            -- 1.90.9 and later name them (Ashita's is 1.92), or as before that.
            { ImGuiCol_TabSelected or ImGuiCol_TabActive,                0.40, 'HighlightColor' },
            { ImGuiCol_TabSelectedOverline,                              0.40, 'HighlightColor' },
            { ImGuiCol_TabDimmed or ImGuiCol_TabUnfocused,               0.18 },
            { ImGuiCol_TabDimmedSelected or ImGuiCol_TabUnfocusedActive, 0.40, 'HighlightColor' },
            { ImGuiCol_TabDimmedSelectedOverline,                        0.40, 'HighlightColor' },
            { ImGuiCol_Separator,            0.50 },
            { ImGuiCol_TableHeaderBg,        0.22 },
            { ImGuiCol_TableBorderStrong,    0.60 },
            { ImGuiCol_TableBorderLight,     0.30 },
            { ImGuiCol_TableRowBg,           0.00 },
            { ImGuiCol_TableRowBgAlt,        0.00, { 1.00, 1.00, 1.00, 0.04 } },
            { ImGuiCol_Button,               0.25 },
            { ImGuiCol_ButtonHovered,        0.45 },
            { ImGuiCol_ButtonActive,         0.60 },
            { ImGuiCol_FrameBg,              0.15 },
            { ImGuiCol_FrameBgHovered,       0.30 },
            { ImGuiCol_FrameBgActive,        0.42 },
            { ImGuiCol_CheckMark,            1.00 },
            { ImGuiCol_SliderGrab,           0.60 },
            { ImGuiCol_SliderGrabActive,     0.90 },
            { ImGuiCol_TitleBg,              0.20 },
            { ImGuiCol_TitleBgActive,        0.32 },
            { ImGuiCol_TitleBgCollapsed,     0.15 },
            { ImGuiCol_TextSelectedBg,       0.35 },
            { ImGuiCol_Header,               0.25 },
            { ImGuiCol_HeaderHovered,        0.38 },
            { ImGuiCol_HeaderActive,         0.50 },
            { ImGuiCol_ScrollbarBg,          0.00 },
            { ImGuiCol_ScrollbarGrab,        0.40 },
            { ImGuiCol_ScrollbarGrabHovered, 0.60 },
            { ImGuiCol_ScrollbarGrabActive,  0.80 },
        };
        palette = {};
        palettes[kind] = palette;
        for _, slot in ipairs(slots) do
            if slot[1] ~= nil then
                local index = #palette + 1;
                local fixed = type(slot[3]) == 'table' and slot[3] or nil;
                palette[index] = { slot[1], fixed or { 0, 0, 0, 0 } };
                paletteStrengths[index] = (fixed == nil) and slot[2];
                paletteKeys[index] = type(slot[3]) == 'string' and slot[3] or nil;
            end
        end
    end

    local settingsKind = kind == 'settings';
    local border = theme.For('BorderColor', settingsKind);
    for index = 1, #palette do
        local strength, key = paletteStrengths[index], paletteKeys[index];
        local color = palette[index][2];
        if key then
            local from = theme.For(key, settingsKind);
            color[1], color[2], color[3], color[4] = from[1], from[2], from[3], from[4];
        elseif strength then
            color[1], color[2], color[3], color[4] = border[1], border[2], border[3], border[4] * strength;
        end
    end
end

-- The border colour of a game window: BorderColor, faded by BorderOpacity. The same table each time,
-- recoloured only when the theme has changed.
local gameBorder, gameBorderVersion = { 0, 0, 0, 0 }, -1;
function theme.GameBorderColor()
    if gameBorderVersion ~= version then
        local border = active.BorderColor;
        gameBorder[1], gameBorder[2], gameBorder[3] = border[1], border[2], border[3];
        gameBorder[4] = border[4] * (tonumber(active.BorderOpacity) or 100) / 100;
        gameBorderVersion = version;
    end
    return gameBorder;
end

-- A list of { slot, colour } for imgui.PushStyleColor, worked out again only when the theme has changed:
-- a game window's, or with settingsKind true a settings window's. The same list and the same colour
-- tables each time: they are recoloured, never replaced.
function theme.Palette(settingsKind)
    local kind = settingsKind and 'settings' or 'game';
    if paletteVersions[kind] ~= version then
        BuildPalette(kind);
        paletteVersions[kind] = version;
    end
    return palettes[kind];
end

-- Start from the defaults, then whatever has been saved, and listen for other addons' changes
Apply(current, theme.Defaults);
theme.Load();

ashita.events.register('plugin_event', 'winxi_theme_plugin_event', function(e)
    if e.name == eventName then
        theme.Load();
    end
end);

return theme;
