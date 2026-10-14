-- Independent Windows waveOut voices. No native callbacks enter Lua: completion is polled.
local M = {}
local ffi, winmm
local initialized, problem = false, nil
local voices = {}
local limit, maxBytes = 8, 16 * 1024 * 1024

function M.Available()
    if not initialized then
        initialized = true
        local ok, err = pcall(function()
            ffi = require('ffi')
            assert(ffi.os == 'Windows', 'Windows is required')
            ffi.cdef[[
                typedef struct { uint16_t tag, channels; uint32_t rate, bytesPerSecond;
                    uint16_t alignment, bits, extra; } TriggerWaveFormat;
                typedef struct TriggerWaveHeader { char *data; uint32_t length, recorded;
                    uintptr_t user; uint32_t flags, loops; struct TriggerWaveHeader *next;
                    uintptr_t reserved; } TriggerWaveHeader;
                uint32_t __stdcall waveOutOpen(void **, uint32_t, const TriggerWaveFormat *, uintptr_t, uintptr_t, uint32_t);
                uint32_t __stdcall waveOutPrepareHeader(void *, TriggerWaveHeader *, uint32_t);
                uint32_t __stdcall waveOutWrite(void *, TriggerWaveHeader *, uint32_t);
                uint32_t __stdcall waveOutUnprepareHeader(void *, TriggerWaveHeader *, uint32_t);
                uint32_t __stdcall waveOutReset(void *);
                uint32_t __stdcall waveOutClose(void *);
            ]]
            winmm = ffi.load('winmm')
        end)
        if not ok then problem = tostring(err) end
    end
    return problem == nil, problem
end

local function release(v, stop)
    if stop and winmm.waveOutReset(v.handle) ~= 0 then return false end
    if v.prepared then
        if winmm.waveOutUnprepareHeader(v.handle, v.header, ffi.sizeof(v.header)) ~= 0 then return false end
        v.prepared = false
    end
    return winmm.waveOutClose(v.handle) == 0
end

function M.Poll()
    for i = #voices, 1, -1 do
        local v = voices[i]
        if v.header[0].flags % 2 == 1 and release(v, false) then table.remove(voices, i) end
    end
end

function M.Stop()
    for i = #voices, 1, -1 do
        if release(voices[i], true) then table.remove(voices, i) end
    end
end

local function number(s, at, count)
    local n = 0
    for i = count - 1, 0, -1 do n = n * 256 + s:byte(at + i) end
    return n
end

-- Keep parsing bounded, and only accept ordinary integer PCM WAVs. The existing Ashita
-- backend remains available for custom files using other encodings (turn overlap off).
local function load(path)
    local f = io.open(path, 'rb')
    if not f then return nil, 'cannot open WAV' end
    local s = f:read(maxBytes + 1)
    f:close()
    if not s or #s > maxBytes or #s < 12 or s:sub(1, 4) ~= 'RIFF' or s:sub(9, 12) ~= 'WAVE' then
        return nil, 'invalid WAV or file exceeds 16 MiB'
    end
    local ending = number(s, 5, 4) + 8
    if ending > #s then return nil, 'truncated WAV' end
    local at, fmt, data = 13, nil, nil
    while at + 7 <= ending do
        local kind, size = s:sub(at, at + 3), number(s, at + 4, 4)
        if at + 7 + size > ending then return nil, 'truncated WAV chunk' end
        if kind == 'fmt ' and size >= 16 then fmt = s:sub(at + 8, at + 23) end
        if kind == 'data' then data = s:sub(at + 8, at + 7 + size) end
        at = at + 8 + size + size % 2
    end
    if not fmt or not data or #data == 0 then return nil, 'missing WAV format or samples' end
    local tag, channels, rate = number(fmt, 1, 2), number(fmt, 3, 2), number(fmt, 5, 4)
    local bytes, alignment, bits = number(fmt, 9, 4), number(fmt, 13, 2), number(fmt, 15, 2)
    if tag ~= 1 or channels < 1 or channels > 2 or rate == 0
        or (bits ~= 8 and bits ~= 16 and bits ~= 24 and bits ~= 32)
        or alignment ~= channels * bits / 8 or bytes ~= rate * alignment or #data % alignment ~= 0 then
        return nil, 'unsupported WAV (use mono/stereo integer PCM)'
    end
    return { channels = channels, rate = rate, bytes = bytes, alignment = alignment, bits = bits, data = data }
end

function M.Play(path)
    local available, err = M.Available()
    if not available then return false, err end
    M.Poll()
    if #voices >= limit then return false, 'eight sounds are already playing' end
    local wav
    wav, err = load(path)
    if not wav then return false, err end
    local format = ffi.new('TriggerWaveFormat', { 1, wav.channels, wav.rate, wav.bytes, wav.alignment, wav.bits, 0 })
    local handle = ffi.new('void *[1]')
    local result = winmm.waveOutOpen(handle, 0xFFFFFFFF, format, 0, 0, 0)
    if result ~= 0 then return false, 'waveOutOpen error ' .. result end
    local buffer = ffi.new('char[?]', #wav.data)
    ffi.copy(buffer, wav.data, #wav.data)
    local header = ffi.new('TriggerWaveHeader[1]')
    header[0].data, header[0].length = buffer, #wav.data
    local v = { handle = handle[0], header = header, buffer = buffer, prepared = false }
    -- Hold all native memory until the driver releases it, including on failure.
    voices[#voices + 1] = v
    result = winmm.waveOutPrepareHeader(v.handle, header, ffi.sizeof(header))
    if result == 0 then
        v.prepared = true
        result = winmm.waveOutWrite(v.handle, header, ffi.sizeof(header))
    end
    if result ~= 0 then
        if release(v, true) then table.remove(voices) end
        return false, 'waveOut playback error ' .. result
    end
    return true
end

return M
