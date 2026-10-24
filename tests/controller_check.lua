-- winxi.controller on its own: the triggers, and telling other addons who has the controller
local controller = require('winxi.controller')
local on = false
controller.Bind({ active = function() return on end, actions = controller.StandardActions() })
H.frames(3)
H.print('idle: a trigger is the game\'s', H.button(H.Button.L2, 200) == false, '| nothing told', #H.raised); H.button(H.Button.L2, 0)
on = true; H.frames(70)
H.print('has the controller: told', H.raised[1], '| and again each second', #H.raised >= 2, '| trigger kept from the game', H.button(H.Button.L2, 200))
on = false; H.frames(1)
H.print('let go: told', H.raised[#H.raised], '| the trigger held is kept until it is let go', H.button(H.Button.L2, 200), H.button(H.Button.L2, 0),
    '| the next is the game\'s', H.button(H.Button.L2, 200) == false)
H.plugin('winxi_controller_focus', 'other:1'); H.print('another addon has it', controller.OtherHasFocus())
H.frames(120); H.print('and is forgotten when not heard from', controller.OtherHasFocus() == false)
-- a DualSense on DirectInput reports each trigger twice, as a button and as how far it is pulled: both kept
controller.SetLayout('playstation'); on = true; H.frames(1)
H.print('PlayStation: L2 kept as a button and as an axis', H.dinput(54, 128), H.dinput(12, 200), H.dinput(12, 0), H.dinput(54, 0))
on = false; H.frames(1); controller.SetLayout('xinput')
-- a binding that passes the triggers: told so, the triggers let through, and no press taken while one is held
local pass, pressed = false, 0
controller.Bind({ active = function() return pass end, actions = { [H.Button.Y] = 'y' }, press = function() pressed = pressed + 1 end, passTriggers = true })
pass = true; H.frames(1)
H.print('passTriggers: told', H.raised[#H.raised], '| a trigger the game\'s', H.button(H.Button.L2, 200) == false)
H.print('a button pressed with it held not taken', H.tap(H.Button.Y) == false, pressed == 0)
H.button(H.Button.L2, 0)
H.print('let go: the button taken again', H.tap(H.Button.Y) == true, pressed == 1)
on = true; H.frames(1)
H.print('with a binding that keeps them: told without pass', H.raised[#H.raised], '| the trigger kept', H.button(H.Button.L2, 200))
H.button(H.Button.L2, 0); on, pass = false, false; H.frames(1)
-- the kind of controller pressing buttons, and whether the layout chosen is the other kind
H.print('a DirectInput press heard on XInput: a mismatch', H.dinput(49, 128) == false, controller.Heard(), controller.LayoutMismatch())
H.dinput(49, 0); H.dinput(12, 200); H.dinput(12, 0)
controller.SetLayout('playstation'); H.print('PlayStation chosen: none', controller.LayoutMismatch() == false)
H.button(H.Button.A, 1); H.button(H.Button.A, 0)
H.print('an XInput press heard: a mismatch again', controller.Heard(), controller.LayoutMismatch())
controller.SetLayout('xinput')
