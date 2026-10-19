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
print('Chatbox visibility: routing, resize animation, idle timing, fade-in/out, interaction and imported history passed')
