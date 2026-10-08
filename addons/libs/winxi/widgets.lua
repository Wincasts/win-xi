-- winxi.widgets: ready-made controls for an addon's settings window.
--
--   widgets.Appearance(hooks)        the theme: colours, padding and drop shadow
--   widgets.GrowFrom(current)        four buttons for a window's corner; returns the new choice or nil
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

function widgets.Appearance(appearanceHooks)
    hooks = appearanceHooks;

    -- Only an addon that can keep a theme of its own offers the choice
    if hooks and hooks.onUseShared then
        box[1] = theme.IsShared();
        if imgui.Checkbox('Use shared theme', box) then
            hooks.onUseShared(box[1] and true or false);
        end
        Tooltip('On: this addon looks like every other addon that uses the shared theme, and changes made here change them all.\nOff: this addon keeps colours, padding and shadow of its own, starting from the shared ones.');
    end

    local current = theme.Get();
    local shared = theme.IsShared();

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

    if imgui.Button('Reset appearance') then
        theme.Reset();
        Commit();
    end
    Tooltip(shared and 'Puts the colours, padding and shadow back as they started, for every addon using the shared theme.'
        or 'Puts this addon\'s own colours, padding and shadow back as they started.');
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

return widgets;
