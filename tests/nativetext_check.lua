-- luajit tests/nativetext_check.lua
-- The text tap bridge: each chat line as uihook recorded it after every addon, read once each, round the ring.
package.path='addons/libs/?.lua;'..package.path
local ffi=require('ffi')
local model=require('winxi.nativetext')
assert(ffi.sizeof('uihook_text_t')==16+16+64*(24+8192),'text ABI 1 layout')
local data=ffi.new('uihook_text_t[1]')
local b=data[0]; b.Version=1; b.Size=ffi.sizeof('uihook_text_t'); b.Frame=42
local loaded,base,finds=true,1000,0
AshitaCore={GetPluginManager=function() return {IsLoaded=function(_,name) assert(name=='uihook'); return loaded end} end}
ashita={memory={get_base=function() return base end,find=function(_,_,pattern)
    assert(pattern=='5549484F4F4B2D544558540000000000',pattern); finds=finds+1; return ffi.cast('uintptr_t',data)
end}}
local now=0
os.clock=function() return now end
-- a line recorded, as uihook does it: at the serial's place, the serial written last
local function Record(mode,finalMode,original,final,flags)
    local e=b.Events[b.Serial%64]
    e.Serial=0; e.Mode,e.FinalMode,e.Flags=mode,finalMode,flags or 0
    ffi.copy(e.Original,original,#original); e.OriginalLength=#original
    ffi.copy(e.Final,final,#final); e.FinalLength=#final
    b.Serial=b.Serial+1; e.Serial=b.Serial
end
Record(9,9,'before chatbox','before chatbox')
local tap=model.new()
assert(tap.Ready(),'uihook 0.8 found')
local first=tap.Drain()
assert(type(first)=='table' and #first==0,'the first drain starts at the newest: lines from before are not replayed')
Record(10,10,'Ann : hi','\30\81[12:00:00]\30\01 Ann : hi',8)
Record(150,151,'npc','npc',4+1)
local lines=tap.Drain()
assert(#lines==2 and lines[1].serial==2 and lines[1].text=='\30\81[12:00:00]\30\01 Ann : hi' and lines[1].original=='Ann : hi','the lines since, oldest first, the bytes the game keeps and was given')
assert(lines[1].modified and not lines[1].injected and not lines[1].blocked and not lines[1].indent,'modified, and nothing else')
assert(lines[2].mode==150 and lines[2].finalMode==151 and lines[2].indent and lines[2].injected and not lines[2].modified,'the modes both ways; indent and injected flags')
assert(#tap.Drain()==0,'read once')
Record(20,20,'crab','crab',2)
assert(tap.Drain()[1].blocked,'a blocked line says so')
-- further behind than the ring holds: the oldest lost, the newest 64 read
for i=1,70 do Record(1,1,'line '..i,'line '..i) end
lines=tap.Drain()
assert(#lines==64 and lines[1].text=='line 7' and lines[64].text=='line 70','the newest 64 of 70: the oldest six lost')
-- a line still being written (its serial not yet its own) is left out, and read next time
local e=b.Events[b.Serial%64]; e.Serial=0; e.Mode,e.FinalMode=1,1; ffi.copy(e.Final,'half',4); e.FinalLength=4; e.OriginalLength=0
b.Serial=b.Serial+1
assert(#tap.Drain()==0,'a half-written line is not read')
e.Serial=b.Serial
Record(1,1,'whole','whole')
lines=tap.Drain()
assert(#lines==2 and lines[1].text=='half' and lines[2].text=='whole','both read once whole') -- the half one's serial was moved past: read after
-- a line cut by uihook says so
Record(1,1,'long','long',16)
assert(tap.Drain()[1].cut,'a cut line says so')
-- uihook gone and back: nothing while gone, then a fresh start at the newest
loaded=false; assert(tap.Drain()==nil and not tap.Ready() and tap.Status():find('Load uihook'),'no uihook, nothing')
loaded=true; now=now+2; Record(1,1,'while away','while away')
assert(#tap.Drain()==0,'back: starts at the newest again')
b.Version=2; now=now+2; assert(model.new().Drain()==nil,'ABI mismatch refused')
b.Version=1
print('Native text: ABI, a fresh start at the newest, lines once each with modes and flags, the ring\'s limit, a half-written line, uihook gone and back passed')
