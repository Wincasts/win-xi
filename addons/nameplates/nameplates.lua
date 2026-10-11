addon.name    = 'nameplates';
addon.author  = 'win (and claude)';
addon.version = '0.2';
addon.desc    = 'Draws the names over characters\' heads in place of the game, from what the nameplatew plugin hands over.';

require('common');

local chat  = require('chat');
local d3d   = require('d3d8');
local ffi   = require('ffi');
local imgui = require('imgui');
local text  = require('winxi.text');
local icons = require('icons');

local C = ffi.C;
local d3d8dev = d3d.get_device();

-- The list the nameplatew plugin keeps, as it is laid out in the plugin (CustomNames, Nameplate.cpp).
-- With its "custom" setting on and Consumer set, every name the game is about to draw is added to the
-- list and not drawn. Whoever reads the list sets Count back to 0.
ffi.cdef[[
    typedef struct {
        uint32_t EntityIndex;
        float    X, Y, Z;   // where the game puts the name, in the world: the point above the head
        float    Scale;     // 1 near to, falling to 0 as the name nears the distance it is no longer drawn at
        uint32_t NameColor; // the game's colour for the name, as 0xAARRGGBB with 0x80 for full
        uint32_t IconColor; // its colour for the linkshell pearl, as 0xAABBGGRR with 0x80 for full
        uint32_t Reserved;
        char     Text[48];  // the name as the game writes it: its icons, a byte each, then the name
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
local LIST_VERSION = 2;
local LIST_MAX     = 256;
local LOOK_EVERY   = 1; -- seconds between looks for the plugin's list while it is not found

local PEARL         = 0x92; -- the linkshell pearl, the one icon that is given a colour
local TWO_PART      = 0xAC; -- an icon the game draws with the next character of its font over it
local ICON_SIZE     = 1.25; -- an icon's side, in heights of the text
local ICON_GAP      = 2;    -- pixels between one icon and the next, and the name
local FADE_OVER     = 1 / 3; -- the last part of a name's distance over which it fades out

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
        say('This nameplatew plugin has no names to hand over: it is older than 0.71.');
        return nil;
    end

    local list = ffi.cast('nameplatew_names_t*', found);
    if (list.Version ~= LIST_VERSION) then
        say('This nameplatew plugin hands names over in another way than this addon reads: one of the two is older than the other.');
        return nil;
    end

    nameplates.list = list;
    return list;
end

-- Colours as imgui packs them, kept by colour and by how solid: the same few are asked for every frame
local packed = {};
local packedCount = 0;

local rgba = { 0, 0, 0, 0 };

local function pack(key, red, green, blue, alpha)
    local found = packed[key];
    if (found == nil) then
        if (packedCount > 4096) then
            packed, packedCount = {}, 0;
        end
        rgba[1], rgba[2], rgba[3], rgba[4] = red, green, blue, alpha;
        found = imgui.GetColorU32(rgba);
        packed[key] = found;
        packedCount = packedCount + 1;
    end
    return found;
end

-- One part of a game colour, where 0x80 is full and more than that is no brighter
local function part(value)
    return value >= 0x80 and 1 or value / 0x80;
end

-- alpha here and below is 0 to 255
local function nameColor(color, alpha)
    return pack(color % 0x1000000 * 256 + alpha,
        part(bit.band(bit.rshift(color, 16), 0xFF)), part(bit.band(bit.rshift(color, 8), 0xFF)), part(bit.band(color, 0xFF)), alpha / 255);
end

local function pearlColor(color, alpha)
    return pack(0x100000000 + color % 0x1000000 * 256 + alpha,
        part(bit.band(color, 0xFF)), part(bit.band(bit.rshift(color, 8), 0xFF)), part(bit.band(bit.rshift(color, 16), 0xFF)), alpha / 255);
end

local function plainColor(alpha)
    return pack(0x200000000 + alpha, 1, 1, 1, alpha / 255);
end

local function darkColor(alpha)
    local dark = text.OutlineColor;
    return pack(0x300000000 + alpha, dark[1], dark[2], dark[3], dark[4] * alpha / 255);
end

-- The game's writing of a name taken apart, kept by that writing: { icons = { byte, ... }, words =
-- the name, width = of the words }. The same names come round every frame.
local parsed = {};
local parsedCount = 0;

local function parse(written)
    local found = parsed[written];
    if (found ~= nil) then
        return found;
    end

    found = { icons = {}, words = '', width = 0 };

    -- the icons lead; the name is what follows them, less the space between
    local at = 1;
    while (at <= #written) do
        local byte = written:byte(at);
        if (byte < 0x8E) then
            break;
        end
        if (icons.Has(byte)) then
            found.icons[#found.icons + 1] = byte;
        end
        at = at + 1;
    end

    -- a character of the font that is not a letter cannot be written in this one
    found.words = written:sub(at):gsub('[%z\1-\31\127-\255]', ''):gsub('^ +', '');
    found.width = imgui.CalcTextSize(found.words);

    if (parsedCount > 1024) then
        parsed, parsedCount = {}, 0;
    end
    parsed[written] = found;
    parsedCount = parsedCount + 1;
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

ashita.events.register('load', 'load_cb', function ()
    if (not icons.Find()) then
        print(chat.header(addon.name):append(chat.message('The game\'s icons were not found in this client: names are drawn without them.')));
    end
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

    local drawList = imgui.GetBackgroundDrawList and imgui.GetBackgroundDrawList() or imgui.GetForegroundDrawList();

    local _, height = imgui.CalcTextSize('A');
    local iconSize = math.floor(height * ICON_SIZE + 0.5);

    icons.Begin();

    for i = 0, count - 1 do
        local name = list.Names[i];
        local x, y, z = name.X, name.Y, name.Z;

        -- in front of the camera, or it is not to be seen
        local w = x * m14 + y * m24 + z * m34 + m44;
        if (w > 0.01) then
            local written = parse(ffi.string(name.Text));

            -- as solid as the game has it, which fades a name with its character; and fading out
            -- over the last of its distance, where the game draws it smaller and smaller
            local solid = bit.rshift(name.NameColor, 24) / 0x80;
            local near = name.Scale / FADE_OVER;
            local alpha = math.floor(255 * math.max(0, math.min(1, solid, near)) + 0.5);

            if (alpha > 0 and (written.words ~= '' or #written.icons > 0)) then
                local screenX = (1 + (x * m11 + y * m21 + z * m31 + m41) / w) * halfWidth;
                local screenY = (1 - (x * m12 + y * m22 + z * m32 + m42) / w) * halfHeight;

                -- icons, then the name, the middle of them all on the point the game gave
                local iconsWidth = #written.icons * (iconSize + ICON_GAP);
                local left = math.floor(screenX - (iconsWidth + written.width) * 0.5);
                local top = math.floor(screenY - height * 0.5);
                local iconTop = math.floor(screenY - iconSize * 0.5);

                for _, byte in ipairs(written.icons) do
                    local color = byte == PEARL and pearlColor(name.IconColor, alpha) or plainColor(alpha);
                    icons.Draw(drawList, byte, left, iconTop, iconSize, color);
                    if (byte == TWO_PART) then
                        icons.Draw(drawList, byte + 1, left, iconTop, iconSize, color);
                    end
                    left = left + iconSize + ICON_GAP;
                end

                if (written.words ~= '') then
                    text.Packed(drawList, left, top, nameColor(name.NameColor, alpha), written.words, 1, darkColor(alpha));
                end
            end
        end
    end
end);
