-- Reuse Zone's floor selection, transforms and reviewed boundaries without loading its addon
-- or polluting this addon's package cache with generic names such as data.all_maps.
local M = {}
function M.New(root)
    local modules = {}
    local function Load(name)
        if modules[name] then return modules[name] end
        if name ~= 'area_geometry' and name ~= 'map_catalog' and name ~= 'map_position'
            and name ~= 'area_tracking' and not name:match('^data%.') then return require(name) end
        local chunk = assert(loadfile(root .. name:gsub('%.', '/') .. '.lua'))
        setfenv(chunk, setmetatable({ require = Load }, { __index = _G }))
        modules[name] = chunk()
        return modules[name]
    end
    local position = Load('map_position')
    local tracker = Load('area_tracking').new(position.new(ashita.memory))
    tracker.state.debug = true -- Sample silently, just like Zone's location line.
    local nextSample, lastZone = 0, nil
    return function(zone, now)
        now = now or os.clock()
        if zone ~= lastZone or now >= nextSample then
            lastZone, nextSample = zone, now + 0.2
            tracker:sample(zone, position.player_position(), now)
        end
        local area = tracker.state.area
        return area and area.name or nil
    end
end
local read, attempted
function M.Read(zone)
    if not attempted then
        attempted = true
        local ok, value = pcall(function()
            return M.New(AshitaCore:GetInstallPath() .. 'addons/zone/')
        end)
        if ok then read = value end
    end
    if not read or not zone then return nil end
    local ok, name = pcall(read, zone)
    return ok and name or nil
end
return M
