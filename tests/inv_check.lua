-- inv: loads, brings its settings over from xitools, draws, answers its command, takes the controller
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
    H.command('/inv'); H.frames(8)
    H.print('attached, it goes with the window', Begun() == 0)
    o.treasureDetached[1] = true
    H.print('detached, it stays', Begun() == 1)
    o.treasurePool[1] = false
    H.print('switched off, it is gone', Begun() == 0)
    o.treasurePool[1], o.treasureDetached[1] = true, false
    H.command('/inv'); H.pool(0); H.frames(8)
end

H.command('/inv'); H.frames(8); H.print('/inv closes it', o.isVisible[1] == false, '| A is the game\'s', H.tap(H.Button.A) == false)
H.print('/invite is left alone', H.command('/invite Someone') == false)
H.packet(0x01D); H.packet(0x01E); H.unload(); H.print('packets and unload ran; saves', H.saves() > 0)
