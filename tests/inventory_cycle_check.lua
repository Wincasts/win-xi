-- inventory: Y cycles the controller through the inventory, the treasure pool (while there is treasure)
-- and the equipment monitor; the pool lots and passes with A, the monitor puts on and takes off gear
local o = H.options()
H.play(true)
o.isVisible[1], o.controller[1], o.controllerSounds[1] = true, true, true
o.equipment.enabled[1] = true
H.job(1, 75) -- a warrior: the harness's gear is warriors' head gear, level 1
H.gil(1000); H.bag(0, 30, { { 20001 }, { 20002 }, { 1, 5 } })
-- the controller the window's before the window has ever been drawn (its Begin refused): no legend, no error
do
    H.ret.Begin = { false }
    local ok, err = pcall(H.frames, 3)
    H.ret.Begin = { true }
    H.print('the window not yet drawn, the controller its: no error', ok, ok or err)
end
H.frames(8)

local function Sound() return H.sounds[#H.sounds] end
local function Sent() return H.sent[#H.sent] end

H.print('on by default: treasure', o.cycleTreasure[1], '| equipment', o.cycleEquipment[1])

-- no treasure: Y goes past the pool to the monitor
H.pool(0); H.frames(2)
H.print('Y is the window\'s', H.tap(H.Button.Y), '| no treasure: to the monitor', Sound() == 'tab')
H.tap(H.Button.A)
H.print('A on Main: nothing goes there', H.selected() == '(nothing to put on)')
H.tap(H.Button.B)
H.print('B closes the menu', Sound() == 'back')
H.tap(H.Button.B)
H.print('B again: back to the inventory, where X opens the sort menu', (H.tap(H.Button.X) and H.selected()) == 'Auto')
H.tap(H.Button.B)

-- with treasure: inventory, pool, monitor, inventory
H.pool(2); H.frames(2)
local sent = #H.sent
H.tap(H.Button.Y); H.tap(H.Button.A)
H.print('Y: the pool, on the first Lot: A lots on it', #H.sent == sent + 1 and Sent() == '41:0', Sound() == 'confirm')
H.tap(H.Button.DpadRight); H.tap(H.Button.A)
H.print('right: Pass, and A passes on it', Sent() == '42:0')
H.tap(H.Button.DpadDown); H.tap(H.Button.A)
H.print('down: the second Pass', Sent() == '42:1')
H.tap(H.Button.DpadLeft); H.tap(H.Button.A)
H.print('left: its Lot', Sent() == '41:1')
H.tap(H.Button.DpadUp); H.tap(H.Button.DpadUp); sent = #H.sent; H.tap(H.Button.A)
H.print('up past the first: Lot All, both lotted', #H.sent == sent + 2 and Sent() == '41:1')
H.tap(H.Button.DpadRight); sent = #H.sent; H.tap(H.Button.A)
H.print('right: Pass All, both passed', #H.sent == sent + 2 and Sent() == '42:1')
sent = #H.sent; H.tap(H.Button.DpadUp)
H.print('up from the top: stays, nothing sent', #H.sent == sent and Sound() ~= 'move')
H.tap(H.Button.B); H.tap(H.Button.Y); H.tap(H.Button.A)
H.print('back in: on the first Lot again', Sent() == '41:0')
H.tap(H.Button.Y)
H.print('Y: on to the monitor', Sound() == 'tab')
H.tap(H.Button.DpadDown); H.tap(H.Button.A)
H.print('down to Head, A: the gear for it, the first', H.selected())
sent = #H.sent
H.tap(H.Button.A)
H.print('A puts it on: 0x050 for its slot', #H.sent == sent + 1 and Sent() == '50:1')
H.tap(H.Button.Y)
H.print('Y: back to the inventory, where X opens the sort menu', (H.tap(H.Button.X) and H.selected()) == 'Auto')
H.tap(H.Button.B)

-- worn: Remove first, and what is worn not offered again
H.equip(4, 0, 1); H.frames(2)
H.tap(H.Button.Y); H.tap(H.Button.Y); H.tap(H.Button.A)
H.print('worn: Remove first', H.selected() == 'Remove')
sent = #H.sent
H.tap(H.Button.A)
H.print('Remove takes it off: 0x050 with no item', #H.sent == sent + 1 and Sent() == '50:0')
H.tap(H.Button.A); H.tap(H.Button.DpadDown)
H.print('then only the other', H.selected() == 'Item 20002')
H.tap(H.Button.B)

-- another job: none of it
H.job(18, 75); H.tap(H.Button.A); H.tap(H.Button.DpadDown)
H.print('a puppetmaster: nothing to put on', H.selected() == '(nothing to put on)')
H.tap(H.Button.B); H.job(1, 75)

-- the pool emptied while it has the controller: back to the inventory
H.tap(H.Button.B)
H.tap(H.Button.Y)
H.pool(0); H.frames(2)
H.print('the treasure gone: the inventory has it again', (H.tap(H.Button.X) and H.selected()) == 'Auto')
H.tap(H.Button.B)

-- left out of the cycle
H.pool(2); o.cycleTreasure[1] = false; H.frames(2)
H.tap(H.Button.Y); H.tap(H.Button.A)
H.print('Cycle Treasure Pool off: Y goes to the monitor', H.selected() == 'Remove')
H.tap(H.Button.B); H.tap(H.Button.B)
o.cycleEquipment[1] = false; H.frames(1)
H.tap(H.Button.Y)
H.print('both off: Y has nowhere to go', Sound() == 'error')
o.cycleTreasure[1], o.cycleEquipment[1] = true, true

-- sorting by hand is finished before Y moves on
H.tap(H.Button.X); H.tap(H.Button.DpadDown); H.tap(H.Button.A)
H.tap(H.Button.Y)
H.print('sorting by hand: Y refused', Sound() == 'error')
H.tap(H.Button.B)

-- closed and opened again: the inventory has the controller
H.tap(H.Button.Y)
H.command('/inv toggle'); H.frames(8); H.command('/inv toggle'); H.frames(8)
H.print('opened again: the inventory has it', (H.tap(H.Button.X) and H.selected()) == 'Auto')

-- the legend under the window, while it has the controller, its buttons named for the controller
do
    local function Texts() local before = H.calls['draw.AddText'] or 0 H.frames(1) return (H.calls['draw.AddText'] or 0) - before end
    H.tap(H.Button.B) -- the sort menu, open from the check before
    local shown = Texts()
    o.controllerLegend[1] = false
    local off = Texts()
    H.print('Controller Legend: on by default, drawn', shown > off)
    o.controllerLegend[1] = true
    H.tap(H.Button.B); local released = Texts()
    H.print('the controller given back: not drawn', released == off)
    H.command('/inv focus'); H.frames(1)
    local controller = require('winxi.controller')
    H.print('button names: XInput', controller.ButtonName(controller.Button.A), controller.ButtonName(controller.Button.LB))
    controller.SetLayout('playstation')
    H.print('PlayStation', controller.ButtonName(controller.Button.A), controller.ButtonName(controller.Button.Y), controller.ButtonName(controller.Button.RB))
    controller.SetLayout('switch')
    H.print('Switch Pro (A in the bottom place is its B)', controller.ButtonName(controller.Button.A))
    -- the glyphs: PlayStation's shapes (the triangle is Y's), Xbox's letters, the d-pad and the shoulder pills
    local function Count(name) local before = H.calls['draw.' .. name] or 0 H.frames(1) return (H.calls['draw.' .. name] or 0) - before end
    controller.SetLayout('playstation'); H.frames(1)
    H.print('PlayStation glyphs: a triangle', Count('AddTriangle') == 1, '| rounds and pills', Count('AddCircleFilled') > 0, Count('AddRectFilled') > 0)
    controller.SetLayout('xinput'); H.frames(1)
    H.print('Xbox glyphs: no triangle', Count('AddTriangle') == 0)
    H.print('glyph widths: a face button is square, a shoulder a pill wider than tall', controller.GlyphWidth(controller.Button.A, 16) == 16,
        controller.GlyphWidth(controller.Button.LB, 16) > 16, controller.GlyphWidth(controller.Dpad, 16) == 16)
end
