-- winxi.fade: fades an addon's windows out once the player has been idle, and brings them back.
--
-- Idle means standing still. The settings say how long for, how long the fade takes, how visible a
-- faded window stays, and what else counts as not being idle:
--     { Enabled = false, Delay = 10, Duration = 1.5, Opacity = 0,
--       Combat = true, Target = true, MissingHp = false, Resting = false, Transition = 0.1 }
-- Delay and Duration are seconds, Opacity a percentage. Transition is how many seconds a window takes
-- to fade in as it appears, out as it goes, and back in when idling ends: one speed for every window. Combat, Target, MissingHp and Resting each keep
-- the windows up while engaged, while anything is targeted, while below full HP, and while resting.
--
-- The settings are the addon's own, kept wherever it keeps the rest; fade.Complete(settings) fills in
-- whatever a table lacks, and winxi.widgets.Fade draws the controls for them.
--
-- Call fade.Update(settings) once a frame, then give fade.Alpha() to each window that fades (as the
-- alpha option of winxi.window or winxi.style). A window at fade.Hidden() need not be drawn at all.
--
-- Separately from idling, fade.Presence fades a window in when it appears and out when it goes (see
-- below). Multiply the two for a window that does both.
local fade = {};

fade.Defaults = {
    Enabled = false,
    Delay = 10,
    Duration = 1.5,
    Opacity = 0,
    Combat = true,
    Target = true,
    MissingHp = false,
    Resting = false,
    Transition = 0.1, -- seconds a window takes to fade in as it appears, out as it goes, and back from idling
};

-- Gives a settings table each setting it does not yet have, at its default. Returns the table.
function fade.Complete(settings)
    for key, value in pairs(fade.Defaults) do
        if type(settings[key]) ~= type(value) then
            settings[key] = value;
        end
    end
    return settings;
end

local moveThreshold = 0.05;  -- a change in position smaller than this is not movement
local statusEngaged = 1;
local statusResting = 33;    -- kneeling to recover HP and MP (/heal)

-- Seconds to fade in, out, and back from idling. Set from the settings' Transition by fade.Update.
fade.TransitionTime = fade.Defaults.Transition;

local alpha = 1;
local lastMove, lastFrame = os.clock(), os.clock();
local lastX, lastY, lastZ = nil, nil, nil;

-- suspended: true to hold the windows fully visible this frame whatever the settings say (while they
-- are being arranged, for one)
function fade.Update(settings, suspended)
    local now = os.clock();
    local elapsed = math.min(now - lastFrame, 0.1);
    lastFrame = now;

    -- the one speed for appearing, disappearing and coming back from idling
    if settings ~= nil and type(settings.Transition) == 'number' then
        fade.TransitionTime = math.max(0, settings.Transition);
    end

    if settings == nil or not settings.Enabled or suspended then
        alpha = 1;
        lastMove = now;
        return;
    end

    local memory = AshitaCore:GetMemoryManager();
    local index = memory:GetParty():GetMemberTargetIndex(0);
    if index ~= 0 then
        local entities = memory:GetEntity();
        local x = entities:GetLocalPositionX(index);
        local y = entities:GetLocalPositionY(index);
        local z = entities:GetLocalPositionZ(index);

        local active = lastX == nil
            or math.abs(x - lastX) > moveThreshold
            or math.abs(y - lastY) > moveThreshold
            or math.abs(z - lastZ) > moveThreshold;
        if active then
            lastX, lastY, lastZ = x, y, z;
        end

        if not active and (settings.Combat or settings.Resting) then
            local status = entities:GetStatus(index);
            active = (settings.Combat and status == statusEngaged) or (settings.Resting and status == statusResting);
        end

        if not active and settings.Target then
            local target = memory:GetTarget();
            active = target:GetIsActive(0) == 1 and target:GetTargetIndex(0) ~= 0;
        end

        if not active and settings.MissingHp then
            local maxHp = memory:GetPlayer():GetHPMax();
            active = maxHp > 0 and memory:GetParty():GetMemberHP(0) < maxHp;
        end

        if active then
            lastMove = now;
        end
    end

    local idleAlpha = math.max(0, math.min(1, (tonumber(settings.Opacity) or 0) / 100));
    local target = (now - lastMove >= (tonumber(settings.Delay) or 10)) and idleAlpha or 1;
    local range = 1 - idleAlpha;

    if alpha > target then
        local duration = tonumber(settings.Duration) or 0;
        if duration > 0 then
            alpha = math.max(target, alpha - range * elapsed / duration);
        else
            alpha = target;
        end
    elseif alpha < target then
        if fade.TransitionTime > 0 then
            alpha = math.min(target, alpha + range * elapsed / fade.TransitionTime);
        else
            alpha = target;
        end
    end
end

-- Appearing and disappearing. A window that has just come to be shown fades in, and one that has just
-- stopped being wanted fades out, each over fade.TransitionTime seconds.
--
--     local alpha = fade.Presence(key, wanted)
--
-- key names the window. Called on each frame the window might be drawn, it gives the opacity to draw it
-- at, moving towards 1 while wanted is true and towards 0 while it is false; at 0 there is nothing to
-- draw. A window whose addon simply stops asking about it when it is not wanted still fades in the next
-- time it is: a gap in the asking counts as the window having been away. To fade such a window out, the
-- addon has to go on drawing it, with wanted false, for as long as fade.Lingering(key) is true.

local presenceGap = 0.25; -- seconds without being asked about before a window counts as having been away
local presence = {};      -- key -> { alpha, time = when it was last asked about }

function fade.Presence(key, wanted)
    local now = os.clock();
    local state = presence[key];
    if state == nil then
        state = { alpha = 0, time = now };
        presence[key] = state;
    end

    local elapsed = now - state.time;
    state.time = now;
    if elapsed > presenceGap then
        -- not asked about for a while: it was not on screen, so it starts from nothing
        state.alpha = 0;
        elapsed = 0;
    end

    local step = (fade.TransitionTime > 0) and (elapsed / fade.TransitionTime) or 1;
    if wanted then
        state.alpha = math.min(1, state.alpha + step);
    else
        state.alpha = math.max(0, state.alpha - step);
    end
    return state.alpha;
end

-- True while a window that is no longer wanted has not yet finished fading out
function fade.Lingering(key)
    local state = presence[key];
    return state ~= nil and state.alpha > 0.01 and os.clock() - state.time <= presenceGap;
end

-- How opaque a fading window is this frame, 0 to 1
function fade.Alpha()
    return alpha;
end

-- True while a fading window has faded right out
function fade.Hidden()
    return alpha <= 0.01;
end

return fade;
