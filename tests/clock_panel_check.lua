-- Pure info-panel geometry, formatting, migration and icon-placement checks.
package.path = 'addons/clock/?.lua;addons/libs/?.lua;'..package.path
local panel = require('panel')
local fields = require('fields')
local function Near(a,b) assert(math.abs(a-b)<0.0001, tostring(a)..' ~= '..tostring(b)) end
local p = panel.Defaults()
panel.Complete(p)
local bounds = panel.Layout(p,10,20,606,24)
Near(bounds[1].left,13); Near(bounds[1].right,213)
Near(bounds[2].left,213); Near(bounds[3].right,613)
p.slots[1].weight[1]=2
bounds=panel.Layout(p,10,20,606,24)
Near(bounds[1].right-bounds[1].left,300)
Near(bounds[2].right-bounds[2].left,150)
Near(panel.Aligned(10,110,40,1),10)
Near(panel.Aligned(10,110,40,2),40)
Near(panel.Aligned(10,110,40,3),70)
Near(panel.Aligned(10,110,200,3),10) -- overflow clips from left
local context = {dayIcon=101,weatherIcon=102,weekday=0,weatherId=7,exp={level=75}}
assert(fields.IconTooltip('day',context):find('Firesday',1,true) and fields.IconTooltip('day',context):find('Fire',1,true))
assert(fields.IconTooltip('weather',context):find('Squalls',1,true) and fields.IconTooltip('weather',context):find('Water',1,true) and fields.IconTooltip('weather',context):find('Double',1,true))
assert(fields.IconTooltip('weather',{weatherId=6}):find('Single',1,true))
assert(fields.IconTooltip('weather',{weatherId=0}):find('No elemental weather',1,true))
assert(fields.IconTooltip('weather',{}):find('Unknown',1,true))
p.slots[1].format='{dayicon} | {level}'
p.slots[2].format='Center'; p.slots[3].format='Right'
local slots=panel.Build(p,fields,context)
assert(slots[1][1].icon==101 and slots[1][1].kind=='day' and slots[1][1].tooltip:find('Firesday',1,true))
assert(slots[3][#slots[3]].tooltip:find('Squalls',1,true),'automatically placed icons also carry tooltip metadata')
local dividers,days=0,0
for _,s in ipairs(slots[1]) do
    if type(s)=='table' then
        if s.separator then dividers=dividers+1 end
        if s.icon==101 then days=days+1 end
    end
end
assert(dividers==1 and days==1,'styled pipe and no duplicate automatic day icon')
assert(slots[3][#slots[3]].icon==102,'weather after right-slot data')
p.dayPlace[1]=4; p.dayAfter[1]=true; p.slots[1].format='Left'
slots=panel.Build(p,fields,context)
assert(slots[2][#slots[2]].icon==101,'day moved after middle-slot data')
p.weatherPlace[1]=1
slots=panel.Build(p,fields,context)
assert(#slots[3]==1,'hidden weather is not auto inserted')
p.weatherPlace[1]=2
slots=panel.Build(p,fields,context)
assert(#slots[3]==1,'native weather is not auto inserted')
local missing=panel.Segments(fields,{exp=nil,weather='Rain'},'{level} | {weather}')
assert(#missing==1 and missing[1]=='Rain','empty field removes styled divider')
local corrupt={ width={0/0}, height={math.huge}, slots={{format=false,align={8},weight={-1}}} }
panel.Complete(corrupt)
assert(corrupt.width[1]==0 and corrupt.height[1]==0 and corrupt.slots[1].align[1]==3)
assert(corrupt.slots[1].weight[1]==0.1 and #corrupt.slots==3)
assert(corrupt.slots[1].format==panel.Defaults().slots[1].format)
-- Zone field: one lookup per shared sample, safe during zoning/resource failures.
local core = AshitaCore
local zone, zoneName, lookups = 100, 'West Ronfaure', 0
AshitaCore = {
    GetMemoryManager=function() return {GetParty=function() return {
        GetMemberZone=function(_,index) assert(index==0); return zone end,
    } end} end,
    GetResourceManager=function() return {GetString=function(_,key,id)
        assert(key=='zones.names' and id==100); lookups=lookups+1
        if zoneName==false then error('resources unavailable') end
        return zoneName
    end} end,
}
local z = {}
assert(fields.Line(z,'{zone} | {zone}')=='West Ronfaure | West Ronfaure' and lookups==1)
zoneName=''; assert(fields.Line({},'{zone}')=='Zone 100')
zoneName=false; assert(fields.Line({},'{zone}')=='Zone 100')
zone=0; assert(fields.Line({},'{zone} | {weather}')=='')
assert(fields.Line({weather='Rain'},'{zone} | {weather}')=='Rain','zone unavailable removes divider')
zone=0/0; assert(fields.Line({},'{zone}')=='')
AshitaCore = nil; assert(fields.Line({},'{zone}')=='','missing game memory is safe')
AshitaCore = core

-- Drawing contract: content is clipped per slot and vertically centred; icon offsets
-- do not change neighbouring slots or the panel's requested dimensions.
local texts, images, lines, clips = {}, {}, {}, 0
local list = {
    AddText=function(_,at,_,words) texts[#texts+1]={at[1],at[2],words} end,
    AddImage=function(_,handle,a,b) images[#images+1]={handle,a[1],a[2],b[1],b[2]} end,
    AddLine=function(_,a,b) lines[#lines+1]={a[1],a[2],b[1],b[2]} end,
    AddTriangleFilled=function() end,
    PushClipRect=function() clips=clips+1 end, PopClipRect=function() end,
}
local mouse={x=-1,y=-1}
package.loaded.imgui = { GetIO=function() return {MousePos=mouse} end,
    GetWindowDrawList=function() return list end, GetFontSize=function() return 14 end,
    GetColorU32=function() return 123 end, CalcTextSize=function(text) return #text*7 end, Dummy=function() end }
package.loaded['winxi.theme'] = { GameBorderColor=function() return {1,1,1,1} end }
package.loaded['winxi.text'] = {Draw=function(list,x,y,color,words) list:AddText({x,y},123,words) end} -- the edge is the theme's
p=panel.Defaults(); p.dayPlace[1]=1; p.weatherPlace[1]=1
panel.Draw(p,{{'a'},{'bb'},{'ccc'}},{left=10,top=20,width=306,height=24},
    {textColor={1,1,1,1},iconScale={1},weatherScale={1},iconOffset={0},outline={0}})
Near(texts[1][1],17); Near(texts[2][1],156); Near(texts[3][1],288)
Near(texts[1][2],25); assert(clips==3 and #lines==4,'independent slot clips and beveled boundaries')
p.dayX[1]=4; p.dayY[1]=-2
panel.Draw(p,{{{icon=101,kind='day'}},{},{}},{left=10,top=20,width=306,height=24},
    {textColor={1,1,1,1},iconScale={1},weatherScale={1},iconOffset={0},outline={0}})
assert(images[1][1]==101); Near(images[1][2],21); Near(images[1][3],23)
local tips={}
local opts={textColor={1,1,1,1},iconScale={1},weatherScale={1},iconOffset={0},reserve=false,
    tooltip=function(text) tips[#tips+1]=text end}
local iconSlots={{{icon=101,kind='day',tooltip='Firesday'}},{},{}}
mouse.x,mouse.y=22,24
panel.Draw(p,iconSlots,{left=10,top=20,width=306,height=24},opts)
assert(#tips==1 and tips[1]=='Firesday','hover follows actual icon offsets')
mouse.x,mouse.y=18,24
panel.Draw(p,iconSlots,{left=10,top=20,width=306,height=24},opts)
assert(#tips==1,'old unshifted area does not trigger tooltip')
p.dayX[1]=-10
mouse.x,mouse.y=10,24
panel.Draw(p,iconSlots,{left=10,top=20,width=306,height=24},opts)
assert(#tips==1,'clipped-off icon area does not trigger tooltip')
mouse.x,mouse.y=18,24
panel.Draw(p,iconSlots,{left=10,top=20,width=306,height=24},opts)
assert(#tips==2,'visible clipped icon area can still trigger tooltip')
print('Info panel: slots, weights, alignment, styled pipes, rendering, icon offsets, tooltip metadata/hit regions and settings validation passed')
