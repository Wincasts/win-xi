-- The Names, Bars, Check Details and NM Tracking tabs of the settings: how the
-- names are drawn, as custom.lua draws them. Every setting is a described row (controls).
--
--   settings.DrawSettings(options, save)    the Names tab
--   settings.DrawBars(options, save)        the Bars tab: health and cast bars
--   settings.DrawCheck(options, save)       the Check Details tab
--   settings.DrawTracking(options, save)    the NM Tracking tab, after /name dev
local imgui = require('imgui');
local widgets    = require('winxi.widgets');
local nameplates = require('winxi.nameplates');
local controls   = require('controls');
local format     = require('format');
local tips       = require('winxi.tips');
local levels     = require('levels');
local nameColours = require('name_colours');
local nameTypes  = require('name_types');
local entityTypes = require('entity_types');
local icons      = require('icons');
local healthbar  = require('healthbar');

local settings = {};

local SMALLEST     = 6;  -- pixels: the smallest a name can be set to be
local LARGEST      = 48; -- and the largest
local FONT_FOLDER  = 'C:\\Windows\\Fonts\\';
local DEFAULT_FONT = 'Default';

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

-- The names' fonts as the dropdown takes them: Default, then the files; and the cast's, with Same as
-- Names before. Each made once.
local nameFonts, castFonts = nil, nil;

local function NameFonts()
    if (nameFonts == nil) then
        nameFonts = { { key = '', label = DEFAULT_FONT } };
        for _, file in ipairs(getFontFiles()) do
            nameFonts[#nameFonts + 1] = file;
        end
    end
    return nameFonts;
end

local function CastFonts()
    if (castFonts == nil) then
        castFonts = { { key = '', label = 'Same as Names' }, { key = require('custom').CastDefaultFont, label = DEFAULT_FONT } };
        for _, file in ipairs(getFontFiles()) do
            castFonts[#castFonts + 1] = file;
        end
    end
    return castFonts;
end

-- The rows' specs, made once; a parent is set on each as it is drawn
local castSpec = {};        -- the cast text's rows: while cast bars are on
local weaponskillSpec = {};
local textOnlySpec = {};
local castNameSpec = {};
local castTimerSpec = {};
local sharedSpec = {};      -- what the bars share: while either kind is on
local healthSpec = {};
local checkSpec = {};
local trackedSpec = { experimental = true };
local huntSpec = {};

local checkStyles = { { key = false, label = 'Icons & Text' }, { key = true, label = 'Text Only' } };

-- The notorious monster being hunted: a tab of its own
local notorious = { { key = '', label = 'None' } }; -- the area's, found afresh as the list opens

local function Notorious()
    for index = #notorious, 2, -1 do
        notorious[index] = nil;
    end
    for _, monster in ipairs(levels.Notorious()) do
        notorious[#notorious + 1] = monster;
    end
    return notorious;
end
trackedSpec.onOpen = Notorious;

function settings.DrawTracking(options, save)
    controls.Note('NM tracking could be considered cheating. Enable at your own risk.');
    if (controls.Section('Tracked Monster', true)) then
        -- the one notorious monster being hunted, of those the area has
        local tracked = options.trackedNm[1];
        local chosen = widgets.Dropdown('Tracked NM',
            'Marks one notorious monster of this area, and what it can spawn from, with a hunt sign instead of the aggro icon. Enemy Format needs [aggro].',
            notorious, tracked, '##name.trackedNm', trackedSpec);
        if (chosen ~= nil) then
            options.trackedNm[1] = chosen;
            if (save ~= nil) then save(); end
        end
        huntSpec.parent = options.trackedNm[1] ~= '';
        controls.Slider('Target Size', '##name.huntScale', options.huntScale, 100, 200, '%d%%',
            'How much larger the tracked monster\'s whole name is drawn. Its placeholders stay the usual size.', huntSpec);
        if (options.trackedNm[1] ~= '' and levels.Placeholders(options.trackedNm[1]) ~= nil) then
            controls.Checkbox('Label Placeholders', '##name.labelPlaceholders', options.labelPlaceholders,
                'Writes Placeholder instead of each placeholder\'s name. The rest of its name is unchanged.', huntSpec);
        end
    end
end

-- The bars under the names, health and cast, in one tab: what they share first (their size, Fit To Name and
-- the preview of them all), then each kind's own
function settings.DrawBars(options, save)
    local either = options.showHealthBar[1] or options.showCastBar[1];
    if controls.Section('Shared Bar Settings', true) then
        nameTypes.DrawSize(options);
        sharedSpec.parent = either and true or false;
        controls.Checkbox('Fit To Name', '##name.castBarAutoWidth', options.castBarAutoWidth,
            'Bars grow to the width of the name and its spawn letter. Bar Width is the least they are.', sharedSpec);
        controls.Checkbox('Preview', '##name.barPreview', healthbar.Preview,
            'Shows a bar under every name that can have one, emptying and filling, and a sample cast. Not saved.', sharedSpec);
    end
    -- one preview for both kinds, each shown while it is enabled, and only while this is drawn
    local casts = require('castbar');
    casts.Preview[1] = healthbar.Preview[1];
    if options.showHealthBar[1] then healthbar.PreviewVisible(os.clock()); end
    if options.showCastBar[1] then casts.PreviewVisible(os.clock()); end

    if (controls.Section('Health Bars')) then
        nameTypes.Draw(options);
        if (controls.Sub('Entity Types')) then
            healthSpec.parent = options.showHealthBar;
            if (entityTypes.Draw('healthBarTypes', options.healthBarCategories, 'A health bar', healthSpec) and save ~= nil) then
                save();
            end
        end
    end

    if controls.Section('Cast Bars') then
        controls.Checkbox('Enabled', '##name.showCastBar', options.showCastBar,
            'A bar under a name while its owner casts, filling as the cast goes on, in the health bars\' size. A cast time not known is counted up instead.');
        weaponskillSpec.parent = options.showCastBar;
        controls.Checkbox('Show Weaponskills', '##name.castBarWeaponskills', options.castBarWeaponskills,
            'Also shows readied weaponskills and monster moves, with their preparation times where known.', weaponskillSpec);
        textOnlySpec.parent = (options.showCastBar[1] and options.castBarWeaponskills[1]) and true or false;
        controls.Checkbox('Text Only For Weaponskills', '##name.castBarSkillTextOnly', options.castBarSkillTextOnly,
            'Weaponskills and monster moves as name and timer alone, with no bar. Spells keep their bar.', textOnlySpec);
    end
    if controls.Section('Cast Text') then
        castSpec.parent = options.showCastBar;
        local castFont = widgets.Dropdown('Font',
            'The font the cast\'s name and timer are written in. Same as Names is the names\' font, Default the font everything else is written in.',
            CastFonts(), options.castFont[1], '##name.castFont', castSpec);
        if (castFont ~= nil) then options.castFont[1] = castFont; end
        controls.Checkbox('Show Action Name', '##name.castShowName', options.castShowName,
            'Writes the spell, weaponskill or monster move\'s name under the cast bar.', castSpec);
        controls.Checkbox('Show Timer', '##name.castShowTimer', options.castShowTimer,
            'Writes the time left, or the time so far, under the action\'s name.', castSpec);
        controls.Choice('Text Colour', '##name.castTextColour', options.castTextColour, require('custom').CastTextColours,
            'The colour of the action\'s name and timer: White, Name Colour or Custom.', castSpec);
        if options.castTextColour[1] == 'custom' then
            controls.Color('Custom Colour', '##name.castTextColor', options.castTextColor,
                'The colour of the action\'s name and timer while Text Colour is Custom.', castSpec);
        end
        castNameSpec.parent = (options.showCastBar[1] and options.castShowName[1]) and true or false;
        controls.Slider('Cast Name Size', '##name.castNameScale', options.castNameScale, 25, 200, '%d%%',
            'How big the action\'s name is, compared with the name over the head.', castNameSpec);
        castTimerSpec.parent = (options.showCastBar[1] and options.castShowTimer[1]) and true or false;
        controls.Slider('Timer Size', '##name.castTimerScale', options.castTimerScale, 25, 200, '%d%%',
            'How big the timer is, compared with the name over the head.', castTimerSpec);
    end
end

-- What a check of a monster says, on a line under its name: a tab of its own
function settings.DrawCheck(options, save)
    if (controls.Section('Check Details', true)) then
        controls.Checkbox('Enabled', '##name.showCheckDetails', options.showCheckDetails,
            'After you check a monster, its difficulty, what it detects by and what it links with are written under its name for five seconds.');
        checkSpec.parent = options.showCheckDetails;
        controls.Slider('Size', '##name.checkSize', options.checkSize, 50, 125, '%d%%',
            'How big the check text and icons are, compared with the name.', checkSpec);
        controls.Checkbox('Abbreviate Difficulty', '##name.abbreviateDifficulty', options.abbreviateDifficulty,
            'Short difficulty labels, such as EP or VT, when detection or link details are written beside them.', checkSpec);
        controls.Choice('Display Style', '##name.checkDetailsInWords', options.checkDetailsInWords, checkStyles,
            'Icons with the text, or the text alone: Icons & Text or Text Only.', checkSpec);
    end
end

-- The tokens each kind of name can have, with an example, under Format Tokens
local formatHelp = {
    nameFormat = tips.Get('name.format.player'),
    monsterFormat = tips.Get('name.format.enemy'),
    npcFormat = tips.Get('name.format.npc'),
};

-- Each format's row, its Reset after it, and its tokens in a sub-section collapsed to start
local formats = {
    nameFormat = { label = 'Player Format', id = '##name.nameFormat', reset = 'Reset##name.reset.nameFormat', resetLabel = 'Reset Player Format',
        baseline = '[party: space=2][icons: space=4][name]',
        sentence = 'How player names are written, from tokens such as [name], [party] and [icons]. Format Tokens below lists them all.' },
    monsterFormat = { label = 'Enemy Format', id = '##name.monsterFormat', reset = 'Reset##name.resetFormat', resetLabel = 'Reset Enemy Format',
        baseline = '[aggro] [name] [letters]',
        sentence = 'How enemy names are written, from tokens such as [name], [level], [aggro] and [letters]. Format Tokens below lists them all.' },
    npcFormat = { label = 'NPC Format', id = '##name.npcFormat', reset = 'Reset##name.reset.npcFormat', resetLabel = 'Reset NPC Format',
        baseline = '[vendor: space=4][name]',
        sentence = 'How NPC names are written, from tokens such as [name], [vendor] and [distance]. Format Tokens below lists them all.' },
};

local function DrawFormat(key, options, save)
    local row = formats[key];
    controls.Text(row.label, row.id, options[key], math.max(1024, #options[key][1] + 256), row.sentence);
    if (widgets.Action(row.resetLabel, 'Puts back this format\'s default. Nothing else changes.', row.reset)) then
        options[key][1] = row.baseline;
        if (save ~= nil) then save(); end
    end
end

local function DrawTokens(key)
    if (controls.Sub('Format Tokens', false, true)) then
        controls.Note(formatHelp[key]);
    end
end

function settings.DrawSettings(options, save)
    local problem = nameplates.Problem(nameplates.Feature.IconOutline);
    if (problem ~= nil) then
        controls.Note(problem);
    end

    if (controls.Section('Appearance', true)) then
        if (controls.Sub('Font', true)) then
            local font = widgets.Dropdown('Font',
                'The font the names are written in. Default is the font everything else is written in.',
                NameFonts(), options.font, '##name.font');
            if (font ~= nil) then
                options.font = font;
                if (save ~= nil) then save(); end
            end
            controls.Checkbox('Bold', '##name.fontBold', options.fontBold,
                'Writes names and check details heavier. Icons and outlines are unchanged.');
            controls.Checkbox('Smooth Font', '##name.fontSmooth', options.fontSmooth,
                'Draws the letters from a finer copy of the font, so curves look smoother. Very small text may look softer.');
        end
        if (controls.Sub('Size')) then
            if (controls.Input('Maximum Name Size', '##name.fontSize', options.fontSize, SMALLEST, LARGEST, '%d px',
                    'How large a name is when close, for players, enemies and NPCs alike. Bars have a size of their own.')
                    and options.minSize[1] > options.fontSize[1]) then
                options.minSize[1] = options.fontSize[1];
            end
            if (controls.Input('Minimum Name Size', '##name.minSize', options.minSize, SMALLEST, LARGEST, '%d px',
                    'The smallest a name shrinks to as it gets farther away.')
                    and options.fontSize[1] < options.minSize[1]) then
                options.fontSize[1] = options.minSize[1];
            end
            controls.Slider('Subtarget Size', '##name.subtargetScale', options.subtargetScale, 50, 200, '%d%%',
                'How big the name under the subtarget cursor is while you choose a target.');
            controls.Slider('Letter Spacing', '##name.letterSpacing', options.letterSpacing, 0, 10, '%d px',
                'Extra room between the letters of every name, at its largest. 0 is the font\'s own spacing.');
        end
        if (controls.Sub('Outlines')) then
            controls.Outline(options.outline, 'Text Outline', '##name.outline',
                'How thick the dark edge round the text is. Icons have an edge of their own.');
            controls.Slider('Text Outline Opacity', '##name.textOutlineOpacity', options.textOutlineOpacity, 0, 100, '%d%%',
                'How solid the edge round the text is. 0 hides it.');
            controls.Outline(options.iconOutline, 'Icon Outline', '##name.iconOutline',
                'How thick the dark edge round the icons is. Mastery stars and letter badges have their own.');
            controls.Slider('Icon Outline Opacity', '##name.iconOutlineOpacity', options.iconOutlineOpacity, 0, 100, '%d%%',
                'How solid the edge round the icons is. 0 hides it.');
        end
    end

    if (controls.Section('Player Names')) then
        DrawFormat('nameFormat', options, save);
        controls.Choice('Player Icon Source', '##name.playerIconSource', options.playerIconSource, icons.Sources,
            'Where the player icons and mastery stars come from: Game DATs, Bundled or Custom. A source that cannot be loaded falls back to Bundled.');
        local iconProblem = icons.Problem(options.playerIconSource[1]);
        if iconProblem then
            controls.Note(icons.Texture() and ('The chosen icon source could not be loaded, so the bundled icons are used: ' .. iconProblem)
                or ('Player icons unavailable: ' .. iconProblem));
        end
        DrawTokens('nameFormat');
        nameColours.Draw(options, 'playerNames');
    end
    if (controls.Section('Enemy Names')) then
        DrawFormat('monsterFormat', options, save);
        DrawTokens('monsterFormat');
        nameColours.Draw(options, 'enemyNames');
        local rosterProblem = format.Compile(options.monsterFormat[1]).letter and levels.RosterProblem() or nil;
        if (rosterProblem ~= nil) then
            controls.EndSub();
            controls.Note(rosterProblem);
        end
    end
    if (controls.Section('NPC Names')) then
        DrawFormat('npcFormat', options, save);
        DrawTokens('npcFormat');
        nameColours.Draw(options, 'npcNames');
    end
    require('readability').DrawDistance(options);
end

return settings;
