-- treas: loads, brings its settings over, shows the pool, lots and passes by mouse and by controller
local o = H.options()
H.print('imported', o.importedFromXitools, '| pos', o.pos[1], o.pos[2], '| showAll', o.showAllSlots[1], '| fadeInOut', o.fadeInOut[1])
H.print('said:', H.printed[#H.printed])

H.play(true); H.frames(4); H.print('no treasure: windows begun', H.calls.Begin or 0)
H.pool(3); H.frames(6); H.print('three items: windows begun', H.calls.Begin, '| rows', H.calls.TableNextRow)

H.ret.Button = { true }; H.frames(1); H.ret.Button = { false }
H.print('every button clicked: packets', #H.sent, H.sent[1], H.sent[#H.sent])
for i = #H.sent, 1, -1 do H.sent[i] = nil end

H.print('not focused: A is the game\'s', H.tap(H.Button.A) == false)
H.command('/treas focus'); H.print('with the setting off:', H.printed[#H.printed])
o.controller[1] = true; H.command('/treas focus'); H.frames(2)
H.print('focused: down is the window\'s', H.tap(H.Button.DpadDown), '| left is the game\'s', H.tap(H.Button.DpadLeft) == false)
H.print('A opens the menu on', H.tap(H.Button.A) and H.selected()); H.tap(H.Button.A); H.print('Lot sends', H.sent[#H.sent])
H.tap(H.Button.X); H.print('X opens the menu for all, on', H.selected())
H.tap(H.Button.DpadDown); H.tap(H.Button.A); H.print('Pass All asks first, on', H.selected())
H.tap(H.Button.DpadDown); H.tap(H.Button.A); H.print('confirmed:', table.concat(H.sent, ' '))
H.print('B gives the controller back', H.tap(H.Button.B), '| then A is the game\'s', H.tap(H.Button.A) == false)

H.print('/treas config kept from the game', H.command('/treas config')); H.frames(1)
H.command('/treas'); H.print('/treas hides it', o.isVisible[1] == false, '| /treasure is left alone', H.command('/treasure x') == false)
H.unload(); H.print('unload ran; saves', H.saves() > 0)
