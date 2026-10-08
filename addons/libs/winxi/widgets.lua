-- winxi.widgets: ready-made controls for an addon's settings window.
--
--   widgets.Appearance(hooks)        the Theme and Window sections of an Appearance tab
--   widgets.Header(text)             a section title, for the addon's own section after those
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
-- Given those, a "Use shared theme" checkbox heads the controls. Without them there is no checkbox and
-- the addon always follows the shared theme.
local imgui = require('imgui');
local theme = require('winxi.theme');
local anchor = require('winxi.anchor');

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

-- Builds without the "let go" test save on every change instead
local function Released()
    return imgui.IsItemDeactivatedAfterEdit == nil or imgui.IsItemDeactivatedAfterEdit();
end

local function AfterControl(changed)
    if changed then
        theme.Touch();
        dirty = true;
    end
    if dirty and Released() then
        dirty = false;
        Commit();
    end
end

local function Tooltip(text)
    if text and imgui.IsItemHovered() then
        imgui.SetTooltip(text);
    end
end

local function Color(label, key, tooltip)
    local changed = imgui.ColorEdit4(label, theme.Get()[key]);
    Tooltip(tooltip);
    AfterControl(changed);
end

local function Slider(label, key, min, max, tooltip)
    local current = theme.Get();
    box[1] = current[key];
    local changed = imgui.SliderInt(label, box, min, max);
    if changed then
        current[key] = box[1];
    end
    Tooltip(tooltip);
    AfterControl(changed);
end

-- The title of a section of a settings window. An addon's Appearance tab has three: Theme and Window,
-- which widgets.Appearance draws, and one of the addon's own for whatever else it has to set.
widgets.HeaderColor = { 1.0, 0.75, 0.55, 1.0 };

function widgets.Header(text)
    imgui.TextColored(widgets.HeaderColor, text);
end

local resetPopup = 'Reset the shared theme?##winxi.reset';
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

    -- Only an addon that can keep a theme of its own offers the choice
    if hooks and hooks.onUseShared then
        widgets.Header('Theme');
        box[1] = theme.IsShared();
        if imgui.Checkbox('Use shared theme', box) then
            hooks.onUseShared(box[1] and true or false);
        end
        Tooltip('On: this addon looks like every other addon that uses the shared theme, and changes made here change them all.\nOff: this addon keeps colours, padding and shadow of its own, starting from the shared ones.');
    end

    local current = theme.Get();
    local shared = theme.IsShared();

    widgets.Header('Window');
    Color('Background Color', 'BackgroundColor', 'The background of every window.');
    Color('Border Color', 'BorderColor', 'The border of every window. Tabs, buttons, sliders and other controls are tinted from it.');
    Color('Text Color', 'TextColor');
    Slider('Padding', 'Padding', 0, theme.MaxPadding, 'Space between a window\'s border and its content, the same on every side.');

    box[1] = current.ShadowEnabled;
    if imgui.Checkbox('Drop shadow', box) then
        current.ShadowEnabled = box[1] and true or false;
        theme.Touch();
        Commit();
    end
    Tooltip('Draws a soft shadow behind each window, down and to the right of it.');

    if current.ShadowEnabled then
        Slider('Shadow offset', 'ShadowOffset', 0, 20);
        Slider('Shadow softness', 'ShadowBlur', 0, 20);
        Slider('Shadow opacity (%)', 'ShadowOpacity', 0, 100);
    end

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
end

-- The corner a window grows from, as four buttons laid out as the corners themselves are. current is
-- the present choice. Returns the newly chosen corner, or nil if it was not changed.
function widgets.GrowFrom(current)
    if anchor.Labels[current] == nil then
        current = anchor.Default;
    end

    local chosen = nil;
    for index, mode in ipairs(anchor.Modes) do
        -- two to a row: the top corners, then the bottom ones
        if index % 2 == 0 then
            imgui.SameLine(140);
        end
        if imgui.RadioButton(anchor.Labels[mode] .. '##winxi.growfrom', current == mode) and current ~= mode then
            chosen = mode;
        end
        Tooltip('The corner that stays where it is when the window\'s content changes size: it grows away from that corner.');
    end
    return chosen;
end

local fadeDirty = false; -- a fade slider has been moved since the addon was last told

-- The controls for an addon's idle-fade settings (a table as winxi.fade describes). onChanged, if given,
-- is called when a change is final, for the addon to save its settings.
function widgets.Fade(settings, onChanged)
    local function Check(label, key, tooltip)
        box[1] = settings[key];
        if imgui.Checkbox(label, box) then
            settings[key] = box[1] and true or false;
            if onChanged then
                onChanged();
            end
        end
        Tooltip(tooltip);
    end

    -- sliders are saved when let go, not on every step of the drag
    local function Number(label, key, min, max, format, tooltip)
        box[1] = settings[key];
        local changed;
        if format then
            changed = imgui.SliderFloat(label, box, min, max, format);
        else
            changed = imgui.SliderInt(label, box, min, max);
        end
        if changed then
            settings[key] = box[1];
            fadeDirty = true;
        end
        Tooltip(tooltip);
        if fadeDirty and Released() then
            fadeDirty = false;
            if onChanged then
                onChanged();
            end
        end
    end

    Check('Fade when idle', 'Enabled', 'Fades the windows out once you have stood still for a while, and brings them back as soon as you move.');
    if not settings.Enabled then
        return;
    end

    Number('Idle time (seconds)', 'Delay', 1, 120, nil, 'How long you must stand still before the fade starts.');
    Number('Fade time (seconds)', 'Duration', 0, 5, '%.1f');
    Number('Faded opacity (%)', 'Opacity', 0, 100, nil, 'How visible a faded window stays. At 0 it disappears completely.');
    Check('Stay visible while engaged', 'Combat', 'Standing still with your weapon drawn does not count as idle.');
    Check('Stay visible while targeting', 'Target', 'Having anything targeted does not count as idle: the windows come back as soon as you target something.');
    Check('Stay visible while missing HP', 'MissingHp', 'Standing still below full HP does not count as idle.');
    Check('Stay visible while healing', 'Resting', 'Resting to recover HP and MP (/heal) does not count as idle.');
end

return widgets;
