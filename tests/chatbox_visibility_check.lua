package.path = 'addons/chatbox/?.lua;' .. package.path
local visibility = require('visibility')
local model = require('log')
local box = { left=20, top=100, bottom=250, width=400, height=150 }
local function measure(log, rows)
    if rows then return rows * 14 + 10 end
    return #log.messages
end
local function apply(state, options, history, filter, now, active)
    return visibility.Apply(state, options, history, filter, box, 10, now, active, measure)
end
local options = visibility.Defaults()
local history = model.New()
local original, rows, alpha = apply({}, options, history, nil, 100, false)
assert(original==box and rows==10 and alpha==1, 'disabled by default')
options.resize[1]=true
assert(apply({}, options, history, nil, 100, false)==nil, 'empty auto-resize hides')
model.Add(history, 'first', 1, 100)
model.Add(history, 'party', 5, 101)
local first = function(message) return message.mode==1 end
local second = function(message) return message.mode==5 end
local state = {}
local b, count = apply(state, options, history, first, 102, false)
assert(count==1 and b.height==24 and b.bottom==box.bottom, 'only routed recent rows determine size')
assert(box.height==150, 'layout source is not mutated')
assert(apply(state, options, history, first, 115, false)==nil, 'recent rows expire independently')
assert(apply({}, options, history, second, 115, false)~=nil, 'other window remains awake')
options.minimum[1]=2
b, count=apply(state, options, history, first, 120, false)
assert(count==2 and b.height==38, 'minimum rows retained')
b, count=apply(state, options, history, first, 120, true)
assert(b==box and count==10, 'interaction restores full size')
options.minimum[1]=50
b, count=apply({}, options, history, first, 120, false)
assert(b==box and count==10, 'minimum capped at capacity')
options.resize[1], options.fade[1]=false,true
state={}
b, count, alpha=apply(state, options, history, first, 100, false)
assert(b==box and alpha==1, 'active fade log fully visible')
b, count, alpha=apply(state, options, history, first, 115.5, false)
assert(math.abs(alpha-0.5)<0.0001, 'fade starts after the idle deadline, not the previous frame')
b, count, alpha=apply(state, options, history, first, 116, false)
assert(b==nil and alpha==0, 'fully faded log removed')
model.Add(history, 'new', 1, 116)
apply(state, options, history, first, 116, false)
b, count, alpha=apply(state, options, history, first, 116.1, false)
assert(b and math.abs(alpha-0.5)<0.0001, 'new routed message fades in')
b, count, alpha=apply(state, options, history, first, 116.2, false)
assert(b and math.abs(alpha-1)<0.0001, 'fade-in completes in 0.2 seconds')
b, count, alpha=apply(state, options, history, first, 200, true)
assert(b==box and alpha==1, 'interaction immediately reveals idle log')
b, count, alpha=apply(state, options, history, first, 210, false)
assert(b==box and alpha==1, 'idle delay restarts after interaction')
local imported={messages={{text='old',mode=1,time=0}},revision=1}
assert(apply({}, options, imported, nil, 1, false)==nil, 'imported history is not activity')
options.resize[1]=true
options.minimum[1]=0
assert(apply({}, options, imported, nil, 1, false)==nil, 'resize and fade can be combined')
state={}
apply(state, options, history, first, 116, false)
b, count, alpha=apply(state, options, history, first, 131.5, false)
assert(b and count>0 and math.abs(alpha-0.5)<0.0001, 'combined resizing retains rows during fade-out')
assert(apply(state, options, history, first, 132, false)==nil, 'combined resizing hides after fade-out')
local completed=visibility.Complete({window1={idle={0/0},duration={-2},minimum={500},fade='bad'}})
assert(completed.window1.idle[1]==15 and completed.window1.duration[1]==0.1 and completed.window1.minimum[1]==50 and completed.window1.fade[1]==false,'invalid saved settings normalized')
assert(completed.window2.resize[1]==false,'older settings gain disabled defaults')
-- Optional resize tween: bottom anchored, time-based, and exact again at rest.
local animated = visibility.Defaults()
animated.resize[1], animated.animate[1] = true, true
local moving, messages = {}, model.New()
local function near(a,b) return math.abs(a-b)<0.00001 end
assert(apply(moving,animated,messages,nil,100,false)==nil,'animation starts idle at zero height')
model.Add(messages,'one',1,101)
assert(apply(moving,animated,messages,nil,101,false)==nil,'growth starts from collapsed height')
b,count=apply(moving,animated,messages,nil,101.1,false)
assert(count==1 and near(b.height,12) and near(b.top,box.bottom-12),'halfway growth stays bottom anchored')
b=apply(moving,animated,messages,nil,101.2,false)
assert(near(b.height,24),'growth settles at exact row height and padding')
model.Add(messages,'two',1,102)
apply(moving,animated,messages,nil,102,false)
b=apply(moving,animated,messages,nil,102.1,false)
assert(near(b.height,31),'additional content smoothly grows existing box')
b=apply(moving,animated,messages,nil,102.2,false)
assert(near(b.height,38),'second row reaches exact height')
apply(moving,animated,messages,nil,117,false)
b,count=apply(moving,animated,messages,nil,117.1,false)
assert(count==2 and near(b.height,19),'collapse keeps rows available for clipping while shrinking')
model.Add(messages,'return',1,117.1)
b=apply(moving,animated,messages,nil,117.1,false)
assert(near(b.height,19),'reversing a shrink does not jump')
b=apply(moving,animated,messages,nil,117.3,false)
assert(near(b.height,24),'reversed animation reaches new target')
b,count=apply(moving,animated,messages,nil,118,true)
assert(b==box and count==10,'interaction bypasses animation immediately')
apply(moving,animated,messages,nil,140,false)
assert(apply(moving,animated,messages,nil,140.2,false)==nil,'completed collapse removes all padding and frame')
local normalized=visibility.Complete({window1={animate={true},resizeDuration={99}}})
assert(normalized.window1.animate[1] and normalized.window1.resizeDuration[1]==2
    and not normalized.window2.animate[1] and normalized.window2.resizeDuration[1]==0.2,'animation migration and duration bounds')
-- The window's messages are filtered once for each revision and filter, and the recent ones kept until one ages
-- out of idle: an unchanged history costs no filter calls, with the same results as a fresh state's.
do
    local cached = visibility.Defaults()
    cached.resize[1] = true
    local calls, measured = 0, {}
    local log = model.New()
    model.Add(log, 'a', 1, 100); model.Add(log, 'b', 5, 101); model.Add(log, 'c', 1, 105)
    local function counting(message) calls = calls + 1; return message.mode == 1 end
    local function other(message) calls = calls + 1; return message.mode == 5 end
    local function track(recent, rows)
        if rows then return rows * 14 + 10 end
        measured[#measured + 1] = recent
        return #recent.messages
    end
    local function run(st, filter, now) return visibility.Apply(st, cached, log, filter, box, 10, now, false, track) end
    local st = {}
    local _, n = run(st, counting, 106)
    assert(n == 2 and calls == 3, 'first frame filters every message')
    local kept = st.log
    calls = 0
    for t = 106.1, 109, 0.1 do
        local _, again = run(st, counting, t)
        assert(again == 2, 'unchanged history keeps its rows')
    end
    assert(calls == 0, 'an unchanged history is not filtered again')
    assert(st.log == kept and measured[#measured] == kept, 'the same wrapped log is measured')
    local list = st.recent.list
    run(st, counting, 109.5)
    assert(st.recent.list == list, 'the recent list is kept while nothing leaves idle')
    -- 'a' (100) leaves idle at 115: then and only then the recent list is made again, without filtering
    run(st, counting, 114.9)
    assert(st.recent.list == list and calls == 0, 'kept just before the oldest ages out')
    local _, aged = run(st, counting, 115)
    assert(aged == 1 and st.recent.list ~= list and calls == 0, 'a message ageing out of idle makes the list again, unfiltered')
    assert(#st.recent.list == 1 and st.recent.list[1] == log.messages[3], 'only the newer message is recent')
    local _, freshRows = run({}, counting, 115)
    assert(freshRows == aged, 'the same rows as a fresh state after ageing out')
    -- a new message: filtered again
    calls = 0
    model.Add(log, 'd', 1, 116)
    local _, grown = run(st, counting, 116)
    assert(grown == 2 and calls == 4 and st.log.messages[2] == log.messages[4], 'a new message is filtered and counted')
    calls = 0; run(st, counting, 116.5); assert(calls == 0, 'and kept after')
    -- a filter change: filtered again with the new filter
    local routed = run(st, other, 116.5)
    assert(routed == nil and calls == 4, 'a filter change filters again') -- 'b' (101) is past idle
    calls = 0; run(st, other, 116.6); assert(calls == 0, 'the new filter kept after')
    -- a message with a time still to come is not activity until it is reached
    local future = model.New()
    model.Add(future, 'later', 1, 200)
    local fst = {}
    assert(visibility.Apply(fst, cached, future, nil, box, 10, 199, false, track) == nil, 'a later message is not yet recent')
    local _, reached = visibility.Apply(fst, cached, future, nil, box, 10, 200, false, track)
    assert(reached == 1, 'it is once its time is reached')
    -- time going back makes the list again
    assert(visibility.Apply(fst, cached, future, nil, box, 10, 199, false, track) == nil, 'time gone back is worked out again')
    -- Clear: filtered again, nothing recent
    calls = 0
    model.Clear(log)
    assert(run(st, counting, 116.6) == nil and calls == 0 and #st.timed.list == 0, 'Clear forgets the kept messages')
    model.Add(log, 'e', 1, 117)
    local _, after = run(st, counting, 117)
    assert(after == 1 and calls == 1, 'a message after Clear is filtered')
end
-- Against the scan of every message each frame, as Apply did it: the same recent messages, in the same order, and
-- the same newest time, over random messages, filters, idle windows and frames.
do
    local function reference(history, filter, now, idle)
        local recent, latest = {}, nil
        for _, message in ipairs(history.messages) do
            if not filter or filter(message) then
                if message.time > 0 and message.time <= now then
                    latest = math.max(latest or message.time, message.time)
                    if now - message.time < idle then recent[#recent + 1] = message end
                end
            end
        end
        return recent, latest
    end
    math.randomseed(7)
    local filters = { false, function(m) return m.mode == 1 end, function(m) return m.mode ~= 1 end }
    local random = visibility.Defaults()
    random.resize[1] = true
    local log, st, now = model.New(), {}, 50
    for step = 1, 3000 do
        local roll = math.random()
        if roll < 0.15 then model.Add(log, 'm' .. step, math.random(1, 2), now + (math.random() < 0.1 and math.random() * 3 or 0))
        elseif roll < 0.16 then model.Clear(log)
        elseif roll < 0.17 then model.Prepend(log, { { text = 'old', mode = 1 } })
        elseif roll < 0.19 then random.idle[1] = math.random(1, 6) end
        now = now + (math.random() < 0.02 and -math.random() or math.random() * 0.7)
        local filter = filters[math.random(1, #filters)] or nil
        visibility.Apply(st, random, log, filter, box, 10, now, false, measure)
        local want, wantLatest = reference(log, filter, now, random.idle[1])
        local got = st.recent.list
        assert(#got == #want and st.recent.latest == wantLatest, 'the same recent messages as a full scan, step ' .. step)
        for i = 1, #want do assert(got[i] == want[i], 'the same messages in order, step ' .. step) end
    end
end
print('Chatbox visibility: routing, resize animation, idle timing, fade-in/out, interaction, imported history and the kept recent messages passed')
