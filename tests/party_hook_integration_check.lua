-- Through Party's harness: only actual party windows are handed to C++, while still current.
H.load()
local options, windows = H.options(), require('windows')
local imgui, roster = require('imgui'), require('roster')
local game, organize = require('winxi.game'), require('winxi.organize')
assert(options.nativeParty[1] == false and options.nativeTarget[1] == false and options.nativeHook[1] == false, 'existing installs must not opt in automatically')
local begin, finish = imgui.Begin, imgui.End
local stack, captured, stopped, emptyFrames = {}, {}, 0, 0
local begun={}
imgui.Begin = function(name, ...)
    begun[name]=(begun[name] or 0)+1
    stack[#stack+1] = name
    return begin(name, ...)
end
imgui.End = function(...)
    local result = finish(...)
    stack[#stack] = nil
    return result
end
local shadow = require('winxi.shadow')
local drawShadow, shadowed = shadow.Draw, {}
shadow.Draw = function(native)
    local name = stack[#stack]
    assert(name, 'shadow drawn inside its window')
    shadowed[name] = native and 'captured' or 'ordinary'
    return drawShadow(native)
end
local active, partyActive, targetActive = false, false, false
package.loaded.hook = {
    Begin=function(party, target)
        partyActive, targetActive = party, target
        active=party or target
        if active then emptyFrames=emptyFrames+1 else stopped=stopped+1 end
        return active
    end,
    Stop=function() active=false; stopped=stopped+1 end,
    Uses=function(window) return (window.group=='party' and partyActive) or (window.group=='target' and targetActive) end,
    Disable=function(target) if target then targetActive=false else partyActive=false end end,
    Capture=function(window)
        assert(active and stack[#stack]==window.name, 'capture must be inside its own real window, not anchor measurement')
        assert(shadowed[window.name]=='captured', 'native shadow must be on the captured list before submission')
        captured[window.name]=(captured[window.name] or 0)+1
        return true
    end,
    Status=function() return 'test plugin' end,
}
roster.Counts=function() return 6,6,6 end
roster.Members=function(list)
    return {{name='Member '..list, serverId=100+list, isInZone=true, hpp=80, hp=1000,
        mpp=50, mp=500, tp=1000, statusIds={}, jobText='[WAR15/RDM7]'}}
end
require('target').Indexes=function() return 0,0,0 end
options.party.enabled[1]=true
options.pets.enabled[1]=false
options.party.hideWhenSolo[1]=false
options.party.showInvites[1]=false; options.party.showTreasure[1]=false
options.fade.Enabled=false
options.nativeHook[1],options.nativeParty[1]=true,true
options.showConfig[1]=false
game.IsHidden=function() return false end
organize.IsActive=function() return false end
H.frames(1)
for i=1,3 do assert(captured['xiframes.us.'..i]==1,'each real party/alliance list captured exactly once') end
-- Combat menus must suppress clicks without suppressing read-only status hover.
local menuName, mousePos = game.MenuName, imgui.GetMousePos
local details = require('details')
local clickThrough = options.clickThrough[1]
options.clickThrough[1] = false
imgui.GetMousePos = function() return 20, 30 end
game.MenuName = function() return 'menu battle' end
H.frames(1)
assert(windows.BlockNativeInputs, 'combat menu still blocks native window clicks')
assert(details.Hover(0, 0, 40, 50), 'combat menu must not block status tooltip hover')
options.clickThrough[1] = true
H.frames(1)
assert(details.Hover(0, 0, 40, 50), 'clickthrough lets clicks through, not hover')
options.clickThrough[1] = clickThrough
game.MenuName, imgui.GetMousePos = menuName, mousePos
windows.Draw(windows.List.main, function() end)
assert(captured['xiframes.tgt.main']==nil and #stack==0,'target untouched, ImGui stack balanced')
assert(shadowed['xiframes.tgt.main']=='ordinary', 'unhooked target retains the background-list shadow')
local before=stopped
organize.IsActive=function() return true end
H.frames(1)
assert(stopped>before and windows.Capture==nil,'organize uses ordinary interactive windows')
assert(shadowed['xiframes.us.1']=='ordinary', 'organize restores ordinary shadows')
organize.IsActive=function() return false end
before=stopped
local previousEmpty, previousCaptures=emptyFrames, captured['xiframes.us.1']
game.IsHidden=function() return true end
H.frames(5) -- longer than the plugin's two-frame freshness timeout
assert(stopped==before and emptyFrames==previousEmpty+5 and active,
    'expanded chat/map/interface hiding renews empty replacements instead of restoring stock lists')
assert(windows.Capture==nil and captured['xiframes.us.1']==previousCaptures,
    'hidden frames do not capture window geometry')
game.IsHidden=function() return false end
H.frames(1)
assert(captured['xiframes.us.1']==previousCaptures+1 and windows.Capture,
    'closing chat resumes replacement drawing')
options.nativeParty[1]=false
H.frames(1)
assert(windows.Capture==nil and stopped>before,'disabled setting restores ordinary rendering')
options.nativeParty[1]=true
options.party.enabled[1]=false
game.IsHidden=function() return true end
before=stopped
H.frames(1)
assert(stopped>before and not active,'disabling Party relinquishes native lists even while chat is expanded')
-- Independent target opt-in, including all three windows in the same native target group.
H.command('/pt native target on')
assert(options.nativeTarget[1] and options.nativeParty[1], 'target command does not change party preference')
options.target.enabled[1]=true
options.target.showMain[1], options.target.showSub[1], options.target.showTot[1] = true, true, true
require('target').Indexes=function() return 10,11,12 end
local entities={}
for i=10,12 do entities[i]={Name='Target '..i,Distance=64,HPPercent=80,ServerId=1000+i} end
GetEntity=function(index) return entities[index] end
game.IsHidden=function() return false end
H.frames(1)
assert(targetActive and not partyActive, 'target replacement works while party is disabled')
for _,key in ipairs({'main','sub','tot'}) do
    assert(captured[windows.List[key].name]==1, 'actual target content captured once while current')
end
assert(not windows.Native(windows.List.party1) and windows.Native(windows.List.main), 'only enabled group is native-rendered')
previousEmpty=emptyFrames
local mainCaptures=captured['xiframes.tgt.main']
game.IsHidden=function() return true end
H.frames(5)
assert(emptyFrames==previousEmpty+5 and targetActive and windows.Capture==nil
    and captured['xiframes.tgt.main']==mainCaptures, 'hidden target group receives empty frames past timeout')
game.IsHidden=function() return false end
organize.IsActive=function() return true end
H.frames(1)
assert(not active and windows.Capture==nil,'organize relinquishes target as well as party')
-- Optional default behavior changes only native-rendered groups; custom styling remains in use.
organize.IsActive=function() return false end
options.party.enabled[1],options.nativeBehavior[1],options.party.hideWhenSolo[1],options.party.sortByRole[1]=true,true,true,true
options.fade.Enabled=true
options.fade.Delay,options.fade.Duration,options.fade.Opacity=0,0,0
roster.Counts=function() return 1,0,0 end
local members=roster.Members
roster.Members=function(list,sample,sorted,...)
    assert(not sorted,'native behavior keeps the client party order even if role sorting is configured')
    return members(list,sample,sorted,...)
end
game.IsLoading=function() return false end
game.IsHidden=function() return true end
local priorParty,priorTarget=captured['xiframes.us.1'],captured['xiframes.tgt.main']
H.frames(3)
assert(captured['xiframes.us.1']==priorParty+3 and captured['xiframes.tgt.main']==priorTarget+3,
    'native behavior submits solo party and targets despite custom hide/idle rules; client controls actual drawing')
assert(not windows.IsFadedOut('party') and not windows.IsFadedOut('target') and not windows.Lingers(windows.List.main),
    'native groups do not inherit addon idle/presence fading')
game.IsLoading=function() return true end
priorParty,priorTarget=captured['xiframes.us.1'],captured['xiframes.tgt.main']
previousEmpty=emptyFrames
H.frames(2)
assert(emptyFrames==previousEmpty+2 and captured['xiframes.us.1']==priorParty and captured['xiframes.tgt.main']==priorTarget,
    'loading still renews empty native submissions without polling/drawing entities')
game.IsLoading=function() return false end
for _,name in ipairs({'IsInterfaceHidden','IsEventHappening'}) do
    game[name]=function() return true end
    H.frames(1)
    assert(captured['xiframes.us.1']==priorParty and captured['xiframes.tgt.main']==priorTarget,
        'native behavior never draws through interface hiding/cutscenes')
    game[name]=function() return false end
end
options.nativeTarget[1]=false
local mainBegun=begun['xiframes.tgt.main']
H.frames(1)
assert(captured['xiframes.us.1']==priorParty+1 and begun['xiframes.tgt.main']==mainBegun,
    'ordinary target group still obeys custom hide rules when only party follows native behavior')
game.IsHidden=function() return false end
options.hide.WithInterface=false
options.fade.Enabled=false
game.IsInterfaceHidden=function() return true end
mainBegun=begun['xiframes.tgt.main']; priorParty=captured['xiframes.us.1']
H.frames(1)
assert(captured['xiframes.us.1']==priorParty and begun['xiframes.tgt.main']>mainBegun,
    'hard native guard does not change an ordinary group with explicitly overridden hide rules')
game.IsInterfaceHidden=function() return false end
H.command('/pt native target off')
assert(not options.nativeTarget[1] and options.nativeParty[1],'target-off preserves party setting')
priorParty=captured['xiframes.us.1']
options.nativeHook[1]=false
H.frames(1)
assert(captured['xiframes.us.1']==priorParty,'Hook Into uihook off: Party ticked, but nothing hooked')
options.nativeHook[1]=true
H.print('Party native integration: six HUD windows, independent target opt-in, empty hidden frames, native behavior/loading guards, resume, organize and command routing passed')
