-- winxi.controller: working an addon's windows with a controller, XInput or DirectInput.
--
-- The game reads the controller too, so an addon takes it only while it has reason to (a window of its
-- own is showing, say), and only the buttons it uses: those are kept from the game, and the sticks and
-- every other button still reach it. A press that an addon takes stays the addon's until the button is
-- let go, and a button already down when the addon takes the controller is not counted as a press, so
-- that the button which opened a window does not at once act in it.
--
-- Three pieces, to use together or apart:
--
--   controller.Bind(spec)      takes button presses and hands them to the addon as named actions
--   controller.NewGrid()       a highlight that moves over things drawn in rows (items, icons, slots)
--   controller.NewMenu(...)    a list of choices worked with up, down, confirm and back
--   controller.Label(...)      a floating box naming what the highlight is on
--
-- controller.Highlight(binding), called while drawing a window, marks it as the one the controller is
-- working, so that it can be told which window the buttons will act in.
--
-- While a binding has the controller the triggers are kept from the game as well, whether or not the
-- binding uses them (controller.BlockTriggers), and every other addon is told: a plugin event named
-- controller.FocusEvent goes out, carrying the addon's name and whether it has the controller, when
-- that changes and once a second while it has. An addon with a controller of its own listens for it
-- and stands down; controller.OtherHasFocus() is the same asked of other winxi addons.
--
-- The grid and the menu make the sounds of winxi.sound as they are worked, once an addon turns those on,
-- and a binding makes the open sound as it takes the controller: as its window opens.
--
-- Binding buttons:
--
--     local binding = controller.Bind({
--         active  = function() return myWindowIsShowing end,   -- whether the addon wants the controller now
--         actions = controller.StandardActions(),             -- button -> action name
--         repeats = controller.StandardRepeats(),             -- action name -> true: repeats while held
--         press   = function(action) ... end,                 -- an action's button was pressed, or repeated
--     });
--
-- The standard actions are up, down, left, right (the d-pad), confirm (A), back (B), sort (X, the
-- square on a PlayStation controller: for putting what the window shows in order), previous (LB) and
-- next (RB). Any table of controller.Button values to names will do in their place. Where several
-- bindings want the same button, the one bound first that is active gets it.
--
-- The buttons are named as an Xbox controller's are, whatever the controller. XInput reports them that
-- way. DirectInput numbers them differently on each make of controller, so for one of those the addon
-- says which it is with controller.SetLayout (controller.Layouts lists the choices), and its buttons
-- are read as the Xbox buttons in the same positions: the bottom face button is A, and so on.
local bit = require('bit');
local imgui = require('imgui');
local sound = require('winxi.sound');

local controller = {};

-- The buttons, by their Xbox names, as XInput numbers them in Ashita's xinput_button event
controller.Button = {
    DpadUp = 0, DpadDown = 1, DpadLeft = 2, DpadRight = 3,
    Start = 4, Back = 5, L3 = 6, R3 = 7,
    LB = 8, RB = 9,
    A = 12, B = 13, X = 14, Y = 15,
};

-- Seconds a button is held before its action repeats, and between repeats
controller.RepeatDelay = 0.35;
controller.RepeatRate = 0.08;

function controller.StandardActions()
    local button = controller.Button;
    return {
        [button.DpadUp] = 'up', [button.DpadDown] = 'down', [button.DpadLeft] = 'left', [button.DpadRight] = 'right',
        [button.A] = 'confirm', [button.B] = 'back', [button.X] = 'sort',
        [button.LB] = 'previous', [button.RB] = 'next',
    };
end

function controller.StandardRepeats()
    return { up = true, down = true, left = true, right = true };
end

-- The triggers are not buttons of the kind bindings take, but a window that has the controller does
-- not want them working the game's macros behind it: they are kept from the game while it has
controller.BlockTriggers = true;

-- The plugin event that tells other addons this one has, or no longer has, the controller. Its data
-- is the addon's name, a colon, and 1 or 0.
controller.FocusEvent = 'winxi_controller_focus';

local bindings = {};
local held = {};      -- button -> whether it is down
local owner = {};     -- button -> the binding that took its press, until it is let go
local since = {};     -- button -> when that press began
local repeated = {};  -- button -> when it last repeated
local listening = false;

-- The kinds of controller. XInput is read as it comes. Each DirectInput layout says which of that
-- controller's buttons (by the number DirectInput gives it) is which Xbox button, by position.
local B = controller.Button;
controller.Layouts = {
    { key = 'xinput', label = 'XInput (Xbox)' },
    { key = 'playstation', label = 'DirectInput (PlayStation)', buttons = {
        [48] = B.X, [49] = B.A, [50] = B.B, [51] = B.Y,          -- square, cross, circle, triangle
        [52] = B.LB, [53] = B.RB, [56] = B.Back, [57] = B.Start, [58] = B.L3, [59] = B.R3 },
        triggers = { [54] = true, [55] = true } },                -- L2, R2
    { key = 'switch', label = 'DirectInput (Switch Pro)', buttons = {
        [48] = B.A, [49] = B.B, [50] = B.X, [51] = B.Y,          -- B, A, Y, X: bottom, right, left, top
        [52] = B.LB, [53] = B.RB, [56] = B.Back, [57] = B.Start, [58] = B.L3, [59] = B.R3 },
        triggers = { [54] = true, [55] = true } },                -- ZL, ZR
    { key = 'stadia', label = 'DirectInput (Stadia)', buttons = {
        [48] = B.A, [49] = B.B, [50] = B.X, [51] = B.Y,
        [52] = B.LB, [53] = B.RB, [54] = B.L3, [55] = B.R3, [56] = B.Back, [57] = B.Start } },
};

local layout = controller.Layouts[1];

-- Says which kind of controller is in use, by its key in controller.Layouts. Returns the key in use
-- (the present one, if the key given is not one of them).
function controller.SetLayout(key)
    for _, candidate in ipairs(controller.Layouts) do
        if candidate.key == key then
            if candidate ~= layout then
                layout = candidate;

                -- what was held was held on the other kind of controller, whose releases will no
                -- longer be heard: forget it, or a press taken there would repeat for ever
                for button in pairs(held) do
                    held[button] = nil;
                end
                for button in pairs(owner) do
                    owner[button] = nil;
                end
            end
            break;
        end
    end
    return layout.key;
end

function controller.GetLayout()
    return layout.key;
end

-- A button (by its Xbox name's number) is down or up, or is being reported again. Returns whether the
-- event that said so should be kept from the game. Every button's state is followed whether or not
-- anything wants the controller, so that one already down is not taken for a new press.
local function Process(button, down)
    local wasDown = held[button];
    held[button] = down;

    -- a press that was taken is kept from the game until the button is let go, even if the binding
    -- has since stopped being active: the game never saw it go down
    if owner[button] ~= nil then
        if not down then
            owner[button] = nil;
        end
        return true;
    end

    if down and not wasDown then
        for _, binding in ipairs(bindings) do
            local action = binding.actions[button];
            if action ~= nil and binding.active() then
                owner[button] = binding;
                since[button] = os.clock();
                repeated[button] = nil;
                binding.press(action);
                return true;
            end
        end
    end
    return false;
end

-- Whether any binding has the controller, as of the last frame
local anyActive = false;

-- A trigger is being reported (by whatever number the controller gives it). Kept from the game from
-- when it is pulled while a binding has the controller until it is let go.
local triggerHeld = {};

local function ProcessTrigger(id, down)
    if not down then
        local was = triggerHeld[id];
        triggerHeld[id] = nil;
        return was == true;
    end
    if triggerHeld[id] == nil and anyActive and controller.BlockTriggers then
        triggerHeld[id] = true;
    end
    return triggerHeld[id] == true;
end

-- XInput numbers the triggers after the buttons: 16 and 17, or 32 and 33 on an older Ashita
local xinputTrigger = (ashita.interface_version ~= nil) and 16 or 32;

local function OnXInput(e)
    if layout.buttons ~= nil then
        return; -- a DirectInput controller is in use
    end
    -- the buttons proper: beyond them the event reports the triggers and sticks
    if e.button <= 15 then
        if Process(e.button, e.state == 1) then
            e.blocked = true;
        end
    elseif e.button == xinputTrigger or e.button == xinputTrigger + 1 then
        if ProcessTrigger(e.button, e.state > 0) then
            e.blocked = true;
        end
    end
end

-- DirectInput reports the d-pad as one direction, in hundredths of a degree clockwise from up, or -1
-- (anything else) for none. A diagonal is two of the buttons at once.
local dpadOffset = 32;
local dpadHas = {
    [B.DpadUp]    = { [0] = true, [4500] = true, [31500] = true },
    [B.DpadRight] = { [4500] = true, [9000] = true, [13500] = true },
    [B.DpadDown]  = { [13500] = true, [18000] = true, [22500] = true },
    [B.DpadLeft]  = { [22500] = true, [27000] = true, [31500] = true },
};

local function OnDirectInput(e)
    local buttons = layout.buttons;
    if buttons == nil then
        return; -- an XInput controller is in use
    end

    if e.button == dpadOffset then
        -- one event for the whole d-pad: it is kept from the game if any of its buttons is taken
        local blocked = false;
        for button, angles in pairs(dpadHas) do
            if Process(button, angles[e.state] == true) then
                blocked = true;
            end
        end
        if blocked then
            e.blocked = true;
        end
        return;
    end

    local button = buttons[e.button];
    if button ~= nil then
        if Process(button, e.state == 128) then
            e.blocked = true;
        end
    elseif layout.triggers ~= nil and layout.triggers[e.button] then
        if ProcessTrigger(e.button, e.state == 128) then
            e.blocked = true;
        end
    end
end

-- How long after a binding is made before its taking the controller makes a sound: a window already
-- showing as its addon loads has not just been opened
local openGrace = 1.0;

-- Telling other addons whether this one has the controller, and hearing the same from them
local focusTold = nil;       -- what was last told: true or false
local focusToldAt = 0;
local focusRepeat = 1.0;     -- told again this often while it has the controller
local focusExpiry = 2.5;     -- an addon not heard from for this long is taken to have let go
local othersFocused = {};    -- addon name -> when it last said it has the controller

local function TellFocus(focused, now)
    local text = ('%s:%d'):format(addon.name, focused and 1 or 0);
    AshitaCore:GetPluginManager():RaiseEvent(controller.FocusEvent, { text:byte(1, -1) });
    focusTold, focusToldAt = focused, now;
end

local function OnPluginEvent(e)
    if e.name ~= controller.FocusEvent then
        return;
    end
    local name, focused = tostring(e.data or ''):match('^([^:%z]+):([01])');
    if name ~= nil and name ~= addon.name then
        othersFocused[name] = (focused == '1') and os.clock() or nil;
    end
end

-- Whether another addon's window has the controller
function controller.OtherHasFocus()
    local now = os.clock();
    for name, heard in pairs(othersFocused) do
        if now - heard < focusExpiry then
            return true;
        end
        othersFocused[name] = nil;
    end
    return false;
end

-- Whether any binding of this addon has the controller
function controller.HasFocus()
    return anyActive;
end

-- Once a frame: a binding that has just taken the controller sounds, and a held button whose action
-- repeats does so
local function OnPresent()
    local now = os.clock();

    -- a binding that has just taken the controller: its window has opened
    local any = false;
    for index = 1, #bindings do
        local binding = bindings[index];
        local active = binding.active() and true or false;
        if active ~= binding.wasActive then
            if active and now - binding.bound >= openGrace then
                sound.Play('open');
            end
            binding.wasActive = active;
        end
        any = any or active;
    end

    anyActive = any;
    if any ~= (focusTold or false) or (any and now - focusToldAt >= focusRepeat) then
        TellFocus(any, now);
    end

    -- nothing is held that a binding took: nothing to repeat
    if next(owner) == nil then
        return;
    end

    for button, binding in pairs(owner) do
        local action = binding.actions[button];
        if held[button] and action ~= nil and binding.repeats[action] and binding.active() then
            local last = repeated[button];
            if (last == nil and now - since[button] >= controller.RepeatDelay)
            or (last ~= nil and now - last >= controller.RepeatRate) then
                repeated[button] = now;
                binding.press(action);
            end
        end
    end
end

-- Starts taking presses for the addon as the spec describes (see the top of this file). Returns the
-- binding, for controller.Unbind.
function controller.Bind(spec)
    local binding = {
        active = spec.active or function() return true; end,
        actions = spec.actions or controller.StandardActions(),
        repeats = spec.repeats or {},
        press = spec.press or function() end,
        bound = os.clock(),   -- when it was made
        wasActive = false,    -- whether it had the controller a frame ago
    };
    bindings[#bindings + 1] = binding;

    if not listening then
        listening = true;
        ashita.events.register('xinput_button', 'winxi_controller_xinput', OnXInput);
        ashita.events.register('dinput_button', 'winxi_controller_dinput', OnDirectInput);
        ashita.events.register('d3d_present', 'winxi_controller_present', OnPresent);
        ashita.events.register('plugin_event', 'winxi_controller_plugin_event', OnPluginEvent);
        -- an addon unloaded with the controller in hand lets go of it
        ashita.events.register('unload', 'winxi_controller_unload', function()
            if focusTold then
                TellFocus(false, os.clock());
            end
        end);
    end
    return binding;
end

-- Whether a binding has the controller now
function controller.IsActive(binding)
    return binding ~= nil and binding.active() and true or false;
end

-- Marks the window being drawn as the one the controller is working: a bright line around its edge.
-- Called between the window's Begin and End, and not from inside a child of it; it draws nothing
-- unless the binding has the controller. winxi.window does this itself, given the binding as its
-- controller option.
controller.HighlightColor = { 0.23, 0.67, 0.91, 1.0 };

local highlightGlow = { 0, 0, 0, 0 };
local highlightMin, highlightMax = { 0, 0 }, { 0, 0 };
local clipMin, clipMax = { 0, 0 }, { 0, 0 };

-- How round the corners of windows are. Whether imgui's style can be read is found out the first
-- time; if it cannot, the corners are taken as square from then on.
local canReadRounding = nil;

local function ReadRounding()
    return imgui.GetStyle().WindowRounding;
end

local function WindowRounding()
    if canReadRounding then
        return ReadRounding();
    elseif canReadRounding == nil then
        local ok, rounding = pcall(ReadRounding);
        canReadRounding = ok and type(rounding) == 'number';
        return canReadRounding and rounding or 0;
    end
    return 0;
end

function controller.Highlight(binding)
    if not controller.IsActive(binding) then
        return false;
    end

    local x, y = imgui.GetWindowPos();
    local w, h = imgui.GetWindowSize();
    local rounding = WindowRounding();

    -- the colours are worked out each time, as they take in the window's fade
    local color = controller.HighlightColor;
    highlightGlow[1], highlightGlow[2], highlightGlow[3] = color[1], color[2], color[3];
    highlightGlow[4] = color[4] * 0.35;

    -- the window's own list, so that the line sits with the window among the others, opened up to
    -- take in its very edge and a little past it
    local drawList = imgui.GetWindowDrawList();
    clipMin[1], clipMin[2] = x - 3, y - 3;
    clipMax[1], clipMax[2] = x + w + 3, y + h + 3;
    drawList:PushClipRect(clipMin, clipMax, false);

    highlightMin[1], highlightMin[2] = x - 2, y - 2;
    highlightMax[1], highlightMax[2] = x + w + 2, y + h + 2;
    drawList:AddRect(highlightMin, highlightMax, imgui.GetColorU32(highlightGlow), rounding + 2, 0, 2);

    highlightMin[1], highlightMin[2] = x, y;
    highlightMax[1], highlightMax[2] = x + w, y + h;
    drawList:AddRect(highlightMin, highlightMax, imgui.GetColorU32(color), rounding, 0, 2);

    drawList:PopClipRect();
    return true;
end

function controller.Unbind(binding)
    for index, bound in ipairs(bindings) do
        if bound == binding then
            table.remove(bindings, index);
            break;
        end
    end
    for button, bound in pairs(owner) do
        if bound == binding then
            owner[button] = nil;
        end
    end
end

-- A grid: a highlight over things drawn in rows.
--
-- The things are told to the grid as they are drawn, each with where it is on screen, and the highlight
-- moves by those positions: left and right through them in the order drawn, up and down to the nearest
-- one in the next row. So it works whatever the layout, and needs to know nothing of it.
--
--     grid:Begin()                    -- before drawing
--     local index = grid:Add(x, y)    -- for each thing, as it is drawn; grid:IsOn(index) if it has the highlight
--     grid:End()                      -- after drawing
--     grid:Move('left')               -- from the addon's press function; true if the highlight moved
--
-- grid.cursor is the index the highlight is on, grid.count how many things were drawn, and grid.moved
-- is true during the one frame after the highlight has moved (to scroll it into view, for one).
local Grid = {};
Grid.__index = Grid;

function controller.NewGrid()
    return setmetatable({ cursor = 1, count = 0, moved = false, xs = {}, ys = {}, pending = false }, Grid);
end

function Grid:Begin()
    self.count = 0;
    self.moved = self.pending;
    self.pending = false;
end

function Grid:Add(x, y)
    local index = self.count + 1;
    self.count = index;
    self.xs[index], self.ys[index] = x, y;
    return index;
end

function Grid:IsOn(index)
    return index == self.cursor;
end

function Grid:End()
    if self.cursor > self.count then
        self.cursor = math.max(1, self.count);
    end
end

-- Puts the highlight back on the first thing (a different set of things is about to be drawn)
function Grid:Reset()
    self.cursor = 1;
    self.pending = true;
end

-- Where the thing with the highlight was last drawn
function Grid:Position()
    return self.xs[self.cursor], self.ys[self.cursor];
end

local function MoveRow(grid, direction)
    local x, y = grid.xs[grid.cursor], grid.ys[grid.cursor];
    if x == nil then
        return false;
    end

    -- the nearest row in that direction, then the thing in it closest across
    local rowY = nil;
    for index = 1, grid.count do
        local distance = (grid.ys[index] - y) * direction;
        if distance > 1 and (rowY == nil or distance < (rowY - y) * direction) then
            rowY = grid.ys[index];
        end
    end
    if rowY == nil then
        return false;
    end

    local best, bestDistance = nil, nil;
    for index = 1, grid.count do
        if math.abs(grid.ys[index] - rowY) <= 1 then
            local distance = math.abs(grid.xs[index] - x);
            if bestDistance == nil or distance < bestDistance then
                best, bestDistance = index, distance;
            end
        end
    end

    grid.cursor = best;
    return true;
end

function Grid:Move(direction)
    local moved = false;
    if direction == 'left' and self.cursor > 1 then
        self.cursor = self.cursor - 1;
        moved = true;
    elseif direction == 'right' and self.cursor < self.count then
        self.cursor = self.cursor + 1;
        moved = true;
    elseif direction == 'up' then
        moved = MoveRow(self, -1);
    elseif direction == 'down' then
        moved = MoveRow(self, 1);
    end

    if moved then
        self.pending = true;
        sound.Play('move');
    end
    return moved;
end

-- A menu: a list of choices.
--
--     local menu = controller.NewMenu('Title', {
--         { label = 'Use',  run = function() ... end },
--         { label = 'More', run = function() return controller.NewMenu(...) end },   -- opens another in its place
--         { label = 'Cancel' },                                                      -- just closes
--     });
--
--     menu = menu:Press(action)    -- from the addon's press function: the menu to show next, or nil once closed
--     menu:Draw(x, y)              -- each frame it is open, at a place on screen
--
-- Up and down move through the choices, confirm runs the one highlighted (and closes the menu unless it
-- hands back another), and back closes it.
local Menu = {};
Menu.__index = Menu;

function controller.NewMenu(title, entries)
    return setmetatable({ title = title, entries = entries or {}, index = 1 }, Menu);
end

function Menu:Press(action)
    local count = #self.entries;
    if action == 'up' and count > 0 then
        self.index = (self.index - 2) % count + 1;
        sound.Play('move');
    elseif action == 'down' and count > 0 then
        self.index = self.index % count + 1;
        sound.Play('move');
    elseif action == 'confirm' then
        local entry = self.entries[self.index];
        sound.Play('confirm');
        return entry and entry.run and entry.run() or nil;
    elseif action == 'back' then
        sound.Play('back');
        return nil;
    end
    return self;
end

local menuOpen = { true };
local menuPos = { 0, 0 };
local menuName = nil;

-- The flags of a floating box, the menu's and the label's: made on first use, when imgui's are certain
-- to be defined
local floatFlags = nil;

local function FloatFlags()
    if floatFlags == nil then
        floatFlags = bit.bor(
            ImGuiWindowFlags_NoDecoration,
            ImGuiWindowFlags_AlwaysAutoResize,
            ImGuiWindowFlags_NoSavedSettings,
            ImGuiWindowFlags_NoInputs);
    end
    return floatFlags;
end

function Menu:Draw(x, y)

    -- every addon draws in the one imgui, so the window is named for the addon it belongs to; one is
    -- enough, as a menu that opens another takes its place
    menuName = menuName or ('winxi.menu.' .. addon.name);

    menuPos[1], menuPos[2] = x, y;
    imgui.SetNextWindowPos(menuPos, ImGuiCond_Always);
    -- brought to the front every frame: a window that is clicked, or that appears after the menu was
    -- first made, would otherwise be drawn over it
    imgui.SetNextWindowFocus();
    menuOpen[1] = true;
    if imgui.Begin(menuName, menuOpen, FloatFlags()) then
        if self.title then
            imgui.TextDisabled(self.title);
        end
        for index, entry in ipairs(self.entries) do
            -- the label with an id of its own, so that two choices may read the same: made once
            entry.id = entry.id or ('%s##winxi.menu.%d'):format(entry.label, index);
            imgui.Selectable(entry.id, index == self.index);
        end
    end
    imgui.End();
end

-- A label: a small floating box with a line of text in it, in the manner of the menu, for saying
-- what the highlight is on. Its bottom left corner is put at x, y, so that given the top left of the
-- thing it names it sits just above it; or, with below set, its top left corner is, for a place under
-- the thing.
--
--     controller.Label(text, x, y, below)    -- each frame it should show
--
-- In place of the text may go a function that draws what the box holds, for more than a line. The
-- box is brought forward when what it says changes, which for a function it cannot tell, so with one
-- goes a key: anything that is different when the content is.
--
--     controller.Label(Draw, x, y, below, key)
local labelOpen = { true };
local labelPos = { 0, 0 };
local labelAbove, labelBelow = { 0, 1 }, { 0, 0 }; -- which corner of the box goes at the point
local labelName = nil;
local labelText = nil;   -- what it last said
local labelDrawn = 0;    -- when it was last drawn

function controller.Label(text, x, y, below, key)
    key = key or text;
    labelName = labelName or ('winxi.label.' .. addon.name);

    -- brought to the front when it appears, moves or says something new, and not every frame as the
    -- menu is: taking the focus closes any popup that is open, and unlike the menu the label is up
    -- the whole time, over a window that may have a right-click menu of its own
    local now = os.clock();
    if key ~= labelText or x ~= labelPos[1] or y ~= labelPos[2] or now - labelDrawn > 0.25 then
        imgui.SetNextWindowFocus();
        labelText = key;
    end
    labelDrawn = now;

    labelPos[1], labelPos[2] = x, y;
    imgui.SetNextWindowPos(labelPos, ImGuiCond_Always, below and labelBelow or labelAbove);
    labelOpen[1] = true;
    if imgui.Begin(labelName, labelOpen, FloatFlags()) then
        if type(text) == 'function' then
            text();
        else
            imgui.Text(text);
        end
    end
    imgui.End();
end

return controller;
