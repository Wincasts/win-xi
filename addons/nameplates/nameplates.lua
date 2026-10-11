addon.name    = 'nameplates';
addon.author  = 'win (and claude)';
addon.version = '0.1';
addon.desc    = 'Draws the names over characters\' heads in place of the game, from what the nameplatew plugin hands over.';

require('common');

local chat  = require('chat');
local d3d   = require('d3d8');
local ffi   = require('ffi');
local imgui = require('imgui');
local text  = require('winxi.text');

local C = ffi.C;
local d3d8dev = d3d.get_device();

-- The list the nameplatew plugin keeps, as it is laid out in the plugin (CustomNames, Nameplate.cpp).
-- With its "custom" setting on and Consumer set, every name the game is about to draw is added to the
-- list and not drawn. Whoever reads the list sets Count back to 0.
ffi.cdef[[
    typedef struct {
        uint32_t EntityIndex;
        float    X, Y, Z;   // where the game puts the name, in the world: the point above the head
        float    Scale;
        float    Param;
        uint32_t Color;     // the model's own colour, 0x80 in each part when it is plain
        uint32_t Reserved;
    } nameplatew_name_t;

    typedef struct {
        char     Magic[16];
        uint32_t Version;
        uint32_t Hooked;
        uint32_t Enabled;
        uint32_t Consumer;
        uint32_t Count;
        uint32_t Reserved[3];
        nameplatew_name_t Names[256];
    } nameplatew_names_t;
]]

local PLUGIN       = 'nameplatew';
local LIST_MAGIC   = '4E414D45504C415445572D4C49535400'; -- "NAMEPLATEW-LIST" and the 0 that ends it
local LIST_VERSION = 1;
local LIST_MAX     = 256;
local LOOK_EVERY   = 1; -- seconds between looks for the plugin's list while it is not found

local PLAYER_COLOR = { 1.00, 1.00, 1.00 };
local OTHER_COLOR  = { 0.75, 1.00, 0.75 };

local nameplates = {
    show     = true,
    list     = nil,  -- the plugin's list, while the plugin is loaded
    lookedAt = -LOOK_EVERY,
    told     = nil,  -- the last thing said about the plugin, so that it is said once
};

local function say(words)
    if (nameplates.told ~= words) then
        nameplates.told = words;
        print(chat.header(addon.name):append(chat.message(words)));
    end
end

-- The plugin's list, or nil while there is none to read. The list lives in the plugin's DLL, so it is
-- let go of the moment the plugin is no longer loaded.
local function getList()
    if (not AshitaCore:GetPluginManager():IsLoaded(PLUGIN)) then
        nameplates.list = nil;
        say('The nameplatew plugin is not loaded: names are drawn by the game. /load nameplatew');
        return nil;
    end

    if (nameplates.list ~= nil) then
        return nameplates.list;
    end

    local now = os.clock();
    if (now - nameplates.lookedAt < LOOK_EVERY) then
        return nil;
    end
    nameplates.lookedAt = now;

    local found = ashita.memory.find(PLUGIN .. '.dll', 0, LIST_MAGIC, 0, 0);
    if (found == 0) then
        say('This nameplatew plugin has no names to hand over: it is older than 0.70.');
        return nil;
    end

    local list = ffi.cast('nameplatew_names_t*', found);
    if (list.Version ~= LIST_VERSION) then
        say('This nameplatew plugin hands names over in a way this addon does not know.');
        return nil;
    end

    nameplates.list = list;
    return list;
end

-- Colours as imgui packs them, kept by kind and by how solid: the same few are asked for every frame
local packed = {};

local function packedColor(kind, color, alpha)
    local key = kind * 256 + alpha;
    local found = packed[key];
    if (found == nil) then
        found = imgui.GetColorU32({ color[1], color[2], color[3], color[4] and color[4] * alpha / 255 or alpha / 255 });
        packed[key] = found;
    end
    return found;
end

local function print_help(isError)
    if (isError) then
        print(chat.header(addon.name):append(chat.error('Invalid command syntax for command: ')):append(chat.success('/' .. addon.name)));
    else
        print(chat.header(addon.name):append(chat.message('Available commands:')));
    end

    local cmds = T{
        { '/nameplates', 'Toggles between this addon drawing the names and the game drawing them.' },
        { '/nameplates help', 'Displays the addons help information.' },
        { '/nameplates (on | off)', 'Sets which of the two draws the names.' },
    };

    cmds:ieach(function (v)
        print(chat.header(addon.name):append(chat.error('Usage: ')):append(chat.message(v[1]):append(' - ')):append(chat.color1(6, v[2])));
    end);
end

ashita.events.register('command', 'command_cb', function (e)
    local args = e.command:args();
    if (#args == 0 or not args[1]:any('/nameplates')) then
        return;
    end

    e.blocked = true;

    if (#args == 1) then
        nameplates.show = not nameplates.show;
        return;
    end

    if (#args == 2 and args[2]:any('help')) then
        print_help(false);
        return;
    end

    if (#args == 2 and args[2]:any('on')) then
        nameplates.show = true;
        return;
    end

    if (#args == 2 and args[2]:any('off')) then
        nameplates.show = false;
        return;
    end

    print_help(true);
end);

ashita.events.register('unload', 'unload_cb', function ()
    -- Without this the plugin would go on listing names for a few frames, until it found its list full
    if (AshitaCore:GetPluginManager():IsLoaded(PLUGIN) and nameplates.list ~= nil) then
        nameplates.list.Consumer = 0;
        nameplates.list.Count = 0;
    end
end);

ashita.events.register('d3d_present', 'present_cb', function ()
    local list = getList();
    if (list == nil) then
        return;
    end

    if (not nameplates.show) then
        if (list.Consumer ~= 0) then
            list.Consumer = 0;
            list.Count = 0;
        end
        return;
    end

    if (list.Hooked == 0) then
        say('The nameplatew plugin did not recognise this client\'s name drawing: names are drawn by the game.');
        return;
    elseif (list.Enabled == 0) then
        say('Names are drawn by the game until the plugin is told to hand them over: /nameplatew custom on');
    else
        say('Drawing the names.');
    end

    list.Consumer = 1;

    -- The names the game was about to draw this frame; taken, and the list emptied for the next
    local count = math.min(list.Count, LIST_MAX);
    list.Count = 0;
    if (count == 0) then
        return;
    end

    -- A point in the world goes through the view and then the projection to where it is on screen
    local _, v = d3d8dev:GetTransform(C.D3DTS_VIEW);
    local _, p = d3d8dev:GetTransform(C.D3DTS_PROJECTION);

    local m11 = v._11 * p._11 + v._12 * p._21 + v._13 * p._31 + v._14 * p._41;
    local m12 = v._11 * p._12 + v._12 * p._22 + v._13 * p._32 + v._14 * p._42;
    local m14 = v._11 * p._14 + v._12 * p._24 + v._13 * p._34 + v._14 * p._44;
    local m21 = v._21 * p._11 + v._22 * p._21 + v._23 * p._31 + v._24 * p._41;
    local m22 = v._21 * p._12 + v._22 * p._22 + v._23 * p._32 + v._24 * p._42;
    local m24 = v._21 * p._14 + v._22 * p._24 + v._23 * p._34 + v._24 * p._44;
    local m31 = v._31 * p._11 + v._32 * p._21 + v._33 * p._31 + v._34 * p._41;
    local m32 = v._31 * p._12 + v._32 * p._22 + v._33 * p._32 + v._34 * p._42;
    local m34 = v._31 * p._14 + v._32 * p._24 + v._33 * p._34 + v._34 * p._44;
    local m41 = v._41 * p._11 + v._42 * p._21 + v._43 * p._31 + v._44 * p._41;
    local m42 = v._41 * p._12 + v._42 * p._22 + v._43 * p._32 + v._44 * p._42;
    local m44 = v._41 * p._14 + v._42 * p._24 + v._43 * p._34 + v._44 * p._44;

    local display = imgui.GetIO().DisplaySize;
    local halfWidth, halfHeight = display.x * 0.5, display.y * 0.5;

    local entities = AshitaCore:GetMemoryManager():GetEntity();
    local drawList = imgui.GetBackgroundDrawList and imgui.GetBackgroundDrawList() or imgui.GetForegroundDrawList();

    for i = 0, count - 1 do
        local name = list.Names[i];
        local x, y, z = name.X, name.Y, name.Z;

        -- in front of the camera, or it is not to be seen
        local w = x * m14 + y * m24 + z * m34 + m44;
        if (w > 0.01) then
            local words = entities:GetName(name.EntityIndex);
            if (words ~= nil and words ~= '') then
                local screenX = (1 + (x * m11 + y * m21 + z * m31 + m41) / w) * halfWidth;
                local screenY = (1 - (x * m12 + y * m22 + z * m32 + m42) / w) * halfHeight;

                -- as solid as the model is: a character fading in or out takes its name with it
                local alpha = math.min(255, bit.rshift(name.Color, 24) * 2);

                local isPlayer = entities:GetServerId(name.EntityIndex) < 0x01000000;
                local color = packedColor(isPlayer and 1 or 2, isPlayer and PLAYER_COLOR or OTHER_COLOR, alpha);
                local dark = packedColor(0, text.OutlineColor, alpha);

                -- the middle of the name on the point the game gave
                local width, height = imgui.CalcTextSize(words);
                text.Packed(drawList, math.floor(screenX - width * 0.5), math.floor(screenY - height * 0.5), color, words, 1, dark);
            end
        end
    end
end);
