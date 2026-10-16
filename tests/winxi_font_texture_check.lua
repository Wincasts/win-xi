-- Run: luajit tests/winxi_font_texture_check.lua
-- winxi.fonts.Texture: the plugins' mark for imgui's font texture, and imgui's unique id for which
-- texture it is, while imgui has it ready; the texture's id is never asked for (Ashita cannot hand it
-- to Lua once it is above 2 GB, and every way of asking throws). fonts.TextureDetail says what imgui
-- says of it.
package.path = 'addons/libs/?.lua;' .. package.path
local asked = 0
local data = { UniqueID = 2, Status = 0, Width = 512, Height = 256 }
setmetatable(data, { __index = function(_, key)
    asked = asked + 1
    error('C++ exception', 0) -- TexID, GetTexID, GetTexRef: as on the tester's machine
end })
local font = { ContainerAtlas = { TexData = data } }
package.preload['imgui'] = function() return { GetFont = function() return font end } end
package.preload['winxi.theme'] = function() return { For = function() return '' end } end
local fonts = require('winxi.fonts')

local function check(label, ok)
    print(label, ok)
    assert(ok, label)
end

local id, which = fonts.Texture()
check('ready: the mark, and which texture', id == fonts.TextureMark and id == 1 and which == 2)
check('the texture\'s id never asked for', asked == 0)
data.Status = 3
check('letters being added to it: still ready', fonts.Texture() == 1)
data.Status, data.UniqueID = 0, 7
id, which = fonts.Texture()
check('made again: the same mark, another texture', id == 1 and which == 7)
data.Status = 2
id, which = fonts.Texture()
check('not made yet: nil, and said', id == nil and which == 'imgui\'s font texture is not ready: status 2')
data.Status = 0
check('detail', fonts.TextureDetail() == 'unique id 7, 512 x 256, status 0')
font = nil
id, which = fonts.Texture()
check('no font: nil, and said', id == nil and which:find('could not be read') ~= nil)
check('no font: detail says so', fonts.TextureDetail():find('^unreadable') ~= nil)
check('still never asked for', asked == 0)
