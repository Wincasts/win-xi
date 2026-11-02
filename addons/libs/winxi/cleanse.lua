-- winxi.cleanse: what can take a status off, and whether the player can, now.
--
--     cleanse.Kind(status)     'cure' for a debuff a friend can have taken off (Erase, a -na spell or a
--                              waltz), 'dispel' for a buff Dispel and the like take off, or nil
--     cleanse.Spells(status)   the spells that take it off, as the server's scripts have them: a list of
--                              spell numbers, empty where none does
--     cleanse.Can(status)      whether the player can cast one of those spells now: learned, and its job's
--                              level reached by the main job's level, or the support job's while it is not
--                              restricted. The levels are the game's own, so a level sync or a level
--                              restriction is followed as it lowers them
--
-- What each spell takes off is the server's (scripts/actions/spells): Erase what the server flags
-- erasable; Poisona, Paralyna, Blindna, Silena, Stona, Viruna and Cursna their own; Esuna its list; Dispel,
-- Dispelga, Magic Finale, Blank Gaze and Geist Wall what it flags dispelable. Which jobs learn each, at
-- which level, is winxi.spells'. Abilities (a waltz) are not counted yet, and a blue magic spell counts
-- when learned, whether or not it is set.
local statuses = require('winxi.statuses');
local spells = require('winxi.spells');

local cleanse = {};

local ERASE, ESUNA = 143, 95;
local DISPELLING = { 260, 360, 462, 592, 605 }; -- Dispel, Dispelga, Magic Finale, Blank Gaze, Geist Wall
-- status -> the -na spells that take it off
local NA = {
    [3] = { 14 },          -- poison: Poisona
    [4] = { 15 },          -- paralysis: Paralyna
    [5] = { 16 },          -- blindness: Blindna
    [6] = { 17 },          -- silence: Silena
    [7] = { 18 },          -- petrification: Stona
    [8] = { 19 },          -- disease: Viruna
    [31] = { 19 },         -- plague: Viruna
    [9] = { 20 },          -- curse: Cursna
    [20] = { 20 },         -- curse II: Cursna
    [30] = { 20 },         -- bane: Cursna
    [15] = { 20 },         -- doom: Cursna, by chance
};
-- and Esuna's
local ESUNA_TAKES = { [156] = true, [5] = true, [4] = true, [3] = true, [9] = true, [20] = true, [8] = true, [31] = true };
local SJ_RESTRICTION = 157;

local kinds, lists = {}, {};

function cleanse.Kind(status)
    local kind = kinds[status];
    if kind == nil then
        local removable = statuses.Removable(status);
        if removable == 'erase' or removable == 'waltz' or NA[status] ~= nil then
            kind = 'cure';
        elseif removable == 'dispel' then
            kind = 'dispel';
        else
            kind = false;
        end
        kinds[status] = kind;
    end
    return kind or nil;
end

function cleanse.Spells(status)
    local list = lists[status];
    if list == nil then
        list = {};
        local kind = cleanse.Kind(status);
        if kind == 'dispel' then
            for _, id in ipairs(DISPELLING) do list[#list + 1] = id; end
        elseif kind == 'cure' then
            if statuses.Removable(status) == 'erase' then list[#list + 1] = ERASE; end
            for _, id in ipairs(NA[status] or {}) do list[#list + 1] = id; end
            if ESUNA_TAKES[status] then list[#list + 1] = ESUNA; end
        end
        lists[status] = list;
    end
    return list;
end

-- The spells the player can cast now, worked out again when the jobs or levels change, and every few
-- seconds for one learned in between
-- seconds; the jobs and levels are looked at again no more often than LOOK
local REFRESH, LOOK = 2, 0.25;
local castable, castableAt, castableFor, lookedAt = {}, -REFRESH, nil, -LOOK;

local function Castable()
    local now = os.clock();
    if now - lookedAt < LOOK then
        return castable;
    end
    lookedAt = now;
    local ok, player = pcall(function () return AshitaCore:GetMemoryManager():GetPlayer(); end);
    if not ok or player == nil then
        return castable;
    end
    local read, main, mainLevel, sub, subLevel, icons = pcall(function ()
        return player:GetMainJob(), player:GetMainJobLevel(), player:GetSubJob(), player:GetSubJobLevel(), player:GetStatusIcons();
    end);
    if not read then
        return castable;
    end
    -- a support job that is restricted counts for nothing
    if icons ~= nil then
        for slot = 1, 32 do
            if icons[slot] == SJ_RESTRICTION then subLevel = 0; break; end
        end
    end
    local key = ('%d:%d:%d:%d'):format(main or 0, mainLevel or 0, sub or 0, subLevel or 0);
    if key == castableFor and now - castableAt < REFRESH then
        return castable;
    end
    castable, castableAt, castableFor = {}, now, key;
    local seen = {};
    for _, list in ipairs({ DISPELLING, { ERASE, ESUNA }, { 14, 15, 16, 17, 18, 19, 20 } }) do
        for _, id in ipairs(list) do
            if not seen[id] then
                seen[id] = true;
                local record = spells.Get(id);
                local jobs = record and record.Jobs or {};
                local mainNeeds, subNeeds = jobs[main], jobs[sub];
                local reached = (mainNeeds ~= nil and (mainLevel or 0) >= mainNeeds)
                    or (subNeeds ~= nil and (subLevel or 0) > 0 and subLevel >= subNeeds);
                local ok, learned = pcall(player.HasSpell, player, id);
                castable[id] = reached and ok and learned == true or false;
            end
        end
    end
    return castable;
end

function cleanse.Can(status)
    local list = cleanse.Spells(status);
    if #list == 0 then
        return false;
    end
    local can = Castable();
    for _, id in ipairs(list) do
        if can[id] then return true; end
    end
    return false;
end

-- Another server's data chosen: what each takes off is worked out again
function cleanse.Clear()
    kinds, lists, castableFor, lookedAt = {}, {}, nil, -LOOK;
end
require('winxi.gamedata').OnChange(cleanse.Clear);

return cleanse;
