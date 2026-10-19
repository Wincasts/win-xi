local skills = require('winxi.catalog').New('skills');

function skills.Cap(id, job, level)
    local record = skills.Get(id);
    local rank = record and record.Ranks and record.Ranks[job];
    local caps = (skills.Index().Caps or {})[level];
    return rank and caps and caps[rank] or nil;
end

return skills;
