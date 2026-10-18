package.path='addons/libs/?.lua;'..package.path
local ffi=require('ffi')
local model=require('winxi.nativemenus')
assert(ffi.sizeof('uihook_menus_t')==108)
local data=ffi.new('uihook_menus_t[1]')
local b=data[0]; b.Version=1; b.Size=108; b.Frame=42; b.Supported=1; b.RequestFrame=40
local loaded,base,finds=true,1000,0
AshitaCore={GetPluginManager=function() return {IsLoaded=function(_,name) assert(name=='uihook'); return loaded end} end}
ashita={memory={get_base=function() return base end,find=function(_,_,pattern)
    assert(pattern=='5549484F4F4B2D4D454E55530000000000'); finds=finds+1; return ffi.cast('uintptr_t',data)
end}}
local hook=model.new()
hook.Stop(); assert(b.RequestFrame==40,'no ownership means no native write')
local rect={left=20,top=700,width=640,height=18}
assert(hook.Set(rect,1))
assert(b.RequestFrame==42 and b.HostSlot==1 and b.Panel[0]==20 and b.Panel[1]==700 and b.Panel[2]==660 and b.Panel[3]==718)
assert(finds==1 and hook.Status():find('above'),'published only panel bounds/slot/stamp')
b.Frame=43; assert(hook.Set(rect,0) and b.RequestFrame==43 and finds==1,'cached matching ABI renews each capture')
assert(not hook.Set(rect,2) and not hook.Set(nil,0))
assert(not hook.Set({left=0,top=0,width=0,height=1},0))
assert(not hook.Set({left=0,top=0,width=0/0,height=1},0))
assert(not hook.Set({left=0,top=0,width=math.huge,height=1},0))
assert(not hook.Set({left=0,top=0,width='640',height=1},0))
hook.StopLog(); assert(b.LogRequestFrame==0 and b.RequestFrame==43,'the log never placed: nothing written')
assert(hook.PlaceLog(20,982) and b.LogPlace[0]==20 and b.LogPlace[1]==982 and b.LogRequestFrame==43,'the expanded log placed by its bottom-left, stamped')
assert(b.RequestFrame==43,'the menus\' request untouched')
assert(not hook.PlaceLog(0/0,982) and not hook.PlaceLog(20,math.huge) and not hook.PlaceLog(-1,982) and not hook.PlaceLog(20,0) and not hook.PlaceLog('20',982))
hook.Stop(); assert(b.LogRequestFrame==43,'giving the menus back leaves the log placed')
hook.StopLog(); assert(b.LogRequestFrame==0,'and the log is given back on its own')
assert(hook.Set(rect,0))
hook.Stop(); assert(b.RequestFrame==0,'stop releases request, native side restores geometry')
loaded=false; assert(not hook.Set(rect,0)); hook.Stop()
loaded=true; base=2000; assert(hook.Set(rect,0) and finds==2,'DLL base/load change rediscovers before any write')
hook.Stop(); b.Supported=0
local unsupported=model.new(); assert(not unsupported.Set(rect,0) and unsupported.Status():find('unchanged'))
b.Supported=1; b.Version=2
local wrong=model.new(); assert(not wrong.Set(rect,0) and wrong.Status():find('ABI mismatch'))
b.Version=1; b.Size=84
assert(not model.new().Set(rect,0),'layout mismatch cannot write')
print('Native menus: ABI/slot/bounds validation, capture renewal, ownership-only stop, unsupported client and DLL reload passed')
