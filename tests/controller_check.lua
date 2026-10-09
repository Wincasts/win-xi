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
