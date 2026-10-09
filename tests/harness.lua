-- A stand-in for Ashita, enough to load an addon and run its frames outside the game.
--
--     luajit tests/harness.lua <addon name> <addon file> <check file>
--
-- The addon is loaded with imgui, the settings library, the game's memory and the rest replaced by
-- stubs that do nothing much and count what they are asked; the check file then drives it through
-- the table H and prints what it finds. It proves that the code loads, runs and takes the paths
-- expected: not that anything looks right, or that the game agrees.
local addonName, target, check = arg[1], arg[2], arg[3]
local root = debug.getinfo(1, 'S').source:match('^@(.*)tests/harness%.lua$') or './'
package.path = root .. 'addons/libs/?.lua;' .. package.path
-- an addon of several files finds its own beside it, as it does in Ashita
package.path = (target:match('^(.*)/[^/]*$') or '.') .. '/?.lua;' .. package.path

local handlers, present, calls, printed, clock = {}, {}, {}, {}, 0
os.clock = function() return clock end
local realprint = print
print = function(...) printed[#printed + 1] = (table.concat({ ... }, ' '):gsub('[%z\1-\31]', '')) end

-- what Ashita's 'common' adds to Lua
T = function(t) return setmetatable(t or {}, { __index = table }) end
function table.append(t, v) t[#t + 1] = v return t end
function table.extend(t, o) for _, v in ipairs(o) do t[#t + 1] = v end return t end
local sort = table.sort
function table.sort(t, f) sort(t, f) return t end
function table.join(t, sep) return table.concat(t, sep or '') end
string.args = function(s) local a = T{} for w in s:gmatch('%S+') do a[#a + 1] = w end return a end
string.replace = function(s, a, b) return (s:gsub(a:gsub('%p', '%%%0'), (b:gsub('%%', '%%%%')))) end
string.slice = function(s, first, last) return s:sub(first + 1, last) end
string.explode = function(s) local t = T{} for c in s:gmatch('.') do t[#t + 1] = c end return t end
debug.setmetatable(function() end, { __index = { bindn = function(f, ...) local a, n = { ... }, select('#', ...) return function(...) local all = { unpack(a, 1, n) } for i = 1, select('#', ...) do all[n + i] = (select(i, ...)) end return f(unpack(all, 1, n + select('#', ...))) end end } })
package.preload['common'] = function() return true end

addon = { name = addonName, path = 'C:\\ashita\\addons\\' .. addonName .. '\\' }

-- imgui: every call is counted; those in ret answer with what is given there
local ret = { GetCursorScreenPos = { 10, 20 }, GetCursorPosX = { 5 }, CalcTextSize = { 7, 14 }, GetWindowPos = { 100, 200 },
    GetWindowSize = { 300, 150 }, GetItemRectSize = { 280, 40 }, GetContentRegionAvail = { 200, 100 }, Begin = { true }, BeginTabBar = { true },
    BeginTable = { true }, GetColorU32 = { 1 }, IsMouseDown = { false }, IsItemHovered = { false }, IsRectVisible = { true },
    Checkbox = { false }, InputInt = { false }, InputInt2 = { false }, RadioButton = { false }, Button = { false }, Selectable = { false },
    ColorEdit4 = { false }, SliderInt = { false }, SliderFloat = { false }, BeginPopupContextItem = { false }, BeginPopupModal = { false }, BeginPopup = { false } }
local drawList = setmetatable({}, { __index = function(_, k) return function() calls['draw.' .. k] = (calls['draw.' .. k] or 0) + 1 end end })
local selected, tabsBegun = nil, 0
local imgui = setmetatable({}, { __index = function(_, k) return function(...)
    calls[k] = (calls[k] or 0) + 1
    if k == 'GetWindowDrawList' or k == 'GetBackgroundDrawList' or k == 'GetForegroundDrawList' then return drawList end
    if k == 'GetStyle' then return { WindowRounding = 0 } end
    if k == 'GetIO' then return { DisplaySize = { x = 1920, y = 1080 } } end
    if k == 'Selectable' then local label, on = ... if on then selected = label:match('^[^#]+') end end
    -- one tab of a tab bar is showing at a time: the first
    if k == 'BeginTabBar' then tabsBegun = 0 end
    if k == 'BeginTabItem' then tabsBegun = tabsBegun + 1 return tabsBegun == 1 end
    local r = ret[k] if r then return unpack(r) end
end end })
package.preload['imgui'] = function() return imgui end
package.preload['d3d8'] = function() return { get_device = function() return nil end, gc_safe_release = function(x) return x end } end
local flags = 0
setmetatable(_G, { __index = function(_, k) if type(k) == 'string' and k:match('^ImGui') then flags = flags + 1 rawset(_G, k, flags) return flags end end })

-- the settings library: one character, logged in; whatever is loaded is kept to look at
local saves, store = 0, nil
package.preload['settings'] = function() return { logged_in = true, name = 'Tester', server_id = 1,
    load = function(d) store = d return d end, save = function() saves = saves + 1 end,
    register = function(_, _, f) handlers.settings = f end } end

-- xitools' settings, for the addons that bring theirs over from it: the fixture stands in for the file
local realLoadfile = loadfile
loadfile = function(p) if p:find('xitools') then return realLoadfile(root .. 'tests/fixtures/xitools_settings.lua') end return realLoadfile(p) end

local playing, pool, lots, sent, sounds, raised = false, 0, {}, {}, {}, {}
function GetPlayerEntity() return playing and {} or nil end
ashita = { interface_version = 4,
    events = { register = function(e, _, f) handlers[e] = handlers[e] or {}; table.insert(handlers[e], f) end },
    memory = { find = function() return 0 end, read_uint32 = function() return 0 end, read_uint8 = function() return 0 end },
    fs = { exists = function() return true end, create_directory = function() end, get_directory = function() return {} end },
    time = { qpf = function() return { q = 1 } end, qpc = function() return { q = 0 } end }, tasks = { once = function() end },
    misc = { play_sound = function(p) sounds[#sounds + 1] = p:match('([^\\]+)%.wav') end } }
local inventory = { GetContainerItem = function() return nil end, GetContainerCountMax = function() return 0 end,
    GetTreasurePoolItem = function(_, i) if i < pool then return { ItemId = 100 + i, DropTime = 5, WinningLot = 0, WinningEntityName = '', Lot = lots[i] or 0 } end end }
AshitaCore = { GetInstallPath = function() return 'C:\\ashita' end,
    GetMemoryManager = function() return { GetInventory = function() return inventory end,
        GetPlayer = function() return { GetMainJob = function() return 18 end } end,
        GetParty = function() return { GetMemberTargetIndex = function() return 0 end, GetMemberName = function() return 'Tester' end } end } end,
    GetResourceManager = function() return { GetItemById = function(_, id) return { Id = id, Name = { 'Item ' .. id } } end } end,
    GetPointerManager = function() return { Get = function() return 0 end } end,
    GetPluginManager = function() return { RaiseEvent = function(_, name, data) raised[#raised + 1] = name .. ' ' .. string.char(unpack(data)) end } end,
    GetChatManager = function() return { QueueCommand = function() end } end,
    GetPacketManager = function() return { AddOutgoingPacket = function(_, id, data) sent[#sent + 1] = ('%X:%s'):format(id, tostring(data and data[5])) end } end }
struct = { pack = function() return { totable = function() return {} end } end, unpack = function() return 1 end }

local function fire(event, e) for _, f in ipairs(handlers[event] or {}) do f(e) end return e end

-- What a check file works with
H = {
    print = realprint, calls = calls, ret = ret, printed = printed, sent = sent, sounds = sounds, raised = raised,
    options = function() return store end,
    saves = function() return saves end,
    selected = function() return selected end,             -- the menu choice last drawn as highlighted
    play = function(v) playing = v end,                    -- whether there is a player (false: loading)
    pool = function(count) pool = count end,               -- how many items are in the treasure pool
    frames = function(count) for _ = 1, count or 1 do clock = clock + 0.03; fire('d3d_present') end end,
    command = function(text) return fire('command', { command = text, blocked = false }).blocked end,
    packet = function(id) fire('packet_in', { id = id, data = '' }) end,
    load = function() fire('load') end,                    -- Ashita's own, once the addon's file has run
    unload = function() fire('unload') end,
    -- an XInput button, pressed and let go, then a frame; returns whether the game was kept from the press
    tap = function(button)
        local blocked = fire('xinput_button', { button = button, state = 1, blocked = false }).blocked
        fire('xinput_button', { button = button, state = 0, blocked = false })
        H.frames(1)
        return blocked
    end,
    button = function(button, state) return fire('xinput_button', { button = button, state = state, blocked = false }).blocked end,
    plugin = function(name, data) fire('plugin_event', { name = name, data = data }) end,
    Button = { DpadUp = 0, DpadDown = 1, DpadLeft = 2, DpadRight = 3, LB = 8, RB = 9, A = 12, B = 13, X = 14, Y = 15, L2 = 16, R2 = 17 },
}

dofile(target)
dofile(check)
