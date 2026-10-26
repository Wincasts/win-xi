-- Testing build: native anchoring is hidden and disabled, including older saved opt-ins.
H.load()
local options,windows=H.options(),require('windows')
local placement,organize=require('nativeposition'),require('winxi.organize')
local imgui=require('imgui')
local x,y=options.party.pos1[1],options.party.pos1[2]
local cx,cy=options.party.corner1[1],options.party.corner1[2]
local links=options.links
options.nativePositioning[1]=true
require('options').Complete(options)
assert(not options.nativePositioning[1],'old saved native placement must be forced off')
assert(options.party.pos1[1]==x and options.party.pos1[2]==y
    and options.party.corner1[1]==cx and options.party.corner1[2]==cy and options.links==links,
    'disabling the feature must preserve manual positions/corner/links')
options.nativeParty[1],options.nativeTarget[1],options.nativePositioning[1]=true,true,true
options.nativeHook=nil
require('options').Complete(options)
options.nativePositioning[1]=true
options.party.enabled[1],options.target.enabled[1]=true,true
options.nativeAlliance2[1],options.nativeAlliance3[1]=false,false
for _,key in ipairs({'party1','party2','party3','main','sub','tot'}) do
    assert(not placement.Enabled(options,key) and not placement.ManualOverride(options,key),
        'runtime/saved flags must not reactivate native anchoring or override automatic/manual layout')
end
windows.Native=function() return true end
windows.NativeRect=function() error('parked positioning must not query native rectangles') end
options.fade.Enabled=false
organize.SetActive(false)
local places,moves=0,0
organize.Place=function() places=places+1 end
organize.Track=function() end
imgui.SetWindowPos=function() moves=moves+1 end
local bit,begun=require('bit'),nil
-- the harness numbers imgui's flags one after another: NoMove a bit of its own, for its own to be seen
local noMove=ImGuiWindowFlags_NoMove
ImGuiWindowFlags_NoMove=0x100000
local begin=imgui.Begin
imgui.Begin=function(name,open,flags) begun=flags or 0; return begin(name,open,flags) end
options.automaticPositioning[1]=false
-- with Clickthrough off and Shift held, as a manual window is dragged
options.clickThrough[1]=false
local shiftHeld=windows.ShiftHeld
windows.ShiftHeld=function() return true end
windows.UpdatePositions()
windows.Draw(windows.List.party2,function() end)
assert(places==1 and moves==0,'ordinary manual placement remains in use')
assert(bit.band(begun,ImGuiWindowFlags_NoMove)==0,'a manually placed window can be dragged')
options.automaticPositioning[1]=true
windows.UpdatePositions(250,80,200)
windows.Draw(windows.List.party2,function() end)
assert(places==1 and moves==1,'old native flags do not disable ordinary automatic placement')
-- placed after Begin, so a drag would lay it and its clip out where it was taken, the window drawn back in
-- its place cut to that clip: not to be dragged
assert(bit.band(begun,ImGuiWindowFlags_NoMove)~=0,'an automatically placed window cannot be dragged')
imgui.Begin,ImGuiWindowFlags_NoMove=begin,noMove
windows.ShiftHeld=shiftHeld
local widgets=require('winxi.widgets')
local headers={}
widgets.Header=function(text) headers[#headers+1]=text; return true end
local checks={}
imgui.Checkbox=function(id)
    assert(not id:find('nativePositioning',1,true) and not id:find('nativeAlliance',1,true),
        'parked native placement controls must not be displayed')
    checks[id]=true
    return false
end
package.loaded.hook={Status=function() return 'Native replacement ready.' end}
local behavior=require('config').Tabs[1].draw
assert(options.nativeHook[1],'settings from before the toggle keep their hooked windows hooked')
H.loaded('uihook',true)
options.nativeHook[1]=false
behavior(options)
assert(checks['##party.nativeHook'] and not checks['##party.nativeParty'],
    'uihook found: the toggle alone until it is on')
options.nativeHook[1]=true
checks={}
behavior(options)
assert(checks['##party.nativeHook'] and checks['##party.nativeParty'] and checks['##party.nativeTarget'] and checks['##party.nativeBehavior'],
    'hooking on: which windows it hooks')
assert(headers[#headers]=='uihook','uihook is the last section of Behavior')
-- Use uihook, untagged; every explanation behind a (?); the plugin and its version in green after the
-- title; no status line
local labels,marks,colored,wrapped={},0,{},0
local label,disabled,textColored,textWrapped=widgets.Label,imgui.TextDisabled,imgui.TextColored,imgui.TextWrapped
local getManager=AshitaCore.GetPluginManager
widgets.Label=function(text,experimental) labels[text]=experimental or false end
imgui.TextDisabled=function(text) if text=='(?)' then marks=marks+1 end end
imgui.TextColored=function(color,text) colored[#colored+1]={color,text} end
imgui.TextWrapped=function() wrapped=wrapped+1 end
AshitaCore.GetPluginManager=function(self)
    local manager=getManager(self)
    manager.Get=function(_,name) return name=='uihook' and { GetVersion=function() return 1.6 end } or nil end
    return manager
end
behavior(options)
assert(labels['Use uihook']==false and labels['Hook Into uihook']==nil,'Use uihook, not experimental')
assert(marks==4,'a (?) for each uihook setting: '..marks)
local found=colored[#colored]
assert(found and found[2]=='[uihook 1.60 found]' and found[1][2]>found[1][1] and found[1][2]>found[1][3],'the plugin found, in green')
assert(wrapped==0,'no native rendering status line')
AshitaCore.GetPluginManager=getManager
colored={}
behavior(options)
assert(colored[#colored][2]=='[uihook found]','no version to be had: the plugin alone')
widgets.Label,imgui.TextDisabled,imgui.TextColored,imgui.TextWrapped=label,disabled,textColored,textWrapped
H.loaded('uihook',false)
checks={}
behavior(options)
assert(not checks['##party.nativeHook'] and not checks['##party.nativeParty'],'uihook not loaded: no uihook section')
assert(options.nativeHook[1] and options.nativeParty[1],'its choices kept')
H.print('Native positioning parked: saved opt-in cleared, runtime gating enforced, controls hidden, manual/automatic layout preserved')
