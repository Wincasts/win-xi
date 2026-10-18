addon.name    = 'mapoverlay';
addon.author  = 'win';
addon.version = '0.1';
addon.desc    = 'The zone\'s map over the game, only where the ground can be walked.';
addon.link    = 'https://github.com/Wincasts/win-xi';

-- The map of the zone the player is in, laid over the game, with only its walkable ground drawn and
-- the parchment round it left clear. The ground is traced from the map's own artwork, ahead of time,
-- by tools/trace_walkable_maps.py into data/walkable.lua: a mask for each map, which winxi.mapdat lays
-- over the picture as it reads it from the game's files (XICombinedMaps' where pivot has it). Only the
-- maps traced so far have one: elsewhere nothing is drawn.
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
local position = require('position');

local windowName = 'winxi.mapoverlay';
local LOOK_EVERY = 0.25; -- seconds between looks at which map the player is on
local MARGIN = 6;        -- map units kept round the ground when fitting to it
local KEEP = 8;          -- textures kept, for going back to a floor without reading it again

local defaults = T{
    isVisible = T{ true },
    pos = T{ 100, 100 },
    centered = T{ true },
    locked = T{ true },
    size = T{ 600 },
    opacity = T{ 0.85 },
    fit = T{ true },
    zoom = T{ 1.0 },
    showPlayer = T{ true },
    playerColor = T{ 1.00, 0.85, 0.20, 1.00 },
    playerSize = T{ 14 },
};

local app;

-- Textures

local textures = {}; -- map key -> { texture, handle, used }, or { why } where it could not be made
local clock = 0;

local function Texture(map)
    clock = clock + 1;
    local held = textures[map.key];
    if held then
        held.used = clock;
        return held.handle, held.why;
    end
    local count, oldest = 0, nil;
    for key, kept in pairs(textures) do
        count = count + 1;
        if oldest == nil or kept.used < textures[oldest].used then oldest = key; end
    end
    if count >= KEEP then textures[oldest] = nil; end
    local texture, handle, why = mapdat.Load(map.dat, masks.Get(map));
    if why == 'no device yet' then return nil, why; end
    textures[map.key] = { texture = texture, handle = handle, why = why, used = clock };
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
    local handle = Texture(map);
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

local function Tip(words)
    if imgui.IsItemHovered() then imgui.SetTooltip(words); end
end

local function Status()
    if current.map == nil then
        return 'No map: ' .. tostring(current.why);
    end
    local transform, why = position.Transform(current.map);
    local text = ('Zone %d, floor %d: %s'):format(current.map.zone, current.map.floor, current.map.key);
    local held = textures[current.map.key];
    if held and held.why then text = text .. ' (the picture could not be read: ' .. held.why .. ')'; end
    if transform == nil then text = text .. ' (no player marker: ' .. tostring(why) .. ')'; end
    return text;
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
        widgets.Label('Opacity');
        imgui.SliderFloat('##mapoverlay.opacity', options.opacity, 0.1, 1.0, '%.2f');
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
        imgui.SliderInt('##mapoverlay.playerSize', options.playerSize, 6, 40, '%d px');
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
    onSettings = function() place = true; end,
});

ashita.events.register('d3d_present', 'mapoverlay_present', function()
    Look();
    if not app:BeginFrame() then return; end
    Draw(app.options);
end);
