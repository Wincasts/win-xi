-- Clickthrough lets clicks through, not hovering: the windows' tooltips still show, unless another imgui
-- window over them wants the mouse; hidden windows hover nothing; a target's debuff letters are hovered by
-- their rect, as imgui does not hover a window the mouse goes through.
H.load()
local imgui,details=require('imgui'),require('details')
local getIO,mousePos=imgui.GetIO,imgui.GetMousePos
local io={ DisplaySize={ x=1920, y=1080 }, WantCaptureMouse=false }
imgui.GetIO=function() return io end
imgui.GetMousePos=function() return 30,30 end

details.BeginFrame(true,true)
assert(details.Hover(10,20,60,38),'Clickthrough on: hovered')
details.BeginFrame(true,false)
assert(details.Hover(10,20,60,38),'Clickthrough off: hovered')
io.WantCaptureMouse=true
details.BeginFrame(true,true)
assert(not details.Hover(10,20,60,38),'Clickthrough on, another window over them wants the mouse: not hovered')
details.BeginFrame(true,false)
assert(details.Hover(10,20,60,38),'Clickthrough off: their own window wanting the mouse is them')
io.WantCaptureMouse=false
details.BeginFrame(false,true)
assert(not details.Hover(10,20,60,38),'hidden: nothing hovered')

-- a debuff letter (the harness gives every item the rect 10,20 to 60,38), not through IsItemHovered
local tracker=require('winxi.debuffs')
local shown=nil
local status=details.Status
details.Status=function(id) shown=id end
local isItemHovered=imgui.IsItemHovered
imgui.IsItemHovered=function() error('debuff letters are hovered by their rect') end
local get=tracker.Get
tracker.Get=function() return {} end
details.BeginFrame(true,true)
require('debuffs').Draw(1234,true)
assert(shown~=nil,'Clickthrough on: a debuff letter under the mouse shows its status')
shown=nil
imgui.GetMousePos=function() return 500,500 end
details.BeginFrame(true,true)
require('debuffs').Draw(1234,true)
assert(shown==nil,'mouse elsewhere: no status')
tracker.Get,details.Status,imgui.IsItemHovered=get,status,isItemHovered
imgui.GetIO,imgui.GetMousePos=getIO,mousePos
H.print('Clickthrough hover: tooltips through clickthrough, not under another window or while hidden; debuff letters by rect',true)
