-- winxi.fade: fades an addon's windows out once the player has been idle, and brings them back.
--
-- Idle means standing still. The settings say how long for, how long the fade takes, how visible a
-- faded window stays, and what else counts as not being idle:
--     { Enabled = false, Delay = 10, Duration = 1.5, Opacity = 0,
--       Combat = true, Target = true, MissingHp = false, Resting = false }
-- Delay and Duration are seconds, Opacity a percentage. Combat, Target, MissingHp and Resting each keep
-- the windows up while engaged, while anything is targeted, while below full HP, and while resting.
--
-- Call fade.Update(settings) once a frame, then give fade.Alpha() to each window that fades (as the
-- alpha option of winxi.window or winxi.style). A window at fade.Hidden() need not be drawn at all.
local fade = {};

local fadeInTime = 0.2;      -- seconds to come back, however long the fade out takes
local moveThreshold = 0.05;  -- a change in position smaller than this is not movement
local statusEngaged = 1;
local statusResting = 33;    -- kneeling to recover HP and MP (/heal)

local alpha = 1;
local lastMove, lastFrame = os.clock(), os.clock();
local lastX, lastY, lastZ = nil, nil, nil;

-- suspended: true to hold the windows fully visible this frame whatever the settings say (while they
-- are being arranged, for one)
function fade.Update(settings, suspended)
    local now = os.clock();
    local elapsed = math.min(now - lastFrame, 0.1);
    lastFrame = now;

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
        alpha = math.min(target, alpha + range * elapsed / fadeInTime);
    end
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
