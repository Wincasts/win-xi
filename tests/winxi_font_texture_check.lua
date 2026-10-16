-- Run: luajit tests/winxi_font_texture_check.lua
-- winxi.fonts.Texture: imgui's font texture from the atlas's texture data first, then its reference,
-- each asked apart, so that the reference throwing (imgui's assertion, as Ashita reports it) does not
-- keep the data from being asked; and when neither answers, what each said.
package.path = 'addons/libs/?.lua;' .. package.path
local data, reference = { id = 0 }, { id = 0 }
local atlas = {
    TexData = { GetTexID = function() if data.fails then error('C++ exception', 0) end return data.id end },
    TexRef = { GetTexID = function() if reference.fails then error('C++ exception', 0) end return reference.id end },
}
local font = { ContainerAtlas = atlas }
package.preload['imgui'] = function() return { GetFont = function() return font end } end
package.preload['winxi.theme'] = function() return { For = function() return '' end } end
local fonts = require('winxi.fonts')

local function check(label, ok)
    print(label, ok)
    assert(ok, label)
end

data.id, reference.fails = 0x1234, true
check('the reference throwing: the data\'s texture all the same', fonts.Texture() == 0x1234)
data.id, reference.fails, reference.id = 0, false, 0x5678
check('the data with none yet: the reference\'s', fonts.Texture() == 0x5678)
data.id, reference.id = 0x1234, 0x5678
check('both: the data\'s, asked first', fonts.Texture() == 0x1234)
data.id, reference.id = 0, 0
local id, why = fonts.Texture()
check('neither has one: nil, and both answers said', id == nil and why == 'texture data id 0; reference id 0')
data.fails, reference.fails = true, true
id, why = fonts.Texture()
check('both throw: nil, and both errors said', id == nil and why == 'texture data error: C++ exception; reference error: C++ exception')
font = nil
id, why = fonts.Texture()
check('no font: nil, and said', id == nil and why:find('no font atlas') ~= nil)
