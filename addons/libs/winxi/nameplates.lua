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
--   nameplates.SetTexture(slot, texture)          slot 0 to 7 (to 31 with namehook 1.43: nameplates.TextureSlots); texture a Direct3D texture's address,
--                                                 or winxi.fonts.TextureMark for imgui's font texture,
--                                                 which the plugin reads itself (hook.FontTexture says
--                                                 which it last drew from, 0 for none)
--   nameplates.BeginName(entityIndex, alpha, edge, edgeColor)   false if there is no room for it
--   nameplates.Quad(x0, y0, x1, y1, u0, v0, u1, v1, color, slot, edged, edgeOpacity, softRect, tightEdge, edgeRadius, doubled)
--                                     doubled: the colour is doubled as the game's own are, 0x80 the texture as it
--                                     is and more brightening it, its edge not (namehook 1.36, Feature.Doubled).
--                                     edgeRadius: independent target-pixel width, including when text edge is zero (1.34).
--                                     tightEdge: cap an icon halo at one target pixel, no shadow (namehook 1.33).
--                                     softRect: antialias an unedged rectangle (namehook 1.32), a textured one too
--                                     (namehook 1.37, Feature.SoftTexture).
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
local abi = require('winxi.abi');

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
        uint32_t LoadId;          // namehook 1.42: read only where abi.Has says it is there
        uint32_t NamesDropped;
        uint32_t DrawingsRefused;
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
        uint32_t TexturesExtra[24]; // namehook 1.43, Feature.Textures32: written only then
    } namehook_draw_t;

    typedef struct {
        uint32_t Owner;
        uint32_t Categories;
        uint32_t ClaimFrame;
        uint32_t Priority;
        uint32_t Draw;
        uint32_t Reserved[3];
    } namehook_claim_slot_t;

    typedef struct {
        char     Magic[16];
        uint32_t Version;
        uint32_t Size;
        uint32_t SlotSize;
        uint32_t SlotsMax;
        uint32_t SharedPriority;
        uint32_t Reserved[3];
        namehook_claim_slot_t Slots[3];
    } namehook_claims_t;
]]

local nameplates = {};

nameplates.Plugin = 'namehook';
nameplates.Feature = { IconOutline = 1, SoftRectangle = 2, TightEdge = 4, Doubled = 8, SoftTexture = 16, Textures32 = 32 };
ffi.cdef[[
    typedef struct {
        char Magic[16];
        uint32_t Size, Version, Features, Build;
    } namehook_capabilities_t;
]];

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
local module = nil;        -- the plugin's DLL the block was found in: { base, stamp, size }
local loadId = nil;        -- the load the block was found in (namehook 1.42's LoadId), nil before that
local generation = 0;      -- counts each time what was found in the plugin's DLL is let go of
local why = 'unloaded';    -- why there is none: 'unloaded', 'old' or 'mismatch'
local lookedAt = -LOOK_EVERY;
local capabilities, capabilityOwner, capabilityLookedAt = nil, nil, -LOOK_EVERY;
-- Connection-owned caches must be forgotten even if the DLL reloads at the same address.
local places, placedAt, placedOwner = {}, nil, nil;
local draw, drawing, quadLimit = nil, nil, 0;

local problems = {
    unloaded = 'The namehook plugin is not loaded: /load namehook',
    old      = 'The namehook plugin has nothing to read: it is not the plugin this addon was written for.',
    mismatch = 'The namehook plugin keeps its names another way than this addon reads: one of the two is older than the other.',
    unhooked = 'The namehook plugin did not recognise this client\'s name drawing: names are shown and hidden, but none are listed.',
};

pcall(ffi.cdef, [[
    void* __stdcall winxi_nameplates_GetModuleHandleA(const char*) __asm__("GetModuleHandleA");
]]);
local kernel = nil;

-- The plugin's DLL as it is loaded now: where, and which build (its header's time stamp and size), or
-- nil. The plugin can be unloaded and loaded again between two looks, at another address or as
-- another build: what was found in the old one is then gone, though Ashita says it is loaded.
-- (Away from Windows, as in the tests, there is no DLL to ask: one that never changes.)
function nameplates.Module()
    if (ffi.os ~= 'Windows') then return 1, 0, 0; end
    local ok, base = pcall(function()
        kernel = kernel or ffi.load('kernel32');
        return kernel.winxi_nameplates_GetModuleHandleA(nameplates.Plugin .. '.dll');
    end);
    if (not ok or base == nil) then return nil; end
    local at = tonumber(ffi.cast('uintptr_t', base));
    if (at == 0) then return nil; end
    local header = at + ffi.cast('uint32_t*', at + 0x3C)[0];
    return at, ffi.cast('uint32_t*', header + 8)[0], ffi.cast('uint32_t*', header + 0x50)[0];
end

local function LetGo(reason)
    if (block ~= nil or module ~= nil or capabilities ~= nil) then generation = generation + 1; end
    block, module, loadId, why = nil, nil, nil, reason;
    capabilities, capabilityOwner, capabilityLookedAt = nil, nil, -LOOK_EVERY;
    lookedAt = -LOOK_EVERY;
    placedAt, placedOwner = nil, nil;
    draw, drawing, quadLimit = nil, nil, 0;
end

-- Changes each time anything found in the plugin's DLL is let go of: an addon that keeps a block of
-- the plugin's own (popups, bubbles) lets it go too when this is not what it was when it found it.
function nameplates.Generation()
    nameplates.Hook();
    return generation;
end

-- The block lives in the plugin's DLL, so it is let go of the moment the plugin is no longer loaded,
-- or is no longer the DLL it was found in.
function nameplates.Hook()
    if (not AshitaCore:GetPluginManager():IsLoaded(nameplates.Plugin)) then
        LetGo('unloaded');
        return nil, why;
    end
    local base, stamp, size = nameplates.Module();
    if (base == nil) then
        LetGo('unloaded');
        return nil, why;
    end
    if (module ~= nil and (module.base ~= base or module.stamp ~= stamp or module.size ~= size)) then
        LetGo('unloaded');
    end
    -- loaded again at the same address as the same build: another load all the same (namehook 1.42).
    -- Read only once the DLL is known to be the one the block was found in, so the memory is there.
    if (block ~= nil and loadId ~= nil and block.LoadId ~= loadId) then
        LetGo('unloaded');
    end
    if (module == nil) then
        module = { base = base, stamp = stamp, size = size };
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
    if (not abi.Accepts(candidate, 'namehook_t', VERSION, 'LoadId') or candidate.NameSize ~= ffi.sizeof('namehook_name_t')) then
        why = 'mismatch';
        return nil, why;
    end

    block, why = candidate, nil;
    loadId = abi.Has(candidate, 'namehook_t', 'LoadId') and candidate.LoadId or nil;
    placedAt, placedOwner = nil, nil;
    draw, drawing, quadLimit = nil, nil, 0;
    return block;
end

-- What did not make it, for diagnostics: { namesDropped, drawingsRefused, namesRefused, quadsRefused }.
-- namesDropped: the names the client drew last frame that the list had no room for; drawingsRefused:
-- addons' drawings the plugin refused since it was loaded (more quads than a name may have, or past the
-- end of the quads); both nil from a namehook before 1.42, which does not count them. namesRefused and
-- quadsRefused: what this addon could not hand over since it was loaded, the buffer or a name being full.
function nameplates.Dropped(hook)
    hook = hook or nameplates.Hook();
    local counted = hook ~= nil and abi.Has(hook, 'namehook_t', 'DrawingsRefused');
    return {
        namesDropped = counted and tonumber(hook.NamesDropped) or nil,
        drawingsRefused = counted and tonumber(hook.DrawingsRefused) or nil,
        namesRefused = namesRefused,
        quadsRefused = quadsRefused,
    };
end

-- The optional sidecar is separate from ABI 3, so older consumers still work.
-- Missing/malformed capability blocks are never treated as implicit support.
function nameplates.Supports(features, hook)
    hook = hook or nameplates.Hook();
    if hook == nil then return false; end
    if capabilityOwner ~= hook then
        capabilities, capabilityOwner, capabilityLookedAt = nil, hook, -LOOK_EVERY;
    end
    if capabilities == nil and os.clock() - capabilityLookedAt >= LOOK_EVERY then
        capabilityLookedAt = os.clock();
        local found = ashita.memory.find(nameplates.Plugin .. '.dll', 0,
            '4E414D45484F4F4B4341505300000000', 0, 0); -- NAMEHOOKCAPS + four zeroes
        if found ~= nil and found ~= 0 then
            local candidate = ffi.cast('namehook_capabilities_t*', found);
            if abi.Accepts(candidate, 'namehook_capabilities_t', 1) then
                capabilities = candidate;
            end
        end
    end
    return capabilities ~= nil and bit.band(capabilities.Features, features) == bit.tobit(features);
end

-- Copy only public capability metadata, never expose a cached DLL pointer.
function nameplates.Capabilities(hook)
    hook = hook or nameplates.Hook();
    if hook == nil or not nameplates.Supports(0, hook) then return nil; end
    return { version = tonumber(capabilities.Version), features = tonumber(capabilities.Features), build = tonumber(capabilities.Build) };
end

function nameplates.Problem(requiredFeatures)
    local hook, reason = nameplates.Hook();
    if (hook == nil) then
        return problems[reason];
    end
    if (hook.Hooked == 0) then
        return problems.unhooked;
    end
    if requiredFeatures and not nameplates.Supports(requiredFeatures, hook) then
        return 'Name requires namehook 1.35 or newer for independent icon outlines. Update namehook.dll and reload the plugin.';
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
function nameplates.Find(entityIndex, hook)
    hook = hook or nameplates.Hook();
    if (hook == nil) then
        return nil;
    end

    if (placedAt ~= hook.Sequence or placedOwner ~= hook) then
        placedAt, placedOwner = hook.Sequence, hook;
        for index in pairs(places) do
            places[index] = nil;
        end
        for i = 0, hook.Count - 1 do
            places[hook.Names[i].EntityIndex] = i;
        end
    end

    local place = places[entityIndex];
    if (place == nil or place >= hook.Count or hook.Names[place].EntityIndex ~= entityIndex) then
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
-- draw/drawing/quadLimit are connection-owned and declared beside Hook's caches.
local horizontalFit = 1; -- opt-in correction from vertical layout pixels to target X pixels
local QUADS_PER_NAME = 256;
local QUADS_MAX = 16384;
local TEXTURES = 8;
local TEXTURES_ALL = 32; -- with Feature.Textures32 (namehook 1.43): slots 8 to 31 in TexturesExtra
local extras = false;    -- whether the plugin's buffer has TexturesExtra, as BeginDrawing found

-- How many texture slots an addon may give: 32 with namehook 1.43 (Feature.Textures32), 8 before
function nameplates.TextureSlots()
    return nameplates.Supports(nameplates.Feature.Textures32) and TEXTURES_ALL or TEXTURES;
end

-- Invalidate the ordinary-name buffer before releasing its owned textures.
-- Never follow a cached DLL pointer after unload; resolve a current Hook first.
-- Speech bubbles own a different buffer and are not touched here.
function nameplates.ClearDrawing(hook)
    -- Drop cached writer pointers before resolving the current connection or freeing owners.
    draw, drawing, quadLimit = nil, nil, 0;
    hook = hook or nameplates.Hook();
    if hook ~= nil and hook.Draw ~= nil and hook.Draw ~= 0 then
        local target = ffi.cast('namehook_draw_t*', hook.Draw);
        target.QuadCount = 0;
        ffi.fill(target.Textures, ffi.sizeof(target.Textures));
        -- only where the plugin's buffer has them: nothing else says how large it is
        if nameplates.Supports(nameplates.Feature.Textures32) then
            ffi.fill(target.TexturesExtra, ffi.sizeof(target.TexturesExtra));
        end
        target.Frame = hook.Frame - 9; -- beyond HOOK_DRAW_FRAMES, including frame wrap
    end
end

function nameplates.BeginDrawing(hook, correctAspect)
    -- asked first: asking may look for the plugin again, and that lets go of a buffer already taken
    local supportsExtras = nameplates.Supports(nameplates.Feature.Textures32);
    draw, drawing = nil, nil;
    horizontalFit = 1;

    hook = hook or nameplates.Hook();
    if (hook == nil or hook.Hooked == 0 or hook.Draw == 0) then
        return nil;
    end

    draw = ffi.cast('namehook_draw_t*', hook.Draw);
    extras = supportsExtras;
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

-- slot 0 to 7, or to 31 with namehook 1.43 (nameplates.TextureSlots): false where it cannot be given
function nameplates.SetTexture(slot, texture)
    if (draw == nil or slot < 0) then return false; end
    if (slot < TEXTURES) then
        draw.Textures[slot] = texture or 0;
        return true;
    end
    if (extras and slot < TEXTURES_ALL) then
        draw.TexturesExtra[slot - TEXTURES] = texture or 0;
        return true;
    end
    return false;
end

-- What this addon could not hand over since it was loaded: names begun with the buffer full, and quads
-- past a name's 256 or the buffer's end. Read by nameplates.Dropped.
local namesRefused, quadsRefused = 0, 0;

function nameplates.BeginName(entityIndex, alpha, edge, edgeColor)
    drawing = nil;
    if (draw == nil or entityIndex < 0 or entityIndex >= ENTITIES) then
        return false;
    end
    if (draw.QuadCount >= quadLimit) then
        namesRefused = namesRefused + 1;
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

-- One quad written into the plugin's buffer, as nameplates.Quad takes it: for winxi.popups too
function nameplates.FillQuad(quad, fit, x0, y0, x1, y1, u0, v0, u1, v1, color, slot, edged, edgeOpacity, softRect, tightEdge, edgeRadius, doubled)
    local flags, reserved = edged and 1 or 0, 0;
    if (edged and edgeOpacity ~= nil) then
        -- edged, with explicit edge opacity in Reserved's low byte
        flags, reserved = 3, math.floor(math.max(0, math.min(1, edgeOpacity)) * 255 + 0.5);
    end
    -- Only unedged rectangles take the screen-space alpha fringe; a textured one since namehook 1.37
    -- (Feature.SoftTexture). Older builds draw that one, and any with the flag they cannot, hard.
    if (softRect and not edged) then flags = bit.bor(flags, 4); end
    if (tightEdge and edged) then flags = bit.bor(flags, 8); end
    if (edged and edgeRadius ~= nil) then
        flags = bit.bor(flags, 16);
        reserved = reserved + math.floor(math.max(0, math.min(8, edgeRadius)) * 256 + 0.5) * 256;
    end
    -- an older plugin knows nothing of it, and draws the colour as it is
    if (doubled) then flags = bit.bor(flags, 32); end
    quad.X0, quad.Y0, quad.X1, quad.Y1 = x0 * fit, y0, x1 * fit, y1;
    quad.U0, quad.V0, quad.U1, quad.V1 = u0, v0, u1, v1;
    quad.Color = color;
    quad.Texture = slot or 0;
    quad.Flags = flags;
    quad.Reserved = reserved;
end

function nameplates.Quad(x0, y0, x1, y1, u0, v0, u1, v1, color, slot, edged, edgeOpacity, softRect, tightEdge, edgeRadius, doubled)
    if (drawing == nil) then
        return;
    end
    if (drawing.Count >= QUADS_PER_NAME or drawing.First + drawing.Count >= quadLimit) then
        quadsRefused = quadsRefused + 1;
        return;
    end
    nameplates.FillQuad(draw.Quads[drawing.First + drawing.Count], horizontalFit,
        x0, y0, x1, y1, u0, v0, u1, v1, color, slot, edged, edgeOpacity, softRect, tightEdge, edgeRadius, doubled);
    drawing.Count = drawing.Count + 1;
end

function nameplates.EndName()
    if (drawing ~= nil) then
        draw.QuadCount = drawing.First + drawing.Count;
        drawing = nil;
    end
end

-- A second addon drawing names (namehook 1.45): beside the one claiming through the plugin's own claim (Name,
-- with nameplates.Claim), up to three more each take a claim slot and draw into its own buffer. Of those
-- claiming a name's category, by priority, highest first, the first that has drawn the name draws it; the
-- plugin's own claim is priority 100 (nameplates.SharedPriority). Each frame:
--
--   local owner = nameplates.OwnerOf(addon.name)          -- a number of the addon's own, never 0
--   slot = slot or nameplates.TakeSlot(owner)             -- nil and why where none is free or the plugin is older
--   if slot and nameplates.ClaimSlot(slot, owner, categories, priority) then
--       local scale = nameplates.BeginDrawing(nameplates.SlotDrawing(slot), true)
--       ... nameplates.BeginName / Quad / EndName, nameplates.SetTexture, as for the plugin's own claim
--   else slot = nil end                                    -- lost (it lapsed and another took it): take one again
--
-- and nameplates.ReleaseSlot(slot, owner) on unload. A claim not renewed lapses in half a second, and the
-- plugin frees the slot.
local CLAIMS_MAGIC = '4E414D45484F4F4B434C41494D530000'; -- "NAMEHOOKCLAIMS" and the two 0s after it
local claims, claimsGeneration, claimsLookedAt = nil, nil, -LOOK_EVERY;

nameplates.SharedPriority = 100;

-- The plugin's claim slots (its HookClaims), or nil and why not
function nameplates.Claims()
    local hook = nameplates.Hook();
    if (hook == nil) then claims, claimsLookedAt = nil, -LOOK_EVERY; return nil, problems.unloaded; end
    local generation = nameplates.Generation();
    if (claims ~= nil and claimsGeneration ~= generation) then claims, claimsLookedAt = nil, -LOOK_EVERY; end
    if (claims == nil) then
        local now = os.clock();
        if (now - claimsLookedAt < LOOK_EVERY) then return nil, 'Looking for namehook\'s claim slots.'; end
        claimsLookedAt = now;
        local found = ashita.memory.find(nameplates.Plugin .. '.dll', 0, CLAIMS_MAGIC, 0, 0);
        if (found == nil or found == 0) then return nil, 'A second names addon needs namehook 1.45 or newer.'; end
        local candidate = ffi.cast('namehook_claims_t*', found);
        if (not abi.Accepts(candidate, 'namehook_claims_t', 1) or candidate.SlotSize ~= ffi.sizeof('namehook_claim_slot_t')) then
            return nil, 'namehook keeps its claim slots another way than this addon reads: one of the two is older than the other.';
        end
        claims, claimsGeneration = candidate, generation;
        nameplates.SharedPriority = tonumber(candidate.SharedPriority);
    end
    return claims;
end

-- A number of the addon's own for its slot, from its name: never 0
function nameplates.OwnerOf(name)
    -- FNV-1a, its multiply split in two so that no product passes the 2^53 a double holds exactly
    local h = 2166136261;
    for i = 1, #name do
        h = bit.bxor(h, name:byte(i)) % 4294967296;
        local low, high = h % 65536, math.floor(h / 65536);
        h = (low * 16777619 + ((high * 16777619) % 65536) * 65536) % 4294967296;
    end
    return h ~= 0 and h or 1;
end

local function SlotOf(slot)
    local c = nameplates.Claims();
    if (c == nil or slot == nil or slot < 1 or slot > math.min(c.SlotsMax, 3)) then return nil; end
    return c.Slots[slot - 1];
end

-- Takes a free slot for owner (or the one it holds already): the slot's number, or nil and why not
function nameplates.TakeSlot(owner, priority)
    local c, why = nameplates.Claims();
    if (c == nil) then return nil, why; end
    local hook = nameplates.Hook();
    local free = nil;
    for i = 0, math.min(c.SlotsMax, 3) - 1 do
        if (c.Slots[i].Owner == owner) then return i + 1; end
        if (free == nil and c.Slots[i].Owner == 0) then free = i; end
    end
    if (free == nil) then return nil, 'Every one of namehook\'s claim slots is taken by another addon.'; end
    local s = c.Slots[free];
    s.Categories, s.Priority, s.ClaimFrame = 0, priority or nameplates.SharedPriority, hook.Frame;
    s.Owner = owner; -- last: the slot is the addon's once the rest is in place
    return free + 1;
end

-- Renews the slot's claim, made every frame: false where the slot is no longer the owner's
function nameplates.ClaimSlot(slot, owner, categories, priority)
    local s, hook = SlotOf(slot), nameplates.Hook();
    if (s == nil or hook == nil or s.Owner ~= owner) then return false; end
    s.Categories = categories or 0;
    if (priority ~= nil) then s.Priority = priority; end
    s.ClaimFrame = hook.Frame;
    return true;
end

-- What to hand nameplates.BeginDrawing to draw into the slot's buffer, or nil
function nameplates.SlotDrawing(slot)
    local s, hook = SlotOf(slot), nameplates.Hook();
    if (s == nil or hook == nil or s.Draw == 0) then return nil; end
    return { Hooked = hook.Hooked, Frame = hook.Frame, Draw = s.Draw, Width = hook.Width, Height = hook.Height,
        TargetWidth = hook.TargetWidth, TargetHeight = hook.TargetHeight };
end

-- Gives the slot back, its drawing cleared, where it is still the owner's
function nameplates.ReleaseSlot(slot, owner)
    local s, hook = SlotOf(slot), nameplates.Hook();
    draw, drawing, quadLimit = nil, nil, 0;
    if (s == nil or hook == nil or s.Owner ~= owner) then return; end
    if (s.Draw ~= 0) then
        local target = ffi.cast('namehook_draw_t*', s.Draw);
        target.QuadCount = 0;
        ffi.fill(target.Textures, ffi.sizeof(target.Textures));
        if nameplates.Supports(nameplates.Feature.Textures32) then
            ffi.fill(target.TexturesExtra, ffi.sizeof(target.TexturesExtra));
        end
        target.Frame = hook.Frame - 9;
    end
    s.Categories = 0;
    s.Owner = 0;
end

return nameplates;
