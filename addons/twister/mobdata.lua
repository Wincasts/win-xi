-- What is known of the game's mobs is in mobs.lua, which generate_mobs.py makes and says the layout
-- of: the kinds of mob there are (sheep, crabs, quadav) with what each kind's mobs can do, and for
-- every area the names of its mobs of each kind.
--
-- It is read when it is wanted and not kept: by the Triggers tab, to make a trigger with, which lets
-- go of it when the settings are closed; and once in an area, on arriving there with a trigger made,
-- to find out which kind each of the area's mobs is, so that it is not read in the middle of a fight.
-- That is kept for the one area, being small: a few dozen names.
local mobData = nil -- mobs.lua as it is, or false if it cannot be read
local area = nil    -- the one area: { zone, kindOf = a mob's name in small letters -> its kind, among = kind -> its mobs there, as written }

local function MobData()
    if mobData == nil then
        mobData = false
        local chunk = loadfile(addon.path .. 'mobs.lua')
        if chunk ~= nil then
            local ok, found = pcall(chunk)
            if ok and type(found) == 'table' and type(found.zones) == 'table' and type(found.kinds) == 'table' and type(found.lists) == 'table' then
                mobData = found
            end
        end
    end
    return mobData or nil
end

local actionNames -- what spells and moves are called, as far as asked: below

local function ForgetMobData()
    mobData = nil
    -- the names were for the lists of the Triggers tab
    actionNames.spell, actionNames.move = { }, { }
end

-- An area's mobs: which kind each is, and each kind's mobs. Nothing in either for an area nothing
-- is known of.
local function Area(zone)
    if area == nil or area.zone ~= zone then
        area = { zone = zone, kindOf = { }, among = { } }
        local data = MobData()
        local written = data ~= nil and data.zones[zone] or nil
        if written ~= nil then
            for kind, names in written:gmatch('([^:;]+):([^;]*);') do
                area.among[kind] = names
                for name in names:gmatch('[^|]+') do
                    area.kindOf[name:lower()] = kind
                end
            end
        end
    end
    return area
end

local function CurrentZone()
    return AshitaCore:GetMemoryManager():GetParty():GetMemberZone(0)
end

-- A name out of the game's own files, or nil: some come with what ends them still on the end
local function GameName(read, ...)
    local ok, name = pcall(read, ...)
    if not ok or type(name) ~= 'string' then
        return nil
    end
    name = name:gsub('[%z\1-\31].*', '')
    return name ~= '' and name or nil
end

-- What a spell, a weaponskill or an ability is called. A mob's weaponskills and abilities over 256
-- are named in the game's list of monsters' abilities, and those under it are the players' own. Where
-- the game has no name, the server's is used, from mobs.lua.
actionNames = { spell = { }, move = { } }

local function ActionName(kind, id)
    local names = actionNames[kind == 'spell' and 'spell' or 'move']
    local name = names[id]
    if name ~= nil then
        return name
    end
    local resources = AshitaCore:GetResourceManager()
    if kind == 'spell' then
        name = GameName(function() return resources:GetSpellById(id).Name[1] end)
            or ('Spell %d'):format(id)
    else
        if id > 256 then
            name = GameName(function() return resources:GetString('monsters.abilities', id - 256, 2) end)
        else
            name = GameName(function() return resources:GetAbilityById(id).Name[1] end)
        end
        if name == nil then
            local data = MobData()
            name = data ~= nil and type(data.names) == 'string' and data.names:match((';%d=([^;]*);'):format(id))
                or ('%s %d'):format(kind == 'skill' and 'Weaponskill' or 'Ability', id)
        end
    end
    names[id] = name
    return name
end

local zoneNames = { }

local function ZoneName(zone)
    local name = zoneNames[zone]
    if name == nil then
        local resources = AshitaCore:GetResourceManager()
        name = GameName(function() return resources:GetString('zones.names', zone) end) or ('Area %d'):format(zone)
        zoneNames[zone] = name
    end
    return name
end

return {
    Read = MobData,
    -- whether mobs.lua is held at the moment, or was found not to be readable
    IsRead = function() return mobData ~= nil end,
    Forget = ForgetMobData,
    Area = Area,
    CurrentZone = CurrentZone,
    ActionName = ActionName,
    ZoneName = ZoneName,
}
