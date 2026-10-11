addon.name    = 'nameplates';
addon.author  = 'win (and claude)';
addon.version = '0.5';
addon.desc    = 'Draws the names over characters\' heads in place of the game, from what the nameplatew plugin hands over.';

require('common');

local chat  = require('chat');
local d3d   = require('d3d8');
local ffi   = require('ffi');
local imgui = require('imgui');
local shell   = require('winxi.shell');
local text    = require('winxi.text');
local widgets = require('winxi.widgets');
local icons   = require('icons');
local sight   = require('sight');

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
        uint32_t Stars;     // 1 if the game was about to draw the Job Mastery stars over the name
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
local STAR          = 0xAD; -- the star of the Job Mastery stars: a small one, a large one, a small one
local ICON_GAP      = 2;    -- pixels between one icon and the next, and the name
local FADE_OVER     = 1 / 3; -- the last part of a name's distance over which it fades out, if it does not shrink
local SMALLEST      = 6;    -- pixels: a name that has shrunk below this height is not drawn
local LOOK_AFTER    = 4;    -- frames between one look and the next at whether a name is behind something
local SIGHT_FADE    = 0.15; -- seconds for a name to go as it passes behind something, and to come back

local FONT_FOLDER   = 'C:\\Windows\\Fonts\\';
local DEFAULT_FONT  = 'Default';

-- What can be set, in /nameplates. A setting changed by a control is a table of one, as imgui wants.
local defaults = T{
    enabled   = T{ true },
    fontSize  = T{ 15 },   -- the height of the names, in pixels
    shrink    = T{ true }, -- names get smaller towards the distance they are no longer drawn at, as the game's do
    outline   = T{ 1 },    -- how thick the dark edge round them is, in pixels
    font      = '',        -- a file of FONT_FOLDER, or nothing for the font everything else is in
    showIcons = T{ true },
    iconSize  = T{ 125 },  -- an icon's side, as a percentage of the height of the names
    showStars = T{ true },
    hideBehind = T{ false }, -- names of those behind a wall, or the ground, are not drawn
};

-- Whether each name is behind something, by its entity: { hidden = whether it was at the last look,
-- shown = 0 to 1, how far it has come back into view, seen = the frame it was last drawn in }
local sights = {};
local frame = 0;
local lastClock = os.clock();

local nameplates = {
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
local textAt = { 0, 0 };

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
-- the name }. The same names come round every frame.
local parsed = {};
local parsedCount = 0;

-- Fonts loaded from files, by file: the font, or false for a file that would not load
local fonts = {};

local function getFont(file)
    if (file == nil or file == '') then
        return nil;
    end

    local found = fonts[file];
    if (found == nil) then
        local ok, made = pcall(imgui.AddFontFromFileTTF, FONT_FOLDER .. file, 16);
        found = (ok and made ~= nil) and made or false;
        fonts[file] = found;
        if (found == false) then
            print(chat.header(addon.name):append(chat.message(('The font %s could not be loaded: names are in the usual one.'):format(file))));
        end
    end
    return found or nil;
end

-- The files there are to choose a font from, looked for once
local fontFiles = nil;

local function getFontFiles()
    if (fontFiles == nil) then
        fontFiles = {};
        local ok, files = pcall(ashita.fs.get_directory, FONT_FOLDER, '.*\\.ttf');
        if (ok and type(files) == 'table') then
            for _, file in pairs(files) do
                fontFiles[#fontFiles + 1] = file;
            end
            table.sort(fontFiles, function (a, b) return a:lower() < b:lower(); end);
        end
    end
    return fontFiles;
end

local function parse(written)
    local found = parsed[written];
    if (found ~= nil) then
        return found;
    end

    found = { icons = {}, words = '' };

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

    if (parsedCount > 1024) then
        parsed, parsedCount = {}, 0;
    end
    parsed[written] = found;
    parsedCount = parsedCount + 1;
    return found;
end

local app;

local function DrawSettings(options)
    widgets.Label('Draw Names');
    imgui.Checkbox('##nameplates.enabled', options.enabled);
    if (imgui.IsItemHovered()) then
        imgui.SetTooltip('Off, the game draws the names itself, as it does without this addon. /nameplates toggle switches this.');
    end

    widgets.Gap();
    widgets.Label('Font Size');
    imgui.SliderInt('##nameplates.fontSize', options.fontSize, 8, 48, '%d px');
    widgets.Label('Shrink With Distance');
    imgui.Checkbox('##nameplates.shrink', options.shrink);
    if (imgui.IsItemHovered()) then
        imgui.SetTooltip('A name gets smaller as it nears the distance it is no longer drawn at, as the game\'s own does. Off, names stay one size and fade out there.');
    end
    widgets.Label('Outline Thickness');
    imgui.SliderInt('##nameplates.outline', options.outline, 0, 4, '%d px');
    if (imgui.IsItemHovered()) then
        imgui.SetTooltip('The dark edge round each name. At 0 the names are written plain.');
    end

    widgets.Label('Font', true);
    if (imgui.BeginCombo('##nameplates.font', options.font ~= '' and options.font or DEFAULT_FONT)) then
        if (imgui.Selectable(DEFAULT_FONT, options.font == '') and options.font ~= '') then
            options.font = '';
            app:Save();
        end
        for _, file in ipairs(getFontFiles()) do
            if (imgui.Selectable(file, options.font == file) and options.font ~= file) then
                options.font = file;
                app:Save();
            end
        end
        imgui.EndCombo();
    end
    if (imgui.IsItemHovered()) then
        imgui.SetTooltip('A font of Windows\' own, by its file in C:\\Windows\\Fonts. Default is the font everything else is written in.');
    end

    widgets.Gap();
    widgets.Label('Hide Behind Walls', true);
    imgui.Checkbox('##nameplates.hideBehind', options.hideBehind);
    if (imgui.IsItemHovered()) then
        imgui.SetTooltip('A name is not drawn while a wall, the ground or a closed door is between the camera and it, as the game\'s own is hidden then. Characters in the way do not hide it.');
    end

    widgets.Gap();
    widgets.Label('Show Icons');
    imgui.Checkbox('##nameplates.showIcons', options.showIcons);
    if (imgui.IsItemHovered()) then
        imgui.SetTooltip('The game\'s icons before a name: the linkshell pearl, the party\'s flags, the bazaar\'s bag and the rest.');
    end
    if (options.showIcons[1] or options.showStars[1]) then
        widgets.Label('Icon Size');
        imgui.SliderInt('##nameplates.iconSize', options.iconSize, 50, 300, '%d%%');
        if (imgui.IsItemHovered()) then
            imgui.SetTooltip('An icon\'s side, as a percentage of the height of the names. The icons are sharp up to 32 pixels.');
        end
    end
    widgets.Label('Show Mastery Stars');
    imgui.Checkbox('##nameplates.showStars', options.showStars);
    if (imgui.IsItemHovered()) then
        imgui.SetTooltip('The three stars over the name of a player with a job mastered. The plugin\'s own /nameplatew hidestars hides them too.');
    end
end

-- The settings, the settings window and the command are the shell's
app = shell.New({
    defaults     = defaults,
    configTitle  = 'Nameplates Settings',
    command      = '/nameplates',
    help         = '/nameplates opens or closes the settings; /nameplates on, off and toggle set whether this addon draws the names or the game does.',
    drawSettings = DrawSettings,
    commands     = {
        on     = function (options) options.enabled[1] = true; app:Save(); end,
        off    = function (options) options.enabled[1] = false; app:Save(); end,
        toggle = function (options) options.enabled[1] = not options.enabled[1]; app:Save(); end,
    },
});

ashita.events.register('load', 'load_cb', function ()
    if (not sight.Find()) then
        print(chat.header(addon.name):append(chat.message('The game\'s test of what is in the way was not found in this client: Hide Behind Walls does nothing.')));
    end
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
    -- the settings window, while it is open
    app:BeginFrame();
    local options = app.options;

    local list = getList();
    if (list == nil) then
        return;
    end

    if (not options.enabled[1]) then
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

    local font = getFont(options.font);
    local fullSize = math.max(8, math.min(48, options.fontSize[1]));
    local shrink = options.shrink[1];
    local edge = math.max(0, math.min(4, options.outline[1]));
    local showIcons, showStars = options.showIcons[1], options.showStars[1];
    local iconScale = options.iconSize[1] / 100;

    -- Where the camera is, out of the view: the look for what is in the way starts there
    local hideBehind = options.hideBehind[1] and sight.Found();
    local eyeX = -(v._41 * v._11 + v._42 * v._12 + v._43 * v._13);
    local eyeY = -(v._41 * v._21 + v._42 * v._22 + v._43 * v._23);
    local eyeZ = -(v._41 * v._31 + v._42 * v._32 + v._43 * v._33);

    frame = frame + 1;
    local now = os.clock();
    local step = math.min(1, (now - lastClock) / SIGHT_FADE);
    lastClock = now;

    icons.Begin();

    for i = 0, count - 1 do
        local name = list.Names[i];
        local x, y, z = name.X, name.Y, name.Z;

        -- in front of the camera, or it is not to be seen
        local w = x * m14 + y * m24 + z * m34 + m44;
        if (w > 0.01) then
            local written = parse(ffi.string(name.Text));
            local iconCount = showIcons and #written.icons or 0;

            -- The game draws a name at one size out to a distance, then smaller and smaller until at
            -- its furthest it is nothing: Scale is 1 and then falls to 0. Here it shrinks the same
            -- way, or keeps its size and fades out over the last of that.
            local scale = math.max(0, math.min(1, name.Scale));
            local size = shrink and math.floor(fullSize * scale + 0.5) or fullSize;

            -- as solid as the game has it, which fades a name with its character
            local solid = bit.rshift(name.NameColor, 24) / 0x80;
            local near = shrink and 1 or scale / FADE_OVER;
            -- and going while it is behind something. Each name is looked at every few frames, not all
            -- in the same one; a name new this frame is looked at straight away, and starts as it is found.
            local inSight = 1;
            if (hideBehind) then
                local index = name.EntityIndex;
                local known = sights[index];
                if (known == nil) then
                    known = { hidden = false, shown = 1, seen = 0 };
                    sights[index] = known;
                end

                local isNew = known.seen ~= frame - 1;
                if (isNew or (frame + index) % LOOK_AFTER == 0) then
                    known.hidden = sight.Blocked(eyeX, eyeY, eyeZ, x, y, z);
                end
                if (isNew) then
                    known.shown = known.hidden and 0 or 1;
                elseif (known.hidden) then
                    known.shown = math.max(0, known.shown - step);
                else
                    known.shown = math.min(1, known.shown + step);
                end
                known.seen = frame;
                inSight = known.shown;
            end

            local alpha = math.floor(255 * math.max(0, math.min(1, solid, near)) * inSight + 0.5);

            if (alpha > 0 and size >= SMALLEST and (written.words ~= '' or iconCount > 0)) then
                -- the name's font at its size, for measuring it and for writing it
                imgui.PushFont(font, size);
                local width, height = imgui.CalcTextSize(written.words);
                local iconSize = math.floor(height * iconScale + 0.5);
                local smallStar = math.floor(iconSize * 0.5 + 0.5);
                local nameEdge = math.min(edge, math.max(1, math.floor(size / 8)));

                local screenX = (1 + (x * m11 + y * m21 + z * m31 + m41) / w) * halfWidth;
                local screenY = (1 - (x * m12 + y * m22 + z * m32 + m42) / w) * halfHeight;

                -- icons, then the name, the middle of them all on the point the game gave
                local iconsWidth = iconCount * (iconSize + ICON_GAP);
                local left = math.floor(screenX - (iconsWidth + width) * 0.5);
                local top = math.floor(screenY - height * 0.5);
                local iconTop = math.floor(screenY - iconSize * 0.5);

                -- the stars over the middle of it: a small one, a large one, a small one
                if (showStars and name.Stars ~= 0) then
                    local color = plainColor(alpha);
                    local starsLeft = math.floor(screenX - (smallStar * 2 + iconSize) * 0.5);
                    local starsTop = math.min(top, iconTop) - iconSize - 1;
                    local smallTop = starsTop + math.floor((iconSize - smallStar) * 0.5);
                    icons.Draw(drawList, STAR, starsLeft, smallTop, smallStar, color);
                    icons.Draw(drawList, STAR, starsLeft + smallStar, starsTop, iconSize, color);
                    icons.Draw(drawList, STAR, starsLeft + smallStar + iconSize, smallTop, smallStar, color);
                end

                for index = 1, iconCount do
                    local byte = written.icons[index];
                    local color = byte == PEARL and pearlColor(name.IconColor, alpha) or plainColor(alpha);
                    icons.Draw(drawList, byte, left, iconTop, iconSize, color);
                    if (byte == TWO_PART) then
                        icons.Draw(drawList, byte + 1, left, iconTop, iconSize, color);
                    end
                    left = left + iconSize + ICON_GAP;
                end

                if (written.words ~= '') then
                    if (edge > 0) then
                        text.Packed(drawList, left, top, nameColor(name.NameColor, alpha), written.words, nameEdge, darkColor(alpha));
                    else
                        textAt[1], textAt[2] = left, top;
                        drawList:AddText(textAt, nameColor(name.NameColor, alpha), written.words);
                    end
                end

                imgui.PopFont();
            end
        end
    end

    sight.Done();
end);
