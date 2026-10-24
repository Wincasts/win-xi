local casts,custom=require('castbar'),require('custom')
local packet=dofile('tests/fixtures/parse_packets.lua')
local options=custom.Defaults({})
local clock,now=os.clock,100
os.clock=function() return now end
local reads=0
local resources={
    GetSpellById=function(_,id) reads=reads+1;if id~=999 then return {Name={'Fire'},CastTime=16} end end,
    GetAbilityById=function() return {Name={'Fast Blade'}} end,
    GetString=function(_,kind,id) assert(kind=='monsters.abilities');return 'Ultrasonics' end,
}
AshitaCore.GetResourceManager=function() return resources end
package.loaded['winxi.spells']={Get=function(id) if id~=999 then return {Data={castTime=4000}} end end}
local actor=1001
local name={ServerId=actor,EntityIndex=1}
local currentId=actor
local entities={GetServerId=function() return currentId end}
local sequence=0
local function data(category,id,who,param)
    sequence=sequence+1
    return packet.Packet(who or actor,category,param or ((category==7 or category==8) and 24931 or id),
        {{id=2001,results={{value=id or 0,message=0}}}},sequence)
end
local function send(category,id,who,param)
    local bytes=data(category,id,who,param)
    casts.HandlePacket({id=0x028,data=bytes},options)
    return bytes
end
local function view(dead) return casts.Of(name,entities,now,dead) end
send(8,144);assert(not view() and reads==0,'disabled casts must not load resources')
assert(not options.showCastBar[1] and not options.castBarWeaponskills[1])
options.showCastBar[1]=true
local whole=data(8,144)
for length=0,34 do casts.HandlePacket({id=0x028,data=whole:sub(1,length)},options);assert(not view(),'truncated first result') end
casts.HandlePacket({id=0x028,data=whole,blocked=true},options);assert(not view())
casts.HandlePacket({id=0x028,data=whole},options)
local entry=assert(view());assert(entry.name=='Fire' and entry.progress==0 and entry.timer=='~4.0s')
now=101;entry=assert(view());assert(entry.progress==.25 and entry.timer=='~3.0s')
casts.HandlePacket({id=0x028,data=whole},options);assert(view().started==100,'duplicate starts cannot rewind progress')
send(4,145);assert(view(),'unrelated spell finish must not cancel a newer/different cast')
now=104.2;assert(view().progress==1 and view().timer=='Waiting')
send(4,144);assert(not view(),'server finish wins over an estimate')
send(8,144);send(8,0,nil,28787);assert(not view(),'interrupted spell')
-- Zero-target interruption packets are valid and need no result array.
send(8,144)
casts.HandlePacket({id=0x028,data=packet.Packet(actor,8,28787,{})},options)
assert(not view())
send(8,999);now=now+2;assert(view().progress==0 and view().timer=='+2.0s' and view().name=='Spell 999')
currentId=2002;assert(not view(),'never attach an old actor to a reused entity index')
currentId=actor;assert(not view())
send(8,144);assert(not view(true),'death clears the actor')
send(8,144)
local despawn=string.char(0,0,0,0,actor%256,math.floor(actor/256),0,0,0,0,0x20)
casts.HandlePacket({id=0x00E,data=despawn},options);assert(not view(),'despawn clears the actor')
send(8,144);casts.HandlePacket({id=0x00A,data=''},options);assert(not view(),'zone change clears the actor')
send(7,392);assert(not view(),'weaponskills are independently opt-in')
options.castBarWeaponskills[1]=true
send(7,392);entry=assert(view());assert(entry.name=='Ultrasonics' and entry.duration==1)
now=now+.5;assert(view().progress==.5)
send(11,392);entry=assert(view());assert(entry.timer=='Used' and entry.progress==1)
now=now+1.21;assert(not view())
local used=send(3,16);assert(view().name=='Fast Blade' and view().timer=='Used')
local started=view().started;now=now+.3
casts.HandlePacket({id=0x028,data=used},options);assert(view().started==started,'duplicate finishes cannot prolong a flash')
options.castBarWeaponskills[1]=false;casts.Begin(options,now)
assert(not view() and package.loaded['assets.mob_cast_times']==nil)
options.castBarWeaponskills[1]=true;send(7,392);send(7,0,nil,28787);assert(not view(),'ready move interrupted')
send(8,999);now=now+31;casts.Begin(options,now);assert(not view(),'safety timeout bounds missed finishes')
for i=1,300 do send(8,144,5000+i) end
assert(casts.Diagnostics():find('256 observed',1,true),'actor state must be bounded')
options.showCastBar[1]=false;casts.Begin(options,now)
assert(casts.Diagnostics():find('0 observed',1,true) and package.loaded['assets.mob_cast_times']==nil)
options.showCastBar[1]=true;options.drawNames={false};send(8,144);assert(not view())
options.drawNames[1]=true;casts.Configure(options)
casts.Preview[1]=true;casts.PreviewVisible(now)
local demo=assert(view());assert(demo.preview and demo.progress==0 and demo.name:find('Preview:',1,true))
assert(casts.Diagnostics():find('0 observed',1,true),'samples must not become observed actors')
now=now+.5;casts.PreviewVisible(now);assert(view().progress==.125)
send(8,144);assert(not view().preview and view().name=='Fire','real actions take precedence over the sample')
send(4,144);assert(view().preview)
now=now+4;casts.PreviewVisible(now);assert(view().kind=='skill','WS-enabled preview alternates action types')
now=now+.3;assert(not view(),'leaving the visible preview control stops the sample')
casts.Reset();assert(not casts.Preview[1]);os.clock=clock
H.print('Cast tracking: bounded packets/state, estimates, duplicate/late actions, spell/WS start/finish/interrupt, instant WS, identity, death/despawn/zone, disable and timeouts passed',true)
