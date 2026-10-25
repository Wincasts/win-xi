-- nativeui's Drawn As Winxi: the menus over the chat log asked of uihook's mirror each frame and drawn in winxi, one
-- that cannot be measured whole left to the game for a while and taken again, and the game given them back.
local failures = 0
local function check(label, ok) H.print(label, ok and 'true' or 'FALSE'); if not ok then failures = failures + 1 end end
local function Last() return GROUP.requests[#GROUP.requests] end
local function Kept(name) for _, n in ipairs(Last() or {}) do if n == name then return true end end return false end
-- the command menu: its words letters of the game's menu font (elements), its hand, the second row lit
local function uv(x0, y0, x1, y1) return { x0 / 256, y0 / 256, x1 / 256, y1 / 256 } end
local boxes = { A = { 77, 26, 86, 37 }, t = { 0, 92, 6, 102 }, a = { 49, 67, 57, 76 }, c = { 68, 67, 77, 76 }, k = { 25, 78, 34, 89 },
    M = { 80, 39, 89, 50 }, g = { 107, 67, 116, 79 }, i = { 10, 78, 15, 89 } }
local function Spell(quads, word, x, y, color)
    for ch in word:gmatch('.') do
        quads[#quads + 1] = { phase = 3, uv = uv(unpack(boxes[ch])), color = color, rect = { x, y, x + 9, y + 12 }, texture = 0x55 }
        x = x + 8
    end
end
local function Command()
    local quads = {}
    Spell(quads, 'Attack', 40, 810, { 1, 1, 1, 1 })
    Spell(quads, 'Magic', 40, 826, { 1, 0.6, 0.25, 1 })
    -- the button bars: blue-grey (616180), the one the cursor is on orange (613C20)
    quads[#quads + 1] = { phase = 3, uv = { 0.25, 0, 1, 0.25 }, color = { 0.76, 0.76, 1, 1 }, rect = { 30, 806, 120, 822 }, texture = 0x66 }
    quads[#quads + 1] = { phase = 3, uv = { 0.25, 0, 1, 0.25 }, color = { 0.76, 0.47, 0.25, 1 }, rect = { 30, 822, 120, 838 }, texture = 0x66 }
    quads[#quads + 1] = { phase = 3, uv = { 0.9, 0, 1, 0.05 }, color = { 1, 1, 1, 1 }, rect = { 110, 826, 118, 834 }, texture = 0x66 } -- a submenu's arrow
    return { name = 'playermo', hidden = true, kept = false, focused = true, hasCursor = true, drewContent = true,
        rect = { 16, 800, 128, 888 }, cursor = { 20, 826, 36, 838 }, selection = { 30, 822, 120, 838 },
        runs = {}, quads = quads, target = { 16, 800, 112, 88 }, scrollPage = 0, scrollCount = 0, scrollTop = 0 }
end
local function Question(placed)
    return { name = 'comyn', hidden = true, kept = false, focused = true, hasCursor = false, drewContent = true,
        rect = { 130, 800, 382, 888 },
        runs = { { text = 'Yes', raw = 'Yes', route = 2, color = { 1, 1, 1, 1 }, rect = placed ~= false and { 150, 820, 180, 832 } or nil, x = 0, y = 0, phase = 1 } },
        quads = {}, target = { 130, 800, 252, 88 }, scrollPage = 0, scrollCount = 0, scrollTop = 0 }
end

H.load()
H.loaded('uihook', true)
H.wait(0.6); H.frames(1)
check('The Game to begin with: the group not asked for', #GROUP.requests == 0)
local options = H.options()
options.look = 'Winxi'
H.wait(0.6); H.frames(1)
check('Winxi: the group asked for, none kept', Last() ~= nil and #Last() == 0)
local before = #GROUP.requests
H.frames(2)
check('asked again every frame', #GROUP.requests == before + 2)

local texts = H.calls['draw.AddText'] or 0
GROUP.windows = { Command(), Question() }
H.frames(1)
check('the windows drawn: their words', (H.calls['draw.AddText'] or 0) > texts)
local function Box(l, t, r, b)
    for _, box in ipairs(GROUP.boxes) do
        if box.min[1] == l and box.min[2] == t and box.max[1] == r and box.max[2] == b then return box end
    end
end
check('the button bars drawn as square boxes, not the game\'s art', Box(30, 806, 120, 822) and Box(30, 806, 120, 822).rounding == 0 and Box(30, 822, 120, 838))
local arrows, letters, hand = 0, 0, nil
for _, image in ipairs(GROUP.images) do
    if image.texture == 0x66 then arrows = arrows + 1 elseif image.texture == 0x55 then letters = letters + 1 elseif image.texture == 0x77 then hand = image end
end
check('the arrow the game\'s art, the letters read as words, not drawn', arrows == 1 and letters == 0)
check('the hand\'s fingertip on the lit button\'s left edge, hanging out past the box', hand and hand.max[1] == 29 and hand.min[1] < 26 and hand.min[2] == 822 and hand.max[2] == 838)
check('the box only as large as its buttons and words, and 4 round them', Box(26, 802, 124, 842) ~= nil)
check('nothing printed', #H.printed == 0)

-- a window whose text could not be placed: left to the game, and taken again once it is measured whole a while
GROUP.windows = { Command(), Question(false) }
H.frames(1)
H.frames(1)
check('text unplaced: the window kept for the game', Kept('comyn') and not Kept('playermo'))
local kept = Question(); kept.hidden, kept.kept = false, true
GROUP.windows = { Command(), kept }
H.frames(1)
check('measured whole: still the game\'s a moment', Kept('comyn'))
H.wait(0.3); H.frames(1); H.frames(1)
check('measured whole a while: drawn in winxi again', not Kept('comyn'))
GROUP.windows = { Command(), (function() local w = Question(); w.rect = nil; return w end)() }
H.frames(1); H.frames(1)
check('no place measured: kept for the game', Kept('comyn'))
H.wait(3); GROUP.windows = { Command(), Question() }; H.frames(1); H.frames(1)
check('two seconds on: asked of the mirror again', not Kept('comyn'))

-- the settings say what it does
H.command('/nativeui')
H.frames(2)
check('the settings drawn with it', (H.calls['BeginCombo'] or 0) > 0)

-- back to the game's own
local stops = GROUP.stops
options.look = 'The Game'
H.frames(1)
check('The Game: the mirror stopped', GROUP.stops > stops)
options.look = 'Winxi'
H.frames(1)
stops = GROUP.stops
H.unload()
check('unloaded: the mirror stopped', GROUP.stops > stops)
H.print(failures == 0 and 'nativeui group: 0 failures' or ('nativeui group: %d failures'):format(failures))
if failures > 0 then os.exit(1) end
