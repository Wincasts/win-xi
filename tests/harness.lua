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
local cpuClock = os.clock
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
local ret = { GetCursorScreenPos = { 10, 20 }, GetCursorPosX = { 5 }, GetCursorPosY = { 5 }, CalcTextSize = { 7, 14 }, GetWindowPos = { 100, 200 },
    GetWindowSize = { 300, 150 }, GetItemRectSize = { 280, 40 }, GetItemRectMin = { 10, 20 }, GetItemRectMax = { 60, 38 }, GetFontSize = { 14 }, GetContentRegionAvail = { 200, 100 }, Begin = { true }, BeginTabBar = { true },
    BeginTable = { true }, BeginChild = { true }, GetColorU32 = { 1 }, IsMouseDown = { false }, IsItemHovered = { false }, IsRectVisible = { true },
    Checkbox = { false }, InputInt = { false }, InputInt2 = { false }, RadioButton = { false }, Button = { false }, Selectable = { false },
    ColorEdit4 = { false }, SliderInt = { false }, SliderFloat = { false }, BeginPopupContextItem = { false }, BeginPopupModal = { false }, BeginPopup = { false } }
local drawList = setmetatable({}, { __index = function(_, k) return function() calls['draw.' .. k] = (calls['draw.' .. k] or 0) + 1 end end })
-- the tab bars begun and not yet ended, each with how many of its tabs have been begun; and which tab
-- shows: tabShown in every bar, unless tabsIn names one for that bar
local selected, bars, tabShown, tabsIn = nil, {}, 1, {}
local imgui = setmetatable({}, { __index = function(_, k) return function(...)
    calls[k] = (calls[k] or 0) + 1
    if k == 'GetWindowDrawList' or k == 'GetBackgroundDrawList' or k == 'GetForegroundDrawList' then return drawList end
    if k == 'GetStyle' then return { WindowRounding = 0, FramePadding = { x = 4, y = 2 }, ItemInnerSpacing = { x = 4, y = 4 } } end
    if k == 'GetIO' then return { DisplaySize = { x = 1920, y = 1080 } } end
    if k == 'Selectable' then local label, on = ... if on then selected = label:match('^[^#]+') end end
    -- one tab of a tab bar is showing at a time: the first, unless H.tab has chosen another
    if k == 'BeginTabBar' then bars[#bars + 1] = { id = (...), begun = 0 } end
    if k == 'EndTabBar' then bars[#bars] = nil end
    if k == 'BeginTabItem' then
        local bar = bars[#bars] or { begun = 0 }
        bar.begun = bar.begun + 1
        return bar.begun == (tabsIn[bar.id] or tabShown)
    end
    local r = ret[k] if r then return unpack(r) end
end end })
package.preload['imgui'] = function() return imgui end
package.preload['d3d8'] = function() return { get_device = function() return nil end, gc_safe_release = function(x) return x end } end
local flags = 0
-- the names imgui gave up before Ashita's 1.92 are not there, as they are not in the game
local retired = { ImGuiCol_TabActive = true, ImGuiCol_TabUnfocused = true, ImGuiCol_TabUnfocusedActive = true }
setmetatable(_G, { __index = function(_, k) if type(k) == 'string' and k:match('^ImGui') and not retired[k] then flags = flags + 1 rawset(_G, k, flags) return flags end end })

-- the settings library: one character, logged in; whatever is loaded is kept to look at
local saves, store = 0, nil
package.preload['settings'] = function() return { logged_in = true, name = 'Tester', server_id = 1,
    -- HARNESS_SAVED, if a check's stand-in sets it, is a settings file already saved: merged with the
    -- defaults as Ashita merges them (table.merge, the saved file the destination), and given back
    load = function(d)
        if HARNESS_SAVED == nil then store = d return d end
        local function merge(into, from)
            for k, v in pairs(from) do
                if type(v) == 'table' then
                    if rawget(into, k) == nil then into[k] = v else merge(into[k], v) end
                elseif rawget(into, k) == nil then
                    into[k] = v
                end
            end
            return into
        end
        store = merge(HARNESS_SAVED, d)
        return store
    end, save = function() saves = saves + 1 end,
    register = function(_, _, f) handlers.settings = f end } end

-- xitools' settings, for the addons that bring theirs over from it: the fixture stands in for the file
local realLoadfile = loadfile
loadfile = function(p) if p:find('xitools') then return realLoadfile(root .. 'tests/fixtures/xitools_settings.lua') end return realLoadfile(p) end

-- winxi's own files, the shared theme and the layouts: kept here, in memory, so that no check reads what
-- another saved, and none leaves a file named after the Ashita folder in the project
local winxiThemeFile = 'config\\addons\\winxi\\'
local themeLoadfile, realOpen = loadfile, io.open
loadfile = function(p) if p:find(winxiThemeFile, 1, true) then return nil end return themeLoadfile(p) end
io.open = function(p, mode)
    if type(p) == 'string' and p:find(winxiThemeFile, 1, true) then
        if mode ~= nil and mode:find('[wa]') then return { write = function() end, close = function() end } end
        return nil
    end
    return realOpen(p, mode)
end

local playing, loginStatus, pool, lots, sent, sounds, raised, plugins = false, 2, 0, {}, {}, {}, {}, {}
function GetPlayerEntity() return playing and {} or nil end
ashita = { interface_version = 4,
    events = { register = function(e, _, f) handlers[e] = handlers[e] or {}; table.insert(handlers[e], f) end },
    memory = { find = function() return 0 end, read_uint32 = function() return 0 end, read_uint8 = function() return 0 end },
    fs = { exists = function(path)
            -- a file of the addon's own is there if it is in the project; anything else is taken to be
            local own = type(path) == 'string' and path:sub(1, #addon.path) == addon.path and path:sub(#addon.path + 1):gsub('\\', '/')
            if own then
                local found = io.open(('%saddons/%s/%s'):format(root, addonName, own), 'rb')
                if found then found:close() end
                return found ~= nil
            end
            return true
        end, create_directory = function() end, get_directory = function() return {} end },
    time = { qpf = function() return { q = 1 } end, qpc = function() return { q = 0 } end }, tasks = { once = function() end },
    misc = { play_sound = function(p) sounds[#sounds + 1] = p:match('([^\\]+)%.wav') end },
    -- some bits of a packet where it lies, which here is the string H.packetData was given: counted from
    -- its start, the low bit of each byte first
    bits = { unpack_be = function(raw, offset, length)
        local first, value = math.floor(offset / 8), 0
        for index = 4, 0, -1 do value = value * 256 + (raw:byte(first + index + 1) or 0) end
        return math.floor(value / 2 ^ (offset % 8)) % 2 ^ length
    end } }
-- the bags: what H.bag has put in each (bag -> slot -> { Id, Count, Index, Flags }) and how big each is,
-- the gil H.gil has set, and how many times each bag's slots have been read
local contents, sizes, gil, reads, equipped = {}, {}, nil, {}, {}
local inventory = {
    GetEquippedItem = function(_, slot)
        calls.GetEquippedItem = (calls.GetEquippedItem or 0) + 1
        return equipped[slot]
    end,
    GetContainerItem = function(_, bag, slot)
        reads[bag] = (reads[bag] or 0) + 1
        if bag == 0 and slot == 0 and gil ~= nil then return { Id = 65535, Count = gil, Index = 0, Flags = 0 } end
        return contents[bag] and contents[bag][slot] or nil
    end,
    GetContainerCountMax = function(_, bag) return sizes[bag] or 0 end,
    GetTreasurePoolItem = function(_, i) if i < pool then return { ItemId = 100 + i, DropTime = 5, WinningLot = 0, WinningEntityName = '', Lot = lots[i] or 0 } end end }
AshitaCore = { GetInstallPath = function() return 'C:\\ashita' end,
    GetMemoryManager = function() return { GetInventory = function() return inventory end,
        GetPlayer = function() return { GetMainJob = function() return 18 end, GetLoginStatus = function() return loginStatus end,
            GetIsZoning = function() return 0 end, GetStatusIcons = function() return {} end } end,
        GetParty = function() return { GetMemberTargetIndex = function() return 0 end, GetMemberName = function() return 'Tester' end } end,
        GetTarget = function() return { GetIsSubTargetActive = function() return 0 end, GetSubTargetFlags = function() return 0xFFFFFFFF end,
            GetTargetIndex = function() return 0 end } end } end,
    GetResourceManager = function() return { GetItemById = function(_, id) return { Id = id, Name = { 'Item ' .. id },
        ResourceId = id, Type = id >= 20000 and 5 or 1, Flags = 0, Targets = 0, StackSize = id < 1000 and 12 or 1,
        LogNameSingular = { 'item ' .. id }, LogNamePlural = { 'items ' .. id }, Description = { 'About item ' .. id },
        Slots = 16, Skill = 0, Level = 1, Jobs = 2, Races = 0, Bitmap = '', ImageSize = 0 } end } end,
    GetPointerManager = function() return { Get = function() return 0 end } end,
    GetPluginManager = function() return { RaiseEvent = function(_, name, data) raised[#raised + 1] = name .. ' ' .. string.char(unpack(data)) end,
        IsLoaded = function(_, name) return plugins[name] == true end } end,
    GetChatManager = function() return { QueueCommand = function() end } end,
    GetPacketManager = function() return { AddOutgoingPacket = function(_, id, data) sent[#sent + 1] = ('%X:%s'):format(id, tostring(data and data[5])) end } end }
-- a byte of a packet's data, where the data has it ('B', or 'i1' signed); anything else is 1
struct = { pack = function() return { totable = function() return {} end } end, unpack = function(format, data, at)
    local byte = type(data) == 'string' and data:byte(at or 1) or nil
    if byte ~= nil and format == 'B' then return byte end
    if byte ~= nil and format == 'i1' then return byte >= 128 and byte - 256 or byte end
    return 1
end }

local function fire(event, e) for _, f in ipairs(handlers[event] or {}) do f(e) end return e end

-- What a check file works with
H = {
    print = realprint, calls = calls, ret = ret, printed = printed, sent = sent, sounds = sounds, raised = raised,
    cpuClock = cpuClock, -- real process CPU time, distinct from the simulated game clock
    options = function() return store end,
    saves = function() return saves end,
    resettle = function() handlers.settings(store) end,    -- the settings as they are, given to the addon again as if loaded afresh
    tab = function(number) tabShown = number or 1 end,     -- which tab of a tab bar is showing: the first, unless told
    tabIn = function(bar, number) tabsIn[bar] = number end, -- which tab shows in the bar of that id (nil: as H.tab says)
    selected = function() return selected end,             -- the menu choice last drawn as highlighted
    play = function(v) playing = v end,                    -- whether there is a player (false: loading)
    login = function(status) loginStatus = status end,     -- the game's login status: 2 in the world, less before
    pool = function(count) pool = count end,               -- how many items are in the treasure pool
    -- a bag of size slots, with { id, count } in its first slots; and the gil (with which the bags are loaded)
    bag = function(bag, size, items)
        sizes[bag], contents[bag] = size, {}
        for i, item in ipairs(items or {}) do contents[bag][i] = { Id = item[1], Count = item[2] or 1, Index = i, Flags = 0 } end
    end,
    equip = function(slot, bag, index)
        equipped[slot] = bag ~= nil and { Index = bag * 256 + index } or nil
    end,
    gil = function(count) gil = count; sizes[0] = sizes[0] or 30 end,
    reads = function() local r = reads reads = {} return r end,  -- how many slots of each bag were read, since last asked
    frames = function(count) for _ = 1, count or 1 do clock = clock + 0.03; fire('d3d_present') end end,
    wait = function(seconds) clock = clock + seconds end, -- time going by without a frame, as for a check that draws its own
    command = function(text) return fire('command', { command = text, blocked = false }).blocked end,
    packet = function(id) fire('packet_in', { id = id, data = '' }) end,
    packetData = function(id, data) fire('packet_in', { id = id, data = data, data_raw = data }) end, -- a packet with its bytes
    packetOut = function(id) fire('packet_out', { id = id, data = '' }) end,
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
    dinput = function(button, state) return fire('dinput_button', { button = button, state = state, blocked = false }).blocked end, -- a DirectInput button or axis
    plugin = function(name, data) fire('plugin_event', { name = name, data = data }) end,
    loaded = function(name, on) plugins[name] = on end,      -- whether Ashita says a plugin is loaded
    Button = { DpadUp = 0, DpadDown = 1, DpadLeft = 2, DpadRight = 3, LB = 8, RB = 9, A = 12, B = 13, X = 14, Y = 15, L2 = 16, R2 = 17 },
}

-- The checks were written against winxi's plain look, from before the shipped theme took on borders,
-- backgrounds and titles of its own: they get that look, so that what they measure does not move
-- whenever the shipped defaults do.
do
    local theme = require('winxi.theme')
    local plain = {
        BackgroundColor = { 0.08, 0.08, 0.08, 0.8 }, BorderColor = { 0.69, 0.68, 0.78, 1.0 },
        ThemeTabColor = { 0.20, 0.54, 0.58, 1.0 }, HighlightColor = { 0.69, 0.68, 0.78, 0.4 },
        Padding = 10, ShadowEnabled = false, ShadowOffset = 4, ShadowBlur = 6, ShadowOpacity = 50, BorderOpacity = 100,
        BorderStyle = 'theme', BackgroundStyle = 'plain', TabStyle = 'sheen', BarTexture = 'original', BookendOpacity = 100,
        TitleStyle = 'outline', TitleColor = { 0.94, 0.90, 0.76, 1.0 }, TitleSize = 0, TitleFontFile = '', TitleOffsetX = 10,
        TitleShadow = false, TitleShadowOpacity = 70,
        SettingsBackgroundColor = { 0.08, 0.08, 0.08, 0.8 }, SettingsBorderColor = { 0.69, 0.68, 0.78, 1.0 },
        SettingsHighlightColor = { 0.69, 0.68, 0.78, 0.4 }, SettingsHeaderColor = { 1.00, 0.75, 0.55, 1.0 },
        TooltipPadding = 6, TooltipBackgroundColor = { 0.05, 0.05, 0.05, 0.95 },
    }
    for key, value in pairs(plain) do theme.Defaults[key] = value end
    theme.Reset()
end

dofile(target)
dofile(check)
