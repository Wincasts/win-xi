-- namehooktest against namehook 1.46's blocks stood in for: with a target, the layer's cross at the target and
-- the square at its name's point, the camera's dot, and with slot on the target's name drawn through a slot
-- above Name's claim; with no namehook, said once and nothing drawn; unloaded, the layer and slot given back.
--     luajit tests/harness.lua namehooktest addons/namehooktest/namehooktest.lua tests/namehooktest_check.lua
local ffi = require('ffi')
local imgui = require('imgui')
local nameplates = require('winxi.nameplates')
nameplates.Module = function() return 1, 0, 0 end
require('winxi.fonts').Texture = function() return 1, 7 end
imgui.GetFontTexUvWhitePixel = function() return 0.25, 0.75 end

local before = #H.printed
H.frames(3)
H.print('no namehook: said once', #H.printed - before == 1 and H.printed[#H.printed]:find('/load namehook', 1, true) ~= nil)

pcall(ffi.cdef, 'void* mmap(void*, size_t, int, int, int, long);')
local function low(ctype) return ffi.cast(ctype .. '*', ffi.C.mmap(nil, ffi.sizeof(ctype), 3, 0x62, -1, 0)) end
local function at(p) return tonumber(ffi.cast('uintptr_t', ffi.cast('void*', p))) end
local names = low('namehook_t')
names.Version, names.Size, names.NameSize, names.Hooked, names.Frame, names.Sequence = 3, ffi.sizeof('namehook_t'), ffi.sizeof('namehook_name_t'), 1, 40, 1
names.TargetWidth, names.TargetHeight, names.Width, names.Height = 1920, 1080, 1920, 1080
names.Count = 1
names.Names[0].EntityIndex, names.Names[0].ServerId, names.Names[0].X, names.Names[0].Y, names.Names[0].Z = 0x401, 0x2000, 1, 2, 3
local claims = low('namehook_claims_t')
claims.Version, claims.Size, claims.SlotSize, claims.SlotsMax, claims.SharedPriority = 1, ffi.sizeof('namehook_claims_t'), ffi.sizeof('namehook_claim_slot_t'), 3, 100
local slotDraw = low('namehook_draw_t'); slotDraw.QuadsMax = 16384
claims.Slots[0].Draw = at(slotDraw)
local layerBlock = low('namehook_layers_t')
layerBlock.Version, layerBlock.Size, layerBlock.SlotSize, layerBlock.SlotsMax = 1, ffi.sizeof('namehook_layers_t'), ffi.sizeof('namehook_layer_slot_t'), 4
local layerDraw = low('namehook_layer_draw_t'); layerDraw.QuadsMax, layerDraw.DrawingsMax = 8192, 512
layerBlock.Slots[0].Draw = at(layerDraw)
local cam = low('namehook_camera_t')
cam.Version, cam.Size, cam.Frame, cam.Valid = 1, ffi.sizeof('namehook_camera_t'), 40, 1
cam.ViewProjection[0], cam.ViewProjection[5], cam.ViewProjection[10], cam.ViewProjection[15] = 0.1, 0.1, 0.1, 1
local addresses = {
    ['4E414D45484F4F4B0000000000000000'] = at(names), ['4E414D45484F4F4B434C41494D530000'] = at(claims),
    ['4E414D45484F4F4B4C41594552530000'] = at(layerBlock), ['4E414D45484F4F4B43414D4552410000'] = at(cam),
}
ashita.memory.find = function(module, _, magic) return module == 'namehook.dll' and addresses[magic] or 0 end
H.loaded('namehook', true)
local manager = AshitaCore.GetMemoryManager
local targetIndex = 0x401
AshitaCore.GetMemoryManager = function()
    local m = manager()
    m.GetTarget = function() return { GetTargetIndex = function(_, which) return which == 0 and targetIndex or 0 end } end
    m.GetEntity = function() return { GetServerId = function(_, i) return i == 0x401 and 0x2000 or 0 end } end
    return m
end

H.frames(3)
local cross, square = layerDraw.Drawings[0], layerDraw.Drawings[1]
H.print('a layer taken, ordered', layerBlock.Slots[0].Owner == nameplates.OwnerOf('namehooktest') and layerBlock.Slots[0].Order == 10)
H.print('the cross at the target, anchored to it', layerDraw.Count == 2 and cross.Flags == 1 and cross.EntityIndex == 0x401 and cross.ServerId == 0x2000 and cross.Drawing.Count == 2)
H.print('the square at its name\'s point in the world', square.Flags == 2 and square.X == 1 and square.Y == 2 and square.Z == 3 and square.Drawing.Count == 4)
H.print('from the font\'s white pixel', layerDraw.Textures[0] == 1 and layerDraw.Quads[0].U0 == 0.25 and layerDraw.Quads[0].V1 == 0.75)
H.print('the camera\'s dot drawn', (H.calls['draw.AddCircleFilled'] or 0) >= 2)

H.command('/nht over on')
H.frames(1)
H.print('over: drawn over everything', layerDraw.Drawings[0].Flags == 1 + 4 and layerDraw.Drawings[1].Flags == 2 + 4)
H.command('/nht slot on')
H.frames(2)
local s = claims.Slots[0]
H.print('slot: every name claimed above Name', s.Owner == nameplates.OwnerOf('namehooktest') and s.Categories == 0xFF and s.Priority == 200 and s.ClaimFrame == 40)
H.print('the target\'s name alone drawn into it', slotDraw.Entities[0x401].Count == 1 and slotDraw.QuadCount == 1)
targetIndex = 0
H.frames(1)
H.print('no target: the claim kept, nothing drawn', s.Owner ~= 0 and slotDraw.QuadCount == 0 and layerDraw.Count == 0)
H.command('/nht slot off')
H.print('slot off: given back', s.Owner == 0 and slotDraw.QuadCount == 0)
H.unload()
H.print('unloaded: the layer given back', layerBlock.Slots[0].Owner == 0 and layerDraw.Count == 0)
