-- How much of the map shows while the player is on the move: in passthrough it fades to Passthrough
-- Opacity as the player starts off, and back up as they stop. The mouse over the map has all of it
-- again.
--
--   moving.Update(on, opacity, held, hidden)   once a frame: on whether the map fades while moving
--                                      (in passthrough), opacity how far, 0 to 100, held whether the
--                                      map is wanted whole; hidden holds its opacity during the
--                                      window's fade-out. Returns 0 to 1.
local moving = {};

local STEP = 0.05;     -- a change in position smaller than this is not movement
local STILL = 0.4;     -- seconds stood still before the player counts as stopped
local TRANSITION = 0.25; -- seconds to fade all the way out or in

local alpha = 1;
local lastX, lastY, lastZ = nil, nil, nil;
local movedAt = -math.huge;
local lastFrame = nil;

local function Moved(now)
    local ok, x, y, z = pcall(function()
        local memory = AshitaCore:GetMemoryManager();
        local index = memory:GetParty():GetMemberTargetIndex(0);
        if index == 0 then return nil; end
        local entities = memory:GetEntity();
        return entities:GetLocalPositionX(index), entities:GetLocalPositionY(index), entities:GetLocalPositionZ(index);
    end);
    if not ok or x == nil then
        lastX = nil;
        return;
    end
    if lastX == nil then
        lastX, lastY, lastZ = x, y, z; -- where the player stands to begin with is no move
    elseif math.abs(x - lastX) > STEP or math.abs(y - lastY) > STEP or math.abs(z - lastZ) > STEP then
        lastX, lastY, lastZ = x, y, z;
        movedAt = now;
    end
end

function moving.Update(on, opacity, held, hidden)
    local now = os.clock();
    local elapsed = lastFrame and math.min(now - lastFrame, 0.1) or 0;
    lastFrame = now;
    -- The shell fades visibility itself. Keep the movement multiplier steady while it closes,
    -- rather than flashing back to full opacity just as passthrough is switched off.
    if hidden then
        lastX, movedAt = nil, -math.huge;
        return alpha;
    end
    if on then
        Moved(now);
    else
        lastX, movedAt = nil, -math.huge;
    end
    local low = math.max(0, math.min(1, opacity / 100));
    local wanted = (not on or held or now - movedAt >= STILL) and 1 or low;
    local step = elapsed / TRANSITION;
    if alpha < wanted then
        alpha = math.min(wanted, alpha + step);
    else
        alpha = math.max(wanted, alpha - step);
    end
    return alpha;
end

return moving;
