-- Chat-owned panel data must keep updating when the native clock is hidden/unavailable.
package.path='addons/libs/?.lua;'..package.path
local sourceModel=require('winxi.infopanel.source')
local exp=require('winxi.infopanel.exp')
local raw=1
local time={get_game_time_raw=function() return raw end,get_game_weekday=function() return 3 end}
local nativeVisible=true
local hud={Grid=function() return nativeVisible and '(H-9)' or nil end,
    Weather=function() return nativeVisible and 6 or nil end,
    Begin=function() error('must not claim clock slot') end,Stop=function() error('must not stop clock slot') end}
local gameGrid='(H-10)'
local source=sourceModel.New({time=time,native={Clock=0,new=function() return hud end},grid={Read=function() return gameGrid end}})
AshitaCore={GetMemoryManager=function() return {GetParty=function() return {
    GetMemberServerId=function() return 123 end,GetMemberZone=function() return 100 end,
} end} end,GetResourceManager=function() return {GetString=function(_,kind,id)
    if kind=='weather' then return id==7 and 'Squalls' or 'Rain' end
    return 'West Ronfaure'
end} end}
local c=source.Context('{time} {zone} {weather}',100)
assert(c.raw==1 and c.grid=='(H-9)' and c.weatherId==6 and c.weather=='Rain')
nativeVisible=false; raw=2
c=source.Context('{time} {zone}',101)
assert(c.raw==2 and c.grid==nil and c.weekday==3,'hidden native clock never gates time/context')
c=source.Context('{time} {grid}',101)
assert(c.raw==2 and c.grid=='(H-10)','with the clock hidden (fishing), the grid is the game\'s own, worked out')
gameGrid=nil
assert(source.Context('{time} {grid}',101).grid==nil,'a zone without a grid has none')
gameGrid='(H-10)'
assert(require('winxi.infopanel.fields').Line(c,'{zone}')=='West Ronfaure')
local function Packet(size,offset,value)
    return string.rep('\0',offset)..string.char(value%256,math.floor(value/256))..string.rep('\0',size-offset-2)
end
source.Packet(0x057,Packet(12,8,7),'',false)
c=source.Context('{weather}',102)
assert(c.weatherId==7 and c.weather=='Squalls','weather packet works while clock hidden and panel disabled')
source.Packet(0x00b,'','',false)
assert(source.Context('',103).weatherId==nil,'zone departure clears weather')
source.Packet(0x00a,Packet(0x70,0x68,0),'',false)
assert(source.Context('',104).weatherId==0,'clear sky from zone-in is valid')
source.Packet(0x057,'short','',false)
assert(source.Context('',105).weatherId==nil,'short packet does not invent weather')
source.Packet(0x057,Packet(12,8,200),'',false)
assert(source.Context('',106).weatherId==nil,'unsupported weather is omitted')
local function LE(n,bytes) local s='' for _=1,bytes do s=s..string.char(n%256); n=math.floor(n/256) end return s end
local gain=LE(0,4)..LE(123,4)..LE(123,4)..LE(0,4)..LE(200,4)..LE(0,4)..LE(8,2)..LE(0,2)
exp.Reset(100)
source.Packet(0x02D,gain,'{rate}',true)
assert(select(2,exp.Since())==1,'EXP counted for active slot data')
source.Packet(0x02D,gain,'{rate}',false)
source.Packet(0x02D,gain,'{time}',true)
assert(select(2,exp.Since())==1,'no counting for disabled/non-EXP panel')
source.Reset(); assert(select(2,exp.Since())==0,'character reset clears EXP/private source state')
assert(source.Status()==nil)
-- The grid function is found through the clock's own call to it, and refused where it is not the one known
do
    local finds, start = 0, 0x10
    ashita={memory={find=function() finds=finds+1; return finds==1 and 0 or 0x1000 end,
        read_uint32=function(at) assert(at==0x1000+12); return 0xFFFFFFF0 end, -- back 16 from the call's end
        read_uint8=function(at) return at==0x1000+16-16 and start or 0 end}}
    package.loaded['winxi.infopanel.grid']=nil
    local grid=require('winxi.infopanel.grid')
    local clock=os.clock; local now=0; os.clock=function() return now end
    assert(grid.Read()==nil and grid.Status():find('not found'),'no clock call: no grid, said why')
    assert(grid.Read()==nil and finds==1,'not looked for again at once')
    now=6
    assert(grid.Read()==nil and finds==2 and grid.Status():find('not the one known'),'a call to some other function is refused')
    os.clock=clock; ashita=nil
end
print('Info panel source: hidden-clock independence, the grid kept while the clock is hidden, zone name, weather packets, EXP and reset passed')
