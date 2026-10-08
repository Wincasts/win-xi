-- winxi.widgets: ready-made controls for an addon's settings window.
--
--   widgets.Appearance(hooks)        the Theme and Window sections of an Appearance tab
--   widgets.Header(text)             a section title, for the addon's own section after those
--   widgets.Label(text)              a setting's name, to the left of its control, in line with winxi's
--   widgets.BeginLabels(key)         starts a group of settings whose controls line up with each other
--   widgets.Gap()                    the space between one family of settings and the next
--   widgets.PushControlWidth() / PopControlWidth()   around an addon's own settings, to match winxi's
--   widgets.GrowFrom(current)        four buttons for a window's corner; returns the new choice or nil
--   widgets.Fade(settings, onChanged) the controls for fading while idle (see winxi.fade)
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

local function Tooltip(text)
    if text and imgui.IsItemHovered() then
        imgui.SetTooltip(text);
    end
end

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

-- Draws a setting's name and leaves the cursor where its control goes. Give the control a label that
-- shows nothing ('##something'). For an addon's own settings as well as winxi's, so that they line up.
function widgets.Label(text)
    local shown = labelTexts[text];
    local width = labelWidths[text];
    if shown == nil then
        shown = text .. ':';
        width = imgui.CalcTextSize(shown);
        labelTexts[text], labelWidths[text] = shown, width;
    end

    local startX = imgui.GetCursorPosX();
    local column = labelColumns[labelGroup] or 0;
    if startX + width + labelGap > column then
        column = startX + width + labelGap;
        labelColumns[labelGroup] = column;
    end

    imgui.AlignTextToFramePadding();
    imgui.Text(shown);
    imgui.SameLine(column);
end

-- How wide the controls are, in text heights. ImGui's own width in a self-sizing window is 16, which
-- cuts the figures in a colour picker short; a self-sizing settings window grows to fit.
widgets.ControlWidth = 20;

-- Call before drawing settings and widgets.PopControlWidth after, for controls of the width above.
-- widgets.Appearance does so for its own; an addon does for its section, so the two match.
function widgets.PushControlWidth()
    local _, textHeight = imgui.CalcTextSize('A');
    imgui.PushItemWidth((textHeight or 14) * widgets.ControlWidth);
end

function widgets.PopControlWidth()
    imgui.PopItemWidth();
end

-- The space between one family of settings and the next (the colours, the padding, the drop shadow)
local familyGap = { 0, 5 };

function widgets.Gap()
    imgui.Dummy(familyGap);
end

-- A control's hidden label, by the setting it is for: made once per setting
local controlIds = setmetatable({}, { __index = function(ids, key)
    local id = '##winxi.' .. key;
    ids[key] = id;
    return id;
end });

local function Color(label, key, tooltip)
    widgets.Label(label);
    local changed = imgui.ColorEdit4(controlIds[key], theme.Get()[key]);
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
-- section above (pass first for the section that heads the tab). An addon's Appearance tab has three:
-- Theme and Window, which widgets.Appearance draws, and Addon, the addon's own, for whatever else it
-- has to set.
widgets.HeaderColor = { 1.0, 0.75, 0.55, 1.0 };

function widgets.Header(text, first)
    if not first then
        imgui.NewLine();
    end
    imgui.TextColored(widgets.HeaderColor, text);
end

local resetPopup = 'Reset Shared Theme?##winxi.reset';
local resetPopupOpen = { true };
local resetPopupFlags = nil;

-- Asks before the shared theme is reset, since that changes every addon using it. Returns true on the
-- frame the reset is confirmed.
local function ConfirmSharedReset()
    local confirmed = false;

    -- a modal where there is one; an ordinary popup otherwise
    local begun;
    if imgui.BeginPopupModal ~= nil then
        resetPopupFlags = resetPopupFlags or ImGuiWindowFlags_AlwaysAutoResize;
        resetPopupOpen[1] = true;
        begun = imgui.BeginPopupModal(resetPopup, resetPopupOpen, resetPopupFlags);
    else
        begun = imgui.BeginPopup(resetPopup);
    end

    if begun then
        imgui.Text('This puts the colours, padding and drop shadow back to their defaults');
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

-- The Theme section (whether this addon uses the shared theme) and the Window section (the colours,
-- padding and drop shadow of whichever theme is in use). An addon follows it with a section of its own.
function widgets.Appearance(appearanceHooks)
    hooks = appearanceHooks;
    widgets.BeginLabels('winxi.appearance');
    widgets.PushControlWidth();

    -- Only an addon that can keep a theme of its own offers the choice
    local offersChoice = hooks ~= nil and hooks.onUseShared ~= nil;
    if offersChoice then
        widgets.Header('Theme', true);
        widgets.Label('Use Shared Theme');
        box[1] = theme.IsShared();
        if imgui.Checkbox('##winxi.UseSharedTheme', box) then
            hooks.onUseShared(box[1] and true or false);
        end
        Tooltip('On: this addon looks like every other addon that uses the shared theme, and changes made here change them all.\nOff: this addon keeps colours, padding and shadow of its own, starting from the shared ones.');
    end

    local current = theme.Get();
    local shared = theme.IsShared();

    -- Three families of settings, a little apart: the colours, the padding, the drop shadow
    widgets.Header('Window', not offersChoice);
    Color('Background Color', 'BackgroundColor', 'The background of every window.');
    Color('Border Color', 'BorderColor', 'The border of every window. Tabs, buttons, sliders and other controls are tinted from it.');
    Color('Text Color', 'TextColor');

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
    Tooltip('Draws a soft shadow behind each window, down and to the right of it.');

    if current.ShadowEnabled then
        Slider('Shadow Offset', 'ShadowOffset', 0, 20);
        Slider('Shadow Softness', 'ShadowBlur', 0, 20);
        Slider('Shadow Opacity (%)', 'ShadowOpacity', 0, 100);
    end

    widgets.Gap();
    -- An addon's own theme is reset at once. The shared one is everyone's, so that is confirmed first.
    if imgui.Button('Reset Appearance') then
        if shared then
            imgui.OpenPopup(resetPopup);
        else
            theme.Reset();
            Commit();
        end
    end
    Tooltip(shared and 'Puts the colours, padding and shadow back as they started, for every addon using the shared theme.'
        or 'Puts this addon\'s own colours, padding and shadow back as they started.');

    if ConfirmSharedReset() then
        theme.Reset();
        Commit();
    end

    SaveIfChanged();
    widgets.PopControlWidth();
end

-- The corner a window grows from, as four buttons laid out as the corners themselves are. current is
-- the present choice. Returns the newly chosen corner, or nil if it was not changed.
-- From the left of the first column of corners to the left of the second: the widest option in the
-- first column (its button, which is about as wide as the text is tall, and its name), then a gap.
-- Measured rather than fixed, so the two columns stay apart at any font size.
local growFromGap = 24;
local growFromColumn = nil;

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
        if imgui.RadioButton(anchor.Labels[mode] .. '##winxi.growfrom', current == mode) and current ~= mode then
            chosen = mode;
        end
        Tooltip('The corner that stays where it is when the window\'s content changes size: it grows away from that corner.');
    end
    return chosen;
end

local fadeDirty = false; -- a fade setting has been changed since the addon was last told

local function FadeCheck(settings, label, key, tooltip)
    widgets.Label(label);
    box[1] = settings[key];
    if imgui.Checkbox(controlIds['fade.' .. key], box) then
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
        changed = imgui.SliderFloat(controlIds['fade.' .. key], box, min, max, format);
    else
        changed = imgui.SliderInt(controlIds['fade.' .. key], box, min, max);
    end
    if changed then
        settings[key] = box[1];
        fadeDirty = true;
    end
    Tooltip(tooltip);
end

-- The controls for an addon's idle-fade settings (a table as winxi.fade describes). onChanged, if given,
-- is called when a change is final (the mouse is up), for the addon to save its settings.
function widgets.Fade(settings, onChanged)
    FadeCheck(settings, 'Fade When Idle', 'Enabled', 'Fades the windows out once you have stood still for a while, and brings them back as soon as you move.');

    if settings.Enabled then
        FadeNumber(settings, 'Idle Time (Seconds)', 'Delay', 1, 120, nil, 'How long you must stand still before the fade starts.');
        FadeNumber(settings, 'Idle Fade Time (Seconds)', 'Duration', 0, 5, '%.1f', 'How long the windows take to fade out once you are idle.');
        FadeNumber(settings, 'Fade In/Out Time (Seconds)', 'Transition', 0, 1, '%.2f', 'How long a window takes to fade in as it appears, out as it goes, and back in when you stop being idle.\nOne speed for every window. At 0 they appear and go at once.');
        FadeNumber(settings, 'Faded Opacity (%)', 'Opacity', 0, 100, nil, 'How visible a faded window stays. At 0 it disappears completely.');
        FadeCheck(settings, 'Stay Visible While Engaged', 'Combat', 'Standing still with your weapon drawn does not count as idle.');
        FadeCheck(settings, 'Stay Visible While Targeting', 'Target', 'Having anything targeted does not count as idle: the windows come back as soon as you target something.');
        FadeCheck(settings, 'Stay Visible While Missing HP', 'MissingHp', 'Standing still below full HP does not count as idle.');
        FadeCheck(settings, 'Stay Visible While Healing', 'Resting', 'Resting to recover HP and MP (/heal) does not count as idle.');
    end

    if fadeDirty and MouseIsUp() then
        fadeDirty = false;
        if onChanged then
            onChanged();
        end
    end
end

return widgets;

