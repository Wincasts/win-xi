-- party: the smooth bar textures, the light at a fill's end, the backdrop and the rounded caps.
-- Each smooth set is offered, loaded and bundled (in party's assets and winxi's). Fill End Glow draws
-- the light over the end of each fill, as solid as the glow is strong and the line's range allows, and
-- nothing at 0. Custom Bar Backdrop draws its colour over each bar's inside, between back and fill.
-- Rounded caps go beyond the bar's ends, the right one turned about, both of one width.
H.load()
local theme, frames, draw = require('winxi.theme'), require('frames'), require('draw')
local style = require('options').Style(H.options())
local member = { name = 'Test', serverId = 123, hp = 500, hpp = 50, mp = 200,
    mpp = 50, tp = 0, isInZone = true, isPlayer = true, statusIds = {} }

local handles, paths = {}, {}
draw.Texture = function(path)
    if not handles[path] then paths[#paths + 1] = path; handles[path] = #paths end
    return handles[path]
end
local drawn = {}
draw.Image = function(handle, x1, y1, x2, y2, packed, u1, v1, u2, v2)
    drawn[#drawn + 1] = { path = paths[handle], x1 = x1, y1 = y1, x2 = x2, y2 = y2, u1 = u1, u2 = u2, alpha = draw.lastAlpha }
end
local packed = draw.Packed
draw.Packed = function(color, alpha) draw.lastAlpha = alpha; return packed(color, alpha) end
local rects = {}
draw.Rect = function(x1, y1, x2, y2, colour) rects[#rects + 1] = { x1, y1, x2, y2 } end
local function paint()
    drawn, rects = {}, {}
    frames.Draw({ member }, 'party', nil, style)
end
local function find(pattern)
    local found = {}
    for _, image in ipairs(drawn) do if image.path and image.path:match(pattern) then found[#found + 1] = image end end
    return found
end
local function listed(choices, key)
    for _, choice in ipairs(choices) do if choice.key == key then return true end end
end
local function png(path)
    local file = io.open(path, 'rb')
    local ok = file and file:read(8) == '\137PNG\r\n\26\n'
    if file then file:close() end
    return ok
end

style.bookends, style.barGlow, style.barBackdrop = false, 0, nil
for _, key in ipairs({ 'enamel', 'enamel_rim', 'enamel_gradient', 'tube', 'tube_deep', 'glass_enamel' }) do
    assert(listed(theme.BarTextures, key), 'Bar Texture offers ' .. key)
    style.barTexture = key
    paint()
    for _, kind in ipairs({ 'hp', 'mp' }) do
        for _, layer in ipairs({ 'back', 'fill', 'front' }) do
            local path = 'bars/' .. key .. '/' .. kind .. '_' .. layer .. '.png'
            assert(handles[path], 'drawn with ' .. path)
            assert(png('addons/party/assets/' .. path), 'bundled ' .. path)
        end
    end
    for _, layer in ipairs({ 'back', 'fill', 'front' }) do
        assert(png(('addons/libs/winxi/assets/bars/%s/%s.png'):format(key, layer)), 'winxi has ' .. key .. ' ' .. layer)
    end
end
assert(#find('glow') == 0 and #rects == 0, 'no glow or backdrop unless asked')
H.print('smooth sets: offered, drawn and bundled in party and winxi', true)

-- the glow: one over each fill, its right edge at the fill's, as solid as asked
style.barGlow = 60
paint()
local glows, fills = find('glow%.png$'), find('_fill%.png$')
assert(#glows == 2 and #fills == 2, 'one glow a fill')
assert(png('addons/party/assets/bars/glow.png') and png('addons/libs/winxi/assets/bars/glow.png'), 'glow image bundled')
for index = 1, 2 do
    local light, fill = glows[index], fills[index]
    assert(math.abs(light.x2 - fill.x2) < 1e-6 and light.x1 < light.x2 and light.x1 >= fill.x1, 'over the fill\'s end')
    assert(math.abs(light.alpha - 0.6) < 1e-9 and light.u2 == 1, 'as strong as asked')
end
-- a nearly empty bar: the light no longer than the fill, its right end shown
member.hpp, member.hp = 1, 10
frames.Draw({ member }, 'party', nil, style) -- the bar's animation settles over frames
for _ = 1, 200 do frames.Draw({ member }, 'party', nil, style) end
paint()
local light, fill = find('glow%.png$')[1], find('hp_fill%.png$')[1]
assert(math.abs(light.x1 - fill.x1) < 1e-6 and light.u1 > 0, 'a short fill: the light\'s right end only')
member.hpp, member.hp = 50, 500
style.barGlow = 0
paint()
assert(#find('glow') == 0, 'none at 0')
H.print('fill end glow: over each fill\'s end, its strength, short fills, none at 0', true)

-- the backdrop: a rectangle a bar, on its inside, drawn before the fill
style.barBackdrop = { 0.1, 0.2, 0.3, 0.8 }
paint()
assert(#rects == 2, 'a backdrop a bar')
fills = find('_fill%.png$')
assert(rects[1][1] <= fills[1].x1 and rects[1][3] > fills[1].x2, 'under the whole of the bar')
style.barBackdrop = nil
H.print('custom bar backdrop: one a bar, the length of its inside', true)

-- rounded caps: beyond each end, the right turned about, one width
style.bookends, style.bookendOpacity = true, 100
for _, key in ipairs({ 'rounded', 'rounded_silver' }) do
    assert(listed(theme.BookendStyles, key), 'Bookend Style offers ' .. key)
    assert(png('addons/party/assets/bookends/' .. key .. '.png'), 'bundled ' .. key)
    style.bookendStyle = key
    paint()
    local caps = find('^bookends/' .. key)
    assert(#caps == 4, 'two caps a bar')
    local backs = find('_back%.png$')
    for bar = 1, 2 do
        local left, right = caps[bar * 2 - 1], caps[bar * 2]
        assert(left.u1 == 0 and left.u2 == 1 and right.u1 == 1 and right.u2 == 0, 'the right one turned about')
        assert(left.x2 - left.x1 == right.x2 - right.x1 and left.x2 - left.x1 >= 2, 'one width')
        assert(left.x2 < right.x1 and left.x1 > backs[1].x1 - 20, 'beyond the ends')
    end
end
style.bookendStyle = 'silver'
paint()
local caps = find('^bookends/silver')
assert(#caps == 4 and caps[2].u1 == 0, 'the others as they were')
H.print('rounded caps: beyond the bar\'s ends, the right turned about', true)
