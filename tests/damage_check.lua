-- damage and winxi.popups: the game's damage popups read from namehook, claimed, and drawn in winxi's
-- style, one for each hit. The plugin here is blocks of the same shape, made in this file.
local ffi = require('ffi')
local imgui = require('imgui')
local popups = require('winxi.popups')

local names = ffi.new('namehook_t')
ffi.copy(names.Magic, 'NAMEHOOK')
names.Version, names.Size, names.NameSize, names.Hooked = 3, ffi.sizeof('namehook_t'), ffi.sizeof('namehook_name_t'), 1
names.Width, names.Height, names.TargetWidth, names.TargetHeight = 1920, 1080, 1920, 1080
names.Frame = 100

local block = ffi.new('namehook_popups_t')
ffi.copy(block.Magic, 'NAMEHOOKPOPUPS')
block.Version, block.Size, block.PopupSize, block.Hooked = 1, ffi.sizeof('namehook_popups_t'), ffi.sizeof('namehook_popup_t'), 1
-- the plugin gives the drawings' place as 32 bits: in low memory, as it is in the game
ffi.cdef('void* mmap(void*, size_t, int, int, int, long);')
local low = ffi.C.mmap(nil, ffi.sizeof('namehook_popup_draw_t'), 3, 0x62, -1, 0) -- read and write; private, anonymous, 32-bit
assert(low ~= ffi.cast('void*', -1))
local draw = ffi.cast('namehook_popup_draw_t*', low)
draw.QuadsMax, draw.DrawingsMax = 4096, 64
block.Draw = tonumber(ffi.cast('uintptr_t', low))

local function address(data) return tonumber(ffi.cast('uintptr_t', ffi.cast('void*', data))) end
ashita.memory.find = function(module, _, signature)
    if module ~= 'namehook.dll' then return 0 end
    if signature == '4E414D45484F4F4B504F505550530000' then return address(block) end
    if signature == '4E414D45484F4F4B0000000000000000' then return address(names) end
    return 0
end

-- imgui's letters: each 10 wide and 20 tall, a space with nothing to draw
rawset(imgui, 'GetFont', function() return { ContainerAtlas = { TexData = { UniqueID = 7, Status = 0 } } } end)
local pushed = {}
rawset(imgui, 'PushFont', function(_, size) pushed[#pushed + 1] = size end)
rawset(imgui, 'PopFont', function() end)
rawset(imgui, 'GetFontBaked', function()
    return { FindGlyph = function(_, byte)
        return { X0 = 1, Y0 = 2, X1 = 9, Y1 = 18, U0 = byte / 256, V0 = 0, U1 = (byte + 1) / 256, V1 = 1, AdvanceX = 10, Visible = byte ~= 32 }
    end }
end)

H.print('the blocks are laid out as the plugin has them', ffi.sizeof('namehook_popup_t') == 84, ffi.offsetof('namehook_popups_t', 'Draw') == 52,
    ffi.offsetof('namehook_popups_t', 'Popups') == 56, ffi.sizeof('namehook_popup_drawing_t') == 32,
    ffi.offsetof('namehook_popup_draw_t', 'Drawings') == 56, ffi.offsetof('namehook_popup_draw_t', 'Quads') == 56 + 32 * 64)

-- the game's popups: a hit and its copy, a miss and its empty copy, and another's hit
local function popup(i, id, text, target, source, color, first)
    local p = block.Popups[i]
    p.Id, p.EntityIndex, p.SourceIndex, p.Flags, p.Color, p.FirstFrame = id, target, source, 1 + 4 + 8, color, first or 99
    p.Scale = 1
    ffi.copy(p.Text, text)
end
popup(0, 6, '74', 0x0E, 0x40B, 0x18962626, 100) -- the copy, first listed a frame after the number
popup(1, 5, '74', 0x0E, 0x40B, 0x40FF3C3C)
popup(2, 7, ':', 0x14, 0x80C, 0x217A8C7A)
popup(3, 8, '', 0x14, 0x80C, 0x15460F64)
popup(4, 9, '74', 0x14, 0x80C, 0x80FFFFFF)
block.Count = 5

-- without the plugin: nothing claimed, the problem said once
H.frames(2)
local said = 0
for _, line in ipairs(H.printed) do if line:find('not loaded', 1, true) then said = said + 1 end end
H.print('no plugin: nothing claimed', block.Claimed == 0, '| said once', said == 1)

H.loaded('namehook', true)
H.frames(1)
H.print('claimed with the names\' frame', block.Claimed == 1, block.ClaimFrame == 100, '| drawn for that frame', draw.Frame == 100)
H.print('one drawing for each hit, the number and not its copy', draw.Count == 3, draw.Drawings[0].Id == 5, draw.Drawings[1].Id == 7, draw.Drawings[2].Id == 9)
local hit, miss = draw.Drawings[0].Drawing, draw.Drawings[1].Drawing
H.print('"74" two letters, "Miss!" five', hit.Count == 2, miss.Count == 5, miss.First == 2, draw.QuadCount == 2 + 5 + 2)
local first = draw.Quads[0]
H.print('centred on the point at 26 pixels', first.X0 == -10 + 1, first.Y0 == -13 + 2, draw.Quads[1].X1 == 9 + 0, pushed[1] == 26)
H.print('the game\'s colour, its alpha doubled', first.Color == 0x80FF3C3C, draw.Quads[2].Color == 0x427A8C7A, draw.Quads[7].Color == 0xFFFFFFFF)
H.print('edged, from imgui\'s letters', first.Flags == 1, first.Texture == 0, draw.Textures[0] == 1, hit.Edge > 0, draw.Drawings[0].Flags == 0)

-- smaller far away, and the game's size followed
block.Popups[1].Scale = 0.5
names.Frame = 101
pushed = {}
H.frames(1)
H.print('at half the size, 13 pixels', pushed[1] == 13, draw.Frame == 101, block.ClaimFrame == 101)

-- off: the game's to draw; on again, claimed
H.command('/damage off')
H.print('off: the claim given up', block.Claimed == 0, draw.Count == 0)
names.Frame = 102
H.frames(1)
H.print('and not made again', block.Claimed == 0, draw.Frame == 101)
H.command('/damage on')
H.frames(1)
H.print('on: claimed again', block.Claimed == 1, block.ClaimFrame == 102)

-- unloaded: the claim given up
H.unload()
H.print('unload gives up the claim', block.Claimed == 0)
H.print('Miss! for the game\'s ":"', popups.Text(block.Popups[2]) == 'Miss!', popups.Text(block.Popups[0]) == '74')
