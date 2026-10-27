-- Shared Phoenix item definitions. Returned tables are read-only by convention.
-- Server data and client presentation are deliberately separate; see items.md.
local gamedata = require('winxi.gamedata');
local items = {};
local pages, scripts = {}, {};
local index, ids, mods;

function items.Clear()
    pages, scripts = {}, {};
    index, ids, mods = nil, nil, nil;
end

function items.Index()
    index = index or gamedata.Read('items', 'index') or {};
    return index;
end

local function valid(id)
    return type(id) == 'number' and id >= 0 and id < 65536 and id == math.floor(id);
end

function items.Get(id)
    if not valid(id) then return nil; end
    local size = items.Index().PageSize;
    if not size then return nil; end
    local page = math.floor(id / size);
    if pages[page] == nil then pages[page] = gamedata.Read('items', page) or false; end
    return pages[page] and pages[page][id] or nil;
end

-- Explicit full enumeration; unlike Get, this loads every definition page.
function items.Ids()
    if ids then return ids; end
    ids = {};
    local size = items.Index().PageSize;
    if not size then return ids; end
    for page = 0, math.floor(65535 / size) do
        if pages[page] == nil then pages[page] = gamedata.Read('items', page) or false; end
        for id in pairs(pages[page] or {}) do ids[#ids + 1] = id; end
    end
    table.sort(ids);
    return ids;
end

function items.Script(path)
    local page = (items.Index().Scripts or {})[path];
    if page == nil then return nil; end
    if scripts[page] == nil then scripts[page] = gamedata.Read('items', 'script_' .. page) or false; end
    return scripts[page] and scripts[page][path] or nil;
end

function items.ModName(id)
    if not mods then
        mods = {};
        for name, value in pairs(((items.Index().Enums or {}).mod) or {}) do
            mods[value] = name:upper();
        end
    end
    return mods[id] or ('MOD_' .. tostring(id));
end

-- Presentation model, not an ImGui dependency. Numeric modifiers use SERVER units,
-- not implied percentages. Latents/pet modifiers stay separate and conditional.
-- Pass an Ashita item resource optionally; no live client is needed for server lookups.
function items.Tooltip(id, resource)
    local item = items.Get(id);
    if not item then return nil; end
    local model = { Id = id, Name = item.Name, Server = item, Lines = {}, Warnings = {},
        Latents = item.Latents or {}, PetMods = item.PetMods or {}, Food = item.Food };
    if resource then
        model.Name = resource.Name and resource.Name[1] or model.Name;
        model.ClientDescription = resource.Description and resource.Description[1] or nil;
    end
    local lines = model.Lines;
    local function line(value) lines[#lines + 1] = value; end
    local bit = require('bit');
    local flags = item.Basic.flags;
    if bit.band(flags, 32768) ~= 0 then line('Rare'); end
    if bit.band(flags, 16384) ~= 0 then line('Ex'); end
    line('Stack: ' .. item.Basic.stackSize);
    local gear = item.Equipment;
    if gear then
        line('Level: ' .. gear.level);
        local jobs = {};
        for name, value in pairs(((items.Index().Enums or {}).job) or {}) do
            if value > 0 and bit.band(gear.jobs, bit.lshift(1, value - 1)) ~= 0 then
                jobs[#jobs + 1] = { Id = value, Name = name:upper() };
            end
        end
        table.sort(jobs, function(a, b) return a.Id < b.Id; end);
        local names = {};
        for _, job in ipairs(jobs) do names[#names + 1] = job.Name; end
        line('Jobs: ' .. table.concat(names, ' / '));
        -- Slot bit masks are left available in Server.Equipment.slot for each UI's layout.
    end
    if item.Weapon then
        line(('Damage: %s; server delay: %s'):format(item.Weapon.dmg, item.Weapon.delay));
    end
    for _, mod in ipairs(item.Mods or {}) do
        line(('%s: %+d (server units)'):format(items.ModName(mod.modId), mod.value));
    end
    if item.Usable and item.Usable.reuseDelay > 0 then
        line(('Reuse: %s seconds; equip-to-use: %s seconds'):format(item.Usable.reuseDelay, item.Usable.useDelay));
    end
    if item.Food then
        line(('Food duration: %s seconds'):format(item.Food.Duration));
        for _, mod in ipairs(item.Food.Mods) do
            line(('Food %s: %+d (server units)'):format(mod.Name, mod.Value));
        end
    end
    if item.Changed then model.Warnings[#model.Warnings + 1] = 'Phoenix SQL differs from base data.'; end
    if item.Overrides then model.Warnings[#model.Warnings + 1] = 'Lua item overrides declared; consult script evidence for behavior and runtime gates.'; end
    if item.Script and not item.Food then model.Warnings[#model.Warnings + 1] = 'Scripted behavior is not fully summarized here.'; end
    if model.ClientDescription then model.Warnings[#model.Warnings + 1] = 'Client description is presentation text, not verified server behavior.'; end
    return model;
end

gamedata.OnChange(function () items.Clear(); end); -- another server's data chosen

return items;
