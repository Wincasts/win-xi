-- Browsing the expanded log: a cursor moved message by message through what chatbox has kept, the view
-- going back with it, and the name to send a tell to from the message chosen. No Ashita dependency:
-- chatbox.lua feeds it the keys and buttons and does what it asks.
local M = {}

-- selected: the message the cursor is on, counting back from the newest (1). newer: how many of the
-- newest messages the view leaves out, so that the selected one is shown.
function M.New() return { selected = 1, newer = 0 } end
function M.Reset(state) state.selected, state.newer = 1, 0 end

-- Up (older, +1) or down (newer, -1), within the count of messages there are. Returns whether it moved.
function M.Move(state, step, count)
    local selected = math.max(1, math.min(math.max(1, count), state.selected + step))
    if selected == state.selected then return false end
    state.selected = selected
    return true
end

-- The view, moved only as far as needed for the selected message's first row to be in it: tail(newer)
-- gives the rows shown leaving out that many of the newest. Returns those rows.
function M.Show(state, tail)
    if state.newer >= state.selected then state.newer = state.selected - 1 end
    local rows = tail(state.newer)
    -- older than the view: go back a message at a time until its first row comes in (bounded)
    for _ = 1, 256 do
        local found = false
        for _, row in ipairs(rows) do
            if row.index == state.selected and row.first then found = true; break end
        end
        if found or state.newer >= state.selected - 1 then break end
        state.newer = state.newer + 1
        rows = tail(state.newer)
    end
    return rows
end

-- The name a message came from (or, sent by the player, went to), for a tell: as each channel writes
-- its lines, after any timestamp. nil for a line with no player behind it, or the player's own.
local senders = {
    [9] = '^(%a+)%s*:', [1] = '^(%a+)%s*:',            -- say: Name : words
    [10] = '^(%a+)%s*:', [2] = '^(%a+)%s*:',           -- shout
    [11] = '^(%a+)%[[^%]]*%]%s*:', [3] = '^(%a+)%[[^%]]*%]%s*:', -- yell: Name[Zone]: words
    [12] = '^(%a+)>>', [4] = '^>>(%a+)',               -- a tell heard (Name>> words), sent (>>Name : words)
    [13] = '^%((%a+)%)', [5] = '^%((%a+)%)',           -- party: (Name) words
    [14] = '^<(%a+)>', [6] = '^<(%a+)>', [205] = '^<(%a+)>', -- linkshell: <Name> words
    [214] = '^<(%a+)>', [213] = '^<(%a+)>', [217] = '^<(%a+)>',
    [212] = '^{(%a+)}', [211] = '^{(%a+)}',            -- unity: {Name} words
}
function M.Sender(text, mode, stamp, self)
    local pattern = senders[mode]
    if not pattern or type(text) ~= 'string' then return nil end
    local body = text
    local found = stamp and stamp(body)
    if found then body = body:sub(#found + 1) end
    local name = body:gsub('^%s+', ''):match(pattern)
    if not name or #name < 3 or #name > 15 then return nil end
    if self and name:lower() == tostring(self):lower() then return nil end
    return name
end

-- Opening a tell is done as the player would: cancel until the full log and the chat's selection are
-- both gone, then Enter to open the input, then the input's text set, and nothing sent: the line is
-- left for the player to finish. Each step waits on the game, and the whole is given up after a while.
-- Step(plan, now, game) is called each frame with what the game shows (game.expanded, game.selected,
-- game.inputOpen) and whether an Enter is down (game.enterDown: the player's, or the one pressed for
-- them). An Enter still down as the input opens would send the line, so Enter is pressed only once none
-- is down, and the text set only once it is up again. Returns the key to press this frame ('cancel' or
-- 'enter'), 'text' when the text is to be set, 'failed', or nil to wait.
M.Timeout, M.Gap = 1.5, 0.15 -- seconds: the whole, and between presses
function M.Tell(name, now) return { name = name, began = now, pressed = -1 } end
function M.Step(plan, now, game)
    if now - plan.began > M.Timeout then return 'failed' end
    if game.inputOpen then return not game.enterDown and 'text' or nil end
    if now - plan.pressed < M.Gap then return nil end
    if game.expanded or game.selected then plan.pressed = now; return 'cancel' end
    if game.enterDown then return nil end
    plan.pressed = now
    return 'enter'
end

return M
