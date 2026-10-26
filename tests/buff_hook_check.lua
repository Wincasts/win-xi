-- buff with the buffhook plugin: the anchored bar is handed to the plugin, in the game's pixels from
-- where the game puts its first icon, instead of being drawn as a window; the game's row of icons is
-- left for the plugin to stand in for; an empty bar keeps it away while the bar is hidden; and without
-- the plugin, or with one that took nothing, the bar is a window again.
--     luajit tests/harness.lua buff addons/buff/buff.lua tests/buff_hook_check.lua
local ffi = require('ffi')
local imgui = require('imgui')
local game = require('winxi.game')
local icons = require('winxi.statusicons')
local hook = require('hook')
local plugin = os.getenv('UIHOOK_TEST_PLUGIN') or 'buffhook'

for _, key in ipairs({ 'IsLoading', 'IsInterfaceHidden', 'IsEventHappening', 'IsChatExpanded', 'IsMapOpen' }) do
    game[key] = function() return false end
end
local chat = false
game.IsChatExpanded = function() return chat end
local menu = ''
game.MenuName = function() return menu end

-- Protect (40, no end), Haste (33, 90 seconds left)
local statuses = require('statuses')
statuses.Read = function(list)
    list[1], list[2] = { id = 40 }, { id = 33, seconds = 90 }
    for index = #list, 3, -1 do list[index] = nil end
    return 2
end
AshitaCore.GetResourceManager = function() return { GetString = function(_, _, id) return 'Status ' .. id end,
    GetStatusIconByIndex = function(_, id) return { CanCancel = id == 33 and 1 or 0, HideTimer = 0, Description = { 'What it does.' } } end } end
icons.Get = function(id) return 0x1000 + id, true end

-- The plugin's block, as it would be in its DLL; and the game's code the addon changes
local holder = ffi.new('buffhook_t[1]')
local block = holder[0]
block.Version, block.Size, block.Hooked, block.Frame = 4, ffi.sizeof('buffhook_t'), 1, 10
block.Width, block.Height = 960, 540 -- the game's picture, half imgui's 1920 by 1080
local written, at = {}, { ['75??8B4E0851B9'] = 100, ['7D??33C05EC20400C6'] = 200, ['85C00F??????????6A0232DBE8'] = 300 }
ashita.memory.find = function(module, _, pattern)
    if module == plugin .. '.dll' then return tonumber(ffi.cast('uintptr_t', holder)) end
    return at[pattern] or 0
end
ashita.memory.read_uint16 = function(pointer) return written[pointer] or pointer + 1 end
ashita.memory.write_uint16 = function(pointer, value) written[pointer] = value end

-- the font: a glyph a letter, 6 wide, from a texture of its own
local font = { ContainerAtlas = { TexData = { UniqueID = 2, Status = 0, Width = 512, Height = 256 } } }
imgui.GetFont = function() return font end
local baked = { FindGlyph = function(_, byte) return { X0 = 0, Y0 = 2, X1 = 5, Y1 = 12, U0 = byte / 256, V0 = 0, U1 = (byte + 1) / 256, V1 = 1, AdvanceX = 6, Visible = 1 } end }
imgui.GetFontBaked = function() return baked end

local o = H.options()
o.fadeInOut[1] = false
H.play(true)
H.loaded(plugin, true)

local begins = H.calls.Begin or 0
H.frames(1)
H.print('handed over, not drawn as a window', block.SubmitFrame == 10, (H.calls.Begin or 0) == begins)
H.print('the textures: the font\'s mark and the two icons', block.Textures[0] == 1, block.Textures[1] == 0x1000 + 40, block.Textures[2] == 0x1000 + 33)
-- Protect has no end: two icons, and Haste's 90 seconds, "1m": two letters, each five times over
H.print('quads: two icons, two letters with their edges', block.Count == 2 + 2 * 5)
local first = block.Quads[0]
local width = math.floor(40 * icons.OwnAspect + 0.5)
H.print('the first icon at the first icon\'s place, in the game\'s pixels', first.X0 == 0 and first.Y0 == 0, first.X1 == width * 0.5, first.Y1 == 40 * 0.5,
    '| white', first.Color == 0xFFFFFFFF, '| from its texture', first.Texture == 1)
local second = block.Quads[1]
H.print('the second beside it, a gap on', second.X0 == (width + 4) * 0.5 and second.Y0 == 0)
local edge, letter = block.Quads[2], block.Quads[10]
H.print('the edge first, dark, then the letter', bit.rshift(edge.Color, 24) < 255 and bit.band(edge.Color, 0xFFFFFF) == 0, letter.Texture == 0, letter.Y0 > first.Y1)
H.print('the game\'s row left to the plugin, the rest hidden', written[100] == nil and written[200] == nil, written[300] == 0xC031)

-- nudged: the whole bar moves, in imgui's pixels
o.anchorAdjustment[1], o.anchorAdjustment[2] = 10, 4
block.Frame = 11; H.frames(1)
H.print('nudged', block.Quads[0].X0 == 5 and block.Quads[0].Y0 == 2)
o.anchorAdjustment[1], o.anchorAdjustment[2] = 0, 0

-- hidden by the shared rules, or switched off: an empty bar, so that the game's icons stay away
chat = true; block.Frame = 12; H.frames(1)
H.print('hidden under chat: an empty bar', block.SubmitFrame == 12 and block.Count == 0)
chat = false; o.isVisible[1] = false; block.Frame = 13; H.frames(1)
H.print('switched off: an empty bar', block.SubmitFrame == 13 and block.Count == 0)
o.isVisible[1] = true

-- under the mouse, with the game having drawn it: a window over the cell, for its tooltip and click
block.DrawnFrame, block.Frame, block.OriginX, block.OriginY = 14, 14, 100, 50
H.ret.GetMousePos = { 200 + 2, 100 + 2 } -- the first icon's corner in imgui's pixels, and a little in
H.ret.IsItemHovered = { true }
local tips = H.calls.BeginTooltip or 0
begins = H.calls.Begin or 0
H.frames(1)
H.print('hovered: a window over the cell, and the tooltip', (H.calls.Begin or 0) == begins + 1, (H.calls.BeginTooltip or 0) == tips + 1)
menu = 'menu    mcr1pall'; begins = H.calls.Begin; block.Frame = 15; block.DrawnFrame = 15
H.frames(1)
H.print('not while a menu of the game\'s is open, as it may be over the bar', H.calls.Begin == begins)
menu = ''

-- Grow From: the row at the right of a full row of Icons Per Row (16), or in its middle; the mouse
-- finds the icons where they are drawn
block.Frame, block.DrawnFrame = 16, 16; H.frames(1)
local x0, x1 = block.Quads[0].X0, block.Quads[1].X0 -- as Left has them
local step = x1 - x0 -- a cell and a gap, in the game's pixels
o.growFrom = 'Right'; block.Frame, block.DrawnFrame = 16, 16; H.frames(1)
H.print('Grow From Right: the two icons at the end of the row', block.Quads[0].X0 == x0 + 14 * step, block.Quads[1].X0 == x1 + 14 * step)
H.ret.GetMousePos = { 200 + 2, 100 + 2 }; begins = H.calls.Begin; block.Frame, block.DrawnFrame = 17, 17; H.frames(1)
H.print('nothing to hover where they were', H.calls.Begin == begins)
H.ret.GetMousePos = { 200 + 14 * step * 2 + 2, 100 + 2 }; begins = H.calls.Begin; block.Frame, block.DrawnFrame = 18, 18; H.frames(1)
H.print('the first where it is drawn', H.calls.Begin == begins + 1)
o.growFrom = 'Middle'; block.Frame, block.DrawnFrame = 19, 19; H.frames(1)
H.print('Grow From Middle: in the middle of the row', block.Quads[0].X0 == x0 + 7 * step)
o.growFrom = 'Left'; H.ret.GetMousePos = { 200 + 2, 100 + 2 }

-- dragged with the left button: the adjustment follows the mouse, and is saved as it is let go;
-- not with Lock Position on, nor in the selector, where a click removes a status
local function drag(n, dx, dy)
    H.ret.GetMousePos = { 202, 102 }; H.ret.IsMouseClicked = { true }; H.ret.IsMouseDown = { true }
    block.Frame, block.DrawnFrame = n, n; H.frames(1)
    H.ret.IsMouseClicked = { false }; H.ret.GetMousePos = { 202 + dx, 102 + dy }
    block.Frame, block.DrawnFrame = n + 1, n + 1; H.frames(1)
end
local saves = H.saves()
drag(16, 30, 12)
H.print('dragged: the adjustment follows the mouse', o.anchorAdjustment[1] == 30 and o.anchorAdjustment[2] == 12, '| the bar with it', block.Quads[0].X0 == 15 and block.Quads[0].Y0 == 6)
H.ret.IsMouseDown = { false }; block.Frame, block.DrawnFrame = 18, 18; H.frames(1)
H.print('let go: saved', H.saves() > saves)
o.anchorAdjustment[1], o.anchorAdjustment[2] = 0, 0
o.lockPosition[1] = true; drag(19, 30, 12)
H.print('Lock Position: not moved', o.anchorAdjustment[1] == 0 and o.anchorAdjustment[2] == 0)
o.lockPosition[1] = false; menu = 'menu    buff    '; drag(21, 30, 12)
H.print('the selector: not moved', o.anchorAdjustment[1] == 0 and o.anchorAdjustment[2] == 0)
menu = ''; H.ret.IsMouseDown = { false }; block.Frame, block.DrawnFrame = 23, 23; H.frames(1)
-- between two icons, not on one: a window over the bar takes the click, and drags it all the same
begins = H.calls.Begin
H.ret.GetMousePos = { 200 + step * 2 - 2, 102 }; H.ret.IsMouseClicked = { true }; H.ret.IsMouseDown = { true }
block.Frame, block.DrawnFrame = 24, 24; H.frames(1)
H.print('the gap between two icons: a window over the bar', H.calls.Begin == begins + 1)
H.ret.IsMouseClicked = { false }; H.ret.GetMousePos = { 200 + step * 2 - 2 + 20, 102 + 8 }
block.Frame, block.DrawnFrame = 25, 25; H.frames(1)
H.print('dragged from the gap: the adjustment follows the mouse', o.anchorAdjustment[1] == 20 and o.anchorAdjustment[2] == 8)
H.ret.IsMouseDown = { false }; block.Frame, block.DrawnFrame = 26, 26; H.frames(1)
o.anchorAdjustment[1], o.anchorAdjustment[2] = 0, 0
H.ret.GetMousePos = { 0, 0 }; H.ret.IsItemHovered = { false }

-- without the plugin, or with one that took nothing: a window, and the game's row hidden again
H.loaded(plugin, false); begins = H.calls.Begin
H.frames(1)
H.print('no plugin: a window', H.calls.Begin > begins, '| the row hidden', written[100] == 0x9090 and written[200] == 0x9090,
    '| said in the settings', hook.Problem() ~= nil and hook.Problem():find('/load buffhook') ~= nil)
H.loaded(plugin, true); block.Hooked = 0; begins = H.calls.Begin
H.frames(1)
H.print('a plugin that took nothing: a window', H.calls.Begin > begins, '| said', hook.Problem() ~= nil and hook.Problem():find('recognise') ~= nil)
block.Hooked = 1; block.Frame = 20; H.frames(1)
H.print('the plugin again: handed over, the row given back', block.SubmitFrame == 20, written[100] == 101 and written[200] == 201)

-- not anchored: a window; with the game's icons hidden, the plugin keeps them, and its hand, away
o.anchorToDefault[1] = false; block.Frame = 21; begins = H.calls.Begin
H.frames(1)
H.print('draggable: a window, and an empty bar handed over', H.calls.Begin > begins, block.SubmitFrame == 21 and block.Count == 0,
    '| the row left to the plugin', written[100] == 101 and written[200] == 201)
o.hideGameIcons[1] = false; block.Frame = 22; H.frames(1)
H.print('draggable, the game\'s icons shown: nothing handed over', block.SubmitFrame == 21, '| nothing hidden', written[300] == 301)
o.hideGameIcons[1] = true

-- The buff selector: the status the game's cursor is on has the highlight round it, drawn by the
-- plugin anchored, and in the window dragged; a click on an icon removes it
menu = 'menu    buff    '
block.CursorStatus = 33
block.Frame = 30; block.DrawnFrame = 30; H.frames(1)
local rects = H.calls['draw.AddRect'] or 0
block.Frame = 31; block.DrawnFrame = 31; H.frames(1)
H.print('dragged: the highlight drawn round the cursor\'s status', (H.calls['draw.AddRect'] or 0) == rects + 2)
o.anchorToDefault[1] = true
block.Frame = 32; block.DrawnFrame = 32; H.frames(1)
local solid, around = 0, true
for i = 0, block.Count - 1 do
    local quad = block.Quads[i]
    if quad.Texture == hook.Solid then
        solid = solid + 1
        around = around and quad.X1 > (width + 4) * 0.5 - 3 and quad.X0 < (2 * width + 4) * 0.5 + 3
    end
end
H.print('anchored: the highlight handed over, a line and its glow, round Haste', solid == 8, around)
block.CursorStatus = 0xFFFF; block.Frame = 33; block.DrawnFrame = 33; H.frames(1)
solid = 0
for i = 0, block.Count - 1 do if block.Quads[i].Texture == hook.Solid then solid = solid + 1 end end
H.print('no status under the cursor: no highlight', solid == 0)

-- with the game's hand read from its DAT: the hand at the left of the status in place of the
-- highlight, its fingertip at the icon's edge, as tall as the icon and over the icons
local handLib = require('winxi.cursor')
local handGet = handLib.Get
local handFrame = { 0, 0, 0.5, 0.25, 32, 20, corners = { -32, -2, 0, -2, -32, 18, 0, 18 } }
handLib.Get = function() return 0x5000, handFrame end
block.CursorStatus = 33; block.Frame = 40; block.DrawnFrame = 40; H.frames(1)
local hands, handQuad = 0, nil
solid = 0
for i = 0, block.Count - 1 do
    local quad = block.Quads[i]
    if quad.Texture == hook.Solid then solid = solid + 1 end
    if quad.Texture ~= hook.Solid and block.Textures[quad.Texture] == 0x5000 then hands, handQuad = hands + 1, quad end
end
H.print('anchored, the hand: handed over in place of the highlight', hands == 1, solid == 0)
H.print('its fingertip at Haste\'s left edge, Cursor Size (60%) of the icon\'s height, written last',
    handQuad ~= nil and math.abs(handQuad.X1 - (width + 4) * 0.5) < 0.01 and math.abs((handQuad.Y1 - handQuad.Y0) - o.iconSize[1] * 0.6 * 0.5) < 0.01,
    block.Quads[block.Count - 1] == handQuad)
o.cursorSize[1] = 100; block.Frame = 45; block.DrawnFrame = 45; H.frames(1)
handQuad = block.Quads[block.Count - 1]
H.print('at 100%, as tall as the icon, in the middle of its height', math.abs((handQuad.Y1 - handQuad.Y0) - o.iconSize[1] * 0.5) < 0.01,
    math.abs((handQuad.Y0 + handQuad.Y1) / 2 - o.iconSize[1] * 0.25) < 0.01)
o.cursorSize[1] = 60
o.anchorToDefault[1] = false
block.Frame = 41; block.DrawnFrame = 41; H.frames(1)
local function counted(n)
    local images, rects = H.calls['draw.AddImage'] or 0, H.calls['draw.AddRect'] or 0
    block.Frame, block.DrawnFrame = n, n; H.frames(1)
    return (H.calls['draw.AddImage'] or 0) - images, (H.calls['draw.AddRect'] or 0) - rects
end
local withImages, withRects = counted(42)
handLib.Get = handGet
local withoutImages, withoutRects = counted(43)
H.print('dragged, the hand: one image more, in place of the highlight', withImages == withoutImages + 1, withRects == 0, withoutRects == 2)
o.anchorToDefault[1] = true
block.CursorStatus = 0xFFFF; block.Frame = 44; block.DrawnFrame = 44; H.frames(1)

block.OriginX, block.OriginY = 100, 50
H.ret.GetMousePos = { 200 + 2, 100 + 2 }; H.ret.IsItemHovered = { true }; H.ret.IsItemClicked = { true }
local sent = #H.sent
block.Frame = 34; block.DrawnFrame = 34; H.frames(1)
H.print('in the selector, a click on Protect: it cannot be removed, nothing sent', #H.sent == sent)
H.ret.GetMousePos = { 200 + (width + 4) + 2, 100 + 2 }
block.Frame = 35; block.DrawnFrame = 35; H.frames(1)
H.print('a click on Haste removes it', #H.sent == sent + 1)
H.ret.GetMousePos = { -1000, -1000 }; H.ret.IsItemHovered = { false }; H.ret.IsItemClicked = { false }
menu = ''

-- The controller's confirm in the selector removes the status its cursor is on: the press is left to
-- the game, and buff asks only if the game has not a moment later
o.anchorToDefault[1] = true
local function frame(n) block.Frame = n; block.DrawnFrame = n; H.frames(1) end
menu = 'menu    buff    '; block.CursorStatus = 33; frame(40)
local sent = #H.sent
H.print('A on Haste in the selector: left to the game', H.tap(H.Button.A) == false, '| nothing sent at once', #H.sent == sent)
frame(41); frame(42); frame(43); frame(44); frame(45); frame(46); frame(47); frame(48); frame(49)
H.print('the game did not ask: buff asks for Haste once', #H.sent == sent + 1, H.sent[#H.sent] == 'F1:33')
frame(50); frame(51); frame(52); frame(53); frame(54); frame(55); frame(56); frame(57); frame(58)
H.print('and only once', #H.sent == sent + 1)
sent = #H.sent
H.tap(H.Button.A)
H.packetOutData(0xF1, string.char(0xF1, 4, 0, 0, 33, 0, 0, 0))
for n = 60, 70 do frame(n) end
H.print('the game asked for it itself: nothing more sent', #H.sent == sent)
o.controllerType = 'playstation'
H.print('PlayStation cross (DirectInput 49) left to the game', H.dinput(49, 128) == false); H.dinput(49, 0)
for n = 71, 81 do frame(n) end
H.print('and Haste asked for', #H.sent == sent + 1)
sent = #H.sent
H.dinput(48, 128); H.dinput(48, 0)
for n = 82, 92 do frame(n) end
H.print('square: nothing', #H.sent == sent)
o.controllerType = 'xinput'
block.CursorStatus = 40; frame(93)
H.tap(H.Button.A)
for n = 94, 104 do frame(n) end
H.print('A on Protect, which cannot be removed: nothing', #H.sent == sent)
block.CursorStatus = 33; o.controller[1] = false; frame(105)
H.tap(H.Button.A)
for n = 106, 116 do frame(n) end
H.print('with Controller Navigation off: nothing', #H.sent == sent)
o.controller[1] = true
menu = ''; frame(117)
H.tap(H.Button.A)
for n = 118, 128 do frame(n) end
H.print('A out of the selector: nothing', #H.sent == sent)
block.CursorStatus = 0xFFFF; frame(129)

-- The bar is written only when something of it changes, and handed over again as it was otherwise;
-- a plugin loaded again has nothing of it, and it is written afresh
block.Frame = 50; H.frames(1)
local sequence, count = block.Sequence, block.Count
block.Frame = 51; H.frames(1)
H.print('unchanged: handed over again, not written', block.SubmitFrame == 51, block.Sequence == sequence)
o.iconSize[1] = 48; block.Frame = 52; H.frames(1)
H.print('changed: written afresh', block.Sequence == sequence + 1)
o.iconSize[1] = 40; block.Frame = 53; H.frames(1)
block.Sequence, block.Count = 0, 0 -- the plugin loaded again
block.Frame = 54; H.frames(1)
H.print('a plugin loaded again: written afresh', block.Sequence == 1 and block.Count > 0)
sequence = block.Sequence
font.ContainerAtlas.TexData.UniqueID = 3 -- imgui made its font texture again
block.Frame = 55; H.frames(1)
H.print('imgui\'s font texture made again: written afresh, the font still its mark', block.Sequence == sequence + 1, block.Textures[0] == 1)
font.ContainerAtlas.TexData.Status = 2 -- and has it not ready
block.Frame = 56; H.frames(1)
H.print('the font texture not ready: the bar still handed over, with no font', block.SubmitFrame == 56)
font.ContainerAtlas.TexData.Status = 0
