-- Packet/state/layout logic kept independent of Ashita for the proof-of-concept tests.
local modes = require('modes');
local M = {};
local function enabled(mode, allows)
    return allows and allows(mode) or (allows == nil and mode == 0);
end

local function cstring(data, first, last)
    return data:sub(first, last):match('^[^%z]*');
end

-- Incoming 0x017: mode at 0x04, speaker at 0x08, message at 0x17 (zero-based).
function M.Parse(data, allows)
    if (type(data) ~= 'string' or #data < 24) then return nil; end
    local mode = data:byte(5);
    if (not enabled(mode, allows)) then return nil; end
    local speaker = cstring(data, 9, 23);
    local message = cstring(data, 24, math.min(#data, 1024));
    if (speaker == '' or message == '') then return nil; end
    return speaker:lower(), message, mode;
end

-- Outgoing 0x0B5: mode at 0x04, message at 0x06. 0x0B6 is the tell layout.
-- Own chat need not echo back.
function M.ParseOutgoing(data, allows, packetId)
    if (type(data) ~= 'string') then return nil; end
    local tell = packetId == 0x0B6;
    local first = tell and 22 or 7; -- tell: recipient at 0x06 (15 bytes), text at 0x15
    if (#data < first) then return nil; end
    local mode = tell and 3 or data:byte(5);
    if (not tell and not modes.Outgoing[mode]) then return nil; end
    if (not enabled(mode, allows)) then return nil; end
    local message = cstring(data, first, math.min(#data, 1024));
    if (message == '') then return nil; end
    return message, mode;
end

function M.New()
    return { messages = {} };
end

function M.Add(state, speaker, text, now, mode)
    if (text == '' or not text:find('%S')) then return; end
    -- One bubble per speaker; a new line replaces the old one and resets its lifetime.
    local message = { text = text, expires = now + 8, mode = mode or 0 };
    state.messages[speaker] = message;
    return message;
end

function M.Prune(state, now)
    local count = 0;
    for speaker, message in pairs(state.messages) do
        if (now >= message.expires) then state.messages[speaker] = nil;
        else count = count + 1; end
    end
    return count;
end

-- Wrap only at UTF-8 boundaries, including long words; prefer a space where possible.
-- Text and font are stable during each message, so the renderer caches this result.
function M.Wrap(text, maxWidth, measure)
    local lines, line, lastSpace = {}, '', nil;
    for character in text:gmatch('[%z\1-\127\194-\244][\128-\191]*') do
        while (line ~= '' and measure(line .. character) > maxWidth) do
            if (lastSpace) then
                lines[#lines + 1] = line:sub(1, lastSpace - 1);
                line = line:sub(lastSpace + 1);
            else
                lines[#lines + 1] = line;
                line = '';
            end
            lastSpace = nil;
            for at in line:gmatch('() ') do lastSpace = at; end
        end
        if (character ~= ' ' or line ~= '') then
            line = line .. character;
            if (character == ' ') then lastSpace = #line; end
        end
    end
    if (line ~= '') then lines[#lines + 1] = line; end
    return lines;
end

return M;
