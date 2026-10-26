-- winxi.popups: the damage numbers the game pops up over whoever was hit, by way of the namehook
-- plugin (1.38 and newer): what each says, who it is over and from, and where it is; and drawing
-- them in the game's place.
--
-- The plugin lists the popups the game drew, or was about to draw, last frame. Each hit makes two of
-- them, from two of the game's objects: the number and a darker copy under it (for a miss, ':' and a
-- copy with no text). popups.Each gives them all; popups.Hits gives one for each hit.
--
--   popups.Hook()                      the plugin's block, or nil and why not
--   popups.Problem()                   a sentence for the user while something is wrong, or nil
--   for i, popup in popups.Each(hook) do ... end    last frame's popups
--   for popup in popups.Hits(hook) do ... end       one for each hit: the first of each pair
--   popups.Text(popup)                 what it says, with the game's ':' for a miss made "Miss!"
--   popups.Has(popup, flag)            popups.Flag
--
-- A popup is the plugin's own record, read in place and good for this frame only:
--   popup.Id                           the same while it is drawn, a new one for each
--   popup.EntityIndex, popup.SourceIndex   who was hit and who hit them (Flag.Target, Flag.Source)
--   popup.Color                        the game's colour, 0xAARRGGBB with 0x80 for full: the alpha is its fading
--   popup.X, popup.Y, popup.Z          where the game puts it, in the world: it rises as it goes
--   popup.Scale                        the game's size for it; popup.Width, popup.Height a letter's size
--   popup.FirstFrame                   the frame it was first listed in
--
-- An addon that draws the popups itself claims them every frame it does so, and the game draws none
-- (a claim not made again lapses in half a second). The plugin draws a popup's quads where and when
-- the game would have drawn it, so they rise and go with it. Every frame:
--   popups.Claim(hook)
--   local scale = popups.BeginDrawing(hook)   nil if the plugin cannot; else how many pixels of the
--                                             game's picture there are to one of the screen's
--   popups.SetTexture(slot, texture)          as nameplates.SetTexture
--   popups.BeginPopup(popup, alpha, edge, edgeColor, over)   false if there is no room for it; over:
--                                             drawn over everything, not hidden by what is in front
--   popups.Quad(...)                          as nameplates.Quad, from the popup's point
--   popups.EndPopup()
--   popups.Release(hook)                      on unload: the claim given up, the drawing let go
local bit = require('bit');
local ffi = require('ffi');
local nameplates = require('winxi.nameplates'); -- its quads, drawings and the frame count

ffi.cdef[[
    typedef struct {
        uint32_t Id;
        uint32_t Object;
        uint32_t EntityIndex;
        uint32_t SourceIndex;
        uint32_t Flags;
        uint32_t Color;
        uint32_t FirstFrame;
        float    X, Y, Z;
        float    Scale;
        float    Width, Height;
        float    ScreenX, ScreenY, Depth;
        char     Text[20];
    } namehook_popup_t;

    typedef struct {
        char     Magic[16];
        uint32_t Version;
        uint32_t Size;
        uint32_t PopupSize;
        uint32_t Hooked;
        uint32_t Claimed;
        uint32_t ClaimFrame;
        uint32_t Frame;
        uint32_t Count;
        uint32_t Sequence;
        uint32_t Draw;
        namehook_popup_t Popups[64];
    } namehook_popups_t;

    typedef struct {
        uint32_t Id;
        uint32_t Flags;
        namehook_drawing_t Drawing;
    } namehook_popup_drawing_t;

    typedef struct {
        uint32_t Frame;
        uint32_t QuadCount;
        uint32_t QuadsMax;
        uint32_t Reserved;
        uint32_t Textures[8];
        uint32_t Count;
        uint32_t DrawingsMax;
        namehook_popup_drawing_t Drawings[64];
        namehook_quad_t Quads[4096];
    } namehook_popup_draw_t;
]]

local popups = {};

popups.Flag = {
    Drawn    = 0x01, -- drawn by the game: not claimed
    OnScreen = 0x02, -- ScreenX, ScreenY and Depth are filled in
    Target   = 0x04, -- EntityIndex is who was hit
    Source   = 0x08, -- SourceIndex is who hit them
};

local MAGIC = '4E414D45484F4F4B504F505550530000'; -- "NAMEHOOKPOPUPS" and the two 0s after it
local VERSION = 1;
local LOOK_EVERY = 1; -- seconds between looks for the block while it is not found
local POPUPS_MAX, QUADS_MAX, QUADS_PER_POPUP, TEXTURES = 64, 4096, 256, 8;
local DRAW_OVER = 1;

local block = nil;
local blockGeneration = nil; -- nameplates.Generation() when block was found
local why = 'unloaded';
local lookedAt = -LOOK_EVERY;

local problems = {
    unloaded = 'The namehook plugin is not loaded: /load namehook',
    old      = 'The namehook plugin does not list damage popups: it is older than 1.38.',
    mismatch = 'The namehook plugin keeps its damage popups another way than this addon reads: one of the two is older than the other.',
    unhooked = 'The namehook plugin did not recognise this client\'s damage popups: the game draws them as it does.',
};

-- The block lives in the plugin's DLL, so it is let go of the moment the plugin is no longer loaded,
-- or has been loaded again since it was found (nameplates.Generation).
function popups.Hook()
    if (not AshitaCore:GetPluginManager():IsLoaded(nameplates.Plugin)) then
        block, why, lookedAt = nil, 'unloaded', -LOOK_EVERY;
        return nil, why;
    end
    local generation = nameplates.Generation();
    if (block ~= nil and blockGeneration ~= generation) then
        block, why, lookedAt = nil, 'unloaded', -LOOK_EVERY;
    end
    if (block ~= nil) then
        return block;
    end

    local now = os.clock();
    if (now - lookedAt < LOOK_EVERY) then
        return nil, why;
    end
    lookedAt = now;

    local found = ashita.memory.find(nameplates.Plugin .. '.dll', 0, MAGIC, 0, 0);
    if (found == nil or found == 0) then
        why = 'old';
        return nil, why;
    end
    local candidate = ffi.cast('namehook_popups_t*', found);
    if (candidate.Version ~= VERSION or candidate.Size ~= ffi.sizeof('namehook_popups_t') or candidate.PopupSize ~= ffi.sizeof('namehook_popup_t')) then
        why = 'mismatch';
        return nil, why;
    end
    block, why, blockGeneration = candidate, nil, generation;
    return block;
end

function popups.Problem()
    local hook, reason = popups.Hook();
    if (hook == nil) then
        return problems[reason];
    end
    if (hook.Hooked == 0) then
        return problems.unhooked;
    end
    return nil;
end

local function nothing()
    return nil;
end

local function nextPopup(hook, i)
    if (i < hook.Count and i < POPUPS_MAX) then
        return i + 1, hook.Popups[i];
    end
    return nil;
end

function popups.Each(hook)
    hook = hook or popups.Hook();
    if (hook == nil) then
        return nothing;
    end
    return nextPopup, hook, 0;
end

-- One popup for each hit: of the popups over the same one, from the same one and saying the same,
-- the one the game made first (the lower id: the number, not its copy, which is first listed a frame
-- or so after it); the empty copy of a miss is never one
local hitKeys, hits = {}, {};
function popups.Hits(hook)
    hook = hook or popups.Hook();
    if (hook == nil) then
        return nothing;
    end
    for key in pairs(hitKeys) do
        hitKeys[key] = nil;
    end
    local count = 0;
    for i = 0, math.min(hook.Count, POPUPS_MAX) - 1 do
        local popup = hook.Popups[i];
        if (popup.Text[0] ~= 0) then
            local key = ('%d:%d:%s'):format(popup.EntityIndex, popup.SourceIndex, ffi.string(popup.Text));
            local at = hitKeys[key];
            if (at == nil) then
                count = count + 1;
                hits[count], hitKeys[key] = popup, count;
            elseif (popup.Id < hits[at].Id) then
                hits[at] = popup;
            end
        end
    end
    local i = 0;
    return function ()
        i = i + 1;
        return i <= count and hits[i] or nil;
    end;
end

function popups.Has(popup, flag)
    return bit.band(popup.Flags, flag) ~= 0;
end

function popups.Text(popup)
    local words = ffi.string(popup.Text);
    return words == ':' and 'Miss!' or words;
end

-- The claim is renewed with the names' frame count, which goes on every frame: the popups' own only
-- moves while there are popups
function popups.Claim(hook)
    hook = hook or popups.Hook();
    local names = nameplates.Hook();
    if (hook ~= nil and names ~= nil) then
        hook.Claimed = 1;
        hook.ClaimFrame = names.Frame;
    end
end

local draw = nil;      -- the plugin's place for the drawings, between BeginDrawing and the frame's end
local drawing = nil;   -- the popup being drawn
local horizontalFit = 1;
local quadLimit = 0;

function popups.Release(hook)
    hook = hook or popups.Hook();
    if (hook ~= nil) then
        hook.Claimed = 0;
        if (hook.Draw ~= 0) then
            local target = ffi.cast('namehook_popup_draw_t*', hook.Draw);
            target.Count, target.QuadCount = 0, 0;
            ffi.fill(target.Textures, ffi.sizeof(target.Textures));
        end
    end
    draw, drawing, quadLimit = nil, nil, 0;
end

-- Set out as nameplates.BeginDrawing(hook, true) sets out names: in the game's picture's pixels,
-- uniform in its height, X put right for a picture of another shape than the screen
local imgui = nil;
function popups.BeginDrawing(hook)
    draw, drawing, horizontalFit = nil, nil, 1;
    hook = hook or popups.Hook();
    local names = nameplates.Hook();
    if (hook == nil or names == nil or hook.Hooked == 0 or hook.Draw == 0) then
        return nil;
    end

    draw = ffi.cast('namehook_popup_draw_t*', hook.Draw);
    draw.Frame = names.Frame;
    draw.Count = 0;
    draw.QuadCount = 0;
    draw.Reserved = 0;
    quadLimit = math.min(draw.QuadsMax, QUADS_MAX);

    imgui = imgui or require('imgui');
    local display = imgui.GetIO().DisplaySize;
    local width = display.x > 0 and display.x or names.Width;
    local height = display.y > 0 and display.y or names.Height;
    if (names.TargetWidth > 0 and names.TargetHeight > 0 and width > 0 and height > 0) then
        local scaleX, scaleY = names.TargetWidth / width, names.TargetHeight / height;
        horizontalFit = scaleX / scaleY;
        draw.Reserved = math.max(1, math.min(0xFFFFFFFF, math.floor(horizontalFit * 65536 + 0.5)));
        return scaleY;
    end
    return 1;
end

function popups.SetTexture(slot, texture)
    if (draw ~= nil and slot >= 0 and slot < TEXTURES) then
        draw.Textures[slot] = texture or 0;
    end
end

function popups.BeginPopup(popup, alpha, edge, edgeColor, over)
    drawing = nil;
    if (draw == nil or draw.Count >= math.min(draw.DrawingsMax, POPUPS_MAX) or draw.QuadCount >= quadLimit) then
        return false;
    end
    local one = draw.Drawings[draw.Count];
    one.Id = popup.Id;
    one.Flags = over and DRAW_OVER or 0;
    drawing = one.Drawing;
    drawing.Frame = draw.Frame;
    drawing.First = draw.QuadCount;
    drawing.Count = 0;
    drawing.Alpha = alpha or 1;
    drawing.Edge = edge or 0;
    drawing.EdgeColor = edgeColor or 0;
    return true;
end

function popups.Quad(x0, y0, x1, y1, u0, v0, u1, v1, color, slot, edged, edgeOpacity, softRect, tightEdge, edgeRadius, doubled)
    if (drawing == nil or drawing.Count >= QUADS_PER_POPUP or drawing.First + drawing.Count >= quadLimit) then
        return;
    end
    nameplates.FillQuad(draw.Quads[drawing.First + drawing.Count], horizontalFit,
        x0, y0, x1, y1, u0, v0, u1, v1, color, slot, edged, edgeOpacity, softRect, tightEdge, edgeRadius, doubled);
    drawing.Count = drawing.Count + 1;
end

-- A drawing is counted once it is ended, with whatever quads it has
function popups.EndPopup()
    if (drawing ~= nil) then
        draw.QuadCount = drawing.First + drawing.Count;
        if (drawing.Count > 0) then
            draw.Count = draw.Count + 1;
        end
        drawing = nil;
    end
end

return popups;
