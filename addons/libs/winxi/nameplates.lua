-- winxi.nameplates: the names the game draws over characters' heads, by way of the nameplatehook
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
--   nameplates.Screen(name)           where it is on screen, in imgui's pixels: x, y, or nil behind the camera
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
    } nameplatehook_name_t;

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
        uint32_t Reserved[3];
        uint8_t  Override[0x900];
        nameplatehook_name_t Names[256];
    } nameplatehook_t;
]]

local nameplates = {};

nameplates.Plugin = 'nameplatehook';

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
};

local MAGIC        = '4E414D45504C415445484F4F4B000000'; -- "NAMEPLATEHOOK" and the three 0s after it
local VERSION      = 1;
local LOOK_EVERY   = 1; -- seconds between looks for the plugin's block while it is not found
local ENTITIES     = 0x900;
local ALWAYS_TARGET = 0x01;
local OVERRIDE_SHOW, OVERRIDE_HIDE = 1, 2;

local block = nil;         -- the plugin's block, while the plugin is loaded
local why = 'unloaded';    -- why there is none: 'unloaded', 'old' or 'mismatch'
local lookedAt = -LOOK_EVERY;

local problems = {
    unloaded = 'The nameplatehook plugin is not loaded: /load nameplatehook',
    old      = 'The nameplatehook plugin has nothing to read: it is not the plugin this addon was written for.',
    mismatch = 'The nameplatehook plugin keeps its names another way than this addon reads: one of the two is older than the other.',
    unhooked = 'The nameplatehook plugin did not recognise this client\'s name drawing: names are shown and hidden, but none are listed.',
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

    local candidate = ffi.cast('nameplatehook_t*', found);
    if (candidate.Version ~= VERSION or candidate.Size ~= ffi.sizeof('nameplatehook_t') or candidate.NameSize ~= ffi.sizeof('nameplatehook_name_t')) then
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

function nameplates.Count()
    local hook = nameplates.Hook();
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

function nameplates.Each()
    local hook = nameplates.Hook();
    if (hook == nil) then
        return nothing;
    end
    return nextName, hook, 0;
end

-- Where each entity's name is in the list, worked out once each time the plugin makes the list ready
local places = {};
local placedAt = nil;

function nameplates.Find(entityIndex)
    local hook = nameplates.Hook();
    if (hook == nil) then
        return nil;
    end

    if (placedAt ~= hook.Sequence) then
        placedAt = hook.Sequence;
        places = {};
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
-- is the same size unless something has made it otherwise
function nameplates.Screen(name)
    local hook = nameplates.Hook();
    if (hook == nil or bit.band(name.Flags, nameplates.Flag.OnScreen) == 0 or hook.Width <= 0 or hook.Height <= 0) then
        return nil;
    end

    local display = require('imgui').GetIO().DisplaySize;
    return name.ScreenX * display.x / hook.Width, name.ScreenY * display.y / hook.Height;
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

function nameplates.Claim(categories)
    local hook = nameplates.Hook();
    if (hook ~= nil) then
        hook.Claimed = bit.band(categories or nameplates.Category.All, nameplates.Category.All);
        hook.ClaimFrame = hook.Frame;
    end
end

return nameplates;
