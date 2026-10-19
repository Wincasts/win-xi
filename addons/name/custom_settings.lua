-- The Names, Health Bars and NM Tracking tabs of the settings: how the names are drawn, as custom.lua
-- draws them.
--
--   settings.DrawSettings(options, save)    the Names tab
--   settings.DrawHealthBars(options, save)  the Health Bars tab
--   settings.DrawTracking(options, save)    the NM Tracking tab, after /name dev
local imgui = require('imgui');
local widgets    = require('winxi.widgets');
local nameplates = require('winxi.nameplates');
local controls   = require('controls');
local format     = require('format');
local levels     = require('levels');
local nameColours = require('name_colours');
local nameTypes  = require('name_types');
local entityTypes = require('entity_types');

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

local warning = { 1.0, 0.6, 0.4, 1.0 };

-- The notorious monster being hunted: a tab of its own
function settings.DrawTracking(options, save)
    imgui.TextWrapped('Disclaimer: NM tracking could be considered cheating. Enable at your own risk.');
    widgets.Gap();
    controls.BeginLayout('tracking', 360, 'Label Placeholders');
    if (controls.Section('Tracked Monster', '##name.trackOptions', true)) then
        -- the one notorious monster being hunted, of those the area has
        local tracked = options.trackedNm[1];
        widgets.Label('Tracked NM', true);
        controls.Width();
        if (imgui.BeginCombo('##name.trackedNm', tracked ~= '' and tracked or 'None')) then
            if (imgui.Selectable('None', tracked == '') and tracked ~= '') then
                options.trackedNm[1] = '';
                if (save ~= nil) then save(); end
            end
            for _, monster in ipairs(levels.Notorious()) do
                if (imgui.Selectable(monster, tracked == monster) and tracked ~= monster) then
                    options.trackedNm[1] = monster;
                    if (save ~= nil) then save(); end
                end
            end
            imgui.EndCombo();
        end
        controls.Mark('Track a notorious monster in this area. Requires [aggro] in Mob Format and Show Aggro Icons. The choice is saved when you leave.');
        if (options.trackedNm[1] ~= '') then
            controls.Slider('Target Size (%)', '##name.huntScale', options.huntScale, 100, 200, '%d%%',
                'Enlarge the tracked monster\'s whole nameplate. Placeholders keep their normal size.');
        end
    end
    controls.EndSection();
    if (options.trackedNm[1] ~= '' and levels.Placeholders(options.trackedNm[1]) ~= nil
            and controls.Section('Placeholder Options', '##name.placeholderOptions')) then
            controls.Checkbox('Label Placeholders', '##name.labelPlaceholders', options.labelPlaceholders,
                'Replace placeholder names with "Placeholder". The rest of each nameplate is unchanged.');
    end
    controls.EndSection();
    controls.EndLayout();
end

-- The bars under the names: a tab of their own
function settings.DrawHealthBars(options, save)
    controls.BeginLayout('healthBars', 360, 'Health Bar Height (px)');
    if (controls.Section('Health Bars', '##name.healthBarOptions', true)) then
        nameTypes.Draw(options);
    end
    controls.EndSection();
    if (controls.Section('Entity Types', '##name.healthBarTypes')) then
        imgui.BeginDisabled(not options.showHealthBar[1]);
        if (entityTypes.Draw('healthBarTypes', options.healthBarCategories, 'Whether names of this kind have a health bar.') and save ~= nil) then
            save();
        end
        imgui.EndDisabled();
    end
    controls.EndSection();
    controls.EndLayout();
end

-- Keep format reference/examples on the editor's (?) rather than separate dropdowns.
local formatHelp = {
    nameFormat = 'Format for player names. Tokens:\n[name] - player name.\n[icons] - available game status icons.\n[distance] - distance in yalms.\n\nExample format:\n[icons: space=4][name] ([distance: decimals=1, color=yellow]y)\nExample result: [status icons] Player Name (12.4y)',
    monsterFormat = 'Format for all enemy names, including targeted and checked enemies. Tokens:\n[name] - enemy name.\n[distance] - distance in yalms.\n[level] - database level range, or exact level after /check. [level: exact] - only the exact level, once checked.\n[aggro] - aggression/difficulty icon when known.\n[checked] - magnifying glass when the exact level is known from /check.\n[letters] - stable spawn-slot letter; [letter] is an alias.\nUse type=double for AA, AB after Z, or type=single to repeat A-Z.\n\nExample format:\n[aggro: space=4]Lv [level]. [name] [letters: type=double] ([distance: decimals=1]y)\nExample result: [aggro icon] Lv 80-82. Goblin Butcher AA (12.4y)\nRemove a token to hide its information; unknown values are omitted.',
    npcFormat = 'Format for NPC names. Tokens:\n[name] - NPC name.\n[distance] - distance in yalms.\n[icons] - game-supplied icons, when present.\n\nExample format:\n[name: color=cyan] ([distance: decimals=1]y)\nExample result: Mog House (4.2y)',
};
local formatOptions = '\n\nOptions: color=yellow (or #RRGGBB), space=0-64 pixels after non-empty tokens.\n[distance]: decimals=0-2. [icons]: size=25-300 (% of name height), gap=0-24 pixels.\nSeparate options with commas, spaces or semicolons. Literal text stays where you type it.\nEnabled state colour overrides take precedence over name/spawn-letter token colours; other explicit token colours are unchanged.\nLegacy [name:yellow] and [#FF8000]text[/] still work.';
local function DrawFormat(label, key, options, save)
    local enemy = key == 'monsterFormat';
    local baseline = enemy and '[aggro] [name] [letters]' or (key == 'nameFormat' and '[icons: space=4][name]' or '[name]');
    widgets.Label(label);
    controls.Width();
    imgui.InputText('##name.' .. key, options[key], math.max(1024, #options[key][1]+256));
    controls.Mark(formatHelp[key] .. formatOptions .. '\nDefault: ' .. baseline);
    widgets.Label('Reset Format');
    if (imgui.Button('Reset##name.' .. (enemy and 'resetFormat' or ('reset.' .. key)))) then
        options[key][1] = baseline;
        if (save ~= nil) then save(); end
    end
    controls.Mark('Restore this category\'s default format without changing other settings.');
end

function settings.DrawSettings(options, save)
    local problem = nameplates.Problem();
    if (problem ~= nil) then
        imgui.TextColored(warning, problem);
        widgets.Gap();
    end

    controls.BeginLayout('nameplates', 360, 'Abbreviate Difficulty');
    if (controls.Section('General Name Appearance', '##name.appearanceOptions', true)) then
        widgets.Label('Font');
        controls.Width();
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
        controls.Mark('A font of Windows\' own, by its file in C:\\Windows\\Fonts. Default is the font everything else is written in.');
        controls.Checkbox('Bold', '##name.fontBold', options.fontBold,
            'Makes names and check-detail text heavier, by drawing each letter twice, a pixel apart. Icons, stars and outline thickness are unchanged.');
        if (controls.Input('Maximum Name Size (px)', '##name.fontSize', options.fontSize, SMALLEST, LARGEST,
                'Nearby name size shared by players, enemies and NPCs. Independent of health-bar dimensions.') and options.minSize[1] > options.fontSize[1]) then
            options.minSize[1] = options.fontSize[1];
        end
        if (controls.Input('Minimum Name Size (px)', '##name.minSize', options.minSize, SMALLEST, LARGEST,
                'Smallest distant name size shared by every entity type.') and options.fontSize[1] < options.minSize[1]) then
            options.fontSize[1] = options.minSize[1];
        end
        controls.Slider('Subtarget Size (%)', '##name.subtargetScale', options.subtargetScale, 50, 200, '%d%%',
            'Size of the name under the subtarget cursor while choosing a target. 100% is normal size.');
        controls.Outline(options.outline);
    end
    controls.EndSection();

    if (controls.Section('Player Names', '##name.playerOptions')) then
        DrawFormat('Player Format', 'nameFormat', options, save);
        nameColours.Draw(options, 'playerNames');
    end
    controls.EndSection();
    if (controls.Section('Enemy Names', '##name.mobOptions')) then
        DrawFormat('Enemy Format', 'monsterFormat', options, save);
        nameColours.Draw(options, 'enemyNames');
        local rosterProblem = format.Compile(options.monsterFormat[1]).letter and levels.RosterProblem() or nil;
        if (rosterProblem ~= nil) then
            imgui.TextColored(warning, rosterProblem);
        end
        controls.Help('Help / Examples', '##name.letterHelp',
            'Mob Letters use stable entity-index order, not encounter order. Unknown or renamed slots are not labelled.\nAdd [letters] to Enemy Format for single letters, or [letters: type=double] for AA, AB, etc. after Z. No token means no letters. Users comparing letters need matching game files, zone tables and token type.');
        if (controls.More('Check Details', '##name.checkOptions')) then
            controls.Checkbox('Enabled', '##name.showCheckDetails', options.showCheckDetails,
                'Show difficulty, detection and linking information for five seconds after checking a monster.');
            if (options.showCheckDetails[1]) then
                controls.Slider('Size (%)', '##name.checkSize', options.checkSize, 50, 125, '%d%%',
                    'Size of check text and icons relative to the name. Applies to both display styles.');
                controls.Checkbox('Abbreviate Difficulty', '##name.abbreviateDifficulty', options.abbreviateDifficulty,
                    'Use short difficulty labels beside detection/link details. Impossible to Gauge stays ???.');
                controls.Choice('Display Style', '##name.checkDetailsInWords', options.checkDetailsInWords,
                    { { key = false, label = 'Icons & Text' }, { key = true, label = 'Text Only' } },
                    'Choose icons with text, or a text-only description.');
                controls.Help('Help / Examples', '##name.checkHelp',
                    'Text-only example: TW, Sight Aggro, Link: Goblin (Sight).\nAbbreviations: TW, IEP, EP, DC, EM, T, VT and IT. When difficulty is shown alone, full words are used.\nDetection can include Sight, Sound, Blood, Magic, JA, Scent and true senses. Multiple senses are separated by a slash. Link names the monster family and its known Sight/Hearing detection.');
            end
            imgui.TreePop();
        end
    end
    controls.EndSection();
    if (controls.Section('NPC Names', '##name.npcOptions')) then
        DrawFormat('NPC Format', 'npcFormat', options, save);
        nameColours.Draw(options, 'npcNames');
    end
    controls.EndSection();
    controls.EndLayout();
end

return settings;
