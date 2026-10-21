-- Working the map with a controller, as the game's own map is worked: browsing takes the controller
-- until it is given back.
--
--   pad.Attach(spec)     spec = { options = function() ... end, state = <view state>,
--                        floor = function() ... end (the next floor), shown = function(on) ... end
--                        (shows or hides the map) }
--   pad.Browse(on)       takes the controller for the map, or gives it back; nil switches
--   pad.Browsing()       whether the map has the controller
--   pad.Frame(dt)        while drawing the map: the stick's pan for this frame, and the window marked
--   pad.Hint()           what the buttons do, for under the map while browsing
--
-- While browsing: the d-pad and the left stick scroll, RB zooms in and LB out, A follows you again,
-- X shows the zone's next floor, and B gives the controller back (hiding the map again, if browsing
-- opened it). The left stick walks your character as ever, unless Stick Scrolls Map is on: then it
-- scrolls, and is kept from the game while browsing, so you do not walk off; it is let through as it
-- comes back to the middle, and centred for the game as browsing begins. The triggers are left alone:
-- a crossbar (tcrossbar) keeps them, and while one is held the buttons are its, for its macros.
--
-- The buttons go through winxi.controller, XInput or DirectInput by Controller Type, and the stick is
-- read from the same kind. XInput's axes come as buttons 18 (across) and 19 (up and down), each -32768
-- to 32767, up the more; DirectInput's as 0 (across) and 4 (up and down), each -128 to 127, down the
-- more.
local controller = require('winxi.controller');
local sound = require('winxi.sound');
local view = require('view');
local pad = {};

-- The left stick's axes on each kind of controller: their button numbers, how far each goes, and
-- whether up is more
local XINPUT = { x = 18, y = 19, reach = 32767, up = 1 };
local DINPUT = { x = 0, y = 4, reach = 127, up = -1 };
local DEAD = 0.25;         -- of the stick's reach: its middle, where it does nothing
local STICK_SPEED = 0.9;   -- the view's width a second, at the stick's edge
local STEP = 0.1;          -- the view's width a d-pad press scrolls
local ZOOM_STEP = 1.25;
local FRESH = 0.25;        -- seconds the map can go undrawn and still have the controller

local spec = nil;
local browsing, opened = false, false;
local drawn = -1;
local stick = { x = 0, y = 0 }; -- -1 to 1, up the more, read from whichever kind is in use

local B = controller.Button;
local actions = {
    [B.DpadUp] = 'up', [B.DpadDown] = 'down', [B.DpadLeft] = 'left', [B.DpadRight] = 'right',
    [B.RB] = 'zoomIn', [B.LB] = 'zoomOut', [B.A] = 'follow', [B.X] = 'floor', [B.B] = 'back',
};
local repeats = { up = true, down = true, left = true, right = true, zoomIn = true, zoomOut = true };

local function Active()
    if not browsing or spec == nil then
        return false;
    end
    local options = spec.options();
    return options.controller[1] and options.isVisible[1] and os.clock() - drawn < FRESH or false;
end

-- whether the left stick is the map's while browsing, not the character's
local function StickScrolls()
    local option = spec.options().stickScrolls;
    return option ~= nil and option[1] == true;
end

local function Span()
    return view.Size / spec.state.zoom;
end

local function DirectInput()
    return controller.GetLayout() ~= 'xinput';
end

-- The game is told the stick is in the middle, so that whoever was walking stops
local function Centre()
    pcall(function()
        local input = AshitaCore:GetInputManager();
        local kind = DirectInput() and DINPUT or XINPUT;
        local device = DirectInput() and input:GetController() or input:GetXInput();
        device:QueueButtonData(kind.x, 0);
        device:QueueButtonData(kind.y, 0);
    end);
end

function pad.Browse(on)
    if on == nil then on = not browsing; end
    if on == browsing then
        return;
    end
    local options = spec.options();
    if on then
        browsing, opened = true, not options.isVisible[1];
        if opened then spec.shown(true); end
        drawn = os.clock(); -- has the controller from now, before the map is first drawn
        if StickScrolls() and (stick.x ~= 0 or stick.y ~= 0) then Centre(); end
    else
        browsing = false;
        if opened then spec.shown(false); end
        opened = false;
    end
end

function pad.Browsing()
    return browsing;
end

local function Press(action)
    local state = spec.state;
    local step = Span() * STEP;
    if action == 'up' then view.Pan(state, 0, -step);
    elseif action == 'down' then view.Pan(state, 0, step);
    elseif action == 'left' then view.Pan(state, -step, 0);
    elseif action == 'right' then view.Pan(state, step, 0);
    elseif action == 'zoomIn' then view.Zoom(state, state.zoom * ZOOM_STEP, state.cx, state.cy);
    elseif action == 'zoomOut' then view.Zoom(state, state.zoom / ZOOM_STEP, state.cx, state.cy);
    elseif action == 'follow' then view.Follow(state, true); sound.Play('confirm');
    elseif action == 'floor' then spec.floor(); sound.Play('tab');
    elseif action == 'back' then sound.Play('back'); pad.Browse(false);
    end
end

local binding = controller.Bind({ active = Active, actions = actions, repeats = repeats, press = Press, passTriggers = true });

-- How far the stick is pushed, past its middle: -1 to 1
local function Push(value)
    if math.abs(value) <= DEAD then
        return 0;
    end
    local sign = value > 0 and 1 or -1;
    return sign * math.min(1, (math.abs(value) - DEAD) / (1 - DEAD));
end

function pad.Frame(dt)
    local options = spec.options();
    if options.controllerType ~= nil and options.controllerType ~= controller.GetLayout() then
        controller.SetLayout(options.controllerType);
    end
    sound.SetEnabled(options.controllerSounds[1]);
    if browsing then
        drawn = os.clock();
    end
    if not Active() then
        return;
    end
    controller.Highlight(binding);
    if not StickScrolls() then
        return;
    end
    local x, y = Push(stick.x), Push(stick.y);
    if x ~= 0 or y ~= 0 then
        local reach = Span() * STICK_SPEED * math.min(dt, 0.1);
        view.Pan(spec.state, x * reach, -y * reach); -- the stick's up is more, the map's up is less
    end
end

function pad.Hint()
    if not StickScrolls() then
        return 'D-Pad: Scroll   LB/RB: Zoom   A: Follow   X: Floor   B: Done';
    end
    return 'D-Pad, Stick: Scroll   LB/RB: Zoom   A: Follow   X: Floor   B: Done';
end

function pad.Attach(given)
    spec = given;
end

-- An axis of the stick moved, on the kind of controller given
local function Axis(kind, e)
    local axis = (e.button == kind.x and 'x') or (e.button == kind.y and 'y') or nil;
    if axis == nil then
        return;
    end
    local value = math.max(-1, math.min(1, e.state / kind.reach));
    stick[axis] = axis == 'y' and value * kind.up or value;
    -- kept from the game while browsing, but for its coming back to the middle
    if e.state ~= 0 and Active() and StickScrolls() then
        e.blocked = true;
    end
end

ashita.events.register('xinput_button', 'atlas_stick', function(e)
    if not DirectInput() then Axis(XINPUT, e); end
end);

ashita.events.register('dinput_button', 'atlas_stick_dinput', function(e)
    if DirectInput() then Axis(DINPUT, e); end
end);

return pad;
