-- The look shared with the xitools windows: their dark background, pale border and padding, with the
-- tabs, tables, buttons, inputs and so on tinted from the border colour. xitools runs as a separate
-- addon, so its settings cannot be read from here: the background and border are this addon's own
-- settings (Appearance tab), and these are what they start as, which are the xitools defaults.
local style = {
    Background = { 0.08, 0.08, 0.08, 0.8 },
    Border     = { 0.69, 0.68, 0.78, 1.0 },
    Text       = { 1.00, 1.00, 1.00, 1.0 },
    Padding    = { 10, 10 },   -- the padding of the window last pushed for; set by style.Push
    DefaultPadding = 10,
    MaxPadding = 40,
};

-- The padding chosen in the settings (Appearance tab): the space between a window's border and its
-- content, the same on every side
function style.GetPadding()
    local chosen = gSettings and tonumber(gSettings.Padding) or style.DefaultPadding;
    return math.max(0, math.min(style.MaxPadding, chosen));
end

local function IsColor(value)
    return type(value) == 'table' and value[1] and value[2] and value[3] and value[4];
end

-- The colours chosen in the settings, or the defaults above where there are none
local function GetBackground()
    local chosen = gSettings and gSettings.BackgroundColor;
    return IsColor(chosen) and chosen or style.Background;
end

local function GetBorder()
    local chosen = gSettings and gSettings.BorderColor;
    return IsColor(chosen) and chosen or style.Border;
end

-- Each colour slot and how strong the border colour is there, or a colour of its own
local function BuildPalette(border)
    local entries = {
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
        { ImGuiCol_Border,               1.00 },
        { ImGuiCol_Text,                 0.00, style.Text },
    };

    -- slots this build of imgui does not have are left out
    local palette = {};
    for _, entry in ipairs(entries) do
        if entry[1] ~= nil then
            palette[#palette + 1] = { entry[1], entry[3] or { border[1], border[2], border[3], border[4] * entry[2] } };
        end
    end
    return palette;
end

-- Built the first time it is needed, by which point imgui's colour slots are certain to be defined,
-- and again whenever the border colour is changed
local palette = nil;
local paletteBorder = { nil, nil, nil, nil };

-- Flags for a window with no title bar that still sizes itself and scrolls
function style.WindowFlags()
    return bit.bor(
        ImGuiWindowFlags_NoTitleBar,
        ImGuiWindowFlags_NoResize,
        ImGuiWindowFlags_NoCollapse,
        ImGuiWindowFlags_AlwaysAutoResize);
end

-- Call before a window's Begin, and style.Pop after its End.
-- The info bar and detail view take the padding chosen in the settings. The settings windows pass
-- fixedPadding, and keep the default: the padding slider must not squeeze the window it is in.
function style.Push(fixedPadding)
    local padding = fixedPadding and style.DefaultPadding or style.GetPadding();
    style.Padding[1], style.Padding[2] = padding, padding;

    local border = GetBorder();
    local was = paletteBorder;
    if palette == nil or was[1] ~= border[1] or was[2] ~= border[2] or was[3] ~= border[3] or was[4] ~= border[4] then
        palette = BuildPalette(border);
        was[1], was[2], was[3], was[4] = border[1], border[2], border[3], border[4];
    end

    for _, entry in ipairs(palette) do
        imgui.PushStyleColor(entry[1], entry[2]);
    end
    imgui.PushStyleColor(ImGuiCol_WindowBg, GetBackground());
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, style.Padding);
end

function style.Pop()
    imgui.PopStyleVar();
    imgui.PopStyleColor(#palette + 1);
end

-- The same look for a window that holds only text and icons (the info bar and the detail view): just
-- the background, border and text colours, and the padding chosen in the settings. None of the
-- palette is needed there, and it is thirty-odd colours to push on every frame.
function style.PushPlain()
    local padding = style.GetPadding();
    style.Padding[1], style.Padding[2] = padding, padding;

    imgui.PushStyleColor(ImGuiCol_WindowBg, GetBackground());
    imgui.PushStyleColor(ImGuiCol_Border, GetBorder());
    imgui.PushStyleColor(ImGuiCol_Text, style.Text);
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, style.Padding);
end

function style.PopPlain()
    imgui.PopStyleVar();
    imgui.PopStyleColor(3);
end

return style;
