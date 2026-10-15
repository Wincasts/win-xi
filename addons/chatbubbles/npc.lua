-- NPC text is resolved by the client (text_in), not carried as plain 0x017 chat.
-- Keep attribution conservative: never use the player's arbitrary current target.
local M = {};
local packets = {
    [0x027] = { index = 0x08, direct = true },
    [0x036] = { index = 0x08, direct = true },
    [0x02A] = { index = 0x18, direct = true },
    [0x043] = { index = 0x08, direct = true },
    [0x032] = { index = 0x08 }, [0x033] = { index = 0x08 }, [0x034] = { index = 0x28 },
};
local function number(data, offset, count)
    local value = 0;
    for i = count - 1, 0, -1 do value = value * 256 + data:byte(offset + i + 1); end
    return value;
end
function M.New() return { pending = {}, messages = {} }; end
function M.Packet(state, id, data, now, valid)
    if (id == 0x052) then state.context, state.lastSpeaker, state.pending = nil, nil, {}; return; end
    local layout = packets[id];
    if (not layout or type(data) ~= 'string' or #data < layout.index + 2) then return; end
    local actor = { id = number(data, 4, 4), index = number(data, layout.index, 2), at = now };
    -- A new message source invalidates a previous speaker continuation, even
    -- when this packet's actor is no longer loaded or is a player/system target.
    state.lastSpeaker = nil;
    -- Exclude player-targeted system/fishing messages. NPC IDs have a nonzero high byte.
    if (actor.id < 0x01000000 or actor.index <= 0 or actor.index >= 0x900 or not valid(actor)) then
        state.pending = {};
        if (not layout.direct) then state.context = nil; end
        return;
    end
    if (layout.direct) then
        state.pending[#state.pending + 1] = actor;
        if (#state.pending > 16) then table.remove(state.pending, 1); end
    else
        state.context, state.lastSpeaker, state.pending = actor, nil, {};
    end
end
-- Remove FFXI palette and timed-dialogue/prompt escapes before SJIS decoding.
-- A lone DEL followed by '1' must not leak a visible '1' into the bubble.
function M.CleanRaw(text)
    return text:gsub('[\30\31].', ''):gsub('\127[\49-\55][\1-\6]', ''):gsub('\127.', ''):gsub('\127$', '');
end
local function same(a, b) return a and b and a.index == b.index and a.id == b.id; end

function M.Resolve(state, text, mode, now, candidates, lookup)
    for i = #state.pending, 1, -1 do
        if (now - state.pending[i].at > 1) then table.remove(state.pending, i); end
    end
    if (state.context and now - state.context.at > 120) then state.context = nil; end
    local list, seen = {}, {};
    local function add(actor)
        if (actor and actor.name and not seen[actor.index]) then
            list[#list + 1], seen[actor.index] = actor, true;
        end
    end
    for _, actor in ipairs(candidates) do add(actor); end
    for _, actor in ipairs(state.pending) do add(lookup(actor)); end
    if (state.context) then add(lookup(state.context)); end
    local speaker, body = text:match('^%s*(.-)%s*:%s*(.+)$');
    if (not speaker) then speaker, body = text:match('^%s*(.-)%s*：%s*(.+)$'); end
    local chosen;
    if (speaker) then
        local matches = {};
        for _, actor in ipairs(list) do
            if (actor.name:lower():gsub('_', ' ') == speaker:lower():gsub('_', ' ')) then matches[#matches + 1] = actor; end
        end
        -- Direct packet identity disambiguates multiple same-named NPCs.
        for _, pending in ipairs(state.pending) do
            for _, actor in ipairs(matches) do if (same(actor, pending)) then chosen = actor; break; end end
            if (chosen) then break; end
        end
        if (not chosen and #matches == 1) then chosen = matches[1]; end
        if (not chosen and state.context) then
            for _, actor in ipairs(matches) do if (same(actor, state.context)) then chosen = actor; break; end end
        end
        -- Never pin another cutscene speaker's named line to the event initiator.
        if (not chosen) then
            state.lastSpeaker = nil;
            return nil, 'unidentified or ambiguous NPC speaker';
        end
    else
        body = text;
        -- A direct message packet identifies an otherwise unnamed line.
        if (#state.pending == 1) then chosen = lookup(state.pending[1]); end
        if (#state.pending > 1) then return nil, 'ambiguous unnamed NPC line'; end
        -- Only ordinary dialogue may continue a recently identified speaker.
        if (not chosen and (mode == 150 or mode == 151) and state.lastSpeaker
                and now - state.lastSpeaker.at <= 10) then chosen = lookup(state.lastSpeaker); end
        if (not chosen) then return nil, 'NPC line has no attributable speaker'; end
    end
    for i, actor in ipairs(state.pending) do
        if (same(actor, chosen)) then table.remove(state.pending, i); break; end
    end
    if (not body:find('%S')) then return nil, 'empty NPC dialogue'; end
    state.lastSpeaker = { index = chosen.index, id = chosen.id, at = now };
    local previous = state.messages[chosen.index];
    -- Some client paths repeat the same resolved line (including prompt channels).
    if (previous and previous.id == chosen.id and previous.text == body and now - previous.at < 0.5) then
        previous.mode = mode; -- keep channel filtering current without extending lifetime
        return nil, 'duplicate NPC line';
    end
    local message = { text = body, mode = mode, npc = true, index = chosen.index, id = chosen.id, at = now, expires = now + 8 };
    state.messages[chosen.index] = message;
    return message;
end
function M.Prune(state, now)
    local count = 0;
    for index, message in pairs(state.messages) do
        if (now >= message.expires) then state.messages[index] = nil; else count = count + 1; end
    end
    return count;
end
function M.ForName(state, name)
    local message = state.messages[tonumber(name.EntityIndex)];
    if (message and message.id == name.ServerId) then return message; end
end
return M;
