addon.name    = 'atlas';
addon.author  = 'win';
addon.version = '0.5';
addon.desc    = 'The zone\'s map in a window: who is where, panned and zoomed.';
addon.link    = 'https://github.com/Wincasts/win-xi';

-- The map of the zone the player is in, in a window of its own: the game's own picture, with the
-- player, their party and alliance, and their target on it. The map follows the floor the player is
-- on; another of the zone's floors can be chosen over it. The wheel zooms round the place under the
-- mouse and a drag pans; while following, the player is kept in the middle.
--
--   /atlas           shows or hides the map
--   /atlas config    opens or closes the settings
--   /atlas status    says which map is drawn, or why none is
--   /atlas browse    takes the controller for the map, as the game's own map does, or gives it back;
--                    opens the map if it is hidden (pad.lua)
--
-- The game's own /map is left to the game. maps.lua knows the zone's maps and how they lie over it,
-- markers.lua who is where, and view.lua draws a map into a square, knowing nothing of the window:
-- the square can later be where the game draws its own map.

local winxiNeeded = 26;
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
local imgui = require('imgui');
local widgets = require('winxi.widgets');
local shell = require('winxi.shell');
local tips = require('winxi.tooltip');
local maps = require('maps');
local markers = require('markers');
local view = require('view');
local pad = require('pad');
local moving = require('moving');

local defaults = T{
    isVisible = T{ true },
    pos = T{ 100, 100 },
    locked = T{ false },
    size = T{ 512 },
    fadeWhileMoving = T{ false },
    movingOpacity = T{ 30 },
    showPlayer = T{ true },
    playerColor = T{ 1.00, 0.85, 0.20, 1.00 },
    showParty = T{ true },
    partyColor = T{ 0.35, 0.80, 1.00, 1.00 },
    showAlliance = T{ true },
    allianceColor = T{ 0.55, 0.95, 0.45, 1.00 },
    showTarget = T{ true },
    targetColor = T{ 1.00, 0.35, 0.30, 1.00 },
    markerSize = T{ 9 },
    showNames = T{ true },
    askServer = T{ true },
    controller = T{ true },
    controllerSounds = T{ false },
    stickScrolls = T{ false },
    controllerType = 'xinput', -- which kind: a key of winxi.controller's Layouts
};

local app;
local state = view.New();

-- Which map

-- zone: the zone the player is in; chosen: a floor's id picked over the map, or nil to follow the
-- player's; here: the map the player is on, and why not where none
local current = { zone = nil, chosen = nil, here = nil, why = 'not looked yet' };
local scene = { picture = nil, markers = {} };
local playerAt = { mx = nil, my = nil }; -- the player's place on the map shown, or nil

local function Zone()
    local ok, zone = pcall(function() return AshitaCore:GetMemoryManager():GetParty():GetMemberZone(0); end);
    return ok and zone or nil;
end

local names = {}; -- zone -> its name, asked once

local function ZoneName(zone)
    if names[zone] == nil then
        local ok, name = pcall(function() return AshitaCore:GetResourceManager():GetString('zones.names', zone); end);
        names[zone] = ok and name ~= nil and name ~= '' and name or ('Zone %d'):format(zone);
    end
    return names[zone];
end

-- The map shown: the one picked, or the one the player is on, or the zone's first where that cannot be told
local function Shown()
    local zone = current.zone;
    if zone == nil then
        return nil;
    end
    if current.chosen ~= nil then
        local map = maps.Floor(zone, current.chosen);
        if map ~= nil then return map; end
    end
    if current.here ~= nil then
        return current.here;
    end
    local floors = maps.Floors(zone);
    return floors and floors[1] or nil;
end

-- Who is where, on the map shown: the player's own map first, as the map shown follows it, then
-- each marker's floor asked of the client in a zone of several
local function Place()
    local list = markers.List();
    current.here, current.why = nil, 'the player is not there';
    for _, marker in ipairs(list) do
        if marker.kind == 'player' then
            current.here, current.why = maps.At(current.zone, marker.x, marker.y, marker.z);
        end
    end
    local shown = Shown();
    local entry = shown and maps.Entry(shown, current.zone) or nil;
    local several = #(maps.Floors(current.zone) or {}) > 1;
    local placed = scene.markers;
    local count = 0;
    playerAt.mx, playerAt.my = nil, nil;
    for _, marker in ipairs(entry and list or {}) do
        local map = marker.kind == 'player' and current.here or (several and maps.At(current.zone, marker.x, marker.y, marker.z) or shown);
        if map ~= nil and map.floor == shown.floor then
            local mx, my = maps.ToMap(entry, marker.x, marker.y);
            count = count + 1;
            local p = placed[count] or {};
            placed[count] = p;
            p.kind, p.mx, p.my, p.heading, p.name, p.near = marker.kind, mx, my, marker.heading, marker.name, marker.near;
            if marker.kind == 'player' then
                playerAt.mx, playerAt.my = mx, my;
            end
        end
    end
    for i = #placed, count + 1, -1 do
        placed[i] = nil;
    end
end

local function Look()
    local zone = Zone();
    if zone ~= current.zone then
        current.zone, current.chosen, current.here = zone, nil, nil;
        markers.Forget();
        view.Reset(state);
    end
    if zone == nil or zone == 0 then
        current.why = 'no zone';
        return;
    end
    if markers.Refresh(zone) then
        Place();
    end
    if app.options.askServer[1] then
        markers.Ask(zone);
    end
end

-- Drawing

local canvas = { 0, 0 };
local REACH = 8; -- pixels from a marker the mouse is still over it

local function Status()
    local shown = Shown();
    if shown == nil then
        return current.zone and ('No map: no map is known for %s.'):format(ZoneName(current.zone)) or 'No map: no zone.';
    end
    local said = ('%s, floor %d (%s)'):format(ZoneName(current.zone), shown.floor, shown.dat);
    local entry, why = maps.Entry(shown, current.zone);
    if entry == nil then said = said .. '; nobody can be placed on it: ' .. tostring(why); end
    if current.here == nil then said = said .. '; the player\'s floor: ' .. tostring(current.why); end
    local _, missing = maps.Texture(shown);
    if missing ~= nil then said = said .. '; no picture: ' .. missing; end
    return said;
end

-- The floor picked: one of the zone's, or nil to follow the player's again
local function Choose(floor)
    current.chosen = floor;
    view.Reset(state);
    if floor ~= nil then view.Follow(state, false); end
    Place();
end

-- The zone's next floor after the one picked, then back to following the player's
local function NextFloor()
    local floors = current.zone and maps.Floors(current.zone) or nil;
    if floors == nil or #floors < 2 then
        return;
    end
    if current.chosen == nil then
        Choose(floors[1].floor);
        return;
    end
    for i, map in ipairs(floors) do
        if map.floor == current.chosen then
            Choose(floors[i + 1] and floors[i + 1].floor or nil);
            return;
        end
    end
    Choose(nil);
end

local function Floors(floors, shown)
    if floors == nil or #floors < 2 then
        return;
    end
    if imgui.SmallButton(current.chosen == nil and '[Auto]##atlas.auto' or 'Auto##atlas.auto') then
        Choose(nil);
    end
    tips.Hover('Follow the floor you are on.');
    for i, map in ipairs(floors) do
        imgui.SameLine();
        local label = shown ~= nil and map.floor == shown.floor and ('[%d]'):format(i) or tostring(i);
        if imgui.SmallButton(('%s##atlas.floor%d'):format(label, i)) then
            Choose(map.floor);
        end
    end
end

local function Hovered(mx, my, entry, size)
    local lines = { maps.Square(mx, my) };
    if entry ~= nil then
        local x, y = maps.ToWorld(entry, mx, my);
        lines[1] = ('%s  (%d, %d)'):format(lines[1], math.floor(x + 0.5), math.floor(y + 0.5));
    end
    local unit = size / (view.Size / state.zoom);
    for _, marker in ipairs(scene.markers) do
        local dx, dy = (marker.mx - mx) * unit, (marker.my - my) * unit;
        if dx * dx + dy * dy <= REACH * REACH and marker.name ~= nil and marker.name ~= '' then
            lines[#lines + 1] = marker.near and marker.name or (marker.name .. ' (far off)');
        end
    end
    tips.Show(table.concat(lines, '\n'));
end

local lastFrame = nil;

-- where the window was last drawn, so that the mouse over it brings back a map faded out of sight
local windowRect = { nil, nil, nil, nil };

local function MouseOverWindow()
    if windowRect[1] == nil then return false; end
    local mx, my = imgui.GetMousePos();
    return mx ~= nil and my ~= nil and mx >= windowRect[1] and my >= windowRect[2] and mx < windowRect[3] and my < windowRect[4];
end

local function Draw()
    local options = app.options;
    local now = os.clock();
    local wx, wy = imgui.GetWindowPos();
    local ww, wh = imgui.GetWindowSize();
    windowRect[1], windowRect[2], windowRect[3], windowRect[4] = wx, wy, wx + ww, wy + wh;
    pad.Frame(lastFrame and now - lastFrame or 0);
    lastFrame = now;
    Look();
    local zone = current.zone;
    if zone == nil or zone == 0 then
        imgui.Text('No zone.');
        return;
    end
    local floors = maps.Floors(zone);
    local shown = Shown();
    imgui.Text(ZoneName(zone));
    if floors ~= nil and #floors > 1 then
        imgui.SameLine();
        Floors(floors, shown);
    end

    local size = options.size[1];
    local x, y = imgui.GetCursorScreenPos();
    canvas[1], canvas[2] = size, size;
    imgui.InvisibleButton('##atlas.canvas', canvas);
    local hovered, active = imgui.IsItemHovered(), imgui.IsItemActive();
    view.Input(state, x, y, size, hovered, active);
    if current.chosen == nil and playerAt.mx ~= nil then
        view.Track(state, playerAt.mx, playerAt.my);
    end
    scene.picture = shown and maps.Texture(shown) or nil;
    local mx, my = view.Draw(imgui.GetWindowDrawList(), state, x, y, size, scene, options);
    if hovered and mx ~= nil and shown ~= nil then
        Hovered(mx, my, maps.Entry(shown, zone), size);
    end

    if imgui.SmallButton('-##atlas.zoomOut') then view.Zoom(state, state.zoom / 1.25, state.cx, state.cy); end
    imgui.SameLine();
    imgui.Text(('%.1fx'):format(state.zoom));
    imgui.SameLine();
    if imgui.SmallButton('+##atlas.zoomIn') then view.Zoom(state, state.zoom * 1.25, state.cx, state.cy); end
    imgui.SameLine();
    if imgui.SmallButton((state.follow and '[Follow]' or 'Follow') .. '##atlas.follow') then
        view.Follow(state, not state.follow);
    end
    tips.Hover('Keep yourself in the middle of the map. Dragging the map stops it.');
    imgui.SameLine();
    if imgui.SmallButton('Whole Map##atlas.reset') then view.Reset(state); end
    if playerAt.mx ~= nil then
        imgui.SameLine();
        imgui.Text(maps.Square(playerAt.mx, playerAt.my));
    end
    if shown == nil then
        imgui.TextDisabled('No map is known for this zone.');
    end
    if pad.Browsing() then
        imgui.TextDisabled(pad.Hint());
    end
end

-- Settings

local function Show(label, key, colourKey, tip)
    local options = app.options;
    widgets.Label(label);
    imgui.Checkbox('##atlas.' .. key, options[key]);
    if tip then tips.Hover(tip); end
    imgui.SameLine();
    imgui.ColorEdit4('##atlas.' .. colourKey, options[colourKey], ImGuiColorEditFlags_NoInputs);
end

local controllerTip = '/atlas browse (from a macro) gives the map the controller, as the game\'s own map has it:\n'
    .. 'the d-pad scrolls, RB zooms in and LB out, A follows you again, X shows the next floor, and B gives it back.\n'
    .. 'The left stick still walks your character, unless Stick Scrolls Map is on.';

local function DrawSettings(options)
    if widgets.Header('Window') then
        widgets.Label('Visible');
        imgui.Checkbox('##atlas.visible', options.isVisible);
        tips.Hover('Whether the map shows. /atlas switches this.');
        widgets.Lock(options.locked, '##atlas.locked', { tooltip = 'Keeps the window where it is. The map can still be panned and zoomed.' });
        widgets.PushControlWidth();
        widgets.Label('Map Size');
        imgui.SliderInt('##atlas.size', options.size, 256, 1024, '%d px');
        widgets.PopControlWidth();
        widgets.Label('Fade While Moving');
        imgui.Checkbox('##atlas.fadeWhileMoving', options.fadeWhileMoving);
        tips.Hover('The map fades while your character moves, and comes back as you stop.\nThe mouse over the map, or browsing it with the controller, shows it whole.');
        if options.fadeWhileMoving[1] then
            widgets.PushControlWidth();
            widgets.Label('Moving Opacity');
            imgui.SliderInt('##atlas.movingOpacity', options.movingOpacity, 0, 100, '%d%%');
            tips.Hover('How much of the map shows while you move. At 0% it is gone until you stop.');
            widgets.PopControlWidth();
        end
    end

    if widgets.Header('Markers') then
        Show('Show Player', 'showPlayer', 'playerColor', 'You, as an arrow the way you face.');
        Show('Show Party', 'showParty', 'partyColor', 'Your party. One out of sight, placed by the server, is drawn hollow.');
        Show('Show Alliance', 'showAlliance', 'allianceColor', 'The alliance\'s other parties.');
        Show('Show Target', 'showTarget', 'targetColor', 'What you have targeted.');
        widgets.Label('Show Names');
        imgui.Checkbox('##atlas.showNames', options.showNames);
        tips.Hover('Names beside the party, the alliance and the target.');
        widgets.PushControlWidth();
        widgets.Label('Marker Size');
        imgui.SliderInt('##atlas.markerSize', options.markerSize, 4, 24, '%d px');
        widgets.PopControlWidth();
    end

    if widgets.Header('Party') then
        widgets.Label('Party Across Zone');
        imgui.Checkbox('##atlas.askServer', options.askServer);
        tips.Hover('Asks the server where your party is while one of them is in the zone and out of sight, as the game\'s own map does while it is open, every few seconds.');
    end

    if widgets.Header('Controller') then
        shell.ControllerSettings(options, controllerTip, function()
            widgets.Label('Stick Scrolls Map');
            imgui.Checkbox('##atlas.stickScrolls', options.stickScrolls);
            tips.Hover('While browsing, the left stick scrolls the map, faster the further it is pushed, and your character does not walk.\nOff, the stick walks your character as ever while the d-pad scrolls. The stick is read from the kind of controller Controller Type names.');
        end);
    end

    imgui.TextWrapped(Status());
end

app = shell.New({
    defaults = defaults,
    window = 'winxi.atlas',
    configTitle = 'Atlas Settings',
    hideHeader = 'Visibility',
    command = '/atlas',
    help = '/atlas shows or hides the map; /atlas config opens the settings; /atlas status says which map is drawn; /atlas browse gives it the controller.',
    drawSettings = DrawSettings,
    commands = {
        status = function() Look(); app:Say(Status()); end,
        browse = function(options)
            if not options.controller[1] then
                app:Say('Controller Navigation is off in /atlas config.');
                return;
            end
            pad.Browse();
        end,
    },
});

pad.Attach({
    options = function() return app.options; end,
    state = state,
    floor = NextFloor,
    shown = function(on) app.options.isVisible[1] = on; end,
});

local extra = { locked = false };

ashita.events.register('d3d_present', 'atlas_present', function()
    -- hidden with the controller in hand: given back
    if pad.Browsing() and not app.options.isVisible[1] then pad.Browse(false); end
    if not app:BeginFrame() then return; end
    extra.locked = app.options.locked[1];
    extra.alpha = moving.Update(app.options, pad.Browsing() or MouseOverWindow());
    app:Window(app.options.isVisible, Draw, extra);
end);

ashita.events.register('packet_in', 'atlas_packet', function(e)
    markers.Packet(e.id, e.data);
end);
