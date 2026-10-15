-- Run with: luajit tests/harness.lua inventory addons/inventory/inventory.lua tests/inventory_currency_check.lua
-- Two of the game's currencies, chosen in the settings, on a row under the gil: asked of the server as
-- the game's Currencies menus ask, while the window is shown, and read from its answers.
local imgui = require('imgui')
local function check(label, ok)
    H.print(label, ok)
    assert(ok, label)
end
local o = H.options()
-- the answers' numbers, little-endian, where the packets have them
local structUnpack = struct.unpack
struct.unpack = function(format, data, at)
    if (format == 'i' or format == 'H') and type(data) == 'string' then
        local value = 0
        for i = (format == 'i' and 3 or 1), 0, -1 do value = value * 256 + data:byte(at + i) end
        return value
    end
    return structUnpack(format, data, at)
end
local function answer(id, size, fields)
    local bytes = {}
    for i = 1, size do bytes[i] = 0 end
    for at, value in pairs(fields) do
        for i = 0, 3 do bytes[4 + at + i + 1] = math.floor(value / 256 ^ i) % 256 end
    end
    H.packetData(id, string.char(unpack(bytes)))
end
local texts = {}
local text = imgui.Text
imgui.Text = function(t, ...) texts[#texts + 1] = t; return text(t, ...) end
local function frame(n)
    texts = {}
    H.frames(n or 1)
end
local function shown(t)
    for _, v in ipairs(texts) do if v == t then return true end end
    return false
end
local function asked(id)
    local n = 0
    for _, s in ipairs(H.sent) do if s:find('^' .. id .. ':') then n = n + 1 end end
    return n
end

H.play(true); H.gil(100)
o.isVisible[1], o.controller[1], o.fadeInOut[1] = true, false, false
H.bag(0, 30, { { 1 } })
H.packet(0x00A); frame(200) -- the area settles
check('no currency chosen: none asked for, no row', asked('10F') == 0 and asked('115') == 0
    and not shown('- Sparks of Eminence'))

o.currency1 = 'sparks'
frame()
check('one chosen: its menu asked for, once', asked('10F') == 1 and asked('115') == 0)
check('until it is answered, its name with a dash', shown('- Sparks of Eminence'))
answer(0x113, 260, { [112] = 45000, [244] = 12 })
frame()
check('the answer read: grouped by thousands', shown('45,000 Sparks of Eminence'))

o.currency2 = 'bayld'
frame()
check('a second, from the other menu: that menu asked for', asked('10F') == 1 and asked('115') == 1)
answer(0x118, 160, { [0] = 1234567 })
frame()
check('both shown, the first then the second', shown('45,000 Sparks of Eminence') and shown('1,234,567 Bayld'))

frame(1000)
check('not asked again within the minute', asked('10F') == 1 and asked('115') == 1)
frame(1000)
check('asked again each minute the window stays shown', asked('10F') == 2 and asked('115') == 2)

o.isVisible[1] = false
frame(2100)
check('the window hidden: not asked', asked('10F') == 2 and asked('115') == 2)
o.isVisible[1] = true
frame()
check('shown again: asked as it is shown', asked('10F') == 3 and asked('115') == 3)

H.packet(0x00A)
frame(100)
check('a new area: not asked while it settles', asked('10F') == 3)
frame(100)
check('then asked again', asked('10F') == 4 and asked('115') == 4)

-- side by side while they fit; where they do not, the second on a row of its own
local sameLine, calc = imgui.SameLine, imgui.CalcTextSize
local sequence = {}
imgui.SameLine = function(...)
    local last = sequence[#sequence]
    if last ~= nil and last ~= 'same' then sequence[#sequence + 1] = 'same' end -- only after a currency
    return sameLine(...)
end
local wide = false
imgui.CalcTextSize = function(t, ...)
    if wide and (t:find('Sparks', 1, true) or t:find('Bayld', 1, true)) then return 400, 14 end
    return calc(t, ...)
end
local function between()
    sequence = {}
    local text2 = imgui.Text
    imgui.Text = function(t, ...)
        if t:find('Sparks', 1, true) or t:find('Bayld', 1, true) then sequence[#sequence + 1] = t end
        return text2(t, ...)
    end
    frame()
    imgui.Text = text2
    return table.concat(sequence, ',')
end
check('short enough: one row', between() == '45,000 Sparks of Eminence,same,1,234,567 Bayld')
wide = true
check('too long for one row: two', between() == '45,000 Sparks of Eminence,1,234,567 Bayld')
wide = false
imgui.SameLine, imgui.CalcTextSize = sameLine, calc

o.currency1, o.currency2 = 'deeds', ''
answer(0x113, 260, { [112] = 45000, [244] = 12 })
frame()
check('two-byte counts read too; none for the second, no second', shown('12 Deeds') and not shown('1,234,567 Bayld'))
o.currency1, o.currency2 = '', 'bayld'
frame()
check('only the second chosen: it is shown alone', shown('1,234,567 Bayld') and not shown('12 Deeds'))
o.currency1, o.currency2 = 'gone', ''
frame()
check('a key no longer known is none', not shown('- gone'))
H.unload()
