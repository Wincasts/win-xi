-- winxi.rules: the server's game rules the addons work out what will happen with, read from its code
-- (winxi's rules set, made by tools/build_rules.py; what each holds is said there).
--
--     rules.Get(name)    one rule's table (treasureHunter, treasurePool, haste, hasteEffects, swing,
--                        resting, bind), or nil where winxi's data is not installed: each addon then
--                        keeps to what it knew before
--     rules.Source()     the server it was made from: Repository, Branch, Commit, Committed
--     rules.Clear()      read again, for when the data has changed
local gamedata = require('winxi.gamedata');

local rules = {};
local index = nil;

local function Index()
    index = index or gamedata.Read('rules', 'index') or {};
    return index;
end

function rules.Get(name)
    return (Index().Rules or {})[name];
end

function rules.Source()
    return Index().Source;
end

function rules.Clear()
    index = nil;
end

gamedata.OnChange(function () rules.Clear(); end); -- another server's data chosen

return rules;
