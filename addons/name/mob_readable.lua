-- Resource-backed names are optional. Raw mobdb values remain the default.
local bit = require('bit');
local readable = {};
local cache = { item = {}, spell = {} };
local counts = { item = 0, spell = 0 };
local jobs = { 'WAR', 'MNK', 'WHM', 'BLM', 'RDM', 'THF', 'PLD', 'DRK', 'BST', 'BRD', 'RNG',
    'SAM', 'NIN', 'DRG', 'SMN', 'BLU', 'COR', 'PUP', 'DNC', 'SCH', 'GEO', 'RUN' };
-- Same mobdb immunity-mask definitions as forks/addons/mobdb/mobdb/cache.lua.
local immunities = { 'Sleep', 'Gravity', 'Bind', 'Stun', 'Silence', 'Paralyze', 'Blind', 'Slow',
    'Poison', 'Elegy', 'Requiem', 'Light Sleep', 'Dark Sleep', 'Petrify' };
function readable.Clear()
    cache, counts = { item = {}, spell = {} }, { item = 0, spell = 0 };
end
local function name(kind, id)
    local kept = cache[kind][id];
    if (kept ~= nil) then return kept.text, kept.named; end
    local ok, value = pcall(function()
        local resources = AshitaCore:GetResourceManager();
        local entry;
        if (kind == 'item') then entry = resources:GetItemById(id); else entry = resources:GetSpellById(id); end
        return entry.Name[1];
    end);
    if (not ok or type(value) ~= 'string') then value = nil;
    else value = value:gsub('[%z\1-\31].*', ''):gsub('[^\32-\126]', ''); end
    local named = value ~= nil and value ~= '';
    if (not named) then value = (kind == 'item' and 'Item #' or 'Spell #') .. tostring(id); end
    if (counts[kind] >= 512) then cache[kind], counts[kind] = {}, 0; end
    cache[kind][id], counts[kind] = { text = value, named = named }, counts[kind]+1;
    return value, named;
end
function readable.Value(field, value, both)
    if (field == 'job' or field == 'subjob') then
        local known = value == 0 or jobs[value] ~= nil;
        local job = value == 0 and 'None' or jobs[value] or ('#' .. tostring(value));
        return (field == 'job' and 'Job: ' or 'Subjob: ') .. job .. (both and known and (' (#%s)'):format(value) or '');
    end
    if (field == 'immunities' and type(value) == 'number') then
        local out = {};
        for i, label in ipairs(immunities) do if bit.band(value, 2^(i-1)) ~= 0 then out[#out+1] = label; end end
        local unknown = bit.band(value, bit.bnot(0x3FFF));
        if (unknown < 0) then unknown = unknown+0x100000000; end
        if (unknown ~= 0) then out[#out+1] = ('Unknown 0x%X'):format(unknown); end
        return 'Immunities: ' .. (#out > 0 and table.concat(out, ', ') or 'none')
            .. (both and (' (mask %s)'):format(value) or '');
    end
    if ((field == 'drops' or field == 'steal' or field == 'despoil' or field == 'spells') and type(value) == 'table') then
        local out = {};
        for i, id in ipairs(value) do
            if (i > 32) then out[#out+1] = ('... (+%d)'):format(#value-32); break; end
            local label, named = name(field == 'spells' and 'spell' or 'item', id);
            out[#out+1] = label .. (both and named and (' (#%s)'):format(id) or '');
        end
        return field:sub(1,1):upper() .. field:sub(2) .. ': ' .. (#out > 0 and table.concat(out, ', ') or 'none');
    end
    if (field == 'respawn' and type(value) == 'number') then
        local time = value >= 60 and ('%dm %ds'):format(math.floor(value/60), value%60) or (value .. 's');
        return 'Respawn: ' .. time .. (both and (' (%ss)'):format(value) or '');
    end
end
return readable;
