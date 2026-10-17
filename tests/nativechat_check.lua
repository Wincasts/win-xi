-- Standalone native chat bridge contract; callbacks mocked, no client needed.
local ffi = require('ffi')
local block = {Version=8,Size=232,Submit=123,SupportedMask=63,Frame=10,
    NativeFrame={[0]=10,[1]=0,[2]=0},DrawnFrame={[0]=10,[1]=0,[2]=0},
    InputRect={[0]=0,[1]=0.9,[2]=1,[3]=1},InputRectFrame=10,
    PrimaryRect={[0]=0.05,[1]=0.5,[2]=0.5,[3]=0.9},PrimaryRectFrame=10,
    ExpandedRect={[0]=0,[1]=0.1,[2]=1,[3]=0.9},ExpandedRectFrame=10,
    StateFlags=0,StateFrame=10,FullScroll=0,FullCursor=20,FullPageRows=20,FullFilter=0,
    ControlStyleFrame=0,ControlColors={[0]={},[1]={},[2]={},[3]={}}}
local loaded, base, address, now, result = false, 100, 500, 0, 1
local calls, scans = {}, 0
package.loaded.ffi = {cdef=ffi.cdef,sizeof=ffi.sizeof,cast=function(kind)
    if kind == 'uihook_chat_t*' then return block end
    assert(kind == 'uihook_chat_submit_t')
    return function(index, capture) calls[#calls+1]={index,capture}; return result end
end}
os.clock=function() return now end
AshitaCore={GetPluginManager=function() return {IsLoaded=function(_,name) assert(name=='uihook'); return loaded end} end}
ashita={memory={get_base=function(name) assert(name=='uihook.dll'); return base end,
    find=function(name,offset,pattern)
        assert(name=='uihook.dll' and offset==0)
        assert(pattern:gsub('..',function(h) return string.char(tonumber(h,16)) end)=='UIHOOK-CHAT'..string.rep('\0',5))
        scans=scans+1; return address
    end}}
local native=dofile('addons/libs/winxi/nativechat.lua')
assert(ffi.sizeof('uihook_chat_t')==232)
local primary, split, input=native.new(native.Primary),native.new(native.Secondary),native.new(native.Input)
assert(not primary.Begin() and #calls==0)
loaded=true; block.Version=7
assert(not primary.Begin() and primary.Status():find('ABI mismatch'))
block.Version=8; now=2
assert(primary.Begin() and primary.Capture())
assert(calls[#calls][1]==0 and calls[#calls][2]==1)
assert(primary.Capture(true) and calls[#calls][1]==0 and calls[#calls][2]==2,
    'expanded capture explicitly requests frame-only native content')
local controls={{0.2,0.4,0.8,0.6},{1,0.9,0.8,1},{0.7,0.8,1,1},{1,1,1,0.7}}
assert(primary.Capture(true,controls) and block.ControlStyleFrame==block.Frame)
assert(block.ControlColors[0][2]==0.8 and block.ControlColors[3][3]==0.7,'RGBA controls copied separately from native state')
controls[2][1]=0/0
assert(primary.Capture(true,controls) and block.ControlStyleFrame==0,'invalid theme falls back to untinted native controls')
controls[2][1]=1
assert(primary.Capture(true,controls) and block.ControlStyleFrame==block.Frame)
assert(primary.Capture() and block.ControlStyleFrame==0,'compact capture cannot retain expanded tints')
block.SupportedMask=31
assert(primary.Capture(true,controls) and block.ControlStyleFrame==0,'optional controls capability is independent of frame capture')
block.SupportedMask=63
assert(primary.Capture(true,controls)); primary.Stop()
assert(block.ControlStyleFrame==0,'release invalidates shared colour stamp')
assert(primary.Begin())
assert(split.Begin() and calls[#calls][1]==1)
assert(input.Begin() and input.Capture() and calls[#calls][1]==2)
input.Stop(); assert(calls[#calls][1]==2 and calls[#calls][2]==-1, 'input stop cannot release logs')
primary.Stop(); assert(calls[#calls][1]==0 and calls[#calls][2]==-1)
local l,t,r,b=input.Rect(1920,1080)
assert(l==0 and t==972 and r==1920 and b==1080, 'input geometry maps normalized native bounds to display pixels')
local pl,pt,pr,pb=primary.Rect(1920,1080)
assert(pl==96 and pt==540 and pr==960 and pb==972, 'primary log anchor uses its own native rectangle')
local el,et,er,eb=primary.Rect(1920,1080,true)
assert(el==0 and et==108 and er==1920 and eb==972, 'expanded geometry independent of compact anchor')
assert(input.Rect(1920,1080,true)==nil, 'input cannot read expanded log bounds')
local state=primary.State(); assert(not state.selected and not state.expanded and state.expandedSupported and state.nativeContent and state.nativeControls)
block.StateFlags=1; assert(primary.State().selected and not primary.State().expanded, 'native selector focus')
block.StateFlags=4; state=primary.State(); assert(state.expanded and not state.nativeBrowse and state.pageRows==20)
block.StateFlags=12; assert(primary.State().nativeBrowse, 'native history/menu fallback')
block.Frame=13; assert(primary.State()==nil and primary.Rect(1920,1080,true)==nil, 'state/full bounds expire')
block.Frame=10; block.StateFlags=0
assert(split.Rect(1920,1080)==nil and input.Rect(0,1080)==nil, 'no split geometry; invalid display rejected')
block.PrimaryRectFrame=0; assert(primary.Rect(1920,1080)==nil and input.Rect(1920,1080)~=nil, 'log/input geometry independent')
block.PrimaryRectFrame=10
block.Frame=13; assert(primary.Rect(1920,1080)==nil, 'stale primary geometry expires')
block.Frame=10
block.Frame=13; assert(input.Rect(1920,1080)==nil, 'stale input geometry expires')
block.Frame=10; block.InputRectFrame=0; assert(input.Rect(1920,1080)==nil)
block.InputRectFrame=10; block.InputRect[2]=0/0; assert(input.Rect(1920,1080)==nil)
block.InputRect[2]=0; assert(input.Rect(1920,1080)==nil)
block.InputRect[2]=1
assert(split.Capture() and calls[#calls][1]==1,'primary stop leaves split alone')
result=0; assert(not split.Capture() and calls[#calls][2]==-1,'failed capture releases empty Begin')
result=1; block.SupportedMask=15
assert(primary.Begin() and not primary.Capture(true) and calls[#calls][2]==-1,
    'missing content capability releases the log rather than hiding native rows')
assert(input.Begin() and not input.Capture(true) and calls[#calls][1]==2 and calls[#calls][2]==-1,
    'frame-only capture is restricted to primary slot')
block.SupportedMask=1
assert(not split.Begin() and not input.Begin() and primary.Begin(),'unsupported split/input do not disable primary')
local n,d=primary.Ages(); assert(n==0 and d==0)
block.Frame=13; n,d=primary.Ages(); assert(n==3 and d==3 and primary.Status():find('not drawing'))
local count=#calls
loaded=false; primary.Stop(); assert(#calls==count and not primary.Capture(),'no stale DLL calls')
loaded=true; base=200; address=0; now=4
assert(not primary.Begin()); local previous=scans
assert(not primary.Begin() and scans==previous,'missing block scan throttled')
base=300; address=600
assert(primary.Begin(),'reload resets scan throttle')
base=400
assert(not primary.Capture(),'new DLL cannot inherit old ownership')
assert(primary.Begin()); block.SupportedMask=0
assert(not primary.Begin() and primary.Status():find('not recognise'))
print('Native chat bridge: ABI, marker, slot isolation, failure release, expiry, unload/reload passed')
