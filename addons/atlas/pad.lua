-- Working the map with a controller, as the game's own map is worked: browsing takes the controller
-- until it is given back.
--
--   pad.Attach(spec)     spec = { options = function() ... end, state = <view state>,
--                        floor = function() ... end (the next floor), shown = function(on) ... end
--                        (shows or hides the map), mark = function(mx, my) ... end (the reticle's
--                        place on the map, for a waypoint: Y) }
--   pad.Browse(on, keep) takes the controller for the map, or gives it back; nil switches. Given back
--                        with keep, the map stays shown even if browsing opened it
--   pad.Browsing()       whether the map has the controller
--   pad.Frame(dt)        while drawing the map: the sticks for this frame, and the window marked
--   pad.Reticle()        the reticle's place on the map while browsing, in map units, or nil
--   pad.Hint()           what the buttons do, for under the map while browsing
--
-- While browsing: the left stick and the d-pad scroll, RB zooms in a step and LB out (1x, 1.5x, 2x,
-- 3x, 4x, 6x, 8x), the right stick moves a reticle over the map and Y puts a waypoint there, A follows
-- you again, X shows the zone's next floor, and B gives the controller back (hiding the map again, if
-- browsing opened it). Both sticks are kept from the game while browsing, so you do not walk off or
-- turn the camera; each is let through as it comes back to the middle, and the game is told both are
-- centred as browsing begins. The triggers are left alone: a crossbar (tcrossbar) keeps them, and
-- while one is held the buttons are its, for its macros.
--
-- The buttons go through winxi.controller, XInput or DirectInput by Controller Type, and the sticks are
-- read from the same kind. XInput's axes come as buttons 18 and 19 (the left stick across and up and
-- down) and 20 and 21 (the right), each -32768 to 32767, up the more; DirectInput's as 0 and 4 (the
-- left) and 8 and 20 (the right), each -128 to 127, down the more.
local controller = require('winxi.controller');
local sound = require('winxi.sound');
local view = require('view');
local pad = {};

-- The sticks' axes on each kind of controller: their button numbers (left stick across and up and
-- down, then the right's), how far each goes, and whether up is more
local XINPUT = { x = 18, y = 19, rx = 20, ry = 21, reach = 32767, up = 1 };
local DINPUT = { x = 0, y = 4, rx = 8, ry = 20, reach = 127, up = -1 };
local DEAD = 0.25;         -- of the stick's reach: its middle, where it does nothing
local STICK_SPEED = 0.9;   -- the view's width a second, at the stick's edge
local RETICLE_SPEED = 0.6; -- the square's width a second the reticle moves, at the right stick's edge
local STEP = 0.1;          -- the view's width a d-pad press scrolls
local LEVELS = { 1, 1.5, 2, 3, 4, 6, 8 }; -- the zoom a bumper steps through
local FRESH = 0.25;        -- seconds the map can go undrawn and still have the controller

local spec = nil;
local browsing, opened = false, false;
local drawn = -1;
local stick = { x = 0, y = 0, rx = 0, ry = 0 }; -- -1 to 1, up the more, read from whichever kind is in use
local reticle = { u = 0.5, v = 0.5 }; -- where the reticle is in the square, 0 to 1 across and down

local B = controller.Button;
local actions = {
    [B.DpadUp] = 'up', [B.DpadDown] = 'down', [B.DpadLeft] = 'left', [B.DpadRight] = 'right',
    [B.RB] = 'zoomIn', [B.LB] = 'zoomOut', [B.A] = 'follow', [B.X] = 'floor', [B.B] = 'back', [B.Y] = 'mark',
};
local repeats = { up = true, down = true, left = true, right = true };

local function Active()
    if not browsing or spec == nil then
        return false;
    end
    local options = spec.options();
    return options.controller[1] and options.isVisible[1] and os.clock() - drawn < FRESH or false;
end

local function Span()
    return view.Size / spec.state.zoom;
end

local function DirectInput()
    return controller.GetLayout() ~= 'xinput';
end

-- The game is told the sticks are in the middle, so that whoever was walking stops, and the camera
local function Centre()
    pcall(function()
        local input = AshitaCore:GetInputManager();
        local kind = DirectInput() and DINPUT or XINPUT;
        local device = DirectInput() and input:GetController() or input:GetXInput();
        for _, axis in ipairs({ 'x', 'y', 'rx', 'ry' }) do
            if stick[axis] ~= 0 then device:QueueButtonData(kind[axis], 0); end
        end
    end);
end

-- The zoom level next above (step 1) or below (-1) the zoom now
local function Level(zoom, step)
    if step > 0 then
        for _, level in ipairs(LEVELS) do
            if level > zoom + 0.001 then return level; end
        end
        return LEVELS[#LEVELS];
    end
    for i = #LEVELS, 1, -1 do
        if LEVELS[i] < zoom - 0.001 then return LEVELS[i]; end
    end
    return LEVELS[1];
end

function pad.Browse(on, keep)
    if on == nil then on = not browsing; end
    if on == browsing then
        return;
    end
    local options = spec.options();
    if on then
        browsing, opened = true, not options.isVisible[1];
        if opened then spec.shown(true); end
        drawn = os.clock(); -- has the controller from now, before the map is first drawn
        reticle.u, reticle.v = 0.5, 0.5;
        Centre();
    else
        browsing = false;
        if opened and not keep then spec.shown(false); end
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
    elseif action == 'zoomIn' then view.Zoom(state, Level(state.zoom, 1), state.cx, state.cy);
    elseif action == 'zoomOut' then view.Zoom(state, Level(state.zoom, -1), state.cx, state.cy);
    elseif action == 'mark' then spec.mark(pad.Reticle()); sound.Play('confirm');
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
    dt = math.min(dt, 0.1);
    local x, y = Push(stick.x), Push(stick.y);
    if x ~= 0 or y ~= 0 then
        local reach = Span() * STICK_SPEED * dt;
        view.Pan(spec.state, x * reach, -y * reach); -- the stick's up is more, the map's up is less
    end
    local rx, ry = Push(stick.rx), Push(stick.ry);
    if rx ~= 0 or ry ~= 0 then
        local reach = RETICLE_SPEED * dt;
        reticle.u = math.max(0, math.min(1, reticle.u + rx * reach));
        reticle.v = math.max(0, math.min(1, reticle.v - ry * reach));
    end
end

function pad.Reticle()
    if not Active() then
        return nil;
    end
    local state, span = spec.state, Span();
    return state.cx + (reticle.u - 0.5) * span, state.cy + (reticle.v - 0.5) * span;
end

function pad.Hint()
    return 'L Stick, D-Pad: Scroll   LB/RB: Zoom   R Stick: Aim   Y: Waypoint   A: Follow   X: Floor   B: Done';
end

function pad.Attach(given)
    spec = given;
end

local vertical = { y = true, ry = true };

-- An axis of a stick moved, on the kind of controller given
local function Axis(kind, e)
    local axis = (e.button == kind.x and 'x') or (e.button == kind.y and 'y')
        or (e.button == kind.rx and 'rx') or (e.button == kind.ry and 'ry') or nil;
    if axis == nil then
        return;
    end
    local value = math.max(-1, math.min(1, e.state / kind.reach));
    stick[axis] = vertical[axis] and value * kind.up or value;
    -- kept from the game while browsing, but for its coming back to the middle
    if e.state ~= 0 and Active() then
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
