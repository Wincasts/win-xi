-- Standalone: luajit tests/chatbubbles_colors_check.lua
package.path = './addons/chatbubbles/?.lua;' .. package.path;
local colors = require('colors');
local function hex(text) return (text:gsub('%x%x', function(pair) return string.char(tonumber(pair, 16)); end)); end
local function le(value, count)
    local out = {};
    for i = 1, count do out[i], value = string.char(value % 256), math.floor(value / 256); end
    return table.concat(out);
end
-- Lookup instruction sequences observed in the client. These independently
-- verify scan patterns, operand offsets and repeated table-address validation.
local modeCode = hex('A188E8320333C96685C07418668B542404663BC27411668B048D8CE83203416685C075ED');
local paletteCode = hex('A0E8E6320333C984C0741A0FBF54240425FF0000003BC274128A04CDF0E632034184C075EBB880808080C38B04CDECE63203C3');
local mapping = {
    {1,0x54},{9,0x54},{2,0x55},{10,0x55},{3,0x6C},{11,0x6C},
    {4,0x56},{12,0x56},{5,0x57},{13,0x57},{6,0x58},{14,0x58},{7,0x59},{15,0x59},
    {211,0x6D},{212,0x6D},{213,0x6E},{214,0x6E},{220,0x70},{222,0x71},
    {150,0x5B},{151,0x5B},{152,0x5B},
};
local values = { [0x54]=0x80808080, [0x55]=0x80402010, [0x6C]=0x80706050,
    [0x56]=0x80602040, [0x57]=0x80102030, [0x58]=0x80103050, [0x59]=0x80504020,
    [0x6D]=0x80406080, [0x6E]=0x80204060, [0x70]=0x80101020, [0x71]=0x80201010, [0x5B]=0x80408010 };
local tables, now, available, readable = {}, 10, true, true;
local scans = 0;
local function rebuild()
    local rows = {};
    for _, row in ipairs(mapping) do rows[#rows + 1] = le(row[1], 2) .. string.char(row[2], 1); end
    local modeTable = table.concat(rows);
    tables[0x332E888] = modeTable .. ('\0'):rep(1024 - #modeTable);
    rows = {};
    for slot, value in pairs(values) do rows[#rows + 1] = le(slot, 4) .. le(value, 4); end
    rows[#rows + 1] = le(0x54, 4) .. le(0, 4); -- first duplicate slot wins, as in FFXI
    local palette = table.concat(rows);
    tables[0x332E6E8] = palette .. ('\0'):rep(1024 - #palette);
end
rebuild();
local function matches(pattern, bytes)
    local result = {};
    for at = 1, #pattern, 2 do
        local pair = pattern:sub(at, at + 1);
        result[#result + 1] = pair == '??' and '.' or (hex(pair):gsub('([%^%$%(%)%%%.%[%]%*%+%-%?])', '%%%1'));
    end
    return bytes:match('^' .. table.concat(result) .. '$') ~= nil;
end
ashita = { memory = { find = function(module, _, signature)
    assert(module == 'FFXiMain.dll'); scans = scans + 1;
    if not available then return 0; end
    if matches(signature, modeCode) then return 0x30E9CD0; end
    if matches(signature, paletteCode) then return 0x30E9D00; end
    return 0;
end } };
package.loaded['winxi.safe_memory'] = { read = function(address, length)
    if address == 0x30E9CD0 then assert(length == 36); return modeCode; end
    if address == 0x30E9D00 then assert(length == 51); return paletteCode; end
    assert(length == 1024 and tables[address], 'unexpected pointer read');
    return readable and tables[address] or nil;
end };
local oldClock = os.clock;
os.clock = function() return now; end;
assert(colors.Get(9) == 0xFFFFFFFF);
assert(colors.Get(12) == 0xFFC04080);
assert(colors.Get(13) == 0xFF204060);
assert(colors.Get(151) == 0xFF80FF20);
assert(colors.Get(255) == nil and colors.Problem() == nil);
local appearance = { gameTextColors = { true }, text = {1,1,1,0.5} };
assert(colors.ForMessage({ mode = 3 }, appearance) == 0x80C04080); -- incoming tell log mode 12
assert(colors.ForMessage({ mode = 3, outgoing = true }, appearance) == 0x80C04080); -- outgoing tell log mode 4
assert(colors.ForMessage({ mode = 151, npc = true }, appearance) == 0x8080FF20);
for _, mode in ipairs({0,1,3,4,5,8,13,14,15,16,26,27,28,33,34,35}) do
    assert(colors.ForMessage({mode=mode}, appearance));
end
assert(colors.ForMessage({ mode=27, outgoing=true }, appearance) == colors.Get(213, 0.5));
assert(colors.ForMessage({ mode=150 }, appearance) == nil); -- packet/text namespaces stay separate
assert(colors.ForMessage({ mode=0, synthetic=true }, appearance) == nil);
assert(colors.ForMessage({}, appearance) == nil); -- target test
appearance.gameTextColors[1] = false;
local before = scans;
assert(colors.ForMessage({mode=0}, appearance) == nil and scans == before);
appearance.gameTextColors[1] = true;
values[0x54] = 0x80102030; rebuild();
assert(colors.Get(9) == 0xFFFFFFFF); -- quarter-second cache
now = now + 0.3;
assert(colors.Get(9) == 0xFF204060); -- live config edits update existing bubbles
readable = false; now = now + 0.3;
assert(colors.Get(9) == nil and colors.Problem():find('not readable', 1, true));
readable = true; now = now + 0.3;
assert(colors.Get(9) == 0xFF204060 and colors.Problem() == nil);
colors.Reset(); available = false;
assert(colors.Get(9) == nil and colors.Problem():find('signatures', 1, true));
before = scans; assert(colors.Get(9) == nil and scans == before); -- retry throttle
available = true; now = now + 1.1;
assert(colors.Get(9) == 0xFF204060);
colors.Reset();
-- Match the opcode wildcard pattern but reject inconsistent repeated operands.
modeCode = modeCode:sub(1,26) .. le(0x332E999,4) .. modeCode:sub(31);
assert(colors.Get(9) == nil and colors.Problem():find('validation', 1, true));
os.clock = oldClock;
print('chatbubbles colors: live tables, signatures, RGB scaling, channels, NPCs, opacity, refresh and safe fallback passed');
