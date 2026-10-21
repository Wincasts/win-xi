-- winxi.nameplates: the names the game draws over characters' heads, by way of the namehook
-- plugin: what each one is, where it is, and whether it is shown.
--
-- The plugin sorts every name into one category, shows or hides each category's names, and keeps a
-- list of the names the game was about to draw last frame, the hidden ones among them. This reads the
-- list and sets what is shown. It needs nothing else of winxi, and can be copied out by itself.
--
--   nameplates.Hook()                 the plugin's block, or nil and why not; everything below is
--                                     nothing, or does nothing, while there is none
--   nameplates.Problem()              a sentence for the user while something is wrong, or nil
--
--   for i, name in nameplates.Each() do ... end    the names of the last frame
--   nameplates.Count()                how many there are
--   nameplates.Find(entityIndex)      the name over one entity, or nil if none was to be drawn
-- Each, Find, Count and Screen take the plugin's block as a last argument, for an addon that has it
-- already: see nameplates.Hook below.
--
-- A name is the plugin's own record, read in place and good for this frame only:
--   name.EntityIndex, name.ServerId
--   name.Category                     one of nameplates.Category
--   name.Flags                        nameplates.Flag, asked with nameplates.Has(name, flag)
--   name.X, name.Y, name.Z            where the game puts the name, in the world: the point above the head
--   name.Scale                        1 near to, falling to 0 as it nears the distance it is not drawn at
--   name.NameColor, name.IconColor    the game's colours for the name and the linkshell pearl, with
--                                     0x80 for full: 0xAARRGGBB and 0xAABBGGRR
--   nameplates.Name(name)             the entity's name
--   nameplates.Text(name)             the name as the game writes it: its icons, a byte each, then the name
--   nameplates.Screen(name, hook)     where it is on screen, in imgui's pixels: x, y, or nil behind the camera
--
-- What is shown:
--   nameplates.IsHidden(category), nameplates.SetHidden(category, hidden)
--   nameplates.Hidden(), nameplates.SetAllHidden(categories)      all of them at once, as one number
--   nameplates.AlwaysTarget(), nameplates.SetAlwaysTarget(on)     the target's name, whatever its category
--   nameplates.Override(entityIndex, show)    one entity's name: true shown, false hidden, nil by its category
--   nameplates.ClearOverrides()
--
-- An addon that draws names itself asks the game not to, every frame it does so:
--   nameplates.Claim(categories)      these categories' names are listed as wanted, and not drawn by the game
-- A claim not made again lapses in half a second, and the game draws the names as before.
--
-- Or it has the plugin draw them for it, in the game's own picture, where what is in front of a name
-- hides it as it hides the game's. Every frame:
--   local scale = nameplates.BeginDrawing()       nil if the plugin cannot; else how many pixels of the
--                                                 game's picture there are to one of the screen's
--   BeginDrawing(hook, true) uses the live output's vertical ratio and converts Quad X coordinates
--   by the horizontal/vertical ratio, for uniformly laid out fonts on nonuniform render targets.
--   Without that opt-in, coordinates and the returned horizontal ratio retain their legacy meaning.
--   nameplates.SetTexture(slot, texture)          slot 0 to 7; texture a Direct3D texture's address,
--                                                 or winxi.fonts.TextureMark for imgui's font texture,
--                                                 which the plugin reads itself (hook.FontTexture says
--                                                 which it last drew from, 0 for none)
--   nameplates.BeginName(entityIndex, alpha, edge, edgeColor)   false if there is no room for it
--   nameplates.Quad(x0, y0, x1, y1, u0, v0, u1, v1, color, slot, edged, edgeOpacity)
--   nameplates.EndName()
-- A quad is a rectangle of a texture: its corners are in pixels of the game's picture, measured from
-- the point the game puts the name at, and its colour is 0xAARRGGBB. alpha, 0 to 1, fades the whole
-- name; edge is how thick a dark edge the edged quads are given, and edgeColor its colour.
-- Quad's optional edgeOpacity (0 to 1, default 1) softens just that quad's edge;
-- its fill is unchanged. Older plugins ignore this optional per-quad effect. Names are
-- claimed with nameplates.Claim as before: the plugin draws the wanted ones the addon has drawn, a
-- frame after it drew them, and draws nothing for the others.
--
-- nameplates.Hook asks Ashita whether the plugin is still loaded, which is not free. An addon that
-- has just asked can hand what it was given to nameplates.Claim(categories, hook),
-- nameplates.BeginDrawing(hook), nameplates.Each(hook), nameplates.Find(entityIndex, hook),
-- nameplates.Count(hook) and nameplates.Screen(name, hook), and read hook.Hidden, hook.Options and
-- hook.Names itself: within one frame the plugin cannot have gone. (The answer is not kept here from
-- one call to the next: the plugin can be unloaded between two frames, and its block goes with it.)
--
-- Entities are known by index, which another entity has after a change of area: an addon that
-- overrides names clears them then.
local bit = require('bit');
local ffi = require('ffi');

ffi.cdef[[
    typedef struct {
        uint32_t EntityIndex;
        uint32_t ServerId;
        uint32_t Category;
        uint32_t Flags;
        float    X, Y, Z;
        float    Scale;
        float    ScreenX, ScreenY;
        float    Depth;
        uint32_t NameColor;
        uint32_t IconColor;
        char     Name[28];
        char     Text[48];
    } namehook_name_t;

    typedef struct {
        char     Magic[16];
        uint32_t Version;
        uint32_t Size;
        uint32_t NameSize;
        uint32_t Hooked;
        uint32_t Hidden;
        uint32_t Options;
        uint32_t Claimed;
        uint32_t ClaimFrame;
        uint32_t Frame;
        uint32_t Count;
        float    Width, Height;
        uint32_t Sequence;
        uint32_t Draw;
        float    TargetWidth, TargetHeight;
        uint32_t FontTexture;
        uint8_t  Override[0x900];
        namehook_name_t Names[256];
    } namehook_t;

    typedef struct {
        float    X0, Y0, X1, Y1;
        float    U0, V0, U1, V1;
        uint32_t Color;
        uint32_t Texture;
        uint32_t Flags;
        uint32_t Reserved;
    } namehook_quad_t;

    typedef struct {
        uint32_t Frame;
        uint32_t First;
        uint32_t Count;
        float    Alpha;
        float    Edge;
        uint32_t EdgeColor;
    } namehook_drawing_t;

    typedef struct {
        uint32_t Frame;
        uint32_t QuadCount;
        uint32_t QuadsMax;
        uint32_t Reserved;
        uint32_t Textures[8];
        namehook_drawing_t Entities[0x900];
        namehook_quad_t Quads[16384];
    } namehook_draw_t;
]]

local nameplates = {};

nameplates.Plugin = 'namehook';

nameplates.Category = {
    Self     = 0x01, -- the player
    Party    = 0x02, -- the others of the party, trusts among them
    Alliance = 0x04, -- the other parties of the alliance
    Player   = 0x08, -- every other player
    MyPet    = 0x10, -- the player's pet
    Pet      = 0x20, -- anyone else's pet, trust or fellow
    Npc      = 0x40, -- what cannot be fought
    Monster  = 0x80, -- what can, charmed players among them
    All      = 0xFF,
};

-- The categories in order, each with its key in nameplates.Category
nameplates.Categories = { 'Self', 'Party', 'Alliance', 'Player', 'MyPet', 'Pet', 'Npc', 'Monster' };

nameplates.Flag = {
    Wanted      = 0x01, -- not hidden by its category, or shown in spite of it
    Drawn       = 0x02, -- drawn by the game: wanted, and not claimed by an addon
    Stars       = 0x04, -- the game was about to draw the Job Mastery stars over it
    Target      = 0x08, -- it is the player's target
    Charmed     = 0x10, -- a player who can be fought
    Whitelisted = 0x20, -- a player on the plugin's whitelist
    OnScreen    = 0x40, -- in front of the camera
    Overridden  = 0x80, -- shown or hidden by nameplates.Override, and not by its category
    Custom      = 0x100, -- drawn by the plugin, from what an addon drew for it
};

local MAGIC        = '4E414D45484F4F4B0000000000000000'; -- "NAMEHOOK" and the eight 0s after it
local VERSION      = 3;
local LOOK_EVERY   = 1; -- seconds between looks for the plugin's block while it is not found
local ENTITIES     = 0x900;
local ALWAYS_TARGET = 0x01;
local OVERRIDE_SHOW, OVERRIDE_HIDE = 1, 2;

local block = nil;         -- the plugin's block, while the plugin is loaded
local why = 'unloaded';    -- why there is none: 'unloaded', 'old' or 'mismatch'
local lookedAt = -LOOK_EVERY;

local problems = {
    unloaded = 'The namehook plugin is not loaded: /load namehook',
    old      = 'The namehook plugin has nothing to read: it is not the plugin this addon was written for.',
    mismatch = 'The namehook plugin keeps its names another way than this addon reads: one of the two is older than the other.',
    unhooked = 'The namehook plugin did not recognise this client\'s name drawing: names are shown and hidden, but none are listed.',
};

-- The block lives in the plugin's DLL, so it is let go of the moment the plugin is no longer loaded.
function nameplates.Hook()
    if (not AshitaCore:GetPluginManager():IsLoaded(nameplates.Plugin)) then
        block, why = nil, 'unloaded';
        lookedAt = -LOOK_EVERY;
        return nil, why;
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

    local candidate = ffi.cast('namehook_t*', found);
    if (candidate.Version ~= VERSION or candidate.Size ~= ffi.sizeof('namehook_t') or candidate.NameSize ~= ffi.sizeof('namehook_name_t')) then
        why = 'mismatch';
        return nil, why;
    end

    block, why = candidate, nil;
    return block;
end

function nameplates.Problem()
    local hook, reason = nameplates.Hook();
    if (hook == nil) then
        return problems[reason];
    end
    if (hook.Hooked == 0) then
        return problems.unhooked;
    end
    return nil;
end

function nameplates.Count(hook)
    hook = hook or nameplates.Hook();
    return hook ~= nil and hook.Count or 0;
end

local function nothing()
    return nil;
end

local function nextName(hook, i)
    if (i < hook.Count) then
        return i + 1, hook.Names[i];
    end
    return nil;
end

function nameplates.Each(hook)
    hook = hook or nameplates.Hook();
    if (hook == nil) then
        return nothing;
    end
    return nextName, hook, 0;
end

-- Where each entity's name is in the list, worked out once each time the plugin makes the list ready:
-- the one table, emptied and filled again, as that is once a frame
local places = {};
local placedAt = nil;

function nameplates.Find(entityIndex, hook)
    hook = hook or nameplates.Hook();
    if (hook == nil) then
        return nil;
    end

    if (placedAt ~= hook.Sequence) then
        placedAt = hook.Sequence;
        for index in pairs(places) do
            places[index] = nil;
        end
        for i = 0, hook.Count - 1 do
            places[hook.Names[i].EntityIndex] = i;
        end
    end

    local place = places[entityIndex];
    if (place == nil or place >= hook.Count) then
        return nil;
    end
    return hook.Names[place];
end

function nameplates.Has(name, flag)
    return bit.band(name.Flags, flag) ~= 0;
end

function nameplates.Name(name)
    return ffi.string(name.Name);
end

function nameplates.Text(name)
    return ffi.string(name.Text);
end

-- The plugin's places are in the client's window; imgui's are in the picture Ashita draws on, which
-- is the same size unless something has made it otherwise. The plugin projects flat, so a point is
-- moved by lens's warp too.
local imgui = nil; -- asked for on first use, so that this file loads where there is none

function nameplates.Screen(name, hook)
    hook = hook or nameplates.Hook();
    if (hook == nil or bit.band(name.Flags, nameplates.Flag.OnScreen) == 0 or hook.Width <= 0 or hook.Height <= 0) then
        return nil;
    end

    imgui = imgui or require('imgui');
    local display = imgui.GetIO().DisplaySize;
    -- moved to where the lens plugin's warp shows the point, when it draws the world bent
    local lens = require('winxi.lens');
    return lens.Point(lens.Current(), name.ScreenX * display.x / hook.Width, name.ScreenY * display.y / hook.Height, display.x, display.y);
end

function nameplates.Hidden()
    local hook = nameplates.Hook();
    return hook ~= nil and hook.Hidden or 0;
end

function nameplates.SetAllHidden(categories)
    local hook = nameplates.Hook();
    if (hook ~= nil) then
        hook.Hidden = bit.band(categories, nameplates.Category.All);
    end
end

function nameplates.IsHidden(category)
    return bit.band(nameplates.Hidden(), category) ~= 0;
end

function nameplates.SetHidden(category, hidden)
    local hook = nameplates.Hook();
    if (hook ~= nil) then
        hook.Hidden = hidden and bit.bor(hook.Hidden, category) or bit.band(hook.Hidden, bit.bnot(category));
    end
end

function nameplates.AlwaysTarget()
    local hook = nameplates.Hook();
    return hook ~= nil and bit.band(hook.Options, ALWAYS_TARGET) ~= 0;
end

function nameplates.SetAlwaysTarget(on)
    local hook = nameplates.Hook();
    if (hook ~= nil) then
        hook.Options = on and bit.bor(hook.Options, ALWAYS_TARGET) or bit.band(hook.Options, bit.bnot(ALWAYS_TARGET));
    end
end

function nameplates.Override(entityIndex, show)
    local hook = nameplates.Hook();
    if (hook ~= nil and entityIndex >= 0 and entityIndex < ENTITIES) then
        hook.Override[entityIndex] = (show == nil) and 0 or (show and OVERRIDE_SHOW or OVERRIDE_HIDE);
    end
end

function nameplates.ClearOverrides()
    local hook = nameplates.Hook();
    if (hook ~= nil) then
        ffi.fill(hook.Override, ENTITIES);
    end
end

function nameplates.Claim(categories, hook)
    hook = hook or nameplates.Hook();
    if (hook ~= nil) then
        hook.Claimed = bit.band(categories or nameplates.Category.All, nameplates.Category.All);
        hook.ClaimFrame = hook.Frame;
    end
end

-- Names drawn for the plugin to put in the picture
local draw = nil;      -- the plugin's place for them, between BeginDrawing and the frame's end
local drawing = nil;   -- the name being drawn
local horizontalFit = 1; -- opt-in correction from vertical layout pixels to target X pixels
local quadLimit = 0;   -- how many quads the plugin has room for, as BeginDrawing found it
local QUADS_PER_NAME = 256;
local QUADS_MAX = 16384;
local TEXTURES = 8;

function nameplates.BeginDrawing(hook, correctAspect)
    draw, drawing = nil, nil;
    horizontalFit = 1;

    hook = hook or nameplates.Hook();
    if (hook == nil or hook.Hooked == 0 or hook.Draw == 0) then
        return nil;
    end

    draw = ffi.cast('namehook_draw_t*', hook.Draw);
    draw.Frame = hook.Frame;
    draw.QuadCount = 0;
    draw.Reserved = 0; -- legacy outlines: equal target-pixel X/Y offsets
    quadLimit = math.min(draw.QuadsMax, QUADS_MAX);

    -- Name's layouts are uniform in vertical target pixels. Convert their X coordinates
    -- separately when submitting quads. The live display is the final output, not the
    -- client's potentially differently-sized menu coordinate system. Legacy callers
    -- retain the original target-pixel API unless they opt in.
    if (correctAspect) then
        imgui = imgui or require('imgui');
        local display = imgui.GetIO().DisplaySize;
        local width = display.x > 0 and display.x or hook.Width;
        local height = display.y > 0 and display.y or hook.Height;
        if (hook.TargetWidth > 0 and hook.TargetHeight > 0 and width > 0 and height > 0) then
            local scaleX, scaleY = hook.TargetWidth / width, hook.TargetHeight / height;
            horizontalFit = scaleX / scaleY;
            -- Optional 16.16 X/Y outline ratio; older plugins safely ignore it.
            draw.Reserved = math.max(1, math.min(0xFFFFFFFF, math.floor(horizontalFit * 65536 + 0.5)));
            return scaleY;
        end
        return 1;
    end

    -- until the plugin has seen a name drawn it does not know the size of the game's picture
    if (hook.TargetWidth <= 0 or hook.Width <= 0) then
        return 1;
    end
    return hook.TargetWidth / hook.Width;
end

function nameplates.SetTexture(slot, texture)
    if (draw ~= nil and slot >= 0 and slot < TEXTURES) then
        draw.Textures[slot] = texture or 0;
    end
end

function nameplates.BeginName(entityIndex, alpha, edge, edgeColor)
    drawing = nil;
    if (draw == nil or entityIndex < 0 or entityIndex >= ENTITIES or draw.QuadCount >= quadLimit) then
        return false;
    end

    drawing = draw.Entities[entityIndex];
    drawing.Frame = draw.Frame;
    drawing.First = draw.QuadCount;
    drawing.Count = 0;
    drawing.Alpha = alpha or 1;
    drawing.Edge = edge or 0;
    drawing.EdgeColor = edgeColor or 0;
    return true;
end

function nameplates.Quad(x0, y0, x1, y1, u0, v0, u1, v1, color, slot, edged, edgeOpacity)
    if (drawing == nil or drawing.Count >= QUADS_PER_NAME or drawing.First + drawing.Count >= quadLimit) then
        return;
    end

    local flags, reserved = edged and 1 or 0, 0;
    if (edged and edgeOpacity ~= nil) then
        -- edged, with explicit edge opacity in Reserved's low byte
        flags, reserved = 3, math.floor(math.max(0, math.min(1, edgeOpacity)) * 255 + 0.5);
    end
    local quad = draw.Quads[drawing.First + drawing.Count];
    quad.X0, quad.Y0, quad.X1, quad.Y1 = x0 * horizontalFit, y0, x1 * horizontalFit, y1;
    quad.U0, quad.V0, quad.U1, quad.V1 = u0, v0, u1, v1;
    quad.Color = color;
    quad.Texture = slot or 0;
    quad.Flags = flags;
    quad.Reserved = reserved;
    drawing.Count = drawing.Count + 1;
end

function nameplates.EndName()
    if (drawing ~= nil) then
        draw.QuadCount = drawing.First + drawing.Count;
        drawing = nil;
    end
end

return nameplates;
