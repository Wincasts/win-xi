-- Real background, border and shadow modules, attached to a host's list with explicit geometry.
package.path='addons/libs/?.lua;'..package.path
local look={BackgroundStyle='gradient',BackgroundColor={0.1,0.2,0.3,0.8},BorderStyle='silver',BorderOpacity=75,
    BorderColor={1,1,1,1},ShadowEnabled=true,ShadowOpacity=50,ShadowOffset=4,ShadowBlur=3}
package.loaded['winxi.theme']={Get=function() return look end,GameBorderColor=function() return look.BorderColor end}
package.loaded.d3d8={get_device=function() return nil end}
local events,depth,geometryReads={},0,0
local list={PushClipRect=function(_,a,b,intersect) depth=depth+1; events[#events+1]={'clip',a[1],a[2],b[1],b[2],intersect} end,
    PopClipRect=function() depth=depth-1 end,
    AddRectFilled=function(_,a,b) events[#events+1]={'flat',a[1],a[2],b[1],b[2]} end,
    AddRectFilledMultiColor=function(_,a,b) events[#events+1]={'gradient',a[1],a[2],b[1],b[2]} end,
    AddImage=function(_,handle,a,b) events[#events+1]={'image',a[1],a[2],b[1],b[2],handle} end,
    AddRect=function(_,a,b) events[#events+1]={'border',a[1],a[2],b[1],b[2]} end}
package.loaded.imgui={GetWindowDrawList=function() return list end,GetIO=function() return {DisplaySize={x=1280,y=720}} end,
    GetWindowPos=function() geometryReads=geometryReads+1; return 500,500 end,
    GetWindowSize=function() geometryReads=geometryReads+1; return 600,100 end,
    GetStyle=function() return {WindowRounding=3} end,GetColorU32=function(c) return c end}
local borders=require('winxi.borders'); borders.Load=function() return 99 end
local frame=require('winxi.frame')
local rect={left=20,top=100,width=640,height=24}
frame.Draw(rect,function() events[#events+1]={'content'} end)
assert(depth==0 and geometryReads==0,'attachment never reads/modifies host geometry')
local gradient,content,border=false,0,0
for i,event in ipairs(events) do
    if event[1]=='gradient' then assert(event[2]==20 and event[3]==100 and event[4]==660 and event[5]==124); gradient=true end
    if event[1]=='content' then content=i end
    if event[1]=='image' then assert(i>content and event[6]==99); border=border+1 end
end
assert(gradient and border==8,'theme gradient and eight border slices surround content')
assert(events[1][1]=='clip' and events[1][6]==false,'attachment opens host content clip before drawing')
look.BackgroundStyle='plain'; look.BorderStyle='theme'; look.ShadowEnabled=false; events={}
frame.Draw(rect,function() end)
assert(depth==0 and #events==3 and events[2][1]=='flat' and events[3][1]=='border','plain frame and border need no separate ImGui window')
local ok=pcall(frame.Draw,rect,function() error('render failure') end)
assert(not ok and depth==0,'attachment restores clip after failed content')
print('Winxi frame: explicit-rect background, border, captured shadow, host isolation and error cleanup passed')
