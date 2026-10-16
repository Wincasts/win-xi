-- buff with the buffhook plugin: the work of handing the anchored bar over, counted over 120 frames
-- with 32 statuses. Counts, not a claim about frames per second.
--     luajit tests/harness.lua buff addons/buff/buff.lua tests/buff_hook_performance_check.lua [measure]
-- With measure, it prints what it counts and asserts nothing, to compare with another version.
local ffi = require('ffi')
local imgui = require('imgui')
local game = require('winxi.game')
local icons = require('winxi.statusicons')
local statuses = require('statuses')
require('hook')

local measure = arg[4] == 'measure'
local counts = { loaded = 0, finds = 0, glyphs = 0, icons = 0, menus = 0 }

for _, key in ipairs({ 'IsLoading', 'IsInterfaceHidden', 'IsEventHappening', 'IsChatExpanded', 'IsMapOpen' }) do
    game[key] = function() return false end
end
local menu = ''
game.MenuName = function() counts.menus = counts.menus + 1; return menu end

-- 32 statuses, each with a time: seconds, minutes and hours
local list = {}
for index = 1, 32 do
    list[index] = { id = 30 + index, seconds = ({ 25, 90, 7200, 600 })[index % 4 + 1] }
end
statuses.Read = function(current)
    for index = 1, 32 do current[index] = list[index] end
    return 32
end
AshitaCore.GetResourceManager = function() return {
    GetString = function(_, _, id) return 'Status ' .. id end,
    GetStatusIconByIndex = function() return { CanCancel = 1, HideTimer = 0, Description = { 'What it does.' } } end,
} end
icons.Get = function(id) counts.icons = counts.icons + 1; return 0x1000 + id, true end

-- the plugin's block
local holder = ffi.new('buffhook_t[1]')
local block = holder[0]
block.Version, block.Size, block.Hooked, block.Frame = 1, ffi.sizeof('buffhook_t'), 1, 1
block.Width, block.Height = 1920, 1080
ashita.memory.find = function(module)
    counts.finds = counts.finds + 1
    if module == 'buffhook.dll' then return tonumber(ffi.cast('uintptr_t', holder)) end
    return 0
end
ashita.memory.read_uint16 = function() return 0 end
ashita.memory.write_uint16 = function() end
local manager = AshitaCore.GetPluginManager()
local isLoaded = manager.IsLoaded
manager.IsLoaded = function(self, name) counts.loaded = counts.loaded + 1; return isLoaded(self, name) end
AshitaCore.GetPluginManager = function() return manager end
H.loaded('buffhook', true)

local font = { ContainerAtlas = { TexRef = { GetTexID = function() return 0x9000 end }, TexData = { GetTexID = function() return 0 end } } }
imgui.GetFont = function() return font end
local glyph = { X0 = 0, Y0 = 2, X1 = 5, Y1 = 12, U0 = 0, V0 = 0, U1 = 0.1, V1 = 1, AdvanceX = 6, Visible = 1 }
local baked = { FindGlyph = function() counts.glyphs = counts.glyphs + 1; return glyph end }
imgui.GetFontBaked = function() return baked end

H.ret.GetMousePos = { -1000, -1000 }
local o = H.options()
o.fadeInOut[1] = false
H.play(true)

local function sample(label, frames)
    for key in pairs(counts) do counts[key] = 0 end
    local metrics = H.calls.CalcTextSize or 0
    local windows = H.calls.Begin or 0
    collectgarbage('collect'); collectgarbage('stop')
    local memory = collectgarbage('count')
    for _ = 1, frames do
        block.Frame = block.Frame + 1
        block.DrawnFrame = block.Frame
        H.frames(1)
    end
    local allocated = (collectgarbage('count') - memory) / frames
    collectgarbage('restart')
    local result = { allocated = allocated, metrics = (H.calls.CalcTextSize or 0) - metrics, windows = (H.calls.Begin or 0) - windows }
    for key, value in pairs(counts) do result[key] = value end
    H.print(('%s: %d frames | quads %d | plugin asked %d | memory finds %d | glyph lookups %d | text measurements %d | icons %d | menu checks %d | windows %d | %.2f KiB/frame')
        :format(label, frames, block.Count, result.loaded, result.finds, result.glyphs, result.metrics, result.icons, result.menus, result.windows, allocated))
    return result
end

H.frames(2) -- warm the label and width caches
-- the harness makes a stand-in for each imgui function as it is asked for: kept, so that what is
-- counted as made each frame is the addon's
block.OriginX, block.OriginY, H.ret.GetMousePos = 100, 50, { 101, 51 }
block.Frame = block.Frame + 1; block.DrawnFrame = block.Frame; H.frames(1)
H.ret.GetMousePos = { -1000, -1000 }
for name in pairs(H.calls) do
    if not name:find('^draw%.') then rawset(imgui, name, imgui[name]) end
end
local display = { DisplaySize = { x = 1920, y = 1080 } }
rawset(imgui, 'GetIO', function() return display end)
H.frames(10)
local warm = sample('32 statuses with times, handed over', 120)
H.ret.GetMousePos = { 101, 51 }
local hovered = sample('the same, the mouse over the first', 120)
H.ret.GetMousePos = { -1000, -1000 }
o.showTimers[1] = false
local untimed = sample('without times', 120)
o.showTimers[1] = true
o.isVisible[1] = false
local hidden = sample('switched off', 120)
o.isVisible[1] = true

if measure then return end
assert(warm.loaded == 120 and warm.finds == 0, 'the plugin is asked after once a frame, its block found once')
assert(warm.icons == 32 * 120 and warm.windows == 0)
assert(warm.metrics == 0, 'label widths are measured once each')
assert(warm.glyphs == 6 * 120, 'each of the six letters (2, 5, 1, m, h, 0) is looked up once a frame, however often it is written')
assert(warm.allocated < 0.5, 'next to nothing is made each frame')
assert(hovered.windows == 120 and hovered.allocated < 0.5)
assert(untimed.glyphs == 0 and untimed.metrics == 0)
assert(hidden.icons == 0 and hidden.glyphs == 0)
H.print('Hooked hot path budgets: passed')
