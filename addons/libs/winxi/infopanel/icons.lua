-- The clock's own icons for the day and the weather, where a set has them; where it has not, the
-- game draws its own from its DATs, as ever.
--
--   icons.Sets()                 the sets to choose from: { key, label } for each folder of
--                                addons\clock\icons, by name
--   icons.Day(set, weekday)      the set's icon for the day (0 Firesday .. 7 Darksday): a handle imgui
--                                can draw, or nil where the set has none
--   icons.Weather(set, weather)  the set's icon for the weather (the game's id, 0 to 19), whether it
--                                is the double weather, and whether the game draws an icon for it
--                                (4 to 19) or none (0 to 3: none, sunshine, clouds, fog), so that the
--                                set's goes where the game's would; nil where the set has none
--   icons.Load(path)             loads one picture (a field, for the checks to stand in for)
--
-- A set is a folder, addons\clock\icons\<set>\, holding any of
--     days\firesday.png  earthsday  watersday  windsday  iceday  lightningday  lightsday  darksday
--     weather\fire.png   ice  wind  earth  thunder  water  light  dark
--     weather\clear.png  (no weather, and sunshine)  clouds  fog: for skies the game draws no icon for
-- Each is drawn where the game draws that icon, at its size, so square pictures suit it best. Double
-- weather is the weather's icon twice, side by side, as the game draws it.
local ffi = require('ffi')
local d3d = require('d3d8')

local icons = {}

icons.None = '' -- the game's icons alone

local DAYS = { 'firesday', 'earthsday', 'watersday', 'windsday', 'iceday', 'lightningday', 'lightsday', 'darksday' }
-- The weather ids in pairs, the single then the double, from 4: hot spell, rain, dust storm, wind,
-- snow, thunder, aurora, gloom; their elements, by which the game picks its icon
local ELEMENTS = { 'fire', 'water', 'earth', 'wind', 'ice', 'thunder', 'light', 'dark' }
-- 0 to 3, which the game draws no icon for: none and sunshine are both a clear sky
local SKIES = { [0] = 'clear', [1] = 'clear', [2] = 'clouds', [3] = 'fog' }

local root = nil
local handles = {} -- path -> its handle, or false where there is none or it will not load
local kept = {}    -- the textures themselves, held so that they are not let go

local function Root()
    root = root or ('%s\\addons\\libs\\winxi\\infopanel\\icons\\'):format(AshitaCore:GetInstallPath())
    return root
end

function icons.Load(path)
    local device = d3d.get_device()
    if device == nil then return false end
    local pointer = ffi.new('IDirect3DTexture8*[1]')
    if ffi.C.D3DXCreateTextureFromFileA(device, path, pointer) ~= ffi.C.S_OK then return false end
    local texture = d3d.gc_safe_release(ffi.cast('IDirect3DTexture8*', pointer[0]))
    kept[#kept + 1] = texture
    return tonumber(ffi.cast('uint32_t', texture))
end

-- Looked for once each, and loaded once each
local function Picture(set, folder, name)
    if set == nil or set == icons.None or name == nil then return nil end
    local path = ('%s%s\\%s\\%s.png'):format(Root(), set, folder, name)
    local handle = handles[path]
    if handle == nil then
        handle = ashita.fs.exists(path) and icons.Load(path) or false
        handles[path] = handle
    end
    return handle or nil
end

-- A host can keep its existing custom icon directory; chatbox uses the shared one.
function icons.Root(path)
    if root ~= path then icons.Forget(); root = path end
end

function icons.Sets()
    local sets = {}
    local ok, entries = pcall(ashita.fs.get_directory, Root())
    for _, entry in ipairs(ok and type(entries) == 'table' and entries or {}) do
        entry = tostring(entry)
        -- folders alone: a name with no extension, that is a folder
        if not entry:find('%.%w+$') and ashita.fs.exists(Root() .. entry .. '\\') then
            sets[#sets + 1] = { key = entry, label = entry }
        end
    end
    table.sort(sets, function(a, b) return a.label:lower() < b.label:lower() end)
    return sets
end

function icons.Day(set, weekday)
    return Picture(set, 'days', DAYS[(tonumber(weekday) or -1) + 1])
end

function icons.Weather(set, weather)
    weather = tonumber(weather)
    if weather == nil or weather < 0 or weather > 19 then return nil end
    if weather < 4 then
        local handle = Picture(set, 'weather', SKIES[weather])
        if handle == nil then return nil end
        return handle, false, false
    end
    local handle = Picture(set, 'weather', ELEMENTS[math.floor((weather - 4) / 2) + 1])
    if handle == nil then return nil end
    return handle, weather % 2 == 1, true
end

-- Another set chosen: what was loaded is looked for again (and a picture added since is found).
-- Letting the textures go is safe: uihook holds its own reference to any it is still drawing.
function icons.Forget()
    handles, kept = {}, {}
end

return icons
