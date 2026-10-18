-- Conditions are ANDed and checked at draw time, not cached with database text.
local fields = require('mob_fields');
local rules = {};
rules.Order = { 'target', 'checked', 'nm', 'relevant' };
local valid = { target = true, checked = true, nm = true, relevant = true };
function rules.Normalize(value)
    if (value == 'always') then return ''; end
    if (value == '' or value:sub(1,1) == '+' or value:sub(-1) == '+' or value:find('++', 1, true)) then return nil; end
    local found = {};
    for key in value:gmatch('[^+]+') do if not valid[key] then return nil; end; found[key] = true; end
    local out = {}; for _, key in ipairs(rules.Order) do if found[key] then out[#out+1] = key; end end
    return table.concat(out, '+');
end
function rules.Has(part, key)
    return part.when ~= nil and ('+' .. part.when .. '+'):find('+' .. key .. '+', 1, true) ~= nil;
end
function rules.Set(part, key, on)
    local out = {};
    for _, name in ipairs(rules.Order) do
        if ((name == key and on) or (name ~= key and rules.Has(part, name))) then out[#out+1] = name; end
    end
    part.when = #out > 0 and table.concat(out, '+') or nil;
end
function rules.Visible(part, context)
    if (part.within and (context.ruleDistance == nil or context.ruleDistance > part.within)) then return false; end
    if (not part.when) then return true; end
    if (part.ruleWhen ~= part.when) then
        part.requireTarget, part.requireChecked = rules.Has(part, 'target'), rules.Has(part, 'checked');
        part.requireNM, part.requireRelevant = rules.Has(part, 'nm'), rules.Has(part, 'relevant');
        part.ruleWhen = part.when;
    end
    if (part.requireTarget and not context.ruleTarget) then return false; end
    if (part.requireChecked and not context.ruleChecked) then return false; end
    if (part.requireNM and not (context.monster and context.monster.Notorious)) then return false; end
    if (part.requireRelevant and not fields.Relevant(part, context)) then return false; end
    return true;
end
return rules;
