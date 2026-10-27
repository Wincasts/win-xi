-- Shared paged reader for Phoenix definitions. See catalogs.md for schemas and units.
-- Tables returned by Get/Index/Ids/Script are shared; treat them as read-only.
local gamedata = require('winxi.gamedata');
local catalog = {};

local function integer(id)
    return type(id) == 'number' and id >= 0 and id < 65536 and id == math.floor(id);
end

function catalog.New(kind)
    assert(type(kind) == 'string' and kind:match('^[%w_]+$'), 'invalid catalog name');
    local api = {};
    local index, pages, scripts = nil, {}, {};

    function api.Clear()
        index, pages, scripts = nil, {}, {};
    end
    gamedata.OnChange(function () api.Clear(); end); -- another server's data chosen

    function api.Index()
        index = index or gamedata.Read(kind, 'index') or {};
        return index;
    end

    function api.Ids()
        return api.Index().Ids or {};
    end

    function api.Get(id)
        if not integer(id) then return nil; end
        local size = api.Index().PageSize;
        if not size then return nil; end
        local page = math.floor(id / size);
        if pages[page] == nil then pages[page] = gamedata.Read(kind, page) or false; end
        return pages[page] and pages[page][id] or nil;
    end

    function api.Script(path)
        local page = (api.Index().Scripts or {})[path];
        if page == nil then return nil; end
        if scripts[page] == nil then scripts[page] = gamedata.Read(kind, 'script_' .. page) or false; end
        return scripts[page] and scripts[page][path] or nil;
    end

    -- ASCII case-insensitive literal substring search. No patterns or implicit client calls.
    function api.Search(query, limit)
        if type(query) ~= 'string' then return {}; end
        query = query:lower();
        local found = {};
        if limit ~= nil and (not integer(limit) or limit == 0) then return found; end
        for _, id in ipairs(api.Ids()) do
            local record = api.Get(id);
            if record and record.Name:lower():find(query, 1, true) then
                found[#found + 1] = record;
                if limit and #found >= limit then break; end
            end
        end
        return found;
    end

    function api.Rows(id, job, level)
        local found, record = {}, api.Get(id);
        if not record then return found; end
        for _, row in ipairs(record.Rows or {}) do
            if (job == nil or row.job == job) and (level == nil or row.level <= level) then
                found[#found + 1] = row;
            end
        end
        return found;
    end

    function api.EnumName(enum, value)
        for name, id in pairs((api.Index().Enums or {})[enum] or {}) do
            if id == value then return name:upper(); end
        end
        return nil;
    end

    -- Lists definitions, NOT learned/unlocked/usable actions. Content/merit gates remain raw.
    -- WS Jobs values are permission bytes, never job levels; use ForSkill for skill thresholds.
    function api.ForJob(job, level)
        if not integer(job) or job == 0 or (level ~= nil and not integer(level)) then return {}; end
        local found = {};
        for _, id in ipairs(api.Ids()) do
            local record = api.Get(id);
            local value = record and record.Jobs and record.Jobs[job];
            local matches = value ~= nil and (kind == 'weaponskills' or level == nil or value <= level);
            if record and record.Rows then matches = #api.Rows(id, job, level) > 0; end
            if record and record.Ranks then matches = record.Ranks[job] ~= nil; end
            if matches then found[#found + 1] = record; end
        end
        return found;
    end

    function api.ForSkill(skill, maxSkill)
        local found = {};
        if not integer(skill) or (maxSkill ~= nil and not integer(maxSkill)) then return found; end
        for _, id in ipairs(api.Ids()) do
            local record = api.Get(id);
            local data = record and record.Data;
            if data and (kind == 'weaponskills' and data.type == skill or kind == 'spells' and data.skill == skill)
                and (kind ~= 'weaponskills' or maxSkill == nil or data.skilllevel <= maxSkill) then
                found[#found + 1] = record;
            end
        end
        return found;
    end

    -- No client resource objects are cached. Call explicitly from an addon with Ashita available.
    function api.ClientResource(id)
        if not api.Get(id) or not AshitaCore then return nil; end
        local ok, resource = pcall(function()
            local manager = AshitaCore:GetResourceManager();
            if kind == 'spells' then return manager:GetSpellById(id); end
            if kind == 'abilities' then return manager:GetAbilityById(id + 512); end
            if kind == 'weaponskills' then return manager:GetAbilityById(id); end
        end);
        return ok and resource or nil;
    end

    -- Presentation only. Client descriptions never replace server fields.
    function api.Tooltip(id, resource)
        local record = api.Get(id);
        if not record then return nil; end
        local model = { Id = id, Name = record.Name, Server = record, Lines = {}, Warnings = {},
            Variants = record.Rows, Charges = record.Charges, Blue = record.Blue, BlueMods = record.BlueMods };
        if resource then
            model.Name = resource.Name and resource.Name[1] or model.Name;
            model.ClientDescription = resource.Description and resource.Description[1] or nil;
        end
        local function line(text) model.Lines[#model.Lines + 1] = text; end
        local data = record.Data;
        if kind == 'spells' and data then
            line(('MP: %d'):format(data.mpCost));
            line(('Base cast: %g s; recast: %g s'):format(data.castTime / 1000, data.recastTime / 1000));
            line(('Range: %g'):format(data.spell_range / 10));
            line(('Element: %s; skill: %s'):format(api.EnumName('element', data.element) or data.element,
                api.EnumName('skill_type', data.skill) or data.skill));
        elseif kind == 'abilities' and data then
            line(('Level: %d; base recast: %g s'):format(data.level, data.recastTime));
            line(('Range: %g'):format(data.range));
        elseif kind == 'weaponskills' and data then
            line(('Skill requirement: %d; range: %g'):format(data.skilllevel, data.range));
            local names = {};
            local lookup = {};
            for name, value in pairs((api.Index().Enums or {}).skillchain or {}) do lookup[value] = name; end
            for _, value in ipairs({ data.primary_sc, data.secondary_sc, data.tertiary_sc }) do
                if value ~= 0 then names[#names + 1] = lookup[value] or tostring(value); end
            end
            if #names > 0 then line('Skillchain: ' .. table.concat(names, ' / ')); end
        elseif kind == 'skills' then
            line('Skill ranks and caps are available in the structured definition.');
        elseif kind == 'traits' then
            line('Job/level/rank variants are separate; modifier values use server units.');
        end
        model.Warnings[#model.Warnings + 1] = 'Definition only: content restrictions, unlocks and player state are not evaluated.';
        if record.Changed then model.Warnings[#model.Warnings + 1] = 'Enabled Phoenix SQL differs from base data.'; end
        if record.Overrides then model.Warnings[#model.Warnings + 1] = 'Lua overrides declared; runtime gates and super chains are not evaluated.'; end
        if record.Sources then model.Warnings[#model.Warnings + 1] = 'Scripted effects and calculations are not fully summarized.'; end
        if resource then model.Warnings[#model.Warnings + 1] = 'Client text may differ from Phoenix server behavior.'; end
        return model;
    end

    return api;
end

return catalog;
