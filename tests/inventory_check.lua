-- inventory: loads, brings its settings over from xitools, draws, answers its command, takes the controller
local o = H.options()
H.print('imported', o.importedFromXitools, '| pos', o.pos[1], o.pos[2], '| maxHeight', o.maxHeight[1], '| info', o.controllerInfo,
    '| manualOrder', type(o.manualOrder), '| fadeInOut', o.fadeInOut[1], '| hide chat', o.hide.UnderChat, 'map', o.hide.UnderMap)
H.print('said:', H.printed[#H.printed])

H.frames(3); H.print('loading: windows begun', H.calls.Begin or 0)
H.play(true); o.isVisible[1] = true; H.frames(8)
H.print('in game: windows begun', H.calls.Begin, '| tab bars', H.calls.BeginTabBar)

-- where a character is chosen there can be a player, but nobody is in the game: nothing is drawn
do
    local begun = H.calls.Begin
    H.login(0); H.frames(8)
    H.print('choosing a character: nothing drawn', H.calls.Begin == begun)
    H.login(2); H.frames(8)
    H.print('logged in again: drawn', H.calls.Begin > begun)
end

local before = H.calls.Begin
H.print('/inv config kept from the game', H.command('/inv config')); H.frames(1)
H.print('settings window drawn', H.calls.Begin - before == 2, '| checkboxes', H.calls.Checkbox > 0, '| radio buttons', H.calls.RadioButton > 0)
H.command('/inv config')

H.print('A is the window\'s', H.tap(H.Button.A), '| B gives the controller back', H.tap(H.Button.B), '| window still open', o.isVisible[1])
H.print('then A is the game\'s', H.tap(H.Button.A) == false)
H.command('/inv focus'); H.frames(1); H.print('/inv focus: A is the window\'s again', H.tap(H.Button.A))
H.print('X opens the sort menu, on', (H.tap(H.Button.X) and H.selected()))
H.tap(H.Button.B)

-- the bags: read once the game has them, then only the bag a packet names, once the packets have
-- been quiet for a moment; hovering and right-clicking found from where the mouse is
do
    H.tap(H.Button.B)
    H.ret.GetWindowPos, H.ret.GetWindowSize = { 0, 0 }, { 300, 1000 } -- everything in view
    local function Packet(at, bag) return string.rep('\0', at) .. string.char(bag) .. string.rep('\0', 8) end
    local function Calls() local n = 0 for k, v in pairs(H.calls) do if not k:find('^draw%.') then n = n + v end end return n end

    H.gil(5000); H.bag(0, 30, { { 1, 5 }, { 20001 }, { 2, 3 } }); H.bag(5, 30, { { 3 } }); H.reads()
    H.frames(1); local r = H.reads()
    H.print('bags: read as the game has them', (r[0] or 0) > 0 and (r[5] or 0) > 0)

    H.packetData(0x020, Packet(0x0E, 5)); H.frames(1); r = H.reads()
    H.print('a change to the satchel: not read at once', r[5] == nil)
    H.frames(5); r = H.reads()
    H.print('read once settled', (r[5] or 0) > 0, '| the satchel alone (the gil looked at, not the inventory)', (r[0] or 0) <= 2 and r[8] == nil)

    -- Choose one column: the third item is two rows down.
    o.gridColumns[1] = 1
    H.ret.IsWindowHovered, H.ret.GetMousePos = { true }, { 15, 20 + 2 * 36 + 5 }
    local tips = H.calls.BeginTooltip or 0; H.frames(1)
    H.print('hovering the third item: its tooltip', (H.calls.BeginTooltip or 0) > tips)
    local opened = H.calls.OpenPopup or 0
    H.ret.IsMouseClicked = { true }; H.frames(1); H.ret.IsMouseClicked = nil
    H.print('right-click: its menu', (H.calls.OpenPopup or 0) > opened)

    -- the last of an item used up: the game says so with 0x020 alone
    H.bag(0, 30, { { 1, 5 }, { 20001 } }); H.packetData(0x020, Packet(0x0E, 0)); H.frames(6)
    tips = H.calls.BeginTooltip or 0; H.frames(1)
    H.print('the last of it used up: gone', (H.calls.BeginTooltip or 0) == tips)

    -- what a frame asks of imgui does not grow with the items
    H.ret.IsWindowHovered, H.ret.GetMousePos = nil, nil
    local before = Calls(); H.frames(1); local few = Calls() - before
    local many = {} for i = 1, 60 do many[i] = { i, 2 } end
    H.bag(0, 80, many); H.packetData(0x020, Packet(0x0E, 0)); H.frames(6)
    before = Calls(); H.frames(1); local lots = Calls() - before
    H.print('imgui calls a frame, 2 items then 60:', few, lots, lots == few)

    o.gridColumns[1] = 6
    H.ret.GetWindowPos, H.ret.GetWindowSize = { 100, 200 }, { 300, 150 }
end

-- the treasure pool, under the window: there only while there is treasure, and only while the window is
do
    H.tap(H.Button.B)
    local function Begun(frames) local b = H.calls.Begin H.frames(frames or 1) return H.calls.Begin - b end
    H.pool(0); H.print('pool: empty, one window a frame', Begun() == 1)
    o.treasureShowEmpty[1] = true; H.print('Show When Empty: two', Begun() == 2)
    do local sent = #H.sent; H.ret.SmallButton = { true }; H.frames(1); H.ret.SmallButton = nil
        H.print('the sample treasure\'s buttons send nothing', #H.sent == sent) end
    o.treasureShowEmpty[1] = false
    H.pool(3); H.print('three items: two windows a frame', Begun() == 2, '| on by default', o.treasurePool[1], '| attached', not o.treasureDetached[1])
    local sent = #H.sent
    H.ret.SmallButton = { true }; H.frames(1); H.ret.SmallButton = nil
    H.print('the buttons lot and pass', #H.sent > sent, H.sent[#H.sent])
    H.command('/inv toggle'); H.frames(8)
    H.print('attached, it goes with the window', Begun() == 0)
    o.treasureDetached[1] = true
    H.print('detached, it stays', Begun() == 1)
    o.treasurePool[1] = false
    H.print('switched off, it is gone', Begun() == 0)
    o.treasurePool[1], o.treasureDetached[1] = true, false
    H.command('/inv toggle'); H.pool(0); H.frames(8)
end

H.command('/inv toggle'); H.frames(8); H.print('/inv toggle closes it', o.isVisible[1] == false, '| A is the game\'s', H.tap(H.Button.A) == false)
H.print('/invite is left alone', H.command('/invite Someone') == false)
H.packet(0x01D); H.packet(0x01E); H.unload(); H.print('packets and unload ran; saves', H.saves() > 0)

-- renamed from inv: what it saved under that name is brought over, once for each character
do
    local o = H.options()
    local before = loadfile
    loadfile = function(p)
        if p:find('\\addons\\inv\\', 1, true) then
            return function() return { maxHeight = { 321 }, isUnified = { false }, importedFromXitools = true } end
        end
        return before(p)
    end
    o.importedFromFormer = false
    H.resettle()
    H.print('from inv: brought over', o.maxHeight[1] == 321 and o.isUnified[1] == false, '| once', o.importedFromFormer, '|', H.printed[#H.printed])
    o.maxHeight[1] = 400; H.resettle()
    H.print('and not again', o.maxHeight[1] == 400)
    loadfile = before
end
