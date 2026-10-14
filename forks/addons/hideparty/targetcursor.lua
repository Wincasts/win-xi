-- The target cursor the game no longer draws once hideparty has hidden its target frame: the game's box
-- and its arrow are one primitive, so hiding one hides both. Drawn over the target and the sub target
-- from the game's own anc_l sprites in ROM/119/51.DAT, through winxi.cursor.
--
-- targetcursor by Hiken, a fork of Jyouya's `customtarget` as extended by yzyii; MIT, see
-- targetcursor.LICENSE. Horizontal position from the model's render base, height from the anchor bone
-- scaled by the model's own render scale. See TARGETCURSOR.md for how each of these was established.
--
--   targetcursor.Draw()   draw the cursors for this frame; call from d3d_present while the frame is hidden

-- * Size * --
local cursorScaleFactor    = 1.0 -- On-screen size multiplier. To match the size
                                 -- the game draws its own cursor:
                                 --   scale = background height / menu height
                                 --
                                 -- 1.0 when they match; a 1440p background with a
                                 -- 1080p menu wants 1.333.
                                 -- default: 1.0
-- * ^^^^ * --

-- * Opacity * --
-- 1.0 = as the game draws it, 0.0 = invisible. A MULTIPLY on the art's own
-- per-pixel alpha, so soft edges stay soft.
local cursorOpacity    = 1.0   -- main cursor. default: 1.0
local subCursorOpacity = 1.0   -- sub cursor.  default: 1.0
-- * ^^^^^^^^ * --

-- * Main cursor tint * --
-- nil = draw the game's cursor as it is (default).
-- Set to {r,g,b} to recolor it, e.g. {120,255,140} for green. The tint is a
-- MULTIPLY on a grey copy of the cursor, so the color comes out clean.
local colorMainCursor = nil    -- default: nil
-- * ^^^^^^^^^^^^^^^^^^^^ * --

-- * Sub cursor range colors * --
-- The game tints its sub cursor by whether the selected action reaches the
-- target. Sampled from the game's own cursor, applied to the grey copy.
-- With rangeColors off the sub cursor is always colorInRange.
local rangeColors     = true               -- default: true
local colorInRange    = {121,107,255}  -- blue  - action will reach.     default: {121,107,255}
local colorNearRange  = {255,255,103}  -- yellow- just out of reach.     default: {255,255,103}
local colorOutOfRange = {255,108,97}   -- red   - out of range.          default: {255,108,97}
-- * ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ * --

-- Range thresholds. All read from the client, so there is no spell table and
-- nothing to maintain:
--
--   blue  <=>  sqrt(GetDistance + dz^2) <= ActionTargetMaxYalms + hitbox
--
-- A ranged attack (ActionId 0) gets no hitbox.
--
-- ModelHitboxSize is already scaled - do not multiply it by the model scale.
local rangeBaseOffset = 0.00   -- constant added to (range + hitbox). default: 0.00
local rangeYellowBand = 0.95   -- width of the yellow "almost in range" band. default: 0.95
local rangeDefaultHitbox = 1.0 -- fallback when the entity reports no hitbox. default: 1.0

-- Placement. Measured against the game's own cursor; none of it should need
-- changing.
local anchorBone      = 2      -- Bone supplying the anchor height. Bone 2 is the top of the body on
                               -- every skeleton measured. -1 = model base. default: 2
local anchorHeight    = 0.0    -- Extra world-units nudge after scaling. POSITIVE raises.
                               -- default: 0.0
local anchorSmoothing = 0.04   -- How fast the damped height follows the bone. Lower = steadier.
                               -- default: 0.04
local objectPosOffset = 0x34   -- Position offset inside a target-actor struct that has no entity
                               -- index (moghouse doors). Copies also exist at 0xC4 and 0xD4.
                               -- Only change this if a client update moves the field.
                               -- default: 0x34

-- Library bindings. Below the settings so the editable values come first.
local d3d               = require('d3d8')
local ffi               = require('ffi')
local C                 = ffi.C
local chat              = require('chat')
local cursor            = require('winxi.cursor')

local targetcursor = {}

local cursorRect        = ffi.new('RECT')
local cursorTransform   = ffi.new('D3DXMATRIX')
cursorTransform._33, cursorTransform._44 = 1, 1

-- GetSubTargetFlags reads 0xFFFFFFFF when nothing is being selected.
local SUBTARGET_NONE = 0xFFFFFFFF

-- Made on the first frame drawn, when the device is certain to be there.
local d3d8dev
local sprite
local width, height = 0, 0
local warned = false

-- Scratch matrix, reused every call to avoid allocating one per frame.
local viewProj = ffi.new('D3DXMATRIX')

-- view * projection, written INTO `out` rather than returned.
local function matrixMultiply(out, m1, m2)
    out._11 = m1._11 * m2._11 + m1._12 * m2._21 + m1._13 * m2._31 + m1._14 * m2._41
    out._12 = m1._11 * m2._12 + m1._12 * m2._22 + m1._13 * m2._32 + m1._14 * m2._42
    out._13 = m1._11 * m2._13 + m1._12 * m2._23 + m1._13 * m2._33 + m1._14 * m2._43
    out._14 = m1._11 * m2._14 + m1._12 * m2._24 + m1._13 * m2._34 + m1._14 * m2._44

    out._21 = m1._21 * m2._11 + m1._22 * m2._21 + m1._23 * m2._31 + m1._24 * m2._41
    out._22 = m1._21 * m2._12 + m1._22 * m2._22 + m1._23 * m2._32 + m1._24 * m2._42
    out._23 = m1._21 * m2._13 + m1._22 * m2._23 + m1._23 * m2._33 + m1._24 * m2._43
    out._24 = m1._21 * m2._14 + m1._22 * m2._24 + m1._23 * m2._34 + m1._24 * m2._44

    out._31 = m1._31 * m2._11 + m1._32 * m2._21 + m1._33 * m2._31 + m1._34 * m2._41
    out._32 = m1._31 * m2._12 + m1._32 * m2._22 + m1._33 * m2._32 + m1._34 * m2._42
    out._33 = m1._31 * m2._13 + m1._32 * m2._23 + m1._33 * m2._33 + m1._34 * m2._43
    out._34 = m1._31 * m2._14 + m1._32 * m2._24 + m1._33 * m2._34 + m1._34 * m2._44

    out._41 = m1._41 * m2._11 + m1._42 * m2._21 + m1._43 * m2._31 + m1._44 * m2._41
    out._42 = m1._41 * m2._12 + m1._42 * m2._22 + m1._43 * m2._32 + m1._44 * m2._42
    out._43 = m1._41 * m2._13 + m1._42 * m2._23 + m1._43 * m2._33 + m1._44 * m2._43
    out._44 = m1._41 * m2._14 + m1._42 * m2._24 + m1._43 * m2._34 + m1._44 * m2._44
end

-- Row-vector convention: v * (view * projection), then NDC -> raster.
local function worldToScreen(x, y, z, view, projection)
    matrixMultiply(viewProj, view, projection)

    local rhw = 1 / (viewProj._14 * x + viewProj._24 * y + viewProj._34 * z + viewProj._44)

    local ndcX = (viewProj._11 * x + viewProj._21 * y + viewProj._31 * z + viewProj._41) * rhw
    local ndcY = (viewProj._12 * x + viewProj._22 * y + viewProj._32 * z + viewProj._42) * rhw
    local ndcZ = (viewProj._13 * x + viewProj._23 * y + viewProj._33 * z + viewProj._43) * rhw

    return math.floor((ndcX + 1) * 0.5 * width),
        math.floor((1 - ndcY) * 0.5 * height),
        ndcZ
end

-- The base position the model is actually RENDERED at this frame, free of
-- animation movement. This is what the nameplate follows.
local function getActorBase(actorPointer)
    return ashita.memory.read_float(actorPointer + 0x678),
        ashita.memory.read_float(actorPointer + 0x680),
        ashita.memory.read_float(actorPointer + 0x67C)
end

-- actor -> skeleton, three dereferences. Each can be null, so each is checked.
local function skeletonOf(actorPointer)
    local skeletonBaseAddress = ashita.memory.read_uint32(actorPointer + 0x6B8)
    if (skeletonBaseAddress == 0) then return 0 end

    local skeletonOffsetAddress = ashita.memory.read_uint32(skeletonBaseAddress + 0x0C)
    if (skeletonOffsetAddress == 0) then return 0 end

    return ashita.memory.read_uint32(skeletonOffsetAddress)
end

-- The anchor bone's height offset ABOVE THE RENDER BASE, in model space.
local function getBoneOffsetZ(actorPointer, bone)
    local skeletonAddress = skeletonOf(actorPointer)
    if (skeletonAddress == 0) then return 0 end

    local boneCount = ashita.memory.read_uint16(skeletonAddress + 0x32)

    -- Generators follow the bone records: header 0x04, then 0x1E per bone.
    local generatorsAddress = skeletonAddress + 0x30 + 0x04 + 0x1E * boneCount + 4

    -- 0x1A per generator record; the offset triplet starts at +0x0E and dz - the
    -- vertical axis - is the SECOND float of the three.
    return ashita.memory.read_float(generatorsAddress + (bone * 0x1A) + 0x0E + 0x4)
end

-- Opacity as a D3DCOLOR alpha byte, clamped so a typo cannot wrap.
local function alphaByte(o)
    if (type(o) ~= 'number' or o ~= o) then return 255 end
    if (o < 0) then o = 0 elseif (o > 1) then o = 1 end
    return math.floor(o * 255 + 0.5)
end

-- Anchor a cursor on a model. Horizontal comes from the model's render base,
-- which is frame-accurate and free of animation. Only the HEIGHT comes from the
-- bone, low-pass filtered so breathing and run cycles do not reach the cursor.
-- The filter state is keyed on target index, and indices are RECYCLED slots, so
-- it records which actor each value belongs to and drops it when that changes.
local smoothDelta = {} -- targetIndex -> damped bone height offset
local smoothOwner = {} -- targetIndex -> actor pointer that value belongs to

-- A jump larger than this is a change of subject, not animation, so the filter
-- restarts rather than sliding across it.
local anchorSnapJump = 0.5 -- world units

-- The model's render scale, per creature. The game hangs its cursor at the
-- anchor bone's height MULTIPLIED by this. Copies live at 0x69C/0x6A0/0x754.
local function getModelScale(pointer)
    local s = ashita.memory.read_float(pointer + 0x698)
    if (s ~= s or s <= 0.01 or s > 20.0) then
        return 1.0
    end
    return s
end

local function anchorFromModel(pointer, idx)
    local scale = getModelScale(pointer)
    local bx, by, bz = getActorBase(pointer)

    local delta = 0
    if (anchorBone >= 0) then
        delta = getBoneOffsetZ(pointer, anchorBone)
    end

    -- New occupant on this index: throw the inherited value away and snap.
    if (smoothOwner[idx] ~= pointer) then
        smoothOwner[idx] = pointer
        smoothDelta[idx] = nil
    end

    local prev = smoothDelta[idx]
    if (prev == nil or math.abs(delta - prev) > anchorSnapJump) then
        prev = delta
    end
    local damped = prev + (delta - prev) * anchorSmoothing
    smoothDelta[idx] = damped

    return bx, by, bz + (damped * scale) - anchorHeight
end

local function rangeColorFor(idx)
    if (not rangeColors or idx == nil or idx == 0) then return nil end
    local tgt = AshitaCore:GetMemoryManager():GetTarget()
    if (tgt == nil or tgt:GetActionTargetActive() == 0) then return nil end

    local maxY = tgt:GetActionTargetMaxYalms()
    if (maxY == 0) then return nil end
    if (maxY == 0xFF) then return colorInRange end   -- self-only action

    local ent = AshitaCore:GetMemoryManager():GetEntity()
    local sq  = ent:GetDistance(idx)                 -- squared, horizontal only
    if (sq == nil or sq < 0) then return nil end

    -- The client's check is 3D; GetDistance is horizontal, so height is added here.
    local party = AshitaCore:GetMemoryManager():GetParty()
    local me    = party and party:GetMemberTargetIndex(0) or 0
    local dz    = 0
    if (me ~= 0 and me ~= idx) then
        dz = ent:GetLocalPositionZ(idx) - ent:GetLocalPositionZ(me)
        if (dz ~= dz) then dz = 0 end
    end

    local dist = math.sqrt(sq + (dz * dz))

    -- Already scaled by the client. Do not multiply by the model scale.
    local hb = ent:GetModelHitboxSize(idx)
    if (hb == nil or hb ~= hb or hb <= 0 or hb > 20) then hb = rangeDefaultHitbox end

    -- A ranged attack (no action id) gets no hitbox allowance. Everything else is
    -- checked edge to edge, so the caster's own hitbox counts too.
    local isRanged = (tgt:GetActionId() == 0)
    local hbSelf = 0
    if (isRanged) then
        hb = 0
    elseif (me ~= 0) then
        hbSelf = ent:GetModelHitboxSize(me)
        if (hbSelf == nil or hbSelf ~= hbSelf or hbSelf <= 0 or hbSelf > 20) then
            hbSelf = 0
        end
    end

    local blueAt = maxY + hb + hbSelf + rangeBaseOffset

    local c
    if (dist <= blueAt) then                       c = colorInRange
    elseif (dist <= blueAt + rangeYellowBand) then c = colorNearRange
    else                                           c = colorOutOfRange end
    return c
end

-- Where the cursor's tip goes on screen, and its depth: the anc_l sprite's pivot is the tip.
local function getPos(targetIndex, slot)
    -- Save the entity manager for ease of use
    local entity = AshitaCore:GetMemoryManager():GetEntity()

    local haveIndex = (targetIndex ~= nil and targetIndex ~= 0)

    -- Only meaningful when there is an entity index to look up
    local entityType, renderFlags, isSelf
    if (haveIndex) then
        entityType = entity:GetType(targetIndex)
        renderFlags = entity:GetRenderFlags0(targetIndex)

        -- Is this us?
        local party = AshitaCore:GetMemoryManager():GetParty()
        isSelf = (party ~= nil and targetIndex == party:GetMemberTargetIndex(0))
    end

    local tx, ty, tz
    if (not haveIndex) then
        -- Moghouse doors report target index 0 - a null entity at the zone origin, so
        -- drive everything from the target structure's own actor pointer.
        local targetActor = 0
        if (slot ~= nil) then
            local tgt = AshitaCore:GetMemoryManager():GetTarget()
            if (tgt ~= nil) then
                targetActor = tgt:GetActorPointer(slot) or 0
            end
        end

        if (targetActor == 0) then
            return nil, nil, nil
        end
        -- Not an XiModel: +0x678 is an orientation vector. Real coordinates live at
        -- objectPosOffset, in the same memory order the rest of the addon uses.
        tx = ashita.memory.read_float(targetActor + objectPosOffset)
        tz = ashita.memory.read_float(targetActor + objectPosOffset + 4)
        ty = ashita.memory.read_float(targetActor + objectPosOffset + 8)
        if (tx == 0 and ty == 0 and tz == 0) then
            tx, ty, tz = getActorBase(targetActor)
        end
    elseif (isSelf) then
        local selfPointer = entity:GetActorPointer(targetIndex)
        if (selfPointer ~= nil and selfPointer ~= 0) then
            tx, ty, tz = anchorFromModel(selfPointer, targetIndex)
        else
            tx = entity:GetLocalPositionX(targetIndex)
            ty = entity:GetLocalPositionY(targetIndex)
            tz = entity:GetLocalPositionZ(targetIndex) - anchorHeight
        end
    elseif (entityType == 3) then -- If target is a door or something similar
        -- Doors that DO have an entity index use the entity position.
        tx = entity:GetLocalPositionX(targetIndex)
        ty = entity:GetLocalPositionY(targetIndex)
        tz = entity:GetLocalPositionZ(targetIndex)
    elseif (renderFlags == 0 and entityType == 0) then
        tx = entity:GetLastPositionX(targetIndex)
        ty = entity:GetLastPositionY(targetIndex)
        tz = entity:GetLastPositionZ(targetIndex)
    else
        -- Mobs, NPCs and other players: same anchoring as the self case.
        local targetPointer = entity:GetActorPointer(targetIndex)
        if (targetPointer ~= nil and targetPointer ~= 0) then
            tx, ty, tz = anchorFromModel(targetPointer, targetIndex)
        else
            tx = entity:GetLocalPositionX(targetIndex)
            ty = entity:GetLocalPositionY(targetIndex)
            tz = entity:GetLocalPositionZ(targetIndex) - anchorHeight
        end
    end

    -- Get the transformation matrices for the scene
    local _, view = d3d8dev:GetTransform(C.D3DTS_VIEW)
    local _, projection = d3d8dev:GetTransform(C.D3DTS_PROJECTION)

    return worldToScreen(tx, tz, ty, view, projection)
end

-- One frame of the sprite, its cell taken from the atlas and its corners laid around the tip at x, y:
-- the cell's top edge runs from corner 1 to corner 2 and its left edge from corner 1 to corner 3.
local function drawFrame(handle, frame, x, y, color)
    local r, c, s = frame.rect, frame.corners, cursorScaleFactor
    local w, h = r[3] - r[1], r[4] - r[2]
    cursorRect.left, cursorRect.top, cursorRect.right, cursorRect.bottom = r[1], r[2], r[3], r[4]
    cursorTransform._11 = s * (c[3] - c[1]) / w
    cursorTransform._12 = s * (c[4] - c[2]) / w
    cursorTransform._21 = s * (c[5] - c[1]) / h
    cursorTransform._22 = s * (c[6] - c[2]) / h
    cursorTransform._41 = x + s * c[1]
    cursorTransform._42 = y + s * c[2]
    sprite:DrawTransform(ffi.cast('IDirect3DTexture8*', handle), cursorRect, cursorTransform, color)
end

-- The game's cursor as it is, or the grey copy multiplied by tint; nil when neither has loaded.
local function drawCursor(x, y, opacity, tint)
    local a = alphaByte(opacity)
    if (tint ~= nil) then
        local handle, frame = cursor.Get(false, 'anc_l', true)
        if (handle) then
            drawFrame(handle, frame, x, y, d3d.D3DCOLOR_ARGB(a, tint[1], tint[2], tint[3]))
            return
        end
    end
    local handle, frame = cursor.Get(false, 'anc_l')
    if (handle) then
        drawFrame(handle, frame, x, y, d3d.D3DCOLOR_ARGB(a, 255, 255, 255))
    elseif (not warned) then
        warned = true
        print(chat.header(addon.name):append(chat.error('Cannot load the target cursor: ' .. tostring(frame))))
    end
end

function targetcursor.Draw()
    -- Save the target manager for ease of use
    local target = AshitaCore:GetMemoryManager():GetTarget()

    -- Determine if we are currently subtargetting
    local isSubTargetActive = target:GetIsSubTargetActive()

    -- Exit early only if NEITHER slot has an active target. When a locked target
    -- dies mid-selection the client drops out of sub-targeting that same frame,
    -- so testing only the slot isSubTargetActive points at would erase a
    -- still-valid sub cursor along with the main one.
    if (target:GetIsActive(0) == 0 and target:GetIsActive(1) == 0) then
        return
    end

    if (sprite == nil) then
        d3d8dev = d3d.get_device()
        local sprite_ptr = ffi.new('ID3DXSprite*[1]')
        if (d3d8dev == nil or C.D3DXCreateSprite(d3d8dev, sprite_ptr) ~= C.S_OK) then
            return
        end
        sprite = d3d.gc_safe_release(ffi.cast('ID3DXSprite*', sprite_ptr[0]))
    end
    local _, viewport = d3d8dev:GetViewport()
    width, height = viewport.Width, viewport.Height

    -- Get the index of your current target or subtarget (if any)
    local targetIndex = target:GetTargetIndex(isSubTargetActive)
    local targetIndexSub = nil
    if (isSubTargetActive == 1) then
        targetIndexSub = target:GetTargetIndex(0)
    end

    -- The sub cursor's color carries range, so colorInRange owns it whenever
    -- there is no action target to measure.
    local function drawSub(idx, x, y)
        drawCursor(x, y, subCursorOpacity, rangeColorFor(idx) or colorInRange)
    end

    -- getPos returns nil, nil, nil when it cannot place this target at all - no
    -- entity index AND no target-struct actor pointer, which is exactly the state
    -- of a target that JUST DIED - so only a real depth is drawn.
    local px, py, ndcZ = getPos(targetIndex, isSubTargetActive)

    -- Test if target cursor is in the viewing volume
    if (ndcZ ~= nil and ndcZ >= 0 and ndcZ <= 1) then
        -- SubTargetFlags is a per-action mask of valid target types, 0xFFFFFFFF when
        -- nothing is selected: while the game would show its blue selection cursor
        -- the sub cursor is drawn rather than the main one. 'not targetIndexSub'
        -- because a separate sub target index is drawn below.
        if (target:GetSubTargetFlags() ~= SUBTARGET_NONE and not targetIndexSub) then
            drawSub(targetIndex, px, py)
        else
            drawCursor(px, py, cursorOpacity, colorMainCursor)
        end
    end

    if (targetIndexSub) then
        local pxSub, pySub, ndcZSub = getPos(targetIndexSub, 0)

        -- Test if subtarget cursor is in the viewing volume; padded up, then drawn
        if (ndcZSub ~= nil and ndcZSub >= 0 and ndcZSub <= 1) then
            drawSub(targetIndexSub, pxSub, pySub - 10)
        end
    end
end

return targetcursor
