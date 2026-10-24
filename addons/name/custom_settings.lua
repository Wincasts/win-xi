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
local tips       = require('winxi.tips');
local levels     = require('levels');
local nameColours = require('name_colours');
local nameTypes  = require('name_types');
local entityTypes = require('entity_types');
local roles      = require('roles');
local icons      = require('icons');

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
        controls.Mark(tips.Get('name.tracking.monster'));
        if (options.trackedNm[1] ~= '') then
            controls.Slider('Target Size (%)', '##name.huntScale', options.huntScale, 100, 200, '%d%%',
                tips.Get('name.tracking.size'));
        end
    end
    controls.EndSection();
    if (options.trackedNm[1] ~= '' and levels.Placeholders(options.trackedNm[1]) ~= nil
            and controls.Section('Placeholder Options', '##name.placeholderOptions')) then
            controls.Checkbox('Label Placeholders', '##name.labelPlaceholders', options.labelPlaceholders,
                tips.Get('name.tracking.placeholders'));
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
    if controls.Section('Cast Bars', '##name.castBarOptions') then
        controls.Checkbox('Enabled', '##name.showCastBar', options.showCastBar, tips.Get('name.cast_bars.enabled'));
        if options.showCastBar[1] then
            controls.Checkbox('Show Weaponskills', '##name.castBarWeaponskills', options.castBarWeaponskills,
                tips.Get('name.cast_bars.weaponskills'));
            imgui.BeginDisabled(not options.castBarWeaponskills[1]);
            controls.Checkbox('Text Only for Weaponskills', '##name.castBarSkillTextOnly', options.castBarSkillTextOnly,
                tips.Get('name.cast_bars.skill_text_only'));
            imgui.EndDisabled();
            controls.Checkbox('Auto-scale to Name', '##name.castBarAutoWidth', options.castBarAutoWidth,
                tips.Get('name.cast_bars.auto_width'));
            local casts = require('castbar');
            controls.Checkbox('Preview', '##name.castBarPreview', casts.Preview, tips.Get('name.cast_bars.preview'));
            casts.PreviewVisible(os.clock());
        end
    end
    controls.EndSection();
    if options.showCastBar[1] and controls.Section('Cast Text', '##name.castTextOptions') then
        controls.Checkbox('Show Action Name', '##name.castShowName', options.castShowName, tips.Get('name.cast_text.show_name'));
        controls.Checkbox('Show Timer', '##name.castShowTimer', options.castShowTimer, tips.Get('name.cast_text.show_timer'));
        controls.Choice('Text Colour', '##name.castTextColour', options.castTextColour, require('custom').CastTextColours,
            tips.Get('name.cast_text.colour'));
        if options.castTextColour[1] == 'custom' then
            widgets.Label('Custom Colour'); controls.Width();
            imgui.ColorEdit4('##name.castTextColor', options.castTextColor, ImGuiColorEditFlags_NoAlpha or 0);
            controls.Mark(tips.Get('name.cast_text.custom_colour'));
        end
        imgui.BeginDisabled(not options.castShowName[1]);
        controls.Slider('Cast Name Size (%)', '##name.castNameScale', options.castNameScale, 25, 200, '%d%%',
            tips.Get('name.cast_bars.name_scale'));
        imgui.EndDisabled();
        imgui.BeginDisabled(not options.castShowTimer[1]);
        controls.Slider('Timer Size (%)', '##name.castTimerScale', options.castTimerScale, 25, 200, '%d%%',
            tips.Get('name.cast_bars.timer_scale'));
        imgui.EndDisabled();
    end
    controls.EndSection();
    if controls.Section('Shared Bar Size', '##name.barSize') then
        nameTypes.DrawSize(options);
    end
    controls.EndSection();
    if (controls.Section('Entity Types', '##name.healthBarTypes')) then
        imgui.BeginDisabled(not options.showHealthBar[1]);
        if (entityTypes.Draw('healthBarTypes', options.healthBarCategories, tips.Get('name.health_bars.entity_types')) and save ~= nil) then
            save();
        end
        imgui.EndDisabled();
    end
    controls.EndSection();
    controls.EndLayout();
end

-- Keep format reference/examples on the editor's (?) rather than separate dropdowns.
local formatHelp = {
    nameFormat = tips.Get('name.format.player'),
    monsterFormat = tips.Get('name.format.enemy'),
    npcFormat = tips.Get('name.format.npc'),
};
local function DrawFormat(label, key, options, save)
    local enemy = key == 'monsterFormat';
    local baseline = enemy and '[aggro] [name] [letters]' or (key == 'nameFormat' and '[icons: space=4][name]' or '[name]');
    widgets.Label(label);
    controls.Width();
    imgui.InputText('##name.' .. key, options[key], math.max(1024, #options[key][1]+256));
    controls.Mark(formatHelp[key] .. '\n\n' .. tips.Get('name.format.options', { default_format = baseline }));
    widgets.Label('Reset Format');
    if (imgui.Button('Reset##name.' .. (enemy and 'resetFormat' or ('reset.' .. key)))) then
        options[key][1] = baseline;
        if (save ~= nil) then save(); end
    end
    controls.Mark(tips.Get('name.format.reset'));
end

function settings.DrawSettings(options, save)
    local problem = nameplates.Problem(nameplates.Feature.IconOutline);
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
        controls.Mark(tips.Get('name.appearance.font'));
        controls.Checkbox('Bold', '##name.fontBold', options.fontBold);
        imgui.SameLine();
        imgui.Checkbox('Smooth Font##name.fontSmooth', options.fontSmooth);
        controls.Mark(tips.Get('name.appearance.bold') .. '\n\n' .. tips.Get('name.appearance.smooth_font'));
        if (controls.Input('Maximum Name Size (px)', '##name.fontSize', options.fontSize, SMALLEST, LARGEST,
                tips.Get('name.appearance.maximum_size')) and options.minSize[1] > options.fontSize[1]) then
            options.minSize[1] = options.fontSize[1];
        end
        if (controls.Input('Minimum Name Size (px)', '##name.minSize', options.minSize, SMALLEST, LARGEST,
                tips.Get('name.appearance.minimum_size')) and options.fontSize[1] < options.minSize[1]) then
            options.fontSize[1] = options.minSize[1];
        end
        controls.Slider('Subtarget Size (%)', '##name.subtargetScale', options.subtargetScale, 50, 200, '%d%%',
            tips.Get('name.appearance.subtarget_size'));
        controls.Outline(options.outline, 'Text Outline (px)');
        controls.Outline(options.iconOutline, 'Icon Outline (px)', 'iconOutline', tips.Get('name.appearance.icon_outline'));
        controls.Slider('Icon Outline Opacity (%)', '##name.iconOutlineOpacity', options.iconOutlineOpacity, 0, 100, '%d%%',
            tips.Get('name.appearance.icon_outline_opacity'));
    end
    controls.EndSection();

    require('readability').DrawSettings(options);

    if (controls.Section('Player Names', '##name.playerOptions')) then
        DrawFormat('Player Format', 'nameFormat', options, save);
        controls.Choice('Player Icon Source', '##name.playerIconSource', options.playerIconSource, icons.Sources,
            tips.Get('name.players.icon_source'));
        local iconProblem = icons.Problem(options.playerIconSource[1]);
        if iconProblem then
            imgui.TextColored(warning, icons.Texture() and 'Player icons: bundled fallback.' or 'Player icons unavailable.');
            controls.Mark(tips.Get('name.players.icon_source_fallback', { reason = iconProblem }));
        end
        controls.Choice('Party Icons', '##name.partyIcons', options.partyIcons, roles.Modes,
            tips.Get('name.players.party_icons'));
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
            tips.Get('name.enemies.letters_help'));
        if (controls.More('Check Details', '##name.checkOptions')) then
            controls.Checkbox('Enabled', '##name.showCheckDetails', options.showCheckDetails,
                tips.Get('name.enemies.check_enabled'));
            if (options.showCheckDetails[1]) then
                controls.Slider('Size (%)', '##name.checkSize', options.checkSize, 50, 125, '%d%%',
                    tips.Get('name.enemies.check_size'));
                controls.Checkbox('Abbreviate Difficulty', '##name.abbreviateDifficulty', options.abbreviateDifficulty,
                    tips.Get('name.enemies.check_abbreviate'));
                controls.Choice('Display Style', '##name.checkDetailsInWords', options.checkDetailsInWords,
                    { { key = false, label = 'Icons & Text' }, { key = true, label = 'Text Only' } },
                    tips.Get('name.enemies.check_style'));
                controls.Help('Help / Examples', '##name.checkHelp',
                    tips.Get('name.enemies.check_help'));
            end
            imgui.TreePop();
        end
    end
    controls.EndSection();
    if (controls.Section('NPC Names', '##name.npcOptions')) then
        DrawFormat('NPC Format', 'npcFormat', options, save);
        controls.Checkbox('Vendor Icons', '##name.showVendorIcons', options.showVendorIcons,
            tips.Get('name.npcs.vendor_icons'));
        nameColours.Draw(options, 'npcNames');
    end
    controls.EndSection();
    controls.EndLayout();
end

return settings;
