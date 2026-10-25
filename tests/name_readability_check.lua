local ffi,bit=require('ffi'),require('bit')
local policy,plates=require('readability'),require('winxi.nameplates')
local custom,format=require('custom'),require('format')
local options=custom.Defaults({})
assert(not options.crowdDeclutter[1] and not options.distanceColours[1])
local hook=ffi.new('namehook_t');hook.Count=4
local oldScreen,projections=plates.Screen,0
plates.Screen=function(n)
    projections=projections+1
    if bit.band(n.Flags,plates.Flag.OnScreen)==0 then return nil end
    return n.ScreenX,n.ScreenY
end
for i=0,3 do
    local n=hook.Names[i]
    n.Category,n.Flags,n.Scale,n.NameColor=plates.Category.Player,bit.bor(plates.Flag.Wanted,plates.Flag.OnScreen),1,0x80808080
    n.ScreenX,n.ScreenY=100+i*30,100
end
policy.Begin(options,hook,0);assert(projections==0,'disabled crowd policy must not project names')
options.crowdDeclutter[1],options.crowdThreshold[1],options.crowdHold[1]=true,4,250
policy.Begin(options,hook,0);policy.Begin(options,hook,.2)
assert(not policy.Simplify(hook.Names[0],false,false))
policy.Begin(options,hook,.251);assert(policy.Simplify(hook.Names[0],false,false))
local n=hook.Names[0]
for _,category in ipairs({plates.Category.Self,plates.Category.Party,plates.Category.Alliance,plates.Category.MyPet}) do
    n.Category=category;assert(not policy.Simplify(n,false,false))
end
n.Category=plates.Category.Monster
assert(not policy.Simplify(n,true,false) and not policy.Simplify(n,false,true))
for _,flag in ipairs({plates.Flag.Target,plates.Flag.Whitelisted,plates.Flag.Charmed}) do
    n.Flags=bit.bor(plates.Flag.Wanted,flag);assert(not policy.Simplify(n,false,false))
end
n.Flags=bit.bor(plates.Flag.Wanted,plates.Flag.OnScreen)
hook.Count=3;policy.Begin(options,hook,.3);assert(policy.Simplify(n,false,false))
hook.Count=1;policy.Begin(options,hook,.4);policy.Begin(options,hook,.6);assert(policy.Simplify(n,false,false))
hook.Count=4;policy.Begin(options,hook,.61)
hook.Count=1;policy.Begin(options,hook,.7);policy.Begin(options,hook,.951)
assert(not policy.Simplify(n,false,false),'stable recovery must restore details')
-- Off-window/transparent anchors must not trigger a crowd.
hook.Count=4;hook.Names[1].ScreenX=-100;hook.Names[2].NameColor=0
policy.Reset();policy.Begin(options,hook,1);policy.Begin(options,hook,2)
assert(not policy.Simplify(n,false,false))
local original=format.Compile('[icons] ([distance]y) [name:yellow] [letters] [aggro]')
local reduced=policy.Compact(original)
assert(reduced==policy.Compact(original) and reduced~=original)
assert(not reduced.distance and not reduced.icons and reduced.name and reduced.letter and reduced.aggro)
for _,part in ipairs(reduced) do
    if part.kind=='name' then assert(part.color==0xFFFFE040) end
    if part.kind=='text' then assert(part.text==' ') end
end
local nameless=format.Compile('[distance]y');assert(policy.Compact(nameless)==nameless)
local written={}
options.distanceColours[1]=true
local function color(d,id) written.distanceValue=d;return policy.Distance(options,written,id or 1) end
assert(color(19.9)==nil and color(20)==0xFFFFCC33)
assert(color(19.5)==0xFFFFCC33 and color(19)==0xFFFFCC33 and color(18.99)==nil)
assert(color(25)==0xFFFF4033 and color(24)==0xFFFF4033 and color(23.99)==0xFFFFCC33)
assert(color(50)==0xFFFF4033 and color(1)==nil)
assert(color(25)==0xFFFF4033 and color(24.5,2)==0xFFFFCC33,'identity changes clear prior hysteresis')
assert(color(25,2)==0xFFFF4033)
options.distanceDanger[1]=30;assert(color(24.5,2)==0xFFFFCC33,'config changes recalculate immediately')
for _,invalid in ipairs({-1,0/0,math.huge}) do assert(color(invalid)==nil and written.distanceBand==nil) end
assert(color(nil)==nil)
options.distanceDanger[1]=25;color(25)
options.distanceColours[1]=false;policy.Begin(options,hook,3)
options.distanceColours[1]=true;policy.Begin(options,hook,4)
assert(color(24.5)==0xFFFFCC33,'off/on must not resurrect a danger band')
color(25);policy.Reset();assert(color(24.5)==0xFFFFCC33)
local bad={crowdThreshold={math.huge},crowdHold={-1},distanceWarning={99},distanceDanger={4},distanceWarningColor={'secret',0/0,99}}
policy.Settle(bad)
assert(bad.crowdThreshold[1]==20 and bad.crowdHold[1]==250 and bad.distanceDanger[1]==99)
assert(bad.distanceWarningColor[1]==1 and bad.distanceWarningColor[2]==.8 and bad.distanceWarningColor[3]==1)
bad.distanceWarning[1],bad.distanceHysteresis[1]=1,10;policy.Settle(bad)
assert(bad.distanceHysteresis[1]==0,'a large margin must not create an unclearable band')
-- Actual quad pipeline: secondary glyphs disappear, core names remain, priority
-- changes restore detail immediately, and token colours win over distance tint.
ffi.cdef('void* mmap(void*, size_t, int, int, int, long); int munmap(void*, size_t);')
local low=ffi.C.mmap(nil,ffi.sizeof('namehook_draw_t'),3,0x62,-1,0)
assert(low~=ffi.cast('void*',-1))
local draw=ffi.cast('namehook_draw_t*',low);draw.QuadsMax=16384
hook.Hooked,hook.Draw=1,tonumber(ffi.cast('uintptr_t',low))
hook.Width,hook.Height,hook.TargetWidth,hook.TargetHeight=1920,1080,1920,1080
hook.Count=4
for i=0,3 do
    local name=hook.Names[i]
    name.EntityIndex,name.ServerId=i+1,100+i
    name.Category,name.Flags,name.Scale,name.NameColor=plates.Category.Player,bit.bor(plates.Flag.Wanted,plates.Flag.OnScreen,plates.Flag.Stars),1,0x80808080
    name.ScreenX,name.ScreenY=100+i*30,100
    ffi.copy(name.Name,'Alpha');ffi.copy(name.Text,'Alpha')
end
local imgui=require('imgui')
local glyph={X0=0,Y0=0,X1=8,Y1=12,U0=0,V0=0,U1=1,V1=1,AdvanceX=8,Visible=1}
local font={ContainerAtlas={TexData={UniqueID=2,Status=0,Width=512,Height=256}}}
imgui.GetFont=function() return font end
imgui.GetFontBaked=function() return {FindGlyph=function() return glyph end} end
imgui.PushFont,imgui.PopFont=function() end,function() end
imgui.GetIO=function() return {DisplaySize={x=1920,y=1080}} end
local memory=AshitaCore:GetMemoryManager()
local distance=21
memory.GetEntity=function() return {GetDistance=function() return distance and distance*distance or nil end} end
AshitaCore.GetMemoryManager=function() return memory end
options.showStars[1],options.showCheckDetails[1]=true,false
options.showStatuses={false}
options.showHealthBar[1]=true;options.healthBarCategories={255}
local bars,statuses={},{}
require('icons').Begin=function() return true end
require('icons').Texture=function() return 0xABCD end
require('icons').Place=function() return {0,0,1,1} end
require('healthbar').Write=function(name,entities,left,right,under) bars[name.EntityIndex]=true;return under+6 end
require('statuses').Begin=function() return true end
require('statuses').Write=function(name) statuses[name.EntityIndex]=true end
options.npcFormat[1]='[name]';options.nameFormat[1]='[name] [distance]';options.monsterFormat[1]='[name]'
custom.SetSheets(0,0)
local clock=os.clock;local now=10;os.clock=function() return now end
policy.Reset()
local function render() bars,statuses={},{};hook.Frame=hook.Frame+1;assert(custom.Frame(options,hook)==nil) end
render();local full=draw.Entities[1].Count
assert(full>0 and draw.Quads[draw.Entities[1].First+full-1].Color==0xFFFFCC33)
now=10.3;render();local core=draw.Entities[1].Count
assert(core>0 and core<full and draw.Entities[2].Count==core and not bars[1] and not statuses[1],
    'ordinary crowd plates omit stars, bars and status rows')
hook.Names[0].Flags=bit.bor(hook.Names[0].Flags,plates.Flag.Target)
render();assert(draw.Entities[1].Count==full and draw.Entities[2].Count==core and bars[1] and statuses[1])
hook.Names[1].Category=plates.Category.Party
render();assert(draw.Entities[2].Count==full and bars[2] and statuses[2],'party plates retain their details')
options.nameFormat[1]='[name] [distance:#FF0000]';render()
local row=draw.Entities[1];assert(draw.Quads[row.First+row.Count-1].Color==0xFFFF0000)
options.nameFormat[1]='[name] [distance]';distance=nil;render()
assert(draw.Entities[1].Count<full,'invalid distances must not retain stale digits')
options.crowdDeclutter[1]=false;distance=21;render()
assert(draw.Entities[3].Count==full,'off restores the exact original format')
custom.ResetReadability();os.clock=clock;plates.Screen=oldScreen
ffi.C.munmap(low,ffi.sizeof('namehook_draw_t'))
H.print('Readability: opt-in crowd projection, hold/margins, priority exemptions, compact identity, distance hysteresis, invalidation and actual quads passed',true)
