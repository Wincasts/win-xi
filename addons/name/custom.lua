-- The names drawn in winxi's style, in place of the game's own.
--
--   custom.Defaults(defaults)     adds the settings below to an addon's own
--   custom.Settle(options)        the settings have been loaded: what an older version kept is brought over
--   custom.Frame(options, hook)   each frame: claims the names and draws them;
--                                 hook is the plugin's block, as nameplates.Hook gave it this frame.
--                                 Returns nil, or why nothing was claimed: a key of diag.Reasons, and
--                                 for 'texture' what imgui said, for the log
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
-- A claim lapses by itself: when the addon is unloaded, the game draws the names again.
local bit   = require('bit');
local ffi   = require('ffi');
local imgui = require('imgui');
local text       = require('winxi.text');
local nameplates = require('winxi.nameplates');
local winxiFonts = require('winxi.fonts');
local icons = require('icons');
local format = require('format');
local levels = require('levels');
local letterBadges = require('letter_badges');
local filteredText = require('filtered_text');
local statuses = require('statuses');
local healthbar = require('healthbar');
local vendors = require('vendors');
local roles = require('roles');
local special = require('special');
local nameColours = require('name_colours');
local inline = require('inline_tokens');
local nameTypes = require('name_types');
local entityTypes = require('entity_types');
local rules = require('block_rules');
local diag = require('diag');

local custom = {};
local fontPipeline = { Readability = require('readability'), Castbar = require('castbar') };

local STAR          = 0xAD; -- the star of the Job Mastery stars: a small one, a large one, a small one
local FADE_SHRUNK   = 0.15; -- the last part of a name's distance over which it fades out
local DESPAWN_FADE  = 0.20; -- seconds to remove a monster label after its model stops being rendered
local SPAWNED      = 0x200; -- GetRenderFlags0: the client is showing this entity (also used by mark)
-- The plugin's numbers for the textures the names are drawn from. In tables, here and below: a
-- function can name sixty things from outside itself and no more, and the frame's is near that.
local SLOT = { Font = 0, Icon = 1, Sense = 2, Temper = 3, Sign = 4 };
-- What is written for the name of a monster a tracked notorious monster is drawn by lot from. Its
-- sign, a vendor's coin and the party roles are special.lua's sheet. In a table: the frame's function
-- has no room for more names than it has.
local HUNT = { Placeholder = 'Placeholder' };
-- statuses.lua has 7, the last, for the sheet of status icons.

-- What is written under the name of a monster its player has checked: see the frame, below
local DETAIL = {
    Gap   = 0.4,  -- the space between its parts, as a part of its own height
    Below = 2,    -- pixels between the name and it
    In    = 0.3,  -- seconds it takes to come
    Shown = 5,    -- seconds it is there
    Out   = 0.6,  -- seconds it takes to go
};

-- The signs for what a monster does, in assets/senses.png: mobdb's own icons, sixteen to a sheet in
-- four rows, each a quarter of it across and down. The first four, for whether it is aggressive, are
-- no longer drawn from: assets/aggro.png has taken their place.
local SENSES = { Sight = 4, TrueSight = 5, Sound = 6, Blood = 7, Magic = 8, JA = 9, Scent = 10, Link = 11 };
-- what an aggressive monster notices its prey by, in the order they are drawn
local NOTICES = { 'Sight', 'TrueSight', 'Sound', 'Blood', 'Magic', 'JA', 'Scent' };

-- The sign that a monster is aggressive or is not, in assets/aggro.png: six for one that is not and
-- then six for one that is, four to a row. Of each six the first five are by how strong the monster
-- is, and the last is a notorious monster's, or one whose strength is impossible to gauge.
local TEMPER_SIZE   = 1.25; -- how large it is drawn beside the name's letters
local TEMPERS       = 6;
local TEMPER_TOP    = 75;   -- the level from which an ordinary monster has the fifth
local RUNGS         = { 1, 0.75, 0.5 }; -- the sizes letters are kept at, as parts of the largest: see below
local SIZE_JUMP     = 0.15; -- a change in the game's size for a name, from one frame to the next, that is no step of a walk
local SIZE_HOLD     = 0.1;  -- seconds such a change has to last to be believed: longer than a frame of the game's own (a 30th)
local PULSE_SLACK   = 3;    -- of the game's 0x80: how far a channel may stray from a pulse's mix and be counted in it
local SUB_SETTLE    = 0.5;  -- seconds after a character stops being the sub target that its name's size is still held
local SIGN_SIZE     = 0.7;  -- how large the magnifying glass is beside the letters it is written among
local MAGNIFIER     = 0xF002; -- the magnifying glass, among the icons Ashita's own font has with its letters
local PROBE         = 65;   -- the letter looked at each frame to see that the font's letters are where they were
local SUBTARGET_NONE = 0xFFFFFFFF; -- the sub-target flags while no sub target is being chosen

local FONT_FOLDER   = 'C:\\Windows\\Fonts\\';

-- What can be set. A setting changed by a control is a table of one, as imgui wants.
local settings = {
    fontBold    = function () return T{ false }; end, -- simulated: each letter drawn twice, a pixel apart
    fontSmooth  = function () return T{ false }; end, -- optional prefiltered glyph atlas; native layout metrics
    fontSize    = function () return T{ 15 }; end,    -- shared nearby name size for every entity category
    minSize     = function () return T{ 10 }; end,    -- shared distant name size for every entity category
    iconOutline = function () return T{ 1 }; end,
    iconOutlineOpacity = function () return T{ 100 }; end,
    textOutlineOpacity = function () return T{ 100 }; end, -- the text's dark edge, as a percentage of its own
    outline     = function () return T{ 1 }; end,     -- how thick the dark edge round them is, in pixels
    font        = function () return ''; end,         -- a file of FONT_FOLDER, or nothing for the font everything else is in
    iconFormatVersion = function () return 0; end,
    iconSize    = function () return T{ 125 }; end,   -- an icon's side, as a percentage of the height of the names
    iconSpacing = function () return T{ 2 }; end,     -- pixels between the last icon and the name
    showStars   = function () return T{ true }; end,
    playerIconSource = function () return T{ 'game' }; end, -- icons.Sources; unavailable sources use bundled artwork
    signFormatVersion = function () return 0; end, -- 1 once Party Icons and Vendor Icons are in the formats
    showCastBar = function () return T{ false }; end,
    castBarWeaponskills = function () return T{ false }; end,
    castBarAutoWidth = function () return T{ false }; end,
    castNameScale = function () return T{ 75 }; end,
    castTimerScale = function () return T{ 75 }; end,
    castBarSkillTextOnly = function () return T{ true }; end, -- weaponskills and TP moves as words, no bar
    castShowName = function () return T{ true }; end,
    castShowTimer = function () return T{ true }; end,
    castTextColour = function () return T{ 'white' }; end, -- custom.CastTextColours
    castTextColor = function () return T{ 1, 1, 1, 1 }; end, -- for custom
    showHealthBar = function () return T{ false }; end, -- shared by every entity type
    healthBarsCombatOnly = function () return T{ false }; end,
    healthBarWidth = function () return T{ 60 }; end,
    healthBarHeight = function () return T{ 6 }; end,
    healthBarCategories = function () return T{ 0xFF }; end, -- which kinds of name have one: entity_types
    tokenFormatVersion = function () return 0; end,
    trackedNm = function () return T{ '' }; end, -- the notorious monster being hunted, by name, or nothing
    labelPlaceholders = function () return T{ true }; end, -- its placeholders are named Placeholder
    huntScale = function () return T{ 100 }; end, -- its name's size, as a percentage of the others'
    subtargetScale = function () return T{ 100 }; end, -- the sub target's name's size, as a percentage of the others'
    letterSpacing = function () return T{ 0 }; end, -- screen pixels between the letters of a name at its largest
    checkSize = function () return T{ 90 }; end, -- percent of the name's size
    abbreviateDifficulty = function () return T{ true }; end, -- compact difficulty by default
    showCheckDetails = function () return T{ true }; end, -- under a checked monster's name: how hard, what it does
    checkDetailsInWords = function () return T{ false }; end, -- what it notices its prey by, and that it links, in words and not signs
    -- How a name is written: [name] for the name, [distance] for how far off it is, [level] for the
    -- levels a monster can be, and the rest as it is typed (format.lua). One line for all monsters
    -- and separate editable lines for players/pets and non-combat NPCs.
    npcFormat = function () return T{ '[vendor: space=4][name]' }; end,
    nameFormat    = function () return T{ '[party: space=2][icons: space=4][name]' }; end,
    monsterFormat = function () return T{ '[name]' }; end,
};

-- What Settle makes good: the setting, the kind of value it holds, and for a number its bounds
local settled = {
    { 'iconOutline', 'number', 0, 3 }, { 'iconOutlineOpacity', 'number', 0, 100 },
    { 'textOutlineOpacity', 'number', 0, 100 },
    { 'checkSize', 'number', 50, 125 }, { 'healthBarWidth', 'number', 12, 300 }, { 'healthBarHeight', 'number', 3, 40 },
    { 'huntScale', 'number', 100, 200 }, { 'subtargetScale', 'number', 50, 200 },
    { 'letterSpacing', 'number', 0, 10 },
    { 'showCastBar', 'boolean' }, { 'castBarWeaponskills', 'boolean' }, { 'castBarAutoWidth', 'boolean' },
    { 'castNameScale', 'number', 25, 200 }, { 'castTimerScale', 'number', 25, 200 },
    { 'castBarSkillTextOnly', 'boolean' }, { 'castShowName', 'boolean' }, { 'castShowTimer', 'boolean' },
    { 'castTextColour', 'string' },
    { 'showHealthBar', 'boolean' }, { 'healthBarsCombatOnly', 'boolean' }, { 'labelPlaceholders', 'boolean' }, { 'playerIconSource', 'string' },
    { 'abbreviateDifficulty', 'boolean' }, { 'fontBold', 'boolean' }, { 'fontSmooth', 'boolean' },
    { 'trackedNm', 'string' }, { 'nameFormat', 'string' }, { 'monsterFormat', 'string' }, { 'npcFormat', 'string' },
};

-- What a cast's words are written in
custom.CastTextColours = {
    { key = 'white', label = 'White' },
    { key = 'name', label = 'Name Colour' },
    { key = 'custom', label = 'Custom' },
};

function custom.Defaults(defaults)
    fontPipeline.Readability.Defaults(defaults);
    nameTypes.Defaults(defaults);
    nameColours.Defaults(defaults);
    for key, make in pairs(settings) do
        defaults[key] = make();
    end
    return defaults;
end

-- Up to 1.10 a monster's distance was a setting of its own, and another said whether only the
-- target's was written: they are made the lines that say the same, once.
function custom.Settle(options)
    fontPipeline.Readability.Settle(options);
    -- settings of earlier versions that are no longer kept
    options.customNames, options.shrink, options.gdiFonts, options.gdiFamily = nil, nil, nil, nil;
    options.targetFormat, options.checkedFormat, options.statusTimers = nil, nil, nil;
    options.showMobLevel, options.showAggroIcons, options.statusFfxivIcons = nil, nil, nil;
    options.checkFormat = nil; -- the Experimental Builder's check line, which went in 1.38: the original line is drawn
    -- each setting a file may have otherwise is made its default, and a number kept within its bounds
    for _, spec in ipairs(settled) do
        local key, kind = spec[1], spec[2];
        local value = options[key];
        if (type(value) ~= 'table' or type(value[1]) ~= kind or value[1] ~= value[1]) then
            value = settings[key]();
            options[key] = value;
        end
        if (kind == 'number') then
            value[1] = math.max(spec[3], math.min(spec[4], math.floor(value[1])));
        end
    end

    -- What the formats say was once said by switches, which a file saved before then still has: each
    -- is brought into its format once, and let go of
    local function was(key)
        local value = options[key];
        if (type(value) ~= 'table') then return nil; end
        return value[1] == true;
    end
    if (options.iconFormatVersion ~= 1) then
        -- Preserve old visibility and layout once, then let the string own placement/visibility.
        local showIcons = was('showIcons');
        if (showIcons == false
                and options.nameFormat[1] == '[icons: space=4][name]') then
            options.nameFormat[1] = '[name]';
        elseif (not format.Compile(options.nameFormat[1]).icons and showIcons) then
            local size = tonumber(options.iconSize and options.iconSize[1]) or 125;
            local space = tonumber(options.iconSpacing and options.iconSpacing[1]) or 2;
            if (size ~= size) then size = 125; end
            if (space ~= space) then space = 2; end
            options.nameFormat[1] = ('[icons: size=%d, space=%d]'):format(
                math.max(25, math.min(300, math.floor(size))), math.max(0, math.min(64, math.floor(space)))) .. options.nameFormat[1];
        end
        options.iconFormatVersion = 1;
    end

    if (options.tokenFormatVersion ~= 1) then
        local parts = format.Compile(options.monsterFormat[1]);
        if (was('showMobLetter')) then
            if (not parts.letter) then
                options.monsterFormat[1] = options.monsterFormat[1] .. (was('doubleMobLetters')
                    and ' [letters: type=double]' or ' [letters]');
            elseif (was('doubleMobLetters')) then
                options.monsterFormat[1] = format.Serialize(parts, true);
            end
        end
        options.tokenFormatVersion = 1;
    end
    options.showIcons, options.showMobLetter, options.doubleMobLetters = nil, nil, nil;

    -- Party Icons (Off, Beside or Replace Game Icons) and Vendor Icons were settings: they become
    -- [party] before each [icons] and [vendor] before the NPC format, once. A [party] or [vendor]
    -- there already can only be the defaults': kept where the switch was the default, taken out where not.
    if (options.signFormatVersion ~= 1) then
        local mode = type(options.partyIcons) == 'table' and options.partyIcons[1] or 'beside';
        if (mode ~= 'off' and mode ~= 'replace') then mode = 'beside'; end
        local spacing = tonumber(options.iconSpacing and options.iconSpacing[1]) or 2;
        if (spacing ~= spacing) then spacing = 2; end
        spacing = math.max(0, math.min(64, math.floor(spacing)));
        for _, key in ipairs({ 'nameFormat', 'monsterFormat', 'npcFormat' }) do
            local text = options[key][1];
            if (mode ~= 'beside' or not format.Compile(text).party) then
                text = text:gsub('%[%s*party%s*%]', ''):gsub('%[%s*party%s*:[^%]]*%]', '');
            end
            local at = text:lower():find('%[%s*icons');
            if (mode ~= 'off' and at ~= nil and not format.Compile(text).party) then
                local iconsPart;
                for _, part in ipairs(format.Compile(text)) do
                    if (part.kind == 'icons') then iconsPart = part; break; end
                end
                -- beside: as far from the icons as they are from each other; replace: as far from
                -- what follows as the icons were
                local sign = mode == 'replace'
                    and ('[party: replace, space=%d]'):format(iconsPart and iconsPart.space or spacing)
                    or ('[party: space=%d]'):format(iconsPart and iconsPart.gap or 2);
                text = text:sub(1, at - 1) .. sign .. text:sub(at);
            end
            options[key][1] = text;
        end
        local coin = type(options.showVendorIcons) ~= 'table' or options.showVendorIcons[1] ~= false;
        local npc = options.npcFormat[1];
        if (not coin) then
            npc = npc:gsub('%[%s*vendor%s*%]', ''):gsub('%[%s*vendor%s*:[^%]]*%]', '');
        elseif (not format.Compile(npc).vendor) then
            npc = ('[vendor: space=%d]'):format(spacing) .. npc;
        end
        options.npcFormat[1] = npc;
        options.signFormatVersion = 1;
    end
    options.partyIcons, options.showVendorIcons = nil, nil;

    local was = options.showDistance;
    if (type(was) == 'table') then
        if (was[1]) then
            options.monsterFormat[1] = '[name] [distance]';
        end
        options.showDistance, options.distanceTargetOnly = nil, nil;
    end
    local castColour = false;
    for _, choice in ipairs(custom.CastTextColours) do castColour = castColour or choice.key == options.castTextColour[1]; end
    if (not castColour) then options.castTextColour[1] = settings.castTextColour()[1]; end
    if (type(options.castTextColor) ~= 'table') then options.castTextColor = settings.castTextColor(); end
    for i = 1, 3 do
        local n = options.castTextColor[i];
        options.castTextColor[i] = (type(n) == 'number' and n == n) and math.max(0, math.min(1, n)) or 1;
    end
    options.castTextColor[4] = 1;
    if not icons.ValidSource(options.playerIconSource[1]) then
        options.playerIconSource[1] = settings.playerIconSource()[1];
    end
    nameTypes.Settle(options);
    options.healthBarCategories = entityTypes.Settle(options.healthBarCategories);
    options.statusCategories = entityTypes.Settle(options.statusCategories);
    nameColours.Settle(options);
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

-- the game keeps the pearl's colour the other way about. A pearl's colour can be more than 0x80, which
-- the game draws brighter than the icon itself: doubled, it is given as it is for the plugin to double
-- as the game does; otherwise as the others are, where more than 0x80 is no brighter
local function pearlColor(color, doubled)
    local red, green, blue = bit.band(color, 0xFF), bit.band(bit.rshift(color, 8), 0xFF), bit.band(bit.rshift(color, 16), 0xFF);
    if (doubled) then
        return 0xFF000000 + red * 0x10000 + green * 0x100 + blue;
    end
    return 0xFF000000 + part(red) * 0x10000 + part(green) * 0x100 + part(blue);
end

local function darkColor()
    local dark = text.EdgeColor();
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

    -- The game gives the player's own name no text while they are their own target, sub target
    -- or confirm included: what was written for the character before is kept, its icons with it,
    -- and with nothing before the entity's name is written
    local empty = name.Text[0] == 0;
    if (empty and not known.fresh and known.id == name.ServerId and known.words ~= '') then
        return known;
    end

    ffi.copy(known.text, name.Text, TEXT_SIZE);
    known.fresh = false;
    known.id = name.ServerId;
    known.letterOf = nil; -- a renamed monster has no letter, or another's
    known.trackOf = nil;
    known.vendorOf = nil;
    local written = empty and ffi.string(name.Name) or ffi.string(name.Text);

    -- the icons lead; the name is what follows them, less the space between
    known.icons = {};
    local at = 1;
    while (at <= #written) do
        local byte = written:byte(at);
        if (byte < 0x8E) then
            break;
        end
        -- Keep encoded icons even while the bundled sheet is waiting for its texture.
        -- Place() is checked when drawing; unchanged names recover when loading succeeds.
        known.icons[#known.icons + 1] = byte;
        at = at + 1;
    end

    -- a character of the font that is not a letter cannot be written in this one
    known.words = written:sub(at):gsub('[%z\1-\31\127-\255]', ''):gsub('^ +', '');
    return known;
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
            diag.Note('Font %s not loaded: %s', file, tostring(made));
        end
    end
    return found or nil;
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
local glyphTexture = nil; -- imgui's unique id for the font's texture they are in
local frame = 0;
local smoothFont = false; -- the current frame's text mode; signs/badges use native glyphs

-- Every size's letters let go of, to be read again as they are asked for: the texture has been made
-- again or the letters moved in it, the font or the largest size has changed
local function forgetGlyphs()
    glyphSets = {};
end

local function readGlyph(baked, byte, raster)
    local glyph = baked:FindGlyph(byte);
    if (glyph == nil) then
        return false;
    end
    -- Pin bearings, advance and baseline to the native hinted font. Only the
    -- sampled mask comes from the larger raster: quality must not move the nameplate.
    local ink = raster and raster:FindGlyph(byte) or glyph;
    if ink == nil or ink.Visible == 0 or ink.Visible == false then ink = glyph; end
    return { glyph.X0, glyph.Y0, glyph.X1, glyph.Y1, ink.U0, ink.V0, ink.U1, ink.V1, glyph.AdvanceX,
        glyph.Visible ~= 0 and glyph.Visible ~= false, byte = byte };
end

-- Glyph runs belong to their set, so replacing a font/atlas also invalidates
-- all runs. Bound each cache: changing distances must not accumulate forever.
local function textRun(set, words)
    local stroke = set.syntheticBold and 1 or 0;
    if (set.runStroke ~= stroke) then
        set.runs, set.runCount, set.runStroke = nil, 0, stroke;
    end
    local runs = set.runs;
    if (runs == nil) then runs = {}; set.runs, set.runCount = runs, 0; end
    local run = runs[words];
    if (run ~= nil) then return run; end
    if (set.runCount >= 512) then runs = {}; set.runs, set.runCount = runs, 0; end
    run = { glyphs = {}, offsets = {}, width = 0, stroke = stroke };
    local glyphs = set.glyphs;
    for at = 1, #words do
        local byte = words:byte(at);
        local glyph = glyphs[byte];
        if (glyph == nil) then
            glyph = readGlyph(set.baked, byte, set.smoothBaked);
            glyphs[byte] = glyph;
        end
        if (glyph) then
            local index = #run.glyphs + 1;
            run.glyphs[index], run.offsets[index] = glyph, run.width;
            run.width = run.width + glyph[9] + (glyph[10] and stroke or 0);
        end
    end
    runs[words], set.runCount = run, set.runCount + 1;
    return run;
end

-- track, if given, is what is put between one letter and the next, in the picture's pixels
local function wordsWidth(set, words, fit, track)
    if (words == '') then return 0; end
    local run = textRun(set, words);
    return run.width * fit + (track and track * math.max(0, #run.glyphs - 1) or 0);
end

local function fadedColor(color, opacity)
    if (opacity == nil or opacity >= 1) then return color; end
    return color % 0x1000000 + math.floor(bit.rshift(color, 24) * math.max(0, opacity) + 0.5) * 0x1000000;
end

function letterBadges.Width(set, letter, fit)
    fit = fit * (set.badgeFit or 1);
    local badge = set.badges and set.badges[letter:upper()];
    return badge and (badge.width or badge.uv.w) * fit or wordsWidth(set.badgeFont or set, letter:upper(), fit * letterBadges.Scale);
end

function letterBadges.Write(set, letter, pen, top, fit, color)
    local textFit = fit;
    fit = fit * (set.badgeFit or 1);
    local badge = set.badges and set.badges[letter:upper()];
    if not badge then return nil end
    local uv = badge.uv;
    local width, height = badge.width or uv.w, badge.height or uv.h;
    local padding = (badge.padding or 0) * fit;
    -- Anchor the visible box, not its transparent filtering guard, to the name
    -- font's lowercase baseline. Layout/advance exclude that guard as well.
    local reference = textRun(set, 'x').glyphs[1];
    local y = reference and (top + reference[4] * textFit - height * fit)
        or (top + badge.top * fit);
    -- Use the same outline thickness, colour and distance fade as the nameplate.
    nameplates.Quad(pen - padding, y - padding, pen + width * fit + padding, y + height * fit + padding,
        uv.u0, uv.v0, uv.u1, uv.v1, color, letterBadges.Slot, true);
    return pen + width * fit;
end

local function writeWords(set, words, pen, top, fit, color, slot, opacity, track)
    if (words == '') then return pen; end
    track = track or 0;
    color = fadedColor(color, opacity);
    -- namehook already multiplies outline opacity by the glyph colour's alpha; Text Outline Opacity
    -- softens the text's edge alone (nil, the edge as it is)
    local run = textRun(set, words);
    local quad = nameplates.Quad;
    local edgeOpacity = fontPipeline.textEdgeOpacity;
    local masks = slot == nil and set.filtered or nil;
    slot = slot or set.textSlot or SLOT.Font;
    for index = 1, #run.glyphs do
        local glyph = run.glyphs[index];
        if (glyph[10]) then
            local at = pen + run.offsets[index] * fit + track * (index - 1);
            local x0, y0 = at + glyph[1] * fit, top + glyph[2] * fit;
            local x1, y1 = at + glyph[3] * fit, top + glyph[4] * fit;
            local mask = masks and masks[glyph.byte];
            local u0, v0, u1, v1, atSlot = glyph[5], glyph[6], glyph[7], glyph[8], slot;
            if mask then
                local uv = mask.uv;
                x0, y0 = x0 - mask.padX * fit, y0 - mask.padY * fit;
                x1, y1 = x1 + mask.padX * fit, y1 + mask.padY * fit;
                u0, v0, u1, v1, atSlot = uv.u0, uv.v0, uv.u1, uv.v1, SLOT.Font;
            end
            quad(x0, y0, x1, y1, u0, v0, u1, v1, color, atSlot, true, edgeOpacity);
            if (run.stroke > 0) then
                local shift = run.stroke * fit;
                quad(x0 + shift, y0, x1 + shift, y1, u0, v0, u1, v1, color, atSlot, true, edgeOpacity);
            end
        end
    end
    return pen + run.width * fit + track * math.max(0, #run.glyphs - 1);
end

-- the time left under a status's icon is written in the name's letters
-- Plain-letter fallback must share the badge's name-font baseline; otherwise
-- the letter jumps vertically when its prepared atlas becomes available.
local function writeLetterFallback(set, words, pen, top, fit, color)
    local font = set.badgeFont or set;
    local badgeFit = fit * (set.badgeFit or 1) * letterBadges.Scale;
    local run = textRun(font, words:upper());
    local reference = textRun(set, 'x').glyphs[1];
    local bottom;
    for _, glyph in ipairs(run.glyphs) do
        if (glyph[10]) then bottom = math.max(bottom or glyph[4], glyph[4]); end
    end
    if (reference ~= nil and bottom ~= nil) then top = top + reference[4] * fit - bottom * badgeFit; end
    return writeWords(font, words:upper(), pen, top, badgeFit, color, SLOT.Sign);
end

-- A sheet of signs from the assets folder, loaded the first time one of its signs is to be drawn:
-- its address for the plugin, or 0 if it would not load
local sheets = {};   -- file -> { texture = kept so that it is not let go, at = its address }

-- Apart from sheet, which is asked every frame: a function with another made inside it is one
-- LuaJIT will not compile, nor anything that calls it.
local function loadSheet(known, file)
    pcall(function ()
        local d3d = require('d3d8');
        local made = ffi.new('IDirect3DTexture8*[1]');
        if (ffi.C.D3DXCreateTextureFromFileA(d3d.get_device(), addon.path .. 'assets/' .. file, made) == ffi.C.S_OK) then
            known.texture = d3d.gc_safe_release(ffi.cast('IDirect3DTexture8*', made[0]));
            known.at = tonumber(ffi.cast('uint32_t', known.texture));
        end
    end);
end

local function sheet(file)
    local known = sheets[file];
    if (known == nil) then
        known = { at = 0, nextRetry = 0 };
        sheets[file] = known;
    end
    -- A device/file may not be ready at addon load. Do not cache that failure forever,
    -- or hammer Direct3D every frame; successful textures stay owned and cached.
    if (known.at == 0 and os.clock() >= (known.nextRetry or 0)) then
        known.nextRetry = os.clock() + 1;
        loadSheet(known, file);
    end
    return known.at;
end

local function sensesTexture()
    return sheet('senses.png');
end

-- The sheets' addresses given and not loaded: for the tests, which have no Direct3D
function custom.SetSheets(senses, tempers, hunt)
    sheets['senses.png'] = { at = senses };
    sheets['aggro.png'] = { at = tempers };
    if (hunt ~= nil) then sheets[special.Sheet] = { at = hunt }; end
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

local function linkWords(monster, besideIcon)
    if (monster.nameLink == nil) then
        local family = monster.Family or '';
        -- The copied tables expose detection senses, not separate link senses.
        -- Infer only from Sight/Sound, not TrueSight (which can accompany Sound).
        local sense = monster.Sight and (monster.Sound and 'Sight/Hearing' or 'Sight') or (monster.Sound and 'Hearing' or '');
        local label = family;
        if (sense ~= '') then
            label = family ~= '' and (family .. ' (' .. sense .. ')') or sense;
        end
        monster.nameLinkLabel = monster.Link and label or '';
        monster.nameLink = monster.Link and ((family ~= '' and ('Link: ' .. family) or 'Link') .. (sense ~= '' and (' (' .. sense .. ')') or '')) or '';
    end
    return besideIcon and monster.nameLinkLabel or monster.nameLink;
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
local function glyphSet(font, height, key, smooth)
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

    local raster;
    if smooth then
        imgui.PushFont(font, height * filteredText.SourceScale);
        raster = imgui.GetFontBaked();
        imgui.PopFont();
    end

    if (set == nil) then
        set = { glyphs = {} };
        glyphSets[key] = set;
    end

    local now = readGlyph(baked, PROBE, raster);
    local was = set.glyphs[PROBE];
    if (was and now and (was[5] ~= now[5] or was[6] ~= now[6] or was[7] ~= now[7] or was[8] ~= now[8])) then
        -- the letters have been moved: every size's are read again
        forgetGlyphs();
        set = { glyphs = {} };
        glyphSets[key] = set;
    end
    set.glyphs[PROBE] = now;
    set.baked, set.smoothBaked = baked, raster;
    set.checked = frame;

    imgui.PopFont();
    return set;
end

-- Per-entity appearance state: identity/frame, corpse grey, the target's steady colour and
-- opacity, and a short disappearance deadline.
local steady = {};

-- whether colour a is colour b gone toward white or toward dark, as the game's pulse takes a name:
-- each channel the same share of the way, give or take PULSE_SLACK
local function pulseOf(a, b)
    local ar, ag, ab = math.min(0x80, bit.rshift(a, 16)), math.min(0x80, bit.band(bit.rshift(a, 8), 0xFF)), math.min(0x80, bit.band(a, 0xFF));
    local br, bg, bb = math.min(0x80, bit.rshift(b, 16)), math.min(0x80, bit.band(bit.rshift(b, 8), 0xFF)), math.min(0x80, bit.band(b, 0xFF));
    for _, toward in ipairs({ 0, 0x80 }) do
        -- the share of the way, from the channel with furthest to go
        local far, near = br, ar;
        if (math.abs(toward - bg) > math.abs(toward - far)) then far, near = bg, ag; end
        if (math.abs(toward - bb) > math.abs(toward - far)) then far, near = bb, ab; end
        local share = far == toward and 0 or (near - far) / (toward - far);
        if (share >= -0.05 and share <= 1.05
                and math.abs(ar - (br + (toward - br) * share)) <= PULSE_SLACK
                and math.abs(ag - (bg + (toward - bg) * share)) <= PULSE_SLACK
                and math.abs(ab - (bb + (toward - bb) * share)) <= PULSE_SLACK) then
            return true;
        end
    end
    return false;
end

-- The game pulses the target's name, its colour brightening toward white and its opacity dipping;
-- the name is drawn steady instead, at its brightest opacity and the colour the pulse starts from. Corpses use
-- grey, never the last live claim colour, and always follow the client's current fade.
local function steadyColor(name, entities, now)
    local index = name.EntityIndex;
    local monster = name.Category == nameplates.Category.Monster and name.ServerId ~= 0;
    local id = monster and entities ~= nil and entities.GetServerId ~= nil and entities:GetServerId(index) or nil;
    local available = type(id) == 'number' and id >= 0 and id <= 0xFFFFFFFF and id == math.floor(id);
    local valid = available and id == name.ServerId;
    local flags = valid and entities.GetRenderFlags0 ~= nil and entities:GetRenderFlags0(index) or nil;
    local hasFlags = type(flags) == 'number' and flags >= 0 and flags <= 0xFFFFFFFF and flags == math.floor(flags);
    local gone = monster and available and (id == 0 or (hasFlags and bit.band(flags, SPAWNED) == 0));
    local replaced = monster and available and id ~= 0 and not valid;
    local dead = valid and entities.GetHPPercent ~= nil and entities:GetHPPercent(index) == 0;
    local known = steady[index];
    -- A disappearing corpse may lose its entity data before the final name calls.
    -- Keep its grey and fade deadline through those calls, including drawing gaps.
    if (known ~= nil and known.id == name.ServerId and gone and known.dead) then dead = true; end
    if (known ~= nil and (known.id ~= name.ServerId
            or (not gone and (known.frame ~= frame - 1 or (known.dead and not dead))))) then
        steady[index], known = nil, nil;
    end
    if (known == nil) then known = { id = name.ServerId }; steady[index] = known; end
    local fade = 1;
    if (gone) then
        known.goneAt = known.goneAt or now;
        fade = math.max(0, math.min(1, 1 - (now - known.goneAt) / DESPAWN_FADE));
    else
        known.goneAt = nil;
    end
    -- Never draw a stale label on a different entity that has reused the index.
    if (replaced) then fade = 0; end
    local color = name.NameColor;
    local opacity = bit.rshift(color, 24);
    local iconOpacity = opacity;
    if (dead) then
        local rgb = color % 0x1000000;
        local r, g, b = bit.rshift(rgb, 16), bit.band(bit.rshift(rgb, 8), 0xFF), bit.band(rgb, 0xFF);
        -- Prefer the client's corpse grey when available. A stale red/white claim
        -- sample must not keep a corpse red/white or overwrite an observed grey.
        if (r == g and g == b and r > 0 and r < 0x80) then known.corpse = rgb; end
        color = opacity * 0x1000000 + (known.corpse or 0x404040);
    elseif (bit.band(name.Flags, nameplates.Flag.Target) ~= 0) then
        -- Hold opacity, not a saturation-selected RGB sample. Do not expire it
        -- mid-target: a slow/low-FPS pulse must not make the icons blink again.
        known.alphaPeak = math.max(known.alphaPeak or opacity, opacity);
        iconOpacity = known.alphaPeak;
        -- The colour the pulse starts from is kept. A colour that is the kept one gone toward white
        -- or dark is the pulse; one the kept colour is a pulse of is truer, and taken; any other (a
        -- claim's) is taken at once.
        local rgb = color % 0x1000000;
        local base = known.base or known.plain or rgb;
        if (not pulseOf(rgb, base) and (pulseOf(base, rgb) or known.base ~= nil)) then
            base = rgb;
        end
        known.base = base;
        color = known.alphaPeak * 0x1000000 + known.base;
    else
        known.alphaPeak, known.base = nil, nil;
        known.plain = color % 0x1000000;
    end
    known.dead, known.frame = dead, frame;
    return color, dead, iconOpacity / 0x80, fade;
end

-- The game's size for a name, less its starts: as a character becomes the target the game gives its
-- name its full size for a frame, whatever distance it is at, and then the size it had. A name whose
-- size leaps between one frame and the next keeps the size it had until the new one has lasted; one
-- that changes as a walk changes it is followed at once. known is what is kept of the name's entity.
-- held, while the character is the sub target being chosen and for a little after: the game sizes
-- that name its own way as the choice begins and ends, and none of its leaps is believed then, only
-- the steps of a walk; Subtarget Scale is the one change of size it has.
local function steadySize(known, name, held, now)
    local size = math.max(0, math.min(1, name.Scale));

    if (held and known.sizeOf == name.ServerId) then
        if (math.abs(size - known.size) <= SIZE_JUMP) then
            known.size = size;
        end
        known.sizeRun = 0;
    elseif (known.sizeOf ~= name.ServerId or known.sizeSeen ~= frame - 1 or math.abs(size - known.size) <= SIZE_JUMP) then
        -- another character's, or one not listed last frame, or a step: as the game has it
        known.sizeOf, known.size, known.sizeRun = name.ServerId, size, 0;
    elseif (known.sizeRun > 0 and math.abs(size - known.sizeLeap) <= SIZE_JUMP) then
        known.sizeRun = known.sizeRun + 1;
        if (now - known.sizeLeapAt >= SIZE_HOLD) then
            known.size, known.sizeRun = size, 0;
        end
    else
        known.sizeLeap, known.sizeLeapAt, known.sizeRun = size, now, 1;
    end

    known.sizeSeen = frame;
    return known.size;
end

-- The rungs' heights, shared by every name, and made again only as the largest changes: with the
-- size setting, or the window's. The letters kept for the heights before are let go then, so that
-- dragging a window's edge does not leave a set behind for every height it passed through.
local cachedRungs;
function fontPipeline.Rungs(height)
    if (cachedRungs == nil or cachedRungs.height ~= height) then
        cachedRungs = { height = height, badge = 'badge:' .. height };
        for rung = 1, #RUNGS do
            cachedRungs[rung] = math.max(1, math.floor(height * RUNGS[rung] + 0.5));
        end
        forgetGlyphs();
    end
    return cachedRungs;
end

-- A name's letters at a rung's height: the set, with whether it is to be drawn bold
local function nameSet(font, height, bold)
    local set = glyphSet(font, height, smoothFont and ('smooth:' .. height) or height, smoothFont);
    if (set ~= nil) then
        set.syntheticBold = bold;
        if smoothFont then textRun(set, filteredText.Characters); end
    end
    return set;
end

function fontPipeline.DiscardIfDisabled(options, hook)
    if options.fontSmooth and options.fontSmooth[1] then return end
    if smoothFont then nameplates.ClearDrawing(hook); end
    filteredText.Release();
    if cachedRungs then cachedRungs.filteredDefinitions = nil; end
    if smoothFont then
        forgetGlyphs(); -- drop the cached high-resolution baked-font handles too
        smoothFont = false;
    end
end

-- Build only when immutable glyph sets change, not for each entity or frame.
function fontPipeline.Filtered(font, heights, bold, fontAddress)
    if not smoothFont then return nil end
    local definitions, rungs = heights.filteredDefinitions, #heights;
    local valid, complete = definitions ~= nil and #definitions == rungs, true;
    for rung = 1, rungs do
        local set = nameSet(font, heights[rung], bold);
        if set then
            set.filtered, set.textSlot = nil, nil;
            if not definitions or not definitions[rung] or definitions[rung].glyphs ~= set.glyphs then valid = false; end
        else
            complete = false;
        end
    end
    if not complete then return nil end
    if not valid then
        definitions = {};
        for rung = 1, rungs do
            definitions[rung] = { height = heights[rung], glyphs = nameSet(font, heights[rung], bold).glyphs };
        end
        heights.filteredDefinitions = definitions;
    end
    local ready = filteredText.Prepare(fontAddress, definitions);
    if ready then
        nameplates.SetTexture(SLOT.Font, ready.address);
        for rung = 1, rungs do
            local set = nameSet(font, heights[rung], bold);
            set.filtered, set.textSlot = ready.regions[heights[rung]], SLOT.Sign;
        end
    end
    return ready;
end

-- Under the name of a monster its player has checked, and with its middle under
-- the name's: how hard a fight the game said it would be; then, if the tables
-- have the monster and it is aggressive, what it notices its prey by; and if it
-- links, the sign for that and the family it links with. Whether it is aggressive
-- at all is not said here: [aggro] in the name's own line says it.
-- It comes as the monster is checked, is there a few seconds, and goes: how solid
-- it is, from how long ago that was.
--
-- Apart from the frame's function, which calls it for a checked monster's name after the name is
-- written: set is the letters the name was written in, sign the magnifying glass among them or
-- false, own the name's colour, fit, height, rungHeight and top as the name had them, scale the
-- pixels of the game's picture to one of the screen's.
-- Gives back the foot of the line, or nil when nothing of it is drawn
local function writeDetails(options, written, set, sign, own, fit, height, rungHeight, top, scale, now)
    local since = now - written.found.at;
    local showing = 0;
    if (since < DETAIL.In) then
        showing = since / DETAIL.In;
    elseif (since < DETAIL.In + DETAIL.Shown) then
        showing = 1;
    elseif (since < DETAIL.In + DETAIL.Shown + DETAIL.Out) then
        showing = 1 - (since - DETAIL.In - DETAIL.Shown) / DETAIL.Out;
    end
    if (showing <= 0) then
        return;
    end
    local detailsInWords = options.checkDetailsInWords[1];

    -- the colours of its parts, as solid as it now is
    local solidity = math.floor(showing * 255 + 0.5) * 0x1000000;
    local own = own % 0x1000000 + solidity;
    local WHITE = 0xFFFFFF + solidity;
    local detailScale = options.checkSize[1] / 100;
    local detail = fit * detailScale;
    local detailHeight = math.floor(height * detailScale + 0.5);
    local gap = math.floor(detailHeight * DETAIL.Gap + 0.5);
    local monster = written.monster;
    local sheet = (not detailsInWords and monster ~= nil) and sensesTexture() or 0;
    local signs = (monster ~= nil and sheet ~= 0) and signsOf(monster) or nil;
    local links = not detailsInWords and monster ~= nil and monster.Link;
    local linked = links and linkWords(monster, true) or '';
    local extra = (signs ~= nil and #signs > 0) or (links and sheet ~= 0) or linked ~= '';
    if (detailsInWords and monster ~= nil) then
        extra = noticeWords(monster) ~= '' or linkWords(monster) ~= '';
    end
    -- A lone difficulty is more useful spelled out. Keep ???
    -- compact even when no aggro/link information is available.
    local short = options.abbreviateDifficulty[1] and (extra or written.found.hardShort == '???');
    local hard = (short and written.found.hardShort or written.found.hard) or '';

    -- In words it is the one sentence, its parts with commas between them: "Too
    -- Weak, Sight Aggro, Link: Goblin". Put together once for each check.
    if (detailsInWords) then
        if (written.sentenceOf ~= written.found or written.sentenceFor ~= monster or written.sentenceHard ~= hard) then
            written.sentenceOf, written.sentenceFor, written.sentenceHard = written.found, monster, hard;
            local said = { hard ~= '' and hard or nil };
            if (monster ~= nil) then
                local notices, linked = noticeWords(monster), linkWords(monster);
                if (notices ~= '') then said[#said + 1] = notices; end
                if (linked ~= '') then said[#said + 1] = linked; end
            end
            written.sentence = table.concat(said, ', ');
        end
        hard = written.sentence;
    end

    -- what it notices its prey by, and what it links with: as signs, or in words
    local hardWidth = wordsWidth(set, hard, detail);
    local signsWidth = (signs ~= nil and #signs or 0) * detailHeight;
    local linkWidth = (links and sheet ~= 0) and detailHeight or 0;
    local linkedWidth = wordsWidth(set, linked, detail);

    local glassFit = detail * SIGN_SIZE;
    local glassWidth = not detailsInWords and sign and sign[9] * glassFit or 0;
    local across, pieces = glassWidth, glassWidth > 0 and 1 or 0;
    local linkAcross = linkWidth + linkedWidth + ((linkWidth > 0 and linkedWidth > 0) and math.floor(gap * 0.5) or 0);
    if (hardWidth > 0) then across, pieces = across + hardWidth, pieces + 1; end
    if (signsWidth > 0) then across, pieces = across + signsWidth, pieces + 1; end
    if (linkAcross > 0) then across, pieces = across + linkAcross, pieces + 1; end
    across = across + math.max(0, pieces - 1) * gap;

    local at = math.floor(-across * 0.5);
    local below = top + height + math.floor(DETAIL.Below * scale + 0.5);
    local bottom = below + detailHeight;

    if (glassWidth > 0) then
        local middle = rungHeight * 0.5;
        local glassTop = below + middle * detail;
        icons.Quad(at + sign[1] * glassFit, glassTop + (sign[2] - middle) * glassFit,
            at + sign[3] * glassFit, glassTop + (sign[4] - middle) * glassFit,
            sign[5], sign[6], sign[7], sign[8], WHITE, SLOT.Sign);
        at = at + glassWidth + gap;
    end
    if (hardWidth > 0) then
        at = writeWords(set, hard, at, below, detail, own) + gap;
    end
    if (signsWidth > 0) then
        for index = 1, (signs ~= nil and #signs or 0) do
            local sign = signs[index];
            local u, v = (sign % 4) * 0.25, math.floor(sign / 4) * 0.25;
            icons.Quad(at, below, at + detailHeight, below + detailHeight, u, v, u + 0.25, v + 0.25, WHITE, SLOT.Sense);
            at = at + detailHeight;
        end
        at = at + gap;
    end
    if (linkWidth > 0) then
        local u, v = (SENSES.Link % 4) * 0.25, math.floor(SENSES.Link / 4) * 0.25;
        icons.Quad(at, below, at + detailHeight, below + detailHeight, u, v, u + 0.25, v + 0.25, WHITE, SLOT.Sense);
        at = at + linkWidth + (linkedWidth > 0 and math.floor(gap * 0.5) or 0);
    end
    if (linkedWidth > 0) then
        writeWords(set, linked, at, below, detail, own);
    end
    return bottom;
end

-- The entity manager as the names ask it, each answer read once a frame for each entity: the steady
-- colour, the colour overrides, the health bar and Combat Only each ask after the same name's id, HP,
-- status and claim, and the game is asked once. It answers with the manager's own methods, those the
-- manager has, and none it has not.
local NONE = {}; -- an answer of nil, kept apart from one not yet asked for
local answers = {}; -- entity index -> { frame, and the answers of that frame }
local MIRRORED = { GetServerId = 'id', GetHPPercent = 'hp', GetRenderFlags0 = 'flags', GetStatus = 'status',
    GetClaimStatus = 'claim', GetDistance = 'distance' };
local asked = { real = nil };

local function answering(method, field)
    return function (self, index)
        local kept = answers[index];
        if (kept == nil) then
            kept = {};
            answers[index] = kept;
        end
        if (kept.frame ~= frame) then
            kept.frame = frame;
            kept.id, kept.hp, kept.flags, kept.status, kept.claim, kept.distance = nil, nil, nil, nil, nil, nil;
        end
        local value = kept[field];
        if (value == nil) then
            local real = self.real;
            value = real[method](real, index);
            kept[field] = value == nil and NONE or value;
            return value;
        end
        if (value == NONE) then
            return nil;
        end
        return value;
    end
end

local answerers = {};
for method, field in pairs(MIRRORED) do
    answerers[method] = answering(method, field);
end

-- The manager's answers for this frame: nil where there is no manager
local function askedOnce(real)
    if (real == nil) then
        return nil;
    end
    asked.real = real;
    for method, answer in pairs(answerers) do
        asked[method] = real[method] ~= nil and answer or nil;
    end
    return asked;
end

-- What a part of a line writes: the name (or Placeholder), the distance, the level (the exact one if
-- asked for), the letter (the double one if asked for), or its own text
local function partWords(part, kind, written, nameWords, letter)
    return kind == 'name' and nameWords
        or (kind == 'distance' and inline.Distance(part, written))
        or (kind == 'level' and (part.exact and written.exactLevel or written.level or ''))
        or (kind == 'letter' and (part.type == 'double' and written.doubleLetter or letter))
        or part.text or '';
end

-- And its colour: a state override's, a corpse's grey, the part's own, or the name's
local function partColor(part, kind, override, dead, own)
    return kind == 'name' and (override or (dead and own) or part.color or own) or part.color or own;
end

-- Idempotent: settings/profile changes, plugin loss and Enable Name off all
-- reach this path, even when Frame will no longer be called. ImGui owns fonts.
function custom.Deactivate()
    fontPipeline.Castbar.Reset();
    if not fontPipeline.active then return end
    fontPipeline.active = false;
    nameplates.ClearDrawing();
    fontPipeline.Readability.Reset();
    filteredText.Release();
    letterBadges.Release();
    icons.Release();
    local atlas = require('gdi.atlas');
    for _, known in pairs(sheets) do
        if known.texture then
            local texture = known.texture;
            known.texture, known.at, known.nextRetry = nil, 0, 0;
            atlas.release(texture);
        end
    end
    forgetGlyphs();
    cachedRungs, smoothFont = nil, false;
    parsed, steady, answers = {}, {}, {};
end

function custom.ResetReadability() fontPipeline.Readability.Reset(); end
-- Queried only on demand; no addresses, names, paths or user-entered formats.
function custom.Diagnostics()
    return {
        { 'Filtered font', filteredText.Diagnostics() },
        { 'Letter badge atlas', letterBadges.Diagnostics() },
        { 'Player artwork', icons.Diagnostics() },
        { 'Crowd policy', fontPipeline.Readability.Diagnostics() },
        { 'Cast bars', fontPipeline.Castbar.Diagnostics() },
    };
end

-- Both rows use the same geometry. Cast labels and timer are below the bar;
-- include their foot in the layout so below-name statuses cannot overlap them.
function fontPipeline.CastCaption(set, words, left, right, under, fit, nominal, gap, opacity, color)
    local low, high = 0, nominal;
    for _, glyph in ipairs(textRun(set, words).glyphs) do
        if glyph[10] then
            local mask = set.filtered and set.filtered[glyph.byte];
            local pad = mask and mask.padY or 0;
            low, high = math.min(low, (glyph[2] - pad) * fit), math.max(high, (glyph[4] + pad) * fit);
        end
    end
    local top = math.ceil(under + gap - low);
    writeWords(set, words, math.floor((left + right - wordsWidth(set, words, fit)) * 0.5),
        top, fit, color or WHITE, nil, opacity);
    return math.ceil(top + high);
end
-- Weaponskills and TP moves can be words alone (castBarSkillTextOnly), written where the bar would be.
function fontPipeline.WriteCast(entry, set, left, right, under, scale, fit, height, width, barHeight, opacity, options, color)
    local bottom = under;
    if not (entry.kind == 'skill' and options.castBarSkillTextOnly[1]) then
        bottom = healthbar.Bar(left, right, under, scale, entry.progress,
            fadedColor(color, opacity), width, barHeight, 0xFF203048);
        if bottom == under then return under; end
    end
    local showName, showTimer = options.castShowName[1], options.castShowTimer[1];
    if not (showName or showTimer) then return bottom; end
    local mode, textColor = options.castTextColour[1], WHITE;
    if (mode == 'name') then textColor = color;
    elseif (mode == 'custom') then
        local c = options.castTextColor;
        textColor = 0xFF000000 + math.floor(c[1] * 255 + 0.5) * 0x10000 + math.floor(c[2] * 255 + 0.5) * 0x100 + math.floor(c[3] * 255 + 0.5);
    end
    local nameScale, timerScale = options.castNameScale[1] / 100, options.castTimerScale[1] / 100;
    if showName then
        bottom = fontPipeline.CastCaption(set, entry.name, left, right, bottom, fit * nameScale,
            math.max(1, math.ceil(height * nameScale)),
            math.max(1, math.floor(2 * scale + 0.5)), opacity, textColor);
    end
    if showTimer then
        bottom = fontPipeline.CastCaption(set, entry.timer, left, right, bottom, fit * timerScale,
            math.max(1, math.ceil(height * timerScale)),
            math.max(1, math.floor((showName and 1 or 2) * scale + 0.5)), opacity, textColor);
    end
    return bottom + math.max(1, math.floor(scale + 0.5));
end

function custom.Frame(options, hook, formats)
    fontPipeline.active = true;
    formats = formats or options; -- optional format overrides for rendering fixtures
    fontPipeline.DiscardIfDisabled(options, hook);
    fontPipeline.Castbar.Configure(options); -- disable cleanup also runs before font/draw early returns
    local FONT_SLOT, ICON_SLOT, SENSE_SLOT, TEMPER_SLOT, SIGN_SLOT = SLOT.Font, SLOT.Icon, SLOT.Sense, SLOT.Temper, SLOT.Sign;
    -- without the plugin's list there is nothing to draw from, and the game draws the names
    if (hook == nil or hook.Hooked == 0) then
        return 'unhooked';
    end

    -- the font's texture: the plugin is given winxi's mark for it and reads it itself as it draws.
    -- None while imgui has none ready. Which texture it is (imgui's unique id, new each time imgui
    -- makes it again) says when the letters' places in it may have changed.
    local texture, which = winxiFonts.Texture();
    if (texture == nil) then
        return 'texture', which;
    end
    if (which ~= glyphTexture or options.font ~= glyphFont) then
        if (which ~= glyphTexture) then
            diag.Note('Font texture %s (was %s)', tostring(which), tostring(glyphTexture));
        end
        glyphTexture, glyphFont = which, options.font;
        forgetGlyphs();
    end

    -- how many pixels of the game's picture there are to one of the screen's: the names are set out
    -- in the game's, at the size that makes them the size asked for on the screen
    local scale = nameplates.BeginDrawing(hook, true);
    if (scale == nil) then
        return 'draw';
    end

    -- every frame: the game draws none of the names while this does
    nameplates.Claim(nameplates.Category.All, hook);

    local monsterFormat = format.Compile(options.monsterFormat[1]);
    local nameFormat = format.Compile(formats.nameFormat[1]);
    local npcFormat = format.Compile(formats.npcFormat and formats.npcFormat[1] or options.npcFormat and options.npcFormat[1] or '[name]');
    local wantsIcons = nameFormat.icons or monsterFormat.icons or npcFormat.icons or false;
    nameplates.SetTexture(ICON_SLOT, 0); -- unpublish an old DAT pointer before a source switch releases it
    icons.Begin(sheet, options.playerIconSource and options.playerIconSource[1], wantsIcons or options.showStars[1]);
    local iconTexture = icons.Texture() or 0;
    nameplates.SetTexture(FONT_SLOT, texture);
    nameplates.SetTexture(ICON_SLOT, iconTexture);
    nameplates.SetTexture(SENSE_SLOT, sheets['senses.png'] and sheets['senses.png'].at or 0);
    nameplates.SetTexture(TEMPER_SLOT, sheets['aggro.png'] and sheets['aggro.png'].at or 0);
    local trackedName = options.trackedNm ~= nil and options.trackedNm[1] or '';
    local labelPlaceholders = options.labelPlaceholders ~= nil and options.labelPlaceholders[1];
    local coins = vendors.Begin(npcFormat.vendor);
    local ranks = roles.Begin(AshitaCore:GetMemoryManager(), nameFormat.party or monsterFormat.party or npcFormat.party);
    local huntTexture = (trackedName ~= '' or coins or ranks) and sheet(special.Sheet) or 0;
    coins, ranks = coins and huntTexture ~= 0, ranks and huntTexture ~= 0;
    local huntScale = options.huntScale ~= nil and math.max(100, math.min(200, options.huntScale[1])) / 100 or 1;
    nameplates.SetTexture(special.Slot, huntTexture);
    -- the character under the sub-target cursor while one is being chosen. It is the first of the game's two targets either way: with a
    -- target already, that moves to the second and IsSubTargetActive is set; with none, nothing
    -- moves and only the sub-target flags (the kinds that may be chosen, all set when none is
    -- being chosen) say a choice is being made
    local subtargetScale = options.subtargetScale ~= nil and math.max(50, math.min(200, options.subtargetScale[1])) / 100 or 1;
    local subtarget = 0;
    -- the plugin doubles a pearl's colour as the game does
    local pearlDoubled = nameplates.Supports(nameplates.Feature.Doubled, hook);
    local letterSpacing = options.letterSpacing ~= nil and math.max(0, math.min(10, tonumber(options.letterSpacing[1]) or 0)) or 0;
    local target = AshitaCore:GetMemoryManager():GetTarget();
    if (target ~= nil and (target:GetIsSubTargetActive() == 1 or target:GetSubTargetFlags() ~= SUBTARGET_NONE)) then
        subtarget = target:GetTargetIndex(0);
    end
    -- the statuses its player has chosen to see over a name: read once, here, for all of them
    local statusRows = statuses.Begin(options);

    frame = frame + 1;

    local font = getFont(options.font);
    local badgeFont = monsterFormat.letter and getFont(letterBadges.Font) or nil;
    levels.DoubleLetters(monsterFormat.doubleLetters == true);
    local fullSize, leastSize = nameTypes.Bounds(options);

    -- A name is not given letters of exactly its own size. imgui makes the letters of a size the
    -- first time they are asked for, and makes room for them in its texture by moving the others
    -- about: with names of every size from the smallest to the largest coming and going as the
    -- player moves, that was done over and over, and for a frame each time the names were drawn from
    -- where their letters no longer were. So letters are kept at a few sizes only, the rungs, and a
    -- name is drawn from the smallest of them that is no smaller than it, scaled down to fit. Every
    -- rung is asked after every frame, in use or not, which keeps imgui from letting it go; and all
    -- of them before any name is set out, so that if the letters have been moved it is known first.
    local fullHeight = math.max(1, math.floor(fullSize * scale + 0.5));
    local heights = fontPipeline.Rungs(fullHeight);
    local rungs = #heights;
    local bold = options.fontBold[1];
    smoothFont = options.fontSmooth ~= nil and options.fontSmooth[1] == true;
    local textOutline = options.textOutlineOpacity ~= nil and tonumber(options.textOutlineOpacity[1]) or 100;
    fontPipeline.textEdgeOpacity = textOutline < 100 and math.max(0, textOutline) / 100 or nil;
    nameplates.SetTexture(SIGN_SLOT, texture);

    -- the magnifying glass is in the font everything else is written in: with a font of the player's
    -- choosing for the names, that one's letters are kept as well, for it
    nameplates.SetTexture(letterBadges.Slot, 0); -- before any badge release/replacement
    if not monsterFormat.letter then
        letterBadges.Release();
        glyphSets[heights.badge] = nil;
    end
    -- the sheet of aggro signs, asked for once a frame and only if some line draws from it
    local temperSheet = monsterFormat.aggro and sheet('aggro.png') or 0;
    -- One editable format for every mob, regardless of target/check state.
    -- Legacy targetFormat/checkedFormat settings are removed by Settle.
    local wantsSign = options.showCheckDetails[1] and not options.checkDetailsInWords[1]
        or (not options.showCheckDetails[1] and (nameFormat.checked or monsterFormat.checked or npcFormat.checked));
    local signsApart = font ~= nil and wantsSign;
    for _ = 1, 2 do
        local sets = glyphSets;
        if (monsterFormat.letter) then
            local indicator = glyphSet(badgeFont, fullHeight, heights.badge);
            if (indicator ~= nil) then
                indicator.syntheticBold = false; -- Arial Bold is already natively bold
                textRun(indicator, 'ABCDEFGHIJKLMNOPQRSTUVWXYZ');
            end
        end
        for rung = 1, rungs do
            local rungHeight = heights[rung];
            nameSet(font, rungHeight, bold);
            if (signsApart) then
                glyphSet(nil, rungHeight, -rungHeight);
            end
        end
        -- moved while they were being looked at: once more, and they are all as they now are
        if (sets == glyphSets) then
            break;
        end
    end
    -- One close-up master for every distance: never switch the indicator to a
    -- separately hinted/rasterized smaller glyph when the name changes rung.
    local badgeDefinitions;
    local indicator = monsterFormat.letter and glyphSet(badgeFont, fullHeight, heights.badge) or nil;
    if indicator ~= nil then
        -- A set is replaced whenever its font/texture/UVs change. Keep immutable
        -- definitions on that set, rather than rereading A-Z and allocating per frame.
        -- The double letters wanted change with the area and the setting: then they are made again.
        local doubles = levels.LetterPairs();
        if indicator.badgeDefinitions == nil or indicator.badgeDefinitions[1].pairs ~= doubles then
            local glyphs = {};
            for byte = 65, 90 do
                glyphs[string.char(byte)] = indicator.glyphs[byte] or readGlyph(indicator.baked, byte);
            end
            indicator.badgeDefinitions = { { height = fullHeight, glyphs = glyphs, bold = false, pairs = doubles } };
        end
        badgeDefinitions = indicator.badgeDefinitions;
    end
    for rung = 1, rungs do
        local set = nameSet(font, heights[rung], bold);
        if set ~= nil then
            set.badges, set.badgeFont = nil, indicator;
            set.badgeFit = indicator ~= nil and heights[rung] / fullHeight or 1;
        end
    end
    -- the badges are cut from the font's texture as Direct3D has it, which only the plugin can read
    -- (texture is winxi's mark for it): the one it drew from, which it holds while it draws, or 0
    -- until it has
    local fontAddress = tonumber(hook.FontTexture) or 0;
    local badgeAtlas = badgeDefinitions ~= nil and fontAddress ~= 0 and letterBadges.Prepare(
        fontAddress, badgeDefinitions, letterBadges.Font, true) or nil;
    nameplates.SetTexture(letterBadges.Slot, badgeAtlas and badgeAtlas.address or 0);
    if badgeAtlas then
        for rung = 1, rungs do
            local set = nameSet(font, heights[rung], bold);
            if set then set.badges = badgeAtlas.regions[fullHeight]; end
        end
    end
    local filteredAtlas = fontPipeline.Filtered(font, heights, bold, fontAddress);
    local edge = math.max(0, math.min(4, options.outline[1]));
    local showStars = options.showStars[1];
    local showDetails = options.showCheckDetails[1];
    local detailsInWords = options.checkDetailsInWords[1];
    local now = os.clock();
    fontPipeline.Readability.Begin(options, hook, now);
    fontPipeline.Castbar.Begin(options, now);
    local iconScale = options.iconSize[1] / 100;
    local dark = darkColor();

    local WANTED, STARS, TARGET = nameplates.Flag.Wanted, nameplates.Flag.Stars, nameplates.Flag.Target;

    -- The entity manager supplies monster death state; distance is read only when a format needs it.
    local MONSTER = nameplates.Category.Monster;
    local memory = AshitaCore:GetMemoryManager();
    local entities = askedOnce(memory.GetEntity ~= nil and memory:GetEntity() or nil);
    local colourContext = nameColours.Context(options, memory);
    healthbar.Begin(filteredAtlas and filteredAtlas.white);

    -- a monster that was checked and has died is forgotten before any level is written; what is
    -- written of a level is kept until what is known of levels changes
    levels.Tidy();
    local levelsAt = levels.Generation();

    -- each entity is listed once: the plugin takes one of the times the game draws a name in a frame
    for i = 0, hook.Count - 1 do
        local name = hook.Names[i];

        if (bit.band(name.Flags, WANTED) ~= 0) then
            local maximumSize, minimumSize = fullSize, leastSize;
            local written = parse(name);
            written.role = ranks and roles.Of(name.ServerId) or nil;
            local iconCount = #written.icons + (written.role and 1 or 0);

            -- The game draws a name at one size out to a distance, then smaller and smaller until at
            -- its furthest it is nothing: Scale is 1 and then falls to 0. Here it shrinks over the
            -- same distance, from its largest to its smallest rather than to nothing,
            -- and fades out over the last of it.
            local isSubtarget = subtarget ~= 0 and name.EntityIndex == subtarget;
            if (isSubtarget) then written.subUntil = now + SUB_SETTLE; end
            local nearness = steadySize(written, name, written.subUntil ~= nil and now <= written.subUntil, now);
            local size = minimumSize + (maximumSize - minimumSize) * nearness;

            -- whether it is the notorious monster being hunted, or one of its placeholders: looked
            -- for once for each character there is, as its letter is. The hunted one's name can be
            -- larger than the rest, at every distance.
            local hunted, lot, nameWords = false, false, written.words;
            if (trackedName ~= '' and name.Category == MONSTER) then
                if (written.trackOf ~= name.ServerId or written.trackAt ~= levelsAt or written.trackFor ~= trackedName) then
                    written.trackOf, written.trackAt, written.trackFor = name.ServerId, levelsAt, trackedName;
                    local lots = levels.Placeholders(trackedName);
                    written.hunted = ffi.string(name.Name) == trackedName;
                    written.placeholder = not written.hunted and lots ~= nil and lots[name.EntityIndex] == true;
                end
                hunted, lot = written.hunted, written.placeholder;
                if (lot and labelPlaceholders) then
                    nameWords = HUNT.Placeholder;
                end
                if (hunted) then
                    size = size * huntScale;
                end
            end
            if (isSubtarget) then
                size = size * subtargetScale;
            end
            local displayColor, dead, solid, despawn = steadyColor(name, entities, now);
            written.cast = fontPipeline.Castbar.Of(name, entities, now, dead);
            written.simplified = fontPipeline.Readability.Simplify(name, isSubtarget, hunted or lot or written.cast ~= nil);
            local near = nearness / FADE_SHRUNK;
            local alpha = math.max(0, math.min(1, solid, near)) * despawn;
            -- Glyph fill and outline take the name's opacity (the target's held steady), not shared opacity.
            local textAlpha = math.max(0, math.min(1, bit.rshift(displayColor, 24) / 0x80, near)) * despawn;
            local textOpacity = alpha > 0 and math.min(1, textAlpha / alpha) or 0;

            if (alpha > 0 and (written.words ~= '' or iconCount > 0)) then
                -- its height in the game's picture, the rung its letters are taken from, and how much
                -- smaller than the rung it is: at the largest size it is the rung itself, letter for letter
                local height = size == fullSize and fullHeight or math.max(1, size * scale);
                local rungHeight = fullHeight;
                for rung = 2, rungs do
                    local smaller = heights[rung];
                    if (smaller < height) then
                        break;
                    end
                    rungHeight = smaller;
                end
                -- an enlarged name is the largest rung's letters drawn larger: there are none of its own size
                local fit = size > fullSize and height / rungHeight or math.min(1, height / rungHeight);
                local set = nameSet(font, rungHeight, bold);

                -- Round the base edge down to whole render-target pixels so
                -- resolution scaling does not make nearby names unnecessarily bold.
                -- Shrink the integer edge with the letters, still without fractional
                -- offsets or a thickness jump as soon as shrinking starts.
                local outlineFit = size / maximumSize;
                local nameEdge = edge > 0 and math.max(1, math.floor(math.min(edge, math.max(1, math.floor(size / 8 + 0.5))) * scale)) or 0;
                local nameDark = dark;
                if (outlineFit < 1) then
                    if nameEdge > 0 then nameEdge = math.max(1, math.floor(nameEdge * outlineFit + 0.5)); end
                    -- Keep small names separated from bright scenery: only soften
                    -- the halo slightly, rather than losing half its contrast.
                    local edgeAlpha = math.floor(bit.rshift(dark, 24) * (0.85 + 0.15 * outlineFit) + 0.5);
                    nameDark = dark % 0x1000000 + edgeAlpha * 0x1000000;
                end
                icons.ConfigureOutline(options, size, scale, outlineFit);
                if (set ~= nil and nameplates.BeginName(name.EntityIndex, alpha, nameEdge, nameDark)) then
                    -- what is written, part by part, as its line has it
                    local parts = nameFormat;
                    if (name.Category == MONSTER) then
                        parts = monsterFormat;
                    elseif (name.Category == nameplates.Category.Npc) then
                        parts = npcFormat;
                    end

                    if written.simplified then parts = fontPipeline.Readability.Compact(parts); end
                    written.iconsReplaced = written.role ~= nil and parts.partyReplace;
                    -- a vendor's coin, where [vendor] is, as large as the icons
                    local coin = parts.vendor and coins and name.Category == nameplates.Category.Npc
                        and vendors.Of(written, name) and special.Vendor or nil;
                    local showDetails = showDetails and not written.simplified;

                    -- its level if its player has checked it, or the levels it can be: looked for once
                    -- for each character there is, and again when what is known of levels changes
                    if ((parts.level or parts.checked or parts.aggro or parts.rules or (showDetails and name.Category == MONSTER))
                            and (written.levelOf ~= name.ServerId or written.levelAt ~= levelsAt)) then
                        written.levelOf, written.levelAt = name.ServerId, levelsAt;
                        local plain = ffi.string(name.Name);
                        written.level = levels.Of(name.EntityIndex, plain, name.ServerId) or '';
                        written.found = levels.Checked(name.EntityIndex, name.ServerId);
                        written.isChecked = written.found ~= nil;
                        written.exactLevel = written.found ~= nil and written.found.text or ''; -- impossible to gauge: none
                        written.monster = levels.Monster(name.EntityIndex, plain);
                    end
                    -- how far off it is, to a tenth: written afresh only as that changes
                    written.ruleTarget = bit.band(name.Flags, TARGET) ~= 0;
                    written.ruleChecked = written.isChecked == true;
                    -- a monster in combat, as Combat Only health bars have it, for [level: nocombat]
                    written.ruleCombat = parts.ruleCombat and name.Category == MONSTER and entities ~= nil
                        and nameColours.InCombat(name, entities) or false;
                    written.ruleDistance, written.distanceValue = nil, nil;
                    if ((parts.distance or parts.ruleDistance) and entities ~= nil) then
                        -- the game keeps the distance squared
                        local squared = entities:GetDistance(name.EntityIndex);
                        if (type(squared) == 'number' and squared >= 0 and squared < math.huge) then
                            written.distanceValue = math.sqrt(squared);
                            written.ruleDistance = written.distanceValue;
                            local tenths = math.floor(written.distanceValue * 10 + 0.5);
                            if (written.tenths ~= tenths) then
                                written.tenths = tenths;
                                written.far = ('%.1f'):format(tenths / 10);
                            end
                        end
                    end

                    if written.distanceValue == nil then written.far, written.tenths = '', nil; end
                    written.distanceColor = parts.distance and fontPipeline.Readability.Distance(options, written, name.ServerId) or nil;

                    -- the magnifying glass for one that has been checked, if the font has it
                    local sign = false;
                    if (((parts.checked and not showDetails) or (showDetails and not detailsInWords)) and written.isChecked) then
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
                    local temper, temperSize = nil, math.floor(height * TEMPER_SIZE + 0.5);
                    if (parts.aggro and written.monster ~= nil and name.Category == MONSTER and temperSheet ~= 0) then
                        temper = temperOf(written.monster, written.found);
                    end
                    -- the hunted one and its placeholders have the hunt sign there, whether the tables have them or not
                    local huntSign = (hunted or lot) and parts.aggro and huntTexture ~= 0;
                    if (huntSign) then
                        temper = 0;
                    end

                    -- its letter, looked for once for each character there is, and again when its
                    -- name is written another way or the area's tables change
                    local letter = '';
                    if (parts.letter and name.Category == MONSTER) then
                        if (written.letterOf ~= name.ServerId or written.letterAt ~= levelsAt) then
                            written.letterOf, written.letterAt = name.ServerId, levelsAt;
                            written.letter = levels.Letter(name.EntityIndex, ffi.string(name.Name), name.ServerId, false);
                            written.doubleLetter = levels.Letter(name.EntityIndex, ffi.string(name.Name), name.ServerId, true);
                        end
                        letter = written.letter;
                    end
                    height = math.floor(height + 0.5);
                    -- the space between letters is the setting's, or the token's spacing=, in screen pixels at
                    -- the name's largest: in the picture's pixels, and shrinking with the name
                    local spacingAt = scale * height / fullHeight;
                    local track = letterSpacing * spacingAt;
                    local override = nameColours.Resolve(options, name, entities, colourContext, dead, written.icons);
                    local own = override or nameColor(displayColor);
                    local nameTint = own;
                    local width, iconsHeight = 0, 0;
                    written.barNameLeft, written.barNameRight = nil, nil;
                    for index = 1, #parts do
                        local part = parts[index];
                        if (not parts.rules or rules.Visible(part, written)) then
                            local kind = part.kind;
                            local start = width;
                            if (kind == 'icons') then
                                local tokenWidth, tokenHeight = inline.IconWidth(part, written, height, scale, options.iconSize[1], options.iconSpacing[1]);
                                width = width + tokenWidth;
                                iconsHeight = math.max(iconsHeight, tokenHeight);
                            end
                            if (kind == 'party' or kind == 'vendor') then
                                local sign = kind == 'party' and written.role or coin;
                                local tokenWidth, tokenHeight = inline.SignWidth(part, sign, height, scale, options.iconSize[1], options.iconSpacing[1]);
                                width = width + tokenWidth;
                                iconsHeight = math.max(iconsHeight, tokenHeight);
                            end
                            if (kind == 'aggro' and temper ~= nil) then
                                width = width + (part.size and math.floor(height * part.size / 100 + 0.5) or temperSize);
                            end
                            if (kind == 'checked' and not showDetails) then
                                width = width + (sign and sign[9] * fit * (part.size and part.size / 100 or SIGN_SIZE) or 0);
                            end
                            local words = partWords(part, kind, written, nameWords, letter);
                            if (kind == 'name' and words ~= '') then nameTint = partColor(part, kind, override, dead, own); end
                            width = width + (kind == 'letter' and letterBadges.Width(set, words, fit)
                                or wordsWidth(set, words, fit, part.spacing and part.spacing * spacingAt or track));
                            if (kind == 'name' or kind == 'letter') and words ~= '' and width > start then
                                written.barNameLeft = math.min(written.barNameLeft or start, start);
                                written.barNameRight = math.max(written.barNameRight or width, width);
                            end
                            if (kind ~= 'icons' and kind ~= 'party' and kind ~= 'vendor' and width > start) then
                                width = width + math.floor((part.space or 0) * scale + 0.5);
                            end
                        end
                    end

                    -- A zero-count custom draw falls back to the client's name. Keep a harmless
                    -- transparent marker when conditions intentionally hide the whole inline run.
                    if (parts.rules and width == 0) then
                        nameplates.Quad(0, 0, 0, 0, 0, 0, 0, 0, 0, FONT_SLOT, false);
                    end
                    local iconSize = math.floor(height * iconScale + 0.5);
                    local smallStar = math.floor(iconSize * 0.5 + 0.5);

                    -- Centre the whole formatted run, including icons wherever the token places them.
                    local left = math.floor(-width * 0.5);
                    local nameLeft = left;
                    local top = 0;
                    local iconTop = math.floor((height - iconSize) * 0.5);

                    -- the stars over the middle of it: a small one, a large one, a small one
                    local star = not written.simplified and showStars and bit.band(name.Flags, STARS) ~= 0 and icons.Place(STAR);
                    local clear = math.min(top, math.floor((height - iconsHeight) * 0.5));
                    if (star) then
                        local starsLeft = math.floor(-(smallStar * 2 + iconSize) * 0.5);
                        local starsTop = math.min(clear, iconTop) - iconSize - 1;
                        clear = starsTop;
                        local smallTop = starsTop + math.floor((iconSize - smallStar) * 0.5);
                        nameplates.Quad(starsLeft, smallTop, starsLeft + smallStar, smallTop + smallStar, star[1], star[2], star[3], star[4], WHITE, ICON_SLOT, false);
                        nameplates.Quad(starsLeft + smallStar, starsTop, starsLeft + smallStar + iconSize, starsTop + iconSize, star[1], star[2], star[3], star[4], WHITE, ICON_SLOT, false);
                        nameplates.Quad(starsLeft + smallStar + iconSize, smallTop, starsLeft + smallStar * 2 + iconSize, smallTop + smallStar, star[1], star[2], star[3], star[4], WHITE, ICON_SLOT, false);
                    end

                    local fill = nameTint;
                    local pen = left;
                    for index = 1, #parts do
                        local part = parts[index];
                        if (not parts.rules or rules.Visible(part, written)) then
                            local kind = part.kind;
                            local start = pen;
                            local words = partWords(part, kind, written, nameWords, letter);
                            local color = (kind == 'distance' and not part.color and written.distanceColor)
                                or partColor(part, kind, override, dead, own);
                            if (kind == 'name') then fill = color; end
                            if (kind == 'icons') then
                                pen = pen + inline.WriteIcons(part, written, pen, top, height, scale,
                                    options.iconSize[1], options.iconSpacing[1], pearlColor(name.IconColor, pearlDoubled), pearlDoubled);
                            end
                            if (kind == 'party' or kind == 'vendor') then
                                pen = pen + inline.WriteSign(part, kind == 'party' and written.role or coin, pen, top, height, scale,
                                    options.iconSize[1], options.iconSpacing[1]);
                            end
                            if (kind == 'aggro' and temper ~= nil) then
                                local u, v = (temper % 4) * 0.25, math.floor(temper / 4) * 0.25;
                                -- a little larger than the letters, or as the token's size= has it, its middle
                                -- level with theirs, and with the dark edge they have
                                local temperSize = part.size and math.floor(height * part.size / 100 + 0.5) or temperSize;
                                local temperTop = top + math.floor((height - temperSize) * 0.5);
                                if (huntSign) then
                                    local u0, v0, u1, v1 = special.UV(special.Hunt);
                                    icons.Quad(pen, temperTop, pen + temperSize, temperTop + temperSize, u0, v0, u1, v1, part.color or WHITE, special.Slot, true);
                                else
                                    icons.Quad(pen, temperTop, pen + temperSize, temperTop + temperSize, u, v, u + 0.25, v + 0.25, part.color or WHITE, TEMPER_SLOT, true);
                                end
                                pen = pen + temperSize;
                            end
                            if (kind == 'checked' and sign and not showDetails) then
                                -- smaller than the letters by a set part (or the token's size=), whatever size
                                -- they are, and made smaller about the middle of the line so that it stays level with them
                                local signSize = part.size and part.size / 100 or SIGN_SIZE;
                                local small = fit * signSize;
                                local middle = rungHeight * 0.5;
                                icons.Quad(pen + sign[1] * small, top + (middle + (sign[2] - middle) * signSize) * fit,
                                    pen + sign[3] * small, top + (middle + (sign[4] - middle) * signSize) * fit,
                                    sign[5], sign[6], sign[7], sign[8], part.color or WHITE, SIGN_SLOT);
                                pen = pen + sign[9] * small;
                            end
                            -- Letters are part of the name, not independent status icons.
                            -- Pre-resolved tint also works when [letters] precedes [name].
                            local badgeColor = fadedColor(override or part.color or nameTint, textOpacity);
                            local badgePen = kind == 'letter' and letterBadges.Write(set, words, pen, top, fit, badgeColor);
                            if (kind == 'letter') then
                                pen = badgePen or writeLetterFallback(set, words, pen, top, fit, badgeColor);
                            else
                                pen = writeWords(set, words, pen, top, fit, color, nil, textOpacity,
                                    part.spacing and part.spacing * spacingAt or track);
                            end
                            if (kind ~= 'icons' and kind ~= 'party' and kind ~= 'vendor' and pen > start) then
                                pen = pen + math.floor((part.space or 0) * scale + 0.5);
                            end
                        end
                    end

                    -- what its player's check found, under the name for a few seconds
                    local under = math.max(top + height, math.ceil((height + iconsHeight) * 0.5));
                    if (showDetails and written.isChecked and name.Category == MONSTER) then
                        under = math.max(under, writeDetails(options, written, set, sign, own, fit, height, rungHeight,
                            top + math.max(0, under - top - height), scale, now) or under);
                    end

                    written.barScale = scale * height / fullHeight;
                    written.barLeft, written.barRight, written.barWidth = nameLeft, nameLeft + width, options.healthBarWidth[1];
                    if written.cast and options.castBarAutoWidth[1] and written.barNameLeft ~= nil then
                        written.barLeft, written.barRight = nameLeft + written.barNameLeft, nameLeft + written.barNameRight;
                        written.barWidth = math.max(written.barWidth, (written.barRight - written.barLeft) / written.barScale);
                    end
                    if (not written.simplified and options.showHealthBar[1] and bit.band(options.healthBarCategories[1], name.Category) ~= 0
                            and (not options.healthBarsCombatOnly[1] or nameColours.InCombat(name, entities))) then
                        -- the bar is its saved size under a name at its largest, and shrinks with the name
                        -- as it goes further away (or grows with it, hunted or under the sub-target cursor)
                        under = healthbar.Write(name, entities, written.barLeft, written.barRight,
                            under, written.barScale, fill, written.barWidth, options.healthBarHeight[1], written.cast ~= nil);
                    end
                    if written.cast then
                        under = fontPipeline.WriteCast(written.cast, set, written.barLeft, written.barRight, under,
                            written.barScale, fit, height, written.barWidth, options.healthBarHeight[1], textOpacity,
                            options, nameTint);
                    end

                    -- the row of statuses over all of it, or under it
                    if (statusRows and not written.simplified) then
                        statuses.Write(name, nameLeft, nameLeft + width, clear, under, height, scale);
                    end

                    nameplates.EndName();
                end
            end
        end
    end
end

return custom;
