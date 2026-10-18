addon.name    = 'mapoverlay';
addon.author  = 'win';
addon.version = '0.2';
addon.desc    = 'The zone\'s map over the game, only where the ground can be walked.';
addon.link    = 'https://github.com/Wincasts/win-xi';

-- The walkable ground of the zone the player is in, laid over the game, with everything off it left
-- clear. The ground is traced from the map's own artwork, ahead of time, by
-- tools/trace_walkable_maps.py into data/walkable.lua: a mask for each map. Flat (to start), the
-- ground is painted in one colour with its rim in another (flat.lua), and the lines of the game's
-- own grid, A to O across and 1 to 15 down, drawn where they cross it; Map Art, the mask is laid over
-- the map's picture as winxi.mapdat reads it from the game's files (XICombinedMaps' where pivot has it). Only
-- the maps traced so far have one: elsewhere nothing is drawn.
--
--   /mapoverlay           shows or hides the overlay (/mov does the same)
--   /mapoverlay config    opens or closes the settings
--   /mapoverlay status    says which map is drawn, or why none is
--
-- Where the player is comes from the client's table of maps and, in a zone of several floors, the
-- client's floor for where the player stands, read as zone reads them (position.lua).

local winxiNeeded = 20;
do
    local ok, found = pcall(require, 'winxi.version');
    local number = ok and type(found) == 'table' and found.Number or 0;
    if number < winxiNeeded then
        local text = ('%s needs winxi %d or newer, and addons/libs/winxi is %d: install the newest release of any winxi addon.'):format(addon.name, winxiNeeded, number);
        print(('\30\68[%s]\30\01 %s'):format(addon.name, text));
        error(text, 0);
    end
end

require('common');
local bit = require('bit');
local imgui = require('imgui');
local widgets = require('winxi.widgets');
local shell = require('winxi.shell');
local window = require('winxi.window');
local fade = require('winxi.fade');
local style = require('winxi.style');
local mapdat = require('winxi.mapdat');
local masks = require('masks');
local flat = require('flat');
local position = require('position');

local windowName = 'winxi.mapoverlay';
local LOOK_EVERY = 0.25; -- seconds between looks at which map the player is on
local MARGIN = 6;        -- map units kept round the ground when fitting to it
local KEEP = 8;          -- textures kept, for going back to a floor without reading it again
local REPAINT = 0.2;     -- seconds at least between paintings of the ground while its colours change
local GRID_FIRST, GRID_STEP, GRID_SQUARES = 16, 32, 15; -- the game's grid, in map units: A1 is 16 to 48

local defaults = T{
    isVisible = T{ true },
    pos = T{ 100, 100 },
    centered = T{ true },
    locked = T{ true },
    size = T{ 600 },
    style = 'flat',          -- 'flat': the ground painted; 'art': the map's own picture
    opacity = T{ 0.85 },
    fillColor = T{ 0.92, 0.92, 0.92 },
    edgeColor = T{ 0.55, 0.55, 0.55 },
    showGrid = T{ true },
    gridColor = T{ 0.0, 0.0, 0.0 },
    gridOpacity = T{ 0.6 },
    fit = T{ true },
    zoom = T{ 1.0 },
    showPlayer = T{ true },
    playerColor = T{ 1.00, 0.85, 0.20, 1.00 },
    playerSize = T{ 14 },
};

local styles = { { key = 'flat', label = 'Flat' }, { key = 'art', label = 'Map Art' } };

local app;

-- Textures

-- map key and style -> { texture, handle, why, used, colours, painted }: flat, painted in colours
local textures = {};
local clock = 0;

local function Colours(options)
    local f, e = options.fillColor, options.edgeColor;
    return ('%.3f,%.3f,%.3f/%.3f,%.3f,%.3f'):format(f[1], f[2], f[3], e[1], e[2], e[3]);
end

local function Make(map, options)
    if options.style == 'art' then
        return mapdat.Load(map.dat, masks.Get(map));
    end
    return flat.Load(masks.Get(map), options.fillColor, options.edgeColor);
end

local function Texture(map, options)
    clock = clock + 1;
    local key = map.key .. '/' .. options.style;
    local colours = options.style == 'flat' and Colours(options) or '';
    local held = textures[key];
    -- the colours changed: painted again, but not every frame while a colour is dragged
    if held and held.colours ~= colours and os.clock() - held.painted >= REPAINT then
        local texture, handle, why = Make(map, options);
        if why ~= 'no device yet' then
            held.texture, held.handle, held.why, held.colours, held.painted = texture, handle, why, colours, os.clock();
        end
    end
    if held then
        held.used = clock;
        return held.handle, held.why;
    end
    local count, oldest = 0, nil;
    for name, kept in pairs(textures) do
        count = count + 1;
        if oldest == nil or kept.used < textures[oldest].used then oldest = name; end
    end
    if count >= KEEP then textures[oldest] = nil; end
    local texture, handle, why = Make(map, options);
    if why == 'no device yet' then return nil, why; end
    textures[key] = { texture = texture, handle = handle, why = why, used = clock, colours = colours, painted = os.clock() };
    return handle, why;
end

-- Which map

local current = { map = nil, why = 'not looked yet', zone = nil, next = 0 };

local function Look()
    local now = os.clock();
    if now < current.next then return; end
    current.next = now + LOOK_EVERY;
    current.map = nil;
    local ok, zone = pcall(function() return AshitaCore:GetMemoryManager():GetParty():GetMemberZone(0); end);
    if not ok or zone == nil or zone == 0 then current.why = 'no zone'; return; end
    current.zone = zone;
    local floors = masks.ForZone(zone);
    if floors == nil then current.why = 'no walkable ground has been traced for this zone yet'; return; end
    local player = position.Player();
    if player == nil then current.why = 'the player is not there'; return; end
    local count, only = 0, nil;
    for _, map in pairs(floors) do count, only = count + 1, map; end
    if count == 1 then
        current.map = only;
    else
        local floor, why = position.Floor(player);
        if floor == nil then current.why = why; return; end
        current.map = floors[floor];
        if current.map == nil then current.why = ('no ground has been traced for floor %d'):format(floor); return; end
    end
    current.why = nil;
end

-- Drawing

local corner1, corner2, uv1, uv2 = { 0, 0 }, { 0, 0 }, { 0, 0 }, { 0, 0 };
local tint, colour, dark, edge = { 1, 1, 1, 1 }, { 1, 1, 1, 1 }, { 0, 0, 0, 1 }, { 1, 1, 1, 0.6 };
local line, from, to = { 0, 0, 0, 1 }, { 0, 0, 0 }, { 0, 0, 0 };
local boxSize, outlineA, outlineB = { 0, 0 }, { 0, 0 }, { 0, 0 };
local p1, p2, p3 = { 0, 0 }, { 0, 0 }, { 0, 0 };

-- The square of the map shown, in map units: the ground and a margin, or the whole map; zoomed in,
-- a smaller square with the player in its middle, kept on the map
local function View(mask, options, px, py)
    local b = (options.fit[1] and mask.bounds) or { 0, 0, 512, 512 };
    local cx, cy = (b[1] + b[3]) / 2, (b[2] + b[4]) / 2;
    local half = math.max(b[3] - b[1], b[4] - b[2]) / 2 + (options.fit[1] and MARGIN or 0);
    local zoom = math.max(1, options.zoom[1]);
    if zoom > 1 and px ~= nil then
        half, cx, cy = half / zoom, px, py;
    end
    half = math.min(half, 256);
    cx = math.max(half, math.min(512 - half, cx));
    cy = math.max(half, math.min(512 - half, cy));
    return cx - half, cy - half, half * 2;
end

local function Arrow(drawList, x, y, heading, size, options, alpha)
    local function Corner(point, angle, reach)
        point[1], point[2] = x + math.cos(angle) * reach, y + math.sin(angle) * reach;
    end
    dark[4] = 0.9 * alpha;
    local shade = imgui.GetColorU32(dark);
    Corner(p1, heading, size * 0.75); Corner(p2, heading + 2.4, size * 0.6); Corner(p3, heading - 2.4, size * 0.6);
    drawList:AddTriangleFilled(p1, p2, p3, shade);
    local c = options.playerColor;
    colour[1], colour[2], colour[3], colour[4] = c[1], c[2], c[3], c[4] * alpha;
    Corner(p1, heading, size * 0.6); Corner(p2, heading + 2.4, size * 0.45); Corner(p3, heading - 2.4, size * 0.45);
    drawList:AddTriangleFilled(p1, p2, p3, imgui.GetColorU32(colour));
end

-- The game's grid over the part of the map shown: its lines only where they cross the ground
local function Grid(drawList, options, alpha, x, y, size, vx, vy, vs, stretches)
    local opacity = options.gridOpacity[1] * alpha;
    if opacity <= 0.01 then return; end
    local c = options.gridColor;
    line[1], line[2], line[3], line[4] = c[1], c[2], c[3], opacity;
    local packed = imgui.GetColorU32(line);
    local function SX(u) return x + (u - vx) / vs * size; end
    local function SY(u) return y + (u - vy) / vs * size; end
    for k = 0, GRID_SQUARES do
        local u = GRID_FIRST + k * GRID_STEP;
        if u >= vx and u <= vx + vs then
            local runs = stretches.across[k];
            for i = 1, #runs, 2 do
                local a, b = math.max(runs[i], vy), math.min(runs[i + 1], vy + vs);
                if b > a then
                    from[1], from[2], to[1], to[2] = SX(u), SY(a), SX(u), SY(b);
                    drawList:AddLine(from, to, packed, 1);
                end
            end
        end
        if u >= vy and u <= vy + vs then
            local runs = stretches.down[k];
            for i = 1, #runs, 2 do
                local a, b = math.max(runs[i], vx), math.min(runs[i + 1], vx + vs);
                if b > a then
                    from[1], from[2], to[1], to[2] = SX(a), SY(u), SX(b), SY(u);
                    drawList:AddLine(from, to, packed, 1);
                end
            end
        end
    end
end

local function DrawMap(options, alpha)
    local x, y = imgui.GetCursorScreenPos();
    local size = options.size[1];
    boxSize[1], boxSize[2] = size, size;
    imgui.Dummy(boxSize);
    local drawList = imgui.GetWindowDrawList();
    if not options.locked[1] and not options.centered[1] then
        outlineA[1], outlineA[2], outlineB[1], outlineB[2] = x, y, x + size, y + size;
        drawList:AddRect(outlineA, outlineB, imgui.GetColorU32(edge), 0, 0, 1);
    end
    local map = current.map;
    if map == nil then return; end
    local handle = Texture(map, options);
    if handle == nil then return; end

    local player = position.Player();
    local transform = position.Transform(map);
    local px, py;
    if player ~= nil and transform ~= nil then px, py = position.ToMap(transform, player); end

    local vx, vy, vs = View(masks.Get(map), options, px, py);
    corner1[1], corner1[2], corner2[1], corner2[2] = x, y, x + size, y + size;
    uv1[1], uv1[2], uv2[1], uv2[2] = vx / 512, vy / 512, (vx + vs) / 512, (vy + vs) / 512;
    tint[4] = options.opacity[1] * alpha;
    drawList:AddImage(handle, corner1, corner2, uv1, uv2, imgui.GetColorU32(tint));
    if options.showGrid[1] then
        Grid(drawList, options, alpha, x, y, size, vx, vy, vs, masks.Get(map).grid);
    end

    if options.showPlayer[1] and px ~= nil then
        local sx, sy = x + (px - vx) / vs * size, y + (py - vy) / vs * size;
        if sx >= x and sx <= x + size and sy >= y and sy <= y + size then
            Arrow(drawList, sx, sy, player.heading, options.playerSize[1], options, alpha);
        end
    end
end

local open = { true };
local windowOptions = { alpha = 1, background = { 0, 0, 0, 0 }, border = { 0, 0, 0, 0 }, padding = 0, shadow = false };
local place = true;

local function Draw(options)
    local wanted = options.isVisible[1];
    local alpha = wanted and 1 or 0;
    if options.fadeInOut[1] then alpha = fade.Presence(windowName, wanted); end
    if alpha <= 0.01 then return; end
    if current.map == nil and not app.showConfig[1] then return; end

    local flags = bit.bor(style.TitlelessFlags(), ImGuiWindowFlags_NoSavedSettings, ImGuiWindowFlags_NoFocusOnAppearing,
        ImGuiWindowFlags_NoNav, ImGuiWindowFlags_NoScrollbar, ImGuiWindowFlags_NoScrollWithMouse, ImGuiWindowFlags_NoBackground);
    local fixed = options.locked[1] or options.centered[1];
    if fixed then flags = bit.bor(flags, ImGuiWindowFlags_NoMove, ImGuiWindowFlags_NoInputs); end

    if options.centered[1] then
        local display = imgui.GetIO().DisplaySize;
        local half = options.size[1] / 2;
        imgui.SetNextWindowPos({ display.x / 2 - half, display.y / 2 - half }, ImGuiCond_Always);
    else
        imgui.SetNextWindowPos(options.pos, (options.locked[1] or place) and ImGuiCond_Always or ImGuiCond_FirstUseEver);
    end
    place = false;
    windowOptions.alpha = alpha;
    window.Plain(windowName, open, flags, function()
        DrawMap(options, alpha);
        if not fixed then
            local wx, wy = imgui.GetWindowPos();
            options.pos[1], options.pos[2] = math.floor(wx + 0.5), math.floor(wy + 0.5);
        end
    end, windowOptions);
end

-- Settings

local Tip = require('winxi.tooltip').Hover;

local function Combo(id, value, choices)
    local shown = choices[1].label;
    for _, choice in ipairs(choices) do
        if choice.key == value then shown = choice.label; end
    end
    local chosen = value;
    if imgui.BeginCombo(id, shown) then
        for _, choice in ipairs(choices) do
            if imgui.Selectable(choice.label .. id, choice.key == value) then chosen = choice.key; end
        end
        imgui.EndCombo();
    end
    return chosen;
end

local function Status()
    if current.map == nil then
        return 'No map: ' .. tostring(current.why);
    end
    local transform, why = position.Transform(current.map);
    local said = ('Zone %d, floor %d: %s'):format(current.map.zone, current.map.floor, current.map.key);
    local held = textures[current.map.key .. '/' .. app.options.style];
    if held and held.why then said = said .. ' (nothing to draw: ' .. held.why .. ')'; end
    if transform == nil then said = said .. ' (no player marker: ' .. tostring(why) .. ')'; end
    return said;
end

local function DrawSettings(options)
    if widgets.Header('Overlay') then
        widgets.Label('Visible');
        imgui.Checkbox('##mapoverlay.visible', options.isVisible);
        Tip('Whether the overlay shows. /mapoverlay switches this.');
        widgets.Label('Centered');
        imgui.Checkbox('##mapoverlay.centered', options.centered);
        Tip('In the middle of the screen. Off, it stays where it is put.');
        if not options.centered[1] then
            widgets.Label('Locked');
            imgui.Checkbox('##mapoverlay.locked', options.locked);
            Tip('Unlocked, the overlay can be dragged (its edge drawn). Locked, clicks go through it.');
            widgets.Label('Position');
            if imgui.InputInt2('##mapoverlay.position', options.pos) then place = true; end
        end
        widgets.PushControlWidth();
        widgets.Label('Size');
        imgui.SliderInt('##mapoverlay.size', options.size, 150, 1600, '%d px');
        widgets.Label('Map Opacity');
        imgui.SliderFloat('##mapoverlay.opacity', options.opacity, 0.05, 1.0, '%.2f');
        Tip('How solid the ground is: 1 solid, less to see the game through it.');
        widgets.PopControlWidth();
        widgets.Label('Style');
        options.style = Combo('##mapoverlay.style', options.style, styles);
        Tip('Flat: the ground painted in the colours below.\nMap Art: the map\'s own picture, only where the ground is.');
        if options.style == 'flat' then
            widgets.Label('Fill Color');
            imgui.ColorEdit3('##mapoverlay.fillColor', options.fillColor, ImGuiColorEditFlags_NoInputs);
            widgets.Label('Edge Color');
            imgui.ColorEdit3('##mapoverlay.edgeColor', options.edgeColor, ImGuiColorEditFlags_NoInputs);
            Tip('The rim of the ground, a map unit and a half wide.');
        end
    end

    if widgets.Header('Grid') then
        widgets.Label('Show Grid');
        imgui.Checkbox('##mapoverlay.showGrid', options.showGrid);
        Tip('The lines of the game\'s map squares, the ones the clock names, drawn on the ground only.');
        widgets.Label('Grid Color');
        imgui.ColorEdit3('##mapoverlay.gridColor', options.gridColor, ImGuiColorEditFlags_NoInputs);
        widgets.PushControlWidth();
        widgets.Label('Grid Opacity');
        imgui.SliderFloat('##mapoverlay.gridOpacity', options.gridOpacity, 0.0, 1.0, '%.2f');
        widgets.PopControlWidth();
    end

    if widgets.Header('View') then
        widgets.Label('Fit To Walkable Area');
        imgui.Checkbox('##mapoverlay.fit', options.fit);
        Tip('Shows the part of the map with ground on it, as large as the overlay. Off, the whole map.');
        widgets.PushControlWidth();
        widgets.Label('Zoom');
        imgui.SliderFloat('##mapoverlay.zoom', options.zoom, 1.0, 4.0, '%.1fx');
        Tip('Past 1x, nearer, with the player in the middle.');
        widgets.PopControlWidth();
    end

    if widgets.Header('Player') then
        widgets.Label('Show Player');
        imgui.Checkbox('##mapoverlay.showPlayer', options.showPlayer);
        widgets.Label('Player Color');
        imgui.ColorEdit4('##mapoverlay.playerColor', options.playerColor, ImGuiColorEditFlags_NoInputs);
        widgets.PushControlWidth();
        widgets.Label('Player Size');
        imgui.SliderInt('##mapoverlay.playerSize', options.playerSize, 6, 64, '%d px');
        Tip('How large your marker is on the map.');
        widgets.PopControlWidth();
    end

    imgui.TextWrapped(Status());
end

app = shell.New({
    defaults = defaults,
    window = windowName,
    configTitle = 'Map Overlay Settings',
    command = '/mapoverlay',
    aliases = { '/mov' },
    help = '/mapoverlay shows or hides the overlay; /mapoverlay config opens the settings; /mapoverlay status says which map is drawn.',
    drawSettings = DrawSettings,
    commands = {
        status = function() current.next = 0; Look(); app:Say(Status()); end,
    },
    onSettings = function(options)
        place = true;
        if options.style ~= 'flat' and options.style ~= 'art' then options.style = 'flat'; end
        options.gridLabels = nil; -- 0.2's letters and numbers, gone
    end,
});

ashita.events.register('d3d_present', 'mapoverlay_present', function()
    Look();
    if not app:BeginFrame() then return; end
    Draw(app.options);
end);
