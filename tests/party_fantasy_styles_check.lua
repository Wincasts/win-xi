H.load()
local theme, frames, draw = require('winxi.theme'), require('frames'), require('draw')
local style = require('options').Style(H.options())
local member = { name = 'Test', serverId = 123, hp = 500, hpp = 50, mp = 200,
    mpp = 50, tp = 0, isInZone = true, isPlayer = true, statusIds = {} }
local loaded = {}
draw.Texture = function(path) loaded[path] = true; return 1 end
draw.Image = function() end
local function listed(choices, key)
    for _, choice in ipairs(choices) do if choice.key == key then return true end end
end
for _, key in ipairs({ 'kingdom', 'magitek', 'aether', 'elven', 'gothic' }) do
    assert(listed(theme.BarTextures, key) and listed(theme.BookendStyles, key), 'both dropdowns offer ' .. key)
    style.barTexture, style.bookendStyle, style.bookends = key, key, true
    frames.Draw({ member }, 'party', nil, style)
    for _, kind in ipairs({ 'hp', 'mp' }) do
        for _, layer in ipairs({ 'back', 'fill', 'front' }) do
            local path = 'bars/' .. key .. '/' .. kind .. '_' .. layer .. '.png'
            assert(loaded[path], 'renderer loads ' .. path)
            local file = assert(io.open('addons/party/assets/' .. path, 'rb'))
            assert(file:read(8) == '\137PNG\r\n\26\n'); file:close()
        end
    end
    local path = 'bookends/' .. key .. '.png'
    assert(loaded[path], 'renderer loads independent ornament ' .. key)
    local file = assert(io.open('addons/party/assets/' .. path, 'rb'))
    assert(file:read(8) == '\137PNG\r\n\26\n'); file:close()
end
H.print('fantasy styles: dropdown registration, HP/MP layers, independent bookends and bundled PNGs', true)
