-- Settings controls in the same style as Trigger: consistent widths and a
-- visible help mark beside each control, with wrapped explanations.
local imgui = require('imgui');
local widgets = require('winxi.widgets');
local controls = {};
local helpWidth;
local uniformWidth;
local helpX;
local layouts = {};
local layout;

function controls.Width(width)
    -- Auto-sized windows must be measured from their contents, not their current
    -- available width: feeding that width back into controls can grow indefinitely.
    imgui.SetNextItemWidth(uniformWidth or width or 260);
end

function controls.BeginLayout(key, width, longestLabel)
    local size = imgui.GetFontSize();
    local known = layouts[key];
    if (known == nil or known.fontSize ~= size) then
        local labelWidth = imgui.CalcTextSize(longestLabel);
        known = { key = key, fontSize = size, right = (labelWidth or 0) + (width or 24) + 32 };
        layouts[key] = known;
    end
    local iconWidth = imgui.CalcTextSize('(?)');
    known.iconWidth = math.max(20, type(iconWidth) == 'number' and iconWidth or 20);
    known.measured = 0;
    layout = known;
    uniformWidth = width;
end

function controls.EndLayout()
    if (layout ~= nil and layout.measured > 0) then layout.right = layout.measured; end
    layout, uniformWidth, helpX = nil, nil, nil;
end

-- Returns whether the section is open (winxi's [-] / [+]): its settings are drawn only then.
-- controls.EndSection follows either way.
local sectionOpen = false;

function controls.Section(label, id, first)
    sectionOpen = widgets.Header(label, first);
    if (not sectionOpen) then return false; end
    helpX = layout.right + 8;
    imgui.BeginGroup();
    widgets.BeginLabels(layout.key .. '.options');
    return true;
end

function controls.EndSection()
    if (sectionOpen) then imgui.EndGroup(); end
    sectionOpen = false;
    helpX = nil;
end

function controls.Input(label, id, value, minimum, maximum, help)
    widgets.Label(label);
    controls.Width();
    local changed = imgui.InputInt(id, value);
    value[1] = math.max(minimum, math.min(maximum, value[1]));
    controls.Mark(help);
    return changed;
end

function controls.Outline(value)
    widgets.Label('Outline Thickness');
    for thickness = 0, 3 do
        if thickness > 0 then imgui.SameLine(); end
        if imgui.RadioButton(tostring(thickness) .. '##name.outline' .. thickness, value[1] == thickness) then value[1] = thickness; end
    end
    controls.Mark('Choose the font outline thickness. 0 disables the outline.');
end

function controls.Mark(text)
    if (layout ~= nil) then
        -- Measure only the option itself, before adding help. Never feed the
        -- child/window width or last frame's tooltip position back into sizing.
        local right = imgui.GetItemRectMax();
        local windowX = imgui.GetWindowPos();
        if (type(right) == 'number' and type(windowX) == 'number') then
            layout.measured = math.max(layout.measured, right - windowX);
        end
    end
    if helpX ~= nil then imgui.SameLine(helpX); else imgui.SameLine(); end
    imgui.TextDisabled('(?)');
    if (imgui.IsItemHovered()) then
        helpWidth = helpWidth or imgui.CalcTextSize('A spell or weaponskill sounds as it begins, an ability as it is used.');
        imgui.BeginTooltip();
        imgui.PushTextWrapPos(helpWidth);
        imgui.Text(text);
        imgui.PopTextWrapPos();
        imgui.EndTooltip();
    end
end

function controls.Checkbox(label, id, value, help, experimental)
    widgets.Label(label, experimental);
    local changed = imgui.Checkbox(id, value);
    if (help ~= nil) then controls.Mark(help); end
    return changed;
end

-- One of choices ({ key =, label = } each) as a dropdown, value[1] holding the chosen key
local choiceIds = {};

function controls.Choice(label, id, value, choices, help)
    widgets.Label(label);
    controls.Width();
    local chosen = choices[1];
    for _, choice in ipairs(choices) do
        if (choice.key == value[1]) then
            chosen = choice;
            break;
        end
    end
    local changed = false;
    if (imgui.BeginCombo(id, chosen.label)) then
        local ids = choiceIds[id];
        if (ids == nil) then
            ids = {};
            choiceIds[id] = ids;
        end
        for index, choice in ipairs(choices) do
            ids[index] = ids[index] or (choice.label .. id .. '.' .. index);
            local selected = choice.key == chosen.key;
            if (imgui.Selectable(ids[index], selected) and not selected) then
                value[1] = choice.key;
                changed = true;
            end
            if (selected) then
                imgui.SetItemDefaultFocus();
            end
        end
        imgui.EndCombo();
    end
    if (help ~= nil) then controls.Mark(help); end
    return changed;
end

function controls.Slider(label, id, value, minimum, maximum, format, help)
    widgets.Label(label);
    controls.Width();
    local changed = imgui.SliderInt(id, value, minimum, maximum, format);
    if (help ~= nil) then controls.Mark(help); end
    return changed;
end

return controls;
