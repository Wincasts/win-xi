-- Installed family names, not font filenames. Independent of the texture DLL.
local ffi = require('ffi');
local jit = require('jit');
ffi.cdef[[
    typedef struct {
        int32_t height, width, escapement, orientation, weight;
        uint8_t italic, underline, strikeout, charset;
        uint8_t outPrecision, clipPrecision, quality, pitchAndFamily;
        uint16_t face[32];
    } zoneinfo_logfont_w;
    typedef int (__stdcall *zoneinfo_font_enum_proc)(const zoneinfo_logfont_w*, const void*, uint32_t, intptr_t);
    void* __stdcall GetDC(void*);
    int __stdcall ReleaseDC(void*, void*);
    int __stdcall EnumFontFamiliesExW(void*, zoneinfo_logfont_w*, zoneinfo_font_enum_proc, intptr_t, uint32_t);
    int __stdcall WideCharToMultiByte(uint32_t, uint32_t, const uint16_t*, int, char*, int, const char*, void*);
]];
local families, problem;
local module = {};

local function enumerate()
    local user = ffi.load('user32');
    local gdi = ffi.load('gdi32');
    local kernel = ffi.load('kernel32');
    local dc = user.GetDC(nil);
    assert(dc ~= nil, 'Cannot acquire a Windows font enumeration context');
    local callback;
    local ok, result = pcall(function ()
        local names, seen = {}, {};
        local filter = ffi.new('zoneinfo_logfont_w');
        filter.charset = 1; -- DEFAULT_CHARSET: enumerate all installed charsets
        local buffer = ffi.new('char[128]');
        local callbackError;
        callback = ffi.cast('zoneinfo_font_enum_proc', function (font)
            -- Never let a Lua error escape through a native callback.
            local success, err = pcall(function ()
                local count = kernel.WideCharToMultiByte(65001, 0, font.face, -1, buffer, 128, nil, nil);
                assert(count > 0, 'Cannot decode an installed font family');
                local name = ffi.string(buffer, count - 1);
                local key = name:lower();
                -- Windows exposes vertical variants as @Family; these are not
                -- appropriate for horizontal banners. Multiple styles share a family.
                if (name ~= '' and name:sub(1, 1) ~= '@' and not seen[key]) then
                    seen[key] = true;
                    names[#names + 1] = name;
                end
            end);
            if (not success) then callbackError = err; return 0; end
            return 1;
        end);
        gdi.EnumFontFamiliesExW(dc, filter, callback, 0, 0);
        assert(callbackError == nil, callbackError);
        assert(#names > 0, 'Windows returned no installed font families');
        table.sort(names, function (a, b) return a:lower() < b:lower(); end);
        return names;
    end);
    if (callback ~= nil) then callback:free(); end
    user.ReleaseDC(nil, dc);
    if (not ok) then error(result); end
    return result;
end
-- LuaJIT must not compile a native call that can re-enter Lua through a callback.
jit.off(enumerate, true);

function module.List()
    if (families == nil) then
        local ok, result = pcall(enumerate);
        families = ok and result or {};
        problem = not ok and tostring(result) or nil;
    end
    return families, problem;
end

return module;
