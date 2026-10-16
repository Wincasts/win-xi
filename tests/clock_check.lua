-- Basic clock addon without client/GPU. Checks formatting and current-window capture timing.
local rawCalls=0
local time={get_game_time_raw=function() rawCalls=rawCalls+1; return 123 end}
for name,value in pairs({weekday=7,hours=23,minutes=59,year=900,month=12,day=30,moon_percent=42}) do
    time['get_game_'..name]=function(raw) assert(raw==123,'every field must use the same timestamp'); return value end
end
local display=dofile('addons/clock/display.lua')
local lines=display.Read(time,'Rain')
assert(rawCalls==1 and lines[1]=='23:59  Darksday' and lines[2]=="Vana'diel 0900-12-30" and lines[3]=='Moon: 42%' and lines[4]=='Weather: Rain')
assert(#display.Read(time)==3,'weather is optional')
local handlers,calls,texts={},{},{}
local current,ready=false,true
local hook={Begin=function() calls[#calls+1]='begin'; return ready end,
    Capture=function() assert(current,'capture must happen before End'); calls[#calls+1]='capture'; return true end,
    Stop=function() calls[#calls+1]='stop' end,Status=function() return 'Ready' end,Weather=function() return 7 end}
package.loaded.common={}
package.loaded['winxi.version']={Number=5}
package.loaded['ffxi.time']=time
package.loaded.display=display
package.loaded['winxi.nativehud']={Clock=0,new=function(index) assert(index==0,'clock must never own compass'); return hook end}
package.loaded.settings={load=function(defaults) return defaults end,register=function() end,save=function() end}
local guiBegins=0
package.loaded.imgui={GetIO=function() return {DisplaySize={x=1920,y=1080}} end,
    SetNextWindowPos=function(pos) assert(pos[1]==20 and pos[2]==975) end,
    Begin=function(name) assert(name=='clock.native'); current=true; guiBegins=guiBegins+1; return true end,
    TextUnformatted=function(line) assert(current); texts[#texts+1]=line end,
    End=function() assert(current); current=false end}
for i,name in ipairs({'NoTitleBar','NoResize','NoMove','AlwaysAutoResize','NoSavedSettings','NoInputs','NoFocusOnAppearing','NoBringToFrontOnFocus'}) do
    _G['ImGuiWindowFlags_'..name]=2^(i-1)
end
ImGuiCond_Always=1
addon={}
ashita={events={register=function(_,name,callback) handlers[name]=callback end}}
AshitaCore={GetResourceManager=function() return {GetString=function(_,kind,id) assert(kind=='weather' and id==7); return 'Rain' end} end}
os.clock=function() return 1 end
dofile('addons/clock/clock.lua')
handlers.clock_load()
handlers.clock_present()
assert(not current and calls[#calls]=='capture' and #texts==4)
local function command(...)
    local args={...}; local e={command={args=function() return args end}}
    handlers.clock_command(e); assert(e.blocked)
end
command('/clock','off')
local before=guiBegins
handlers.clock_present()
assert(guiBegins==before and calls[#calls]=='stop','off releases replacement, does not consume or renew empty')
command('/clock','on')
ready=false; handlers.clock_present()
assert(guiBegins==before,'missing native capability never produces a floating duplicate clock')
ready=true; handlers.clock_present()
assert(guiBegins==before+1)
handlers.clock_unload()
assert(calls[#calls]=='stop','unload restores native clock only')
print('Clock addon: timestamp-consistent time/date/day/moon/weather, capture timing, disabled/unavailable and unload passed')
