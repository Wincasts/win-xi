local jobs = require('winxi.catalog').New('jobs');

function jobs.Related(id, level)
    if not jobs.Get(id) then return nil; end
    local result = {};
    for _, kind in ipairs({ 'spells', 'abilities', 'weaponskills', 'traits', 'skills' }) do
        result[kind] = require('winxi.' .. kind).ForJob(id, level);
    end
    return result;
end

return jobs;
