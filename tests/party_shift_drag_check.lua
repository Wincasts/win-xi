-- Shift+drag: with Clickthrough off, a window is moved by holding Shift as it is clicked, the drag going on
-- until the mouse is let go; held still otherwise, with Clickthrough on, when linked or placed automatically,
-- and free while organizing.
H.load()
local options,windows=H.options(),require('windows')
local organize,imgui,bit=require('winxi.organize'),require('imgui'),require('bit')
options.fade.Enabled=false
options.automaticPositioning[1]=false
organize.SetActive(false)
organize.Place=function() end
organize.Track=function() end
-- the harness numbers imgui's flags one after another: NoMove a bit of its own, for its own to be seen
local noMove=ImGuiWindowFlags_NoMove
ImGuiWindowFlags_NoMove=0x100000
local begin,begun=imgui.Begin,nil
imgui.Begin=function(name,open,flags) begun=flags or 0; return begin(name,open,flags) end
local isDown,isClicked=imgui.IsMouseDown,imgui.IsMouseClicked
local shift,down,clicked=false,false,false
windows.ShiftHeld=function() return shift end
imgui.IsMouseDown=function() return down end
imgui.IsMouseClicked=function() return clicked end
local function Movable(window)
    windows.UpdatePositions()
    windows.Draw(window or windows.List.party2,function() end)
    return bit.band(begun,ImGuiWindowFlags_NoMove)==0
end

options.clickThrough[1]=false
assert(not Movable(),'Clickthrough off, no Shift: held still')
shift=true
assert(Movable(),'Shift held: can be dragged')
down,clicked=true,true
assert(Movable(),'clicked with Shift held: the drag begins')
shift,clicked=false,false
assert(Movable(),'Shift let go during the drag: it goes on')
down=false
assert(not Movable(),'mouse let go: held again')
down,clicked=true,true
assert(not Movable(),'clicked without Shift: no drag')
shift,clicked=true,false
assert(not Movable(),'Shift pressed after the click: still no drag')
down=false

options.clickThrough[1]=true
assert(not Movable(),'Clickthrough on: Shift does nothing')
options.clickThrough[1]=false

local isLinked=organize.IsLinked
organize.IsLinked=function(name) return name==windows.List.party3.name end
assert(not Movable(windows.List.party3),'a linked window goes where its link puts it')
organize.IsLinked=isLinked

options.automaticPositioning[1]=true
windows.UpdatePositions(250,80,200)
windows.Draw(windows.List.party2,function() end)
assert(bit.band(begun,ImGuiWindowFlags_NoMove)~=0,'automatically placed: not dragged, Shift or not')
options.automaticPositioning[1]=false

shift=false
organize.SetActive(true)
assert(Movable(),'organizing: dragged without Shift')
organize.SetActive(false)

imgui.Begin,ImGuiWindowFlags_NoMove=begin,noMove
imgui.IsMouseDown,imgui.IsMouseClicked=isDown,isClicked
H.print('Shift+drag: only with Clickthrough off, begun with Shift held and kept to the release; linked, automatic and clickthrough held; organizing free',true)
