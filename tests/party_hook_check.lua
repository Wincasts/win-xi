-- Standalone: lifecycle/ABI/capture routing without Windows or unsafe native calls.
package.path = 'addons/libs/?.lua;' .. package.path
local realffi = require('ffi')
local fake = { Version=3, Size=168, Hooked=1, SupportedMask=7, Frame=1, Submit=123,
    CapturedVertices=12, Replays=1, BlockedCalls=3, Failures=0, TargetCursorCalls=9, GeometryReady=1,
    Rects={ [0]={Left=0.7,Top=0.6,Right=0.99,Bottom=0.98,Frame=1},
        [1]={Left=0.7,Top=0.2,Right=0.99,Bottom=0.4,Frame=1},
        [2]={Left=0.7,Top=0.4,Right=0.99,Bottom=0.6,Frame=1},
        [3]={Left=0.7,Top=0.5,Right=0.99,Bottom=0.6,Frame=1} } }
local plugin = 'uihook'
local loaded, address, calls, captures = false, 500, {}, {}
local moduleBase, scans = 100, 0
package.loaded.ffi = {
    cdef=function() end, sizeof=function() return 168 end,
    cast=function(kind)
        if kind=='partyhook_shared_t*' then return fake end
        return function(index,capture)
            calls[#calls+1]={index,capture}
            if capture==1 then captures[#captures+1]=index end
            return 1
        end
    end,
}
local now=0
local clock=os.clock
os.clock=function() return now end
AshitaCore={ GetPluginManager=function() return {IsLoaded=function(_, name) return loaded and name==plugin end} end }
ashita={memory={find=function(module, offset, pattern)
    assert(module == plugin .. '.dll' and offset == 0)
    local bytes = pattern:gsub('..', function(hex) return string.char(tonumber(hex, 16)) end)
    assert(bytes == 'PARTYHOOK' .. string.rep('\0', 7), 'shared marker must be exactly 16 bytes, matching char Magic[16]')
    scans=scans+1
    return address
end, get_base=function() return moduleBase end}}
local hidepartyLoaded=false
package.loaded['winxi.presence']={ Present=function(name) return name=='hideparty' and hidepartyLoaded end }
local hook=dofile('addons/party/hook.lua')
assert(not hook.Begin(true) and #calls==0,'unloaded DLL is not touched')
loaded=true
fake.Version=2
assert(not hook.Begin(true) and #calls==0,'ABI mismatch does not call code')
fake.Version=3; now=2
fake.Hooked=0
assert(not hook.Begin(true),'unrecognised client stays on ordinary windows')
fake.Hooked=1
assert(hook.Begin(true),'recognised client accepts replacement')
for i=0,5 do
    local call=calls[#calls-5+i]
    assert(call[1]==i and call[2]==(i<3 and 0 or -1),'party empties renewed; target slots relinquished when not enabled')
end
for i=1,3 do assert(hook.Capture({name='xiframes.us.'..i})) end
assert(hook.Rect({name='xiframes.us.2'})[2]==0.2,'alliance has its own live native rectangle')
fake.Rects[1].Frame=0
assert(not hook.Rect({name='xiframes.us.2'}),'unseen/stale native coordinates are not used')
fake.Rects[1].Frame=1
fake.Frame=4
assert(not hook.Rect({name='xiframes.us.2'}),'native geometry expires after two frames')
fake.Frame=1
fake.Rects[1].Frame=4
assert(not hook.Rect({name='xiframes.us.2'}),'future frame stamps are rejected with unsigned age checks')
fake.Rects[1].Frame=1; fake.GeometryReady=0
assert(not hook.Rect({name='xiframes.us.2'}),'missing geometry signature leaves anchoring unavailable')
fake.GeometryReady=1
assert(not hook.Rect({name='xiframes.tgt.main'}),'inactive target group never supplies a placement anchor')
assert(#captures==3 and captures[1]==0 and captures[3]==2,'capture only party/alliance windows')
assert(not hook.Capture({name='xiframes.tgt.main'}),'target drawing is not consumed')
assert(hook.Status():find('party active',1,true),'status still identifies active native mode')
for _,text in ipairs({'Vertices:','replays:','blocked GPU calls:','capture failures:','preserved arrow calls:','native geometry:'}) do
    assert(not hook.Status():find(text,1,true),'user-facing status must not expose debug counters/geometry')
end
assert(hook.Begin(true,true) and not hook.Uses({name='xiframes.tgt.main'}), 'missing target support does not break working party mode')
fake.SupportedMask=15
assert(hook.Begin(false,true) and not hook.Uses({name='xiframes.us.1'}), 'target-only mode relinquishes party lists')
for _,key in ipairs({'main','sub','tot'}) do assert(hook.Capture({name='xiframes.tgt.'..key})) end
assert(captures[4]==3 and captures[5]==4 and captures[6]==5,'all target windows captured in distinct slots')
assert(hook.Status():find('native arrows preserved',1,true),'status explains native arrows without counters')
assert(hook.Begin(true,true))
hook.Disable(true)
assert(hook.Uses({name='xiframes.us.1'}) and not hook.Uses({name='xiframes.tgt.main'}),'target-off does not release party mode')
assert(calls[#calls][1]==5 and calls[#calls][2]==-1, 'target-off clears its slots immediately')
assert(hook.Begin(true,true))
hook.Disable(false)
assert(not hook.Uses({name='xiframes.us.1'}) and hook.Uses({name='xiframes.tgt.main'}),'party-off does not release target mode')
hook.Begin(false,false)
assert(calls[#calls][1]==-1 and not hook.Capture({name='xiframes.us.1'}),'disabled/organize gives native HUD back immediately')
-- A hooked fish: the game's drawing outside the party windows let through, where uihook can
fake.SupportedMask=15
assert(hook.Begin(true,true,true) and not hook.Passing() and not hook.Uses({name='xiframes.us.1'})
    and hook.Uses({name='xiframes.tgt.main'}),'a uihook without the pass gives the party list back, the target kept')
fake.SupportedMask=15+16
assert(hook.Begin(true,true,true) and hook.Passing() and hook.Uses({name='xiframes.us.1'}),'with it the list stays replaced')
for i=0,5 do
    local call=calls[#calls-5+i]
    assert(call[1]==i and call[2]==(i<3 and 4 or 0),'party empties renewed with the pass; target slots as ever')
end
assert(hook.Capture({name='xiframes.us.2'}) and calls[#calls][1]==1 and calls[#calls][2]==5,'party captures carry the pass')
assert(hook.Capture({name='xiframes.tgt.main'}) and calls[#calls][2]==1,'target captures do not')
assert(hook.Begin(true,true) and not hook.Passing() and calls[#calls-5][2]==0,'the fight over: no pass')
assert(hook.Begin(true,true,true) and hook.Passing()); hook.Stop()
assert(not hook.Passing(),'stopping ends the pass')
fake.SupportedMask=15
local n=#calls
loaded=false; hook.Stop()
assert(#calls==n,'unload never calls a dangling DLL function pointer')
assert(not hook.Begin(true),'unloaded pointer cache is forgotten')
loaded=true; now=4
assert(hook.Begin(true),'reload rediscovers the shared block')
local previous = scans
moduleBase = 200 -- unload/reload at another base between frames, without observing IsLoaded=false
assert(hook.Begin(true) and scans>previous,'relocated DLL invalidates cached pointers even between frames')
-- hideparty hides the frames native windows replace: never both, and the windows given back to the game
hidepartyLoaded=true
local before=#calls
assert(not hook.Begin(true, true) and hook.Status():find('hideparty',1,true),'refused while hideparty is loaded, and said why')
assert(calls[#calls][1]==-1 and calls[#calls][2]==0 and #calls==before+1,'what was replaced is given back')
hidepartyLoaded=false
assert(hook.Begin(true),'taken again once hideparty is unloaded')
package.loaded['winxi.presence']=nil
package.loaded.ffi=realffi; os.clock=clock
print('Party native hook: ABI 3/native geometry, independent party/target modes, six slots, cursor diagnostics, the pass outside the party windows, disable/unload/reload passed')
