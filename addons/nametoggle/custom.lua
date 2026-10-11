-- The names drawn here, in winxi's outlined text, in place of the game drawing them.
--
--   custom.Defaults(defaults)     adds the settings below to an addon's own
--   custom.Find()                 once, on loading: the game's icons and its test of what is in the way
--   custom.DrawSettings(options)  the settings tab
--   custom.Frame(options)         each frame: claims the names and draws them, while Custom Names is on
--
-- The nameplatehook plugin lists the names the game was about to draw. While this draws, it claims
-- them all, so the game draws none; which names are wanted is still the plugin's to say, and only
-- those are drawn. A claim lapses by itself: with Custom Names off, or the addon unloaded, the game
-- draws the names again.
local bit   = require('bit');
local d3d   = require('d3d8');
local ffi   = require('ffi');
local imgui = require('imgui');
local game       = require('winxi.game');
local text       = require('winxi.text');
local widgets    = require('winxi.widgets');
local nameplates = require('winxi.nameplates');
local icons = require('icons');
local sight = require('sight');

local custom = {};

local D3DTS_VIEW, D3DTS_PROJECTION = 2, 3;

local PEARL         = 0x92; -- the linkshell pearl, the one icon that is given a colour
local TWO_PART      = 0xAC; -- an icon the game draws with the next character of its font over it
local STAR          = 0xAD; -- the star of the Job Mastery stars: a small one, a large one, a small one
local ICON_GAP      = 2;    -- pixels between one icon and the next, and the name
local FADE_OVER     = 1 / 3; -- the last part of a name's distance over which it fades out, if it does not shrink
local FADE_SHRUNK   = 0.15; -- and if it does, having by then shrunk to its smallest
local SMALLEST      = 6;    -- pixels: the smallest a name can be set to be
local LARGEST       = 48;   -- and the largest
local LOOK_AFTER    = 4;    -- frames between one look and the next at whether a name is behind something
local SIGHT_FADE    = 0.15; -- seconds for a name to go as it passes behind something, and to come back

local FONT_FOLDER   = 'C:\\Windows\\Fonts\\';
local DEFAULT_FONT  = 'Default';

-- What can be set. A setting changed by a control is a table of one, as imgui wants.
local settings = {
    customNames = function () return T{ false }; end, -- the names are drawn here, and not by the game
    fontSize    = function () return T{ 15 }; end,    -- the height of the names near to, in pixels: the largest they are
    shrink      = function () return T{ true }; end,  -- names get smaller towards the distance they are no longer drawn at, as the game's do
    minSize     = function () return T{ 10 }; end,    -- the height they have shrunk to by that distance: the smallest they are
    outline     = function () return T{ 1 }; end,     -- how thick the dark edge round them is, in pixels
    font        = function () return ''; end,         -- a file of FONT_FOLDER, or nothing for the font everything else is in
    showIcons   = function () return T{ true }; end,
    iconSize    = function () return T{ 125 }; end,   -- an icon's side, as a percentage of the height of the names
    showStars   = function () return T{ true }; end,
    hideBehind  = function () return T{ false }; end, -- names of those behind a wall, or the ground, are not drawn
};

function custom.Defaults(defaults)
    for key, make in pairs(settings) do
        defaults[key] = make();
    end
    return defaults;
end

local foundIcons, foundSight = false, false;

function custom.Find()
    foundSight = sight.Find();
    foundIcons = icons.Find();
end

-- Whether each name is behind something, by its entity: { hidden = whether it was at the last look,
-- shown = 0 to 1, how far it has come back into view, seen = the frame it was last drawn in }
local sights = {};
local frame = 0;
local lastClock = os.clock();

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
            print(('\30\81[%s]\30\01 The font %s could not be loaded: names are in the usual one.'):format(addon.name, file));
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

local warning = { 1.0, 0.6, 0.4, 1.0 };

-- save, if given, is called for the one setting that is not saved as the window closes
function custom.DrawSettings(options, save)
    local problem = nameplates.Problem();
    if (problem ~= nil) then
        imgui.TextColored(warning, problem);
        widgets.Gap();
    end

    widgets.Label('Custom Names', true);
    imgui.Checkbox('##nametoggle.customNames', options.customNames);
    if (imgui.IsItemHovered()) then
        imgui.SetTooltip('The names are drawn by this addon, in winxi\'s outlined text, and not by the game. Which names are shown is still set in the Settings tab.\n/nametoggle custom switches this.');
    end
    if (not options.customNames[1]) then
        return;
    end

    widgets.Gap();
    widgets.Label(options.shrink[1] and 'Maximum Font Size' or 'Font Size');
    if (imgui.SliderInt('##nametoggle.fontSize', options.fontSize, SMALLEST, LARGEST, '%d px') and options.minSize[1] > options.fontSize[1]) then
        options.minSize[1] = options.fontSize[1];
    end
    if (options.shrink[1] and imgui.IsItemHovered()) then
        imgui.SetTooltip('The height of a name near to, where it is at its largest.');
    end
    if (options.shrink[1]) then
        widgets.Label('Minimum Font Size');
        if (imgui.SliderInt('##nametoggle.minSize', options.minSize, SMALLEST, LARGEST, '%d px') and options.fontSize[1] < options.minSize[1]) then
            options.fontSize[1] = options.minSize[1];
        end
        if (imgui.IsItemHovered()) then
            imgui.SetTooltip('The height of a name at the distance it is no longer drawn at, where it is at its smallest. It fades out as it gets there.');
        end
    end
    widgets.Label('Shrink With Distance');
    imgui.Checkbox('##nametoggle.shrink', options.shrink);
    if (imgui.IsItemHovered()) then
        imgui.SetTooltip('A name gets smaller as it nears the distance it is no longer drawn at, from the maximum size to the minimum. Off, names stay one size and fade out there.');
    end
    widgets.Label('Outline Thickness');
    imgui.SliderInt('##nametoggle.outline', options.outline, 0, 4, '%d px');
    if (imgui.IsItemHovered()) then
        imgui.SetTooltip('The dark edge round each name. At 0 the names are written plain.');
    end

    widgets.Label('Font', true);
    if (imgui.BeginCombo('##nametoggle.font', options.font ~= '' and options.font or DEFAULT_FONT)) then
        if (imgui.Selectable(DEFAULT_FONT, options.font == '') and options.font ~= '') then
            options.font = '';
            if (save ~= nil) then save(); end
        end
        for _, file in ipairs(getFontFiles()) do
            if (imgui.Selectable(file, options.font == file) and options.font ~= file) then
                options.font = file;
                if (save ~= nil) then save(); end
            end
        end
        imgui.EndCombo();
    end
    if (imgui.IsItemHovered()) then
        imgui.SetTooltip('A font of Windows\' own, by its file in C:\\Windows\\Fonts. Default is the font everything else is written in.');
    end

    widgets.Gap();
    widgets.Label('Hide Behind Walls', true);
    imgui.Checkbox('##nametoggle.hideBehind', options.hideBehind);
    if (imgui.IsItemHovered()) then
        imgui.SetTooltip(foundSight
            and 'A name is not drawn while a wall, the ground or a closed door is between the camera and it, as the game\'s own is hidden then. Characters in the way do not hide it.'
            or 'The game\'s test of what is in the way was not found in this client: this does nothing.');
    end

    widgets.Gap();
    widgets.Label('Show Icons');
    imgui.Checkbox('##nametoggle.showIcons', options.showIcons);
    if (imgui.IsItemHovered()) then
        imgui.SetTooltip(foundIcons
            and 'The game\'s icons before a name: the linkshell pearl, the party\'s flags, the bazaar\'s bag and the rest.'
            or 'The game\'s icons were not found in this client: names are drawn without them.');
    end
    if (options.showIcons[1] or options.showStars[1]) then
        widgets.Label('Icon Size');
        imgui.SliderInt('##nametoggle.iconSize', options.iconSize, 50, 300, '%d%%');
        if (imgui.IsItemHovered()) then
            imgui.SetTooltip('An icon\'s side, as a percentage of the height of the names. The icons are sharp up to 32 pixels.');
        end
    end
    widgets.Label('Show Mastery Stars');
    imgui.Checkbox('##nametoggle.showStars', options.showStars);
    if (imgui.IsItemHovered()) then
        imgui.SetTooltip('The three stars over the name of a player with a job mastered. The plugin\'s own /nameplatehook hidestars hides them too.');
    end
end

local device = nil;

function custom.Frame(options)
    if (not options.customNames[1]) then
        return;
    end

    -- without the plugin's list there is nothing to draw from, and the game draws the names
    local hook = nameplates.Hook();
    if (hook == nil or hook.Hooked == 0) then
        return;
    end

    device = device or d3d.get_device();
    if (device == nil) then
        return;
    end

    -- every frame: the game draws none of the names while this does
    nameplates.Claim(nameplates.Category.All);

    if (hook.Count == 0) then
        return;
    end

    -- A point in the world goes through the view and then the projection to where it is on screen
    local _, v = device:GetTransform(D3DTS_VIEW);
    local _, p = device:GetTransform(D3DTS_PROJECTION);

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
    local fullSize = math.max(SMALLEST, math.min(LARGEST, options.fontSize[1]));
    local leastSize = math.max(SMALLEST, math.min(fullSize, options.minSize[1]));
    local shrink = options.shrink[1];
    local edge = math.max(0, math.min(4, options.outline[1]));
    local showIcons, showStars = options.showIcons[1], options.showStars[1];
    local iconScale = options.iconSize[1] / 100;

    -- Where the camera is, out of the view: the look for what is in the way starts there
    -- (never while the game is between zones, when the map that would be asked may be going or gone)
    local hideBehind = options.hideBehind[1] and sight.Found() and not game.IsLoading();
    local eyeX = -(v._41 * v._11 + v._42 * v._12 + v._43 * v._13);
    local eyeY = -(v._41 * v._21 + v._42 * v._22 + v._43 * v._23);
    local eyeZ = -(v._41 * v._31 + v._42 * v._32 + v._43 * v._33);

    frame = frame + 1;
    local now = os.clock();
    local step = math.min(1, (now - lastClock) / SIGHT_FADE);
    lastClock = now;

    local WANTED, STARS = nameplates.Flag.Wanted, nameplates.Flag.Stars;

    icons.Begin();

    for i = 0, hook.Count - 1 do
        local name = hook.Names[i];
        local x, y, z = name.X, name.Y, name.Z;

        -- wanted, and in front of the camera, or it is not to be seen
        local w = x * m14 + y * m24 + z * m34 + m44;
        if (bit.band(name.Flags, WANTED) ~= 0 and w > 0.01) then
            local written = parse(ffi.string(name.Text));
            local iconCount = showIcons and #written.icons or 0;

            -- The game draws a name at one size out to a distance, then smaller and smaller until at
            -- its furthest it is nothing: Scale is 1 and then falls to 0. Here it shrinks over the
            -- same distance, from its largest to its smallest and not to nothing, or keeps its size;
            -- and either way fades out over the last of it.
            local scale = math.max(0, math.min(1, name.Scale));
            local size = shrink and math.floor(leastSize + (fullSize - leastSize) * scale + 0.5) or fullSize;

            -- as solid as the game has it, which fades a name with its character
            local solid = bit.rshift(name.NameColor, 24) / 0x80;
            local near = scale / (shrink and FADE_SHRUNK or FADE_OVER);
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

            if (alpha > 0 and (written.words ~= '' or iconCount > 0)) then
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
                if (showStars and bit.band(name.Flags, STARS) ~= 0) then
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
end

return custom;
