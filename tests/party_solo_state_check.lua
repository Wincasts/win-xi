-- One-member party leaders are not solo: exercise real roster state and Present's label/visibility.
H.load()
local options,roster,windows=H.options(),require('roster'),require('windows')
local own,second,third,flags=1,0,0,0
local oldMemory=AshitaCore.GetMemoryManager
local memory=oldMemory()
local party={GetAlliancePartyMemberCount1=function() return own end,
    GetAlliancePartyMemberCount2=function() return second end,
    GetAlliancePartyMemberCount3=function() return third end,
    GetMemberFlagMask=function(_,index) assert(index==0); return flags end}
memory.GetParty=function() return party end
AshitaCore.GetMemoryManager=function() return memory end
require('winxi.game').IsHidden=function() return false end
require('game').StPartyIndex=function() return nil end
require('target').Indexes=function() return 0,0,0 end
options.party.enabled[1],options.target.enabled[1],options.pets.enabled[1]=true,false,false
options.party.showInvites[1],options.party.showTreasure[1]=false,false
options.automaticPositioning[1],options.showConfig[1],options.fade.Enabled=false,false,false
options.nativeParty[1],options.nativeTarget[1]=false,false
local draws=0
windows.Draw=function(window) if window==windows.List.party1 then draws=draws+1 end end
local function check(label,visible)
    local before=draws
    H.frames(1)
    assert(windows.List.party1.label==label,'wrong header for native party state: '..label)
    assert((draws>before)==visible,'wrong Hide When Solo behavior for '..label)
end
options.party.hideWhenSolo[1]=false
check('Solo',true)
flags=4; check('Party',true) -- everyone else has left; leader badge remains
options.party.hideWhenSolo[1]=true
check('Party',true) -- a one-member party must not be hidden as solo
flags=0; check('Solo',false) -- leave/disband with member count still one
options.party.hideWhenSolo[1]=false
check('Solo',true)
options.party.hideWhenSolo[1]=true
own=2; check('Party',true) -- ordinary non-leader party member
own,second=1,2; check('Alliance',true) -- alone in own alliance group, not solo
second,third=0,2; check('Alliance',true)
own,third,flags=0,0,4
local a,b,c,inParty=roster.Counts()
assert(a==0 and b==0 and c==0 and not inParty,'absent player is not a party from a stale leader flag')
check('Solo',false)
AshitaCore.GetMemoryManager=oldMemory
H.print('Solo state: one-member leader party, disband, Hide When Solo, alliance membership and absent player passed')
