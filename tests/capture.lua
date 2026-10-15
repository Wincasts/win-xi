-- Records what an addon draws, on top of the harness: every call it makes on a draw list, and the few
-- imgui calls that say how big and where things are, as lines of text to compare with a kept copy.
--
--     luajit tests/capture.lua <addon name> <addon file> <scene file> <saved settings> [variant]
--
-- With "measure" after the variant, nothing is printed of what is drawn: once the scene has run, the
-- windows are put back as they are in play and two hundred frames are counted, for what one costs:
-- calls on the draw lists, changes of image on them (each is a separate batch to the renderer),
-- colours packed, fonts pushed, text measured, and memory made.
--
-- The scene file sets the game up and says which frames to keep (see tests/party_scene.lua). The
-- saved settings are a settings file as the addon wrote it, loaded in place of none: the scene may
-- change them first, for a variant. Image files "load" here, so that what is drawn with which image
-- is recorded too, and a colour is recorded as itself rather than as the harness's one number.
local addonName, target, scene, savedPath, variant, measuring = arg[1], arg[2], arg[3], arg[4], arg[5], arg[6] == 'measure'

CAPTURE = { variant = variant or 'plain', tweak = nil }
local recorded, recording = {}, false
local realprint = print

local function note(...)
    if not recording then return end
    local parts = { ... }
    for i, part in ipairs(parts) do
        if type(part) == 'number' then
            parts[i] = ('%.2f'):format(part):gsub('%.?0+$', '')
        elseif type(part) == 'table' then
            local inner = {}
            for j = 1, #part do inner[j] = type(part[j]) == 'number' and ('%.2f'):format(part[j]):gsub('%.?0+$', '') or tostring(part[j]) end
            parts[i] = '(' .. table.concat(inner, ',') .. ')'
        else
            parts[i] = tostring(part)
        end
    end
    recorded[#recorded + 1] = table.concat(parts, ' ')
end

-- keeps the next frames' calls; CAPTURE.dump prints them under a heading and stops
function CAPTURE.start() recorded, recording = {}, true end
function CAPTURE.dump(label)
    recording = false
    if measuring then return end
    realprint(('## %s (%s): %d calls'):format(label, CAPTURE.variant, #recorded))
    for _, line in ipairs(recorded) do realprint(line) end
end

-- textures: each image file is its own, named for the file; anything made from memory is numbered
local textureNames, nextHandle, fromMemory = {}, 1000, 0
local function newTexture(name) nextHandle = nextHandle + 1; textureNames[nextHandle] = name; return nextHandle end
package.preload['ffi'] = function()
    return {
        new = function() return { [0] = 0 } end,
        cast = function(_, value) return value end,
        C = { S_OK = 0, D3DFMT_A8R8G8B8 = 0, D3DPOOL_MANAGED = 0, D3DX_DEFAULT = 0,
            D3DXCreateTextureFromFileA = function(_, path, pointer)
                pointer[0] = newTexture(path:match('([^/\\]+)$'))
                return 0
            end,
            D3DXCreateTextureFromFileInMemoryEx = function(...)
                local pointer = select(select('#', ...), ...)
                fromMemory = fromMemory + 1
                pointer[0] = newTexture('memory' .. fromMemory)
                return 0
            end },
    }
end

arg = { [0] = 'tests/harness.lua', addonName, target, scene }
local harness = assert(loadfile('tests/harness.lua'))
local realdofile = dofile
dofile = function(path)
    if path == target then
        package.preload['d3d8'] = function() return { get_device = function() return {} end, gc_safe_release = function(x) return x end } end

        -- the saved settings, with whatever the defaults have that they lack
        local function fill(saved, defaults)
            for key, value in pairs(defaults) do
                if saved[key] == nil then
                    saved[key] = value
                elseif type(value) == 'table' and type(saved[key]) == 'table' then
                    fill(saved[key], value)
                end
            end
        end
        local handlersOfSettings = {}
        package.preload['settings'] = function() return { logged_in = true, name = 'Tester', server_id = 1,
            load = function(defaults)
                local saved = assert(loadfile(savedPath))()
                if CAPTURE.tweak then CAPTURE.tweak(saved, CAPTURE.variant) end
                fill(saved, defaults)
                CAPTURE.options = saved
                return saved
            end,
            save = function() end, register = function(_, _, f) handlersOfSettings[#handlersOfSettings + 1] = f end } end

        local imgui = require('imgui')
        -- the harness makes a function each time one of imgui's is asked for: when measuring, each is
        -- made once, so that the memory counted is the addon's own
        if measuring then
            local meta = getmetatable(imgui)
            local index = meta.__index
            meta.__index = function(self, k) local f = index(self, k) rawset(self, k, f) return f end
            local io = { DisplaySize = { x = 1920, y = 1080 } }
            rawset(imgui, 'GetIO', function() return io end)
        end
        local function pack(color)
            return ('#%02X%02X%02X%02X'):format(math.floor(color[1] * 255 + 0.5), math.floor(color[2] * 255 + 0.5), math.floor(color[3] * 255 + 0.5), math.floor(color[4] * 255 + 0.5))
        end
        if measuring then
            COUNT = { calls = {}, changes = 0, last = nil }
            local real = imgui.GetColorU32
            rawset(imgui, 'GetColorU32', function() COUNT.calls.GetColorU32 = (COUNT.calls.GetColorU32 or 0) + 1 return 1 end)
        else
            rawset(imgui, 'GetColorU32', pack)
            -- an addon that packs its colours itself (party's draw.Pack) packs them as recorded too
            local realrequire = require
            require = function(name)
                local module = realrequire(name)
                if name == 'draw' and type(module) == 'table' and module.Pack ~= nil then
                    module.Pack = pack
                end
                return module
            end
        end

        local function list(tag)
            return setmetatable({}, { __index = function(t, k)
                local f = function(_, a, ...)
                    if measuring then
                        COUNT.calls[k] = (COUNT.calls[k] or 0) + 1
                        -- text and shapes are drawn with the font's image, an image with its own
                        if k:sub(1, 3) == 'Add' then
                            local image = k == 'AddImage' and a or 'font'
                            if COUNT.last ~= image then COUNT.changes, COUNT.last = COUNT.changes + 1, image end
                        end
                    elseif k == 'AddImage' then note(tag, k, textureNames[a] or a, ...) else note(tag, k, a, ...) end
                end
                rawset(t, k, f)
                return f
            end })
        end
        local lists = { GetWindowDrawList = list('window'), GetForegroundDrawList = list('over'), GetBackgroundDrawList = list('under') }
        for name, drawList in pairs(lists) do
            rawset(imgui, name, function() return drawList end)
        end
        for _, name in ipairs({ 'Dummy', 'PushFont', 'PopFont', 'Separator', 'Begin', 'End', 'SetCursorPosY', 'Text', 'TextColored', 'SameLine', 'NewLine' }) do
            local real = imgui[name]
            -- a window by its name alone: its flags are numbers the harness makes up as they are first asked for
            if measuring then
                rawset(imgui, name, function(...) COUNT.calls[name] = (COUNT.calls[name] or 0) + 1 return real(...) end)
            else
                rawset(imgui, name, name == 'Begin' and function(window, ...) note('imgui', name, window) return real(window, ...) end
                    or function(...) note('imgui', name, ...) return real(...) end)
            end
        end
    end
    if path == scene and CAPTURE.sceneLoaded then return end
    return realdofile(path)
end

-- the scene is read first, for what it does to the saved settings; the harness then runs the addon and the scene's frames
CAPTURE.loading = true
realdofile(scene)
CAPTURE.loading = false
harness()

if measuring then
    -- as in play: nothing being arranged, the settings shut
    require('winxi.organize').SetActive(false)
    if CAPTURE.options.showConfig[1] then
        H.command(addonName == 'party' and '/pt' or '/' .. addonName)
    end
    assert(not CAPTURE.options.showConfig[1], 'measurement requires settings to be closed')
    assert(not require('winxi.organize').IsActive(), 'measurement requires Organize to be off')
    H.frames(600) -- long enough that everything has been run often enough to be compiled

    local imgui = require('imgui')
    local realCalc = imgui.CalcTextSize
    rawset(imgui, 'CalcTextSize', function(...) COUNT.calls.CalcTextSize = (COUNT.calls.CalcTextSize or 0) + 1 return realCalc(...) end)
    COUNT.calls, COUNT.changes = {}, 0
    local frameCount = 200
    collectgarbage('collect')
    local before = collectgarbage('count')
    collectgarbage('stop')
    H.frames(frameCount)
    local made = (collectgarbage('count') - before) / frameCount
    collectgarbage('restart')

    local names = {}
    for name in pairs(COUNT.calls) do names[#names + 1] = name end
    table.sort(names)
    realprint(('a frame of %s (%s):'):format(addonName, CAPTURE.variant))
    for _, name in ipairs(names) do
        if COUNT.calls[name] / frameCount >= 0.5 then realprint(('  %-16s %6.1f'):format(name, COUNT.calls[name] / frameCount)) end
    end
    realprint(('  %-16s %6.1f'):format('image changes', COUNT.changes / frameCount))
    realprint(('  %-16s %6.2f KB'):format('memory made', made))
end
