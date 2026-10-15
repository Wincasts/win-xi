-- Run with: luajit tests/harness.lua inventory addons/inventory/inventory.lua tests/inventory_currency_check.lua
-- Gil, or one of the game's currencies, in the gil's place at the foot of the window, and a second
-- after it with a comma: currencies asked of the server as the game's Currencies menus ask, while the
-- window is shown, and read from its answers. The choices are the server's era's, and any other the
-- player has some of.
local imgui = require('imgui')
local currency = require('currency')
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
local lines = 0 -- the upright lines drawn in the last frame
local function frame(n)
    texts = {}
    H.frames((n or 1) - 1)
    local before = H.calls['draw.AddLine'] or 0
    H.frames(1)
    lines = (H.calls['draw.AddLine'] or 0) - before
end
-- the texts drawn, in order, from the first given on
local function order(...)
    local want, at = { ... }, 1
    for _, t in ipairs(texts) do
        if t == want[at] then at = at + 1 end
        if at > #want then return true end
    end
    return false
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
local function choosable(key)
    for _, entry in ipairs(currency.Choices()) do if entry.key == key then return true end end
    return false
end

H.play(true); H.gil(12345)
o.isVisible[1], o.controller[1], o.fadeInOut[1] = true, false, false
H.bag(0, 30, { { 1 } })
H.packet(0x00A); frame(200) -- the area settles
check('gil by default, in its place, and nothing asked for', o.currency1 == 'gil' and o.currency2 == ''
    and shown('12,345 G') and asked('10F') == 0 and asked('115') == 0)
check('one currency: no lines', lines == 0)

o.currency2 = 'imperialStanding'
frame()
check('a second: its menu asked for, once', asked('10F') == 1 and asked('115') == 0)
check('until it is answered, a dash, after the gil', order('12,345 G', '- IS', '01/30'))
check('a line between the two, and another before the count', lines == 2)
answer(0x113, 260, { [120] = 45000, [144] = 12 })
frame()
check('the answer read: grouped by thousands', order('12,345 G', '45,000 IS'))

o.currency1, o.currency2 = 'nyzulTokens', 'gil'
frame()
check('either way round', order('12 Tokens', '12,345 G'))
o.currency1, o.currency2 = '', 'imperialStanding'
frame()
check('the second alone, in the first\'s place, without lines', shown('45,000 IS') and lines == 0)
o.currency1, o.currency2 = '', ''
frame()
check('none: nothing in the gil\'s place', shown('') and not shown('12,345 G'))

o.currency1, o.currency2 = 'gil', 'imperialStanding'
frame(1000)
check('not asked again within the minute', asked('10F') == 1)
frame(1000)
check('asked again each minute the window stays shown', asked('10F') == 2 and asked('115') == 0)
o.isVisible[1] = false
frame(2100)
check('the window hidden: not asked', asked('10F') == 2)
o.isVisible[1] = true
frame()
check('shown again: asked as it is shown', asked('10F') == 3)
H.packet(0x00A)
frame(100)
check('a new area: not asked while it settles', asked('10F') == 3)
frame(100)
check('then asked again', asked('10F') == 4)

-- the choices: gil and the era's (Phoenix's, Treasures of Aht Urhgan); the rest when the player has some
check('gil and the era\'s currencies can be chosen', choosable('gil') and choosable('conquestBastok')
    and choosable('imperialStanding') and choosable('idTags'))
check('later ones cannot, while the player has none', not choosable('sparks') and not choosable('bayld')
    and not choosable('cruor'))
answer(0x118, 160, { [0] = 1234567 })
answer(0x113, 260, { [112] = 300 })
check('one the server says the player has some of can', choosable('bayld') and choosable('sparks')
    and not choosable('cruor'))
check('Retail: every currency the game knows', #currency.Choices('retail') == #currency.list
    and currency.Choices('retail')[1].key == 'gil')
check('Phoenix by default', o.currencyList == 'phoenix')
o.currency1, o.currency2 = 'bayld', 'sparks'
frame()
check('and is shown with its short name', order('1,234,567 Bayld', '300 Sparks'))

-- the settings: opening the list asks both menus, so the player's own come into it
local sent115 = asked('115')
H.command('/inv config')
H.tab(2)
local beginCombo = imgui.BeginCombo
local listed = {}
imgui.BeginCombo = function(id, ...) return id == '##inv.currency1' end
local selectable = imgui.Selectable
imgui.Selectable = function(label, ...) listed[#listed + 1] = label:match('^[^#]+'); return selectable(label, ...) end
frame(2100) -- long enough for both to be asked again
check('opening the choices asks about both menus', asked('115') > sent115)
check('the choices listed: None, then gil first', listed[1] == 'None' and listed[2] == 'Gil')
listed = {}
frame()
local phoenixListed = #listed
listed = {}
o.currencyList = 'retail'
frame()
check('the Retail list offers more', #listed > phoenixListed and #listed == #currency.list + 1)
o.currencyList = 'phoenix'
imgui.BeginCombo, imgui.Selectable = beginCombo, selectable
H.command('/inv config')
H.unload()
