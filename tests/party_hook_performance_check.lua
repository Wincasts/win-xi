-- Isolated interpreter-mode budgets: fake DLL calls do not allocate. Not an in-game FPS benchmark.
local realffi=require('ffi')
local queries,submits,releases,failAt=0,0,0,nil
local fake={Version=3,Size=168,Hooked=1,SupportedMask=15,Frame=1,Submit=123,GeometryReady=1,
    Rects={[0]={Left=0.5,Top=0.5,Right=0.99,Bottom=0.99,Frame=1}}}
local function submit(index,capture)
    submits=submits+1
    if index==-1 then releases=releases+1 end
    if index==failAt then failAt=nil; return 0 end
    return 1
end
package.loaded.ffi={cdef=function() end,sizeof=function() return 168 end,
    cast=function(kind) if kind=='partyhook_shared_t*' then return fake else return submit end end}
local manager={IsLoaded=function() queries=queries+1; return true end}
AshitaCore={GetPluginManager=function() return manager end}
ashita={memory={get_base=function() return 100 end,find=function() return 500 end}}
local hook=dofile('addons/party/hook.lua')
local window={name='xiframes.us.1'}
jit.off(); jit.flush()
local function allocated(fn)
    for _=1,10 do fn() end
    collectgarbage('collect'); collectgarbage('stop')
    local before=collectgarbage('count')
    for _=1,1000 do fn() end
    local bytes=(collectgarbage('count')-before)*1024/1000
    collectgarbage('restart')
    return bytes
end
local renewal=allocated(function() assert(hook.Begin(true,true)) end)
local placement=allocated(function() assert(hook.Rect(window)) end)
assert(renewal<8 and placement<8,'steady native renewal/rectangle reads must not allocate per frame')
local before=releases
hook.Stop()
assert(releases==before+1,'first stop releases active submissions immediately')
local oldQueries,oldSubmits=queries,submits
local idle=allocated(function() hook.Begin(false,false) end)
assert(queries==oldQueries and submits==oldSubmits,'idle disabled frames must not query or call the DLL repeatedly')
assert(idle<8)
assert(hook.Begin(true,true))
failAt=3; before=releases
assert(not hook.Begin(true,true) and releases==before+1,'partial renewal failure still releases all owned submissions')
package.loaded.ffi=realffi
print(('Native hook allocations: renewal %.1f B/frame; rectangle %.1f B/read; disabled %.1f B/frame; idle DLL calls 0'):format(renewal,placement,idle))
