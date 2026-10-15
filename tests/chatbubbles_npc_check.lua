-- Standalone: luajit tests/chatbubbles_npc_check.lua
package.path = './addons/chatbubbles/?.lua;' .. package.path;
local npc = require('npc');
local a = { index = 10, id = 0x0100000A, name = 'Porter_Moogle' };
local b = { index = 11, id = 0x0100000B, name = 'Porter Moogle' };
local other = { index = 12, id = 0x0100000C, name = 'Shantotto' };
local actors = { [10] = a, [11] = b, [12] = other };
local function lookup(actor)
    local value = actors[actor.index];
    if (value and value.id == actor.id) then return value; end
end
local function packet(indexOffset, actor)
    local bytes = {};
    for i = 1, indexOffset + 2 do bytes[i] = 0; end
    local function put(at, value, count)
        for i = 1, count do bytes[at + i], value = value % 256, math.floor(value / 256); end
    end
    put(4, actor.id, 4); put(indexOffset, actor.index, 2);
    local result = {};
    for i, byte in ipairs(bytes) do result[i] = string.char(byte); end
    return table.concat(result);
end
assert(npc.CleanRaw('\30\127Porter Moogle : Hello!\127\49\3') == 'Porter Moogle : Hello!');
assert(npc.CleanRaw('Hello\127\48') == 'Hello');
assert(npc.CleanRaw('Hi\127\49') == 'Hi');
assert(npc.CleanRaw('Hi\127') == 'Hi');
local state = npc.New();
local message = assert(npc.Resolve(state, 'Porter Moogle : Hello!', 151, 10, { a }, lookup));
assert(message.text == 'Hello!' and message.id == a.id and message.index == a.index);
assert(npc.ForName(state, { EntityIndex = 10, ServerId = a.id }) == message);
assert(npc.ForName(state, { EntityIndex = 10, ServerId = b.id }) == nil);
assert(npc.Resolve(state, 'Porter Moogle : Hello!', 151, 10.1, { a }, lookup) == nil); -- duplicate
assert(npc.Resolve(state, 'More dialogue.', 150, 12, {}, lookup).index == a.index);
assert(npc.Resolve(state, 'Unknown actor : Hello', 151, 12, { a }, lookup) == nil);
assert(npc.Resolve(state, 'Unattributed narration', 142, 12, {}, lookup) == nil);
assert(npc.Resolve(state, 'Late continuation', 151, 23, {}, lookup) == nil);
assert(npc.Prune(state, 30) == 0);
assert(npc.Resolve(npc.New(), 'Porter Moogle : Hello', 151, 10, { a, b }, lookup) == nil);
for id, offset in pairs({ [0x027] = 8, [0x036] = 8, [0x02A] = 24, [0x043] = 8 }) do
    state = npc.New();
    npc.Packet(state, id, packet(offset, b), 10, lookup);
    message = assert(npc.Resolve(state, 'Porter Moogle : Hello', 151, 10, { a, b }, lookup));
    assert(message.id == b.id); -- direct identity disambiguates identical names
    assert(#state.pending == 0);
    state = npc.New();
    npc.Packet(state, id, packet(offset, a), 10, lookup);
    message = assert(npc.Resolve(state, 'No speaker prefix', 151, 10, {}, lookup));
    assert(message.index == a.index and message.text == 'No speaker prefix');
    state = npc.New();
    npc.Packet(state, id, packet(offset, a), 10, lookup);
    assert(npc.Resolve(state, 'Expired direct context', 151, 11.1, {}, lookup) == nil);
end
for id, offset in pairs({ [0x032] = 8, [0x033] = 8, [0x034] = 40 }) do
    state = npc.New();
    npc.Packet(state, id, packet(offset, a), 10, lookup);
    assert(npc.Resolve(state, 'Narration without speaker', 151, 11, {}, lookup) == nil);
    assert(npc.Resolve(state, 'Shantotto : Another speaker', 151, 11, {}, lookup) == nil);
    message = assert(npc.Resolve(state, 'Porter Moogle : Event dialogue', 151, 11, {}, lookup));
    assert(message.index == a.index);
    npc.Packet(state, 0x052, '', 12, lookup);
    assert(npc.Resolve(state, 'After event', 151, 12, {}, lookup) == nil);
end
state = npc.New();
npc.Packet(state, 0x036, packet(8, a), 10, function() return false; end);
assert(#state.pending == 0);
npc.Packet(state, 0x036, packet(8, { index = 10, id = 123 }), 10, function() return true; end);
assert(#state.pending == 0); -- player-targeted system packet cannot seed NPC context
npc.Packet(state, 0x036, 'short', 10, lookup);
assert(#state.pending == 0);
npc.Packet(state, 0x036, packet(8, a), 10, lookup);
npc.Packet(state, 0x036, packet(8, b), 10, lookup);
assert(npc.Resolve(state, 'Ambiguous unnamed line', 151, 10, {}, lookup) == nil);
print('chatbubbles NPC: dialogue channels, speaker attribution, packet layouts, duplicates, identity and safe fallbacks passed');
