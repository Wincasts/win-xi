-- The settings as described rows (winxi 65): each a name, a sentence under it saying what it does,
-- and its control at the right, drawn by winxi.widgets. This is the thin layer the tabs lay their
-- settings out with, so that each keeps its own tables of what it has.
--
--   controls.Section(label, first, defaultCollapsed)   a section (widgets.Header); its rows only inside the if
--   controls.Sub(label, first, defaultCollapsed)       a sub-section (widgets.SubHeader)
--   controls.EndSub()                                   before a row that follows the last sub-section
--   controls.Checkbox(label, id, value, sentence, spec)
--   controls.Input(label, id, value, min, max, format, sentence, spec)    a whole number in a range, as a slider
--   controls.Slider(label, id, value, min, max, format, sentence, spec)
--   controls.Choice(label, id, value, choices, sentence, spec)   one of choices ({ key =, label = } each),
--                                                       value[1] holding the chosen key; returns whether changed
--   controls.Outline(value, label, id, sentence, spec)   an outline's thickness, None to 3 px
--   controls.Color(label, id, color, sentence, spec)
--   controls.Text(label, id, value, length, sentence, spec)   a line of text typed in
--   controls.Note(text)                                 a dim line that is not a setting: a warning
--
-- spec is the row's, each optional (widgets' own): parent, the setting this one waits on; experimental.
-- A spec is made once, at file scope, never a table a frame: a changing parent is set on it each draw.
-- With none given a scratch one is used, so the unit of a slider never touches widgets' own
-- (widgets.Pixels and the like are shared).
local imgui = require('imgui');
local widgets = require('winxi.widgets');
local controls = {};

local scratch = {};

local function Spec(spec, format)
    if (spec == nil) then
        spec = scratch;
        spec.parent, spec.experimental = nil, nil;
    end
    spec.format = format;
    return spec;
end

function controls.Section(label, first, defaultCollapsed)
    return widgets.Header(label, first, defaultCollapsed);
end

function controls.Sub(label, first, defaultCollapsed)
    return widgets.SubHeader(label, first, defaultCollapsed);
end

function controls.EndSub()
    widgets.EndSub();
end

function controls.Checkbox(label, id, value, sentence, spec)
    return widgets.Check(label, sentence, value, id, spec);
end

function controls.Input(label, id, value, minimum, maximum, format, sentence, spec)
    local changed = widgets.Slider(label, sentence, value, minimum, maximum, id, Spec(spec, format));
    value[1] = math.max(minimum, math.min(maximum, value[1]));
    return changed;
end

function controls.Slider(label, id, value, minimum, maximum, format, sentence, spec)
    return widgets.Slider(label, sentence, value, minimum, maximum, id, Spec(spec, format));
end

function controls.Choice(label, id, value, choices, sentence, spec)
    local chosen = widgets.Dropdown(label, sentence, choices, value[1], id, spec);
    if (chosen ~= nil) then
        value[1] = chosen;
        return true;
    end
    return false;
end

local thicknesses = { { key = 0, label = 'None' }, { key = 1, label = '1 px' }, { key = 2, label = '2 px' }, { key = 3, label = '3 px' } };

function controls.Outline(value, label, id, sentence, spec)
    return controls.Choice(label or 'Outline', id or '##name.outline', value, thicknesses, sentence, spec);
end

function controls.Color(label, id, color, sentence, spec)
    return widgets.Color(label, sentence, color, id, spec);
end

function controls.Text(label, id, value, length, sentence, spec)
    widgets.BeginRow(label, sentence, spec);
    local changed = imgui.InputText(id, value, length);
    widgets.EndRow();
    return changed;
end

function controls.Note(text)
    widgets.Note(text);
end

return controls;
