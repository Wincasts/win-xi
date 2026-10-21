-- Assertion-based puppet correctness, lifecycle, and update-budget checks.
-- luajit tests/harness.lua puppet addons/puppet/puppet.lua tests/puppet_regression_check.lua
local tp = require('tp')
local burden = require('burden')
local predict = require('predict')
local tracker = require('tracker')
local packets = require('winxi.packets')
local gameUI = require('winxi.game')
local imgui = require('imgui')
local count = 0
local function check(ok, message)
    assert(ok, message)
    count = count + 1
end
local function near(a, b) return a ~= nil and math.abs(a - b) < 0.001 end

-- Elapsed time without gains must lower, then expire, a TP estimate.
tp.Clear(); tp.Sample(100, 0); tp.Sample(160, 6)
check(near(tp.Rate(6), 10), 'TP gain rate')
check(near(tp.Rate(12), 5), 'stalls count in rate denominator')
check(tp.Rate(16) == nil and tp.Until(1000, 16) == nil, 'stale TP rate expires')
tp.Sample(160, 200)
check(tp.Rate(200) == nil, 'sampling unchanged TP cannot revive a stale rate')
tp.Sample(220, 201)
check(tp.Rate(201) == nil, 'a late gain does not resurrect an ancient window')
tp.Sample(280, 207)
check(near(tp.Rate(207), 120 / 7), 'new window recovers')
tp.Sample(0, 208)
check(tp.Rate(208) == nil, 'TP expenditure resets estimate')
tp.Sample(1000, 212)
check(tp.Until(1000, 212) == 0, 'already enough TP')
tp.Clear()
tp.Sample(100, 0); tp.Sample(200, 4); tp.Burst(4)
tp.Sample(200, 4.1); tp.Sample(800, 4.2); tp.Sample(800, 5)
check(tp.Rate(6) == nil, 'delayed attachment TP is not counted as ordinary gain')
tp.Sample(860, 11)
check(near(tp.Rate(11), 10), 'normal TP rate recovers after a burst')
tp.Clear()

local plain = { frame = 0x20, attachments = {} }
local sink = { frame = 0x20, attachments = { [162] = true } }
local function maneuver(chance, at)
    burden.Action({ category = 6, param = 141, targets = { { actions = { { param = chance } } } } }, plain, at)
end
burden.Clear(); burden.Spawned(0)
check(burden.Get(1, plain, 2.9) == 35, 'burden waits for discrete tick')
maneuver(26, 2.9)
check(burden.Get(1, plain, 3) == 50, 'maneuver does not restart decay phase')
burden.Clear(); burden.Spawned(0)
check(burden.Get(1, plain, 6) == 33, 'ordinary decay')
burden.Update(sink, 6)
check(burden.Get(1, sink, 9) == 31, 'Heatsink affects future ticks only')
burden.Update(plain, 9)
check(burden.Get(1, plain, 12) == 30, 'removing Heatsink affects future ticks only')
burden.Clear(); burden.Spawned(0); maneuver(26, 0)
check(burden.Chance(1, plain, 0) == 42, 'learned maneuver cost')
burden.Clear(); burden.Spawned(0)
check(burden.Chance(1, plain, 0) == 30, 'clear forgets learned costs')
burden.Clear(); maneuver(0, 0)
local value, exact = burden.Get(1, plain, 0)
check(value == 25 and not exact, 'zero chance is an estimated bound')
burden.Clear(); burden.Spawned(0)
burden.Action({ category = 6, param = 309 }, plain, 0)
check(burden.Get(1, plain, 0) == 17, 'Cooldown rounds down integer burden')

local function chosen(rows)
    for _, row in ipairs(rows) do if row.ready then return row end end
end
local state = { head = 1, frame = 0x20, maneuvers = {}, enfeebles = { 'Dia' },
    weaponskill = 'Slapstick', tp = 0, mpp = 100, hpp = 100, masterHpp = 100,
    since = function() return nil end }
local rows = predict.Priority(state)
check(chosen(rows).state == 'unknown', 'unobserved magic is not ready')
check(chosen(rows).confidence == 'unknown', 'unknown cooldown confidence')
state.since = function() return 100 end
check(chosen(predict.Priority(state)).state == 'ready', 'observed expired timers can be ready')
state.mpp = 0
check(chosen(predict.Priority(state)) == nil, 'zero MP and no TP rate do not invent next WS')
state.mpp, state.silenced = 100, true
check(chosen(predict.Priority(state)) == nil, 'Silence blocks magic')
state.tp = 1000
check(chosen(predict.Priority(state)).name == 'WS', 'WS with enough TP')
state.amnesiac = true
check(chosen(predict.Priority(state)) == nil, 'Amnesia blocks WS')
state.amnesiac, state.tp, state.tpIn = false, 100, 8
local ws = chosen(predict.Priority(state))
check(ws.name == 'WS' and ws.estimate and ws.wait == 8, 'WS estimate requires a measured TP rate')
check(ws.detail.name == 'Slapstick' and ws.tp == 100, 'WS display retains selected skill and current TP below threshold')
local displayState = { head = predict.Heads.Stormwaker, frame = 0x23, maneuvers = { light = 1 },
    enfeebles = { 'Dia' }, masterHpp = 1, hpp = 100, mpp = 100,
    since = function(kind) return kind == 'heal' and 0 or 100 end }
for _, row in ipairs(predict.Priority(displayState)) do
    if row.name == 'Magic' then
        check(row.displayDetail.name == 'Heal', 'magic display follows head priority ignoring cooldown')
        check(row.displayWait > 0, 'magic display keeps selected spell cooldown')
    end
end

-- Live fixture: packet actions use the real addon event path, with parsing stubbed only here.
local game = { job = 18, buffs = {}, hp = 100, mpp = 100, tp = 100 }
local entities = {
    [1] = { ServerId = 1, PetTargetIndex = 2 },
    [2] = { ServerId = 2, HPPercent = 100 },
    [900] = { ServerId = 900, HPPercent = 100 },
}
function GetEntity(index) return entities[index] end
local player = {
    GetMainJob = function() return game.job end,
    GetLoginStatus = function() return 2 end,
    GetIsZoning = function() return 0 end,
    GetBuffs = function() return game.buffs end,
    GetPetMPPercent = function() return game.mpp end,
    GetPetTP = function() return game.tp end,
}
local party = {
    GetMemberTargetIndex = function() return 1 end,
    GetMemberServerId = function() return 1 end,
    GetMemberHPPercent = function() return game.hp end,
}
local core = AshitaCore
AshitaCore = setmetatable({ GetMemoryManager = function() return {
    GetPlayer = function() return player end, GetParty = function() return party end,
} end }, { __index = core })
struct.unpack = function(format, data, at)
    local value = 0
    for i = ({ B = 1, H = 2, I = 4 })[format] - 1, 0, -1 do value = value * 256 + (data:byte(at + i) or 0) end
    return value
end
local function number(value)
    return string.char(value % 256, math.floor(value / 256) % 256, math.floor(value / 65536) % 256, math.floor(value / 16777216) % 256)
end
local function fight(id)
    H.packetData(0x068, ('\0'):rep(8) .. number(1) .. ('\0'):rep(8) .. number(id))
end
local realParse, action = packets.inbound.action.parse
packets.inbound.action.parse = function() return action end
local function did(actor, category, param, result)
    action = { actor_id = actor, category = category, param = param,
        targets = { { id = 900, actions = { { param = result or 0, message = 0 } } } } }
    H.packetData(packets.inbound.action.id, '')
end
local o = H.options()
o.automaton.head, o.automaton.frame = 1, 0x20
o.automaton.magic, o.automaton.melee = 120, 120
H.resettle(); H.play(true); H.frames(1); fight(900)
local realPriority, updates, lastState = predict.Priority, 0, nil
predict.Priority = function(s) updates = updates + 1; lastState = s; return realPriority(s) end
H.frames(100)
check(updates > 0 and updates <= 27, 'decisions throttled to at most 10Hz, not every frame')

local said = {}
imgui.Text = function(s) said[#said + 1] = s end
imgui.TextDisabled = function(s) said[#said + 1] = s end
imgui.TextColored = function(_, s) said[#said + 1] = s end
local function shown()
    H.frames(5); said = {}; H.frames(1)
    return table.concat(said, ' ')
end
check(shown():find('Unknown', 1, true) ~= nil, 'UI discloses unseen cooldown')
check(not shown():find('Predicted:', 1, true), 'prediction heading removed')

game.buffs = { 6, 16 }; H.frames(5)
check(not lastState.silenced and not lastState.amnesiac, 'master ailments never gate pet actions')
game.buffs = {}
local debuffs = require('winxi.debuffs')
debuffs.Action({ actor_id = 900, category = 4, param = 59,
    targets = { { id = 2, actions = { { message = 236 } } } } })
H.frames(5)
check(lastState.silenced, 'observed pet Silence gates magic')
debuffs.Clear(); H.frames(5)

local realHidden = gameUI.IsHidden
gameUI.IsHidden = function() return true end
did(2, 8, 0x68776163, 23)
check(tracker.Since('magic') ~= nil, 'action tracked with UI hidden')
H.wait(4); game.tp = 200; H.frames(1)
check(tp.Rate() ~= nil, 'TP sampled with UI hidden')
entities[2].ServerId = 3
H.frames(1)
check(tracker.Since('magic') == nil and tp.Rate() == nil, 'hidden pet replacement resets old state')
did(3, 11, 1945)
check(tracker.Since('provoke') ~= nil, 'hidden replacement actions attributed to new pet')
check(burden.Get(1, plain) == nil, 'replacement cannot inherit burden')
gameUI.IsHidden = realHidden
fight(900); game.tp = 300; H.frames(1); H.wait(4); game.tp = 400; H.frames(1)
check(tp.Rate() ~= nil, 'combat rate recovered')
did(3, 11, 2745)
check(tp.Rate() == nil, 'Heat Capacitor invalidates attack-rate estimate')
fight(0)
check(tp.Rate() == nil, 'disengage clears TP estimate immediately')

-- Activation can arrive before the entity is visible; preserve its burden on reconciliation.
entities[1].PetTargetIndex = 0; H.frames(1)
did(1, 6, 136)
entities[1].PetTargetIndex = 2; H.frames(1)
check(burden.Get(1, plain) == 35, 'activation observation survives first pet appearance')
H.wait(6); H.frames(1)
check(burden.Get(1, plain) == 33, 'burden decays after activation')
H.packet(0x00A); H.frames(1)
check(burden.Get(1, plain) == 35, 'zone resets burden even with unchanged pet ID')
check(#tracker.History() == 0 and tp.Rate() == nil, 'zone resets history and TP')

-- Dummy mode with a live fighting pet must not be overwritten by live predictions.
local realCheckbox = imgui.Checkbox
local function dummy(on)
    imgui.Checkbox = function(id, value) if id == '##puppet.showDummy' then value[1] = on end return false end
    H.command('/puppet config'); H.frames(1); H.command('/puppet config')
    imgui.Checkbox = realCheckbox
end
fight(900); dummy(true)
local text = shown()
check(text:find('650 TP', 1, true) ~= nil and text:find('Dia II', 1, true) ~= nil, 'live pet does not overwrite dummy data')
dummy(false)
check(not shown():find('650 TP', 1, true), 'dummy data cleared when disabled')
local before = updates
o.showPriority[1], o.showDebug[1] = false, false
H.frames(20)
check(updates == before, 'disabled priority generation is skipped')
o.showBurden[1], o.alwaysShow[1] = false, true
check(shown():find('Nothing to show.', 1, true) ~= nil, 'both sections disabled has useful empty state')
o.showPriority[1], o.showBurden[1] = true, true

-- Bounded history keeps actual observations and immutable prediction context.
tracker.Clear()
local row = { name = 'Magic', detail = { name = 'Dia' }, confidence = 'unknown', reason = 'Cooldown not observed.' }
local maneuvers = { light = 1 }
tracker.Predict(row, maneuvers, 900)
row.detail.name, maneuvers.light = 'changed', 3
for _ = 1, 25 do did(3, 11, 1945) end
local history = tracker.History()
check(#history == 20, 'action history bounded')
check(history[1].prediction.name == 'Dia' and history[1].prediction.maneuvers.light == 1, 'history owns prediction snapshot')
check(history[1].target == 900 and history[1].id == 1945, 'history records observed target and action ID')
o.showDebug[1] = true
check(shown():find('Recent observed actions', 1, true) ~= nil, 'debug UI shows action history')
H.resettle()
check(#tracker.History() == 0 and tp.Rate() == nil and burden.Get(1, plain) == nil, 'settings/character reset clears runtime state')
H.packetData(0x044, '\0'); H.packetData(0x068, '\0')
check(true, 'short job and sync packets ignored safely')

-- Split layout: real themed windows, independent contents/positions, shared visibility rules.
local window = require('winxi.window')
local realFull, realPos = window.Full, imgui.GetWindowPos
local realNextPos, realText, realDisabled, realColored = imgui.SetNextWindowPos, imgui.Text, imgui.TextDisabled, imgui.TextColored
local active, windows, pendingPosition = nil, {}, nil
local moved = {
    ['winxi.puppet.burden'] = { 230, 140 },
    ['winxi.puppet.cooldowns'] = { 570, 330 },
    ['winxi.puppet'] = { 33, 44 },
}
imgui.SetNextWindowPos = function(pos, condition)
    pendingPosition = { pos[1], pos[2] }
    return realNextPos(pos, condition)
end
imgui.GetWindowPos = function()
    local pos = moved[active]
    if pos then return pos[1], pos[2] end
    return realPos()
end
local function capture(text)
    if active and windows[active] then
        local words = windows[active].words
        words[#words + 1] = text
    end
end
imgui.Text = function(text) capture(text); realText(text) end
imgui.TextDisabled = function(text) capture(text); realDisabled(text) end
imgui.TextColored = function(color, text) capture(text); realColored(color, text) end
window.Full = function(name, open, flags, draw, appearance)
    if not moved[name] then return realFull(name, open, flags, draw, appearance) end
    windows[name] = { words = {}, pos = pendingPosition,
        background = appearance and appearance.background, shadow = appearance and appearance.shadow }
    local previous = active
    active = name
    local drawn = realFull(name, open, flags, draw, appearance)
    active = previous
    return drawn
end
local function layout()
    H.frames(5); windows = {}; H.frames(1)
    return windows
end
local function words(name) return table.concat(windows[name].words, ' ') end
check(o.splitWindows[1] == false, 'combined layout remains default')
o.pos, o.burdenPos, o.cooldownPos = T{ 33, 44 }, nil, nil
H.resettle()
check(o.burdenPos[1] == 33 and o.burdenPos[2] == 44, 'burden position initially derives from combined position')
check(o.cooldownPos[1] == 33 and o.cooldownPos[2] == 104, 'cooldown position initially offset below burden')
o.fadeInOut[1], o.alwaysShow[1], o.transparent[1] = false, true, false
imgui.Checkbox = function(id, value)
    if id == '##puppet.splitWindows' then value[1] = true; return true end
    return false
end
H.command('/puppet config'); H.frames(1); H.command('/puppet config')
imgui.Checkbox = realCheckbox
check(o.splitWindows[1], 'settings checkbox enables split layout')
layout()
check(windows['winxi.puppet.burden'] and windows['winxi.puppet.cooldowns'] and not windows['winxi.puppet'], 'exactly two tracker windows, no combined duplicate')
check(not words('winxi.puppet.burden'):find('Predicted:', 1, true), 'burden window excludes cooldown rows')
check(not words('winxi.puppet.cooldowns'):find('Predicted:', 1, true), 'cooldown window excludes prediction heading')
check(not words('winxi.puppet.burden'):find('Automaton:', 1, true)
    and words('winxi.puppet.cooldowns'):find('Automaton:', 1, true), 'debug information belongs only to cooldown window')
check(o.burdenPos[1] == 230 and o.burdenPos[2] == 140 and o.cooldownPos[1] == 570 and o.cooldownPos[2] == 330, 'dragged split positions captured independently')
check(o.pos[1] == 33 and o.pos[2] == 44, 'split drawing preserves combined position')
layout()
check(windows['winxi.puppet.burden'].pos[1] == 230 and windows['winxi.puppet.cooldowns'].pos[1] == 570, 'saved positions reused independently')
o.showBurden[1] = false; layout()
check(not windows['winxi.puppet.burden'] and windows['winxi.puppet.cooldowns'], 'burden toggle hides only burden window')
o.showBurden[1], o.showPriority[1], o.showDebug[1] = true, false, false
layout()
check(windows['winxi.puppet.burden'] and not windows['winxi.puppet.cooldowns'], 'cooldown toggle hides only cooldown window')
o.showPriority[1], o.showDebug[1] = true, true
o.isVisible[1] = false; layout()
check(not next(windows), 'global visibility hides both split windows')
o.isVisible[1], o.alwaysShow[1] = true, false
fight(0); layout()
check(not next(windows), 'both split windows respect combat-only visibility')
fight(900); layout()
check(windows['winxi.puppet.burden'] and windows['winxi.puppet.cooldowns'], 'both split windows return during combat')
o.alwaysShow[1] = true
dummy(true); layout()
check(words('winxi.puppet.burden'):find('78', 1, true)
    and words('winxi.puppet.cooldowns'):find('650 TP', 1, true)
    and not words('winxi.puppet.cooldowns'):find('142s', 1, true), 'Puppet retains Magic and WS but no running pet cooldowns')
dummy(false)
o.transparent[1] = true; layout()
check(windows['winxi.puppet.burden'].background[4] == 0
    and windows['winxi.puppet.cooldowns'].background[4] == 0, 'both split windows support transparency')
o.transparent[1] = false; layout()
check(windows['winxi.puppet.burden'].shadow == nil and windows['winxi.puppet.cooldowns'].shadow == nil, 'opaque split windows restore theme shadows')
local realInput = imgui.InputInt2
imgui.InputInt2 = function(id, value)
    if id == '##puppet.burdenPosition' then value[1], value[2] = 410, 250; return true end
    return false
end
moved['winxi.puppet.burden'] = { 410, 250 }
H.command('/puppet config'); layout(); H.command('/puppet config')
imgui.InputInt2 = realInput
check(windows['winxi.puppet.burden'].pos[1] == 410 and windows['winxi.puppet.cooldowns'].pos[1] == 570, 'numeric burden position edits do not move cooldown window')
H.resettle(); layout()
check(windows['winxi.puppet.burden'].pos[1] == 410 and windows['winxi.puppet.cooldowns'].pos[1] == 570, 'split positions survive settings reload')
o.fadeInOut[1] = true; layout()
H.command('/puppet'); windows = {}; H.frames(1)
check(windows['winxi.puppet.burden'] and windows['winxi.puppet.cooldowns'], 'both split windows fade rather than disappear immediately')
layout()
check(not next(windows), 'both split windows finish fading out')
H.command('/puppet'); layout()
check(windows['winxi.puppet.burden'] and windows['winxi.puppet.cooldowns'], 'command restores both split windows')
o.fadeInOut[1] = false
-- Burden reserves complete slots and keeps its saved top-centre point during resizing.
local realBegin, realRectSize, realCalcSize = imgui.Begin, imgui.GetItemRectSize, imgui.CalcTextSize
local realDummy, realAvailable = imgui.Dummy, imgui.GetContentRegionAvail
local measuredWidth, lastPlaced, reservedWidth = 280, nil, nil
imgui.Begin = function(name, ...)
    if name == 'winxi.puppet.burden' then lastPlaced = { pendingPosition[1], pendingPosition[2] } end
    return realBegin(name, ...)
end
imgui.GetItemRectSize = function()
    if active == 'winxi.puppet.burden' then return measuredWidth, 40 end
    return realRectSize()
end
imgui.CalcTextSize = function(text) return text == '888' and 24 or #text * 7, 14 end
imgui.Dummy = function(size)
    if active == 'winxi.puppet.burden' and size[1] > 0 then reservedWidth = size[1] end
    return realDummy(size)
end
imgui.GetContentRegionAvail = function()
    if active == 'winxi.puppet.burden' then return 10000, 100 end
    return realAvailable()
end
dummy(true); layout()
local center = o.burdenCenter[1]
check(reservedWidth == 8 * 24 + 7 * 8, 'burden reserves full three-digit slots, ignoring stale available window width')
check(lastPlaced[1] + (measuredWidth + 20) / 2 == center, 'burden window is held at its top centre')
measuredWidth = 380; layout()
check(lastPlaced[1] + (measuredWidth + 20) / 2 == center, 'wider burden grows equally to left and right')
measuredWidth = 180; layout()
check(lastPlaced[1] + (measuredWidth + 20) / 2 == center, 'narrower burden shrinks around same centre')
check(o.burdenPos[1] ~= -20000 and o.burdenCenter[1] == center, 'off-screen measurement cannot overwrite saved burden position')
dummy(false); layout()
check(reservedWidth == 8 * 24 + 7 * 8, 'ordinary and unknown burdens retain the same row width')
imgui.Begin, imgui.GetItemRectSize, imgui.CalcTextSize = realBegin, realRectSize, realCalcSize
imgui.Dummy, imgui.GetContentRegionAvail = realDummy, realAvailable
o.splitWindows[1] = false; layout()
check(windows['winxi.puppet'] and not windows['winxi.puppet.burden'] and not windows['winxi.puppet.cooldowns'], 'combined layout restored without duplicate windows')
check(o.burdenPos[1] == 410 and o.cooldownPos[1] == 570, 'combined layout preserves split positions')
window.Full, imgui.GetWindowPos, imgui.SetNextWindowPos = realFull, realPos, realNextPos
imgui.Text, imgui.TextDisabled, imgui.TextColored = realText, realDisabled, realColored

packets.inbound.action.parse, predict.Priority = realParse, realPriority
H.print(('puppet regression: %d assertions passed'):format(count))
