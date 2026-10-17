-- winxi.style: puts the theme on imgui's style stack around a window.
--
--   style.PushPlain()  the background, border and text colours and the padding. For a window that
--                      holds only text, bars and icons: four colours, cheap enough for every frame.
--   style.PushFull()   those, and the palette that tints tabs, tables, buttons, inputs, sliders,
--                      scrollbars and title bars from the border colour. For a window with controls.
--
-- Call one before a window's Begin and style.Pop() after its End. Pushes may be nested.
-- Style rule: child regions are always transparent, showing the parent Winxi background.
-- Do not override ChildBg or draw a separate background for a child region.
-- Both accept per-window RGBA border/textColor overrides (border alpha replaces Border Opacity).
-- Both take an optional table: padding (a number, in place of the theme's), background (a colour, in
-- place of the theme's), alpha (0 to 1, for a window that is fading), kind (winxi.window's: a settings
-- window has the theme's settings window colours and padding, and its border is never faded; a game
-- window's border is faded by the theme's Border Opacity, and it has the theme's background style,
-- which backgrounds.Draw(style.Background(), ...) draws once it has begun).
local bit = require('bit');
local imgui = require('imgui');
local theme = require('winxi.theme');
local backgrounds = require('winxi.backgrounds');

local style = {};

-- What each push put on the stacks, so that Pop takes off exactly that
local pushed = {};
local depth = 0;

-- The padding of the window last pushed for, as a table for imgui and as a number
local padding = { 10, 10 };
local clear = { 0, 0, 0, 0 };
local background = nil; -- the window last pushed for's background (winxi.backgrounds), or nil for imgui's own

local function Push(options, withPalette)
    local settingsKind = options ~= nil and options.kind == 'settings';
    local colors, vars = 4, 1;

    if options and options.alpha and options.alpha < 1 then
        imgui.PushStyleVar(ImGuiStyleVar_Alpha, options.alpha);
        vars = vars + 1;
    end

    if withPalette then
        local palette = theme.Palette(settingsKind);
        local count = #palette;
        for index = 1, count do
            local entry = palette[index];
            imgui.PushStyleColor(entry[1], entry[2]);
        end
        colors = colors + count;
    end

    -- where the theme's background is drawn (winxi.backgrounds), the window's own is left clear under it
    background = backgrounds.For(options);
    imgui.PushStyleColor(ImGuiCol_WindowBg, background and clear or (options and options.background or theme.For('BackgroundColor', settingsKind)));
    -- a settings window's border is never faded, so that it can always be found
    imgui.PushStyleColor(ImGuiCol_Border, options and options.border or (settingsKind and theme.For('BorderColor', true) or theme.GameBorderColor()));
    imgui.PushStyleColor(ImGuiCol_Text, options and options.textColor or theme.For('TextColor', settingsKind));
    -- Apply after the palette so themes cannot introduce a separate child background.
    imgui.PushStyleColor(ImGuiCol_ChildBg, clear);

    local amount = options and tonumber(options.padding) or theme.For('Padding', settingsKind);
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

-- The background of the window last pushed for, for backgrounds.Draw, or nil where it has imgui's own
function style.Background()
    return background;
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
