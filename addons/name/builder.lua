-- Experimental enemy-only two-row editor. Drafts do not touch settings until Apply.
local imgui = require('imgui');
local format = require('format');
local custom = require('custom');
local nameTypes = require('name_types');
local fields = require('mob_fields');
local levels = require('levels');
local rules = require('block_rules');
local outlined = require('winxi.text');
local builder = {};
local draft, drag, message;
local WIDTH, LIMIT = 640, 24;
local labels = { aggro = 'Aggro', level = 'Level', name = 'Enemy name', letter = 'Letters',
    distance = 'Distance', checked = 'Checked', text = 'Text', difficulty = 'Difficulty',
    checklevel = 'Checked level', senses = 'Detection', links = 'Link information' };
local namePalette = { 'aggro', 'level', 'name', 'letter', 'distance', 'checked', 'text' };
local checkPalette = { 'difficulty', 'checklevel', 'senses', 'links', 'text' };
local detailFields = { 'showCheckDetails', 'checkSize', 'abbreviateDifficulty' };
local sample = { Name = 'Goblin Butcher', Family = 'Goblin', Job = 1, SubJob = 0, MinLevel = 80,
    MaxLevel = 82, Notorious = false, Aggro = true, Link = true, Sight = true, Sound = false,
    Blood = false, Magic = false, JA = false, Scent = true, TrueSight = false, Immunities = 0,
    Respawn = 300, Drops = { 4372, 505 }, Steal = { 748 }, Despoil = {}, Spells = { 144, 154 },
    Modifiers = { Slashing = 1, Piercing = 1, H2H = 1, Impact = 1, Fire = 1, Ice = 1.3, Wind = 1,
        Earth = 1, Lightning = 1.5, Water = 1, Light = 1, Dark = 1 } };
-- Preview /check results are simulated; database facts are not modified.
function builder.Preview(d)
    local p = d.preview;
    local list = levels.PreviewMobs();
    local selected;
    for _, entry in ipairs(list) do if entry.id == p.choice then selected = entry; break; end end
    if (not selected and p.choice ~= 'sample') then
        selected = list[1]; p.choice = selected and selected.id or 'sample';
    end
    local monster = selected and selected.monster or sample;
    local name = selected and selected.name or sample.Name;
    local low, high = tonumber(monster.MinLevel) or 0, tonumber(monster.MaxLevel) or 0;
    local range = low > 0 and ((high > low and (low .. '-' .. high)) or tostring(low)) or '';
    local found = p.checked[1] and { text = low > 0 and tostring(math.floor((low+math.max(low, high))/2)) or nil,
        hard = 'Very Tough', hardShort = 'VT' } or nil;
    return { monster = monster, words = name, found = found, level = found and found.text or range,
        letter = 'A', ruleChecked = p.checked[1], ruleTarget = p.target[1], ruleDistance = p.distance[1],
        label = selected and selected.label or 'Demonstration mob (not zone data)' }, list;
end
local function copy(part) local out = {}; for k, v in pairs(part) do out[k] = v; end; return out; end
local function parts(d, row) return row == 'check' and d.checkParts or d.parts; end
local function title(part)
    if (part.kind == 'mob') then return fields.ByKey[part.field].label; end
    if (part.kind == 'text') then return part.text:match('^%s*$') and 'Space' or ('"' .. part.text:sub(1, 12) .. '"'); end
    return labels[part.kind] or part.kind;
end
local function accepts(row, kind)
    if (kind == 'text') then return true; end
    if (row == 'check') then return kind == 'mob' or kind == 'difficulty' or kind == 'checklevel' or kind == 'senses' or kind == 'links'; end
    return kind == 'name' or kind == 'level' or kind == 'aggro' or kind == 'letter' or kind == 'distance' or kind == 'checked';
end
local function snapshot(o)
    local values = { o.monsterFormat[1], o.checkFormat[1] };
    for _, key in ipairs(detailFields) do values[#values+1] = tostring(o[key][1]); end
    return table.concat(values, '|');
end
function builder.Load(o)
    local d = { owner = o, source = snapshot(o), parts = {}, checkParts = {}, selected = 1, row = 'name',
        preview = { checked = { true }, target = { true }, distant = { false }, distance = { 12 } } };
    for _, p in ipairs(format.Compile(o.monsterFormat[1])) do d.parts[#d.parts+1] = copy(p); end
    local check = o.checkFormat[1] ~= '' and o.checkFormat[1] or '[difficulty: space=6][senses: space=6][links]';
    for _, p in ipairs(format.Compile(check)) do d.checkParts[#d.checkParts+1] = copy(p); end
    for _, key in ipairs(detailFields) do d[key] = { o[key][1] }; end
    draft, drag, message = d, nil, nil;
    return d;
end
function builder.Format(d, row) return format.Serialize(parts(d, row)); end
function builder.Insert(d, kind, at, from, row, fromRow, field)
    row = row or ((kind == 'mob' or kind == 'difficulty' or kind == 'checklevel' or kind == 'senses' or kind == 'links') and 'check' or d.row);
    if (not accepts(row, kind) or (kind == 'mob' and not from and not fields.ByKey[field])) then return false; end
    local into, source = parts(d, row), parts(d, fromRow or row);
    if ((not from or source ~= into) and #into >= LIMIT) then return false; end
    local part = from and source[from] or { kind = kind, space = 4, field = field, display = kind == 'mob' and 'names' or nil };
    if (not part) then return false; end
    if (from) then table.remove(source, from); end
    if (not from and kind == 'text') then part.text, part.space = ' ', nil; end
    at = math.max(1, math.min(#into+1, at or #into+1));
    table.insert(into, at, part);
    d.row, d.selected = row, at;
    if (row == 'check' and (not from or source ~= into)) then d.showCheckDetails[1] = true; end
    return true;
end
local function hasContent(list)
    for _, part in ipairs(list) do if part.kind ~= 'text' or part.text:find('%S') then return true; end end
    return false;
end
function builder.Validate(d)
    if (not hasContent(d.parts)) then return 'Add a name-line block before applying.'; end
    if (d.showCheckDetails[1] and not hasContent(d.checkParts)) then return 'Add check information or disable the check line.'; end
    for _, row in ipairs({ 'name', 'check' }) do
        for _, part in ipairs(parts(d, row)) do
            if (part.kind == 'text') then
                if (part.text:find('[^\32-\126]')) then return 'Text blocks support printable ASCII only.'; end
                local parsed = format.Compile(part.text);
                if (part.text ~= '' and (#parsed ~= 1 or parsed[1].kind ~= 'text' or parsed[1].color or parsed[1].text ~= part.text)) then
                    return 'Use blocks instead of format tokens or colour tags inside Text blocks.';
                end
            end
        end
    end
end
function builder.Apply(o, d, save)
    if (d.owner ~= o or d.source ~= snapshot(o)) then return false, 'Enemy settings changed. Reload Current before applying.'; end
    local problem = builder.Validate(d); if (problem) then return false, problem; end
    o.monsterFormat[1], o.checkFormat[1] = builder.Format(d), builder.Format(d, 'check');
    for _, key in ipairs(detailFields) do o[key][1] = d[key][1]; end
    d.source = snapshot(o);
    if (save) then save(); end
    return true, 'Applied enemy name and check lines. Health bars, players and NPCs were not changed.';
end
local function tint(part)
    local n = part.color or 0xFFFFE040;
    return imgui.GetColorU32({ math.floor(n/65536)%256/255, math.floor(n/256)%256/255, n%256/255, 1 });
end
local function rect(list, x, y, w, h, color)
    list:AddRectFilled({ x, y }, { x+w, y+h }, color, 5);
end
local function hit(mx, my, x, y, w, h) return mx and my and mx >= x and mx <= x+w and my >= y and my <= y+h; end
local function words(part, d, row, context)
    if (not rules.Visible(part, context)) then return ''; end
    if (row == 'check') then return fields.Value(part, context.monster, context.found, d.abbreviateDifficulty[1]); end
    if (part.kind == 'checked' and (d.showCheckDetails[1] or not context.ruleChecked)) then return ''; end
    if (part.kind == 'text') then return part.text; end
    if (part.kind == 'letter') then return part.type == 'double' and 'AA' or 'A'; end
    if (part.kind == 'distance') then return ('%.' .. (part.decimals or 1) .. 'f'):format(context.ruleDistance); end
    return ({ name = context.words, level = context.level, aggro = context.monster.Aggro and '!' or '-', checked = '?' })[part.kind] or '';
end
local function preview(o, d)
    imgui.Text('Example');
    local context, mobs = builder.Preview(d);
    local x, y = imgui.GetCursorScreenPos(); imgui.Dummy({ WIDTH, 145 });
    local list = imgui.GetWindowDrawList();
    rect(list, x, y, WIDTH, 145, imgui.GetColorU32({ 0.035, 0.045, 0.065, 1 }));
    list:PushClipRect({ x, y }, { x+WIDTH, y+145 }, true);
    local maximum, minimum = nameTypes.Bounds(o);
    local top = y+20;
    for _, row in ipairs({ 'name', 'check' }) do
        if (row == 'name' or (d.showCheckDetails[1] and context.ruleChecked)) then
            local size = (d.preview.distant[1] and minimum or maximum)*(row == 'check' and d.checkSize[1]/100 or 1);
            imgui.PushFont(custom.PreviewFont(o), size);
            local across = 0;
            for _, p in ipairs(parts(d, row)) do
                local text = words(p, d, row, context);
                if (text ~= '') then across = across+imgui.CalcTextSize(text)+(p.space or 0); end
            end
            local pen = x+(WIDTH-across)/2;
            for _, p in ipairs(parts(d, row)) do
                local text = words(p, d, row, context);
                if (text ~= '') then
                    if (o.outline[1] > 0) then outlined.Packed(list, pen, top, tint(p), text, o.outline[1], imgui.GetColorU32({ 0, 0, 0, 1 }));
                    else list:AddText({ pen, top }, tint(p), text); end
                    if (o.fontBold[1]) then list:AddText({ pen+1, top }, tint(p), text); end
                    pen = pen+imgui.CalcTextSize(text)+(p.space or 0);
                end
            end
            imgui.PopFont(); top = top+size+6;
        end
    end
    list:PopClipRect();
    imgui.SetNextItemWidth(360);
    if (imgui.BeginCombo('Preview mob##builder.previewMob', context.label)) then
        if (imgui.Selectable('Demonstration mob##builder.preview.sample', d.preview.choice == 'sample')) then d.preview.choice = 'sample'; end
        for _, mob in ipairs(mobs) do
            if (imgui.Selectable(mob.label .. '##builder.preview.' .. mob.id, mob.id == d.preview.choice)) then d.preview.choice = mob.id; end
        end
        imgui.EndCombo();
    end
    imgui.Checkbox('Checked##builder.previewChecked', d.preview.checked); imgui.SameLine();
    imgui.Checkbox('Targeted##builder.previewTarget', d.preview.target); imgui.SameLine();
    imgui.Checkbox('Distant size##builder.previewDistant', d.preview.distant);
    imgui.SetNextItemWidth(240);
    if (imgui.SliderInt('Distance (y)##builder.previewDistance', d.preview.distance, 0, 100)) then
        d.preview.distance[1] = math.max(0, math.min(100, d.preview.distance[1]));
    end
    imgui.TextDisabled('Zone entries use mobdb facts; /check results are simulated. Icons are illustrative.');
end
local function workspace(d)
    imgui.Separator(); imgui.Text('Builder');
    imgui.TextDisabled('Drop blocks into either row. Click a block to edit; drag to reorder.');
    local x, y = imgui.GetCursorScreenPos();
    local boxes, rows, height = {}, {}, 0;
    for _, row in ipairs({ 'name', 'check' }) do
        local cx, cy = 12, height+30;
        rows[row] = { y = y+height };
        for i, p in ipairs(parts(d, row)) do
            local text = title(p);
            local w = math.max(84, math.min(180, imgui.CalcTextSize(text)+24));
            if (cx+w > WIDTH-12) then cx, cy = 12, cy+46; end
            boxes[#boxes+1] = { row = row, index = i, x = x+cx, y = y+cy, w = w, title = text };
            cx = cx+w+12;
        end
        rows[row].height, rows[row].endX, rows[row].endY = cy+48-height, x+cx, y+cy;
        height = cy+58;
    end
    imgui.InvisibleButton('##builder.workspace', { WIDTH, height });
    local hovered = imgui.IsItemHovered(ImGuiHoveredFlags_AllowWhenBlockedByActiveItem or 0);
    local mx, my = imgui.GetMousePos();
    local list = imgui.GetWindowDrawList();
    local targetRow = my and my >= rows.check.y and 'check' or 'name';
    local target = #parts(d, targetRow)+1;
    for _, row in ipairs({ 'name', 'check' }) do
        local r = rows[row];
        rect(list, x, r.y, WIDTH, r.height, imgui.GetColorU32({ 0.07, 0.085, 0.11, 1 }));
        list:AddText({ x+12, r.y+7 }, tint({}), row == 'name' and 'Name line' or 'Check information (shown after /check)');
        if (#parts(d, row) == 0) then list:AddText({ x+14, r.y+38 }, tint({}), 'Drop blocks here'); end
        if (hovered and hit(mx, my, x, r.y, WIDTH, r.height) and imgui.IsMouseClicked(0)) then d.row = row; end
    end
    for _, box in ipairs(boxes) do
        local selected = d.row == box.row and d.selected == box.index;
        rect(list, box.x, box.y, box.w, 34, imgui.GetColorU32(selected and { 0.22, 0.43, 0.56, 1 } or { 0.15, 0.21, 0.28, 1 }));
        list:AddText({ box.x+8, box.y+9 }, imgui.GetColorU32({ 0.95, 0.97, 1, 1 }), box.title);
        if (box.row == targetRow and hit(mx, my, box.x-6, box.y-6, box.w+12, 44)) then target = box.index+(mx > box.x+box.w/2 and 1 or 0); end
        if (hovered and hit(mx, my, box.x, box.y, box.w, 34) and imgui.IsMouseClicked(0)) then
            d.row, d.selected = box.row, box.index;
            local p = parts(d, box.row)[box.index];
            drag = { kind = p.kind, from = box.index, row = box.row, field = p.field, x = mx, y = my };
        end
    end
    if (drag and mx and my) then
        local moved = math.abs(mx-drag.x)+math.abs(my-drag.y) > 5;
        local allowed = accepts(targetRow, drag.kind);
        if (moved and hovered and allowed) then
            local px, py = rows[targetRow].endX-6, rows[targetRow].endY;
            for _, b in ipairs(boxes) do if b.row == targetRow and b.index == target then px, py = b.x-6, b.y; end end
            list:AddLine({ px, py }, { px, py+34 }, tint({}), 3);
        end
        if (moved and imgui.IsMouseDown(0)) then
            local ghost = imgui.GetForegroundDrawList();
            rect(ghost, mx+12, my+12, 180, 32, imgui.GetColorU32({ 0.25, 0.45, 0.6, 0.95 }));
            ghost:AddText({ mx+20, my+20 }, tint({}), drag.kind == 'mob' and fields.ByKey[drag.field].label or labels[drag.kind]);
        elseif (not imgui.IsMouseDown(0)) then
            if (moved and hovered) then
                local at = target;
                if (drag.from and drag.row == targetRow and drag.from < at) then at = at-1; end
                if (not builder.Insert(d, drag.kind, at, drag.from, targetRow, drag.row, drag.field)) then
                    message = allowed and 'Row limit: 24 blocks.' or 'That block belongs in the other row.';
                end
            end
            drag = nil;
        end
    end
end
local function tray(d)
    imgui.Separator(); imgui.Text('Blocks');
    imgui.TextDisabled('Drag into the builder above, or click to add. Text can go in either row.');
    local mx, my = imgui.GetMousePos();
    local function button(kind, row, field)
        local text = kind == 'mob' and fields.ByKey[field].label or labels[kind];
        if (imgui.Button(text .. '##builder.add.' .. row .. '.' .. (field or kind))) then
            if (not builder.Insert(d, kind, nil, nil, row, nil, field)) then message = 'Row limit: 24 blocks.'; end
        end
        if (imgui.IsItemHovered() and imgui.IsMouseClicked(0)) then drag = { kind = kind, field = field, x = mx, y = my }; end
    end
    imgui.Text('Name-line blocks');
    for i, kind in ipairs(namePalette) do if (i > 1 and i ~= 5) then imgui.SameLine(); end; button(kind, 'name'); end
    imgui.Text('Check-information blocks');
    for i, kind in ipairs(checkPalette) do if (i > 1) then imgui.SameLine(); end; button(kind, 'check'); end
    imgui.TextDisabled('New mobdb blocks use readable values. Raw IDs/masks remain available in the inspector.');
    if (imgui.TreeNode('All mobdb fields##builder.mobFields')) then
        for i, item in ipairs(fields.List) do
            if ((i-1)%3 ~= 0) then imgui.SameLine(); end
            button('mob', 'check', item.field);
        end
        imgui.TreePop();
    end
end
local function slider(label, value, low, high)
    imgui.SetNextItemWidth(240);
    if (imgui.SliderInt(label, value, low, high)) then value[1] = math.max(low, math.min(high, math.floor(value[1]))); end
end
local function inspector(d)
    imgui.Separator(); imgui.Text('Selected block');
    local list, index = parts(d, d.row), d.selected;
    local p = list[index];
    if (p) then
        imgui.Text(title(p));
        if (p.kind == 'text') then
            local value = { p.text }; imgui.SetNextItemWidth(320);
            if (imgui.InputText('Text##builder.literal', value, math.max(256, #p.text+256))) then p.text = value[1]; end
        else
            local value = { p.space or 0 }; slider('Space after (px)##builder.space', value, 0, 64); p.space = value[1] > 0 and value[1] or nil;
        end
        if (imgui.BeginCombo('Colour##builder.color', p.color and ('#%06X'):format(p.color%0x1000000) or 'Name colour')) then
            if (imgui.Selectable('Name colour##builder.inherit', p.color == nil)) then p.color = nil; end
            for _, name in ipairs({ 'white', 'grey', 'red', 'green', 'blue', 'yellow', 'orange', 'purple', 'pink', 'cyan' }) do
                if (imgui.Selectable(name .. '##builder.color.' .. name, p.color == 0xFF000000+format.Colors[name])) then p.color = 0xFF000000+format.Colors[name]; end
            end
            imgui.EndCombo();
        end
        local rgb = p.color or 0xFFFFE040;
        local picker = { math.floor(rgb/65536)%256/255, math.floor(rgb/256)%256/255, rgb%256/255, 1 };
        if (imgui.ColorEdit4('Custom colour##builder.customColor', picker, ImGuiColorEditFlags_NoAlpha or 0)) then
            local function channel(v) return math.floor(math.max(0, math.min(1, v))*255+0.5); end
            p.color = 0xFF000000+channel(picker[1])*65536+channel(picker[2])*256+channel(picker[3]);
        end
        if (p.kind == 'mob') then
            local current = p.display or 'raw';
            if (imgui.BeginCombo('Database values##builder.display', current)) then
                for _, mode in ipairs({ 'raw', 'names', 'both' }) do
                    if (imgui.Selectable(mode .. '##builder.display.' .. mode, current == mode)) then p.display = mode; end
                end
                imgui.EndCombo();
            end
        end
        do -- Visibility applies to literal labels as well as data/icon blocks.
            local labels = { target = 'Target only', checked = 'Checked only', nm = 'Notorious monsters only', relevant = 'Relevant values only' };
            for _, condition in ipairs(rules.Order) do
                local value = { rules.Has(p, condition) };
                if (imgui.Checkbox(labels[condition] .. '##builder.when.' .. condition, value)) then rules.Set(p, condition, value[1]); end
            end
            local limited = { p.within ~= nil };
            if (imgui.Checkbox('Limit distance##builder.withinEnabled', limited)) then p.within = limited[1] and 20 or nil; end
            if (p.within) then
                local value = { p.within }; slider('Within (y)##builder.within', value, 1, 100); p.within = value[1];
            end
            imgui.TextDisabled('Enabled conditions are combined (AND). Relevant hides false, empty and neutral values.');
        end
        if (p.kind == 'letter') then
            if (imgui.RadioButton('Single A-Z##builder.single', p.type ~= 'double')) then p.type = 'single'; end
            imgui.SameLine(); if (imgui.RadioButton('Double AA-ZZ##builder.double', p.type == 'double')) then p.type = 'double'; end
        elseif (p.kind == 'distance') then
            local decimals = { p.decimals or 1 }; slider('Decimal places##builder.decimals', decimals, 0, 2); p.decimals = decimals[1];
        end
        if (imgui.Button('Move left##builder.left') and index > 1) then builder.Insert(d, p.kind, index-1, index, d.row); end
        imgui.SameLine(); if (imgui.Button('Move right##builder.right') and index < #list) then builder.Insert(d, p.kind, index+1, index, d.row); end
        imgui.SameLine(); if (imgui.Button('Remove block##builder.remove')) then table.remove(list, index); d.selected = math.min(index, #list); end
    else imgui.TextDisabled('Select a block in either builder row.'); end
    imgui.Checkbox('Check line enabled##builder.details', d.showCheckDetails);
    slider('Check line size (%)##builder.detailsSize', d.checkSize, 50, 125);
    imgui.Checkbox('Abbreviate difficulty##builder.abbreviate', d.abbreviateDifficulty);
    imgui.TextDisabled('Name sizes are shared: edit Maximum/Minimum Name Size in General Name Appearance.');
end
function builder.Draw(o, save)
    local d = draft; if (not d or d.owner ~= o) then d = builder.Load(o); end
    preview(o, d);
    workspace(d);
    tray(d);
    inspector(d);
    imgui.TextWrapped('Name format: ' .. builder.Format(d));
    imgui.TextWrapped('Check format: ' .. builder.Format(d, 'check'));
    imgui.TextDisabled('Draft only until Apply. Health bars remain in Names > Enemy Names.');
    local problem = builder.Validate(d);
    if (problem) then imgui.TextWrapped(problem); end
    if (snapshot(o) ~= d.source) then imgui.TextWrapped('Live enemy settings changed. Reload Current before applying.'); end
    imgui.BeginDisabled(problem ~= nil or snapshot(o) ~= d.source);
    if (imgui.Button('Apply to Enemy Names##builder.apply')) then local ok; ok, message = builder.Apply(o, d, save); end
    imgui.EndDisabled(); imgui.SameLine();
    if (imgui.Button('Reload Current##builder.reload')) then builder.Load(o); end
    if (message) then imgui.TextWrapped(message); end
end
return builder;
