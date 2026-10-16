-- Count hot-path work rather than pretending the harness measures game/D3D performance.
-- luajit tests/harness.lua buff addons/buff/buff.lua tests/buff_performance_check.lua
local imgui = require('imgui')
local game = require('winxi.game')
local statuses = require('statuses')
local icons = require('winxi.statusicons')
local counts = {ids=0,timers=0,clock=0,resources=0,menus=0,icons=0}
local ids, timers = {}, {}
local epoch, stamp = 0x3C307D70, 0x3C307D70 + 1000
for i=1,32 do
    local pick=i%4
    ids[i]=({[0]=40,[1]=33,[2]=42,[3]=251})[pick]
    timers[i]=pick==0 and 0x7FFFFFFF or 60000+({[1]=90,[2]=25,[3]=7200})[pick]*60
end
local player = {
    GetIsZoning=function() return 0 end, GetLoginStatus=function() return 2 end,
    GetStatusIcons=function() counts.ids=counts.ids+1; return ids end,
    GetStatusTimers=function() counts.timers=counts.timers+1; return timers end,
}
local party={GetMemberServerId=function() return 1 end}
AshitaCore.GetMemoryManager=function() return {GetParty=function() return party end, GetPlayer=function() return player end} end
AshitaCore.GetResourceManager=function() return {
    GetStatusIconByIndex=function(_,id)
        counts.resources=counts.resources+1
        return {HideTimer=id==251 and 1 or 0, CanCancel=id==33 and 1 or 0}
    end,
} end
icons.Get=function() counts.icons=counts.icons+1; return 1,true end
local menu=''
game.MenuName=function() counts.menus=counts.menus+1; return menu end
for _,key in ipairs({'IsLoading','IsInterfaceHidden','IsEventHappening','IsChatExpanded','IsMapOpen'}) do
    game[key]=function() return false end
end
-- Supply a synthetic readable game clock to the production reader, not a fake status snapshot.
local root=arg[2]:match('^(.*)/[^/]+$')
local originalFind=ashita.memory.find
ashita.memory.find=function() return 0x10000 end
ashita.memory.read_uint32=function(at)
    counts.clock=counts.clock+1
    if at==0x10000 then return 0x20000 end
    if at==0x20000 then return 0x30000 end
    if at==0x3000C then return stamp end
    return 0
end
local clocked=dofile(root .. '/statuses.lua')
ashita.memory.find=originalFind
statuses.Read=clocked.Read
local o=H.options(); o.fadeInOut[1]=false
local font,size={},14
imgui.GetFont=function() return font end
imgui.GetFontSize=function() return size end
H.play(true)
local function sample(label,frames)
    for key in pairs(counts) do counts[key]=0 end
    local metric=H.calls.CalcTextSize or 0
    local draws=H.calls['draw.AddImage'] or 0
    H.frames(frames)
    local result={}
    for key,value in pairs(counts) do result[key]=value end
    result.metrics=(H.calls.CalcTextSize or 0)-metric
    result.draws=(H.calls['draw.AddImage'] or 0)-draws
    H.print(label .. ': ' .. frames .. ' frames | ids',result.ids,'| timers',result.timers,
        '| clock reads',result.clock,'| metadata',result.resources,'| text measurements',result.metrics,
        '| menu checks',result.menus,'| icons',result.draws)
    return result
end
H.frames(2) -- warm resource and label caches
local normal=sample('32 statuses, warm timers',120)
o.showTimers[1]=false
local off=sample('32 statuses, timers disabled',120)
o.showTimers[1]=true; o.isVisible[1]=false
local invisible=sample('Visibility off, no fading',120)
o.isVisible[1]=true
if arg[4]=='measure' then
    for i=1,32 do ids[i]=255 end
    sample('Empty status bar',120)
    return
end
assert(normal.ids==120 and normal.timers==120 and normal.clock==360)
assert(normal.resources==0 and normal.metrics==0 and normal.menus==0 and normal.draws==3840)
assert(off.ids==120 and off.timers==0 and off.clock==0 and off.resources==0 and off.metrics==0 and off.draws==3840)
assert(invisible.ids==0 and invisible.timers==0 and invisible.clock==0 and invisible.draws==0)
-- Font/size changes must invalidate layout and label measurements, then become cheap again.
size=18
local resized=sample('Font-size changed',1)
assert(resized.metrics==4) -- layout (2) and two distinct displayed labels (2)
assert(sample('Font-size stable',2).metrics==0)
font={}
assert(sample('Font face changed',1).metrics==4)
-- Per-addon font overrides are pushed once per bar and restored, not once per icon.
local fonts=require('winxi.fonts')
local oldGet,oldThemePush=fonts.Get,fonts.Push
local oldPush,oldPop=imgui.PushFont,imgui.PopFont
local override,themeFace={},{}
local stack,lastSize={},nil
imgui.PushFont=function(face,value)
    stack[#stack+1]={font,size}
    font,size=face or font,value>0 and value or size
    lastSize=value
    oldPush(face,value)
end
imgui.PopFont=function()
    local prior=assert(table.remove(stack),'balanced font stack')
    font,size=prior[1],prior[2]
    oldPop()
end
fonts.Get=function(file) return file=='test.ttf' and override or nil end
local beforeFont,beforeSize=font,size
o.fontFile='test.ttf'; o.fontSize[1]=22
assert(sample('Addon font override',1).metrics==4)
assert(font==beforeFont and size==beforeSize and #stack==0 and lastSize==22)
assert(sample('Addon font stable',2).metrics==0)
o.fontSize[1]=0
sample('Addon font inherits size',1)
assert(lastSize==beforeSize and #stack==0)
o.fontFile=''; o.fontSize[1]=0
fonts.Push=function() imgui.PushFont(themeFace,20); return true end
local oldIcons=icons.Get
icons.Get=function(...) assert(font==themeFace and size==20); return oldIcons(...) end
sample('Anchored bar inherits theme font',1)
assert(font==beforeFont and size==beforeSize and #stack==0)
-- Both theme and local fonts must be popped if drawing throws.
o.fontFile='test.ttf'; o.fontSize[1]=22
icons.Get=function() error('synthetic font cleanup check') end
assert(not pcall(H.frames,1))
assert(#stack==0 and font==beforeFont and size==beforeSize)
icons.Get=oldIcons; fonts.Get,fonts.Push=oldGet,oldThemePush
imgui.PushFont,imgui.PopFont=oldPush,oldPop
o.fontFile=''; o.fontSize[1]=0
-- No statuses: not even the timer array or clock is fetched.
for i=1,32 do ids[i]=255 end
local empty=sample('Empty status bar',120)
assert(empty.ids==120 and empty.timers==0 and empty.clock==0 and empty.draws==0)
-- Reused entries must clear old countdowns when timers are switched off.
ids[1],timers[1]=33,60000+90*60
local list={}
assert(statuses.Read(list)==1 and list[1].seconds==90)
local entry=list[1]
assert(statuses.Read(list,false)==1 and list[1]==entry and entry.seconds==nil)
timers[1]=nil
assert(statuses.Read(list)==1 and list[1].seconds==nil)
timers[1]=0x7FFFFFFF; counts.clock=0
assert(statuses.Read(list)==1 and counts.clock==0, 'permanent statuses need no game clock')
ids[2]=42
player.GetStatusTimers=function() counts.timers=counts.timers+1; return nil end
counts.timers=0
assert(statuses.Read(list)==2 and counts.timers==1 and list[1].seconds==nil and list[2].seconds==nil,
    'an unavailable timer array is requested only once per frame')
H.print('Hot-path budgets, font invalidation, entry reuse and missing timers: passed')
