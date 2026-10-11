-- The names drawn in winxi's style, in place of the game's own.
--
--   custom.Defaults(defaults)     adds the settings below to an addon's own
--   custom.Settle(options)        the settings have been loaded: what an older version kept is brought over
--   custom.Find()                 once, on loading: the game's icons
--   custom.DrawSettings(options)  the settings tab
--   custom.Frame(options, hook)   each frame: claims the names and draws them, while Custom Names is on;
--                                 hook is the plugin's block, as nameplates.Hook gave it this frame
--
-- The namehook plugin lists the names the game was about to draw. While this draws, it claims
-- them all, so the game draws none; which names are wanted is still the plugin's to say, and only
-- those are drawn.
--
-- They are not drawn on the screen from here. Each name is set out as rectangles, one for each letter
-- and icon, and left with the plugin, which puts them in the game's own picture at the moment the game
-- would have drawn the name, as deep in the picture as the name is: a wall or a character in front of
-- a name hides it, or the part of it that it covers, as it hides the game's. What is set out one frame
-- is drawn in the next.
--
-- A claim lapses by itself: with Custom Names off, or the addon unloaded, the game draws the names again.
local bit   = require('bit');
local ffi   = require('ffi');
local imgui = require('imgui');
local text       = require('winxi.text');
local widgets    = require('winxi.widgets');
local nameplates = require('winxi.nameplates');
local icons = require('icons');
local format = require('format');

local custom = {};

local PEARL         = 0x92; -- the linkshell pearl, the one icon that is given a colour
local TWO_PART      = 0xAC; -- an icon the game draws with the next character of its font over it
local STAR          = 0xAD; -- the star of the Job Mastery stars: a small one, a large one, a small one
local ICON_GAP      = 2;    -- pixels between one icon and the next
local FADE_OVER     = 1 / 3; -- the last part of a name's distance over which it fades out, if it does not shrink
local FADE_SHRUNK   = 0.15; -- and if it does, having by then shrunk to its smallest
local SMALLEST      = 6;    -- pixels: the smallest a name can be set to be
local LARGEST       = 48;   -- and the largest
local FONT_SLOT, ICON_SLOT = 0, 1; -- the plugin's numbers for the two textures the names are drawn from
local RUNGS         = { 1, 0.75, 0.5 }; -- the sizes letters are kept at, as parts of the largest: see below
local STEADY_AFTER  = 4;    -- frames a name's colour has to stay the same to be taken as its own at once
local STEADY_STRETCH = 45;  -- frames over which the strongest of a pulsing name's colours is looked for
local PROBE         = 65;   -- the letter looked at each frame to see that the font's letters are where they were

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
    iconSpacing = function () return T{ 2 }; end,     -- pixels between the last icon and the name
    showStars   = function () return T{ true }; end,
    -- How a name is written: [name] for the name, [distance] for how far off it is, and the rest as
    -- it is typed (format.lua). One line for monsters, one for everything else, and one for the
    -- monster that is the target, which if left empty is written as the other monsters are.
    nameFormat    = function () return T{ '[name]' }; end,
    monsterFormat = function () return T{ '[name]' }; end,
    targetFormat  = function () return T{ '' }; end,
};

function custom.Defaults(defaults)
    for key, make in pairs(settings) do
        defaults[key] = make();
    end
    return defaults;
end

-- Up to 1.10 a monster's distance was a setting of its own, and another said whether only the
-- target's was written: they are made the lines that say the same, once.
function custom.Settle(options)
    for _, key in ipairs({ 'nameFormat', 'monsterFormat', 'targetFormat' }) do
        if (type(options[key]) ~= 'table' or type(options[key][1]) ~= 'string') then
            options[key] = settings[key]();
        end
    end

    local was = options.showDistance;
    if (type(was) == 'table') then
        if (was[1]) then
            local targetOnly = type(options.distanceTargetOnly) == 'table' and options.distanceTargetOnly[1];
            options[targetOnly and 'targetFormat' or 'monsterFormat'][1] = '[name] [distance]';
        end
        options.showDistance, options.distanceTargetOnly = nil, nil;
    end
end

local foundIcons = false;

function custom.Find()
    foundIcons = icons.Find();
end

-- Colours as the plugin takes them, 0xAARRGGBB, all of them solid: a name's fading is told apart.
-- One part of a game colour, where 0x80 is full and more than that is no brighter
local function part(value)
    return value >= 0x80 and 255 or value * 2;
end

local WHITE = 0xFFFFFFFF;

local function nameColor(color)
    return 0xFF000000 + part(bit.band(bit.rshift(color, 16), 0xFF)) * 0x10000 + part(bit.band(bit.rshift(color, 8), 0xFF)) * 0x100 + part(bit.band(color, 0xFF));
end

-- the game keeps the pearl's colour the other way about
local function pearlColor(color)
    return 0xFF000000 + part(bit.band(color, 0xFF)) * 0x10000 + part(bit.band(bit.rshift(color, 8), 0xFF)) * 0x100 + part(bit.band(bit.rshift(color, 16), 0xFF));
end

local function darkColor()
    local dark = text.OutlineColor;
    return math.floor(dark[4] * 255 + 0.5) * 0x1000000 + math.floor(dark[1] * 255 + 0.5) * 0x10000 + math.floor(dark[2] * 255 + 0.5) * 0x100 + math.floor(dark[3] * 255 + 0.5);
end

ffi.cdef('int memcmp(const void*, const void*, size_t);');

local TEXT_SIZE = 48; -- of a name as the plugin lists it

-- The game's writing of a name taken apart: { icons = { byte, ... }, words = the name }. Kept by
-- entity, with the writing it was taken from: the same names come round every frame, and to see that
-- one is as it was its bytes are compared where they lie, without a string being made of them.
local parsed = {};

local function parse(name)
    local known = parsed[name.EntityIndex];
    if (known == nil) then
        known = { text = ffi.new('char[?]', TEXT_SIZE), icons = {}, words = '', fresh = true };
        parsed[name.EntityIndex] = known;
    elseif (not known.fresh and ffi.C.memcmp(known.text, name.Text, TEXT_SIZE) == 0) then
        return known;
    end

    ffi.copy(known.text, name.Text, TEXT_SIZE);
    known.fresh = false;
    local written = ffi.string(name.Text);

    -- the icons lead; the name is what follows them, less the space between
    known.icons = {};
    local at = 1;
    while (at <= #written) do
        local byte = written:byte(at);
        if (byte < 0x8E) then
            break;
        end
        if (icons.Has(byte)) then
            known.icons[#known.icons + 1] = byte;
        end
        at = at + 1;
    end

    -- a character of the font that is not a letter cannot be written in this one
    known.words = written:sub(at):gsub('[%z\1-\31\127-\255]', ''):gsub('^ +', '');
    return known;
end

-- The icons are found a moment after the names are first seen: what was taken apart without them is
-- taken apart again
local function forgetParsed()
    for _, known in pairs(parsed) do
        known.fresh = true;
    end
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
    imgui.Checkbox('##name.customNames', options.customNames);
    if (imgui.IsItemHovered()) then
        imgui.SetTooltip('The names are drawn in winxi\'s outlined text, and not by the game: in the game\'s own picture, where a wall or a character in front of a name hides it.\nWhich names are shown is still set in the Settings tab. /name custom switches this.');
    end
    if (not options.customNames[1]) then
        return;
    end

    widgets.Gap();
    widgets.Label(options.shrink[1] and 'Maximum Font Size' or 'Font Size');
    if (imgui.SliderInt('##name.fontSize', options.fontSize, SMALLEST, LARGEST, '%d px') and options.minSize[1] > options.fontSize[1]) then
        options.minSize[1] = options.fontSize[1];
    end
    if (options.shrink[1] and imgui.IsItemHovered()) then
        imgui.SetTooltip('The height of a name near to, where it is at its largest.');
    end
    if (options.shrink[1]) then
        widgets.Label('Minimum Font Size');
        if (imgui.SliderInt('##name.minSize', options.minSize, SMALLEST, LARGEST, '%d px') and options.fontSize[1] < options.minSize[1]) then
            options.fontSize[1] = options.minSize[1];
        end
        if (imgui.IsItemHovered()) then
            imgui.SetTooltip('The height of a name at the distance it is no longer drawn at, where it is at its smallest. It fades out as it gets there.');
        end
    end
    widgets.Label('Shrink With Distance');
    imgui.Checkbox('##name.shrink', options.shrink);
    if (imgui.IsItemHovered()) then
        imgui.SetTooltip('A name gets smaller as it nears the distance it is no longer drawn at, from the maximum size to the minimum. Off, names stay one size and fade out there.');
    end
    widgets.Label('Outline Thickness');
    imgui.SliderInt('##name.outline', options.outline, 0, 4, '%d px');
    if (imgui.IsItemHovered()) then
        imgui.SetTooltip('The dark edge round each name. At 0 the names are written plain.');
    end

    widgets.Label('Font', true);
    if (imgui.BeginCombo('##name.font', options.font ~= '' and options.font or DEFAULT_FONT)) then
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
    local function line(label, key, id, tooltip)
        widgets.Label(label);
        imgui.InputText(id, options[key], 256);
        if (imgui.IsItemDeactivatedAfterEdit() and save ~= nil) then
            save();
        end
        if (imgui.IsItemHovered()) then
            imgui.SetTooltip(tooltip);
        end
    end
    local how = '[name] is the name and [distance] how far off it is; anything else is written as you type it.\nex: [name] ([distance])\n\n'
        .. 'A colour is #RRGGBB or a word: white, grey, red, green, blue, yellow, orange, purple, pink, cyan.\n'
        .. '[distance:yellow] or [name:#FF8000] colours that one thing; [yellow] colours everything after it, as far as [/].\n'
        .. 'With no colour, a thing is in the colour the game gives the name.';
    line('Name Format', 'nameFormat', '##name.nameFormat', 'How every name but a monster\'s is written.\n' .. how);
    line('Monster Format', 'monsterFormat', '##name.monsterFormat', 'How a monster\'s name is written.\n' .. how);
    line('Targeted Monster Format', 'targetFormat', '##name.targetFormat', 'How the name of the monster you have targeted is written. Left empty, it is written as other monsters\' are.\n' .. how);

    widgets.Gap();
    widgets.Label('Show Icons');
    imgui.Checkbox('##name.showIcons', options.showIcons);
    if (imgui.IsItemHovered()) then
        imgui.SetTooltip(foundIcons
            and 'The game\'s icons before a name: the linkshell pearl, the party\'s flags, the bazaar\'s bag and the rest.'
            or 'The game\'s icons were not found in this client: names are drawn without them.');
    end
    if (options.showIcons[1] or options.showStars[1]) then
        widgets.Label('Icon Size');
        imgui.SliderInt('##name.iconSize', options.iconSize, 50, 300, '%d%%');
        if (imgui.IsItemHovered()) then
            imgui.SetTooltip('An icon\'s side, as a percentage of the height of the names.');
        end
    end
    if (options.showIcons[1]) then
        widgets.Label('Icon Spacing');
        imgui.SliderInt('##name.iconSpacing', options.iconSpacing, 0, 24, '%d px');
        if (imgui.IsItemHovered()) then
            imgui.SetTooltip('The space between a name\'s icons and the name itself.');
        end
    end
    widgets.Label('Show Mastery Stars');
    imgui.Checkbox('##name.showStars', options.showStars);
    if (imgui.IsItemHovered()) then
        imgui.SetTooltip('The three stars over the name of a player with a job mastered. The plugin\'s own /namehook hidestars hides them too.');
    end
end

-- The font's texture as Direct3D has it, or nil while it has none: for a moment after letters of a
-- new size have been put in it
local function askFontTexture()
    local atlas = imgui.GetFont().ContainerAtlas;
    local id = atlas.TexRef:GetTexID();
    if (id == nil or id == 0) then
        id = atlas.TexData:GetTexID();
    end
    return id;
end

local function fontTexture()
    local ok, id = pcall(askFontTexture);
    if (ok and type(id) == 'number' and id ~= 0) then
        return id;
    end
    return nil;
end

-- The font's letters, by size and then by letter: { x0, y0, x1, y1, u0, v0, u1, v1, advance,
-- visible }, for the font now chosen. Where a letter is in the texture changes when the texture is
-- made again, so the texture is watched, and one letter of each size looked at afresh each frame.
--
-- A size is pushed on imgui once a frame, the first time a name of that size comes up, which also
-- keeps imgui from letting its letters go; every other name of the size is set out from what is
-- kept, with nothing asked of imgui at all.
local glyphSets = {};   -- height -> { checked = the frame it was last looked at, glyphs, baked }
local glyphFont = nil;  -- the font they are of
local glyphTexture = nil;
local frame = 0;

local function readGlyph(baked, byte)
    local glyph = baked:FindGlyph(byte);
    if (glyph == nil) then
        return false;
    end
    return { glyph.X0, glyph.Y0, glyph.X1, glyph.Y1, glyph.U0, glyph.V0, glyph.U1, glyph.V1, glyph.AdvanceX,
        glyph.Visible ~= 0 and glyph.Visible ~= false };
end

-- The letters of the font at this height, or nil if imgui has none
local function glyphSet(font, height)
    local set = glyphSets[height];
    if (set ~= nil and set.checked == frame) then
        return set;
    end

    imgui.PushFont(font, height);
    local baked = imgui.GetFontBaked();
    if (baked == nil) then
        imgui.PopFont();
        return nil;
    end

    if (set == nil) then
        set = { glyphs = {} };
        glyphSets[height] = set;
    end

    local now = readGlyph(baked, PROBE);
    local was = set.glyphs[PROBE];
    if (was and now and (was[5] ~= now[5] or was[6] ~= now[6] or was[7] ~= now[7] or was[8] ~= now[8])) then
        -- the letters have been moved: every size's are read again
        glyphSets = {};
        set = { glyphs = {} };
        glyphSets[height] = set;
    end
    set.glyphs[PROBE] = now;
    set.baked = baked;
    set.checked = frame;

    imgui.PopFont();
    return set;
end

-- The game makes some names pulse, the target's for one, by changing their colour from frame to
-- frame: towards white or towards dark and back. Here a name is drawn in the colour the pulse starts
-- from, which of all the colours it passes through is the one with most colour in it, and of those
-- the brightest. So of the colours a name has had over the last while, the best by that measure is
-- the one drawn; a change of colour that is no pulse (a monster's name going red as it is fought)
-- is taken up at once if it is to a stronger colour or holds still, and within the while if not.
--
-- By entity: { id = whose it is, last = the colour last frame, run = how many frames it has been
-- that, now and nowScore = the best of this stretch of frames, was and wasScore = of the stretch
-- before, age = how far through this stretch }
local steady = {};

local function score(color)
    local red, green, blue = part(bit.band(bit.rshift(color, 16), 0xFF)), part(bit.band(bit.rshift(color, 8), 0xFF)), part(bit.band(color, 0xFF));
    local most, least = math.max(red, green, blue), math.min(red, green, blue);
    return (most - least) * 0x10000 + most * 0x100 + bit.rshift(color, 24);
end

local function steadyColor(name)
    local color = name.NameColor;
    local scored = score(color);

    local known = steady[name.EntityIndex];
    if (known == nil or known.id ~= name.ServerId) then
        known = { id = name.ServerId, last = color, run = 0, now = color, nowScore = scored, was = color, wasScore = scored, age = 0 };
        steady[name.EntityIndex] = known;
        return color;
    end

    if (color == known.last) then
        known.run = known.run + 1;
    else
        known.last, known.run = color, 0;
    end

    -- a colour that holds still is the name's own, whatever it was before
    if (known.run >= STEADY_AFTER) then
        known.now, known.nowScore, known.was, known.wasScore, known.age = color, scored, color, scored, 0;
        return color;
    end

    known.age = known.age + 1;
    if (known.age > STEADY_STRETCH) then
        known.was, known.wasScore = known.now, known.nowScore;
        known.now, known.nowScore, known.age = color, scored, 0;
    elseif (scored > known.nowScore) then
        known.now, known.nowScore = color, scored;
    end

    return known.nowScore >= known.wasScore and known.now or known.was;
end

local iconsSeen = nil; -- the icons' texture when names were last taken apart

function custom.Frame(options, hook)
    if (not options.customNames[1]) then
        return;
    end

    -- without the plugin's list there is nothing to draw from, and the game draws the names
    if (hook == nil or hook.Hooked == 0) then
        return;
    end

    local texture = fontTexture();
    if (texture == nil) then
        return;
    end
    if (texture ~= glyphTexture or options.font ~= glyphFont) then
        glyphTexture, glyphFont = texture, options.font;
        glyphSets = {};
    end

    -- how many pixels of the game's picture there are to one of the screen's: the names are set out
    -- in the game's, at the size that makes them the size asked for on the screen
    local scale = nameplates.BeginDrawing(hook);
    if (scale == nil) then
        return;
    end

    -- every frame: the game draws none of the names while this does
    nameplates.Claim(nameplates.Category.All, hook);

    icons.Begin();
    local iconTexture = icons.Texture() or 0;
    if (iconTexture ~= iconsSeen) then
        iconsSeen = iconTexture;
        forgetParsed();
    end
    nameplates.SetTexture(FONT_SLOT, texture);
    nameplates.SetTexture(ICON_SLOT, iconTexture);

    frame = frame + 1;

    local font = getFont(options.font);
    local fullSize = math.max(SMALLEST, math.min(LARGEST, options.fontSize[1]));
    local leastSize = math.max(SMALLEST, math.min(fullSize, options.minSize[1]));

    -- A name is not given letters of exactly its own size. imgui makes the letters of a size the
    -- first time they are asked for, and makes room for them in its texture by moving the others
    -- about: with names of every size from the smallest to the largest coming and going as the
    -- player moves, that was done over and over, and for a frame each time the names were drawn from
    -- where their letters no longer were. So letters are kept at a few sizes only, the rungs, and a
    -- name is drawn from the smallest of them that is no smaller than it, scaled down to fit. Every
    -- rung is asked after every frame, in use or not, which keeps imgui from letting it go; and all
    -- of them before any name is set out, so that if the letters have been moved it is known first.
    local fullHeight = math.max(1, math.floor(fullSize * scale + 0.5));
    local rungs = options.shrink[1] and #RUNGS or 1;
    for _ = 1, 2 do
        local sets = glyphSets;
        for rung = 1, rungs do
            glyphSet(font, math.max(1, math.floor(fullHeight * RUNGS[rung] + 0.5)));
        end
        -- moved while they were being looked at: once more, and they are all as they now are
        if (sets == glyphSets) then
            break;
        end
    end
    local shrink = options.shrink[1];
    local edge = math.max(0, math.min(4, options.outline[1]));
    local showIcons, showStars = options.showIcons[1], options.showStars[1];
    local iconScale = options.iconSize[1] / 100;
    local iconGap = math.floor(ICON_GAP * scale + 0.5);
    local nameGap = math.floor(math.max(0, math.min(24, options.iconSpacing[1])) * scale + 0.5);
    local dark = darkColor();

    local WANTED, STARS, TARGET = nameplates.Flag.Wanted, nameplates.Flag.Stars, nameplates.Flag.Target;

    -- how each kind of name is written, and the game, which is asked how far off a thing is only if
    -- some line has the distance in it
    local MONSTER = nameplates.Category.Monster;
    local nameFormat = format.Compile(options.nameFormat[1]);
    local monsterFormat = format.Compile(options.monsterFormat[1]);
    local targetFormat = options.targetFormat[1] ~= '' and format.Compile(options.targetFormat[1]) or monsterFormat;
    local entities = (nameFormat.distance or monsterFormat.distance or targetFormat.distance) and AshitaCore:GetMemoryManager():GetEntity() or nil;

    for i = 0, hook.Count - 1 do
        local name = hook.Names[i];

        if (bit.band(name.Flags, WANTED) ~= 0) then
            local written = parse(name);
            local iconCount = showIcons and #written.icons or 0;

            -- The game draws a name at one size out to a distance, then smaller and smaller until at
            -- its furthest it is nothing: Scale is 1 and then falls to 0. Here it shrinks over the
            -- same distance, from its largest to its smallest and not to nothing, or keeps its size;
            -- and either way fades out over the last of it.
            local nearness = math.max(0, math.min(1, name.Scale));
            local size = shrink and (leastSize + (fullSize - leastSize) * nearness) or fullSize;

            -- as solid as the game has it, which fades a name with its character; but for the target,
            -- whose name the game pulses, as solid as it last held still
            local held = steadyColor(name);
            local solid = bit.rshift(bit.band(name.Flags, TARGET) ~= 0 and held or name.NameColor, 24) / 0x80;
            local near = nearness / (shrink and FADE_SHRUNK or FADE_OVER);
            local alpha = math.max(0, math.min(1, solid, near));

            if (alpha > 0 and (written.words ~= '' or iconCount > 0)) then
                -- its height in the game's picture, the rung its letters are taken from, and how much
                -- smaller than the rung it is: at the largest size it is the rung itself, letter for letter
                local height = size >= fullSize and fullHeight or math.max(1, size * scale);
                local rungHeight = fullHeight;
                for rung = 2, rungs do
                    local smaller = math.max(1, math.floor(fullHeight * RUNGS[rung] + 0.5));
                    if (smaller < height) then
                        break;
                    end
                    rungHeight = smaller;
                end
                local fit = math.min(1, height / rungHeight);
                local set = glyphSet(font, rungHeight);

                local nameEdge = math.min(edge, math.max(1, math.floor(size / 8 + 0.5))) * scale;
                if (set ~= nil and nameplates.BeginName(name.EntityIndex, alpha, edge > 0 and nameEdge or 0, dark)) then
                    local glyphs, baked = set.glyphs, set.baked;
                    -- what is written, part by part, as its line has it
                    local parts = nameFormat;
                    if (name.Category == MONSTER) then
                        parts = bit.band(name.Flags, TARGET) ~= 0 and targetFormat or monsterFormat;
                    end

                    -- how far off it is, to a tenth: written afresh only as that changes
                    if (parts.distance and entities ~= nil) then
                        -- the game keeps the distance squared
                        local tenths = math.floor(math.sqrt(entities:GetDistance(name.EntityIndex)) * 10 + 0.5);
                        if (written.tenths ~= tenths) then
                            written.tenths = tenths;
                            written.far = ('%.1f'):format(tenths / 10);
                        end
                    end

                    local width = 0;
                    for index = 1, #parts do
                        local part = parts[index];
                        local words = part.kind == 'name' and written.words or (part.kind == 'distance' and (written.far or '') or part.text);
                        for at = 1, #words do
                            local byte = words:byte(at);
                            local glyph = glyphs[byte];
                            if (glyph == nil) then
                                glyph = readGlyph(baked, byte);
                                glyphs[byte] = glyph;
                            end
                            if (glyph) then
                                width = width + glyph[9] * fit;
                            end
                        end
                    end

                    local iconSize = math.floor(height * iconScale + 0.5);
                    local smallStar = math.floor(iconSize * 0.5 + 0.5);

                    -- icons, then the name, hung from the point the game gave as the game hangs its
                    -- own: the middle of them on it from side to side, and the top of the letters at it
                    local iconsWidth = iconCount > 0 and (iconCount * iconSize + (iconCount - 1) * iconGap + nameGap) or 0;
                    local left = math.floor(-(iconsWidth + width) * 0.5);
                    local top = 0;
                    height = math.floor(height + 0.5);
                    local iconTop = math.floor((height - iconSize) * 0.5);

                    -- the stars over the middle of it: a small one, a large one, a small one
                    local star = showStars and bit.band(name.Flags, STARS) ~= 0 and icons.Place(STAR);
                    if (star) then
                        local starsLeft = math.floor(-(smallStar * 2 + iconSize) * 0.5);
                        local starsTop = math.min(top, iconTop) - iconSize - 1;
                        local smallTop = starsTop + math.floor((iconSize - smallStar) * 0.5);
                        nameplates.Quad(starsLeft, smallTop, starsLeft + smallStar, smallTop + smallStar, star[1], star[2], star[3], star[4], WHITE, ICON_SLOT, false);
                        nameplates.Quad(starsLeft + smallStar, starsTop, starsLeft + smallStar + iconSize, starsTop + iconSize, star[1], star[2], star[3], star[4], WHITE, ICON_SLOT, false);
                        nameplates.Quad(starsLeft + smallStar + iconSize, smallTop, starsLeft + smallStar * 2 + iconSize, smallTop + smallStar, star[1], star[2], star[3], star[4], WHITE, ICON_SLOT, false);
                    end

                    for index = 1, iconCount do
                        local byte = written.icons[index];
                        local color = byte == PEARL and pearlColor(name.IconColor) or WHITE;
                        local at = icons.Place(byte);
                        if (at) then
                            nameplates.Quad(left, iconTop, left + iconSize, iconTop + iconSize, at[1], at[2], at[3], at[4], color, ICON_SLOT, false);
                        end
                        if (byte == TWO_PART) then
                            at = icons.Place(byte + 1);
                            if (at) then
                                nameplates.Quad(left, iconTop, left + iconSize, iconTop + iconSize, at[1], at[2], at[3], at[4], color, ICON_SLOT, false);
                            end
                        end
                        left = left + iconSize + (index < iconCount and iconGap or nameGap);
                    end

                    local own = nameColor(held);
                    local pen = left;
                    for index = 1, #parts do
                        local part = parts[index];
                        local words = part.kind == 'name' and written.words or (part.kind == 'distance' and (written.far or '') or part.text);
                        local color = part.color or own;
                        for at = 1, #words do
                            local glyph = glyphs[words:byte(at)];
                            if (glyph) then
                                if (glyph[10]) then
                                    nameplates.Quad(pen + glyph[1] * fit, top + glyph[2] * fit, pen + glyph[3] * fit, top + glyph[4] * fit, glyph[5], glyph[6], glyph[7], glyph[8], color, FONT_SLOT, true);
                                end
                                pen = pen + glyph[9] * fit;
                            end
                        end
                    end

                    nameplates.EndName();
                end
            end
        end
    end
end

return custom;
