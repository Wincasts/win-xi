addon.name    = 'atlas';
addon.author  = 'win';
addon.version = '0.13';
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
--   /atlas cycle     the next of hidden, open (browsing, as /atlas browse) and passthrough (shown, the
--                    controller the game's, faded to Passthrough Opacity while you move), then hidden
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
    -- the map's frame in each mode: open (browsing, or shown by /atlas) and passthrough
    openWidth = T{ 512 },
    openHeight = T{ 512 },
    openShape = 'square',   -- 'square', 'rounded' or 'round'
    passthroughWidth = T{ 512 },
    passthroughHeight = T{ 512 },
    passthroughShape = 'square',
    passthroughOpacity = T{ 30 },
    zoneZoom = T{}, -- zone id (as a string) -> last zoom, shared by that zone's floors
    showPlayer = T{ true },
    playerColor = T{ 1.00, 0.85, 0.20, 1.00 },
    showParty = T{ true },
    partyColor = T{ 0.35, 0.80, 1.00, 1.00 },
    showAlliance = T{ true },
    allianceColor = T{ 0.55, 0.95, 0.45, 1.00 },
    showTarget = T{ true },
    targetColor = T{ 1.00, 0.35, 0.30, 1.00 },
    markerSize = T{ 9 },
    playerStyle = 'arrow',
    partyStyle = 'dot',
    allianceStyle = 'dot',
    playerSize = T{ 0 }, -- 0 inherits Marker Size, preserving existing settings
    partySize = T{ 0 },
    allianceSize = T{ 0 },
    playerOutline = T{ true },
    partyOutline = T{ true },
    allianceOutline = T{ true },
    showNames = T{ true },
    namesOnHover = T{ false },
    askServer = T{ true },
    controller = T{ true },
    analogStick = T{ true }, -- off: use the d-pad to pan instead of the left stick
    controllerSounds = T{ false },
    controllerType = 'xinput', -- which kind: a key of winxi.controller's Layouts
};

local app;
local state = view.New();

-- Whether the map is in passthrough, as /atlas cycle leaves it: shown, with the controller the game's
local passing = false;
-- Keep the last visible frame's shape/size while the shell fades the window out.
local drawnPassing = false;

-- The waypoint put down under the controller's cursor (Y while browsing): its zone, floor and place
-- on that floor's map, or nil. Forgotten as the zone changes.
local waypoint = nil;

-- Which map

-- zone: the zone the player is in; chosen: a floor's id picked over the map, or nil to follow the
-- player's; here: the map the player is on, and why not where none
local current = { zone = nil, chosen = nil, here = nil, why = 'not looked yet' };
local scene = { picture = nil, markers = {} };
local playerAt = { mx = nil, my = nil }; -- the player's place on the map shown, or nil
local cursorAt = { mx = nil, my = nil }; -- the controller's cursor, while browsing

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
            p.slot = marker.slot;
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
        waypoint = nil;
        markers.Forget();
        view.Reset(state);
        local zoom = tonumber(app.options.zoneZoom[tostring(zone)]);
        if zoom ~= nil and zoom > 0 then view.Zoom(state, zoom); end
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
    local zoom = state.zoom;
    view.Reset(state);
    view.Zoom(state, zoom); -- floors share the zone's zoom; only the pan/follow choice is reset
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

local function Hovered(mx, my, entry)
    local lines = { maps.Square(mx, my) };
    if entry ~= nil then
        local x, y = maps.ToWorld(entry, mx, my);
        lines[1] = ('%s  (%d, %d)'):format(lines[1], math.floor(x + 0.5), math.floor(y + 0.5));
    end
    local unit = 1 / view.Units(state, 1);
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

local controlsAir = { 0, 5 }; -- between the map and the controls under it

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
    if floors ~= nil and #floors > 1 then
        Floors(floors, shown);
    end

    local mode = drawnPassing and 'passthrough' or 'open';
    local w, h = options[mode .. 'Width'][1], options[mode .. 'Height'][1];
    view.Frame(state, w, h);
    local x, y = imgui.GetCursorScreenPos();
    canvas[1], canvas[2] = w, h;
    imgui.InvisibleButton('##atlas.canvas', canvas);
    local hovered, active = imgui.IsItemHovered(), imgui.IsItemActive();
    view.Input(state, x, y, hovered, active);
    if current.chosen == nil and playerAt.mx ~= nil then
        view.Track(state, playerAt.mx, playerAt.my);
    end
    scene.picture = shown and maps.Texture(shown) or nil;
    scene.waypoint = nil;
    if waypoint ~= nil and shown ~= nil and waypoint.zone == zone and waypoint.floor == shown.floor then
        scene.waypoint = waypoint;
    end
    scene.cursor = nil;
    local cx, cy = pad.Cursor();
    if cx ~= nil then
        cursorAt.mx, cursorAt.my = cx, cy;
        scene.cursor = cursorAt;
    end
    local mx, my = view.Draw(imgui.GetWindowDrawList(), state, x, y, scene, options, options[mode .. 'Shape']);
    if hovered and mx ~= nil and shown ~= nil then
        Hovered(mx, my, maps.Entry(shown, zone));
    end

    imgui.Dummy(controlsAir); -- breathing room between the map and its controls
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
    if scene.waypoint ~= nil then
        imgui.SameLine();
        imgui.Text('Waypoint ' .. maps.Square(scene.waypoint.mx, scene.waypoint.my));
    end
    if shown == nil then
        imgui.TextDisabled('No map is known for this zone.');
    end
    if pad.Browsing() then
        imgui.TextDisabled(pad.Hint());
    end
end

-- Settings

-- Show <kind>: its checkbox and the colour of its markers, together at the right of one row
local function Show(label, key, colourKey, sentence)
    local options = app.options;
    widgets.BeginRow(label, sentence);
    imgui.Checkbox('##atlas.' .. key, options[key]);
    imgui.SameLine();
    imgui.ColorEdit4('##atlas.' .. colourKey, options[colourKey], ImGuiColorEditFlags_NoInputs);
    widgets.EndRow();
end

local playerStyles = {
    { key = 'arrow', label = 'Arrow' }, { key = 'chevron', label = 'Chevron' },
    { key = 'dotFacing', label = 'Dot + facing line' }, { key = 'ringArrow', label = 'Ring + arrow' },
};
local memberStyles = {
    { key = 'dot', label = 'Dot' }, { key = 'triangle', label = 'Directional triangle' },
    { key = 'hollow', label = 'Hollow circle' }, { key = 'numbered', label = 'Numbered dot' },
};
local markerSpecs = {}; -- kind -> the specs of its rows, under its Show checkbox

local function MarkerSettings(kind, label, showKey, styles)
    local options = app.options;
    local specs = markerSpecs[kind];
    if specs == nil then
        specs = {
            style = {},
            size = { format = '%d px' },
            outline = {},
            names = { label .. ' Style', label .. ' Size', label .. ' Outline', '##atlas.' .. kind .. 'Style', '##atlas.' .. kind .. 'Size', '##atlas.' .. kind .. 'Outline' },
        };
        markerSpecs[kind] = specs;
    end
    specs.style.parent, specs.size.parent, specs.outline.parent = options[showKey], options[showKey], options[showKey];
    local names = specs.names;
    local key = kind .. 'Style';
    local chosen = widgets.Dropdown(names[1], 'The shape of these markers.', styles, options[key], names[4], specs.style);
    if chosen ~= nil then options[key] = chosen; end
    widgets.Slider(names[2], 'How big these markers are. 0 uses Marker Size below.', options[kind .. 'Size'], 0, 24, names[5], specs.size);
    widgets.Check(names[3], 'A dark edge round these markers.', options[kind .. 'Outline'], names[6], specs.outline);
end

local shapes = { { key = 'square', label = 'Square' }, { key = 'rounded', label = 'Rounded' }, { key = 'round', label = 'Round' } };
local frameSentences = {}; -- mode -> the sentences of its rows, made once

-- A mode's frame: its width, height and shape. when says when the mode is in use, for the sentences.
local function Frame(mode, when)
    local options = app.options;
    local sentences = frameSentences[mode];
    if sentences == nil then
        sentences = { ('How wide the map is %s.'):format(when), ('How tall the map is %s.'):format(when),
            '##atlas.' .. mode .. 'Width', '##atlas.' .. mode .. 'Height', '##atlas.' .. mode .. 'Shape' };
        frameSentences[mode] = sentences;
    end
    widgets.Slider('Width', sentences[1], options[mode .. 'Width'], 128, 1024, sentences[3], widgets.Pixels);
    widgets.Slider('Height', sentences[2], options[mode .. 'Height'], 128, 1024, sentences[4], widgets.Pixels);
    local key = mode .. 'Shape';
    local chosen = widgets.Dropdown('Shape', 'Square, rounded corners, or round. Round is a circle when width and height match, and a pill when not.', shapes, options[key], sentences[5]);
    if chosen ~= nil then options[key] = chosen; end
end

local controllerTip = '/atlas browse (from a macro) gives the map the controller, as the game default map has it:\n'
    .. 'the left stick scrolls (or the d-pad with Analog Stick Control off), RB zooms in a step and LB out,\n'
    .. 'Y puts a waypoint under the cursor, A locks the map to you, X shows the next floor, and B gives it back.\n'
    .. 'The right stick and the unused scrolling control stay the game\'s.';

local nameChoices = { { key = 'always', label = 'Always' }, { key = 'hover', label = 'On Hover' }, { key = 'hidden', label = 'Hidden' } };
local lockSpec = { description = 'Keeps the window where it is. The map can still be panned and zoomed.' };
local stickSpec = {};

local function DrawSettings(options)
    if widgets.Header('Window', true) then
        widgets.Check('Visible', 'Shows the map. /atlas switches it too.', options.isVisible, '##atlas.visible');
        widgets.Lock(options.locked, '##atlas.locked', lockSpec);
    end

    if widgets.Header('Open') then
        Frame('open', 'while it is open: shown by /atlas, or browsed with the controller');
    end

    if widgets.Header('Passthrough') then
        Frame('passthrough', 'in passthrough, the last step of /atlas cycle, when the controller is left to the game');
        widgets.Slider('Passthrough Opacity', 'How much of the map shows while you move in passthrough. It comes back as you stop.', options.passthroughOpacity, 0, 100, '##atlas.passthroughOpacity', widgets.Percent);
    end

    if widgets.Header('Markers') then
        widgets.Slider('Marker Size', 'How big the markers are, unless a kind below sets a size.', options.markerSize, 4, 24, '##atlas.markerSize', widgets.Pixels);
        local names = not options.showNames[1] and 'hidden' or (options.namesOnHover[1] and 'hover' or 'always');
        local chosen = widgets.Dropdown('Names', 'When names are written beside party, alliance and target markers.', nameChoices, names, '##atlas.names');
        if chosen ~= nil then
            options.showNames[1], options.namesOnHover[1] = chosen ~= 'hidden', chosen == 'hover';
        end
        if widgets.SubHeader('Player') then
            Show('Show Player', 'showPlayer', 'playerColor', 'You, and which way you are facing.');
            MarkerSettings('player', 'Player', 'showPlayer', playerStyles);
        end
        if widgets.SubHeader('Party') then
            Show('Show Party', 'showParty', 'partyColor', 'Your party. One out of sight is drawn hollow, where the server says it is.');
            MarkerSettings('party', 'Party', 'showParty', memberStyles);
        end
        if widgets.SubHeader('Alliance') then
            Show('Show Alliance', 'showAlliance', 'allianceColor', 'The alliance\'s other parties.');
            MarkerSettings('alliance', 'Alliance', 'showAlliance', memberStyles);
        end
        if widgets.SubHeader('Target') then
            Show('Show Target', 'showTarget', 'targetColor', 'What you have targeted.');
        end
        widgets.EndSub();
    end

    if widgets.Header('Party') then
        widgets.Check('Party Across Zone', 'Asks the server where party members out of sight are, every few seconds.', options.askServer, '##atlas.askServer');
    end

    if widgets.Header('Controller') then
        shell.ControllerSettings(options, controllerTip);
        stickSpec.parent = options.controller;
        widgets.Check('Analog Stick Control', 'The left stick scrolls the map while browsing. Off, the d-pad does.', options.analogStick, '##atlas.analogStick', stickSpec);
    end

    widgets.Status(Status());
end

app = shell.New({
    defaults = defaults,
    window = 'winxi.atlas',
    configTitle = 'Atlas Settings',
    command = '/atlas',
    help = '/atlas shows or hides the map; /atlas config opens the settings; /atlas status says which map is drawn; /atlas browse gives it the controller; /atlas cycle goes from hidden to open to passthrough.',
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
        -- hidden, then open (with the controller, if Controller Navigation is on), then passthrough;
        -- a map shown by /atlas, neither of those, is taken to open
        cycle = function(options)
            if not options.isVisible[1] then
                passing = false;
                if options.controller[1] then pad.Browse(true); else options.isVisible[1] = true; end
            elseif passing then
                options.isVisible[1], passing = false, false;
            elseif pad.Browsing() or not options.controller[1] then
                pad.Browse(false, true);
                passing = true;
            else
                pad.Browse(true);
            end
        end,
    },
});

pad.Attach({
    options = function() return app.options; end,
    state = state,
    floor = NextFloor,
    shown = function(on) app.options.isVisible[1] = on; end,
    -- A: back to the player's floor, the map locked to them; the zoom kept
    follow = function()
        current.chosen = nil;
        view.Follow(state, true);
        Place();
    end,
    player = function() return playerAt.mx, playerAt.my; end,
    -- Y: a waypoint under the cursor, or none if the cursor is on the one there is
    mark = function(mx, my)
        local shown = Shown();
        if mx == nil or shown == nil then
            return;
        end
        if waypoint ~= nil and waypoint.zone == current.zone and waypoint.floor == shown.floor then
            local reach = view.Units(state, REACH);
            local dx, dy = waypoint.mx - mx, waypoint.my - my;
            if dx * dx + dy * dy <= reach * reach then
                waypoint = nil;
                return;
            end
        end
        waypoint = { zone = current.zone, floor = shown.floor, mx = mx, my = my };
    end,
});

local extra = { locked = false };
local zoomSaveAt = nil;

local function RememberZoom()
    local zone = current.zone;
    if zone ~= nil and zone ~= 0 then
        local key = tostring(zone);
        if app.options.zoneZoom[key] ~= state.zoom then
            app.options.zoneZoom[key] = state.zoom;
            zoomSaveAt = os.clock() + 0.75; -- debounce wheel/stick-button changes, not a disk write each frame
        end
    end
    if zoomSaveAt ~= nil and os.clock() >= zoomSaveAt then
        app:Save();
        zoomSaveAt = nil;
    end
end

ashita.events.register('d3d_present', 'atlas_present', function()
    -- hidden with the controller in hand: given back
    if pad.Browsing() and not app.options.isVisible[1] then pad.Browse(false); end
    -- passthrough ends as the map is hidden or browsed
    if passing and (pad.Browsing() or not app.options.isVisible[1]) then passing = false; end
    if not app:BeginFrame() then return; end
    extra.locked = app.options.locked[1];
    local over = MouseOverWindow();
    local hidden = not app.options.isVisible[1];
    if not hidden then drawnPassing = passing; end
    extra.alpha = moving.Update(passing, app.options.passthroughOpacity[1], over, hidden);
    local zone = Zone();
    app.windowStyle.title = zone ~= nil and zone ~= 0 and ZoneName(zone) or 'Atlas';
    app:Window(app.options.isVisible, Draw, extra);
    RememberZoom();
end);

ashita.events.register('packet_in', 'atlas_packet', function(e)
    markers.Packet(e.id, e.data);
end);
