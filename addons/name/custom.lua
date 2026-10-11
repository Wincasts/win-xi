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
local levels = require('levels');

local custom = {};

local PEARL         = 0x92; -- the linkshell pearl, the one icon that is given a colour
local TWO_PART      = 0xAC; -- an icon the game draws with the next character of its font over it
local STAR          = 0xAD; -- the star of the Job Mastery stars: a small one, a large one, a small one
local ICON_GAP      = 2;    -- pixels between one icon and the next
local FADE_OVER     = 1 / 3; -- the last part of a name's distance over which it fades out, if it does not shrink
local FADE_SHRUNK   = 0.15; -- and if it does, having by then shrunk to its smallest
local SMALLEST      = 6;    -- pixels: the smallest a name can be set to be
local LARGEST       = 48;   -- and the largest
local FONT_SLOT, ICON_SLOT, SENSE_SLOT, TEMPER_SLOT = 0, 1, 2, 3; -- the plugin's numbers for the textures the names are drawn from

-- What is written under the name of a monster its player has checked: see the frame, below
local DETAIL_SIZE   = 0.75; -- how large it is beside the name
local DETAIL_GAP    = 0.4;  -- the space between its parts, as a part of its own height
local DETAIL_BELOW  = 2;    -- pixels between the name and it
local DETAIL_IN     = 0.3;  -- seconds it takes to come
local DETAIL_SHOWN  = 5;    -- seconds it is there
local DETAIL_OUT    = 0.6;  -- seconds it takes to go

-- The signs for what a monster does, in assets/senses.png: mobdb's own icons, sixteen to a sheet in
-- four rows, each a quarter of it across and down
local SENSES = { AggroNQ = 0, AggroHQ = 1, PassiveNQ = 2, PassiveHQ = 3, Sight = 4, TrueSight = 5, Sound = 6, Blood = 7, Magic = 8, JA = 9, Scent = 10, Link = 11 };
-- what an aggressive monster notices its prey by, in the order they are drawn
local NOTICES = { 'Sight', 'TrueSight', 'Sound', 'Blood', 'Magic', 'JA', 'Scent' };

-- The sign that a monster is aggressive or is not, in assets/aggro.png: six for one that is not and
-- then six for one that is, four to a row. Of each six the first five are by how strong the monster
-- is, and the last is a notorious monster's, or one whose strength is impossible to gauge.
local TEMPERS       = 6;
local TEMPER_TOP    = 75;   -- the level from which an ordinary monster has the fifth
local RUNGS         = { 1, 0.75, 0.5 }; -- the sizes letters are kept at, as parts of the largest: see below
local SIZE_JUMP     = 0.15; -- a change in the game's size for a name, from one frame to the next, that is no step of a walk
local SIZE_HOLD     = 4;    -- frames such a change has to last to be believed
local STEADY_AFTER  = 4;    -- frames a name's colour has to stay the same to be taken as its own at once
local STEADY_STRETCH = 45;  -- frames over which the strongest of a pulsing name's colours is looked for
local SIGN_SIZE     = 0.7;  -- how large the magnifying glass is beside the letters it is written among
local MAGNIFIER     = 0xF002; -- the magnifying glass, among the icons Ashita's own font has with its letters
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
    showCheckDetails = function () return T{ true }; end, -- under a checked monster's name: how hard, what it does
    checkDetailsInWords = function () return T{ false }; end, -- what it notices its prey by, and that it links, in words and not signs
    -- How a name is written: [name] for the name, [distance] for how far off it is, [level] for the
    -- levels a monster can be, and the rest as it is typed (format.lua). One line for monsters, one
    -- for everything else, one for the monster that is the target and one for a monster that has been
    -- checked: either of the last two, left empty, changes nothing, and a monster that is both is
    -- written as one checked.
    nameFormat    = function () return T{ '[name]' }; end,
    monsterFormat = function () return T{ '[name]' }; end,
    targetFormat  = function () return T{ '' }; end,
    checkedFormat = function () return T{ '' }; end,
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
    for _, key in ipairs({ 'nameFormat', 'monsterFormat', 'targetFormat', 'checkedFormat' }) do
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

-- For finding out what the game does to a name as it becomes the target: while this is on, the name
-- of whatever is newly the target is said in the chat log for the frames that follow, as the plugin
-- lists it, with what it was the frame before.
local watching = false;
local watched = { index = nil, frames = 0, count = 0 };
local seenScale = {};   -- entity -> the game's size for its name, the last frame it was listed
local seenFrame = {};

function custom.Watch()
    watching = not watching;
    watched.index, watched.frames = nil, 0;
    return watching;
end

local function watch(hook, scale)
    local said = watched.frames > 0;
    local entries, target = 0, nil;
    for i = 0, hook.Count - 1 do
        local name = hook.Names[i];
        if (bit.band(name.Flags, nameplates.Flag.Target) ~= 0) then
            target = target or name.EntityIndex;
            if (name.EntityIndex == target) then
                entries = entries + 1;
            end
        end
    end

    if (target ~= watched.index) then
        watched.index = target;
        if (target ~= nil) then
            watched.frames, watched.count = 10, 0;
            local before = seenScale[target];
            print(('\30\81[name]\30\01 watch: target is now entity %d; the frame before its size was %s%s'):format(target,
                before and ('%.3f'):format(before) or 'not listed', (before and seenFrame[target] ~= hook.Frame - 1) and ' (some frames ago)' or ''));
        end
    end

    for i = 0, hook.Count - 1 do
        local name = hook.Names[i];
        if (watched.frames > 0 and name.EntityIndex == watched.index) then
            print(('\30\81[name]\30\01 watch %d: %s | listed %d times | size %.3f | flags %03X | colour %08X | at %.0f,%.0f | picture %.0fx%.0f, %.2f to the screen | names %d'):format(
                watched.count, ffi.string(name.Name), entries, name.Scale, name.Flags, name.NameColor, name.ScreenX, name.ScreenY, hook.TargetWidth, hook.TargetHeight, scale, hook.Count));
        end
        seenScale[name.EntityIndex], seenFrame[name.EntityIndex] = name.Scale, hook.Frame;
    end
    if (watched.frames > 0) then
        watched.frames, watched.count = watched.frames - 1, watched.count + 1;
    end
end

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
    local how = '[name] is the name, [distance] how far off it is, [level] the levels a monster can be, [checked] a magnifying glass on a monster you have checked, and [aggro] the sign that a monster is aggressive or is not; anything else is written as you type it.\nex: [aggro][name] [level][checked] ([distance])\n\n'
        .. 'A colour is #RRGGBB or a word: white, grey, red, green, blue, yellow, orange, purple, pink, cyan.\n'
        .. '[distance:yellow] or [name:#FF8000] colours that one thing; [yellow] colours everything after it, as far as [/].\n'
        .. 'With no colour, a thing is in the colour the game gives the name.';
    line('Name Format', 'nameFormat', '##name.nameFormat', 'How every name but a monster\'s is written.\n' .. how);
    line('Monster Format', 'monsterFormat', '##name.monsterFormat', 'How a monster\'s name is written.\n' .. how);
    line('Targeted Monster Format', 'targetFormat', '##name.targetFormat', 'How the name of the monster you have targeted is written. Left empty, it is written as other monsters\' are.\n' .. how);
    line('Checked Monster Format', 'checkedFormat', '##name.checkedFormat', 'How the name of a monster you have checked is written, until it dies or you leave the area; it comes before Targeted Monster Format for a monster that is both. Left empty, checking a monster changes nothing of how its name is set out.\n' .. how);

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
    widgets.Label('Show Check Details');
    imgui.Checkbox('##name.showCheckDetails', options.showCheckDetails);
    if (imgui.IsItemHovered()) then
        imgui.SetTooltip('Under the name of a monster you have just checked, for five seconds:\nhow hard a fight the game said it would be, what an aggressive one notices you by, and the family it links with.');
    end
    if (options.showCheckDetails[1]) then
        widgets.Label('Check Details In Words');
        imgui.Checkbox('##name.checkDetailsInWords', options.checkDetailsInWords);
        if (imgui.IsItemHovered()) then
            imgui.SetTooltip('The line is written as a sentence, with no signs in it.\nex: Too Weak, Sight Aggro, Link: Goblin\nWhat an aggressive monster notices you by is Sight, Sound, Blood, Magic, JA or Scent, with a stroke between them if there are several, and True Sight and True Sound for one that sees or hears truly. Link is the family it links with.');
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

-- How wide some words are in these letters, and the words written with their top left at a place
local function wordsWidth(set, words, fit)
    local glyphs, width = set.glyphs, 0;
    for at = 1, #words do
        local byte = words:byte(at);
        local glyph = glyphs[byte];
        if (glyph == nil) then
            glyph = readGlyph(set.baked, byte);
            glyphs[byte] = glyph;
        end
        if (glyph) then
            width = width + glyph[9] * fit;
        end
    end
    return width;
end

local function writeWords(set, words, pen, top, fit, color)
    local glyphs = set.glyphs;
    for at = 1, #words do
        local glyph = glyphs[words:byte(at)];
        if (glyph) then
            if (glyph[10]) then
                nameplates.Quad(pen + glyph[1] * fit, top + glyph[2] * fit, pen + glyph[3] * fit, top + glyph[4] * fit, glyph[5], glyph[6], glyph[7], glyph[8], color, FONT_SLOT, true);
            end
            pen = pen + glyph[9] * fit;
        end
    end
    return pen;
end

-- A sheet of signs from the assets folder, loaded the first time one of its signs is to be drawn:
-- its address for the plugin, or 0 if it would not load
local sheets = {};   -- file -> { texture = kept so that it is not let go, at = its address }

local function sheet(file)
    local known = sheets[file];
    if (known == nil) then
        known = { at = 0 };
        sheets[file] = known;
        pcall(function ()
            local d3d = require('d3d8');
            local made = ffi.new('IDirect3DTexture8*[1]');
            if (ffi.C.D3DXCreateTextureFromFileA(d3d.get_device(), addon.path .. 'assets/' .. file, made) == ffi.C.S_OK) then
                known.texture = d3d.gc_safe_release(ffi.cast('IDirect3DTexture8*', made[0]));
                known.at = tonumber(ffi.cast('uint32_t', known.texture));
            end
        end);
    end
    return known.at;
end

local function sensesTexture()
    return sheet('senses.png');
end

local function temperTexture()
    return sheet('aggro.png');
end

-- For whoever has the sheets some other way
function custom.SetSheets(senses, tempers)
    sheets['senses.png'] = { at = senses };
    sheets['aggro.png'] = { at = tempers };
end

-- Which sign of the aggro sheet is a monster's: by whether it is aggressive, and how strong. found is
-- what its player's check of it found, if it has been checked.
--
-- An ordinary monster's is by its level, the first four signs sharing the levels up to TEMPER_TOP
-- evenly among them and the fifth for all from there up: the level a check found, or failing that the
-- highest the tables say it can be. A notorious monster, and one a check found impossible to gauge,
-- has the sixth.
local function temperOf(monster, found)
    local tier;
    if (monster.Notorious or (found ~= nil and found.text == nil)) then
        tier = TEMPERS;
    else
        local level = (found ~= nil and tonumber(found.text)) or tonumber(monster.MaxLevel) or 0;
        if (level <= 0) then
            level = tonumber(monster.MinLevel) or 1;
        end
        if (level >= TEMPER_TOP) then
            tier = TEMPERS - 1;
        else
            tier = math.floor((math.max(1, level) - 1) * (TEMPERS - 2) / (TEMPER_TOP - 1)) + 1;
        end
    end
    return (monster.Aggro and TEMPERS or 0) + tier - 1;
end

-- The same in words, for one who would sooner read than know the signs: 'Sight/Sound/Blood Aggro',
-- with sight and sound called true for a monster that sees or hears truly; and 'Link: Goblin' for what
-- it links with. Kept on the monster. Nothing for one that is not aggressive, or does not link.
local NOTICE_WORDS = { Sight = 'Sight', Sound = 'Sound', Blood = 'Blood', Magic = 'Magic', JA = 'JA', Scent = 'Scent' };
local NOTICE_ORDER = { 'Sight', 'Sound', 'Blood', 'Magic', 'JA', 'Scent' };

local function noticeWords(monster)
    local words = monster.nameNotices;
    if (words == nil) then
        local list = {};
        if (monster.Aggro) then
            for _, notice in ipairs(NOTICE_ORDER) do
                if (monster[notice]) then
                    local truly = monster.TrueSight and (notice == 'Sight' or notice == 'Sound');
                    list[#list + 1] = (truly and 'True ' or '') .. NOTICE_WORDS[notice];
                end
            end
        end
        words = monster.Aggro and ((#list > 0 and (table.concat(list, '/') .. ' ') or '') .. 'Aggro') or '';
        monster.nameNotices = words;
    end
    return words;
end

local function linkWords(monster)
    local words = monster.nameLink;
    if (words == nil) then
        words = monster.Link and ((monster.Family ~= nil and monster.Family ~= '') and ('Link: ' .. monster.Family) or 'Link') or '';
        monster.nameLink = words;
    end
    return words;
end

-- The signs for what an aggressive monster notices its prey by, as the tables have it: kept on the monster
local function signsOf(monster)
    local signs = monster.nameSigns;
    if (signs == nil) then
        signs = {};
        if (monster.Aggro) then
            for _, notice in ipairs(NOTICES) do
                if (monster[notice]) then
                    signs[#signs + 1] = SENSES[notice];
                end
            end
        end
        monster.nameSigns = signs;
    end
    return signs;
end

-- A sign of the font's that is no letter, and may not be there: false if it is not
local function readSign(baked, code)
    local ok, glyph = pcall(baked.FindGlyphNoFallback, baked, code);
    if (not ok or glyph == nil) then
        return false;
    end
    return { glyph.X0, glyph.Y0, glyph.X1, glyph.Y1, glyph.U0, glyph.V0, glyph.U1, glyph.V1, glyph.AdvanceX, true };
end

-- The letters of the font at this height, or nil if imgui has none. key is what they are kept under:
-- the height, or for the font everything else is written in, kept beside a font of the player's
-- choosing for the signs that one does not have, the height below nothing.
local function glyphSet(font, height, key)
    key = key or height;
    local set = glyphSets[key];
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
        glyphSets[key] = set;
    end

    local now = readGlyph(baked, PROBE);
    local was = set.glyphs[PROBE];
    if (was and now and (was[5] ~= now[5] or was[6] ~= now[6] or was[7] ~= now[7] or was[8] ~= now[8])) then
        -- the letters have been moved: every size's are read again
        glyphSets = {};
        set = { glyphs = {} };
        glyphSets[key] = set;
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

-- The game's size for a name, less its starts: as a character becomes the target the game gives its
-- name its full size for a frame, whatever distance it is at, and then the size it had. A name whose
-- size leaps between one frame and the next keeps the size it had until the new one has lasted; one
-- that changes as a walk changes it is followed at once. known is what is kept of the name's entity.
local function steadySize(known, name)
    local size = math.max(0, math.min(1, name.Scale));

    if (known.sizeOf ~= name.ServerId or known.sizeSeen ~= frame - 1 or math.abs(size - known.size) <= SIZE_JUMP) then
        -- another character's, or one not listed last frame, or a step: as the game has it
        known.sizeOf, known.size, known.sizeRun = name.ServerId, size, 0;
    elseif (known.sizeRun > 0 and math.abs(size - known.sizeLeap) <= SIZE_JUMP) then
        known.sizeRun = known.sizeRun + 1;
        if (known.sizeRun >= SIZE_HOLD) then
            known.size, known.sizeRun = size, 0;
        end
    else
        known.sizeLeap, known.sizeRun = size, 1;
    end

    known.sizeSeen = frame;
    return known.size;
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
    nameplates.SetTexture(SENSE_SLOT, sheets['senses.png'] and sheets['senses.png'].at or 0);
    nameplates.SetTexture(TEMPER_SLOT, sheets['aggro.png'] and sheets['aggro.png'].at or 0);

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

    -- the magnifying glass is in the font everything else is written in: with a font of the player's
    -- choosing for the names, that one's letters are kept as well, for it
    local nameFormat = format.Compile(options.nameFormat[1]);
    local monsterFormat = format.Compile(options.monsterFormat[1]);
    local targetFormat = options.targetFormat[1] ~= '' and format.Compile(options.targetFormat[1]) or monsterFormat;
    -- nil while its line is empty: a monster that has been checked is then written as any other
    local checkedFormat = options.checkedFormat[1] ~= '' and format.Compile(options.checkedFormat[1]) or nil;
    local signsApart = font ~= nil and (nameFormat.checked or monsterFormat.checked or targetFormat.checked or (checkedFormat ~= nil and checkedFormat.checked));
    for _ = 1, 2 do
        local sets = glyphSets;
        for rung = 1, rungs do
            local rungHeight = math.max(1, math.floor(fullHeight * RUNGS[rung] + 0.5));
            glyphSet(font, rungHeight);
            if (signsApart) then
                glyphSet(nil, rungHeight, -rungHeight);
            end
        end
        -- moved while they were being looked at: once more, and they are all as they now are
        if (sets == glyphSets) then
            break;
        end
    end
    local shrink = options.shrink[1];
    local edge = math.max(0, math.min(4, options.outline[1]));
    local showIcons, showStars = options.showIcons[1], options.showStars[1];
    local showDetails = options.showCheckDetails[1];
    local detailsInWords = options.checkDetailsInWords[1];
    local now = os.clock();
    local iconScale = options.iconSize[1] / 100;
    local iconGap = math.floor(ICON_GAP * scale + 0.5);
    local nameGap = math.floor(math.max(0, math.min(24, options.iconSpacing[1])) * scale + 0.5);
    local dark = darkColor();

    local WANTED, STARS, TARGET = nameplates.Flag.Wanted, nameplates.Flag.Stars, nameplates.Flag.Target;

    -- how each kind of name is written, and the game, which is asked how far off a thing is only if
    -- some line has the distance in it
    local MONSTER = nameplates.Category.Monster;
    local entities = (nameFormat.distance or monsterFormat.distance or targetFormat.distance or (checkedFormat ~= nil and checkedFormat.distance)) and AshitaCore:GetMemoryManager():GetEntity() or nil;

    -- a monster that was checked and has died is forgotten before any level is written; what is
    -- written of a level is kept until what is known of levels changes
    levels.Tidy();
    local levelsAt = levels.Generation();

    if (watching) then
        watch(hook, scale);
    end

    for i = 0, hook.Count - 1 do
        local name = hook.Names[i];

        if (bit.band(name.Flags, WANTED) ~= 0) then
            local written = parse(name);
            local iconCount = showIcons and #written.icons or 0;

            -- The game draws a name at one size out to a distance, then smaller and smaller until at
            -- its furthest it is nothing: Scale is 1 and then falls to 0. Here it shrinks over the
            -- same distance, from its largest to its smallest and not to nothing, or keeps its size;
            -- and either way fades out over the last of it.
            local nearness = steadySize(written, name);
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

                    -- its level if its player has checked it, or the levels it can be: looked for once
                    -- for each character there is, and again when what is known of levels changes
                    if ((parts.level or parts.checked or parts.aggro or ((checkedFormat ~= nil or showDetails) and name.Category == MONSTER))
                            and (written.levelOf ~= name.ServerId or written.levelAt ~= levelsAt)) then
                        written.levelOf, written.levelAt = name.ServerId, levelsAt;
                        local plain = ffi.string(name.Name);
                        written.level = levels.Of(name.EntityIndex, plain, name.ServerId) or '';
                        written.found = levels.Checked(name.EntityIndex, name.ServerId);
                        written.isChecked = written.found ~= nil;
                        written.monster = levels.Monster(name.EntityIndex, plain);
                    end
                    -- one that has been checked has a line of its own, if its player has written one
                    if (checkedFormat ~= nil and name.Category == MONSTER and written.isChecked) then
                        parts = checkedFormat;
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

                    -- the magnifying glass for one that has been checked, if the font has it
                    local sign = false;
                    if (parts.checked and written.isChecked) then
                        local signs = signsApart and glyphSet(nil, rungHeight, -rungHeight) or set;
                        if (signs ~= nil) then
                            sign = signs.glyphs[MAGNIFIER];
                            if (sign == nil) then
                                sign = readSign(signs.baked, MAGNIFIER);
                                signs.glyphs[MAGNIFIER] = sign;
                            end
                        end
                    end

                    -- the sign that it is aggressive or is not, for a monster the tables have: as high
                    -- as the name, from the sheet of signs
                    local temper, temperSize = nil, math.floor(height + 0.5);
                    if (parts.aggro and written.monster ~= nil and name.Category == MONSTER and temperTexture() ~= 0) then
                        temper = temperOf(written.monster, written.found);
                    end

                    local width = 0;
                    for index = 1, #parts do
                        local part = parts[index];
                        local kind = part.kind;
                        if (kind == 'aggro' and temper ~= nil) then
                            width = width + temperSize;
                        end
                        if (kind == 'checked') then
                            width = width + (sign and sign[9] * fit * SIGN_SIZE or 0);
                        end
                        local words = kind == 'name' and written.words or (kind == 'distance' and (written.far or '')) or (kind == 'level' and (written.level or '')) or part.text or '';
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
                        local kind = part.kind;
                        local words = kind == 'name' and written.words or (kind == 'distance' and (written.far or '')) or (kind == 'level' and (written.level or '')) or part.text or '';
                        local color = part.color or own;
                        if (kind == 'aggro' and temper ~= nil) then
                            local u, v = (temper % 4) * 0.25, math.floor(temper / 4) * 0.25;
                            nameplates.Quad(pen, top, pen + temperSize, top + temperSize, u, v, u + 0.25, v + 0.25, part.color or WHITE, TEMPER_SLOT, false);
                            pen = pen + temperSize;
                        end
                        if (kind == 'checked' and sign) then
                            -- smaller than the letters by a set part, whatever size they are, and
                            -- made smaller about the middle of the line so that it stays level with them
                            local small = fit * SIGN_SIZE;
                            local middle = rungHeight * 0.5;
                            nameplates.Quad(pen + sign[1] * small, top + (middle + (sign[2] - middle) * SIGN_SIZE) * fit,
                                pen + sign[3] * small, top + (middle + (sign[4] - middle) * SIGN_SIZE) * fit,
                                sign[5], sign[6], sign[7], sign[8], color, FONT_SLOT, true);
                            pen = pen + sign[9] * small;
                        end
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

                    -- Under the name of a monster its player has checked, and with its middle under
                    -- the name's: how hard a fight the game said it would be; then, if the tables
                    -- have the monster and it is aggressive, what it notices its prey by; and if it
                    -- links, the sign for that and the family it links with. Whether it is aggressive
                    -- at all is not said here: [aggro] in the name's own line says it.
                    -- It comes as the monster is checked, is there a few seconds, and goes: how solid
                    -- it is, from how long ago that was.
                    local showing = 0;
                    if (showDetails and written.isChecked and name.Category == MONSTER) then
                        local since = now - written.found.at;
                        if (since < DETAIL_IN) then
                            showing = since / DETAIL_IN;
                        elseif (since < DETAIL_IN + DETAIL_SHOWN) then
                            showing = 1;
                        elseif (since < DETAIL_IN + DETAIL_SHOWN + DETAIL_OUT) then
                            showing = 1 - (since - DETAIL_IN - DETAIL_SHOWN) / DETAIL_OUT;
                        end
                    end
                    if (showing > 0) then
                        -- the colours of its parts, as solid as it now is
                        local solidity = math.floor(showing * 255 + 0.5) * 0x1000000;
                        local own = own % 0x1000000 + solidity;
                        local WHITE = 0xFFFFFF + solidity;
                        local detail = fit * DETAIL_SIZE;
                        local detailHeight = math.floor(height * DETAIL_SIZE + 0.5);
                        local gap = math.floor(detailHeight * DETAIL_GAP + 0.5);
                        local hard = written.found.hard or '';
                        local monster = written.monster;

                        -- In words it is the one sentence, its parts with commas between them: "Too
                        -- Weak, Sight Aggro, Link: Goblin". Put together once for each check.
                        if (detailsInWords) then
                            if (written.sentenceOf ~= written.found or written.sentenceFor ~= monster) then
                                written.sentenceOf, written.sentenceFor = written.found, monster;
                                local said = { hard ~= '' and hard or nil };
                                if (monster ~= nil) then
                                    local notices, linked = noticeWords(monster), linkWords(monster);
                                    if (notices ~= '') then said[#said + 1] = notices; end
                                    if (linked ~= '') then said[#said + 1] = linked; end
                                end
                                written.sentence = table.concat(said, ', ');
                            end
                            hard, monster = written.sentence, nil;
                        end

                        -- what it notices its prey by, and what it links with: as signs, or in words
                        local sheet = (monster ~= nil) and sensesTexture() or 0;
                        local signs = (monster ~= nil and sheet ~= 0) and signsOf(monster) or nil;
                        local notices = '';
                        local links = monster ~= nil and monster.Link;
                        local linked = links and (monster.Family or '') or '';

                        local hardWidth = wordsWidth(set, hard, detail);
                        local noticesWidth = wordsWidth(set, notices, detail);
                        local signsWidth = noticesWidth + (signs ~= nil and #signs or 0) * detailHeight;
                        local linkWidth = (links and sheet ~= 0) and detailHeight or 0;
                        local linkedWidth = wordsWidth(set, linked, detail);

                        local across, pieces = 0, 0;
                        for _, piece in ipairs({ hardWidth, signsWidth, linkWidth + linkedWidth + ((linkWidth > 0 and linkedWidth > 0) and math.floor(gap * 0.5) or 0) }) do
                            if (piece > 0) then
                                across, pieces = across + piece, pieces + 1;
                            end
                        end
                        across = across + math.max(0, pieces - 1) * gap;

                        local at = math.floor(-across * 0.5);
                        local below = top + height + math.floor(DETAIL_BELOW * scale + 0.5);

                        if (hardWidth > 0) then
                            at = writeWords(set, hard, at, below, detail, own) + gap;
                        end
                        if (signsWidth > 0) then
                            if (noticesWidth > 0) then
                                at = writeWords(set, notices, at, below, detail, own);
                            end
                            for index = 1, (signs ~= nil and #signs or 0) do
                                local sign = signs[index];
                                local u, v = (sign % 4) * 0.25, math.floor(sign / 4) * 0.25;
                                nameplates.Quad(at, below, at + detailHeight, below + detailHeight, u, v, u + 0.25, v + 0.25, WHITE, SENSE_SLOT, false);
                                at = at + detailHeight;
                            end
                            at = at + gap;
                        end
                        if (linkWidth > 0) then
                            local u, v = (SENSES.Link % 4) * 0.25, math.floor(SENSES.Link / 4) * 0.25;
                            nameplates.Quad(at, below, at + detailHeight, below + detailHeight, u, v, u + 0.25, v + 0.25, WHITE, SENSE_SLOT, false);
                            at = at + linkWidth + (linkedWidth > 0 and math.floor(gap * 0.5) or 0);
                        end
                        if (linkedWidth > 0) then
                            writeWords(set, linked, at, below, detail, own);
                        end
                    end

                    nameplates.EndName();
                end
            end
        end
    end
end

return custom;
