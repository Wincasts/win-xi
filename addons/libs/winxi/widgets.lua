-- winxi.widgets: ready-made controls for an addon's settings window.
--
--   widgets.Appearance(hooks)        the Theme, Window, Font and Styles sections of the Winxi Theme tab: the
--                                    windows on the game screen
--   widgets.SettingsAppearance(hooks) the settings windows' own Window and Font sections
--   widgets.IconAppearance()         the icons' section: the custom status icons
--   widgets.TooltipAppearance()      every tooltip's look and behaviour (winxi.tooltip), always the
--                                    shared theme's
--   widgets.BeginThemeTab() / EndThemeTab()   the Winxi Theme tab itself: last in its tab bar, against
--                                    its right edge, in a colour of its own
--   widgets.Header(text)             a section title, for the addon's own section after those; [-] or
--                                    [+] before it, a click collapses or opens it, and it returns
--                                    whether it is open, for the section to be drawn only then
--   widgets.Label(text)              a setting's name, to the left of its control, in line with winxi's
--   widgets.Label(text, true)        the same for an experimental setting: [Experimental], in yellow,
--                                    goes before its name
--   widgets.BeginLabels(key)         starts a group of settings whose controls line up with each other
--   widgets.Gap()                    the space between one family of settings and the next
--   widgets.PushControlWidth() / PopControlWidth()   around an addon's own settings, to match winxi's
--   widgets.NumberWidth(fields, digits)   the width for a box of whole numbers (InputInt, InputInt2),
--                                    for SetNextItemWidth: room for the digits in each field and no more
--   widgets.GrowFrom(current)        four buttons for a window's corner; returns the new choice or nil
--   widgets.Fade(settings, onChanged) the controls for fading while idle (see winxi.fade)
--   widgets.FontFile(options, key, id, spec)   a font of the addon's own, for text it writes itself: the
--                                    theme's font or a .ttf of C:\Windows\Fonts, kept as a file name
--   widgets.FontSize(options, key, id, spec)   its size: the theme's size (0) or pixels
--   widgets.Lock(box, id, spec)      Lock Window: holds a window still and lets the mouse through it
--
-- With the shared theme in use, the theme controls change it for every addon using winxi. Changes show
-- at once in the addon they are made in, and are saved (and so reach the others) when a control is let
-- go.
--
-- An addon should let its user leave the shared theme and set its own. For that it keeps two settings,
-- whether it uses the shared theme and a table for its own values, hands both to theme.Configure, and
-- gives widgets.Appearance two functions:
--     { onUseShared = function(useShared) ... end,   -- the checkbox was changed: keep and save the choice
--       onOwnChanged = function() ... end }          -- the addon's own theme was changed: save it
-- Given those, a "Use Shared Theme" checkbox heads the controls. Without them there is no checkbox and
-- the addon always follows the shared theme.
local imgui = require('imgui');
local theme = require('winxi.theme');
local anchor = require('winxi.anchor');
local fonts = require('winxi.fonts');
local window = require('winxi.window');
local tooltip = require('winxi.tooltip');
local statusicons = require('winxi.statusicons');

-- Every option's name has each word capitalised: "Shadow Opacity", not "Shadow opacity".
local widgets = {};

local dirty = false; -- the theme has been changed since it was last saved
local box = { 0 };   -- a number on its way in and out of a slider
local hooks = nil;   -- the functions given to the Appearance call being drawn

-- Saves the theme in use: the shared one to its file, the addon's own through the addon
local function Commit()
    if theme.IsShared() then
        theme.Save();
    elseif hooks and hooks.onOwnChanged then
        hooks.onOwnChanged();
    end
end

-- A change is saved once the mouse is up: at once for a click or a typed value, and on letting go for a
-- drag. Asking each control whether it had been let go missed changes made in a colour picker's popup,
-- which is not the control that opened it.
local function MouseIsUp()
    return not imgui.IsMouseDown(0);
end

local function AfterControl(changed)
    if changed then
        theme.Touch();
        dirty = true;
    end
end

-- Call once the theme's controls have been drawn
local function SaveIfChanged()
    if dirty and MouseIsUp() then
        dirty = false;
        Commit();
    end
end

local Tooltip = tooltip.Hover;

-- A setting's name goes to the left of its control, followed by a colon, and the controls line up in a
-- column to the right of the longest name. The widths are measured once per name.
--
-- The column is kept per group of settings, so that one tab's long names do not push another tab's
-- controls across: widgets.BeginLabels(key) starts a group, and every widgets.Label after it belongs to
-- that group until the next. widgets.Appearance starts one for the Appearance tab, which the addon's
-- own section then carries on.
local labelTexts = {};    -- name -> the name with its colon
local labelWidths = {};
local labelColumns = {};  -- group -> where its controls start, from the longest name seen in it
local labelGroup = 'default';
local labelGap = 10;      -- between the longest name and the controls

function widgets.BeginLabels(key)
    labelGroup = key or 'default';
end

-- An experimental setting says so before its name: [Experimental], in this colour, as every addon here
-- marks one
widgets.ExperimentalColor = { 1.0, 1.0, 0.0, 1.0 };

local experimentalTag = '[Experimental]';
local experimentalGap = 6;      -- between the tag and the name
local experimentalTagWidth = nil;
local experimentalWidths = {};  -- name -> how wide the tag, the name and its colon are together

-- Draws a setting's name and leaves the cursor where its control goes. Give the control a label that
-- shows nothing ('##something'). For an addon's own settings as well as winxi's, so that they line up.
-- experimental: true for a setting that is experimental, which is then tagged as one.
function widgets.Label(text, experimental)
    local shown = labelTexts[text];
    local width = labelWidths[text];
    if shown == nil then
        shown = text .. ':';
        width = imgui.CalcTextSize(shown);
        labelTexts[text], labelWidths[text] = shown, width;
    end

    if experimental then
        local tagged = experimentalWidths[text];
        if tagged == nil then
            experimentalTagWidth = experimentalTagWidth or imgui.CalcTextSize(experimentalTag);
            tagged = experimentalTagWidth + experimentalGap + width;
            experimentalWidths[text] = tagged;
        end
        width = tagged;
    end

    local startX = imgui.GetCursorPosX();
    local column = labelColumns[labelGroup] or 0;
    if startX + width + labelGap > column then
        column = startX + width + labelGap;
        labelColumns[labelGroup] = column;
    end

    imgui.AlignTextToFramePadding();
    if experimental then
        imgui.TextColored(widgets.ExperimentalColor, experimentalTag);
        imgui.SameLine(0, experimentalGap);
    end
    imgui.Text(shown);
    imgui.SameLine(column);
end

-- How wide the controls are, in text heights. ImGui's own width in a self-sizing window is 16, which
-- cuts the figures in a colour picker short; a self-sizing settings window grows to fit.
widgets.ControlWidth = 20;

-- Call before drawing settings and widgets.PopControlWidth after, for controls of the width above.
-- widgets.Appearance does so for its own; an addon does for its section, so the two match.
--
-- In a settings window that has been resized (winxi.window), the controls are no wider than the room
-- there is between the column they start in and the window's right edge, so that they fit it; never
-- narrower than widgets.ControlMinWidth text heights. A window fitting its content keeps the width
-- above, which is what it is fitted to.
widgets.ControlMinWidth = 5;

function widgets.PushControlWidth()
    local _, textHeight = imgui.CalcTextSize('A');
    textHeight = textHeight or 14;
    local width = textHeight * widgets.ControlWidth;
    local column = labelColumns[labelGroup];
    if window.IsResized() and column ~= nil then
        local room = imgui.GetCursorPosX() + (imgui.GetContentRegionAvail() or width) - column;
        width = math.max(textHeight * widgets.ControlMinWidth, math.min(width, room));
    end
    imgui.PushItemWidth(width);
end

function widgets.PopControlWidth()
    imgui.PopItemWidth();
end

-- A box of whole numbers sized to what goes in it, rather than to the controls around it: each field
-- is wide enough for digits figures (5 if not given) and its padding, with the gap between fields.
-- Meant for boxes without +/- buttons (InputInt with a step of 0, InputInt2).
function widgets.NumberWidth(fields, digits)
    fields = fields or 1;
    local textWidth = imgui.CalcTextSize(('0'):rep(digits or 5));
    local style = imgui.GetStyle();
    local field = textWidth + style.FramePadding.x * 2;
    return field * fields + style.ItemInnerSpacing.x * (fields - 1);
end

-- The space between one family of settings and the next (the colours, the padding, the drop shadow)
local familyGap = { 0, 5 };

function widgets.Gap()
    imgui.Dummy(familyGap);
end

-- A control's hidden label, by the setting it is for: made once per setting
local function Ids(prefix)
    return setmetatable({}, { __index = function(ids, key)
        local id = prefix .. key;
        ids[key] = id;
        return id;
    end });
end

local controlIds = Ids('##winxi.');
local fadeIds = Ids('##winxi.fade.');
local hideIds = Ids('##winxi.hide.');

local function Color(label, key, tooltip)
    widgets.Label(label);
    local changed = imgui.ColorEdit4(controlIds[key], theme.Get()[key]);
    Tooltip(tooltip);
    AfterControl(changed);
end

-- One of a style's choices (theme.BorderStyles and the like), as a dropdown
local dropdownIds = {}; -- key -> { the label of each choice }, made once

local function Choice(label, key, choices, tooltip)
    local current = theme.Get();
    widgets.Label(label);
    local chosen = choices[1];
    for _, choice in ipairs(choices) do
        if choice.key == current[key] then
            chosen = choice;
            break;
        end
    end
    local opened = imgui.BeginCombo(controlIds[key], chosen.label);
    Tooltip(tooltip);
    if opened then
        local labels = dropdownIds[key];
        if labels == nil then
            labels = {};
            dropdownIds[key] = labels;
        end
        for index, choice in ipairs(choices) do
            labels[index] = labels[index] or ('%s##winxi.%s.%d'):format(choice.label, key, index);
            local selected = choice.key == chosen.key;
            if imgui.Selectable(labels[index], selected) and not selected then
                current[key] = choice.key;
                AfterControl(true);
            end
            if selected then
                imgui.SetItemDefaultFocus();
            end
        end
        imgui.EndCombo();
    end
end

local function Check(label, key, tooltip)
    local current = theme.Get();
    widgets.Label(label);
    box[1] = current[key];
    local changed = imgui.Checkbox(controlIds[key], box);
    if changed then
        current[key] = box[1] and true or false;
    end
    Tooltip(tooltip);
    AfterControl(changed);
end

local function Slider(label, key, min, max, tooltip)
    local current = theme.Get();
    widgets.Label(label);
    box[1] = current[key];
    local changed = imgui.SliderInt(controlIds[key], box, min, max);
    if changed then
        current[key] = box[1];
    end
    Tooltip(tooltip);
    AfterControl(changed);
end

-- The title of a section of a settings window, with a blank line before it to set it apart from the
-- section above (pass first for the section that heads the tab). An addon's Winxi Theme tab has five:
-- Theme, Window, Font and Styles, which widgets.Appearance draws, and Addon, the addon's own, for whatever
-- else it has to set.
--
-- Every section can be collapsed: its title starts [-] while open and [+] while collapsed, and a click
-- on it changes which. widgets.Header returns whether it is open, and the section's settings are drawn
-- only then:
--     if widgets.Header('Window') then
--         ...
--     end
-- Which are collapsed is kept for as long as the addon is loaded, by the title within its group of
-- settings (widgets.BeginLabels). The title is in the theme's SettingsHeaderColor; widgets.HeaderColor
-- is the colour it starts as, for an addon's own text that wants it.
widgets.HeaderColor = { 1.0, 0.75, 0.55, 1.0 };

local collapsed = {};   -- group -> { title -> true while that section is collapsed }
local headerTexts = {}; -- title -> { as shown open, as shown collapsed }, made once

-- defaultCollapsed is optional; it affects only the first visit to this section.
function widgets.Header(text, first, defaultCollapsed)
    if not first then
        imgui.NewLine();
    end
    local shown = headerTexts[text];
    if shown == nil then
        shown = { '[-] ' .. text, '[+] ' .. text };
        headerTexts[text] = shown;
    end
    local group = collapsed[labelGroup];
    if group == nil then
        group = {};
        collapsed[labelGroup] = group;
    end

    if group[text] == nil and defaultCollapsed then group[text] = true; end
    local isCollapsed = group[text] == true;
    imgui.TextColored(theme.Get().SettingsHeaderColor or widgets.HeaderColor, isCollapsed and shown[2] or shown[1]);
    if imgui.IsItemHovered() and ImGuiMouseCursor_Hand ~= nil then
        imgui.SetMouseCursor(ImGuiMouseCursor_Hand);
    end
    if imgui.IsItemClicked() then
        isCollapsed = not isCollapsed;
        group[text] = isCollapsed;
    end
    return not isCollapsed;
end

local resetPopups = {
    game = { id = 'Reset Shared Theme?##winxi.reset', what = 'the colours, padding, drop shadow, font and styles of the windows on the game screen' },
    settings = { id = 'Reset Settings Windows?##winxi.resetSettings', what = 'the colours, padding and font of the settings windows' },
    icons = { id = 'Reset Icons?##winxi.resetIcons', what = 'the icons' },
    tooltips = { id = 'Reset Tooltips?##winxi.resetTooltips', what = 'the look and delay of the tooltips' },
};
local resetPopupOpen = { true };
local resetPopupFlags = nil;

-- Asks before the shared theme is reset, since that changes every addon using it. Returns true on the
-- frame the reset is confirmed.
local function ConfirmSharedReset(popup)
    local confirmed = false;

    -- a modal where there is one; an ordinary popup otherwise
    local begun;
    if imgui.BeginPopupModal ~= nil then
        resetPopupFlags = resetPopupFlags or ImGuiWindowFlags_AlwaysAutoResize;
        resetPopupOpen[1] = true;
        begun = imgui.BeginPopupModal(popup.id, resetPopupOpen, resetPopupFlags);
    else
        begun = imgui.BeginPopup(popup.id);
    end

    if begun then
        imgui.Text(('This puts %s back to their defaults'):format(popup.what));
        imgui.Text('for every addon that uses the shared theme.');
        imgui.Separator();

        if imgui.Button('Reset##winxi.reset.confirm') then
            confirmed = true;
            imgui.CloseCurrentPopup();
        end
        imgui.SameLine();
        if imgui.Button('Cancel##winxi.reset.cancel') then
            imgui.CloseCurrentPopup();
        end
        imgui.EndPopup();
    end

    return confirmed;
end

-- The reset button of a part of the theme: theme.GameWindowKeys or theme.SettingsWindowKeys. An addon's
-- own theme is reset at once. The shared one is everyone's, so that is confirmed first.
local function ResetButton(label, popup, keys, tooltipShared, tooltipOwn)
    local shared = theme.IsShared();
    if imgui.Button(label) then
        if shared then
            imgui.OpenPopup(popup.id);
        else
            theme.Reset(keys);
            theme.Touch();
            Commit();
        end
    end
    Tooltip(shared and tooltipShared or tooltipOwn);

    if ConfirmSharedReset(popup) then
        theme.Reset(keys);
        theme.Touch();
        Commit();
    end
end

-- A font of C:\Windows\Fonts, by its file, and its size: FontFile and FontSize, the settings windows'
-- own, or the titles'. names, if given: { the font's label, the size's label, what '' is called }.
local fontNames = { 'Font', 'Font Size', 'Default' };
local titleFontNames = { 'Title Font', 'Title Size', 'Window Font' };

local function FontChoice(fileKey, sizeKey, fileTooltip, sizeTooltip, names)
    names = names or fontNames;
    local current = theme.Get();
    widgets.Label(names[1]);
    local file = current[fileKey];
    local opened = imgui.BeginCombo(controlIds[fileKey], file ~= '' and file or names[3]);
    Tooltip(fileTooltip);
    if opened then
        if imgui.Selectable(names[3] .. controlIds[fileKey .. '.default'], file == '') and file ~= '' then
            current[fileKey] = '';
            AfterControl(true);
        end
        for _, choice in ipairs(fonts.Files()) do
            if imgui.Selectable(choice, file == choice) and file ~= choice then
                current[fileKey] = choice;
                AfterControl(true);
            end
        end
        imgui.EndCombo();
    end
    widgets.Label(names[2]);
    box[1] = current[sizeKey];
    local resized = imgui.SliderInt(controlIds[sizeKey], box, 0, theme.MaxFontSize, current[sizeKey] > 0 and '%d px' or 'Default');
    if resized then
        current[sizeKey] = box[1];
    end
    Tooltip(sizeTooltip);
    AfterControl(resized);
end

-- Custom Icons: None (the game's own) or one of the sets, the folders of libs\winxi\statusicons. The
-- folders are looked for when the list is opened, so that one just added is there to choose.
local iconSets = nil;   -- statusicons.Sets(), as last looked for
local iconLabels = {};  -- set -> its label in the list, made once
local noIcons = { key = '', label = 'None' };

local function IconSetLabel(set)
    local label = iconLabels[set.key];
    if label == nil then
        label = ('%s##winxi.StatusIconSet.%s'):format(set.label, set.key);
        iconLabels[set.key] = label;
    end
    return label;
end

local function StatusIcons()
    local current = theme.Get();
    iconSets = iconSets or statusicons.Sets();
    local chosen = noIcons;
    if current.StatusIcons then
        chosen = { key = current.StatusIconSet, label = current.StatusIconSet };
        for _, set in ipairs(iconSets) do
            if set.key == current.StatusIconSet then
                chosen = set;
                break;
            end
        end
    end

    widgets.Label('Custom Icons');
    local opened = imgui.BeginCombo(controlIds.StatusIconSet, chosen.label);
    Tooltip('The icons buffs and debuffs are drawn with, in addons that follow this setting (the party addon, buff and name): a set of custom icons, for every status the set has one for, or None for the game\'s own.\nA set is a folder of libs\\winxi\\statusicons holding <status number>.png for each status it has an icon for, 1.png for Poison and so on; add a folder there and it is in this list. FFXIV is the set winxi comes with.');
    if opened then
        iconSets = statusicons.Sets();
        local changed = false;
        if imgui.Selectable('None##winxi.StatusIconSet.none', chosen == noIcons) and chosen ~= noIcons then
            current.StatusIcons = false;
            changed = true;
        end
        for _, set in ipairs(iconSets) do
            local selected = current.StatusIcons and set.key == current.StatusIconSet;
            if imgui.Selectable(IconSetLabel(set), selected) and not selected then
                current.StatusIcons, current.StatusIconSet = true, set.key;
                changed = true;
            end
        end
        imgui.EndCombo();
        AfterControl(changed);
    end
end

-- The icons' values: which custom icons statuses have, if any. hooks as for widgets.SettingsAppearance.
function widgets.IconAppearance(appearanceHooks)
    hooks = appearanceHooks;
    widgets.BeginLabels('winxi.iconAppearance');
    widgets.PushControlWidth();

    if widgets.Header('HQ Icons', true) then
        StatusIcons();
    end

    widgets.Gap();
    ResetButton('Reset Icons', resetPopups.icons, theme.IconKeys,
        'Puts the icons back as they started, for every addon using the shared theme.',
        'Puts this addon\'s own icons back as they started.');

    SaveIfChanged();
    widgets.PopControlWidth();
end

-- The Theme section (whether this addon uses the shared theme), and for the windows on the game
-- screen the Window section (the colours, padding and drop shadow of whichever theme is in use), the
-- Font section (the font and its size) and the Styles section (its border art, titles, bars and status
-- icons). An addon follows it with a section of its own. The settings windows' own values are
-- widgets.SettingsAppearance's. parts, if given: { icons = false } leaves out the icons, for a window
-- that has widgets.IconAppearance elsewhere.
local gameKeysWithoutIcons = nil; -- theme.GameWindowKeys but the icons': made once

function widgets.Appearance(appearanceHooks, parts)
    hooks = appearanceHooks;
    local withIcons = parts == nil or parts.icons ~= false;
    widgets.BeginLabels('winxi.appearance');
    widgets.PushControlWidth();

    -- Only an addon that can keep a theme of its own offers the choice
    local offersChoice = hooks ~= nil and hooks.onUseShared ~= nil;
    if offersChoice and widgets.Header('Theme', true) then
        widgets.Label('Use Shared Theme');
        box[1] = theme.IsShared();
        if imgui.Checkbox('##winxi.UseSharedTheme', box) then
            hooks.onUseShared(box[1] and true or false);
        end
        Tooltip('On: this addon looks like every other addon that uses the shared theme, and changes made here change them all.\nOff: this addon keeps colours, padding and shadow of its own, starting from the shared ones.');
    end

    local current = theme.Get();

    -- Three families of settings, a little apart: the colours, the padding, the drop shadow
    if widgets.Header('Window', not offersChoice) then
        Color('Background Color', 'BackgroundColor', 'The background of every window on the game screen.');
        Color('Border Color', 'BorderColor', 'The border of every window on the game screen. Tabs, buttons, sliders and other controls in them are tinted from it.');
        Color('Text Color', 'TextColor');
        Color('Highlight Color', 'HighlightColor', 'The tab that is chosen, and the line drawn under its row of tabs, in a window on the game screen.');

        widgets.Gap();
        Slider('Padding', 'Padding', 0, theme.MaxPadding, 'Space between a window\'s border and its content, the same on every side.');

        widgets.Gap();
        widgets.Label('Drop Shadow');
        box[1] = current.ShadowEnabled;
        if imgui.Checkbox('##winxi.ShadowEnabled', box) then
            current.ShadowEnabled = box[1] and true or false;
            theme.Touch();
            Commit();
        end
        Tooltip('Draws a soft shadow behind each window on the game screen, down and to the right of it. Settings windows have none.');

        if current.ShadowEnabled then
            Slider('Shadow Offset', 'ShadowOffset', 0, 20);
            Slider('Shadow Softness', 'ShadowBlur', 0, 20);
            Slider('Shadow Opacity (%)', 'ShadowOpacity', 0, 100);
        end
    end

    -- The font every window is written in, where its addon does not choose one of its own, and the
    -- edge round text written over a bar or the game
    if widgets.Header('Font') then
        FontChoice('FontFile', 'FontSize',
            'The font every window on the game screen drawn with winxi is written in: a font of Windows\' own, by its file in C:\\Windows\\Fonts. Default is imgui\'s own.\nA font or size an addon sets for its own text is used in place of this one.',
            'How big the text of every window on the game screen is, in pixels. 0 (Default) keeps the base size.\nAn addon that sets sizes of its own (the party addon\'s names and values, for one) keeps them.');
        widgets.Gap();
        Slider('Text Outline', 'TextOutline', 0, theme.MaxTextOutline, 'How thick the dark edge round text written over a bar, an image or the game itself is, in pixels, in every addon that writes with winxi: the party addon\'s names and figures, a clock\'s line, scrolling text, zone banners. 0 is none.');
        Color('Outline Color', 'TextOutlineColor', 'The colour of that edge, and how solid it is.');
    end

    -- The styles: the window border for every window, and what an addon that draws bars or statuses
    -- draws them with
    if widgets.Header('Styles') then
        Choice('Window Border', 'BorderStyle', theme.BorderStyles, 'Thin 3px borders in place of the plain window border, on every window on the game screen. Keeps the background colour; use at least 3px padding to keep content clear of the edging. Settings windows keep the plain border.');
        Choice('Window Background', 'BackgroundStyle', theme.BackgroundStyles, 'A texture in place of the flat background, on every window on the game screen, in the Background Color: a gradient, the FFXI-inspired gradient with fine lines, stone grain, marble veins, a linen weave or brushed metal. Settings windows keep the flat background.');
        Choice('Tab Style', 'TabStyle', theme.TabStyles, 'A texture over the tabs of every window on the game screen that has them (the inventory\'s bags, mark\'s pages), keeping their colours: Plain is none, Sheen a soft light at the top and shade at the foot, Glass a bright upper half, Bevel raised edges, then brushed metal, stone grain, the FFXI-inspired fine lines or soft satin folds. Settings windows keep plain tabs.');
        Slider('Border Opacity (%)', 'BorderOpacity', 0, 100, 'How solid the border of every window on the game screen is, plain or styled: 100 is solid, 0 is no border. Settings windows keep a solid border.');
        widgets.Gap();
        Check('Frame Titles', 'FrameTitles', 'Writes the name of each window on the game screen across its top edge, at the right, in addons that name their windows (the party addon: Party, Target and the rest). Settings windows keep their own title bar.');
        if current.FrameTitles then
            Choice('Title Style', 'TitleStyle', theme.TitleStyles, 'Outlined Text is the name alone, over the border, with a dark edge. Break In Border leaves a gap in the border for it; Break With Shadow does too, with a soft dark haze behind the name and a slight shadow under it. Plate sets it on a small plate of the Background Color, edged in the Border Color.');
            Color('Title Color', 'TitleColor');
            Check('Title All Caps', 'TitleAllCaps', 'Writes every title in capitals: PARTY, TARGET and the rest.');
            FontChoice('TitleFontFile', 'TitleSize',
                'The font the titles are written in: a font of Windows\' own, by its file in C:\\Windows\\Fonts. Window Font is the window\'s own.',
                'How big the titles are, in pixels. 0 (Default) is the size of the window\'s own text.', titleFontNames);
            Slider('Title Position X', 'TitleOffsetX', -50, theme.MaxTitleOffsetX, 'How far in from the window\'s right edge the title ends, in pixels. Below 0 it runs past the edge.');
            Slider('Title Position Y', 'TitleOffsetY', -theme.MaxTitleOffsetY, theme.MaxTitleOffsetY, 'How far down the title is moved, in pixels, from sitting across the top edge. Below 0 moves it up, clear of the window.');
            Check('Title Shadow', 'TitleShadow', 'A soft dark copy of the title, down and to the right of it.');
            if current.TitleShadow then
                Slider('Title Shadow Offset', 'TitleShadowOffset', 1, 6, 'How far down and to the right the shadow falls, in pixels.');
                Slider('Title Shadow Opacity (%)', 'TitleShadowOpacity', 0, 100, 'How dark the shadow is: 100 is solid, 0 is none.');
            end
        end
        widgets.Gap();
        Choice('Bar Texture', 'BarTexture', theme.BarTextures, 'Matching HP and MP textures, for addons that draw HP and MP bars (the party addon): original, glossy glass, detailed metal, faceted crystal, soft satin, runic markings, a classic FF-style bevel, a brighter Radiant fill, polished chrome, plain flat, ten-cell segmented, a glowing ember, Kingdom console-menu bevels, Magitek machinery, Aether shards, Elven curved rails, Gothic ironwork, or the smooth ones, shaded from top to foot with nothing along the bar so that they look the same at any HP: Enamel (a bright upper half over a deeper one, as the game\'s own bars), Enamel (Lit Rim), Enamel (Gradient), Glass Tube, Glass Tube (Deep) and Glass Enamel. Keeps HP/MP colour tinting.');
        Choice('Bar Frame', 'BarFrame', theme.BarFrames, 'The frame round the HP and MP bars of the party addon. Bar Texture is the texture\'s own. Capsule Outline is a thin rim in the cyan of the Rounded bookends, Capsule Outline (Silver) in Rounded Silver\'s, in place of the texture\'s frame and not tinted by the bar: with those bookends the bar and its caps are one capsule being filled. Without them its ends are closed square.');
        Slider('Bar Frame Opacity (%)', 'BarFrameOpacity', 0, 100, 'How solid the frame round the party addon\'s HP and MP bars is, the Capsule Outline or the texture\'s own: 100 is solid, 0 is none.');
        Slider('Fill End Glow (%)', 'BarGlow', 0, 100, 'A soft light at the end of the HP and MP fills, where each stops, as on the game\'s own gauges: 0 is none, 100 the brightest.');
        Check('Custom Bar Backdrop', 'BarBackdrop', 'The empty part of the HP and MP bars in a colour of your own. Off, it is the bar\'s own colour, darkened.');
        if current.BarBackdrop then
            Color('Bar Backdrop Color', 'BarBackdropColor', 'The colour of the empty part of the HP and MP bars. Its alpha lets the dark trough under it show through.');
        end
        Check('Bar Bookends', 'Bookends', 'Puts a small cap at each end of the HP and MP bars.');
        if current.Bookends then
            Choice('Bookend Style', 'BookendStyle', theme.BookendStyles, 'Separate coloured ornaments for HP and MP: matching window borders, Kingdom crowns, Magitek couplings, Aether shards, Elven leaves, and Gothic lances, or Rounded and Rounded Silver, round ends after the game\'s own that carry the bar on past each end. Match Border follows the Window Border; with the Theme border it uses the bar texture cap.');
            Slider('Bookend Opacity (%)', 'BookendOpacity', 0, 100, 'How solid the bookends are: 100 is solid, 0 is none.');
        end
        if withIcons then
            widgets.Gap();
            StatusIcons();
        end
    end

    local resetKeys = theme.GameWindowKeys;
    if not withIcons then
        if gameKeysWithoutIcons == nil then
            local icons = {};
            for _, key in ipairs(theme.IconKeys) do icons[key] = true; end
            gameKeysWithoutIcons = {};
            for _, key in ipairs(theme.GameWindowKeys) do
                if not icons[key] then gameKeysWithoutIcons[#gameKeysWithoutIcons + 1] = key; end
            end
        end
        resetKeys = gameKeysWithoutIcons;
    end
    widgets.Gap();
    ResetButton('Reset Appearance', resetPopups.game, resetKeys,
        'Puts the colours, padding, shadow, font and styles of the windows on the game screen back as they started, for every addon using the shared theme.',
        'Puts this addon\'s own colours, padding, shadow, font and styles back as they started.');

    SaveIfChanged();
    widgets.PopControlWidth();
end

-- The settings windows' own values (winxi.window's settings kind): the Window section (their colours,
-- the Winxi Theme tab's and their padding) and the Font section (their font and its size). Apart from
-- the game screen's, so that what is set for those does not change the window it is set in. hooks
-- as for widgets.Appearance, but for the checkbox, which is Appearance's alone.
function widgets.SettingsAppearance(appearanceHooks)
    hooks = appearanceHooks;
    widgets.BeginLabels('winxi.settingsAppearance');
    widgets.PushControlWidth();

    if widgets.Header('Window', true) then
        Color('Background Color', 'SettingsBackgroundColor', 'The background of every settings window.');
        Color('Border Color', 'SettingsBorderColor', 'The border of every settings window. Tabs, buttons, sliders and other controls in them are tinted from it.');
        Color('Text Color', 'SettingsTextColor');
        Color('Highlight Color', 'SettingsHighlightColor', 'The tab that is chosen, and the line drawn under its row of tabs.');
        Color('Sub-Category Color', 'SettingsHeaderColor', 'The titles of the sections in every settings window, the ones that collapse with [-] and [+].');
        Color('Theme Tab Color', 'ThemeTabColor', 'The colour of the Winxi Theme tab, which sets it apart from the addon\'s own tabs. It is a little darker when not chosen, and lighter under the mouse.');

        widgets.Gap();
        Slider('Padding', 'SettingsPadding', 0, theme.MaxSettingsPadding, 'Space between a settings window\'s border and its content, the same on every side.');
    end

    if widgets.Header('Font') then
        FontChoice('SettingsFontFile', 'SettingsFontSize',
            'The font every settings window is written in: a font of Windows\' own, by its file in C:\\Windows\\Fonts. Default is imgui\'s own.',
            'How big the text of every settings window is, in pixels. 0 (Default) keeps the base size.');
    end

    widgets.Gap();
    ResetButton('Reset Settings Windows', resetPopups.settings, theme.SettingsWindowKeys,
        'Puts the colours, padding and font of the settings windows back as they started, for every addon using the shared theme.',
        'Puts this addon\'s own settings window colours, padding and font back as they started.');

    SaveIfChanged();
    widgets.PopControlWidth();
end

-- Every tooltip's values (winxi.tooltip): whether they show, how soon, their colours, padding, text
-- size and width. Tooltips are always the shared theme's, so this is for winxisettings, which follows it.
local tooltipSample = 'A tooltip looks like this. Its words go on to another line once they reach the Max Width set above, so a long one stays readable.';

function widgets.TooltipAppearance()
    hooks = nil;
    widgets.BeginLabels('winxi.tooltipAppearance');
    widgets.PushControlWidth();

    if widgets.Header('Tooltips', true) then
        Check('Show Tooltips', 'TooltipsEnabled', 'Off, no tooltip of any addon drawn with winxi is shown, this one included.');
        Slider('Delay (ms)', 'TooltipDelay', 0, theme.MaxTooltipDelay, 'How long the mouse rests on something before its tooltip shows, in milliseconds. Moving straight on to the next thing shows its tooltip at once.');
    end

    if widgets.Header('Window') then
        Color('Background Color', 'TooltipBackgroundColor', 'The background of every tooltip.');
        Color('Border Color', 'TooltipBorderColor', 'The border of every tooltip.');
        Color('Text Color', 'TooltipTextColor');
        widgets.Gap();
        Slider('Padding', 'TooltipPadding', 0, theme.MaxTooltipPadding, 'Space between a tooltip\'s border and its words, the same on every side.');
        Slider('Max Width', 'TooltipMaxWidth', theme.MinTooltipWidth, theme.MaxTooltipWidth, 'How wide a tooltip grows, in pixels, before its words go on to another line.');
        widgets.Label('Font Size');
        local current = theme.Get();
        box[1] = current.TooltipFontSize;
        local resized = imgui.SliderInt(controlIds.TooltipFontSize, box, 0, theme.MaxFontSize, current.TooltipFontSize > 0 and '%d px' or 'Window\'s Own');
        if resized then
            current.TooltipFontSize = box[1];
        end
        Tooltip('How big a tooltip\'s text is, in pixels. 0 (Window\'s Own) is the size of the window it is over.');
        AfterControl(resized);

        widgets.Gap();
        widgets.Label('Sample');
        imgui.TextDisabled('(?)');
        Tooltip(tooltipSample);
    end

    widgets.Gap();
    ResetButton('Reset Tooltips', resetPopups.tooltips, theme.TooltipKeys,
        'Puts every tooltip\'s look and delay back as they started, for every addon using winxi.',
        'Puts every tooltip\'s look and delay back as they started.');

    SaveIfChanged();
    widgets.PopControlWidth();
end

-- The Winxi Theme tab: the one that holds widgets.Appearance, in every addon's settings window. It is
-- the last tab, held against the right edge of its tab bar, and coloured apart from the addon's own
-- tabs: in the theme's ThemeTabColor when chosen, a little darker when not, and lighter under the
-- mouse. Call in place of imgui.BeginTabItem, and EndThemeTab where EndTabItem would go.
widgets.ThemeTabLabel = 'Winxi Theme';

-- Each slot of a tab, and how its colour is made from the theme's: { brightness, opacity }. Each slot
-- by its name since imgui 1.90.9 (Ashita's is 1.92), then its name before that.
local themeTabShades = {
    { 'Tab', 0.8, 0.85 }, { 'TabHovered', 1.2, 1.0 }, { 'TabSelected/TabActive', 1.0, 1.0 },
    { 'TabSelectedOverline', 1.0, 1.0 }, { 'TabDimmed/TabUnfocused', 0.8, 0.6 },
    { 'TabDimmedSelected/TabUnfocusedActive', 1.0, 0.85 }, { 'TabDimmedSelectedOverline', 1.0, 0.85 },
};
local themeTabColors = nil;     -- { slot, colour, brightness, opacity }, made once imgui's slots are certain to be defined
local themeTabVersion = -1;     -- the theme's version they were last coloured for

function widgets.BeginThemeTab()
    if themeTabColors == nil then
        themeTabColors = {};
        for _, shade in ipairs(themeTabShades) do
            local slot = nil;
            for name in shade[1]:gmatch('[^/]+') do
                slot = slot or _G['ImGuiCol_' .. name];
            end
            if slot ~= nil then
                themeTabColors[#themeTabColors + 1] = { slot, { 0, 0, 0, 0 }, shade[2], shade[3] };
            end
        end
    end
    if themeTabVersion ~= theme.Version() then
        themeTabVersion = theme.Version();
        local base = theme.Get().ThemeTabColor;
        for _, entry in ipairs(themeTabColors) do
            local color, brightness = entry[2], entry[3];
            for channel = 1, 3 do
                color[channel] = math.min(1, base[channel] * brightness);
            end
            color[4] = base[4] * entry[4];
        end
    end
    for _, entry in ipairs(themeTabColors) do
        imgui.PushStyleColor(entry[1], entry[2]);
    end
    local open = imgui.BeginTabItem(widgets.ThemeTabLabel, 0, ImGuiTabItemFlags_Trailing or 0);
    imgui.PopStyleColor(#themeTabColors);
    return open;
end

function widgets.EndThemeTab()
    imgui.EndTabItem();
end

-- The corner a window grows from, as four buttons laid out as the corners themselves are. current is
-- the present choice. Returns the newly chosen corner, or nil if it was not changed.
-- From the left of the first column of corners to the left of the second: the widest option in the
-- first column (its button, which is about as wide as the text is tall, and its name), then a gap.
-- Measured rather than fixed, so the two columns stay apart at any font size.
local growFromGap = 24;
local growFromColumn = nil;
local growFromIds = {}; -- corner -> its button's label: made once

local function GrowFromColumn()
    if growFromColumn == nil then
        local widest, textHeight = 0, 14;
        for index, mode in ipairs(anchor.Modes) do
            if index % 2 == 1 then
                local width, height = imgui.CalcTextSize(anchor.Labels[mode]);
                widest = math.max(widest, width or 0);
                textHeight = height or textHeight;
            end
        end
        growFromColumn = widest + textHeight * 2 + growFromGap;
    end
    return growFromColumn;
end

function widgets.GrowFrom(current)
    if anchor.Labels[current] == nil then
        current = anchor.Default;
    end

    -- two to a row, the top corners then the bottom ones, starting wherever the cursor is: after
    -- widgets.Label, that is the column the other controls are in
    local left = imgui.GetCursorPosX();
    local chosen = nil;
    for index, mode in ipairs(anchor.Modes) do
        if index % 2 == 0 then
            imgui.SameLine(left + GrowFromColumn());
        elseif index > 1 then
            imgui.SetCursorPosX(left);
        end
        local id = growFromIds[mode];
        if id == nil then
            id = anchor.Labels[mode] .. '##winxi.growfrom';
            growFromIds[mode] = id;
        end
        if imgui.RadioButton(id, current == mode) and current ~= mode then
            chosen = mode;
        end
        Tooltip('The corner that stays where it is when the window\'s content changes size: it grows away from that corner.');
    end
    return chosen;
end

-- A font of the addon's own, for the text an addon writes itself (a clock's line, a bar's figures,
-- scrolling text): the theme's font and size unless the addon's settings say otherwise, as every
-- winxi addon offers it. The settings are a file name, '' for the theme's font, and a size in a table
-- (as imgui's sliders take), 0 for the theme's size.
--
--   widgets.FontFile(options, key, id, spec)   the combo: Theme Font, then every .ttf of C:\Windows\Fonts
--   widgets.FontSize(options, key, id, spec)   the slider: Theme Size at 0, or pixels
--
-- options[key] is the setting; id the control's hidden label ('##buff.fontFile'). spec, each optional:
--   label     the setting's name to its left: Font, or Font Size; false for none, where the addon has
--             written one already
--   tooltip   over the control
--   theme     what the theme's own is called: Theme Font, or Theme Size
--   min, max  the size's range: 0 and theme.MaxFontSize. Only a range from 0 offers the theme's size.
-- Both return whether the setting was changed this frame. FontSize returns as well whether the slider
-- was let go after a change, for an addon that saves then rather than as it is dragged.
local noSpec = {};

function widgets.FontFile(options, key, id, spec)
    spec = spec or noSpec;
    local file = options[key];
    if type(file) ~= 'string' then file = ''; end
    local themeLabel = spec.theme or 'Theme Font';
    if spec.label ~= false then widgets.Label(spec.label or 'Font'); end
    local opened = imgui.BeginCombo(id, file ~= '' and file or themeLabel);
    Tooltip(spec.tooltip);
    local changed = false;
    if opened then
        if imgui.Selectable(themeLabel .. id .. '.theme', file == '') and file ~= '' then
            options[key] = '';
            changed = true;
        end
        for _, choice in ipairs(fonts.Files()) do
            if imgui.Selectable(choice .. id .. '.' .. choice, file == choice) and file ~= choice then
                options[key] = choice;
                changed = true;
            end
        end
        imgui.EndCombo();
    end
    return changed;
end

function widgets.FontSize(options, key, id, spec)
    spec = spec or noSpec;
    local low, high = spec.min or 0, spec.max or theme.MaxFontSize;
    if spec.label ~= false then widgets.Label(spec.label or 'Font Size'); end
    local size = options[key];
    local format = (low <= 0 and (tonumber(size[1]) or 0) <= 0) and (spec.theme or 'Theme Size') or '%d px';
    local changed = imgui.SliderInt(id, size, low, high, format);
    local done = imgui.IsItemDeactivatedAfterEdit() and true or false;
    Tooltip(spec.tooltip);
    return changed, done;
end

-- Lock Window: a window held where it is, the mouse going through it to the game (winxi.window's
-- locked and clickThrough options, or the addon's own flags). box is the setting, a table holding
-- true or false; id the control's hidden label. spec, each optional: label (Lock Window), tooltip, and
-- onChanged, called with the new value. Returns whether it was changed.
function widgets.Lock(box, id, spec)
    spec = spec or noSpec;
    widgets.Label(spec.label or 'Lock Window');
    local changed = imgui.Checkbox(id, box);
    Tooltip(spec.tooltip or 'Keeps the window where it is, and lets the mouse through it to the game. Off, it can be dragged.');
    if changed and spec.onChanged then
        spec.onChanged(box[1] and true or false);
    end
    return changed;
end

local fadeDirty = false; -- a fade setting has been changed since the addon was last told

local function FadeCheck(settings, label, key, tooltip)
    widgets.Label(label);
    box[1] = settings[key];
    if imgui.Checkbox(fadeIds[key], box) then
        settings[key] = box[1] and true or false;
        fadeDirty = true;
    end
    Tooltip(tooltip);
end

local function FadeNumber(settings, label, key, min, max, format, tooltip)
    widgets.Label(label);
    box[1] = settings[key];
    local changed;
    if format then
        changed = imgui.SliderFloat(fadeIds[key], box, min, max, format);
    else
        changed = imgui.SliderInt(fadeIds[key], box, min, max);
    end
    if changed then
        settings[key] = box[1];
        fadeDirty = true;
    end
    Tooltip(tooltip);
end

-- The controls for an addon's idle-fade settings (a table as winxi.fade describes). onChanged, if given,
-- is called when a change is final (the mouse is up), for the addon to save its settings.
-- grouped optionally splits the detailed controls into collapsible sections.
function widgets.Fade(settings, onChanged, grouped)
    FadeCheck(settings, 'Fade When Idle', 'Enabled', 'Fades the windows out once you have stood still for a while, and brings them back as soon as you move.');

    if settings.Enabled then
        if not grouped or widgets.Header('Timing And Opacity') then
        FadeNumber(settings, 'Idle Time (Seconds)', 'Delay', 1, 120, nil, 'How long you must stand still before the fade starts.');
        FadeNumber(settings, 'Idle Fade Time (Seconds)', 'Duration', 0, 5, '%.1f', 'How long the windows take to fade out once you are idle.');
        FadeNumber(settings, 'Fade In/Out Time (Seconds)', 'Transition', 0, 1, '%.2f', 'How long a window takes to fade in as it appears, out as it goes, and back in when you stop being idle.\nOne speed for every window. At 0 they appear and go at once.');
        FadeNumber(settings, 'Faded Opacity (%)', 'Opacity', 0, 100, nil, 'How visible a faded window stays. At 0 it disappears completely.');
        end
        if not grouped or widgets.Header('Keep Frames Visible') then
        FadeCheck(settings, 'Stay Visible While Moving', 'Moving', 'Moving about does not count as idle. Switched off, the windows fade on the move as well, once nothing else has kept them up for the idle time.');
        FadeCheck(settings, 'Show On Party Changes', 'Party', 'A change to the party list brings the windows back: someone joining, leaving or changing area.');
        FadeCheck(settings, 'Stay Visible While Engaged', 'Combat', 'Standing still with your weapon drawn does not count as idle.');
        FadeCheck(settings, 'Stay Visible While Targeting', 'Target', 'Having anything targeted does not count as idle: the windows come back as soon as you target something, or your target changes.');
        FadeCheck(settings, 'Stay Visible While Missing HP', 'MissingHp', 'Standing still below full HP does not count as idle.');
        FadeCheck(settings, 'Stay Visible While Healing', 'Resting', 'Resting to recover HP and MP (/heal) does not count as idle.');
        end
    end

    if fadeDirty and MouseIsUp() then
        fadeDirty = false;
        if onChanged then
            onChanged();
        end
    end
end

local hideDirty = false; -- a hide rule has been changed since the addon was last told

local function HideCheck(settings, label, key, tooltip)
    widgets.Label(label);
    box[1] = settings[key];
    if imgui.Checkbox(hideIds[key], box) then
        settings[key] = box[1] and true or false;
        hideDirty = true;
    end
    Tooltip(tooltip);
end

-- The controls for an addon's rules for getting its windows out of the way (a table as winxi.game
-- describes). onChanged, if given, is called when a change is final, for the addon to save its settings.
function widgets.Hide(settings, onChanged)
    HideCheck(settings, 'Hide While Map Open', 'UnderMap', 'The windows are not drawn while the map is open.');
    HideCheck(settings, 'Hide While Chat Open', 'UnderChat', 'The windows are not drawn while the chat log is opened right out.');
    HideCheck(settings, 'Hide While Loading', 'WhileLoading', 'The windows are not drawn while changing area.');
    HideCheck(settings, 'Hide During Events', 'DuringEvent', 'The windows are not drawn during cutscenes and while talking to an NPC.');
    HideCheck(settings, 'Hide With Game Interface', 'WithInterface', 'The windows are not drawn while the game\'s own interface is hidden.');

    if hideDirty and MouseIsUp() then
        hideDirty = false;
        if onChanged then
            onChanged();
        end
    end
end

return widgets;

