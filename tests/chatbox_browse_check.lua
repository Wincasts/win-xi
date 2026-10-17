-- The expanded log's cursor, view and senders, and the steps of opening a tell. No FFXI needed.
package.path = 'addons/chatbox/?.lua;' .. package.path
local model = require('log')
local browse = require('browse')

-- moving: within the messages there are
local state = browse.New()
assert(state.selected == 1 and not browse.Move(state, -1, 5), 'newest at first; nothing newer')
assert(browse.Move(state, 1, 5) and state.selected == 2, 'up: one older')
for _ = 1, 10 do browse.Move(state, 1, 5) end
assert(state.selected == 5, 'no further than the oldest')

-- the view follows: ten messages of one row each, four rows shown
local log = model.New()
for i = 1, 10 do model.Add(log, 'line ' .. i, 1) end
local function tail(newer) return model.Tail(log, 1000, 'f', 12, function(s) return #s end, 4, nil, newer) end
browse.Reset(state)
local rows = browse.Show(state, tail)
assert(state.newer == 0 and rows[4].text == 'line 10' and rows[4].index == 1, 'the newest at the foot')
state.selected = 4; rows = browse.Show(state, tail)
assert(state.newer == 0 and rows[1].index == 4, 'still in view: the view stays')
state.selected = 6; rows = browse.Show(state, tail)
assert(state.newer == 2 and rows[1].index == 6 and rows[1].text == 'line 5', 'older than the view: it goes back just enough')
state.selected = 2; rows = browse.Show(state, tail)
assert(state.newer == 1 and rows[4].index == 2, 'newer than the view: it comes forward')
assert(model.Count(log) == 10 and model.Count(log, { [1] = true }) == 10 and model.Count(log, { [5] = true }) == 0, 'counted by channel')

-- a long message: the view goes back until its first row shows
model.Clear(log)
model.Add(log, 'old', 1); model.Add(log, string.rep('w', 30), 1); model.Add(log, 'new', 1)
local function narrow(newer) return model.Tail(log, 10, 'f', 12, function(s) return #s end, 3, nil, newer) end
state.selected = 2; state.newer = 0
rows = browse.Show(state, narrow)
local first = false
for _, row in ipairs(rows) do if row.index == 2 and row.first then first = true end end
assert(first and state.newer == 1, 'a wrapped message is shown from its first row')

-- senders, as each channel writes its lines
local stamp = model.Stamp
assert(browse.Sender('Hamelin : gather at that camp', 9, stamp) == 'Hamelin', 'say')
assert(browse.Sender('[23:55:59] Hamelin : hi', 10, stamp) == 'Hamelin', 'shout, after a timestamp')
assert(browse.Sender('Sevortharte[Kazham]: 31 WHM LFG EXP', 11, stamp) == 'Sevortharte', 'yell, with its zone')
assert(browse.Sender('Melyon>> are you there', 12, stamp) == 'Melyon', 'a tell heard')
assert(browse.Sender('>>Melyon : yes', 4, stamp) == 'Melyon', 'a tell sent: to whom')
assert(browse.Sender('(Blankets) pull', 13, stamp) == 'Blankets', 'party')
assert(browse.Sender('<Sky> hello', 14, stamp) == 'Sky' and browse.Sender('<Sky> hello', 214, stamp) == 'Sky', 'linkshells')
assert(browse.Sender('{Mee} unity', 212, stamp) == 'Mee', 'unity')
assert(browse.Sender('[Addons] Loaded addon: chatbox', 1, stamp) == nil, 'no player behind it')
assert(browse.Sender('The Goblin hits you.', 28, stamp) == nil, 'battle: no sender')
assert(browse.Sender('Win : my own line', 9, stamp, 'Win') == nil, 'the player\'s own line: nobody to tell')

-- opening a tell: cancel out of the full log and the selection, Enter, then the text
local plan = browse.Tell('Melyon', 0)
assert(browse.Step(plan, 0, { expanded = true }) == 'cancel', 'cancel out of the full log')
assert(browse.Step(plan, 0.05, { expanded = true }) == nil, 'a moment between presses')
assert(browse.Step(plan, 0.2, { selected = true }) == 'cancel', 'cancel the chat\'s selection')
assert(browse.Step(plan, 0.4, { enterDown = true }) == nil, 'the player\'s Enter still down: wait, or the line would be sent')
assert(browse.Step(plan, 0.45, {}) == 'enter', 'then Enter, to open the input')
assert(browse.Step(plan, 0.5, { inputOpen = true, enterDown = true }) == nil, 'open, Enter still down: the text waits')
assert(browse.Step(plan, 0.55, { inputOpen = true }) == 'text', 'Enter up: the text set, nothing sent')
plan = browse.Tell('Melyon', 0)
assert(browse.Step(plan, 2, { expanded = true }) == 'failed', 'given up after a while')
print('Chatbox browse: cursor within the messages, the view following, wrapped messages, senders by channel, opening a tell passed')
