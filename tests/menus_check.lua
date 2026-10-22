-- menus: what it asks uihook to mirror, its fallbacks, and the mouse kept from the game's menus and dragging them.
local failures = 0
local function check(label, ok) H.print(label, ok and 'true' or 'FALSE'); if not ok then failures = failures + 1 end end
local function Inventory(placed)
    return { name = 'inventor', hidden = true, focused = true, hasCursor = true, drewContent = true,
        rect = { 100, 100, 300, 300 }, cursor = { 90, 140, 110, 152 },
        runs = { { text = 'Instant Warp', raw = 'Instant Warp', route = 2, color = { 1, 1, 1, 1 }, rect = placed ~= false and { 120, 140, 200, 152 } or nil, x = 221, y = 54 } },
        quads = {}, target = { 200, 48, 182, 190 }, scrollPage = 0, scrollCount = 0, scrollTop = 0 }
end
local MOVE, DOWN, UP, WHEEL = 0x0200, 0x0201, 0x0202, 0x020a
local function Mouse(message, x, y)
    MENUS.mouse.x, MENUS.mouse.y = x, y
    local e = { message = message, blocked = false, wparam = 0 }
    MENUS.handlers.mouse(e)
    return e.blocked
end
local function Last() return MENUS.requests[#MENUS.requests] end
local function Asked(name)
    for _, entry in ipairs(Last() or {}) do if entry.name == name then return entry end end
end

H.load()
MENUS.windows = { Inventory() }
H.frames(1)
check('asks for the items and lists, hidden', Asked('inventor') and Asked('inventor').hide and Asked('ability') and Asked('ability').hide)
check('the status and config windows off to start', not Asked('persona') and not Asked('cfilter'))
check('drawn: a frame and its text', (H.calls['draw.AddText'] or 0) > 0)
check('nothing printed', #H.printed == 0)

-- the mouse, while it is not kept from the game's menus: the game's
check('a press over the menu, with Keep Mouse off: the game\'s', not Mouse(DOWN, 150, 150))
check('and its release', not Mouse(UP, 150, 150))

local options = H.options()
options.blockMouse[1] = true
H.frames(1)
check('the mouse moving over the menu: kept from the game', Mouse(MOVE, 150, 150))
check('the wheel over it: kept', Mouse(WHEEL, 150, 150))
check('the mouse away from it: the game\'s', not Mouse(MOVE, 600, 600))
check('a press away from it: the game\'s', not Mouse(DOWN, 600, 600))
check('and its release', not Mouse(UP, 600, 600))

-- a drag: the press kept, the menu moved as the mouse moves, its place saved as it is let go
local saves = H.saves()
check('a press on the menu: kept', Mouse(DOWN, 150, 150))
check('a move while held: kept', Mouse(MOVE, 200, 180))
check('the menu\'s offset follows', options.offsets.inventor and options.offsets.inventor[1] == 50 and options.offsets.inventor[2] == 30)
check('the release: kept', Mouse(UP, 200, 180))
check('saved as it is let go', H.saves() > saves)
H.frames(1)
check('drawn where it was moved: a press there is kept', Mouse(DOWN, 340, 320))
Mouse(UP, 340, 320)
check('the game\'s own place under it still kept from the game', Mouse(DOWN, 110, 110))
Mouse(UP, 110, 110)

-- a release whose press was kept is kept, even once nothing is mirrored
check('a press on the menu', Mouse(DOWN, 150, 150))
MENUS.windows = {}
H.frames(1)
check('its release kept though the menu has gone', Mouse(UP, 150, 150))
MENUS.windows = { Inventory() }
H.frames(1)

-- the settings window under the mouse has its presses (drawn at 100, 200, 300 by 150 in the harness), whatever
-- imgui says, as its word goes stale while moves are kept
H.command('/menus')
H.frames(1)
check('a press on the settings window over the menu: not kept', not Mouse(DOWN, 200, 250))
Mouse(UP, 200, 250)
H.command('/menus')
H.frames(1)
H.wait(1)
MENUS.captured = true
check('closed, imgui saying it has the mouse: a press on the menu kept still', Mouse(DOWN, 200, 250))
Mouse(UP, 200, 250)
MENUS.captured = false

-- locked: the press kept, nothing moved
options.lockMenus[1] = true
Mouse(DOWN, 200, 180); Mouse(MOVE, 260, 260); Mouse(UP, 260, 260)
check('locked: not moved', options.offsets.inventor[1] == 50 and options.offsets.inventor[2] == 30)
options.lockMenus[1] = false

-- dragged off the screen: drawn on it
Mouse(DOWN, 200, 180); Mouse(MOVE, -2000, -2000); Mouse(UP, -2000, -2000)
H.frames(1)
check('dragged past the screen\'s corner: drawn at it, a press there kept', Mouse(DOWN, 5, 5))
Mouse(UP, 5, 5)
check('its offset kept to the corner', options.offsets.inventor[1] == -100 and options.offsets.inventor[2] == -100)

-- Keep Mouse off: the menu drawn where the game puts it, the mouse the game's
options.blockMouse[1] = false
H.frames(1)
check('Keep Mouse off: nothing kept', not Mouse(MOVE, 150, 150) and not Mouse(DOWN, 5, 5))
Mouse(UP, 5, 5)

-- Reset Positions forgets them
options.offsets = T{}
check('reset', next(options.offsets) == nil)

-- text that could not be placed: given back to the game for a while, and said
MENUS.windows = { Inventory(false) }
H.frames(1)
H.frames(1)
check('text with no place: the window given back to the game', Asked('inventor') and not Asked('inventor').hide)
MENUS.windows = { Inventory() }
H.wait(3)
H.frames(1)
check('two seconds on: hidden again', Asked('inventor').hide)

-- Outline: nothing hidden
options.mode = 'Outline'
H.frames(1)
check('Outline: nothing hidden', not Asked('inventor').hide)

-- a menu whose words are pictures: its elements drawn as the game's art; an item list's elements are not
options.mode = 'Replace'
options.mirror_menuwind[1] = true
H.frames(1)
check('the main menu asked for once on', Asked('menuwind') and Asked('menuwind').hide)
local function Element(top, lit)
    return { rect = { 120, top, 200, top + 16 }, uv = { 0, 0, 0.5, 0.1 }, texture = 77, color = lit and { 1, 0.625, 0.25, 1 } or { 1, 1, 1, 1 }, phase = 3 }
end
local mainMenu = { name = 'menuwind', hidden = true, rect = { 100, 100, 300, 300 }, cursor = { 90, 120, 110, 132 },
    selection = { 120, 118, 200, 134 }, runs = {}, quads = { Element(100), Element(118, true), Element(136) },
    scrollPage = 0, scrollCount = 0, scrollTop = 0 }
local items = Inventory()
items.quads = { Element(160) }
MENUS.windows = { mainMenu }
local images = H.calls['draw.AddImage'] or 0
H.frames(1)
check('the main menu\'s three labels drawn', (H.calls['draw.AddImage'] or 0) - images >= 3)
MENUS.windows = { items }
images = H.calls['draw.AddImage'] or 0
H.frames(1)
check('an item list\'s element not drawn', (H.calls['draw.AddImage'] or 0) - images == 0)
-- its labels spelled from the game's font: drawn as words, their letters not drawn as art
local spelled = Element(100); spelled.word = 'Status'
mainMenu.quads = { spelled, Element(136) }
MENUS.windows = { mainMenu }
images = H.calls['draw.AddImage'] or 0
local texts = H.calls['draw.AddText'] or 0
H.frames(1)
check('a spelled label drawn as words', (H.calls['draw.AddText'] or 0) > texts)
check('its letters not drawn as art, the other element still', (H.calls['draw.AddImage'] or 0) - images == 1)
-- a title in the game's serif letters: on the frame's edge, in an item list too, its letters not drawn
local titled = Element(80); titled.word, titled.font = 'Commands', 'title'
mainMenu.quads = { titled, spelled }
items = Inventory(); items.quads = { (function() local q = Element(80); q.word, q.font = 'Items', 'title'; return q end)() }
MENUS.windows = { mainMenu, items }
images, texts = H.calls['draw.AddImage'] or 0, H.calls['draw.AddText'] or 0
H.frames(1)
check('titles drawn as words, no art', (H.calls['draw.AddText'] or 0) - texts >= 3 and (H.calls['draw.AddImage'] or 0) - images == 0)
-- an item list's words spelled in its contents (as the top bar's help line): drawn, though its elements are not
items = Inventory(); items.quads = { { rect = { 120, 160, 200, 176 }, uv = { 0, 0, 1 / 64, 1 / 128 }, texture = 77, color = { 1, 1, 1, 1 }, phase = 1, word = 'Select an item.', font = 'text' },
    Element(180) }
MENUS.windows = { items }
images, texts = H.calls['draw.AddImage'] or 0, H.calls['draw.AddText'] or 0
H.frames(1)
check('an item list\'s contents\' words drawn, no art', (H.calls['draw.AddText'] or 0) > texts and (H.calls['draw.AddImage'] or 0) - images == 0)
check('nothing printed for them', #H.printed == 0)

-- unloaded: the mirror stopped
local stops = MENUS.stops
H.unload()
check('unloaded: stopped', MENUS.stops > stops)
check('nothing printed throughout', #H.printed == 0)
H.print(('%d failures'):format(failures))
if failures > 0 then os.exit(1) end
