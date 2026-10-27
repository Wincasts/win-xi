-- Phoenix's static quest index. Quest identity is (log, id), never id alone.
-- NPCs, conditions, modules and rewards are source evidence, not a walkthrough or progress tracker.
-- Returned definition tables are cached and read-only by convention. See quests.md.
local gamedata = require('winxi.gamedata');
local quests = {};
local index, hidden, logs, scripts = nil, nil, {}, {};

local function integer(value)
    return type(value) == 'number' and value >= 0 and value < 65536 and value == math.floor(value);
end

function quests.Clear()
    index, hidden, logs, scripts = nil, nil, {}, {};
end

function quests.Index()
    index = index or gamedata.Read('quests', 'index') or {};
    return index;
end

function quests.Logs()
    return quests.Index().Logs or {};
end

function quests.Get(log, id)
    if not integer(log) or not integer(id) or not quests.Logs()[log] then return nil; end
    if logs[log] == nil then logs[log] = gamedata.Read('quests', log) or false; end
    return logs[log] and logs[log][id] or nil;
end

-- Hidden interactions are path-keyed; they must not masquerade as numbered journal quests.
function quests.Hidden(path)
    if type(path) ~= 'string' then return nil; end
    hidden = hidden or gamedata.Read('quests', 'hidden') or {};
    if path:sub(1, 7) ~= 'hidden:' then path = 'hidden:' .. path; end
    return hidden[path];
end

function quests.GetBySymbol(area, symbol)
    if type(area) ~= 'string' or type(symbol) ~= 'string' then return nil; end
    local key = (quests.Index().Symbols or {})[area .. '.' .. symbol];
    return key and quests.GetKey(key) or nil;
end

function quests.GetKey(key)
    if type(key) ~= 'string' then return nil; end
    if key:sub(1, 7) == 'hidden:' then return quests.Hidden(key); end
    local log, id = key:match('^(%d+):(%d+)$');
    if not log then return nil; end
    return quests.Get(tonumber(log), tonumber(id));
end

function quests.Keys(includeHidden)
    local result = {};
    for _, key in ipairs(quests.Index().Keys or {}) do
        if includeHidden or key:sub(1, 7) ~= 'hidden:' then result[#result + 1] = key; end
    end
    return result;
end

function quests.Script(path)
    local page = (quests.Index().Scripts or {})[path];
    if page == nil then return nil; end
    if scripts[page] == nil then scripts[page] = gamedata.Read('quests', 'script_' .. page) or false; end
    return scripts[page] and scripts[page][path] or nil;
end

local function accept(record, options)
    return record and (record.Kind ~= 'hidden' or options.Hidden == true)
        and (options.Log == nil or record.Log == options.Log);
end

local function fromKeys(keys, options)
    local result = {};
    options = options or {};
    if options.Limit ~= nil and (not integer(options.Limit) or options.Limit == 0) then return result; end
    for _, key in ipairs(keys or {}) do
        local record = quests.GetKey(key);
        if accept(record, options) then
            result[#result + 1] = record;
            if options.Limit and #result >= options.Limit then break; end
        end
    end
    return result;
end

function quests.ForLog(log, options)
    if not integer(log) then return {}; end
    return fromKeys((quests.Index().ByLog or {})[log], options);
end

-- A zone reference does not establish where a quest starts or whether it is available.
function quests.ForZone(zone, options)
    if not integer(zone) then return {}; end
    return fromKeys((quests.Index().ByZone or {})[zone], options);
end

-- Only literal base reward item declarations, NOT every item mention or giveItem branch.
function quests.ForReward(itemId, options)
    if not integer(itemId) or itemId == 0 then return {}; end
    return fromKeys((quests.Index().ByDeclaredRewardItem or {})[itemId], options);
end

local function normalized(text)
    return text:lower():gsub('_', ' ');
end

function quests.ForNpc(name, zone, options)
    if type(name) ~= 'string' or (zone ~= nil and not integer(zone)) then return {}; end
    options = options or {};
    if options.Limit ~= nil and (not integer(options.Limit) or options.Limit == 0) then return {}; end
    local result = {};
    name = normalized(name);
    for _, key in ipairs(quests.Keys(options.Hidden)) do
        local record = quests.GetKey(key);
        if accept(record, options) then
            for _, npc in ipairs(record.NPCs or {}) do
                if normalized(npc.Name) == name and (zone == nil or npc.Zone == zone) then
                    result[#result + 1] = record;
                    break;
                end
            end
        end
        if options.Limit and #result >= options.Limit then break; end
    end
    return result;
end

-- Search names/symbols/logs/NPC and zone names, not raw scripts (which can be large).
-- Literal, ASCII-case-insensitive substring matching; no implicit game/client reads.
function quests.Search(query, options)
    if type(query) ~= 'string' then return {}; end
    options = options or {};
    if options.Limit ~= nil and (not integer(options.Limit) or options.Limit == 0) then return {}; end
    local result = {};
    query = normalized(query);
    for _, key in ipairs(quests.Keys(options.Hidden)) do
        local record = quests.GetKey(key);
        if accept(record, options) then
            local text = { record.Name, record.Area or '', record.Key };
            for _, symbol in ipairs(record.Symbols or {}) do text[#text + 1] = symbol; end
            for _, npc in ipairs(record.NPCs or {}) do text[#text + 1] = npc.Name; end
            for _, zone in ipairs(record.Zones or {}) do text[#text + 1] = zone.Symbol; end
            if normalized(table.concat(text, '\n')):find(query, 1, true) then result[#result + 1] = record; end
        end
        if options.Limit and #result >= options.Limit then break; end
    end
    return result;
end

local function model(record, presentation)
    if not record then return nil; end
    local result = { Key = record.Key, Log = record.Log, Id = record.Id, Name = record.Name,
        Server = record, Lines = {}, Warnings = {}, NPCs = record.NPCs or {}, Zones = record.Zones or {},
        RewardDeclarations = record.RewardDeclarations or {}, Evidence = record.Evidence or {} };
    if presentation then
        result.Name = type(presentation.Name) == 'string' and presentation.Name or result.Name;
        result.ClientDescription = presentation.Description;
    end
    local lines = result.Lines;
    if record.Kind == 'hidden' then
        lines[#lines + 1] = 'Hidden interaction (not a numbered quest-log entry)';
    else
        lines[#lines + 1] = ('Log: %s [%d]; quest ID: %d'):format(record.Area, record.Log, record.Id);
    end
    lines[#lines + 1] = 'Source coverage: ' .. record.Coverage;
    for _, declaration in ipairs(record.RewardDeclarations or {}) do
        if type(declaration.Fields.gil) == 'number' then
            lines[#lines + 1] = ('Declared base gil: %d (before server rates)'):format(declaration.Fields.gil);
        end
    end
    if record.DeclaredRewardItems then
        local values = {};
        for _, id in ipairs(record.DeclaredRewardItems) do values[#values + 1] = tostring(id); end
        lines[#lines + 1] = 'Declared base reward item IDs: ' .. table.concat(values, ', ');
    end
    result.Warnings[#result.Warnings + 1] = 'Catalog presence does not prove availability, implementation, unlocks or repeatability.';
    result.Warnings[#result.Warnings + 1] = 'NPC/zone and condition references are not verified starting instructions or prerequisites.';
    result.Warnings[#result.Warnings + 1] = 'Reward declarations are not guaranteed effective rewards; scripts, rates and player state may change them.';
    if record.Modules then result.Warnings[#result.Warnings + 1] = 'Enabled module associations exist; runtime gates and dynamic edits were not evaluated.'; end
    if presentation then result.Warnings[#result.Warnings + 1] = 'Supplied client text is presentation only, not verified Phoenix behavior.'; end
    return result;
end

function quests.Tooltip(log, id, presentation)
    return model(quests.Get(log, id), presentation);
end

function quests.TooltipKey(key, presentation)
    return model(quests.GetKey(key), presentation);
end

gamedata.OnChange(function () quests.Clear(); end); -- another server's data chosen

return quests;
