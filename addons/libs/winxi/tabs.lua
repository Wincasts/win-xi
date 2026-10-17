-- winxi.tabs: the theme's tab style, drawn over the tabs of a window on the game screen.
--
--   tabs.Begin(label, flags)   in place of imgui.BeginTabItem(label, 0, flags): the tab, with the style
--                              over it. Returns what BeginTabItem does.
--   tabs.Draw(chosen)          straight after an imgui.BeginTabItem of the addon's own: the style over
--                              the tab just begun. chosen: what BeginTabItem returned
--   tabs.BeginBar(id, flags)   in place of imgui.BeginTabBar: the bar, with the line under its tabs in
--                              the style. Returns what BeginTabBar does; EndTabBar as ever.
--   tabs.Over(list, left, top, right, bottom, radius)
--                              the style over a tab the addon draws itself, not imgui's: a rectangle on a
--                              draw list, kept inside rounded top corners of the radius (imgui's TabRounding
--                              if none). For an addon drawing tabs where the game's are, as chatbox does
--                              over the expanded log's. Nothing for 'plain'.
--   tabs.Line(list, left, right, y, chosenLeft, chosenRight)
--                              the line under such a row of tabs, from left to right at y, the chosen tab's
--                              part brighter; drawn for every style, there being no line of imgui's.
--
-- Only for a window of the game kind (winxi.window's kinds): a settings window's tabs are left plain.
--
-- The style is over the tab imgui draws in the theme's colours, never in place of it: white where the
-- tab is to be lighter and black where it is to be darker, both faint, so a tab keeps its colour chosen,
-- not chosen and under the mouse. 'plain' draws nothing. 'sheen' is drawn: light at the top, fading out
-- by the middle, then darkening to the foot. The rest are images of libs\winxi\assets\tabs, made by
-- tools/generate_winxi_tabs.py: the first and last 4 columns are the tab's edges, the 56 between them
-- repeated across it, and every row stretched to its height. Both keep to the tab's rounded top
-- corners, and fade with the window.
--
-- With any style but 'plain', the line imgui draws under a bar's tabs is drawn here in its place: in
-- the Highlight Color, two pixels deep and solid across the bar, brighter under the chosen tab with a
-- fine light edge along its top, and a soft shade below it.
local ffi = require('ffi');
local d3d = require('d3d8');
local imgui = require('imgui');
local theme = require('winxi.theme');

local tabs = {};

local folder = nil;
local handles = {}; -- style -> its handle, or false where it would not load
local kept = {};    -- the textures themselves, held so that they are not let go
local files = { glass = true, bevel = true, brushed = true, grain = true, lined = true, satin = true };
local imageWidth, cap = 64, 4;

-- Loads one of the images: a handle imgui can draw, or false. A field, so the checks can stand in for it.
function tabs.Load(style)
    folder = folder or ('%s\\addons\\libs\\winxi\\assets\\tabs\\'):format(AshitaCore:GetInstallPath());
    local device = d3d.get_device();
    if device == nil then
        return false;
    end
    local pointer = ffi.new('IDirect3DTexture8*[1]');
    if ffi.C.D3DXCreateTextureFromFileA(device, folder .. style .. '.png', pointer) ~= ffi.C.S_OK then
        return false;
    end
    local texture = d3d.gc_safe_release(ffi.cast('IDirect3DTexture8*', pointer[0]));
    kept[#kept + 1] = texture;
    return tonumber(ffi.cast('uint32_t', texture));
end

local function Texture(style)
    local handle = handles[style];
    if handle == nil then
        handle = tabs.Load(style) or false;
        handles[style] = handle;
    end
    return handle or nil;
end

-- How far in a rounded top corner pushes each row: rows -> { inset of each row }, by radius
local insets = {};
local function Insets(radius)
    local list = insets[radius];
    if list == nil then
        list = {};
        for row = 0, math.ceil(radius) - 1 do
            local dy = radius - (row + 0.5);
            list[row + 1] = radius - math.sqrt(math.max(0, radius * radius - dy * dy));
        end
        insets[radius] = list;
    end
    return list;
end

-- The sheen: strips of white or black, kept by height and radius, their colours packed again when the
-- window's fade changes
local sheenLight, sheenDark = 0.22, 0.28; -- the most white at the top, and black at the foot, 0 to 1
local sheenStep = 3;                      -- rows to a strip, below the rounded corners
local sheens = {};
local from, to = { 0, 0 }, { 0, 0 };

local function DrawSheen(list, left, top, right, height, radius, alpha)
    local key = height * 64 + radius;
    local sheen = sheens[key];
    if sheen == nil then
        sheen = { strips = {} };
        sheens[key] = sheen;
        local rowInsets = Insets(radius);
        local middle = height / 2;
        local row = 0;
        while row < height do
            -- the rounded top a row at a time, then wider strips down the straight sides
            local bottom = math.min(height, row + (row < radius and 1 or sheenStep));
            local at = (row + bottom) / 2;
            local light = at < middle;
            local amount = light and sheenLight * (1 - at / middle) or sheenDark * (at - middle) / middle;
            if amount > 0.005 then
                local rgb = light and 1 or 0;
                sheen.strips[#sheen.strips + 1] = {
                    row = row, bottom = bottom, inset = rowInsets[row + 1] or 0, color = { rgb, rgb, rgb, amount },
                };
            end
            row = bottom;
        end
    end
    if sheen.alpha ~= alpha then
        for _, strip in ipairs(sheen.strips) do
            strip.packed = imgui.GetColorU32(strip.color);
        end
        sheen.alpha = alpha;
    end
    for _, strip in ipairs(sheen.strips) do
        from[1], from[2] = left + strip.inset, top + strip.row;
        to[1], to[2] = right - strip.inset, top + strip.bottom;
        list:AddRectFilled(from, to, strip.packed);
    end
end

-- An image across a band of the tab, from x0 to x1 and rows y0 to y1 of it (v0 to v1 of the image): the
-- left edge, the middle repeated, and the right edge, each cut to what lies between x0 and x1
local uvA, uvB = { 0, 0 }, { 0, 0 };
local capU, middleU = cap / imageWidth, (imageWidth - 2 * cap) / imageWidth;
local middleWidth = imageWidth - 2 * cap;

local function Piece(list, texture, tint, pieceLeft, pieceRight, uLeft, x0, x1, y0, y1, v0, v1)
    local a, b = math.max(x0, pieceLeft), math.min(x1, pieceRight);
    if b <= a then
        return;
    end
    from[1], from[2], to[1], to[2] = a, y0, b, y1;
    uvA[1], uvA[2] = uLeft + (a - pieceLeft) / imageWidth, v0;
    uvB[1], uvB[2] = uLeft + (b - pieceLeft) / imageWidth, v1;
    list:AddImage(texture, from, to, uvA, uvB, tint);
end

local function Band(list, texture, tint, left, right, x0, x1, y0, y1, v0, v1)
    local leftCap, rightCap = math.min(left + cap, right), math.max(right - cap, left + cap);
    Piece(list, texture, tint, left, leftCap, 0, x0, x1, y0, y1, v0, v1);
    for start = leftCap, rightCap - 1, middleWidth do
        Piece(list, texture, tint, start, math.min(start + middleWidth, rightCap), capU, x0, x1, y0, y1, v0, v1);
    end
    Piece(list, texture, tint, rightCap, right, capU + middleU, x0, x1, y0, y1, v0, v1);
end

local white = { 1, 1, 1, 1 };

local function DrawImage(list, texture, left, top, right, height, radius)
    -- GetColorU32 takes in the window's Alpha, and so a fading window's fade
    local tint = imgui.GetColorU32(white);
    local rowInsets = Insets(radius);
    local rounded = #rowInsets;
    for row = 0, rounded - 1 do
        local inset = rowInsets[row + 1];
        Band(list, texture, tint, left, right, left + inset, right - inset,
            top + row, top + row + 1, row / height, (row + 1) / height);
    end
    Band(list, texture, tint, left, right, left, right, top + rounded, top + height, rounded / height, 1);
end

-- The line under a bar's tabs: where the bar runs across, set by BeginBar and drawn with its first tab
local pendingLeft, pendingRight = nil, nil;
local lineColor = { 0, 0, 0, 0 };
local edgeLight, shadeDark, shadeClear = { 1, 1, 1, 0.30 }, { 0, 0, 0, 0.30 }, { 0, 0, 0, 0 };
local lineStrength = 1.6; -- how much more solid than the Highlight Color the line is, and the chosen tab's part
local chosenStrength = 2.4;

local function LineColor(into, strength)
    local highlight = theme.Get().HighlightColor;
    into[1], into[2], into[3] = highlight[1], highlight[2], highlight[3];
    into[4] = math.min(1, highlight[4] * strength);
    return into;
end

local function DrawLine(list, left, right, y)
    if right - left < 1 then
        return;
    end
    -- GetColorU32 takes in the window's Alpha, and so a fading window's fade
    from[1], from[2], to[1], to[2] = left, y - 1, right, y + 1;
    list:AddRectFilled(from, to, imgui.GetColorU32(LineColor(lineColor, lineStrength)));
    -- the shade under it, dark at the top and clear at its foot
    local dark, none = imgui.GetColorU32(shadeDark), imgui.GetColorU32(shadeClear);
    from[2], to[2] = y + 1, y + 3;
    list:AddRectFilledMultiColor(from, to, dark, dark, none, none);
end

-- Under the chosen tab: the line brighter, with a fine light edge along its top
local function DrawChosen(list, left, right, y)
    local packed = imgui.GetColorU32(LineColor(lineColor, chosenStrength));
    from[1], from[2], to[1], to[2] = left, y - 1, right, y + 1;
    list:AddRectFilled(from, to, packed);
    from[2], to[2] = y - 1, y;
    list:AddRectFilled(from, to, imgui.GetColorU32(edgeLight));
end

function tabs.BeginBar(id, flags)
    local style = theme.Get().TabStyle;
    local styled = style == 'sheen' or files[style];
    local pushed = styled and ImGuiStyleVar_TabBarBorderSize ~= nil;
    if styled then
        -- the bar runs across what is left of the window's width, from where it starts
        local x = imgui.GetCursorScreenPos();
        local width = imgui.GetContentRegionAvail();
        pendingLeft, pendingRight = x, x + width;
    else
        pendingLeft, pendingRight = nil, nil;
    end
    -- imgui draws its own line as the bar begins: none, where this one takes its place
    if pushed then
        imgui.PushStyleVar(ImGuiStyleVar_TabBarBorderSize, 0);
    end
    local open = imgui.BeginTabBar(id, flags or 0);
    if pushed then
        imgui.PopStyleVar();
    end
    return open;
end

function tabs.Draw(chosen)
    local style = theme.Get().TabStyle;
    if style ~= 'sheen' and not files[style] then
        return;
    end
    local left, top = imgui.GetItemRectMin();
    local right, bottom = imgui.GetItemRectMax();
    local height = bottom - top;
    if height < 2 or right - left < 2 then
        return;
    end
    local list = imgui.GetWindowDrawList();
    local imguiStyle = imgui.GetStyle();
    local radius = math.floor(math.min(imguiStyle.TabRounding or 0, height / 2, (right - left) / 2));
    if style == 'sheen' then
        DrawSheen(list, left, top, right, height, radius, imguiStyle.Alpha or 1);
    else
        local texture = Texture(style);
        if texture ~= nil then
            DrawImage(list, texture, left, top, right, height, radius);
        end
    end
    -- the line after the tab, so that the tab's foot does not shade it
    if pendingLeft ~= nil then
        DrawLine(list, pendingLeft, pendingRight, bottom);
        pendingLeft, pendingRight = nil, nil;
    end
    if chosen then
        DrawChosen(list, left, right, bottom);
    end
end

function tabs.Begin(label, flags)
    local open = imgui.BeginTabItem(label, 0, flags or 0);
    tabs.Draw(open);
    return open;
end

function tabs.Over(list, left, top, right, bottom, radius)
    local style = theme.Get().TabStyle;
    if style ~= 'sheen' and not files[style] then
        return;
    end
    local height = bottom - top;
    if height < 2 or right - left < 2 then
        return;
    end
    local imguiStyle = imgui.GetStyle();
    radius = math.floor(math.min(radius or imguiStyle.TabRounding or 0, height / 2, (right - left) / 2));
    if style == 'sheen' then
        DrawSheen(list, left, top, right, height, radius, imguiStyle.Alpha or 1);
    else
        local texture = Texture(style);
        if texture ~= nil then
            DrawImage(list, texture, left, top, right, height, radius);
        end
    end
end

function tabs.Line(list, left, right, y, chosenLeft, chosenRight)
    DrawLine(list, left, right, y);
    if chosenLeft ~= nil and chosenRight ~= nil and chosenRight > chosenLeft then
        DrawChosen(list, chosenLeft, chosenRight, y);
    end
end

return tabs;
