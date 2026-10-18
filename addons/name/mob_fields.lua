-- All source fields present in the bundled mobdb tables (not renderer caches).
-- Values are database facts, not inferred live observations. Unknown values stay empty.
local fields = { List = {}, ByKey = {} };
local readable = require('mob_readable');
local senses = { 'Sight', 'Sound', 'Blood', 'Magic', 'JA', 'Scent', 'TrueSight' };
local function add(path, label)
    local key, child = path:match('^([^.]+)%.(.+)$');
    local item = { field = path:lower(), path = path, label = label or path, key = key or path, child = child };
    fields.List[#fields.List+1], fields.ByKey[item.field] = item, item;
end
for _, key in ipairs({ 'Name', 'Family', 'Job', 'SubJob', 'MinLevel', 'MaxLevel', 'Notorious',
    'Aggro', 'Link', 'Sight', 'Sound', 'Blood', 'Magic', 'JA', 'Scent', 'TrueSight',
    'Immunities', 'Respawn', 'Drops', 'Steal', 'Despoil', 'Spells', 'Modifiers' }) do
    local labels = { Name = 'Database name', Job = 'Job (ID)', SubJob = 'Subjob (ID)',
        MinLevel = 'Minimum level', MaxLevel = 'Maximum level', TrueSight = 'True sight',
        JA = 'Ability detection', Immunities = 'Immunities (mask)', Respawn = 'Respawn (seconds)',
        Drops = 'Drops (IDs)', Steal = 'Steal (IDs)', Despoil = 'Despoil (IDs)', Spells = 'Spells (IDs)' };
    add(key, labels[key]);
end
for _, key in ipairs({ 'Slashing', 'Piercing', 'H2H', 'Impact', 'Fire', 'Ice', 'Wind', 'Earth',
    'Lightning', 'Water', 'Light', 'Dark' }) do add('Modifiers.' .. key, key .. ' modifier'); end

local function describe(value, depth)
    if (type(value) == 'boolean') then return value and 'Yes' or 'No'; end
    if (type(value) ~= 'table') then return tostring(value):gsub('[^\32-\126]', ''); end
    if (depth >= 2) then return '...'; end
    local keys, out = {}, {};
    for key in pairs(value) do keys[#keys+1] = key; end
    table.sort(keys, function(a, b)
        if (type(a) == 'number' and type(b) == 'number') then return a < b; end
        return tostring(a) < tostring(b);
    end);
    for i, key in ipairs(keys) do
        if (i > 32) then out[#out+1] = ('... (+%d)'):format(#keys-32); break; end
        out[#out+1] = (type(key) == 'number' and '' or tostring(key) .. '=') .. describe(value[key], depth+1);
    end
    return #out > 0 and table.concat(out, ', ') or 'none';
end

function fields.Raw(part, monster)
    local item = part.kind == 'mob' and fields.ByKey[part.field] or nil;
    if (not item or not monster) then return nil; end
    local value = monster[item.key];
    if (item.child) then return type(value) == 'table' and value[item.child] or nil; end
    return value;
end

function fields.Relevant(part, context)
    local kind, monster = part.kind, context.monster;
    if (kind == 'name') then return (context.words or '') ~= ''; end
    if (kind == 'checked' or kind == 'difficulty' or kind == 'checklevel') then return context.ruleChecked == true; end
    if (kind == 'distance') then return context.ruleDistance ~= nil; end
    if (kind == 'level') then return (context.level or '') ~= ''; end
    if (kind == 'letter') then return (context.letter or '') ~= ''; end
    if (kind == 'aggro' or kind == 'links') then return monster ~= nil and monster[kind == 'aggro' and 'Aggro' or 'Link'] == true; end
    if (kind == 'senses') then
        for _, key in ipairs(senses) do if monster and monster[key] then return true; end end
        return false;
    end
    if (kind ~= 'mob') then return true; end
    local value = fields.Raw(part, monster);
    if (part.field == 'modifiers' and type(value) == 'table') then
        for _, amount in pairs(value) do if amount ~= 1 then return true; end end
        return false;
    end
    if (part.field:match('^modifiers%.') and value == 1) then return false; end
    if (type(value) == 'table') then return next(value) ~= nil; end
    return value ~= nil and value ~= false and value ~= 0 and value ~= '';
end

function fields.Value(part, monster, found, abbreviated)
    if (part.kind == 'text') then return part.text or ''; end
    if (part.kind == 'difficulty') then
        return found and ((abbreviated and found.hardShort or found.hard) or '') or '';
    end
    if (part.kind == 'checklevel') then return found and found.text and ('Level: ' .. found.text) or ''; end
    if (not monster) then return ''; end
    if (part.kind == 'senses') then
        local out = {};
        for _, key in ipairs(senses) do
            if (monster[key]) then out[#out+1] = key == 'TrueSight' and 'True sight' or key; end
        end
        return #out > 0 and ('Detect: ' .. table.concat(out, '/')) or '';
    end
    if (part.kind == 'links') then
        return monster.Link and ('Link' .. (monster.Family and ': ' .. monster.Family or '')) or '';
    end
    local item = part.kind == 'mob' and fields.ByKey[part.field] or nil;
    if (not item) then return ''; end
    local value = fields.Raw(part, monster);
    if (value == nil) then return ''; end
    if (part.display == 'names' or part.display == 'both') then
        local named = readable.Value(part.field, value, part.display == 'both');
        if (named) then return named; end
    end
    return item.label .. ': ' .. describe(value, 0);
end

return fields;
