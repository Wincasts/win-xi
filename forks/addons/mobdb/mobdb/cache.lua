-- What is shown about a mob that depends only on the mob: its sorted modifier lists with their text
-- already formatted, its flag and immunity icons, its drop and spell names, and its job and level text.
-- All of it used to be worked out again on every frame. Each piece is now worked out the first time it
-- is asked for and kept with the mob's database entry, going away with that entry when the zone's data
-- is replaced.
local cache = {};

local entMgr = AshitaCore:GetMemoryManager():GetEntity();
local resMgr = AshitaCore:GetResourceManager();

-- Older addon versions need a percent sign doubled to show one
cache.PercentSign = (ashita.addons_version < 2.2) and '%%' or '%';

local physicalNames = { 'H2H', 'Impact', 'Piercing', 'Slashing' };
local magicalNames = { 'Fire', 'Ice', 'Wind', 'Earth', 'Lightning', 'Water', 'Light', 'Dark' };
local statusNames = { 'Amnesia', 'Virus', 'Silence', 'Gravity', 'Stun', 'LightSleep', 'Charm', 'Paralyze', 'Bind', 'Slow', 'Petrify', 'Terror', 'Poison', 'DarkSleep', 'Blind' };

-- name -> its place in the list, which also settles the order of modifiers of equal strength
local function Ordered(names, from)
    local set = {};
    for index, name in ipairs(names) do
        set[name] = from + index;
    end
    return set;
end

local physicalSet = Ordered(physicalNames, 0);
local magicalSet = Ordered(magicalNames, 100);
local statusSet = Ordered(statusNames, 200);
local otherOrder = 300;

local flagNames = { 'Link', 'TrueSight', 'Sight', 'Sound', 'Scent', 'Magic', 'JA', 'Blood' };

local immunityFlags = {
    { flag = 0x01, icon = 'ImmuneSleep' },
    { flag = 0x02, icon = 'ImmuneGravity' },
    { flag = 0x04, icon = 'ImmuneBind' },
    { flag = 0x08, icon = 'ImmuneStun' },
    { flag = 0x10, icon = 'ImmuneSilence' },
    { flag = 0x20, icon = 'ImmuneParalyze' },
    { flag = 0x40, icon = 'ImmuneBlind' },
    { flag = 0x80, icon = 'ImmuneSlow' },
    { flag = 0x100, icon = 'ImmunePoison' },
    { flag = 0x200, icon = 'ImmuneElegy' },
    { flag = 0x400, icon = 'ImmuneRequiem' },
    { flag = 0x800, icon = 'ImmuneLightSleep' },
    { flag = 0x1000, icon = 'ImmuneDarkSleep' },
    { flag = 0x2000, icon = 'ImmunePetrify' },
};

-- Every immunity icon there is a texture for, whatever the mob (the debug token)
cache.AllImmunityFlags = immunityFlags;

-- Which modifiers each list takes, the order it puts them in, and any prefix on their icon's name.
-- accept returns the modifier's place among equals, or nil to leave it out.
local modLists = {
    physical = {
        descending = true,
        accept = function(name, potency) return potency ~= 1.0 and physicalSet[name] or nil; end,
    },
    magical = {
        descending = true,
        accept = function(name, potency) return potency ~= 1.0 and magicalSet[name] or nil; end,
    },
    strength = {
        descending = false,
        accept = function(name, potency)
            if statusSet[name] or potency >= 1.0 then return nil; end
            return physicalSet[name] or magicalSet[name] or otherOrder;
        end,
    },
    weakness = {
        descending = true,
        accept = function(name, potency)
            if statusSet[name] or potency <= 1.0 then return nil; end
            return physicalSet[name] or magicalSet[name] or otherOrder;
        end,
    },
    statusresist = {
        descending = true,
        prefix = 'Immune',
        accept = function(name, potency) return potency ~= 1 and statusSet[name] or nil; end,
    },
};

-- Kept by database entry. Weak, so an entry no longer in use takes its results with it.
local byResource = setmetatable({}, { __mode = 'k' });

local function Entry(resource)
    local entry = byResource[resource];
    if entry == nil then
        entry = {};
        byResource[resource] = entry;
    end
    return entry;
end

-- 30.00 -> 30, 12.50 -> 12.5
local function Percent(value)
    local text = string.format('%.2f', value):gsub('0+$', ''):gsub('%.$', '');
    return text;
end

local function BuildMods(resource, list)
    local mods = {};
    for name, potency in pairs(resource.Modifiers or {}) do
        local order = list.accept(name, potency);
        if order then
            mods[#mods + 1] = { Type = (list.prefix or '') .. name, Potency = potency, Order = order };
        end
    end

    table.sort(mods, function(a, b)
        if a.Potency ~= b.Potency then
            if list.descending then
                return a.Potency > b.Potency;
            end
            return a.Potency < b.Potency;
        end
        return a.Order < b.Order;
    end);

    -- Modifiers of the same strength share one figure, shown after the last of them
    for index, mod in ipairs(mods) do
        mod.HasIcon = gTextures.Cache[mod.Type] ~= nil;

        local last = (index == #mods);
        if last or (mods[index + 1].Potency ~= mod.Potency) then
            local text;
            if (mod.Potency > 1) then
                text = '+' .. Percent((mod.Potency - 1) * 100);
            else
                text = '-' .. Percent((1 - mod.Potency) * 100);
            end
            text = text .. cache.PercentSign;
            if not last then
                text = text .. ' ';
            end
            mod.Text = text;
        end
    end

    return mods;
end

-- A mob's modifiers of one kind (physical, magical, strength, weakness or statusresist), sorted.
-- Each has Type (its icon's name), HasIcon, and Text where a figure follows it.
function cache.Mods(resource, kind)
    local entry = Entry(resource);
    local mods = entry[kind];
    if mods == nil then
        mods = BuildMods(resource, modLists[kind]);
        entry[kind] = mods;
    end
    return mods;
end

-- The names of a mob's flag icons: its aggro icon first, then each flag it has that there is an icon for
function cache.Flags(resource)
    local entry = Entry(resource);
    if entry.flags == nil then
        local icons = {};
        if (resource.Notorious) then
            icons[1] = resource.Aggro and 'AggroHQ' or 'PassiveHQ';
        else
            icons[1] = resource.Aggro and 'AggroNQ' or 'PassiveNQ';
        end

        for _, flag in ipairs(flagNames) do
            if (resource[flag] == true) and (gTextures.Cache[flag] ~= nil) then
                icons[#icons + 1] = flag;
            end
        end
        entry.flags = icons;
    end
    return entry.flags;
end

-- The names of the icons for the statuses a mob is immune to
function cache.Immunities(resource)
    local entry = Entry(resource);
    if entry.immunities == nil then
        local icons = {};
        local immunities = resource.Immunities or 0;
        for _, flag in ipairs(immunityFlags) do
            if (bit.band(immunities, flag.flag) ~= 0) and (gTextures.Cache[flag.icon] ~= nil) then
                icons[#icons + 1] = flag.icon;
            end
        end
        entry.immunities = icons;
    end
    return entry.immunities;
end

-- Names for a list of ids, sorted. An id the client has no entry for is named by its number.
local function SortedNames(ids, lookup, unknown)
    local names = {};
    for _, id in ipairs(ids or {}) do
        local resource = lookup(resMgr, id);
        local name = resource and resource.Name and resource.Name[1];
        names[#names + 1] = name or string.format(unknown, id);
    end
    table.sort(names);
    return names;
end

function cache.DropNames(resource)
    local entry = Entry(resource);
    if entry.dropNames == nil then
        entry.dropNames = SortedNames(resource.Drops, resMgr.GetItemById, 'Item %d');
    end
    return entry.dropNames;
end

function cache.DropText(resource)
    local entry = Entry(resource);
    if entry.dropText == nil then
        entry.dropText = table.concat(cache.DropNames(resource), ',');
    end
    return entry.dropText;
end

-- What can be stolen, and what can be despoiled, from a mob: kept apart from what it drops
function cache.StealNames(resource)
    local entry = Entry(resource);
    if entry.stealNames == nil then
        entry.stealNames = SortedNames(resource.Steal, resMgr.GetItemById, 'Item %d');
    end
    return entry.stealNames;
end

function cache.StealText(resource)
    local entry = Entry(resource);
    if entry.stealText == nil then
        entry.stealText = table.concat(cache.StealNames(resource), ',');
    end
    return entry.stealText;
end

function cache.DespoilNames(resource)
    local entry = Entry(resource);
    if entry.despoilNames == nil then
        entry.despoilNames = SortedNames(resource.Despoil, resMgr.GetItemById, 'Item %d');
    end
    return entry.despoilNames;
end

function cache.DespoilText(resource)
    local entry = Entry(resource);
    if entry.despoilText == nil then
        entry.despoilText = table.concat(cache.DespoilNames(resource), ',');
    end
    return entry.despoilText;
end

function cache.SpellNames(resource)
    local entry = Entry(resource);
    if entry.spellNames == nil then
        entry.spellNames = SortedNames(resource.Spells, resMgr.GetSpellById, 'Spell %d');
    end
    return entry.spellNames;
end

-- "WAR" or "WAR/NIN" for a mob with a job; nil for one without
function cache.Job(resource)
    local entry = Entry(resource);
    if entry.job == nil then
        local text = false;
        if (resource.Job ~= nil) and (resource.Job > 0) then
            text = resMgr:GetString(gCompatibility.Resource.Jobs, resource.Job);
            if (resource.SubJob ~= nil) and (resource.SubJob > 0) then
                text = text .. '/' .. resMgr:GetString(gCompatibility.Resource.Jobs, resource.SubJob);
            end
        end
        entry.job = text;
    end
    return entry.job or nil;
end

-- "[Lv33-37]" or "[Lv33-37 WAR/NIN]"
function cache.JobLevel(resource)
    local entry = Entry(resource);
    if entry.jobLevel == nil then
        local text = string.format('[Lv%d-%d', resource.MinLevel, resource.MaxLevel);
        local job = cache.Job(resource);
        if job then
            text = text .. ' ' .. job;
        end
        entry.jobLevel = text .. ']';
    end
    return entry.jobLevel;
end

-- The database entry for the mob at an entity index: by index, or failing that by name. The answer is
-- kept until the target, the entity at that index, or the zone's data changes.
local lastIndex, lastId, lastData, lastResource = nil, nil, nil, nil;

function cache.FindResource(index)
    local id = entMgr:GetServerId(index);
    if (index == lastIndex) and (id == lastId) and (gData.Indices == lastData) then
        return lastResource;
    end

    local resource = gData.Indices[index];
    if resource == nil then
        local name = entMgr:GetName(index);
        if name ~= nil then
            resource = gData.Names[name];
        end
    end

    lastIndex, lastId, lastData, lastResource = index, id, gData.Indices, resource;
    return resource;
end

return cache;
