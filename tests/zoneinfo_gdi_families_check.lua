-- Font enumeration without Windows: exercise callbacks, UTF-8 names and cleanup.
package.path = 'addons/zoneinfo/?.lua;' .. package.path
local ffi = require('ffi')
local families = require('gdi_families')
local acquired, released, enumerated = 0, 0, 0
local originalLoad = ffi.load
ffi.load = function(name)
    if name == 'user32' then return {
        GetDC = function() acquired = acquired + 1; return ffi.cast('void*', 1) end,
        ReleaseDC = function() released = released + 1 end,
    } end
    if name == 'kernel32' then return {
        WideCharToMultiByte = function(codepage, _, face, _, buffer)
            assert(codepage == 65001)
            local out = {}
            for i = 0, 31 do
                if face[i] == 0 then break end
                out[#out + 1] = face[i] == 0x416 and '\208\150' or string.char(face[i])
            end
            local str = table.concat(out)
            ffi.copy(buffer, str .. '\0', #str + 1)
            return #str + 1
        end,
    } end
    if name == 'gdi32' then return {
        EnumFontFamiliesExW = function(_, filter, callback)
            enumerated = enumerated + 1
            assert(filter.charset == 1)
            for _, name in ipairs({ 'Verdana', 'Arial', 'arial', '@Arial', 'Tahoma', '' }) do
                local font = ffi.new('zoneinfo_logfont_w')
                for i = 1, #name do font.face[i - 1] = name:byte(i) end
                assert(callback(font, nil, 0, 0) == 1)
            end
            local font = ffi.new('zoneinfo_logfont_w')
            font.face[0] = 0x416
            assert(callback(font, nil, 0, 0) == 1)
            return 1
        end,
    } end
    error('unexpected native library: ' .. name)
end
local list, err = families.List()
ffi.load = originalLoad
assert(err == nil and table.concat(list, ',') == 'Arial,Tahoma,Verdana,\208\150')
assert(families.List() == list and acquired == 1 and released == 1 and enumerated == 1)
print('Zoneinfo GDI families: sorted, deduplicated, vertical variants excluded, UTF-8, cached and context released\ttrue')
