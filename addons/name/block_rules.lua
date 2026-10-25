-- A token's conditions, when= and within=: ANDed, and checked as the name is set out, not kept with it.
--
--   rules.Normalize(value)        'target+checked+nm+relevant' as typed, in a fixed order, '' for always,
--                                 or nil for what is no condition
--   rules.Visible(part, context)  whether the part is written: context is the name's record, with
--                                 ruleTarget, ruleChecked, ruleDistance, ruleCombat, monster, words, level
--                                 and letter. A [level: nocombat] is not written while ruleCombat is set
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
-- Whether the token has anything to say of this name: a name with words, a checked monster's glass, a
-- distance that is known, a level or letter the tables give, an aggressive monster's sign
local function relevant(part, context)
    local kind = part.kind;
    if (kind == 'name') then return (context.words or '') ~= ''; end
    if (kind == 'checked') then return context.ruleChecked == true; end
    if (kind == 'distance') then return context.ruleDistance ~= nil; end
    if (kind == 'level') then return (context.level or '') ~= ''; end
    if (kind == 'letter') then return (context.letter or '') ~= ''; end
    if (kind == 'aggro') then return context.monster ~= nil and context.monster.Aggro == true; end
    return true;
end
function rules.Visible(part, context)
    if (part.within and (context.ruleDistance == nil or context.ruleDistance > part.within)) then return false; end
    if (part.nocombat and context.ruleCombat) then return false; end
    if (not part.when) then return true; end
    if (part.ruleWhen ~= part.when) then
        part.requireTarget, part.requireChecked = rules.Has(part, 'target'), rules.Has(part, 'checked');
        part.requireNM, part.requireRelevant = rules.Has(part, 'nm'), rules.Has(part, 'relevant');
        part.ruleWhen = part.when;
    end
    if (part.requireTarget and not context.ruleTarget) then return false; end
    if (part.requireChecked and not context.ruleChecked) then return false; end
    if (part.requireNM and not (context.monster and context.monster.Notorious)) then return false; end
    if (part.requireRelevant and not relevant(part, context)) then return false; end
    return true;
end
return rules;
