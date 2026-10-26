-- Controller paths must release owned caches even when custom.Frame is bypassed.
local custom, plates = require('custom'), require('winxi.nameplates')
local filtered, badges, icons = require('filtered_text'), require('letter_badges'), require('icons')
local options = H.options()
local hook = { Hooked=1, Hidden=0, Options=0, Claimed=0 }
local connected, compatible, draws = true, true, 0
plates.Hook=function() return connected and hook or nil, 'unloaded' end
plates.Supports=function() return compatible end
plates.Claim=function(mask) hook.Claimed=mask end
local realFrame=custom.Frame
custom.Frame=function(o) draws=draws+1;return realFrame(o,nil) end -- activates lifecycle, no GPU fixture required
local released={text=0,badges=0,icons=0}
for _,entry in ipairs({{filtered,'text'},{badges,'badges'},{icons,'icons'}}) do
    local module,key=entry[1],entry[2]
    local release=module.Release
    module.Release=function() released[key]=released[key]+1;return release() end
end
H.frames(1)
local before,drawn=released.text,draws
options.drawNames[1]=false
H.frames(2)
assert(draws==drawn and released.text==before+1 and released.badges==1 and released.icons==1,
    'Enable Name off releases once, without dispatching Frame')
options.drawNames[1]=true;H.frames(1)
before,drawn=released.text,draws
-- Plugin loss invalidates the cached DLL writers before Name's own textures are released.
local invalidated=false
local clearDrawing=plates.ClearDrawing
plates.ClearDrawing=function(...) invalidated=true;return clearDrawing(...) end
connected=false;H.frames(2)
assert(invalidated, 'plugin loss invalidates the drawing')
plates.ClearDrawing=clearDrawing
assert(draws==drawn and released.text==before+1 and released.badges==2 and released.icons==2,
    'plugin loss releases once')
connected=true;H.frames(1)
before,drawn=released.text,draws
compatible=false
local printed=#H.printed
H.frames(3)
assert(draws==drawn and hook.Claimed==0 and released.text==before+1)
local warnings=0
for i=printed+1,#H.printed do
    if H.printed[i]:find('requires namehook 1.35',1,true) then warnings=warnings+1 end
end
assert(warnings==1, 'unsupported features leave native names and warn once')
compatible=true;H.frames(1)
assert(draws==drawn+1, 'compatible DLL resumes custom rendering')
before=released.text
H.resettle()
assert(released.text==before+1 and released.badges==4 and released.icons==4,
    'profile/settings changes also drop the previous profile caches')
custom.Deactivate()
assert(released.text==before+1, 'deactivation is idempotent')
local roles=require('roles')
local scans=0
local roster={GetMemberIsActive=function(_,slot) return slot<2 end,GetMemberServerId=function(_,slot) return slot+1 end}
local memory={GetParty=function() scans=scans+1;return roster end}
assert(roles.Begin(memory,true) and roles.Of(1))
assert(not roles.Begin(memory,false) and scans==1 and roles.Of(1)==nil,
    'formats without [party] skip party scans and clear old role state')
-- Unload must clear the published buffer/claim before Lua finalizes GPU owners.
realFrame(options,nil)
hook.Claimed=0xFF
before=released.text
invalidated=false
plates.ClearDrawing=function(...) invalidated=true;return clearDrawing(...) end
local release=filtered.Release
filtered.Release=function(...)
    assert(invalidated and hook.Claimed==0, 'unload must unpublish and release its claim before textures')
    return release(...)
end
H.unload()
assert(invalidated and released.text==before+1 and hook.Claimed==0,
    'unload deterministically releases owned textures even before the first native scene')
H.unload()
assert(released.text==before+1, 'repeated unload cleanup is idempotent')
H.print('Name lifecycle: off/loss/reload/unload release caches once, textured bars invalidate before freeing, claims relinquished',true)
