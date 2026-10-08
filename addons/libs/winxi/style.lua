-- winxi.style: puts the theme on imgui's style stack around a window.
--
--   style.PushPlain()  the background, border and text colours and the padding. For a window that
--                      holds only text, bars and icons: three colours, cheap enough for every frame.
--   style.PushFull()   those, and the palette that tints tabs, tables, buttons, inputs, sliders,
--                      scrollbars and title bars from the border colour. For a window with controls.
--
-- Call one before a window's Begin and style.Pop() after its End. Pushes may be nested.
-- Both take an optional table: padding (a number, in place of the theme's), background (a colour, in
-- place of the theme's), alpha (0 to 1, for a window that is fading).
local theme = require('winxi.theme');

local style = {};

-- What each push put on the stacks, so that Pop takes off exactly that
local pushed = {};
local depth = 0;

-- The padding of the window last pushed for, as a table for imgui and as a number
local padding = { 10, 10 };

local function Push(options, withPalette)
    local current = theme.Get();
    local colors, vars = 3, 1;

    if options and options.alpha and options.alpha < 1 then
        imgui.PushStyleVar(ImGuiStyleVar_Alpha, options.alpha);
        vars = vars + 1;
    end

    if withPalette then
        local palette = theme.Palette();
        for _, entry in ipairs(palette) do
            imgui.PushStyleColor(entry[1], entry[2]);
        end
        colors = colors + #palette;
    end

    imgui.PushStyleColor(ImGuiCol_WindowBg, options and options.background or current.BackgroundColor);
    imgui.PushStyleColor(ImGuiCol_Border, current.BorderColor);
    imgui.PushStyleColor(ImGuiCol_Text, current.TextColor);

    local amount = options and tonumber(options.padding) or current.Padding;
    padding[1], padding[2] = amount, amount;
    imgui.PushStyleVar(ImGuiStyleVar_WindowPadding, padding);

    depth = depth + 1;
    local record = pushed[depth];
    if record == nil then
        record = {};
        pushed[depth] = record;
    end
    record.colors, record.vars = colors, vars;
end

function style.PushPlain(options)
    Push(options, false);
end

function style.PushFull(options)
    Push(options, true);
end

function style.Pop()
    local record = pushed[depth];
    if record == nil then
        return;
    end
    depth = depth - 1;

    imgui.PopStyleVar(record.vars);
    imgui.PopStyleColor(record.colors);
end

-- The padding, in pixels, of the window last pushed for
function style.Padding()
    return padding[1];
end

-- Window flags for the two usual kinds of winxi window: no title bar, sized to its content; and no
-- title bar but resizable. Made on first use, when imgui's flags are certain to be defined.
local titleless, resizable = nil, nil;

function style.TitlelessFlags()
    if titleless == nil then
        titleless = bit.bor(
            ImGuiWindowFlags_NoTitleBar,
            ImGuiWindowFlags_NoResize,
            ImGuiWindowFlags_NoCollapse,
            ImGuiWindowFlags_AlwaysAutoResize);
    end
    return titleless;
end

function style.ResizableFlags()
    if resizable == nil then
        resizable = bit.bor(ImGuiWindowFlags_NoTitleBar, ImGuiWindowFlags_NoCollapse);
    end
    return resizable;
end

return style;
