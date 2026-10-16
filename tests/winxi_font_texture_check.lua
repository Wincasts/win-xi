-- Run: luajit tests/winxi_font_texture_check.lua
-- winxi.fonts.Texture: imgui's font texture from the fields of the atlas's texture data and its
-- reference first, then their methods, each asked apart, so that the methods throwing (imgui's
-- assertion, as Ashita reports it) does not keep the others from being asked; and when none answers,
-- what each said. fonts.TextureDetail reads each apart.
package.path = 'addons/libs/?.lua;' .. package.path
local data, reference = { id = 0 }, { id = 0 }
local function throwing(t, key) return setmetatable({}, { __index = function(_, k)
    if k == key then if t.fieldFails then error('C++ exception', 0) end return t.field or 0 end
end }) end
local texData = throwing(data, 'TexID')
texData.Width, texData.Height, texData.Status, texData.UniqueID = 512, 256, 0, 7
texData.GetTexID = function() if data.fails then error('C++ exception', 0) end return data.id end
local texRef = throwing(reference, '_TexID')
texRef.GetTexID = function() if reference.fails then error('C++ exception', 0) end return reference.id end
local atlas = { TexData = texData, TexRef = texRef, TexList = { texData } }
local font = { ContainerAtlas = atlas }
package.preload['imgui'] = function() return { GetFont = function() return font end } end
package.preload['winxi.theme'] = function() return { For = function() return '' end } end
local fonts = require('winxi.fonts')

local function check(label, ok)
    print(label, ok)
    assert(ok, label)
end

local function texture()
    local id, why, route = fonts.Texture()
    return id, why, route
end

data.field, data.fails, reference.fails = 0x1111, true, true
local id, why, route = texture()
check('the methods throwing: the data\'s field all the same', id == 0x1111 and why == nil and route == 'texture data field')
data.field, reference.field = 0, 0x2222
id, why, route = texture()
check('the data\'s field 0: the reference\'s field', id == 0x2222 and route == 'reference field')
data.fieldFails, reference.fieldFails, reference.field = true, true, 0
data.fails, data.id, reference.fails = false, 0x1234, true
id, why, route = texture()
check('the fields unreadable, the reference throwing: the data\'s method', id == 0x1234 and route == 'texture data')
data.id, reference.fails, reference.id = 0, false, 0x5678
id, why, route = texture()
check('the data with none yet: the reference\'s method', id == 0x5678 and route == 'reference')
data.fieldFails, reference.fieldFails = false, false
data.field, reference.field, data.id, reference.id = 0x1111, 0x2222, 0x1234, 0x5678
check('all: the data\'s field, asked first', texture() == 0x1111)
data.field, reference.field, data.id, reference.id = 0, 0, 0, 0
id, why = texture()
check('none has one: nil, and every answer said', id == nil and why == 'texture data field id 0; reference field id 0; texture data id 0; reference id 0')
data.fieldFails, reference.fieldFails, data.fails, reference.fails = true, true, true, true
id, why = texture()
check('all throw: nil, and every error said', id == nil and why == 'texture data field error: C++ exception; reference field error: C++ exception; texture data error: C++ exception; reference error: C++ exception')

local detail = fonts.TextureDetail()
local said = {}
for _, line in ipairs(detail) do said[line[1]] = line[2] end
check('detail: the data read, though its id throws', said['texture data'] == 'unique id 7, 512 x 256, status 0')
check('detail: each id apart', said['texture data field id']:find('unreadable') and said['reference id']:find('unreadable'))
check('detail: the list, its texture\'s id unreadable', said['textures in the list']:find('^1: %[1%] unreadable') ~= nil)
data.fieldFails, data.field = false, 0x1111
said = {}
for _, line in ipairs(fonts.TextureDetail()) do said[line[1]] = line[2] end
check('detail: the list with its texture\'s id', said['textures in the list'] == '1: [1] 512 x 256 status 0 id 4369')

font = nil
id, why = texture()
check('no font: nil, and said', id == nil and why:find('no font atlas') ~= nil)
check('no font: detail says so', fonts.TextureDetail()[1][2]:find('unreadable') ~= nil)
