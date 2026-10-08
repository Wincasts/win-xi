-- winxi.theme: the look shared by every addon that draws with winxi.
--
-- There is one theme for the whole client: the background, border and text colours, the padding, and
-- the drop shadow. It is kept in config\addons\winxi\theme.lua. Each addon runs on its own, so they
-- cannot share the theme in memory; instead each loads the file, and whichever addon changes it saves
-- the file and raises an event that tells the others to load it again.
--
-- theme.Get() hands back the live theme. Its colour tables are changed in place, never replaced, so they
-- can be given straight to imgui and to colour pickers. After changing anything in it call theme.Touch()
-- (so that what is worked out from it is worked out again) and theme.Save() when the change is final.
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
local current = {};
local version = 0;

local function IsColor(value)
    return type(value) == 'table'
        and type(value[1]) == 'number' and type(value[2]) == 'number'
        and type(value[3]) == 'number' and type(value[4]) == 'number';
end

-- Copies what is usable from source into the live theme, keeping its tables
local function Apply(source)
    for _, key in ipairs(colorKeys) do
        local from = IsColor(source[key]) and source[key] or nil;
        if from then
            local to = current[key];
            if to == nil then
                to = {};
                current[key] = to;
            end
            to[1], to[2], to[3], to[4] = from[1], from[2], from[3], from[4];
        end
    end

    for key, range in pairs(numberKeys) do
        local value = tonumber(source[key]);
        if value then
            current[key] = math.max(range[1], math.min(range[2], value));
        end
    end

    if type(source.ShadowEnabled) == 'boolean' then
        current.ShadowEnabled = source.ShadowEnabled;
    end

    version = version + 1;
end

local function Directory()
    return string.format('%sconfig\\addons\\winxi\\', AshitaCore:GetInstallPath());
end

local function Path()
    return Directory() .. 'theme.lua';
end

-- The live theme
function theme.Get()
    return current;
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
    return current.Padding;
end

-- Puts every value, or just the named ones, back to its default
function theme.Reset(keys)
    if keys == nil then
        Apply(theme.Defaults);
        return;
    end

    local subset = {};
    for _, key in ipairs(keys) do
        subset[key] = theme.Defaults[key];
    end
    Apply(subset);
end

-- Loads the theme file over the live theme. A missing or broken file leaves the theme as it is.
function theme.Load()
    local chunk = loadfile(Path());
    if not chunk then
        return false;
    end

    local ok, saved = pcall(chunk);
    if not ok or type(saved) ~= 'table' then
        return false;
    end

    Apply(saved);
    return true;
end

-- Writes the live theme to its file and tells every other addon using winxi to load it
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
local paletteSlots = nil;
local palette, paletteVersion = nil, -1;

local function BuildPalette()
    if paletteSlots == nil then
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
        paletteSlots = {};
        for _, slot in ipairs(slots) do
            if slot[1] ~= nil then
                paletteSlots[#paletteSlots + 1] = slot;
            end
        end
    end

    local border = current.BorderColor;
    local built = {};
    for _, slot in ipairs(paletteSlots) do
        built[#built + 1] = { slot[1], slot[3] or { border[1], border[2], border[3], border[4] * slot[2] } };
    end
    return built;
end

-- A list of { slot, colour } for imgui.PushStyleColor, rebuilt only when the theme has changed
function theme.Palette()
    if paletteVersion ~= version then
        palette = BuildPalette();
        paletteVersion = version;
    end
    return palette;
end

-- Start from the defaults, then whatever has been saved, and listen for other addons' changes
Apply(theme.Defaults);
theme.Load();

ashita.events.register('plugin_event', 'winxi_theme_plugin_event', function(e)
    if e.name == eventName then
        theme.Load();
    end
end);

return theme;
