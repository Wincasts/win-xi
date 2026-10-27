-- winxi.widgets: ready-made controls for an addon's settings window.
--
-- Every setting is a described row (winxi 65): its name, a plain sentence under the name saying what
-- it does, and its control at the right. The sentence is for someone who does not know the game's
-- insides: one short line, no jargon, no settings named by their keys. There is no other help: what
-- the sentence cannot say is left out. "Game default" is what the game has by itself, "Winxi Theme"
-- what the theme gives; never "the game's own" or "winxi's own".
--
--   widgets.Check(name, sentence, box, id, spec)              a checkbox; returns whether it changed
--   widgets.Slider(name, sentence, box, low, high, id, spec)  a slider of whole numbers (spec.float for
--                                    fractions); spec.format puts the unit in the value: '%d px', '%d s',
--                                    '%d%%'. Returns whether it changed, and whether it was let go after
--                                    a change, for an addon that saves then
--   widgets.Numbers(name, sentence, box, id, spec)            one or two whole numbers typed in (a position),
--                                    sized to their digits (spec.digits, 5); returns whether changed
--   widgets.Dropdown(name, sentence, choices, current, id, spec)   one of a list: choices are { key, label }
--                                    tables, or plain strings. Returns the key newly chosen, or nil.
--                                    spec.onOpen, if given, is called as the list opens and gives the
--                                    choices afresh
--   widgets.Color(name, sentence, color, id, spec)            a colour swatch; the picker opens on it
--   widgets.Action(name, sentence, label, spec)               a button at the right, reading label (with
--                                    its ##id); returns whether it was clicked
--   widgets.BeginRow(name, sentence, spec) / EndRow()         a row with a control of the addon's own
--                                    between them, drawn at the cursor, widgets.RowControlWidth wide
--   widgets.Note(text)               a dim sentence on its own, for what is not a setting (a warning)
--   widgets.Status(text)             the addon's state, one dim line at the foot of a tab, over a rule
--   widgets.Header(text, first)      a section title over a bar across the window, [-] or [+] at the
--                                    right; a click collapses or opens it, and it returns whether it is
--                                    open, for the section to be drawn only then. It sets itself apart
--                                    from the section above; no Gap before it
--   widgets.SubHeader(text, first)   a sub-section inside a section, for a section with many families:
--                                    its title indented a step, its rows a step more, collapsible as a
--                                    section is. The next SubHeader or Header ends it; a row after the
--                                    last sub-section calls widgets.EndSub() first
--   widgets.Gap()                    between one family of settings and the next, within a section: a faint
--                                    rule across the window, with a little air either side. Never before a
--                                    header, which sets itself apart
--
-- spec, on every row, each optional:
--   experimental   true: [Experimental], in yellow, goes before the name
--   parent         the box of the setting this one depends on: the row is indented under it, and greyed
--                  while it is off. parent = true indents without greying; indent = false never indents
--   description    where a widget writes its own sentence (Lock, FontFile): one of the addon's own
--
-- The theme's own sections, drawn this way:
--   widgets.Appearance(hooks)        the Theme, Window, Font and Styles sections of the Winxi Theme tab: the
--                                    windows on the game screen
--   widgets.SettingsAppearance(hooks) the settings windows' own Window and Font sections
--   widgets.IconAppearance()         the icons' section: the custom status icons
--   widgets.TooltipAppearance()      every tooltip's look and behaviour (winxi.tooltip), always the
--                                    shared theme's
--   widgets.BeginThemeTab() / EndThemeTab()   the Winxi Theme tab itself: last in its tab bar, against
--                                    its right edge, in a colour of its own
--   widgets.GrowFrom(current)        Grow From, the corner a window grows from; returns the new choice or nil
--   widgets.Fade(settings, onChanged) the rows for fading while idle (see winxi.fade)
--   widgets.Hide(settings, onChanged) the rows for the rules for hiding (see winxi.game)
--   widgets.FontFile(options, key, id, spec)   a font of the addon's own, for text it writes itself: the
--                                    theme's font or a .ttf of C:\Windows\Fonts, kept as a file name
--   widgets.FontSize(options, key, id, spec)   its size: the theme's size (0) or pixels
--   widgets.Lock(box, id, spec)      Lock Window: holds a window still and lets the mouse through it
--
-- Still here for the addons not yet on rows (party, name, and their kind):
--   widgets.Label(text)              a setting's name, to the left of its control, in line with winxi's
--   widgets.BeginLabels(key)         starts a group of settings whose controls line up with each other
--   widgets.PushControlWidth() / PopControlWidth()   around such settings
--   widgets.NumberWidth(fields, digits)   the width for a box of whole numbers
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
local clip = require('winxi.clip');

-- Every option's name has each word capitalised: "Shadow Opacity", not "Shadow opacity".
local widgets = {};

local dirty = false; -- the theme has been changed since it was last saved
local box = { 0 };   -- a number on its way in and out of a slider
local hooks = nil;   -- the functions given to the Appearance call being drawn
local noSpec = {};

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

-- Text as it is: imgui.Text and TextDisabled take theirs as a format, and make something else of a
-- percent sign. Each sentence is escaped once.
local escaped = {};

local function Escaped(text)
    local done = escaped[text];
    if done == nil then
        done = text:gsub('%%', '%%%%');
        escaped[text] = done;
    end
    return done;
end

local function TextHeight()
    local _, height = imgui.CalcTextSize('A');
    return height or 14;
end

local function FrameHeight()
    if imgui.GetFrameHeight ~= nil then
        local height = imgui.GetFrameHeight();
        if height ~= nil then return height; end
    end
    local style = imgui.GetStyle();
    return TextHeight() + 2 * ((style and style.FramePadding and style.FramePadding.y) or 2);
end

-- An experimental setting says so before its name: [Experimental], in this colour, as every addon here
-- marks one
widgets.ExperimentalColor = { 1.0, 1.0, 0.0, 1.0 };

local experimentalTag = '[Experimental]';
local experimentalGap = 6;      -- between the tag and the name

-- Described rows
--
-- The name and its sentence are at the left, the sentence wrapped at widgets.DescriptionWidth text
-- heights; the control is in a column at the right, widgets.RowControlWidth text heights wide, in line
-- with the name. A settings window fits itself to the two; one that has been resized (winxi.window)
-- keeps the control column and gives the sentence what is left.
widgets.DescriptionWidth = 30;
widgets.RowControlWidth = 13;
local rowGap = 14;           -- between the sentence and the control column
local rowSpacing = { 0, 3 }; -- a little air between one row and the next
local minDescription = 10;   -- text heights, in a window resized very narrow

local row = { left = 0, top = 0, bottom = 0, controlX = 0, controlWidth = 0, right = 0, greyed = false, indented = false };

local function RowColumns()
    local textHeight = TextHeight();
    local control = textHeight * widgets.RowControlWidth;
    local description = textHeight * widgets.DescriptionWidth;
    if window.IsResized() then
        local available = imgui.GetContentRegionAvail();
        if type(available) == 'number' then
            description = math.max(textHeight * minDescription, available - rowGap - control);
        end
    end
    return description, control;
end

-- Whether a row's parent, as its spec says, lets it be changed
local function ParentOn(parent)
    if parent == nil or parent == true then return true; end
    if type(parent) == 'table' then return parent[1] and true or false; end
    return parent and true or false;
end

function widgets.BeginRow(name, sentence, spec)
    spec = spec or noSpec;
    local indented = spec.parent ~= nil or spec.indent == true;
    if spec.indent == false then indented = false; end
    local greyed = not ParentOn(spec.parent) and imgui.BeginDisabled ~= nil;
    row.indented, row.greyed = indented, greyed;
    if indented then imgui.Indent(); end
    if greyed then imgui.BeginDisabled(true); end

    local description, control = RowColumns();
    local left, top = imgui.GetCursorPosX() or 0, imgui.GetCursorPosY() or 0;
    row.left, row.top = left, top;
    row.controlX = left + description + rowGap;
    row.controlWidth = control;
    row.right = row.controlX + control;

    imgui.BeginGroup();
    imgui.AlignTextToFramePadding();
    if spec.experimental then
        imgui.TextColored(widgets.ExperimentalColor, experimentalTag);
        imgui.SameLine(0, experimentalGap);
    end
    imgui.Text(Escaped(name));
    if sentence ~= nil and sentence ~= '' then
        imgui.PushTextWrapPos(left + description);
        imgui.TextDisabled(Escaped(sentence));
        imgui.PopTextWrapPos();
    end
    imgui.EndGroup();
    row.bottom = imgui.GetCursorPosY();

    -- the control goes in line with the name
    imgui.SetCursorPosY(top);
    imgui.SetCursorPosX(row.controlX);
    imgui.PushItemWidth(control);
end

-- Puts a control of the given width against the right edge of the control column
local function AtRight(width)
    imgui.SetCursorPosX(math.max(row.controlX, row.right - width));
end

function widgets.EndRow()
    imgui.PopItemWidth();
    local after = imgui.GetCursorPosY();
    if after < row.bottom then
        imgui.SetCursorPosY(row.bottom);
    end
    imgui.SetCursorPosX(row.left);
    if row.greyed then imgui.EndDisabled(); end
    if row.indented then imgui.Unindent(); end
    imgui.Dummy(rowSpacing);
end

function widgets.Check(name, sentence, value, id, spec)
    widgets.BeginRow(name, sentence, spec);
    AtRight(FrameHeight());
    local changed = imgui.Checkbox(id, value);
    widgets.EndRow();
    return changed;
end

function widgets.Slider(name, sentence, value, low, high, id, spec)
    spec = spec or noSpec;
    widgets.BeginRow(name, sentence, spec);
    local changed;
    if spec.float then
        changed = imgui.SliderFloat(id, value, low, high, spec.format or '%.1f');
    else
        changed = imgui.SliderInt(id, value, low, high, spec.format or '%d');
    end
    local done = imgui.IsItemDeactivatedAfterEdit() and true or false;
    widgets.EndRow();
    return changed, done;
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

function widgets.Numbers(name, sentence, value, id, spec)
    spec = spec or noSpec;
    local fields = spec.fields or (#value >= 2 and 2 or 1);
    widgets.BeginRow(name, sentence, spec);
    local width = widgets.NumberWidth(fields, spec.digits);
    AtRight(width);
    imgui.SetNextItemWidth(width);
    local changed;
    if fields == 2 then
        changed = imgui.InputInt2(id, value);
    else
        changed = imgui.InputInt(id, value, 0, 0);
    end
    widgets.EndRow();
    return changed;
end

-- The labels of a dropdown's choices, each with the dropdown's id in it: made once per dropdown
local dropdownLabels = {};

local function ChoiceKey(choice)
    if type(choice) == 'table' then return choice.key; end
    return choice;
end

local function ChoiceLabel(choice)
    if type(choice) == 'table' then return choice.label; end
    return choice;
end

function widgets.Dropdown(name, sentence, choices, current, id, spec)
    spec = spec or noSpec;
    widgets.BeginRow(name, sentence, spec);
    local shown = nil;
    for _, choice in ipairs(choices) do
        if ChoiceKey(choice) == current then
            shown = ChoiceLabel(choice);
            break;
        end
    end
    -- a choice not in the list (a set of icons whose folder has gone) is shown by its key
    if shown == nil then
        if current ~= nil and current ~= '' then
            shown = tostring(current);
        elseif choices[1] ~= nil then
            shown = ChoiceLabel(choices[1]);
        end
    end
    local chosen = nil;
    if imgui.BeginCombo(id, shown or '') then
        -- a list that is looked for afresh as it is opened (the icon sets, from their folders)
        if spec.onOpen ~= nil then
            choices = spec.onOpen() or choices;
            dropdownLabels[id] = nil;
        end
        local labels = dropdownLabels[id];
        if labels == nil then
            labels = {};
            dropdownLabels[id] = labels;
        end
        for index, choice in ipairs(choices) do
            local label = labels[index];
            if label == nil then
                label = ('%s%s.%s'):format(ChoiceLabel(choice), id, tostring(ChoiceKey(choice)));
                labels[index] = label;
            end
            local selected = ChoiceKey(choice) == current;
            if imgui.Selectable(label, selected) and not selected then
                chosen = ChoiceKey(choice);
            end
            if selected then
                imgui.SetItemDefaultFocus();
            end
        end
        imgui.EndCombo();
    end
    widgets.EndRow();
    return chosen;
end

local colorFlags = nil;

function widgets.Color(name, sentence, color, id, spec)
    colorFlags = colorFlags or ImGuiColorEditFlags_NoInputs or 0;
    widgets.BeginRow(name, sentence, spec);
    AtRight(FrameHeight());
    local changed = imgui.ColorEdit4(id, color, colorFlags);
    widgets.EndRow();
    return changed;
end

local buttonShown = {}; -- a button's label -> the words shown on it, before any ##

function widgets.Action(name, sentence, label, spec)
    widgets.BeginRow(name, sentence, spec);
    local shown = buttonShown[label];
    if shown == nil then
        shown = label:match('^(.-)##') or label;
        buttonShown[label] = shown;
    end
    local style = imgui.GetStyle();
    local padding = (style and style.FramePadding and style.FramePadding.x) or 4;
    AtRight(imgui.CalcTextSize(shown) + 2 * padding);
    local clicked = imgui.Button(label);
    widgets.EndRow();
    return clicked;
end

-- A dim sentence of its own, as wide as a row's sentence, for what is not a setting
function widgets.Note(text)
    local description = RowColumns();
    imgui.PushTextWrapPos((imgui.GetCursorPosX() or 0) + description);
    imgui.TextDisabled(Escaped(text));
    imgui.PopTextWrapPos();
end

-- The addon's state, at the foot of a tab: a thin line, then the words, dim, as wide as the rows
function widgets.Status(text)
    local description, control = RowColumns();
    imgui.Dummy(rowSpacing);
    imgui.Separator();
    imgui.PushTextWrapPos((imgui.GetCursorPosX() or 0) + description + rowGap + control);
    imgui.TextDisabled(Escaped(text));
    imgui.PopTextWrapPos();
end

-- Labelled settings, as the addons not yet on rows draw them
--
-- A setting's name goes to the left of its control, followed by a colon, and the controls line up in a
-- column to the right of the longest name. The widths are measured once per name.
--
-- The column is kept per group of settings, so that one tab's long names do not push another tab's
-- controls across: widgets.BeginLabels(key) starts a group, and every widgets.Label after it belongs to
-- that group until the next.
local labelTexts = {};    -- name -> the name with its colon
local labelWidths = {};
local labelColumns = {};  -- group -> where its controls start, from the longest name seen in it
local labelGroup = 'default';
local labelGap = 10;      -- between the longest name and the controls

function widgets.BeginLabels(key)
    labelGroup = key or 'default';
end

local experimentalTagWidth = nil;
local experimentalWidths = {};  -- name -> how wide the tag, the name and its colon are together

-- Draws a setting's name and leaves the cursor where its control goes. Give the control a label that
-- shows nothing ('##something'). experimental: true for a setting that is experimental.
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

-- How wide labelled controls are, in text heights
widgets.ControlWidth = 20;
widgets.ControlMinWidth = 5;

function widgets.PushControlWidth()
    local textHeight = TextHeight();
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

-- Between one family of settings and the next, within a section: a faint rule in the settings windows'
-- border colour, with a little air either side
local familyGap = { 0, 2 };
local ruleColor = { 0, 0, 0, 0 };
local ruleOpacity = 0.35;

function widgets.Gap()
    local border = theme.For('BorderColor', true) or theme.Get().BorderColor;
    ruleColor[1], ruleColor[2], ruleColor[3], ruleColor[4] = border[1], border[2], border[3], (border[4] or 1) * ruleOpacity;
    imgui.Dummy(familyGap);
    imgui.PushStyleColor(ImGuiCol_Separator, ruleColor);
    imgui.Separator();
    imgui.PopStyleColor();
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

-- The theme's own rows: each a value of theme.Get(), saved as the theme is
local function ThemeColor(label, key, sentence, spec)
    AfterControl(widgets.Color(label, sentence, theme.Get()[key], controlIds[key], spec));
end

local function ThemeChoice(label, key, choices, sentence, spec)
    local current = theme.Get();
    local chosen = widgets.Dropdown(label, sentence, choices, current[key], controlIds[key], spec);
    if chosen ~= nil then
        current[key] = chosen;
        AfterControl(true);
    end
end

local function ThemeCheck(label, key, sentence, spec)
    local current = theme.Get();
    box[1] = current[key];
    local changed = widgets.Check(label, sentence, box, controlIds[key], spec);
    if changed then
        current[key] = box[1] and true or false;
    end
    AfterControl(changed);
end

local function ThemeSlider(label, key, min, max, sentence, spec)
    local current = theme.Get();
    box[1] = current[key];
    local changed = widgets.Slider(label, sentence, box, min, max, controlIds[key], spec);
    if changed then
        current[key] = box[1];
    end
    AfterControl(changed);
end

-- Units go in a slider's value, never in its name: a spec for each, for addons too
widgets.Percent = { format = '%d%%' };
widgets.Pixels = { format = '%d px' };
widgets.Seconds = { format = '%d s' };
widgets.Milliseconds = { format = '%d ms' };
local percent, pixels, milliseconds = widgets.Percent, widgets.Pixels, widgets.Milliseconds;
local dependent = { parent = true };
local dependentPercent = { parent = true, format = '%d%%' };
-- the rows under one of the theme's switches: greyed while it is off, the parent set as they are drawn
local shadowPixels, shadowPercent = { parent = true, format = '%d px' }, { parent = true, format = '%d%%' };
local titleDependent, titlePixels, titlePercent = { parent = true }, { parent = true, format = '%d px' }, { parent = true, format = '%d%%' };
local backdropDependent = { parent = true };
local bookendDependent, bookendPercent = { parent = true }, { parent = true, format = '%d%%' };
local titleShadowPixels = { parent = true, format = '%d px' };
local heightSpec = { format = '%d px' };

-- The title of a section of a settings window, with a blank line before it to set it apart from the
-- section above (pass first for the section that heads the tab). An addon's Winxi Theme tab has five:
-- Theme, Window, Font and Styles, which widgets.Appearance draws, and Addon, the addon's own, for whatever
-- else it has to set.
--
-- Every section can be collapsed: its title has [-] at the right edge of the window while open and
-- [+] while collapsed, and a click on either changes which. A band in the settings windows' Highlight
-- Color lies behind the title row from one edge of the window to the other, with a solid line along
-- its foot, so a section is found at a glance; a sub-section's starts at its indent, fainter. widgets.Header returns whether it is open,
-- and the section's settings are drawn only then:
--     if widgets.Header('Window') then
--         ...
--     end
-- Which are collapsed is kept for as long as the addon is loaded, by the title within its group of
-- settings (widgets.BeginLabels). The title is in the theme's SettingsHeaderColor; widgets.HeaderColor
-- is the colour it starts as, for an addon's own text that wants it.
widgets.HeaderColor = { 1.0, 0.75, 0.55, 1.0 };

local collapsed = {};   -- group -> { title -> true while that section is collapsed }
local currentHeader = ''; -- the section being drawn, which its sub-sections are kept under
local subIndent = 0;      -- the steps the sub-section being drawn has indented by: its title's, and its rows'
local subGap = { 0, 3 };  -- before a sub-section's title
local markers = { '[-]', '[+]' };
local bandPad = 3;               -- the band reaches this far above and below the title row
local lineHeight = { 2, 1 };     -- the line along the band's foot: a section's, a sub-section's
local bandOpacity = { 0.55, 0.35 }; -- of the Highlight Color's own: the band of a section, of a sub-section
local barAfter = { 0, 5 };       -- the room left under the band
local bandColor, lineColor = { 0, 0, 0, 0 }, { 0, 0, 0, 0 };
local barFrom, barTo = { 0, 0 }, { 0, 0 };

-- A title over a bar, [-] or [+] at the right, returning whether its section is open. key is what the
-- collapsed state is kept under; sub, true for a sub-section.
local function Title(text, key, defaultCollapsed, sub)
    local group = collapsed[labelGroup];
    if group == nil then
        group = {};
        collapsed[labelGroup] = group;
    end
    if group[key] == nil and defaultCollapsed then group[key] = true; end
    local isCollapsed = group[key] == true;

    local look = theme.Get();
    local color = look.SettingsHeaderColor or widgets.HeaderColor;
    local marker = isCollapsed and markers[2] or markers[1];
    local clicked = false;

    -- a band behind the row, across the whole window for a section and from the indent for a
    -- sub-section, with a line along its foot. The window clips its content short of its edges, so the
    -- band goes through winxi.clip to reach them: a clip of its own that left the screen would be
    -- stretched over all of it (Direct3D 8 has no scissor), so the clip is the whole screen, and the
    -- band is cut to the window's own area below its title bar, so that one scrolled out of view
    -- draws nothing
    local list = imgui.GetWindowDrawList();
    local x, y = imgui.GetCursorScreenPos();
    local windowX, windowY = imgui.GetWindowPos();
    local windowWidth, windowHeight = imgui.GetWindowSize();
    local textHeight = TextHeight();
    if list ~= nil and list.AddRectFilled ~= nil and list.PushClipRect ~= nil and x ~= nil and y ~= nil
        and windowX ~= nil and windowY ~= nil and windowWidth ~= nil and windowHeight ~= nil then
        local highlight = look.SettingsHighlightColor or look.HighlightColor or color;
        local opacity = highlight[4] or 1;
        bandColor[1], bandColor[2], bandColor[3], bandColor[4] = highlight[1], highlight[2], highlight[3], opacity * (sub and bandOpacity[2] or bandOpacity[1]);
        lineColor[1], lineColor[2], lineColor[3], lineColor[4] = highlight[1], highlight[2], highlight[3], opacity;
        local line = sub and lineHeight[2] or lineHeight[1];
        local top, bottom = windowY + FrameHeight(), windowY + windowHeight;
        barFrom[1], barFrom[2] = sub and x or windowX, math.max(y - bandPad, top);
        barTo[1], barTo[2] = windowX + windowWidth, math.min(y + textHeight + bandPad + line, bottom);
        if barTo[2] > barFrom[2] and clip.Screen(list, barFrom, barTo) then
            list:AddRectFilled(barFrom, barTo, imgui.GetColorU32(bandColor));
            barFrom[2] = math.max(barTo[2] - line, barFrom[2]);
            list:AddRectFilled(barFrom, barTo, imgui.GetColorU32(lineColor));
            list:PopClipRect();
        end
    end

    -- the title at the left, the marker against the right edge, both clickable
    imgui.TextColored(color, text);
    if imgui.IsItemHovered() and ImGuiMouseCursor_Hand ~= nil then imgui.SetMouseCursor(ImGuiMouseCursor_Hand); end
    if imgui.IsItemClicked() then clicked = true; end
    imgui.SameLine(0, 0);
    local room = imgui.GetContentRegionAvail();
    local markerWidth = imgui.CalcTextSize(marker) or 0;
    if type(room) == 'number' and room > markerWidth then
        imgui.SetCursorPosX((imgui.GetCursorPosX() or 0) + room - markerWidth);
    end
    imgui.TextColored(color, marker);
    if imgui.IsItemHovered() and ImGuiMouseCursor_Hand ~= nil then imgui.SetMouseCursor(ImGuiMouseCursor_Hand); end
    if imgui.IsItemClicked() then clicked = true; end

    -- room under the row for the band's foot and its line
    barAfter[2] = bandPad + (sub and lineHeight[2] or lineHeight[1]) + 2;
    imgui.Dummy(barAfter);

    if clicked then
        isCollapsed = not isCollapsed;
        group[key] = isCollapsed;
    end
    return not isCollapsed;
end

-- Ends the sub-section being drawn: the rows after it are back under the section
function widgets.EndSub()
    for _ = 1, subIndent do
        imgui.Unindent();
    end
    subIndent = 0;
end

-- defaultCollapsed is optional; it affects only the first visit to this section.
function widgets.Header(text, first, defaultCollapsed)
    widgets.EndSub();
    currentHeader = text;
    if not first then
        imgui.NewLine();
    end
    return Title(text, text, defaultCollapsed);
end

-- A sub-section of the section being drawn: its title a step in, its rows a step more. It ends at the
-- next SubHeader or Header, or at widgets.EndSub. first: the first in its section, with no gap before it.
function widgets.SubHeader(text, first, defaultCollapsed)
    widgets.EndSub();
    if not first then
        imgui.Dummy(subGap);
    end
    imgui.Indent();
    subIndent = 1;
    local open = Title(text, currentHeader .. '/' .. text, defaultCollapsed, true);
    if open then
        imgui.Indent();
        subIndent = 2;
    end
    return open;
end

local resetPopups = {
    game = { id = 'Reset Shared Theme?##winxi.reset', button = 'Reset##winxi.reset.game', what = 'the colours, padding, drop shadow, font and styles of the windows on the game screen' },
    settings = { id = 'Reset Settings Windows?##winxi.resetSettings', button = 'Reset##winxi.reset.settings', what = 'the colours, padding and font of the settings windows' },
    icons = { id = 'Reset Icons?##winxi.resetIcons', button = 'Reset##winxi.reset.icons', what = 'the icons' },
    tooltips = { id = 'Reset Tooltips?##winxi.resetTooltips', button = 'Reset##winxi.reset.tooltips', what = 'the look and delay of the tooltips' },
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

-- The reset row of a part of the theme: theme.GameWindowKeys or theme.SettingsWindowKeys. An addon's
-- own theme is reset at once. The shared one is everyone's, so that is confirmed first.
local function ResetRow(label, popup, keys, sentenceShared, sentenceOwn)
    local shared = theme.IsShared();
    widgets.EndSub();
    widgets.Gap();
    if widgets.Action(label, shared and sentenceShared or sentenceOwn, popup.button) then
        if shared then
            imgui.OpenPopup(popup.id);
        else
            theme.Reset(keys);
            theme.Touch();
            Commit();
        end
    end

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
local fontChoices = {};   -- what '' is called -> the list of choices, that first then every font file

local function FontList(themeLabel)
    local list = fontChoices[themeLabel];
    if list == nil then
        list = { { key = '', label = themeLabel } };
        for _, file in ipairs(fonts.Files()) do
            list[#list + 1] = file;
        end
        fontChoices[themeLabel] = list;
    end
    return list;
end

local fontSizeSpec = { format = '%d px' };

local function FontChoice(fileKey, sizeKey, fileSentence, sizeSentence, names, spec)
    names = names or fontNames;
    local current = theme.Get();
    local chosen = widgets.Dropdown(names[1], fileSentence, FontList(names[3]), current[fileKey], controlIds[fileKey], spec);
    if chosen ~= nil then
        current[fileKey] = chosen;
        AfterControl(true);
    end
    box[1] = current[sizeKey];
    fontSizeSpec.format = current[sizeKey] > 0 and '%d px' or names[3];
    fontSizeSpec.parent = spec and spec.parent or nil;
    local resized = widgets.Slider(names[2], sizeSentence, box, 0, theme.MaxFontSize, controlIds[sizeKey], fontSizeSpec);
    if resized then
        current[sizeKey] = box[1];
    end
    AfterControl(resized);
end

-- Custom Icons: None (the game's own) or one of the sets, the folders of libs\winxi\statusicons. The
-- folders are looked for each time the row is drawn with the list open, so that one just added is there.
local noIcons = { key = '', label = 'None' };
local iconChoices = nil;

local function IconSets()
    iconChoices = { noIcons };
    for _, set in ipairs(statusicons.Sets()) do
        iconChoices[#iconChoices + 1] = set;
    end
    return iconChoices;
end

local iconSpec = { onOpen = IconSets };

local function StatusIcons()
    local current = theme.Get();
    if iconChoices == nil then
        IconSets();
    end
    local currentKey = current.StatusIcons and current.StatusIconSet or '';
    local chosen = widgets.Dropdown('Custom Icons', 'The pictures used for buffs and debuffs. None keeps the game default icons.',
        iconChoices, currentKey, controlIds.StatusIconSet, iconSpec);
    if chosen ~= nil then
        if chosen == '' then
            current.StatusIcons = false;
        else
            current.StatusIcons, current.StatusIconSet = true, chosen;
        end
        AfterControl(true);
    end
end

-- The icons' values: which custom icons statuses have, if any. hooks as for widgets.SettingsAppearance.
function widgets.IconAppearance(appearanceHooks)
    hooks = appearanceHooks;
    widgets.BeginLabels('winxi.iconAppearance');

    if widgets.Header('Icons', true) then
        StatusIcons();
    end

    ResetRow('Reset Icons', resetPopups.icons, theme.IconKeys,
        'Resets the icons for every addon that shares the theme.',
        'Resets this addon\'s icons.');

    SaveIfChanged();
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

    -- Only an addon that can keep a theme of its own offers the choice
    local offersChoice = hooks ~= nil and hooks.onUseShared ~= nil;
    if offersChoice and widgets.Header('Theme', true) then
        box[1] = theme.IsShared();
        if widgets.Check('Use Shared Theme', 'Uses the Winxi Theme, shared with every winxi addon and changed from here. Off, this addon keeps separate colours.', box, '##winxi.UseSharedTheme') then
            hooks.onUseShared(box[1] and true or false);
        end
    end

    local current = theme.Get();

    -- Three families of settings, a little apart: the colours, the padding, the drop shadow
    if widgets.Header('Window', not offersChoice) then
        ThemeColor('Background Color', 'BackgroundColor', 'Behind everything in each window.');
        ThemeColor('Border Color', 'BorderColor', 'The line round each window. Buttons, tabs and sliders take their colour from it.');
        ThemeColor('Text Color', 'TextColor', 'The words in each window.');
        ThemeColor('Highlight Color', 'HighlightColor', 'The tab you have chosen, and the line under the tabs.');

        widgets.Gap();
        ThemeSlider('Padding', 'Padding', 0, theme.MaxPadding, 'Space between a window\'s edge and what is in it.', pixels);

        widgets.Gap();
        ThemeCheck('Drop Shadow', 'ShadowEnabled', 'A soft shadow behind each window, down and to the right.');
        shadowPixels.parent, shadowPercent.parent = current.ShadowEnabled, current.ShadowEnabled;
        ThemeSlider('Shadow Offset', 'ShadowOffset', 0, 20, 'How far the shadow falls from the window.', shadowPixels);
        ThemeSlider('Shadow Softness', 'ShadowBlur', 0, 20, 'How blurred the shadow\'s edge is.', shadowPixels);
        ThemeSlider('Shadow Opacity', 'ShadowOpacity', 0, 100, 'How dark the shadow is.', shadowPercent);
    end

    -- The font every window is written in, where its addon does not choose one of its own, and the
    -- edge round text written over a bar or the game
    if widgets.Header('Font') then
        FontChoice('FontFile', 'FontSize',
            'The font every window uses. Default is the built-in font, and the rest come from Windows.',
            'How big the words are. Default keeps the usual size.');
        widgets.Gap();
        ThemeSlider('Text Outline', 'TextOutline', 0, theme.MaxTextOutline, 'A dark edge round words written over a bar or the game, so they stay easy to read. 0 is none.', pixels);
        ThemeColor('Outline Color', 'TextOutlineColor', 'The colour of that edge.');
    end

    -- The styles: the window border for every window, and what an addon that draws bars or statuses
    -- draws them with
    if widgets.Header('Styles') then
        if widgets.SubHeader('Border And Background', true) then
            ThemeChoice('Window Border', 'BorderStyle', theme.BorderStyles, 'A decorative border instead of the plain line.');
            ThemeChoice('Window Background', 'BackgroundStyle', theme.BackgroundStyles, 'A texture behind each window instead of the flat colour.');
            ThemeChoice('Tab Style', 'TabStyle', theme.TabStyles, 'A finish over the tabs.');
            ThemeSlider('Border Opacity', 'BorderOpacity', 0, 100, 'How solid the border is. 0 is no border.', percent);
        end
        if widgets.SubHeader('Titles') then
        ThemeCheck('Frame Titles', 'FrameTitles', 'Writes each window\'s name along its top edge.');
        local titled = current.FrameTitles and true or false;
        titleDependent.parent, titlePixels.parent = titled, titled;
        ThemeChoice('Title Style', 'TitleStyle', theme.TitleStyles, 'How the name sits on the edge.', titleDependent);
        ThemeColor('Title Color', 'TitleColor', 'The colour of the name.', titleDependent);
        ThemeCheck('Title All Caps', 'TitleAllCaps', 'Writes the name in capitals, PARTY instead of Party.', titleDependent);
        FontChoice('TitleFontFile', 'TitleSize',
            'The font the names are written in. Window Font uses the window\'s font.',
            'How big the names are. Default matches the window\'s text.', titleFontNames, titleDependent);
        ThemeSlider('Title Position X', 'TitleOffsetX', -50, theme.MaxTitleOffsetX, 'How far in from the right edge the name ends. Below 0 it runs past the edge.', titlePixels);
        ThemeSlider('Title Position Y', 'TitleOffsetY', -theme.MaxTitleOffsetY, theme.MaxTitleOffsetY, 'Moves the name down, or up when below 0.', titlePixels);
        ThemeCheck('Title Shadow', 'TitleShadow', 'A soft dark copy of the name, down and to the right of it.', titleDependent);
        local shadowed = titled and current.TitleShadow and true or false;
        titlePercent.parent, titleShadowPixels.parent = shadowed, shadowed;
        ThemeSlider('Title Shadow Offset', 'TitleShadowOffset', 1, 6, 'How far the copy falls.', titleShadowPixels);
        ThemeSlider('Title Shadow Opacity', 'TitleShadowOpacity', 0, 100, 'How dark the copy is.', titlePercent);
        end
        if widgets.SubHeader('Bars') then
        ThemeChoice('Bar Texture', 'BarTexture', theme.BarTextures, 'The look of the HP and MP bars.');
        ThemeChoice('Bar Frame', 'BarFrame', theme.BarFrames, 'The frame round each bar.');
        ThemeSlider('Bar Frame Opacity', 'BarFrameOpacity', 0, 100, 'How solid the frame is. 0 is none.', percent);
        ThemeSlider('Fill End Glow', 'BarGlow', 0, 100, 'A soft light where the bar\'s fill ends. 0 is none.', percent);
        ThemeCheck('Custom Bar Backdrop', 'BarBackdrop', 'Lets you choose the colour of the empty part of each bar. Off, it is a darker shade of the bar.');
        backdropDependent.parent = current.BarBackdrop and true or false;
        ThemeColor('Bar Backdrop Color', 'BarBackdropColor', 'The colour of the empty part. The more see-through it is, the more the dark behind it shows.', backdropDependent);
        ThemeCheck('Bar Bookends', 'Bookends', 'A small cap at each end of the bars.');
        bookendDependent.parent, bookendPercent.parent = current.Bookends and true or false, current.Bookends and true or false;
        ThemeChoice('Bookend Style', 'BookendStyle', theme.BookendStyles, 'The look of the caps.', bookendDependent);
        ThemeSlider('Bookend Opacity', 'BookendOpacity', 0, 100, 'How solid the caps are. 0 is none.', bookendPercent);
        end
        if withIcons and widgets.SubHeader('Icons') then
            StatusIcons();
        end
        widgets.EndSub();
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
    ResetRow('Reset Appearance', resetPopups.game, resetKeys,
        'Resets every setting above, for every addon that shares the theme.',
        'Resets this addon\'s look.');

    SaveIfChanged();
end

-- The settings windows' own values (winxi.window's settings kind): the Window section (their colours,
-- the Winxi Theme tab's and their padding) and the Font section (their font and its size). Apart from
-- the game screen's, so that what is set for those does not change the window it is set in. hooks
-- as for widgets.Appearance, but for the checkbox, which is Appearance's alone.
function widgets.SettingsAppearance(appearanceHooks)
    hooks = appearanceHooks;
    widgets.BeginLabels('winxi.settingsAppearance');

    if widgets.Header('Window', true) then
        ThemeColor('Background Color', 'SettingsBackgroundColor', 'Behind everything in each settings window.');
        ThemeColor('Border Color', 'SettingsBorderColor', 'The line round each settings window. Buttons, tabs and sliders take their colour from it.');
        ThemeColor('Text Color', 'SettingsTextColor', 'The words in each settings window.');
        ThemeColor('Highlight Color', 'SettingsHighlightColor', 'The tab you have chosen, and the line under the tabs.');
        ThemeColor('Sub-Category Color', 'SettingsHeaderColor', 'The section titles, the ones that fold with [-] and [+].');
        ThemeColor('Theme Tab Color', 'ThemeTabColor', 'The Winxi Theme tab, so it stands out from the other tabs.');

        widgets.Gap();
        ThemeSlider('Padding', 'SettingsPadding', 0, theme.MaxSettingsPadding, 'Space between a settings window\'s edge and what is in it.', pixels);

        widgets.Gap();
        local current = theme.Get();
        heightSpec.format = (tonumber(current.SettingsWindowHeight) or 0) > 0 and '%d px' or 'Fit To Content';
        ThemeSlider('Starting Height', 'SettingsWindowHeight', 0, theme.MaxSettingsWindowHeight, 'How tall a settings window is when it opens. What does not fit scrolls, and Fit To Content makes it as tall as its contents.', heightSpec);
        local _, drawnHeight = window.DrawnSize();
        if drawnHeight ~= nil and widgets.Action('Use This Window\'s Height', 'Makes every settings window open at this window\'s current height.', 'Use##winxi.useHeight') then
            current.SettingsWindowHeight = math.max(0, math.min(theme.MaxSettingsWindowHeight, math.floor(drawnHeight)));
            AfterControl(true);
        end
    end

    if widgets.Header('Font') then
        FontChoice('SettingsFontFile', 'SettingsFontSize',
            'The font every settings window uses. Default is the built-in font, and the rest come from Windows.',
            'How big the words are. Default keeps the usual size.');
    end

    ResetRow('Reset Settings Windows', resetPopups.settings, theme.SettingsWindowKeys,
        'Resets every setting above, for every addon that shares the theme.',
        'Resets this addon\'s settings windows.');

    SaveIfChanged();
end

-- Every tooltip's values (winxi.tooltip): whether they show, how soon, their colours, padding, text
-- size and width. Tooltips are always the shared theme's, so this is for winxisettings, which follows it.
local tooltipSample = 'A tooltip looks like this. Its words go on to another line once they reach the Max Width set above, so a long one stays readable.';
local sampleWords = 'Hover Here';

function widgets.TooltipAppearance()
    hooks = nil;
    widgets.BeginLabels('winxi.tooltipAppearance');

    if widgets.Header('Tooltips', true) then
        ThemeCheck('Show Tooltips', 'TooltipsEnabled', 'Little notes that appear when the mouse rests on something, in every winxi addon.');
        ThemeSlider('Delay', 'TooltipDelay', 0, theme.MaxTooltipDelay, 'How long the mouse rests on something before its note appears.', milliseconds);
    end

    if widgets.Header('Window') then
        ThemeColor('Background Color', 'TooltipBackgroundColor', 'Behind the words of each note.');
        ThemeColor('Border Color', 'TooltipBorderColor', 'The line round each note.');
        ThemeColor('Text Color', 'TooltipTextColor', 'The words of each note.');
        widgets.Gap();
        ThemeSlider('Padding', 'TooltipPadding', 0, theme.MaxTooltipPadding, 'Space between a note\'s edge and its words.', pixels);
        ThemeSlider('Max Width', 'TooltipMaxWidth', theme.MinTooltipWidth, theme.MaxTooltipWidth, 'How wide a note grows before its words go on to another line.', pixels);
        local current = theme.Get();
        box[1] = current.TooltipFontSize;
        local resized = widgets.Slider('Font Size', 'How big a note\'s words are. Same As Window matches the window it is over.', box, 0, theme.MaxFontSize, controlIds.TooltipFontSize,
            { format = current.TooltipFontSize > 0 and '%d px' or 'Same As Window' });
        if resized then
            current.TooltipFontSize = box[1];
        end
        AfterControl(resized);

        widgets.Gap();
        widgets.BeginRow('Sample', 'Rest the mouse on the words at the right to see a note.');
        AtRight(imgui.CalcTextSize(sampleWords));
        imgui.AlignTextToFramePadding();
        imgui.TextDisabled(sampleWords);
        Tooltip(tooltipSample);
        widgets.EndRow();
    end

    ResetRow('Reset Tooltips', resetPopups.tooltips, theme.TooltipKeys,
        'Resets every setting above, for every winxi addon.',
        'Resets every setting above.');

    SaveIfChanged();
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

-- Grow From: the corner a window grows from, as a dropdown. current is the present choice. Returns the
-- newly chosen corner, or nil if it was not changed.
local growFromChoices = nil;

function widgets.GrowFrom(current, spec)
    if growFromChoices == nil then
        growFromChoices = {};
        for _, mode in ipairs(anchor.Modes) do
            growFromChoices[#growFromChoices + 1] = { key = mode, label = anchor.Labels[mode] };
        end
    end
    if anchor.Labels[current] == nil then
        current = anchor.Default;
    end
    return widgets.Dropdown('Grow From', 'The corner that stays where it is as the window changes size.', growFromChoices, current, '##winxi.growfrom', spec);
end

-- A font of the addon's own, for the text an addon writes itself (a clock's line, a bar's figures,
-- scrolling text): the theme's font and size unless the addon's settings say otherwise, as every
-- winxi addon offers it. The settings are a file name, '' for the theme's font, and a size in a table
-- (as imgui's sliders take), 0 for the theme's size.
--
--   widgets.FontFile(options, key, id, spec)   the dropdown: Theme Font, then every .ttf of C:\Windows\Fonts
--   widgets.FontSize(options, key, id, spec)   the slider: Theme Size at 0, or pixels
--
-- options[key] is the setting; id the control's hidden label ('##buff.fontFile'). spec, each optional:
--   label        the setting's name: Font, or Font Size
--   description  the sentence under it, in place of the usual one
--   theme        what the theme's own is called: Theme Font, or Theme Size
--   min, max     the size's range: 0 and theme.MaxFontSize. Only a range from 0 offers the theme's size.
-- Both return whether the setting was changed this frame. FontSize returns as well whether the slider
-- was let go after a change, for an addon that saves then rather than as it is dragged.
function widgets.FontFile(options, key, id, spec)
    spec = spec or noSpec;
    local file = options[key];
    if type(file) ~= 'string' then file = ''; end
    local themeLabel = spec.theme or 'Theme Font';
    local choices = FontList(themeLabel);
    if spec.label == false then
        -- the control alone, after a name the addon wrote itself
        local changed = false;
        if imgui.BeginCombo(id, file ~= '' and file or themeLabel) then
            for _, choice in ipairs(choices) do
                local choiceKey, label = ChoiceKey(choice), ChoiceLabel(choice);
                if imgui.Selectable(label .. id .. '.' .. choiceKey, file == choiceKey) and file ~= choiceKey then
                    options[key] = choiceKey;
                    changed = true;
                end
            end
            imgui.EndCombo();
        end
        return changed;
    end
    local chosen = widgets.Dropdown(spec.label or 'Font',
        spec.description or ('The font for this addon\'s text. %s follows the Winxi Theme, and the rest come from Windows.'):format(themeLabel),
        choices, file, id, spec);
    if chosen ~= nil then
        options[key] = chosen;
        return true;
    end
    return false;
end

function widgets.FontSize(options, key, id, spec)
    spec = spec or noSpec;
    local low, high = spec.min or 0, spec.max or theme.MaxFontSize;
    local size = options[key];
    local themeLabel = spec.theme or 'Theme Size';
    local format = (low <= 0 and (tonumber(size[1]) or 0) <= 0) and themeLabel or '%d px';
    if spec.label == false then
        -- the control alone, after a name the addon wrote itself
        local changed = imgui.SliderInt(id, size, low, high, format);
        return changed, imgui.IsItemDeactivatedAfterEdit() and true or false;
    end
    widgets.BeginRow(spec.label or 'Font Size',
        spec.description or ('How big this addon\'s text is. %s follows the Winxi Theme.'):format(themeLabel), spec);
    local changed = imgui.SliderInt(id, size, low, high, format);
    local done = imgui.IsItemDeactivatedAfterEdit() and true or false;
    widgets.EndRow();
    return changed, done;
end

-- Lock Window: a window held where it is, the mouse going through it to the game (winxi.window's
-- locked and clickThrough options, or the addon's own flags). box is the setting, a table holding
-- true or false; id the control's hidden label. spec, each optional: label (Lock Window), description,
-- and onChanged, called with the new value. Returns whether it was changed.
function widgets.Lock(value, id, spec)
    spec = spec or noSpec;
    local changed = widgets.Check(spec.label or 'Lock Window',
        spec.description or 'Keeps the window where it is, and lets clicks through it to the game. Off, it can be dragged.',
        value, id, spec);
    if changed and spec.onChanged then
        spec.onChanged(value[1] and true or false);
    end
    return changed;
end

local fadeDirty = false; -- a fade setting has been changed since the addon was last told

local function FadeCheck(settings, label, key, sentence, spec)
    box[1] = settings[key];
    if widgets.Check(label, sentence, box, fadeIds[key], spec) then
        settings[key] = box[1] and true or false;
        fadeDirty = true;
    end
end

local function FadeNumber(settings, label, key, min, max, spec, sentence)
    box[1] = settings[key];
    if widgets.Slider(label, sentence, box, min, max, fadeIds[key], spec) then
        settings[key] = box[1];
        fadeDirty = true;
    end
end

local fadeDelay = { format = '%d s', parent = true };
local fadeDuration = { float = true, format = '%.1f s', parent = true };
local fadeTransition = { float = true, format = '%.2f s', parent = true };
local fadeOpacity = { format = '%d%%', parent = true };
local fadeDependent = { parent = true };

-- The controls for an addon's idle-fade settings (a table as winxi.fade describes). onChanged, if given,
-- is called when a change is final (the mouse is up), for the addon to save its settings.
-- grouped optionally splits the detailed controls into sub-sections (widgets.SubHeader).
function widgets.Fade(settings, onChanged, grouped)
    FadeCheck(settings, 'Fade When Idle', 'Enabled', 'Fades the windows out after you stand still for a while. They come back as soon as you move.');

    if settings.Enabled then
        if not grouped or widgets.SubHeader('Timing And Opacity', true) then
            FadeNumber(settings, 'Idle Time', 'Delay', 1, 120, fadeDelay, 'How long you stand still before they start to fade.');
            FadeNumber(settings, 'Idle Fade Time', 'Duration', 0, 5, fadeDuration, 'How long the fading out takes.');
            FadeNumber(settings, 'Fade In/Out Time', 'Transition', 0, 1, fadeTransition, 'How long a window takes to appear, go, or come back. At 0 it is instant.');
            FadeNumber(settings, 'Faded Opacity', 'Opacity', 0, 100, fadeOpacity, 'How much of a faded window still shows. At 0 it disappears.');
        end
        if not grouped or widgets.SubHeader('Keep Frames Visible') then
            FadeCheck(settings, 'Stay Visible While Moving', 'Moving', 'Walking about keeps the windows shown. Off, they fade on the move too.', fadeDependent);
            FadeCheck(settings, 'Show On Party Changes', 'Party', 'Someone joining, leaving or changing area brings them back.', fadeDependent);
            FadeCheck(settings, 'Stay Visible While Engaged', 'Combat', 'Having your weapon drawn keeps them shown.', fadeDependent);
            FadeCheck(settings, 'Stay Visible While Targeting', 'Target', 'Having anything targeted keeps them shown.', fadeDependent);
            FadeCheck(settings, 'Stay Visible While Missing HP', 'MissingHp', 'Being below full HP keeps them shown.', fadeDependent);
            FadeCheck(settings, 'Stay Visible While Healing', 'Resting', 'Resting to recover HP and MP keeps them shown.', fadeDependent);
        end
        if grouped then widgets.EndSub(); end
    end

    if fadeDirty and MouseIsUp() then
        fadeDirty = false;
        if onChanged then
            onChanged();
        end
    end
end

local hideDirty = false; -- a hide rule has been changed since the addon was last told

local function HideCheck(settings, label, key, sentence)
    box[1] = settings[key];
    if widgets.Check(label, sentence, box, hideIds[key]) then
        settings[key] = box[1] and true or false;
        hideDirty = true;
    end
end

-- The controls for an addon's rules for getting its windows out of the way (a table as winxi.game
-- describes). onChanged, if given, is called when a change is final, for the addon to save its settings.
function widgets.Hide(settings, onChanged)
    HideCheck(settings, 'Hide While Map Open', 'UnderMap', 'The windows go while the map is open.');
    HideCheck(settings, 'Hide While Chat Open', 'UnderChat', 'The windows go while the chat log is fully open.');
    HideCheck(settings, 'Hide While Loading', 'WhileLoading', 'The windows go while you change area.');
    HideCheck(settings, 'Hide During Events', 'DuringEvent', 'The windows go during cutscenes and while you talk to someone.');
    HideCheck(settings, 'Hide With Game Interface', 'WithInterface', 'The windows go when you hide the game interface.');

    if hideDirty and MouseIsUp() then
        hideDirty = false;
        if onChanged then
            onChanged();
        end
    end
end

return widgets;
