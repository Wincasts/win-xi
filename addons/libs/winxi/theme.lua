-- winxi.theme: the look shared by every addon that draws with winxi.
--
-- There is one theme for the whole client: the background, border and text colours, the padding, and
-- the drop shadow. It is kept in config\addons\winxi\theme.lua. Each addon runs on its own, so they
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
    BackgroundColor = { 0.08, 0.08, 0.08, 0.8 },
    BorderColor     = { 0.69, 0.68, 0.78, 1.0 },
    TextColor       = { 1.00, 1.00, 1.00, 1.0 },
    Padding         = 10,  -- space between a window's border and its content, the same on every side
    ShadowEnabled   = false,
    ShadowOffset    = 4,   -- pixels down and to the right
    ShadowBlur      = 6,   -- pixels of soft edge
    ShadowOpacity   = 50,  -- percent
};

local colorKeys = { 'BackgroundColor', 'BorderColor', 'TextColor' };
local numberKeys = { Padding = { 0, theme.MaxPadding }, ShadowOffset = { 0, 20 }, ShadowBlur = { 0, 20 }, ShadowOpacity = { 0, 100 } };

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

    if type(source.ShadowEnabled) == 'boolean' then
        target.ShadowEnabled = source.ShadowEnabled;
    end

    version = version + 1;
end

-- Makes a table an addon has handed over into a whole theme: whatever it already holds is kept (if it
-- is usable), and the rest starts as the shared theme has it, so that leaving the shared theme does
-- not change how anything looks until something is changed.
local function Complete(target)
    local held = {};
    Apply(held, target);

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

    Apply(current, saved);
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
    for _, key in ipairs({ 'Padding', 'ShadowOffset', 'ShadowBlur', 'ShadowOpacity' }) do
        file:write(string.format('    %s = %d,\n', key, math.floor(current[key] + 0.5)));
    end
    file:write(string.format('    ShadowEnabled = %s,\n', tostring(current.ShadowEnabled)));
    file:write('};\n');
    file:close();

    AshitaCore:GetPluginManager():RaiseEvent(eventName, {});
    return true;
end

-- The colours of everything inside a window that is tinted from the border colour: each slot, and how
-- strong the border colour is there (or a colour of its own).
local palette = nil;         -- { slot, colour } for each, made once and recoloured in place
local paletteStrengths = {}; -- by place in the palette; false where the colour is the slot's own
local paletteVersion = -1;

local function BuildPalette()
    if palette == nil then
        -- made here rather than as the file loads, by which point imgui's slots are certain to be defined;
        -- slots this build of imgui does not have are left out
        local slots = {
            { ImGuiCol_Tab,                  0.18 },
            { ImGuiCol_TabHovered,           0.55 },
            { ImGuiCol_TabActive,            0.40 },
            { ImGuiCol_TabUnfocused,         0.18 },
            { ImGuiCol_TabUnfocusedActive,   0.40 },
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
        for _, slot in ipairs(slots) do
            if slot[1] ~= nil then
                local index = #palette + 1;
                palette[index] = { slot[1], slot[3] or { 0, 0, 0, 0 } };
                paletteStrengths[index] = (slot[3] == nil) and slot[2];
            end
        end
    end

    local border = active.BorderColor;
    for index = 1, #palette do
        local strength = paletteStrengths[index];
        if strength then
            local color = palette[index][2];
            color[1], color[2], color[3], color[4] = border[1], border[2], border[3], border[4] * strength;
        end
    end
end

-- A list of { slot, colour } for imgui.PushStyleColor, worked out again only when the theme has changed.
-- The same list and the same colour tables each time: they are recoloured, never replaced.
function theme.Palette()
    if paletteVersion ~= version then
        BuildPalette();
        paletteVersion = version;
    end
    return palette;
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
