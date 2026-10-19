-- Standalone: luajit tests/chatbubbles_check.lua (from the repository root).
package.path = './addons/chatbubbles/?.lua;' .. package.path;
local bubbles = require('bubbles');
local function packet(mode, name, text)
    return ('\0'):rep(4) .. string.char(mode) .. ('\0'):rep(3)
        .. name .. ('\0'):rep(15 - #name) .. text .. '\0';
end
local function outgoing(mode, text)
    return ('\0'):rep(4) .. string.char(mode) .. '\0' .. text .. '\0';
end
assert(bubbles.ParseOutgoing(outgoing(0, 'Own say')) == 'Own say');
assert(bubbles.ParseOutgoing(outgoing(4, 'Party')) == nil);
assert(bubbles.ParseOutgoing('') == nil);
assert(bubbles.ParseOutgoing(outgoing(0, '')) == nil);
local speaker, text = bubbles.Parse(packet(0, 'Tester', 'Hello!'));
assert(speaker == 'tester' and text == 'Hello!');
for _, mode in ipairs({ 1, 3, 4, 5, 8, 26 }) do
    assert(bubbles.Parse(packet(mode, 'Tester', 'Not say')) == nil);
end
assert(bubbles.Parse('') == nil);
assert(bubbles.Parse(packet(0, '', 'Hello')) == nil);
assert(bubbles.Parse(packet(0, 'Tester', '')) == nil);
assert(select(2, bubbles.Parse(packet(0, 'Tester', 'hello\0padding'))) == 'hello');

local state = bubbles.New();
bubbles.Add(state, 'tester', 'First', 10);
bubbles.Add(state, 'tester', 'Second', 11);
assert(state.messages.tester.text == 'Second');
assert(bubbles.Prune(state, 18.5) == 1);
assert(bubbles.Prune(state, 19) == 0);
local function measure(s) return #s; end
assert(table.concat(bubbles.Wrap('hello world', 6, measure), '|') == 'hello|world');
assert(table.concat(bubbles.Wrap('abcdefgh', 3, measure), '|') == 'abc|def|gh');
local japanese = 'こんにちは';
local lines = bubbles.Wrap(japanese, 6, measure);
assert(table.concat(lines) == japanese and #lines == 3 and #lines[1] == 6);
for _, line in ipairs(bubbles.Wrap('a abcdefgh ijk', 5, measure)) do assert(#line <= 5); end

-- Load the real event handlers against a tiny read-only namehook / ImGui mock.
local events, draws, now, hook, records = {}, {}, 100, true, {};
local lastMessage;
addon = {};
local targetIndex, targetId, subtarget = 0, 4321, 0;
local npcActors = {};
AshitaCore = { GetMemoryManager = function()
    return {
        GetParty = function() return { GetMemberName = function() return 'Tester'; end }; end,
        GetTarget = function() return {
            GetIsSubTargetActive = function() return subtarget; end,
            GetTargetIndex = function(_, active) assert(active == subtarget); return targetIndex; end,
        }; end,
        GetEntity = function() return {
            GetServerId = function(_, index)
                if npcActors[index] then return npcActors[index].id; end
                assert(index == targetIndex); return targetId;
            end,
            GetName = function(_, index) return npcActors[index] and npcActors[index].name or ''; end,
        }; end,
    };
end };
package.loaded.common = {};
package.loaded.encoding = { Decode = function(s, dialogue) return dialogue and require('npc').CleanRaw(s) or s; end };
ashita = { events = { register = function(event, _, callback) events[event] = callback; end } };
local pushedFonts = {};
local font = {};
local draw = {};
function draw:AddRectFilled() draws[#draws + 1] = 'bubble'; end
function draw:AddRectFilledMultiColor() draws[#draws + 1] = 'parchment'; end
function draw:AddImage() end
function draw:AddTriangleFilled() end
function draw:AddText(_, _, s) draws[#draws + 1] = s; end
package.loaded.imgui = {
    GetIO = function() return { DisplaySize = { x = 800, y = 600 } }; end,
    GetFont = function() return font; end,
    GetFontSize = function() return 16; end,
    GetTextLineHeight = function() return 16; end,
    CalcTextSize = function(s) return #s * 8, 16; end,
    GetBackgroundDrawList = function() return draw; end,
    GetColorU32 = function(color) return color; end,
    PushFont = function(font, size) pushedFonts[#pushedFonts + 1] = { font = font, size = size }; end,
    PopFont = function() pushedFonts[#pushedFonts + 1] = 'pop'; end,
};
package.loaded['winxi.text'] = { Packed = function(list, _, _, _, words) list:AddText(nil, nil, words); end };
local eventHappening = false;
package.loaded['winxi.game'] = { IsEventHappening = function() return eventHappening; end };
package.loaded['winxi.fonts'] = { Get = function(file) return file ~= '' and { file = file } or nil; end, Files = function() return {}; end };
package.loaded['winxi.nameplates'] = {
    Category = { Player = 8 },
    Hook = function() return hook and {} or nil; end,
    Problem = function() if not hook then return 'Missing namehook'; end end,
    Each = function() return ipairs(records); end,
    Name = function(record) return record.name; end,
    Screen = function(record) return record.x, record.y; end,
    -- No Claim/Override: bubble rendering must not change name visibility.
};
package.loaded.world = {
    Begin = function() return 1; end,
    Problem = function() return nil; end,
    Clear = function() end,
    Draw = function(_, message)
        lastMessage = message;
        draws[#draws + 1] = 'bubble';
        draws[#draws + 1] = message.text;
        return true;
    end,
};
local allowed = { [0] = true };
local globallyEnabled = true;
local npcAllowed = { [150] = true, [151] = true };
local toggles = 0;
package.loaded.config = {
    preview = { false },
    options = { appearance = { background = { 1, 1, 1, 1 }, text = { 0, 0, 0, 1 } } },
    Allows = function(mode) return allowed[mode] == true; end,
    AllowsNpc = function(mode) return npcAllowed[mode] == true; end,
    Enabled = function() return globallyEnabled; end,
    SetEnabled = function(value) globallyEnabled = value; end,
    Toggle = function() toggles = toggles + 1; end,
    Draw = function() end,
};
local originalClock = os.clock;
os.clock = function() return now; end;
dofile('addons/chatbubbles/chatbubbles.lua');
local function say(name, message, mode)
    events.packet_in({ id = 0x017, data = packet(mode or 0, name, message) });
end
local function frame()
    draws = {};
    events.d3d_present();
    return table.concat(draws, '|');
end
local function command(action, ...)
    local args = { '/chatbubbles', action, ... };
    local e = { command = { args = function() return args; end } };
    events.command(e);
    assert(e.blocked);
end
records = { { name = 'Tester', Category = 1, x = 400, y = 300 } };
-- Own speech is drawn without any incoming packet or server echo.
events.packet_out({ id = 0x0B5, data = outgoing(0, 'Own say') });
assert(frame() == 'bubble|Own say');
assert(lastMessage.outgoing == true);
events.packet_out({ id = 0x0B5, data = outgoing(4, 'Party must not appear') });
assert(frame() == 'bubble|Own say');
events.packet_out({ id = 0x0B5, data = outgoing(0, 'Blocked'), blocked = true });
assert(frame() == 'bubble|Own say');
say('Tester', 'Hello!');
assert(frame() == 'bubble|Hello!'); -- incoming echo replaces, rather than duplicates
assert(not lastMessage.outgoing);
say('Tester', 'Replacement');
assert(frame() == 'bubble|Replacement');
say('Tester', 'Private', 3);
assert(frame() == 'bubble|Replacement');
records[1].x = nil;
assert(frame() == '');
records[1].x = 400;
records[1].Category = 64; -- NPC with same name is not a valid speaker
assert(frame() == '');
records[1].Category = 8;
assert(frame() == 'bubble|Replacement');
now = 109;
assert(frame() == '');
say('Tester', 'Zoning');
events.packet_in({ id = 0x00B });
assert(frame() == '');
say('Tester', 'Plugin unloaded');
hook = false;
assert(frame() == '');
hook = true;
assert(frame() == '');
command('off');
say('Tester', 'Disabled');
command('on');
assert(frame() == '');
say('Tester', 'Clear me');
command('clear');
assert(frame() == '');
command('test');
assert(frame():find('chatbubbles: overlay drawing works', 1, true));
assert(frame():find('Test speech bubble', 1, true));
command('clear');
assert(frame() == '');
-- Local target test works on NPCs/monsters without enabling real NPC speech.
command('target'); -- no target
assert(frame() == '');
targetIndex, subtarget = 77, 1;
records = {
    { name = 'Goblin', EntityIndex = 76, ServerId = 4320, Category = 128, x = 300, y = 300 },
    { name = 'Goblin', EntityIndex = 77, ServerId = 4321, Category = 128, x = 400, y = 300 },
};
command('target', 'Hello', 'from', 'your', 'target!');
assert(frame() == 'bubble|Hello from your target!'); -- exactly one same-named entity
records[2].ServerId = 9999;
assert(frame() == ''); -- reused entity index cannot inherit test speech
records[2].ServerId = 4321;
records[2].Category = 64;
assert(frame() == 'bubble|Hello from your target!'); -- noncombat NPC works too
now = now + 8;
assert(frame() == '');
command('target');
assert(frame() == 'bubble|Test speech bubble');
command('clear');
assert(frame() == '');
say('Goblin', 'Not an actual player');
assert(frame() == ''); -- target testing must not widen real chat's category filter
command('target');
events.packet_in({ id = 0x00A });
assert(frame() == '');
command('target');
command('off');
assert(frame() == '');
command('target'); -- explicit test re-enables the feature
assert(frame() == 'bubble|Test speech bubble');
command('clear');
targetId = 0;
command('target');
assert(frame() == '');
-- Mode switches apply to both capture and currently active messages.
records = { { name = 'Tester', Category = 1, x = 400, y = 300 } };
allowed[4] = true;
say('Tester', 'Party bubble', 4);
assert(frame() == 'bubble|Party bubble');
allowed[4] = false;
assert(frame() == '');
say('Tester', 'Disabled party', 4);
assert(frame() == '');
allowed[4] = true;
events.packet_out({ id = 0x0B5, data = outgoing(4, 'Outgoing party') });
assert(frame() == 'bubble|Outgoing party');
allowed[3] = true;
local tell = ('\0'):rep(6) .. 'Recipient' .. ('\0'):rep(6) .. 'Outgoing tell' .. '\0';
events.packet_out({ id = 0x0B6, data = tell });
assert(frame() == 'bubble|Outgoing tell');
allowed[3] = false;
assert(frame() == '');
command(nil);
command('settings');
assert(toggles == 2);
command('clear');
-- Real NPC text uses the separate text channel controls, not player packet IDs.
npcActors[77] = { id = 0x0100004D, name = 'Moogle' };
records = { { name = 'Moogle', EntityIndex = 77, ServerId = npcActors[77].id, Category = 64, x = 400, y = 300 } };
local textEvent = { mode = 0x100 + 151, message = 'Moogle : Welcome!', blocked = true };
events.text_in(textEvent);
assert(frame() == 'bubble|Welcome!');
assert(textEvent.blocked and textEvent.message == 'Moogle : Welcome!'); -- read-only, works with chat replacements
npcAllowed[151] = false;
assert(frame() == '');
events.text_in({ mode = 151, message = 'Moogle : Disabled NPC line' });
npcAllowed[151] = true;
assert(frame() == 'bubble|Welcome!'); -- disabled line never replaced the previous message
records[1].ServerId = npcActors[77].id + 1;
assert(frame() == '');
records[1].ServerId = npcActors[77].id;
command('clear');
events.text_in({ mode = 151, message = 'Unknown speaker : Never pin to current target' });
assert(frame() == '');
local function le(value, count)
    local bytes = {};
    for i = 1, count do bytes[i], value = string.char(value % 256), math.floor(value / 256); end
    return table.concat(bytes);
end
-- A direct 0x036 message supplies the identity when the resolved text has no prefix.
events.packet_in({ id = 0x036, data = ('\0'):rep(4) .. le(npcActors[77].id, 4) .. le(77, 2) .. '\0\0' });
events.text_in({ mode = 151, message = 'A line without a name.' });
assert(frame() == 'bubble|A line without a name.');
events.packet_in({ id = 0x00A });
assert(frame() == '');
events.text_in({ mode = 151, message = 'A stale continuation after zoning.' });
assert(frame() == '');
-- Draw On Screen: the bubble is imgui's, over everything, from the name's place on the screen; the
-- world gets an empty frame; one that would not fit above the name is not drawn
local appearance = package.loaded.config.options.appearance;
appearance.onScreen = { true };
records = { { name = 'Tester', Category = 1, x = 400, y = 300 } };
say('Tester', 'On the screen');
assert(frame() == 'bubble|On the screen');
records[1].y = 20;
assert(frame() == '');
records[1].y = 300;
-- the parchment skin on the screen: the gradient and the art in place of the rectangle
local skin = require('skin');
skin.LoadBorder = function() return 0x7001; end;
skin.LoadLines = function() return 0x7002; end;
appearance.skin, appearance.skinTop, appearance.skinBottom = { 'parchment' }, { 0.9, 0.8, 0.7, 1 }, { 0.7, 0.6, 0.4, 1 };
assert(frame() == 'parchment|On the screen');
appearance.skin = { 'plain' };
appearance.onScreen = { false };
assert(frame() == 'bubble|On the screen'); -- the world's again
-- the bubbles' own font and size are pushed round the frame, and popped after; none when neither is set
appearance.font, appearance.fontSize = { 'arial.ttf' }, { 0 };
pushedFonts = {};
frame();
assert(#pushedFonts == 2 and pushedFonts[1].font.file == 'arial.ttf' and pushedFonts[1].size == 16 and pushedFonts[2] == 'pop');
appearance.font, appearance.fontSize = { '' }, { 20 };
pushedFonts = {};
frame();
assert(#pushedFonts == 2 and pushedFonts[1].font == nil and pushedFonts[1].size == 20);
appearance.fontSize = { 0 };
pushedFonts = {};
frame();
assert(#pushedFonts == 0, 'the font everything else is in, at its size: nothing pushed');
-- an NPC's line with the game's prompt escape waits for a key: with the arrow on and an event running
-- the bubble stays and says so; without the event, or the escape, it does not
command('clear');
npcActors[77] = { id = 0x0100004D, name = 'Moogle' };
records = { { name = 'Moogle', EntityIndex = 77, ServerId = npcActors[77].id, Category = 64, x = 400, y = 300 } };
appearance.arrow = { true };
eventHappening = true;
events.text_in({ mode = 151, message = 'Moogle : Press a key.\127\49\3' });
assert(frame() == 'bubble|Press a key.' and lastMessage.waiting == true and lastMessage.prompt == true);
now = now + 20;
assert(frame() == 'bubble|Press a key.', 'it stays while the game waits');
eventHappening = false;
assert(frame() == 'bubble|Press a key.' and lastMessage.waiting == false, 'the event over: no longer waiting');
now = now + 2;
assert(frame() == '', 'and gone soon after');
eventHappening = true;
events.text_in({ mode = 151, message = 'Moogle : No prompt here.' });
assert(frame() == 'bubble|No prompt here.' and lastMessage.waiting == false and lastMessage.prompt == false);
appearance.arrow = { false };
events.text_in({ mode = 151, message = 'Moogle : Arrow off.\127\49\3' });
assert(frame() == 'bubble|Arrow off.' and lastMessage.waiting == false);
eventHappening = false;
command('clear');
-- Preview: a sample over the player's own name while it is on, the arrow with it if that is on,
-- whatever the channels allow; gone a second after it is turned off
records = { { name = 'Tester', Category = 1, x = 400, y = 300 } };
allowed[0] = false;
package.loaded.config.preview[1] = true;
appearance.arrow = { true };
assert(frame():find('bubble|The quick brown fox', 1, true) and lastMessage.waiting == true and lastMessage.preview == true);
appearance.arrow = { false };
now = now + 30;
assert(frame():find('bubble|The quick brown fox', 1, true) and lastMessage.waiting == false, 'kept while the preview is on');
package.loaded.config.preview[1] = false;
now = now + 2;
assert(frame() == '', 'gone after');
allowed[0] = true;
command('clear');
command('clear');
os.clock = originalClock;
print('chatbubbles: packet filtering, expiry, UTF-8 wrapping, anchoring, on-screen drawing, fonts, the click-through arrow, the preview, coexistence, zoning and commands passed');
