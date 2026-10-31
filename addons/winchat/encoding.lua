-- FFXI chat is CP932, not UTF-8. Auto-translate is expanded before cleaning/transcoding.
local ffi = require('ffi')
local log = require('log')
ffi.cdef[[
    int __stdcall MultiByteToWideChar(unsigned int, unsigned long, const char*, int, unsigned short*, int);
    int __stdcall WideCharToMultiByte(unsigned int, unsigned long, const unsigned short*, int, char*, int, const char*, int*);
]]
local kernel = ffi.load('kernel32')
local M = {}
local function Transcode(text)
    local count = kernel.MultiByteToWideChar(932, 0, text, #text, nil, 0)
    if count <= 0 then return nil end
    local wide = ffi.new('unsigned short[?]', count)
    if kernel.MultiByteToWideChar(932, 0, text, #text, wide, count) ~= count then return nil end
    local size = kernel.WideCharToMultiByte(65001, 0, wide, count, nil, 0, nil, nil)
    if size <= 0 then return nil end
    local output = ffi.new('char[?]', size)
    if kernel.WideCharToMultiByte(65001, 0, wide, count, output, size, nil, nil) ~= size then return nil end
    return ffi.string(output, size)
end
function M.Decode(raw, preserveSpaces, preserveColors)
    if raw == '' then return '', '', {} end -- nothing to expand, transcode or colour; the game is not asked
    local expanded = AshitaCore:GetChatManager():ParseAutoTranslate(raw, true)
    if type(expanded) ~= 'string' or #expanded > log.MaxBytes * 4 then return nil end
    local output, spans, length, bank, slot = {}, {}, 0, nil, nil
    for _, run in ipairs(log.Clean(expanded, true, preserveColors)) do
        if type(run) == 'table' and run.bank then
            bank, slot = run.bank, run.slot
            if slot == 1 then bank, slot = nil, nil end -- return to the line's default colour
        else
            local text = type(run) == 'table' and run.text or Transcode(run)
            if not text then return nil end
            output[#output + 1] = text
            if bank and #text > 0 then spans[#spans + 1] = {first=length+1,last=length+#text,bank=bank,slot=slot} end
            length = length + #text
        end
    end
    local decoded = table.concat(output)
    if not preserveSpaces then
        local leading = #(decoded:match('^%s*') or '')
        decoded = decoded:match('^%s*(.-)%s*$')
        spans = require('richtext').Slice(spans, leading + 1, #decoded)
    end
    -- Expanded CP932 bytes remain the second result for diagnostics; spans use UTF-8 byte offsets.
    return decoded, expanded, spans
end
return M
