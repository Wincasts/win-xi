-- Phoenix job/pet ability definitions and charge progression.
local abilities = require('winxi.catalog').New('abilities');

function abilities.ChargeRule(id, job, level)
    if type(job) ~= 'number' or type(level) ~= 'number' then return nil; end
    local record = abilities.Get(id);
    local best;
    for _, rule in ipairs(record and record.Charges or {}) do
        if rule.job == job and rule.level <= level and (not best or rule.level > best.level) then best = rule; end
    end
    return best; -- base rule only; merits/equipment/player recast state are not applied
end

return abilities;
