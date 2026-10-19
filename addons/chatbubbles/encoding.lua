-- FFXI packets contain Windows-932, whereas ImGui expects UTF-8.
local ffi = require('ffi');
ffi.cdef[[
    int __stdcall MultiByteToWideChar(unsigned int, unsigned long, const char*, int, unsigned short*, int);
    int __stdcall WideCharToMultiByte(unsigned int, unsigned long, const unsigned short*, int, char*, int, const char*, int*);
]];
-- Windows' own converter; without it (a check on another system) the text is left as it is
local loaded, kernel = pcall(ffi.load, 'kernel32');
if (not loaded) then kernel = nil; end
local M = {};

function M.Decode(text, dialogue)
    -- Expand auto-translate before removing FFXI's color/control codes.
    text = AshitaCore:GetChatManager():ParseAutoTranslate(text, true);
    if (dialogue) then text = require('npc').CleanRaw(text); end
    text = text:gsub('[\30\31].', ''):gsub('[%z\1-\31\127]', ' ');
    if (kernel == nil) then return text:gsub('%s+', ' '):match('^%s*(.-)%s*$'); end
    local count = kernel.MultiByteToWideChar(932, 0, text, #text, nil, 0);
    if (count <= 0) then return ''; end
    local wide = ffi.new('unsigned short[?]', count);
    if (kernel.MultiByteToWideChar(932, 0, text, #text, wide, count) ~= count) then return ''; end
    local size = kernel.WideCharToMultiByte(65001, 0, wide, count, nil, 0, nil, nil);
    if (size <= 0) then return ''; end
    local utf8 = ffi.new('char[?]', size);
    if (kernel.WideCharToMultiByte(65001, 0, wide, count, utf8, size, nil, nil) ~= size) then return ''; end
    return ffi.string(utf8, size):gsub('%s+', ' '):match('^%s*(.-)%s*$');
end

return M;
