-- winxi.gamekeys against a keys block of its own (uihook's keys ABI 1): found by its magic, the keys named written as
-- bits with the commit after, bit 31 among them, and nothing kept without uihook or with an old one.
package.path = 'addons/libs/?.lua;' .. package.path
local ffi = require('ffi')
local gamekeys = require('winxi.gamekeys')
local loaded, base, found = true, 0x10000000, true
local block = ffi.new('uihook_keys_t')
ffi.copy(block.Magic, 'UIHOOK-KEYS')
block.Version, block.Size, block.Frame, block.Supported = 1, ffi.sizeof('uihook_keys_t'), 500, 1
local address = tonumber(ffi.cast('intptr_t', ffi.cast('void*', block)))
AshitaCore = { GetPluginManager = function() return { IsLoaded = function(_, name) return loaded and name == 'uihook' end } end }
ashita = { memory = {
    get_base = function() return base end,
    find = function(_, _, pattern) assert(pattern == '5549484F4F4B2D4B4559530000000000'); return found and address or 0 end,
} }
local clock = 10
os.clock = function() return clock end
local keys = gamekeys.new()
assert(keys.Ready(), 'found by its magic: ready')
assert(keys.Hold({ [13] = true, [9] = true, [31] = true, [255] = true, [27] = false, [300] = true, [-1] = true, [1.5] = true }))
assert(block.Hold[0] == 2 ^ 13 + 2 ^ 9 + 2 ^ 31, 'Enter, Tab and bit 31 (VK 31) in the first word: ' .. tostring(block.Hold[0]))
assert(block.Hold[7] == 2 ^ 31, 'VK 255, bit 31 of the last word')
for i = 1, 6 do assert(block.Hold[i] == 0, 'nothing else: word ' .. i) end
assert(block.HoldFrame == 500, 'committed with the block\'s frame')
block.Frame = 501
assert(keys.Hold({}) and block.Hold[0] == 0 and block.Hold[7] == 0 and block.HoldFrame == 501, 'none named: every word cleared, committed')
assert(keys.Hold(nil) and block.Hold[0] == 0, 'nil as none')
block.Supported = 0
assert(not keys.Ready() and not keys.Hold({ [13] = true }) and keys.Status():find('input handler', 1, true), 'the game\'s handler not taken: nothing')
block.Supported = 1
loaded = false
assert(not keys.Ready() and keys.Status():find('Load uihook', 1, true), 'uihook not loaded: nothing')
loaded = true
block.Version = 2; clock = clock + 2
assert(not keys.Ready() and keys.Status():find('ABI mismatch', 1, true), 'another ABI: nothing')
block.Version = 1; clock = clock + 2
assert(keys.Ready(), 'the matching ABI again: ready')
found = false; base = 0x20000000; clock = clock + 2
assert(not keys.Ready() and keys.Status():find('Update uihook', 1, true), 'an older uihook with no keys block: nothing, and why')
print('winxi gamekeys: found by magic, bits and commit, bit 31, no uihook, old uihook and ABI mismatch passed')
