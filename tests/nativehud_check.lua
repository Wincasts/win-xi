-- Standalone bridge lifecycle and slot isolation; no native code is called.
local realffi = require('ffi')
local fake = {Version=3,Size=88,Grid='(H-9)',ClockRect={[0]=26,[1]=1098,[2]=106,[3]=1108},ClockRectFrame=10,SupportedMask=3,Frame=10,Submit=123,
    DrawnFrame={[0]=0,[1]=0},NativeFrame={[0]=10,[1]=10},Weather=7}
local loaded,base,address,now = false,100,500,0
local calls,scans={},0
local function submit(index,capture) calls[#calls+1]={index,capture}; return 1 end
package.loaded.ffi={cdef=realffi.cdef,sizeof=realffi.sizeof,string=function(s,n) return s:sub(1,n) end,cast=function(kind)
    if kind=='uihook_hud_t*' then return fake end
    assert(kind=='uihook_hud_submit_t'); return submit
end}
os.clock=function() return now end
AshitaCore={GetPluginManager=function() return {IsLoaded=function(_,name) assert(name=='uihook'); return loaded end} end}
ashita={memory={get_base=function(name) assert(name=='uihook.dll'); return base end,
    find=function(name,offset,pattern)
        assert(name=='uihook.dll' and offset==0)
        local marker=pattern:gsub('..',function(hex) return string.char(tonumber(hex,16)) end)
        assert(marker=='UIHOOK-HUD'..string.rep('\0',6))
        scans=scans+1; return address
    end}}
local native=dofile('addons/libs/winxi/nativehud.lua')
assert(realffi.sizeof('uihook_hud_t')==88)
local clock,compass=native.new(native.Clock),native.new(native.Compass)
assert(not clock.Begin() and #calls==0)
loaded=true; fake.Version=2
assert(not clock.Begin() and #calls==0 and clock.Status():find('ABI mismatch'))
fake.Version=3; now=2
assert(clock.Begin() and calls[#calls][1]==0 and calls[#calls][2]==0)
assert(clock.Capture() and calls[#calls][1]==0 and calls[#calls][2]==1)
assert(clock.Weather()==7)
fake.Frame=13; assert(clock.Weather()==nil,'stale weather must not survive native clock lifecycle')
fake.Frame=10; fake.Weather=65535; assert(clock.Weather()==nil)
fake.Weather=7
assert(compass.Begin() and calls[#calls][1]==1)
clock.Stop(); assert(calls[#calls][1]==0 and calls[#calls][2]==-1,'clock stop cannot release compass or party')
assert(compass.Capture() and calls[#calls][1]==1)
compass.Stop(); assert(calls[#calls][1]==1 and calls[#calls][2]==-1)
fake.SupportedMask=1
assert(not compass.Begin() and clock.Begin(),'missing compass must not disable clock')
local count=#calls
loaded=false; clock.Stop(); assert(#calls==count,'unloaded DLL callback never called')
assert(not clock.Capture() and not clock.Begin())
loaded=true; base=200; now=4; address=0
assert(not clock.Begin() and clock.Status():find('Update uihook'))
local previous=scans
assert(not clock.Begin() and scans==previous,'failed scans throttled')
base=300; address=600
assert(clock.Begin(),'DLL reload invalidates cached pointers and failed-scan throttle')
-- Status says whether the game reached its clock and whether the replacement was drawn there
fake.Frame=10; fake.NativeFrame[0]=0; fake.DrawnFrame[0]=0
assert(clock.Begin() and clock.Status():find('not drawing its clock') and clock.Status():find('never'))
fake.NativeFrame[0]=9
assert(clock.Status():find('could not draw'),'the game drew its clock, the replacement was not')
fake.DrawnFrame[0]=10
assert(clock.Status():find('Drawn in place'))
fake.Frame=20
assert(clock.Status():find('not drawing its clock') and clock.Status():find('11 frames ago'),'a clock the game stopped drawing is not called drawn')
local native,drawn=clock.Ages(); assert(native==11 and drawn==10)
-- The game's clock's place, current only while the game draws it, and the clock's alone
fake.Frame=10
local l,t,r,b=clock.ClockRect(); assert(l==26 and t==1098 and r==106 and b==1108)
assert(compass.ClockRect()==nil,'the compass slot has no clock place')
assert(clock.Grid()=='(H-9)' and compass.Grid()==nil,'the grid, the clock\'s alone')
fake.Grid='(H-9)\0\0\0'; assert(clock.Grid()=='(H-9)','to the first zero')
fake.Grid='\1\2'; assert(clock.Grid()==nil,'not text'); fake.Grid='(H-9)'
fake.Frame=13; assert(clock.ClockRect()==nil,'a place the game stopped drawing at is not kept')
assert(clock.Grid()==nil,'nor its grid')
fake.Frame=10; fake.ClockRect[2]=0/0; assert(clock.ClockRect()==nil,'not a number')
fake.ClockRect[2]=20; assert(clock.ClockRect()==nil,'right of left')
fake.ClockRect[2]=106
fake.SupportedMask=0
assert(not clock.Begin() and clock.Status():find('clock'))
print('Native HUD bridge: ABI, marker, clock/compass independence, renewal/capture/release, weather expiry, unload/reload passed')
