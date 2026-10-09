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

H.command('/inv'); H.frames(8); H.print('/inv closes it', o.isVisible[1] == false, '| A is the game\'s', H.tap(H.Button.A) == false)
H.print('/invite is left alone', H.command('/invite Someone') == false)
H.packet(0x01D); H.packet(0x01E); H.unload(); H.print('packets and unload ran; saves', H.saves() > 0)
