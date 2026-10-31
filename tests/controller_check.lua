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
-- Automatic: the kind of controller the game reads, its padmode000's sixth field (Enable XInput), DirectInput taken
-- for a PlayStation controller; with the game's setting unread, the kind heard
assert(controller.GameKind('1,0,0,1,1,0') == 'directinput' and controller.GameKind('1,1,0,0,0,1') == 'xinput', 'GameKind reads Enable XInput')
assert(controller.GameKind('0,0,0,1,1,1') == nil and controller.GameKind('-1') == nil and controller.GameKind('1,0,0') == nil
    and controller.GameKind('1,0,0,1,1,x') == nil and controller.GameKind(42) == nil, 'GameKind: gamepad off, unread, short or odd')
assert(controller.Choices[1].key == controller.Automatic and controller.Choices[2].key == 'xinput' and #controller.Choices == #controller.Layouts + 1,
    'Choices: Automatic, then the Layouts')
local padmode = '1,0,0,1,1,0'
AshitaCore.GetConfigurationManager = function() return { GetString = function(_, alias, section, key)
    assert(alias == 'boot' and section == 'ffxi.registry' and key == 'padmode000'); return padmode end } end
H.print('Automatic, the game on DirectInput: PlayStation', controller.SetLayout(controller.Automatic) == 'playstation',
    controller.IsAutomatic(), controller.GetLayout() == 'playstation')
padmode = '1,1,0,0,0,1'
H.print('the game on XInput: XInput', controller.SetLayout(controller.Automatic) == 'xinput', controller.IsAutomatic())
controller.SetLayout('playstation'); H.print('a kind chosen: not Automatic', controller.IsAutomatic() == false)
padmode = nil; controller.SetLayout('xinput'); controller.SetLayout(controller.Automatic)
H.print('the game\'s setting unread: as it was', controller.GetLayout() == 'xinput', controller.IsAutomatic())
H.dinput(49, 128); H.print('a DirectInput press heard: PlayStation', controller.GetLayout() == 'playstation')
H.dinput(49, 0); on = true; H.frames(1)
H.print('a cross pressed then works the binding', H.dinput(49, 128)); H.dinput(49, 0)
on = false; H.frames(1)
H.button(H.Button.A, 1); H.print('an XInput press heard: XInput again', controller.GetLayout() == 'xinput'); H.button(H.Button.A, 0)
padmode = '1,0,0,1,1,0'; controller.SetLayout(controller.Automatic)
H.button(H.Button.A, 1); H.button(H.Button.A, 0)
H.print('the game\'s setting read: a press of the other kind changes nothing', controller.GetLayout() == 'playstation')
controller.SetLayout('xinput'); AshitaCore.GetConfigurationManager = nil
