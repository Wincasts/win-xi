-- Standalone addon integration: real model, stub UI/native callbacks. No FFXI needed.
package.path = 'addons/chatbox/?.lua;addons/libs/?.lua;' .. package.path
addon = {}
T = function(t) return t end
package.loaded.common = true
local events, app, spec = {}, nil, nil
local saves = 0
ashita = { events = { register = function(event, _, callback) events[event] = callback end } }
local inputOpen, inputRaw, inputDisplay, inputCaret = false, '', '', 0
local inputSet
AshitaCore = { GetChatManager=function() return {
    IsInputOpen=function() return inputOpen and 0x11 or 0 end,
    GetInputTextRaw=function() return inputRaw end,
    GetInputTextDisplay=function() return inputDisplay end,
    GetInputTextRawCaretPosition=function() return inputCaret end,
    SetInputText=function(_,value) inputSet=value end,
} end }
local flags = 0
setmetatable(_G, {__index=function(_, key)
    if key:match('^ImGui') then flags=flags+1; rawset(_G,key,flags); return flags end
end})
local ready, captureOK, drawn, throwing = true, true, true, false
local hooks, sequence = {}, {}
local currentPanelDrawn=false
local nativeRect, lastWindowStyle
local rendered = {}
local nativeLogRect = {20,700,660,1018}
local expandedRect={0,100,1920,1020}
local chatState={selected=false,expanded=false,expandedSupported=true,nativeBrowse=false,nested=false,nativeContent=true,nativeControls=true,nativeReplace=true,nativeText=true}
local tabsGeometry, scrollGeometry, rowsGeometry -- where the game drew its tabs, scrollbar and rows of text, as uihook measured them
local splitRect, routes -- the game's second log window, and its routing between the two, as uihook reads them
local linesState={} -- each window's lines as the game has them, by slot
local gameColors -- the game's colours, as uihook reads them
-- the game's own history as uihook reads it: nothing to start with, so the tests' messages are their own
local gameLines, historyRequests = {}, 0
-- each chat line as uihook records it after every addon: not there until a test says so, then whatever lines the
-- test puts in tapLines are drained at the next frame
local tapReady,tapLines=false,nil
package.loaded['winxi.nativetext']={new=function() return {
    Ready=function() return tapReady end,
    Drain=function() if not tapReady then return nil end; local l=tapLines or {}; tapLines=nil; return l end,
    Status=function() return tapReady and 'test tap' or 'Load uihook 0.8 or newer to read each chat line after every addon.' end,
} end}
package.loaded['winxi.nativehistory']={new=function() local asked=false; return {
    Request=function() asked=true; historyRequests=historyRequests+1; return true end,
    Lines=function() if not asked then return nil end; asked=false; return gameLines end,
    Status=function() return 'test history' end,
} end}
-- the full log placed where chatbox asks (Expand In Place): its bottom-left, or nil once given back
local logPlace, logStops = nil, 0
package.loaded['winxi.nativemenus']={new=function() return {
    Set=function() return true end, Stop=function() end, Status=function() return 'test menus' end,
    PlaceLog=function(left,bottom) logPlace={left,bottom}; return true end,
    StopLog=function() if logPlace then logStops=logStops+1 end; logPlace=nil end,
} end}
package.loaded['winxi.nativechat'] = { Primary=0,Secondary=1,Input=2,new=function(index)
    local hook = {begins=0,stops=0,captures=0}
    function hook.Begin() hook.begins=hook.begins+1; return ready end
    function hook.Stop() hook.stops=hook.stops+1 end
    function hook.Capture(expanded,controls,replace)
        hook.expanded,hook.controls=expanded,controls
        hook.replace=replace and {tabs=replace.tabs,scrollbar=replace.scrollbar,text=replace.text,all=replace.all} or nil
        assert(sequence[#sequence] == 'border', 'parent title/border drawn after attachment, before capture')
        hook.panel = currentPanelDrawn
        hook.captures=hook.captures+1; return captureOK
    end
    function hook.Status() return 'test hook' end
    function hook.Ages() return 0, 0 end
    function hook.Tabs() return index==0 and tabsGeometry or nil end
    function hook.Scrollbar() return index==0 and scrollGeometry or nil end
    function hook.Rows() return index==0 and rowsGeometry or nil end
    function hook.State()
        local state={}
        for k,v in pairs(chatState) do state[k]=v end
        if state.selected and state.selectedWindow==nil then state.selectedWindow=1 end -- as the real bridge: a focused window is 1 or 2
        return state
    end
    function hook.Routes() return index==0 and routes or nil end
    function hook.Lines() return linesState[index] end
    function hook.Colors() return index==0 and gameColors or nil end
    function hook.Rect(_,_,expanded)
        local rect
        if index==0 then rect=expanded and expandedRect or (not expanded and nativeLogRect or nil)
        elseif index==1 then rect=not expanded and splitRect or nil
        elseif index==2 then rect=nativeRect end
        if rect then return unpack(rect) end
    end
    hooks[index]=hook; return hook
end, Shows=function(r, window, mode)
    mode=tonumber(mode) or 0
    if not r or not r.split then return window==1 end
    if bit.band(mode,0x8000)~=0 then return window==1 end
    local set=window==1 and r.first or window==2 and r.second or nil
    return set~=nil and set[bit.band(mode,0xff)]==true
end }
local look = { Padding=12,TextColor={1,1,1,1},HighlightColor={0.2,0.4,0.8,0.6} }
package.loaded['winxi.theme'] = { Get=function() return look end }
local fontDepth, pushedFonts, pushedSizes = 0, {}, {}
package.loaded['winxi.fonts'] = {Push=function() return false end,Pop=function() end,
    Get=function(file) if file and file~='' then return 'font:'..file end end, Files=function() return {'arial.ttf'} end}
local headers = {}
package.loaded['winxi.widgets'] = {Header=function(name) return headers[name] end, Label=function() end, FontFile=function() return false end, FontSize=function() return false, false end}
local binding
package.loaded['winxi.controller'] = {HighlightColor={0.23,0.67,0.91,1}, RepeatDelay=0.35, RepeatRate=0.08,
    Button={DpadUp=0,DpadDown=1,A=12}, Bind=function(spec) binding=spec; return spec end}
local images = {}
package.loaded['winxi.style'] = {Background=function() return 'tile' end}
local labels, overs, lines = {}, {}, {}
package.loaded['winxi.tabs'] = {Over=function(_,l,t,r,b,radius) overs[#overs+1]={l,t,r,b,radius} end,
    Line=function(_,l,r,y,cl,cr) lines[#lines+1]={l,r,y,cl,cr} end}
package.loaded['winxi.text'] = {Draw=function(_,x,y,color,words) labels[#labels+1]={x=x,y=y,color=color,text=words} end}
package.loaded['winxi.cursor'] = {Get=function() return 99, {0,0,1,1,16,12} end}
package.loaded['winxi.shell'] = {New=function(s)
    spec=s
    app={options=s.defaults,save=function() saves=saves+1 end,Say=function() end,BeginFrame=function() end}
    s.onSettings(app.options)
    return app
end}
package.loaded.encoding = { Decode=function(raw) if raw=='bad' then error('bad encoding') end; return raw end }
local decodes = 0
local plainDecodeStub = package.loaded.encoding.Decode
package.loaded.encoding.Decode = function(raw, ...) decodes = decodes + 1; return plainDecodeStub(raw, ...) end
local text, measured, measuredPos, measuredSize = {}, 0, nil, nil
local dummy
local outlines={}
local styleDepth = 0
local filled={}
local list = { AddText=function(_,pos,color,value) text[#text+1]={pos=pos,color=color,text=value} end,
    AddRect=function(_,a,b,color) outlines[#outlines+1]={a=a,b=b,color=color} end,
    AddRectFilled=function(_,a,b,color) filled[#filled+1]={a=a,b=b,color=color} end,
    AddImage=function(_,handle,a,b) images[#images+1]={handle=handle,a=a,b=b} end,
    AddLine=function() end,PushClipRect=function() end,PopClipRect=function() end }
local fontSize, screen = 14, {x=1920,y=1080}
local imgui = {
    GetIO=function() return { DisplaySize=screen, MousePos=mouseAt and {x=mouseAt[1],y=mouseAt[2]} or nil } end,
    GetFontSize=function() return fontSize end,
    GetFont=function() return 'font' end,
    CalcTextSize=function(value) measured=measured+1; return #value*7, fontSize end,
    GetCursorScreenPos=function() return 32,100 end,
    GetWindowDrawList=function() return list end,
    GetColorU32=function(color) return color end,
    SetNextWindowPos=function(pos,_,pivot) measuredPos={pos[1],pos[2],pivot[1],pivot[2]} end,
    SetNextWindowSize=function(size) measuredSize={size[1],size[2]} end,
    Dummy=function(size) dummy={size[1],size[2]} end,
    PushStyleVar=function() styleDepth=styleDepth+1 end,
    PushFont=function(font,size) fontDepth=fontDepth+1; pushedFonts[#pushedFonts+1]=font; pushedSizes[#pushedSizes+1]=size end,
    PopFont=function() fontDepth=fontDepth-1 end,
    IsItemHovered=function() return false end,
    PopStyleVar=function(n) styleDepth=styleDepth-(n or 1) end,
}
package.loaded.imgui=imgui
local function Window(name,_,_,draw,options)
    lastWindowStyle=options
    rendered[name]={pos=measuredPos,size=measuredSize,style=options}
    local previousFont=fontSize
    fontSize=options.fontSize or fontSize
    if throwing then error('draw failed') end
    if not drawn then return false end
    currentPanelDrawn=false
    sequence[#sequence+1]='background'
    draw()
    sequence[#sequence+1]='border'
    -- winxi.window draws the controller highlight with the border, before capture
    if options.controller and options.controller.active() then outlines[#outlines+1]='highlight' end
    options.capture()
    fontSize=previousFont
    return true
end
package.loaded['winxi.window'] = {Plain=Window, Full=Window}
dofile('addons/chatbox/chatbox.lua')
local function frame()
    text={}; outlines={}; filled={}; images={}; labels={}; overs={}; lines={}
    events.d3d_present(); assert(styleDepth==0, 'input minimum-size override balanced'); assert(fontDepth==0, 'chat font pushes balanced')
end
local function message(value, extra)
    local e=extra or {}; e.message=value; e.mode=e.mode or 1
    events.text_in(e)
    assert(e.message==value and e.blocked~=true,'chatbox must not rewrite/block input')
end
-- Width and ten rows first; Match Game Log Size is checked further down
app.options.matchGameLogSize[1]=false
for i=1,12 do message('line '..i) end
frame()
assert(#text==10 and text[1].text=='line 3' and text[10].text=='line 12')
assert(app.options.fontSize[1]==12 and measuredSize[2]==12*10+2*9+6+6 and dummy[2]==144,'compact 12px text, ten rows, 3px padding and half a row for the title')
assert(rendered['winxi.chatbox'].style.title=='Say','titled with the game\'s first channel, Say')
assert(text[10].pos[2]==1018-3-12,'rows centred between the paddings, clear of the title')
assert(measuredPos[1]==20 and measuredPos[2]==1018 and measuredPos[4]==1,'native log bottom-left anchor')
nativeLogRect={80,400,720,900}; frame()
assert(measuredPos[1]==80 and measuredPos[2]==900 and measuredPos[4]==1,'follows native log moves, not screen/input offset')
assert(measuredSize[2]==150,'native anchor does not change the ten-row height')
nativeLogRect={20,700,660,1018}; frame()
assert(hooks[0].captures==3 and hooks[1].begins==3)
local count=measured; frame(); assert(measured==count,'unchanged frame reuses wrapped rows')
message('original',{message_modified='modified',mode_modified=12}); frame()
assert(text[10].text=='modified' and text[10].color==require('palette').Mode(12),'uses modified text and mode (12, a tell received)')
local e={message='blocked',mode=1,blocked=true}; events.text_in(e); assert(e.blocked)
message('internal',{mode=152}); frame(); assert(text[10].text=='modified')
message('bad'); frame(); assert(text[10].text=='modified','decoding error contained')
fontSize=20; frame(); assert(measuredSize[2]==150,'theme font size does not enlarge compact chat text')
look.Padding=20; frame(); assert(measuredSize[2]==150,'compact padding independent of theme')
app.options.fontSize[1]=16; frame(); assert(measuredSize[2]==186+6,'Font Size applies without changing ten rows')
app.options.fontSize[1]=12
ready=false; count=hooks[0].captures; frame(); assert(hooks[0].captures==count)
ready=true; captureOK=false; count=hooks[1].begins; local stops=hooks[0].stops
frame(); assert(hooks[1].begins==count and hooks[0].stops>stops,'capture failure releases both slots')
captureOK=true; drawn=false; stops=hooks[0].stops
frame(); assert(hooks[0].stops>stops,'clipped Begin releases empty hide')
drawn=true; throwing=true; stops=hooks[0].stops
assert(not pcall(frame) and hooks[0].stops>stops,'draw failure releases native before propagating')
throwing=false
spec.commands.off(app.options); stops=hooks[0].stops; frame(); assert(hooks[0].stops>stops and #text==0)
spec.commands.on(app.options)
events.packet_in({id=0x00b}); count=hooks[0].captures; frame(); assert(hooks[0].captures==count)
events.packet_in({id=0x00a}); frame(); assert(hooks[0].captures==count+1)
spec.commands.clear(); frame(); assert(#text==0 and dummy[2]==144,'empty log still reserves ten rows')
message('private'); spec.onSettings(app.options); frame(); assert(#text==0,'character/settings swap clears private history')
message('retained'); events.unload(); frame(); assert(#text==0)
inputOpen=true; inputRaw='hello'; inputDisplay='hello'; inputCaret=5
frame(); assert(hooks[2].captures==1 and text[#text].text=='hello','native-backed input rendered and captured independently')
assert(text[#text-1].text=='> ' and measuredPos[2]==1018,'input shares the closed native base')
assert(rendered['winxi.chatbox'].pos[2]==1000 and rendered['winxi.chatbox'].size[1]==rendered['winxi.chatbox.input'].size[1], 'log lifts above input, equal widths')
inputRaw='/l see you there'; inputDisplay=inputRaw; inputCaret=#inputRaw; frame()
assert(rendered['winxi.chatbox'].style.title=='Linkshell 1','typing /l: the title says Linkshell while it is typed')
assert(text[#text-1].text=='> ','input prompt stays plain even with a typed chat command')
inputRaw='hello'; inputDisplay='hello'; inputCaret=5; frame()
assert(rendered['winxi.chatbox'].style.title=='Say','no command typed: the channel last spoken in')
nativeLogRect=nil; count=hooks[0].captures; local inputCount=hooks[2].captures
frame(); assert(hooks[0].captures==count+1 and rendered['winxi.chatbox'].pos[2]==1000,'a moment without the game log\'s place: the last box stays')
for _=1,30 do frame() end
count=hooks[0].captures; stops=hooks[0].stops
frame(); assert(hooks[0].captures==count and hooks[0].stops>stops,'missing native log anchor for longer leaves native log visible')
assert(hooks[2].captures==inputCount+32,'working input independent of missing log geometry')
throwing=true; stops=hooks[2].stops; frame(); assert(hooks[2].stops>stops and styleDepth==0,'failed input draw restores minimum-size override')
throwing=false
nativeLogRect={20,700,660,1018}
app.options.matchGameInputSize[1]=true; nativeRect={0,1020,1920,1060}
frame(); assert(measuredPos[1]==0 and measuredPos[2]==1060 and measuredSize[1]==1920 and measuredSize[2]==40)
assert(lastWindowStyle.fontSize==12 and lastWindowStyle.padding==3 and look.Padding==20,'native input outer size keeps compact text')
assert(text[#text].pos[2]==1020+(40-12)/2,'text stays centred in a taller native-sized input box')
assert(rendered['winxi.chatbox'].size[1]==1920 and rendered['winxi.chatbox'].pos[1]==0,'log shares native input width and left edge')
nativeRect=nil; frame(); assert(measuredSize[1]==1920 and measuredSize[2]==18,'native width retained when input geometry expires')
app.options.matchGameInputSize[1]=false; nativeRect={0,1020,1920,1060}
frame(); assert(measuredPos[1]==20 and measuredSize[1]==640 and measuredSize[2]==18,'toggle off restores shared custom width')
inputRaw=string.rep('x',200); inputDisplay=inputRaw; inputCaret=#inputRaw
frame(); assert(text[#text].pos[1]<0,'long input scrolls to keep caret visible')
inputCaret=0; frame(); assert(text[#text].pos[1]>=32,'Home/left edits scroll back')
inputOpen=false; stops=hooks[2].stops; local inputBegins,inputCaps=hooks[2].begins,hooks[2].captures; frame()
assert(hooks[2].stops==stops and hooks[2].begins==inputBegins+1 and hooks[2].captures==inputCaps,
    'closed input keeps the slot armed, empty: the game\'s bar never shows the frame it opens')
inputOpen=true; inputRaw='bad'; inputDisplay='bad'
stops=hooks[2].stops; frame(); assert(hooks[2].stops>stops,'decode failure restores native input')
inputOpen=false
app.options.matchGameInputSize[1]=false
for i=1,50 do message('history '..i) end
chatState.selected=true; frame()
assert(#outlines==0,'no blue outline')
assert(#filled==2 and filled[1].a[2]==1018-150 and filled[1].b[2]==1018 and filled[1].color[4]<0.1,'native Square focus lights the whole box')
assert(#images==1 and images[1].handle==99 and images[1].b[1]<=20+3 and images[1].a[2]==1018-3-12-1,'the game\'s cursor at the newest line, pointing in from the left edge')
chatState.selected=false; frame(); assert(#filled==1 and #images==0,'cursor leaving chat removes light and cursor but keeps the scrollbar')
chatState.expanded=true; nativeLogRect=nil; frame()
assert(measuredPos[2]==1020 and measuredSize[2]==1020-270,'native expansion takes the full log\'s foot, not stale compact geometry, three quarters up the screen')
assert(measuredPos[1]==0 and measuredSize[1]==1920,'expanded frame matches native bounds exactly, not compact width')
do local e, c = rendered['winxi.chatbox.expanded'].style, rendered['winxi.chatbox'].style
    assert(e.padding==c.padding and e.fontSize==c.fontSize and e.shadow==c.shadow and e.background==c.background and e.border==c.border,
        'the compact log\'s window: its padding, font size, shadow and colours') end
assert(#text==0 and #filled==0 and #images==0,'no addon rows, highlight, scrollbar or cursor over native content')
assert(hooks[0].expanded==true and rendered['winxi.chatbox.expanded'].style.title==nil,
    'capture is explicitly frame-only; native tabs replace the custom title')
assert(hooks[0].controls[1]==look.HighlightColor and hooks[0].controls[2]==look.TextColor,
    'native control colours follow current highlight and title/text theme')
local logAppearance=app.options.appearance.log
logAppearance.own.titleColor[1],logAppearance.own.border[1]=true,true
frame()
assert(hooks[0].controls[2]==logAppearance.colors.titleColor and hooks[0].controls[3]==logAppearance.colors.border
    and hooks[0].controls[4]==logAppearance.colors.border and #text==0,
    'local Title and Border / Art Tint style native controls without overlaying rows or hit-tests')
logAppearance.own.titleColor[1],logAppearance.own.border[1]=false,false
captureOK=false; stops=hooks[0].stops; frame()
assert(hooks[0].stops>stops and #text==0,'failed expanded capture restores native rather than a blank log')
captureOK=true; frame()
chatState.nativeBrowse=true; count=hooks[0].captures; stops=hooks[0].stops; frame()
assert(hooks[0].captures==count and hooks[0].stops>stops and #text==0,'nested menus hand the native view back intact')
local said={}; app.Say=function(_,line) said[#said+1]=line end
spec.commands.status()
local joined=table.concat(said,'\n')
assert(joined:find('Last box %(expanded') and joined:find('Last handed to the game'),'/chatbox status says what the expanded box drew and why the game\'s was shown')
app.Say=function() end
chatState.nativeBrowse=false; frame(); assert(hooks[0].captures==count+1,'return to native newest/all restores expanded theme')
chatState.nested=true; count=hooks[0].captures; frame()
assert(hooks[0].captures==count+1 and hooks[0].expanded,'a row\'s action menu open over the log: the skin stays under it')
said={}; app.Say=function(_,line) said[#said+1]=line end; spec.commands.status(); app.Say=function() end
assert(table.concat(said,'\n'):find('A menu of the game\'s is open over it',1,true),'/chatbox status says a menu is open')
chatState.nested=false
message('to you',{mode=12}); message('from you',{mode=4}); message('a yell',{mode=11})
frame()
assert(#text==0,'incoming messages do not create a second expanded history')
message('to the party',{mode=5})
for filter=0,15 do
    chatState.filter=filter; chatState.scroll=50; count=hooks[0].captures; frame()
    assert(hooks[0].captures==count+1 and #text==0 and hooks[0].expanded,
        'all native tabs and older pages retain frame skin without custom filtering')
end
chatState.filter=0; chatState.scroll=0
-- The game's tabs and scrollbar replaced: WinXI tabs named for their channels where the game drew its own,
-- side by side as a winxi tab bar's (each overlap split at its middle, a gap between neighbours), each the
-- window's background then the theme's tab colour (the Highlight Color for the chosen one), rounded at the
-- top, the tab style over it and its name centred; winxi's tab line under the row; a thumb in the game's
-- bar; and the game asked to leave both undrawn, only while there is a fresh place to draw them in
look.BackgroundColor, look.BorderColor = {0.1,0.1,0.2,0.8}, {0.5,0.5,0.5,1}
tabsGeometry={{left=10,top=100,right=64,bottom=116,channel=0,selected=false},
    {left=60,top=100,right=114,bottom=116,channel=2,selected=true},{left=110,top=100,right=160,bottom=116,channel=nil,selected=false}}
scrollGeometry={left=2,top=120,right=6,bottom=1020,page=20,count=100,above=80}
frame()
assert(hooks[0].replace.tabs and hooks[0].replace.scrollbar,'the game asked to leave its tabs and scrollbar undrawn')
assert(#labels==3 and labels[1].text=='Win 1' and labels[2].text=='Say' and labels[3].text=='Tab 3','left to right, each named by its art\'s filter (its short name), an unknown one by its place')
assert(pushedSizes[#pushedSizes-1]==10 or pushedSizes[#pushedSizes]==10,'the names a little smaller than Font Size 12')
assert(labels[1].x==10+(55-5*7)/2 and labels[2].x==69+(55-3*7)/2 and labels[3].x==128+(55-5*7)/2 and labels[2].y>250 and labels[2].y<270
    and labels[2].color==look.TextColor,'each whole, side by side from the strip\'s start, all as wide as the longest name needs, a gap of four, each name centred')
assert(#filled==7 and filled[1].color==look.BackgroundColor and filled[1].a[1]==10 and filled[1].b[1]==65 and filled[3].a[1]==69 and filled[3].b[1]==124
    and filled[5].a[1]==128 and filled[5].b[1]==183 and filled[1].a[2]==250 and filled[1].b[2]==270,'each over the log\'s background, four taller than the game\'s strip, standing on the frame\'s top')
assert(filled[2].color[4]==0.25 and filled[6].color[4]==0.25 and filled[4].color~=filled[2].color and filled[4].color[4]~=0.25,
    'a winxi button\'s colour, the border faint, and the chosen one the Highlight Color')
assert(#outlines==0 and #overs==0 and #lines==0,'a button: no edge, no tab style, no tab line')
mouseAt={20,108}; frame(); assert(filled[2].color[4]==0.25,'no mouse light: the game\'s clicks are at its own places')
mouseAt=nil; frame()
assert(filled[7].a[1]==1920-3-2 and filled[7].b[1]==1920-3 and math.abs(filled[7].a[2]-(1017-744*0.2))<0.01 and filled[7].b[2]==1017 and filled[7].color==require('scrollbar').White,
    'the compact log\'s thumb, no track: inside the log\'s right edge, over the game\'s bar\'s height, at the newest at its foot')
mouseAt={4,500}; frame(); assert(filled[7].color==require('scrollbar').Bright,'brighter with the mouse on the game\'s bar, which it drags')
mouseAt={1916,500}; frame(); assert(filled[7].color==require('scrollbar').Bright,'or on the thumb')
mouseAt=nil; frame(); assert(filled[7].color==require('scrollbar').White)
assert(#text==0 and #images==0,'still no addon rows or cursor over the native content')
scrollGeometry.above=0; frame()
assert(filled[7].a[2]==273 and math.abs(filled[7].b[2]-(273+744*0.2))<0.01,'scrolled to the oldest, the thumb at the top, within the frame')
tabsGeometry[2].channel=8; frame()
assert(labels[2].text=='A (E)' and labels[1].text=='Win 1','the whole name')
local savedRect=expandedRect; expandedRect={0,100,120,1020}; frame()
assert(labels[2].text=='A (' and labels[1].text=='Win' and filled[5].b[1]<=116.01,'narrowed to fit the log, the names cut to fit')
expandedRect=savedRect
tabsGeometry[2].channel=2
local channels=require('channels')
local places={}
for filter, tab in pairs(channels.Filters) do places[tab.place]=tab.name end
assert(table.concat(places,',')=='Window,Window 2,Say,Tell,Party,Linkshell 1,Linkshell 2,Assist (E),Assist (J),Unity,Shout','the tabs in the client\'s order')
tabsGeometry[1].selected, tabsGeometry[2].selected = true, false; frame()
assert(labels[1].text=='Win 1' and labels[1].x==10+(55-5*7)/2 and filled[2].color[4]~=0.25 and filled[4].color[4]==0.25,
    'another tab chosen as the game chooses it: lit in its place, nothing moved')
tabsGeometry[1].selected, tabsGeometry[2].selected = false, true
-- the game's English strip, each tab drawn with its art, as the client's table orders them (its draw order
-- scrambled here: the order is by where each stands), with and without the Window 2 tab
local function Strip(arts)
    local list={}
    for i, a in ipairs(arts) do list[i]={left=10+(i-1)*30,top=100,right=10+(i-1)*30+60,bottom=116,channel=a,selected=i==4} end
    list[3],list[7]=list[7],list[3]
    return list
end
local function Seen()
    local byLeft={}
    for _, l in ipairs(labels) do byLeft[#byLeft+1]=l end
    table.sort(byLeft,function(a,b) return a.x<b.x end)
    local seen={}
    for i, l in ipairs(byLeft) do seen[i]=l.text end
    return table.concat(seen,',')
end
local before=tabsGeometry
tabsGeometry=Strip({0,2,3,4,5,6,8,7,9,10}); frame()
assert(Seen()=='Win 1,Say,Tell,Party,LS 1,LS 2,A (E),A (J),Unity,Shout','the game\'s order, by the short names, whole')
tabsGeometry=Strip({0,1,2,3,4,5,6,8,7,9,10}); frame()
assert(Seen()=='Win 1,Win 2,Say,Tell,Party,LS 1,LS 2,A (E),A (J),Unity,Shout','with the second log window\'s tab')
tabsGeometry=Strip({0,1,2,3,4,5,6,7,8,9,10}); frame()
assert(Seen()=='Win 1,Win 2,Say,Tell,Party,LS 1,LS 2,A (J),A (E),Unity,Shout','a client with Assist (J) first: as the game orders them')
tabsGeometry=before
-- the game's rows of text replaced: each drawn where the game drew it, in the chat's font no taller than the
-- row and centred in it, in its mode's colour; the cursor after the cursor row's text; decoded once each; and
-- the game asked to leave its text undrawn only while there are fresh rows to draw
rowsGeometry={{left=40,top=820,right=300,bottom=836,text='newest line',mode=1,cursor=false},
    {left=40,top=804,right=200,bottom=820,text='older',mode=12,cursor=true},{left=40,top=788,right=100,bottom=804,text='',mode=1,cursor=false},
    {text='nowhere',mode=1,cursor=false}}
pushedFonts={}; app.options.fontFile='arial.ttf'; decodes=0; frame()
assert(hooks[0].replace.text,'the game asked to leave its text undrawn')
assert(#text==2 and text[1].text=='newest line' and text[1].pos[1]==3 and text[1].pos[2]==1020-3-12 and text[1].color==require('palette').Mode(1),
    'laid out as the compact log: the newest from Left Padding, its text ending at the Bottom Padding, in its mode\'s colour')
assert(text[2].text=='older' and text[2].pos[2]==1005-14 and text[2].color==require('palette').Mode(12),'the older row Font Size and the row gap above, in a tell\'s colour')
assert(#images==1 and images[1].a[1]==3+5*7+4 and images[1].a[2]==990,'the cursor after the cursor row\'s text')
assert(pushedFonts[1]=='font:arial.ttf' and decodes==2,'the chat\'s font; the two rows with text decoded, the empty and the unplaced not')
frame(); assert(decodes==2,'the rows decoded once, not every frame')
rowsGeometry[1].text='older'; frame(); assert(decodes==2,'a row already decoded is known by its bytes')
rowsGeometry[1].text='newest line'
-- Expanded Height: the frame reaches three quarters of the way up the screen (1080 high: its top at 270), the tabs
-- standing on it, the scrollbar within it; 100% the game's window
local fitted=rendered['winxi.chatbox.expanded']
assert(fitted.pos[2]==1020 and fitted.size[2]==1020-270,'three quarters up the screen: from 270, to the game\'s window\'s foot')
local standing=0
for _, f in ipairs(filled) do if f.b[2]==270 then standing=standing+1 end end
assert(standing>=2,'the tabs standing on its top')
assert(filled[#filled].a[2]>=273,'the thumb within it')
app.options.expandedHeight[1]=100; frame()
assert(rendered['winxi.chatbox.expanded'].size[2]==1020-100,'100%: the game\'s window, no higher')
app.options.expandedHeight[1]=75
-- the log's Default Text, as the compact log takes it, over the modes' colours
app.options.appearance.log.own.textColor[1]=true; app.options.appearance.log.colors.textColor={0.1,0.8,0.2,1}; frame()
assert(text[1].color==app.options.appearance.log.colors.textColor and text[2].color==text[1].color,'the log\'s own Default Text, as the compact log\'s')
app.options.appearance.log.own.textColor[1]=false; frame()
assert(text[1].color==require('palette').Mode(1),'without it, the modes\' colours')
-- the whole log mirrored: with uihook able to leave all of it undrawn, the addon draws the light on the cursor's
-- row (a row's pitch tall about its glyphs, across the log), brighter held down, and a marked row faintly
local function Lights()
    local found={}
    for _, f in ipairs(filled) do if f.a[1]==1 then found[#found+1]=f end end
    return found
end
assert(not hooks[0].replace.all and #Lights()==0,'an older uihook: the game\'s light and cursor, none of the addon\'s')
chatState.nativeMirror=true; frame()
local lit=Lights()
assert(hooks[0].replace.all and hooks[0].replace.text and #lit==1 and lit[1].a[2]==991-1 and lit[1].b[2]==991+12+1 and lit[1].b[1]==1920-3-2-2,
    'the whole log asked for: the cursor\'s row lit across the log, a line tall with half the gap either side')
assert(#images==1 and #text==2,'the cursor after its text and the rows as before')
rowsGeometry[1].marked=true; rowsGeometry[2].pressed=true; frame(); lit=Lights()
assert(#lit==2 and lit[1].a[2]==1004 and lit[1].color~=lit[2].color,'a marked row lit faintly, the held row brighter')
rowsGeometry[1].marked=nil; rowsGeometry[2].pressed=nil
-- where uihook measured the game's highlight: those rows lit, whatever row the cursor flag is on
rowsGeometry[1].lit=true; frame(); lit=Lights()
assert(#lit==1 and lit[1].a[2]==1004 and lit[1].b[2]==1018,'the row under the game\'s highlight lit, not the cursor flag\'s')
rowsGeometry[3].lit=true; frame(); lit=Lights()
assert(#lit==2 and lit[2].a[2]==976,'every row the game highlights')
rowsGeometry[1].lit=nil; rowsGeometry[3].lit=nil
-- the game's chosen row past what fits: the view moves up to keep it at the top
local many={}
for i=1,80 do many[i]={left=40,top=1000-i*16,right=200,bottom=1016-i*16,text='row '..i,mode=1,cursor=i==70} end
local savedRows=rowsGeometry; rowsGeometry=many; frame()
assert(#text==math.floor((1017-273+2)/14) and text[#text].text=='row 70' and text[#text].pos[2]>=273,'the cursor\'s row kept in view, at the top')
rowsGeometry=savedRows
-- Timestamps off: the game's rows shown without theirs, back with them as it is turned on
rowsGeometry[1].text='[12:00:00] newest line'; frame()
assert(text[1].text=='[12:00:00] newest line','the game\'s stamp shown to begin with')
app.options.timestamps[1]=false; frame()
assert(text[1].text=='newest line' and text[2].text=='older','the stamp hidden in the expanded log: '..text[1].text)
frame(); assert(text[1].text=='newest line','and stays hidden from the kept row')
app.options.timestamps[1]=true; frame()
assert(text[1].text=='[12:00:00] newest line','shown again as Timestamps goes on')
rowsGeometry[1].text='newest line'; frame()
local said3={}; app.Say=function(_,line) said3[#said3+1]=line end
spec.commands.status()
assert(table.concat(said3,'\n'):find('WinXI tabs, scrollbar, text and cursor where the game\'s are',1,true),'/chatbox status says the cursor is the addon\'s')
app.Say=function() end
app.options.replaceCursor[1]=false; frame()
assert(not hooks[0].replace.all and hooks[0].replace.text and #Lights()==0,'Replace Cursor off: the game\'s light and cursor')
app.options.replaceCursor[1]=true
app.options.replaceScrollbar[1]=false; frame()
assert(not hooks[0].replace.all,'the game\'s scrollbar kept: not the whole log, which would leave it undrawn')
app.options.replaceScrollbar[1]=true
chatState.nativeMirror=false; frame()
local said2={}; app.Say=function(_,line) said2[#said2+1]=line end
spec.commands.status()
assert(table.concat(said2,'\n'):find('WinXI tabs, scrollbar and text where the game\'s are',1,true) and table.concat(said2,'\n'):find('2 drawn',1,true),'/chatbox status says the text is the addon\'s and how many rows were drawn')
app.Say=function() end
app.options.fontSize[1]=24; pushedSizes={}; frame()
assert(text[1].pos[2]==1017-24 and text[2].pos[2]==1017-24-26 and pushedSizes[1]==24 and labels[1].y<270,'Font Size past the game\'s row spacing: still Font Size and the compact log\'s spacing')
app.options.fontSize[1]=12
app.options.fontFile=''; pushedFonts={}; frame(); assert(#pushedFonts==0 and #text==2,'the theme\'s font at the row\'s size: nothing named')
app.options.replaceText[1]=false; frame()
assert(not hooks[0].replace.text and #text==0 and hooks[0].replace.tabs,'Replace Text off: the game\'s font, the tabs still the addon\'s')
app.options.replaceText[1]=true
chatState.nativeText=false; frame()
assert(not hooks[0].replace.text and #text==0,'without uihook\'s row site the game draws its text')
chatState.nativeText=true
rowsGeometry=nil; frame()
assert(not hooks[0].replace.text and #text==0 and hooks[0].replace.tabs,'no fresh rows: the game\'s text is left drawn')
app.options.replaceTabs[1]=false; frame()
assert(not hooks[0].replace.tabs and hooks[0].replace.scrollbar and #labels==0 and #filled==1,'Replace Tabs off: the game\'s tabs stay, the scrollbar still the addon\'s')
app.options.replaceScrollbar[1]=false; frame()
assert(not hooks[0].replace.scrollbar and #filled==0,'Replace Scrollbar off: the game\'s')
app.options.replaceTabs[1], app.options.replaceScrollbar[1]=true, true
chatState.nativeReplace=false; frame()
assert(not hooks[0].replace.tabs and not hooks[0].replace.scrollbar and #filled==0,'without uihook\'s hooks the game draws its own, tinted')
chatState.nativeReplace=true
tabsGeometry=nil; frame()
assert(not hooks[0].replace.tabs and hooks[0].replace.scrollbar and #labels==0,'no fresh place for tabs: the game\'s are left drawn')
scrollGeometry=nil; frame()
assert(not hooks[0].replace.scrollbar and #filled==0,'none drawn by the game, none asked for')
assert(hooks[0].expanded and #text==0,'the frame-only capture as before')
expandedRect=nil; count=hooks[0].captures; frame()
assert(hooks[0].captures==count,'missing expanded geometry immediately restores native; no stale compact/full capture')
for _=1,30 do frame() end
count=hooks[0].captures; frame(); assert(hooks[0].captures==count,'missing expanded bounds for longer never suppress native expanded log')
expandedRect={0,100,1920,1020}; chatState.expandedSupported=false; frame()
assert(hooks[0].captures==count,'unsupported expanded recognition leaves native history')
chatState.expandedSupported=true; chatState.nativeContent=false; frame()
assert(hooks[0].captures==count,'missing content hook cannot hide native glyphs')
chatState.nativeContent=true; chatState.expanded=false; nativeLogRect={20,700,660,1018}; frame()
assert(#text==10 and text[1].text=='history 45' and measuredSize[2]==150,'native cancel restores ten compact rows and placement')
assert(rendered['winxi.chatbox'].style.title=='Party','compact: titled with the channel last spoken in, a line sent to the party')
-- Match Game Log Size: the game log's width and height, as many rows as fit, at the bottom
app.options.matchGameLogSize[1]=true; nativeLogRect={20,700,820,1018}; frame()
assert(measuredSize[1]==800 and measuredSize[2]==318 and measuredPos[2]==1018,'the game log\'s width and height')
assert(#text==22 and text[22].text=='to the party' and text[22].pos[2]==1018-3-12,'22 rows of 12px fit in 318 below the title, newest at the foot')
nativeLogRect={20,850,820,1018}; frame()
assert(measuredSize[2]==168 and #text==11,'a smaller game log: fewer rows')
assert(text[#text].pos[2]==850+6+3+2+10*14,'the 11 rows centred: 4 spare pixels, 2 above and 2 below')
app.options.matchGameLogSize[1]=false; nativeLogRect={20,700,660,1018}; frame()
assert(measuredSize[1]==640 and measuredSize[2]==150 and #text==10,'off: Width and ten rows again')
screen={x=1920,y=180}; stops=hooks[0].stops; frame(); assert(hooks[0].stops>stops,'too-small screen leaves native')
-- Source colours are always preserved; uncoloured messages use native chat-mode colours.
screen={x=1920,y=1080}; chatState.expanded=false; chatState.selected=false; nativeLogRect={20,700,660,1018}
message('a tell',{mode=12}); frame()
assert(text[#text].text=='a tell' and text[#text].color==require('palette').Mode(12))
for _, mode in ipairs({1,9,2,10,3,11,4,12,5,13,6,14,205,213,214,217,7,15,211,212,50,123}) do
    message('native colour '..mode,{mode=mode}); frame()
    assert(text[#text].color==require('palette').Mode(mode),'native colour for mode '..mode)
end
local plainDecode = package.loaded.encoding.Decode
package.loaded.encoding.Decode = function() return 'baseinlinereset',nil,{{first=5,last=10,bank=31,slot=2}} end
message('coloured tell',{mode=12})
package.loaded.encoding.Decode = plainDecode
frame()
assert(text[#text-2].text=='base' and text[#text-2].color==require('palette').Mode(12)
    and text[#text-1].text=='inline' and text[#text-1].color==require('palette').Color(31,2)
    and text[#text].text=='reset' and text[#text].color==require('palette').Mode(12),
    'SimpleLog inline overrides native colour, then resets to the native channel colour')
message('yelled',{mode=3}); frame()
assert(rendered['winxi.chatbox'].style.title=='Yell','a line yelled: the title says Yell')
app.options.windowTitle[1]='My Chat'; frame()
assert(rendered['winxi.chatbox'].style.title=='My Chat','Window Title: the words typed in place of the channel')
app.options.windowTitle[1]='   '; frame()
assert(rendered['winxi.chatbox'].style.title=='Yell','Window Title of only spaces: the channel again')
app.options.windowTitle[1]=''
imgui.Checkbox=function() return false end
imgui.ColorEdit4=function() return false end
imgui.IsItemDeactivatedAfterEdit=function() return false end
imgui.SameLine=function() end
imgui.TextDisabled=function() end
imgui.SliderInt=function() return false end
imgui.SmallButton=function() return false end
imgui.InputText=function() return false end
imgui.SetTooltip=function() end
imgui.BeginDisabled=function() end; imgui.EndDisabled=function() end
imgui.Button=function() return false end
-- the settings window: five sections, each folding away, drawn whole when open
local opened = {}
package.loaded['winxi.widgets'].Header=function(name) opened[#opened+1]=name; return headers[name] end
imgui.Selectable=function() return false end
imgui.EndCombo=function() end
imgui.BeginCombo=function() return true end
spec.drawSettings(app.options)
assert(table.concat(opened,',')=='Chatbox,Size,Text,Padding,Expanded,Window Colors','collapsed: only the six section titles')
for _,name in ipairs(opened) do headers[name]=true end
headers['Chat Log Window'], headers['Input Text Box'] = true, true
opened={}
spec.drawSettings(app.options)
assert(table.concat(opened,',')=='Chatbox,Size,Text,Padding,Expanded,Window Colors,Chat Log Window,Input Text Box','open: every section drawn')
for k in pairs(headers) do headers[k]=nil end
package.loaded['winxi.widgets'].Header=function(name) return headers[name] end
assert(#spec.tabs == 1 and spec.tabs[1].label == 'Info Panel' and app.options.colors == nil and app.options.combat == nil,
    'Info Panel tab added without channel colour controls or Combat Log tab')
-- Font, Left Padding and source timestamps
pushedFonts={}; app.options.fontFile='arial.ttf'; inputOpen=true; inputRaw='hi'; inputDisplay='hi'; inputCaret=2; frame()
assert(#pushedFonts==2 and pushedFonts[1]=='font:arial.ttf' and pushedFonts[2]=='font:arial.ttf','the chosen font for the log and the input bar')
local rowX=text[#text-2].pos[1]
app.options.leftPadding[1]=16; frame()
assert(text[#text-2].pos[1]==rowX+13,'Left Padding moves the log\'s text in from the edge')
assert(text[#text-1].text=='> ' and text[#text-1].pos[1]==20+16,'input uses the restored left padding and a plain prompt')
-- the other sides: the bars grow or the rows move by them
app.options.topPadding[1], app.options.bottomPadding[1] = 10, 20; frame()
assert(rendered['winxi.chatbox.input'].size[2]==12+10+20,'input height includes the restored top and bottom padding')
local inputBox=rendered['winxi.chatbox.input']
local aboveText=text[#text].pos[2]-(inputBox.pos[2]-inputBox.size[2])
local belowText=inputBox.pos[2]-(text[#text].pos[2]+12)
assert(text[#text].text=='hi' and aboveText==15 and belowText==15,
    'input has equal space above and below text, even with asymmetric padding settings')
inputOpen=false; frame()
assert(measuredSize[2]==120+18+6+10+20,'the log: ten rows, the title\'s half and both paddings')
assert(text[#text].pos[2]==1018-20-12,'the newest row above the bottom padding')
app.options.topPadding[1], app.options.bottomPadding[1] = 4, 4
app.options.rightPadding[1]=600; message(string.rep('w',20),{mode=1}); frame()
assert(text[#text-1].text=='ww' and #text[#text].text<=2,'Right Padding and slim scrollbar reserve leave 20px, up to two letters per row')
app.options.rightPadding[1]=4
inputOpen=false; app.options.fontFile=''; app.options.leftPadding[1]=4
pushedFonts={}; frame(); assert(#pushedFonts==0,'the theme\'s font: nothing pushed')
message('[23:55:59] stamped',{mode=12}); frame()
assert(text[#text].text=='[23:55:59] stamped','timestamp in the line\'s colour by default')
message('[Addons] not a time',{mode=1}); frame()
assert(text[#text].text=='[Addons] not a time','only a time is a timestamp')
-- the first paddings were 4 on every side: left all at 4, they become 3 once; a choice of one's own stays
for _,key in ipairs({'leftPadding','rightPadding','topPadding','bottomPadding'}) do app.options[key][1]=4 end
app.options.paddingVersion[1]=0; spec.onSettings(app.options)
assert(app.options.leftPadding[1]==3 and app.options.bottomPadding[1]==3 and app.options.paddingVersion[1]==1,'untouched 4s become 3')
app.options.leftPadding[1]=10; app.options.topPadding[1]=4; app.options.paddingVersion[1]=0; spec.onSettings(app.options)
assert(app.options.leftPadding[1]==10 and app.options.topPadding[1]==4,'paddings of one\'s own are kept')
spec.onSettings(app.options); assert(app.options.leftPadding[1]==10,'and only once')
app.options.leftPadding[1]=3; app.options.topPadding[1]=3
-- settings from disk made whole
app.options.colors={party={'x',2,-1}}; app.options.themeColors={}; app.options.combat={show={false}}
app.options.inlineColors={false}; app.options.timestampOwnColor={true}; app.options.timestampColor={1,0,0,1}
app.options.leftPadding[1]=99; app.options.bottomPadding={'x'}; app.options.rightPadding=nil; app.options.fontFile=nil
spec.onSettings(app.options)
assert(app.options.colors == nil and app.options.themeColors == nil and app.options.combat == nil
    and app.options.inlineColors == nil and app.options.timestampOwnColor == nil and app.options.timestampColor == nil,
    'retired settings cannot disable preservation or rewrite/filter source messages')
assert(app.options.leftPadding[1]==40 and app.options.bottomPadding[1]==3 and app.options.rightPadding[1]==3 and app.options.fontFile=='','Left Padding and Font made whole')
-- Native expanded selection is not emulated: no keyboard hook, controller owner or injected tell.
local clock=0; local realClock=os.clock; os.clock=function() return clock end
assert(events.key_state==nil and binding==nil,'all keyboard and controller actions remain native')
spec.commands.clear()
for i=1,30 do message(('Talker%s : line %d'):format(string.char(64+i%26+1),i),{mode=9}) end
message('Melyon>> are you there',{mode=12})
chatState.expanded=true; chatState.filter=0; chatState.nativeBrowse=false; nativeLogRect=nil; expandedRect={0,100,1920,1020}
inputOpen=true; inputRaw='/p draft'; inputDisplay=inputRaw; inputCaret=#inputRaw
count=hooks[2].captures; frame()
assert(hooks[2].captures==count and inputSet==nil and #text==0,
    'expanded mode never overlays native editor or synthesizes tell commands')
inputOpen=false
chatState.expanded=false; nativeLogRect={20,700,660,1018}; frame()
-- /cm changes the persistent title before any message is sent, without blocking the command.
local command={command='/cm p'}; events.command(command); frame()
assert(not command.blocked and rendered['winxi.chatbox'].style.title=='Party','/cm immediately updates the title')
message('one-off say',{mode=1}); frame()
assert(rendered['winxi.chatbox'].style.title=='Party','one-off outgoing channel does not replace /cm mode')
events.command({command='/cm s',blocked=true}); frame()
assert(rendered['winxi.chatbox'].style.title=='Party','blocked mode commands are ignored')
-- The pearl's extra data as the server's EncodeStringLinkshell writes it: six bits a letter from byte 9,
-- then ones to the end of the byte (a whole code of six where none are left, or two), then zeros.
-- FirstShell's ten letters leave four bits, which read as an o with nothing after it.
local function pearl(name)
    local extra, alphabet = {}, 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
    for i=0,27 do extra[i]=0 end
    local function put(code,bitOffset,length)
        local offset,shift=9+math.floor(bitOffset/8),bitOffset%8
        local value=(code%2^length)*2^shift
        extra[offset]=extra[offset]+value%256
        extra[offset+1]=extra[offset+1]+math.floor(value/256)
    end
    for i=1,#name do put(assert(alphabet:find(name:sub(i,i),1,true)),(i-1)*6,6) end
    local leftover=8-(#name*6)%8
    if leftover==8 or leftover==2 then leftover=6 end
    put(0xFF,#name*6,leftover)
    return {Id=515,Extra=extra}
end
local shells={[1]=pearl('FirstShell'),[2]=pearl('SecondShell')}
AshitaCore.GetMemoryManager=function() return {GetInventory=function() return {
    GetContainerItem=function(_,bag,index) assert(bag==1); return shells[index] end,
} end} end
events.packet_in({id=0x0e0,data='\0\0\0\0\1\1\1\0'})
events.packet_in({id=0x0e0,data='\0\0\0\0\2\2\1\0'})
events.command({command='/cm linkshell'}); frame()
assert(rendered['winxi.chatbox'].style.title=='Linkshell 1: FirstShell','first equipped linkshell name')
events.command({command='/chatmode l2'}); frame()
assert(rendered['winxi.chatbox'].style.title=='Linkshell 2: SecondShell','second equipped linkshell name')
shells[2]=pearl('NewShell'); frame()
assert(rendered['winxi.chatbox'].style.title=='Linkshell 2: SecondShell','the name is not read from the inventory every frame')
clock=clock+1; frame()
assert(rendered['winxi.chatbox'].style.title=='Linkshell 2: NewShell','equipped pearl changes refresh the name within a second')
events.packet_in({id=0x0e0,data='\0\0\0\0\2\0\0\0'}); frame()
assert(rendered['winxi.chatbox'].style.title=='Linkshell 2','unequipped pearl has no stale name')
inputOpen=true; inputRaw='/p hello'; inputDisplay=inputRaw; inputCaret=#inputRaw; frame()
assert(rendered['winxi.chatbox'].style.title=='Party','typed one-line channel overrides mode preview')
inputOpen=false; frame()
assert(rendered['winxi.chatbox'].style.title=='Linkshell 2','closing input restores selected mode')
chatState.expanded=true; chatState.filter=0; frame()
assert(rendered['winxi.chatbox.expanded'].style.title==nil and #text==0,'expanded tabs remain native')
-- NPC dialogue repeats arrive on both dialogue modes and the native replay channel.
chatState.expanded=false; spec.commands.clear()
message('NPC: Welcome!',{mode=150})
message('NPC: Welcome!',{mode=151})
message('NPC: Welcome!',{mode=190})
message('NPC: Welcome!',{mode=190,mode_modified=151})
frame()
assert(#text==3 and text[1].text=='NPC [' and text[2].text=='NPC' and text[3].text==']: Welcome!',
    'uppercase NPC tag retained once, native replays ignored')
assert(text[2].color==require('palette').Color(31,50) and text[1].color==require('palette').Mode(150)
    and text[3].color==require('palette').Mode(150),'only tag letters are yellow, not brackets or dialogue')
message('NPC: Next line.',{mode=151}); frame()
assert(#text==6 and text[6].text==']: Next line.','different NPC dialogue is not lost')
clock=clock+2; message('NPC: Next line.',{mode=150}); frame()
assert(#text==9,'later repeated dialogue is preserved')
-- Source combat text is never compacted, grouped, filtered, stamped or recoloured.
spec.commands.clear()
message('Alice hits Crab for 123 points of damage.',{mode=20})
message('Alice hits Crab for 123 points of damage.',{mode=20})
message('hello',{mode=9}); frame()
assert(#text==3 and text[1].text=='Alice hits Crab for 123 points of damage.' and text[2].text==text[1].text)
message('Bob casts Slow.\nCrab receives the effect of Slow.',{mode=57}); frame()
assert(text[#text-1].text=='Bob casts Slow.' and text[#text].text=='Crab receives the effect of Slow.',
    'source paragraphs are preserved without combat classification')
local byteReport={}; app.Say=function(_,line) byteReport[#byteReport+1]=line end
spec.commands.clear()
message('Hill?Lizard hits Alice.',{mode=20,message_modified='Hill\160Lizard hits Alice.'})
spec.commands.bytes()
local report=table.concat(byteReport,'\n')
assert(report:find('48 69 6C 6C 3F 4C',1,true) and report:find('48 69 6C 6C A0 4C',1,true),
    'byte diagnostic distinguishes original question marks from modified non-ASCII separators')
assert(not report:find('\160',1,true),'diagnostic prints safe ASCII hex, not control bytes')
assert(byteReport[1]:find('no timestamp in front',1,true) and byteReport[1]:find('loaded after chatbox',1,true),'the report says the line reached chatbox without a stamp, and why that can be')
byteReport={}; spec.commands.clear(); spec.commands.bytes()
assert(#byteReport==1 and byteReport[1]:find('No decode sample',1,true),'clear removes captured diagnostic data')
-- as in the game, each line the report says goes through text_in itself: the sample is held for the whole report
byteReport={}
app.Say=function(_,line) byteReport[#byteReport+1]=line; events.text_in({mode=11,message='[chatbox] '..line,injected=true}) end
message('[12:00:00] Yeller[Jeuno]: stamped by simplelog',{mode=11})
spec.commands.bytes()
assert(#byteReport==5 and byteReport[1]:find('a timestamp in front',1,true) and not byteReport[1]:find('addon\'s own',1,true),'the game\'s line, with its stamp')
assert(byteReport[2]:find('5B 31 32 3A 30 30 3A 30 30 5D 20 59 65',1,true) and byteReport[3]:find('5B 31 32 3A 30 30 3A 30 30 5D 20 59 65',1,true) and byteReport[5]:find('5B 31 32',1,true),
    'every stage is that line\'s, not one of the report\'s own')
byteReport={}; spec.commands.bytes()
assert(byteReport[1]:find('an addon\'s own line',1,true),'the report\'s last line is now the sample, and said to be an addon\'s')
app.Say=function() end
app.options.combat=false; spec.onSettings(app.options)
assert(app.options.combat == nil, 'legacy combat settings are retired')
-- End-to-end colour metadata from the text event to captured draw calls.
spec.commands.clear()
local oldDecode = package.loaded.encoding.Decode
package.loaded.encoding.Decode = function(raw, spaces, colors)
    if raw ~= 'inline sample' then return oldDecode(raw) end
    assert(colors and not spaces, 'the log opts into colour metadata without changing input decoding')
    local value = '[12:34:56] Alice'
    return value, raw, {{first=1,last=#value,bank=31,slot=2}}
end
message('inline sample', {mode=9}); frame()
assert(#text == 1 and text[1].text == '[12:34:56] Alice' and text[1].color == require('palette').Color(31,2),
    'source colours, including timestamp colours, are always preserved')
package.loaded.encoding.Decode = oldDecode
-- Log/input appearance overrides are independent and never write the shared theme.
spec.commands.clear()
local originalThemeText = look.TextColor
local logLook, inputLook = app.options.appearance.log, app.options.appearance.input
for _, field in ipairs({'background','border','textColor','titleColor'}) do logLook.own[field][1]=true end
for _, field in ipairs({'background','border','textColor'}) do inputLook.own[field][1]=true end
logLook.colors.textColor={0.1,0.8,0.2,1}
inputLook.colors.textColor={0.9,0.4,0.1,1}
inputOpen,inputRaw,inputDisplay,inputCaret=true,'colour input','',4
message('plain window',{mode=121}); frame()
assert(rendered['winxi.chatbox'].style.background == logLook.colors.background
    and rendered['winxi.chatbox'].style.border == logLook.colors.border
    and rendered['winxi.chatbox'].style.titleColor == logLook.colors.titleColor)
assert(rendered['winxi.chatbox.input'].style.background == inputLook.colors.background
    and rendered['winxi.chatbox.input'].style.border == inputLook.colors.border)
local foundLog,foundInput=false,false
for _, drawnText in ipairs(text) do
    if drawnText.text == 'plain window' then foundLog=drawnText.color == logLook.colors.textColor end
    if drawnText.text == 'colour input' then foundInput=drawnText.color == inputLook.colors.textColor end
end
assert(foundLog and foundInput and look.TextColor == originalThemeText, 'both text colours are local to their windows')
for _, section in pairs(app.options.appearance) do for _, own in pairs(section.own) do own[1]=false end end
frame()
assert(rendered['winxi.chatbox'].style.background == nil and rendered['winxi.chatbox'].style.border == nil
    and rendered['winxi.chatbox.input'].style.background == nil, 'theme restoration clears stale frame overrides')
-- Wheel scrolling is row-based, bounded, and never reaches hidden native history.
spec.commands.clear()
app.options.matchGameLogSize[1] = false
chatState.expanded, chatState.nativeBrowse = false, false
inputOpen = false
for i=1,80 do message('wheel ' .. i) end
frame()
assert(text[1].text == 'wheel 71' and text[10].text == 'wheel 80')
local oldIO, mouse = imgui.GetIO, {x=0,y=0}
imgui.GetIO = function() local io=oldIO(); io.MousePos=mouse; return io end
local function hover()
    local box=rendered['winxi.chatbox']
    mouse.x,mouse.y=box.pos[1]+20,box.pos[2]-20
end
local function wheel(delta, extra)
    local event=extra or {}; event.message=0x020a; event.delta=delta
    events.mouse(event); return event
end
hover()
assert(wheel(120).blocked, 'wheel over overflowing replacement is taken from the game')
frame()
assert(text[1].text == 'wheel 68' and text[10].text == 'wheel 77', 'one notch scrolls three visual rows')
assert(wheel(120*100).blocked); frame()
assert(text[1].text == 'wheel 1' and text[10].text == 'wheel 10', 'scroll clamps at oldest full viewport')
-- The settings' Clear forgets the scroll too, as /chatbox clear does: new lines after it show at the bottom
do local oldSmall=imgui.SmallButton; imgui.SmallButton=function(label) return label:find('chatbox.clear',1,true)~=nil end
    headers['Chatbox']=true; spec.drawSettings(app.options); headers['Chatbox']=nil; imgui.SmallButton=oldSmall end
for i=1,80 do message('wheel ' .. i) end; frame() -- no frame between: nothing has clamped the old scroll away
assert(text[10].text == 'wheel 80', 'the settings\' Clear forgets the scroll as well, so the newest line is at the bottom again')
assert(wheel(120*100).blocked); frame()
assert(text[1].text == 'wheel 1' and text[10].text == 'wheel 10')
assert(wheel(-120*100).blocked); frame()
assert(text[10].text == 'wheel 80', 'scroll clamps at newest')
mouse.x,mouse.y=0,0
assert(not wheel(120).blocked, 'wheel outside the box passes through')
hover(); assert(wheel(120,{blocked=true}).blocked, 'already blocked wheel remains blocked')
chatState.nativeBrowse=true
assert(not wheel(120).blocked, 'native browsing never intercepts wheel')
chatState.nativeBrowse=false
chatState.expanded=true; chatState.filter=0
expandedRect={0,100,1920,400}; frame(); hover()
assert(not wheel(120).blocked); frame()
assert(#text==0,'expanded wheel-up is native, not an independent viewport')
assert(not wheel(-120).blocked); frame()
assert(#text==0,'expanded wheel-down remains native')
chatState.expanded=false; frame()
assert(text[#text].text == 'wheel 80', 'changing compact/expanded view resets wheel position')
-- The scrollbar is captured on the right, pages on track clicks and drags past its bounds.
local function mouseEvent(message)
    local event={message=message}; events.mouse(event); return event
end
local function scrollbarRects()
    local thumb=filled[#filled]
    local box=rendered['winxi.chatbox']
    local track={a={thumb.a[1],box.pos[2]-box.size[2]+6+app.options.topPadding[1]},
        b={thumb.b[1],box.pos[2]-app.options.bottomPadding[1]}}
    return track,thumb
end
local track,thumb=scrollbarRects()
assert(thumb.b[1]-thumb.a[1]==2 and thumb.color[4]==0.35, 'inventory-style 2px white thumb, without a painted track')
assert(thumb.b[2] == track.b[2] and track.b[1] == rendered['winxi.chatbox'].pos[1]+rendered['winxi.chatbox'].size[1]-3,
    'newest viewport has its thumb at the bottom, inset from the right border')
mouse.x,mouse.y=track.a[1]+2,track.a[2]+1
assert(mouseEvent(0x0201).blocked and mouseEvent(0x0202).blocked); frame()
assert(text[#text].text == 'wheel 70', 'track click pages by one viewport')
track,thumb=scrollbarRects()
assert(thumb.color[4]==0.7,'hovering scrollbar strip brightens it, like inventory')
mouse.x,mouse.y=thumb.a[1]+1,(thumb.a[2]+thumb.b[2])/2
assert(mouseEvent(0x0201).blocked)
mouse.x,mouse.y=0,track.a[2]-100
assert(mouseEvent(0x0200).blocked); frame()
assert(text[1].text == 'wheel 1' and text[#text].text == 'wheel 10', 'thumb drag reaches the oldest viewport')
assert(mouseEvent(0x0202).blocked, 'drag release outside chat is not sent to the game')
track,thumb=scrollbarRects()
assert(thumb.color[4]==0.7,'dragging keeps the scrollbar bright outside its bounds')
mouse.x,mouse.y=thumb.a[1]+1,(thumb.a[2]+thumb.b[2])/2
assert(mouseEvent(0x0201).blocked)
mouse.y=track.b[2]+100; assert(mouseEvent(0x0200).blocked); frame()
assert(text[#text].text == 'wheel 80' and mouseEvent(0x0202).blocked, 'drag returns to newest')
hover(); assert(not mouseEvent(0x0201).blocked and not mouseEvent(0x0202).blocked, 'clicks on message text stay native')
spec.commands.clear(); message('short log'); frame(); hover()
assert(#filled == 0, 'scrollbar disappears when all rows fit')
assert(not wheel(120).blocked, 'no overflowing rows means no wheel interception')
app.options.enabled[1]=false; frame()
assert(not wheel(120).blocked, 'disabled replacement releases mouse wheel')
-- The game's two log windows mirrored: a second box stacked over the first, of the first's width and the game's
-- second window's height; each shows the messages the game's Log Window settings route to it; each scrolls on its
-- own; the focus light and cursor go to the window the game's focus is on
app.options.enabled[1]=true
spec.commands.clear()
app.options.matchGameLogSize[1]=true
nativeLogRect={20,700,660,1018}; splitRect={20,520,660,700}
routes={split=true,first={[1]=true,[9]=true},second={[1]=true,[5]=true,[13]=true}} -- say to both, party to the second alone, tells to neither
message('said',{mode=1}); message('partied',{mode=5}); message('told',{mode=12}); message('marked',{mode=0x8005})
local begins=hooks[1].begins
frame()
local first,split=rendered['winxi.chatbox'],rendered['winxi.chatbox.split']
assert(split and split.pos[1]==20 and split.pos[2]==700 and split.pos[4]==1 and split.size[1]==640 and split.size[2]==180,'the second box stacked over the first, the first\'s width, the game\'s second window\'s height')
assert(split.style.title=='Window 2' and first.style.title~='Window 2' and split.style.fontSize==12,'titled Window 2, in the chat\'s font size; the first still by its channel')
assert(hooks[1].captures==1 and hooks[1].begins==begins+1,'the second window captured, once begun, not hidden again after')
app.options.splitTitle[1]='Combat'; frame()
assert(rendered['winxi.chatbox.split'].style.title=='Combat','Window 2 Title: the words typed in place of Window 2')
app.options.splitTitle[1]=''
local function texts() local t={} for _,entry in ipairs(text) do t[#t+1]=entry.text end return table.concat(t,'|') end
assert(texts()=='said|marked|said|partied','the first shows what is routed to it, and a line the game marks for it alone; the second its own; the tell neither')
chatState.selected=true; chatState.selectedWindow=2; frame()
assert(#filled==1 and filled[1].a[2]==520 and filled[1].b[2]==700 and #images==1 and images[1].a[2]>520 and images[1].a[2]<700,'the game\'s focus on the second window lights it alone, the cursor at its newest line')
chatState.selectedWindow=1; frame()
assert(#filled==1 and filled[1].a[2]==700 and filled[1].b[2]==1018,'on the first, the first')
chatState.selected=false; chatState.selectedWindow=nil
for i=1,40 do message('party '..i,{mode=5}) end
frame()
assert(text[1].text=='said' and text[2].text=='marked' and text[3].text=='party 29' and text[#text].text=='party 40' and #text==14,'the first two rows, the second its twelve newest')
mouse.x,mouse.y=100,600
assert(wheel(120).blocked,'the wheel over the second box is taken'); frame()
assert(text[1].text=='said' and text[2].text=='marked' and text[#text].text=='party 37','the second scrolls, the first does not')
mouse.x,mouse.y=100,900
assert(not wheel(120).blocked,'the first box, every row fitting, passes the wheel on')
mouse.x,mouse.y=0,0
local captures=hooks[1].captures; begins=hooks[1].begins
routes={split=false}; frame()
assert(hooks[1].captures==captures and hooks[1].begins==begins+1,'the game showing one window: the second is hidden under the first, as before')
assert(#text==22 and text[#text].text=='party 40' and text[1].text=='party 19','and the first shows everything, its 22 newest rows')
routes=nil; frame(); assert(hooks[1].captures==captures,'no routing from uihook: no second box')
routes={split=true,first={[1]=true},second={[5]=true}}; splitRect=nil; frame()
assert(hooks[1].captures==captures and #text==2,'the second window\'s place unknown: no second box; the first still shows what is routed to it')
splitRect={20,520,660,700}; frame()
assert(hooks[1].captures==captures+1,'its place known again: drawn again')
local said3={}; app.Say=function(_,line) said3[#said3+1]=line end; spec.commands.status(); app.Say=function() end
assert(table.concat(said3,'\n'):find('Second window: over the first',1,true) and table.concat(said3,'\n'):find('12 rows of room',1,true),'/chatbox status describes the second window')
app.options.matchGameLogSize[1]=false; frame()
assert(rendered['winxi.chatbox.split'].size[2]==150 and rendered['winxi.chatbox.split'].pos[2]==1018-150,'Match Game Log Size off: ten rows each, the second still stacked over the first')
app.options.matchGameLogSize[1]=true
-- the game's horizontal layout: its second window beside the first, which the second box follows, the game's gap
-- and its width kept, the first's bottom shared, lifting with it over the input
splitRect={680,700,1000,1018}; frame()
split=rendered['winxi.chatbox.split']
assert(split.pos[1]==680 and split.pos[2]==1018 and split.size[1]==320 and split.size[2]==318 and text[#text].text=='party 37','beside the first: the game\'s place and size for it, its scroll kept')
local savedInputRect=nativeRect; nativeRect=nil -- the input over the log's foot: both boxes lift above it
inputOpen=true; inputRaw='hi'; inputDisplay='hi'; inputCaret=2; frame()
assert(rendered['winxi.chatbox'].pos[2]==1000 and rendered['winxi.chatbox.split'].pos[2]==1000,'both lift above the input')
inputOpen=false; nativeRect=savedInputRect
app.options.matchGameLogSize[1]=false; frame()
split=rendered['winxi.chatbox.split']
assert(split.pos[1]==680 and split.pos[2]==1018 and split.size[1]==320 and split.size[2]==150,'Match Game Log Size off: the game\'s width and gap, ten rows, the first\'s bottom')
splitRect={0,700,16,1018}; frame(); assert(rendered['winxi.chatbox.split'].pos[1]==0 and rendered['winxi.chatbox.split'].size[1]==16,'to the first\'s left: there')
splitRect={1700,700,1950,1018}; captures=hooks[1].captures; frame(); assert(hooks[1].captures==captures,'no room on the screen for it: the game\'s is left')
said3={}; app.Say=function(_,line) said3[#said3+1]=line end; spec.commands.status(); app.Say=function() end
assert(table.concat(said3,'\n'):find('no room beside the first',1,true),'/chatbox status says so')
splitRect={20,520,660,700}; app.options.matchGameLogSize[1]=true
chatState.expanded=true; nativeLogRect=nil; captures=hooks[1].captures; frame()
assert(hooks[1].captures==captures and #text==0,'the expanded log: one view, the game\'s rows')
chatState.expanded=false; nativeLogRect={20,700,660,1018}; frame()
assert(hooks[1].captures==captures+1 and text[#text].text=='party 40','back to two, the second at its newest')
-- A log window the game has at 0 lines (its rect too short for one whole row): nothing drawn in its place, nothing
-- of the game's shown there, the other window still drawn; both at 0: nothing, the input still working
splitRect={20,520,660,700}; routes={split=true,first={[1]=true,[5]=true},second={[5]=true}}; frame()
captures=hooks[1].captures; local firstCaptures=hooks[0].captures; local firstStops=hooks[0].stops
nativeLogRect={20,1000,660,1018}; frame()
assert(hooks[0].captures==firstCaptures and hooks[0].stops==firstStops,'the first at 0 lines: not drawn, its empty hide kept, not released')
assert(hooks[1].captures==captures+1 and rendered['winxi.chatbox.split'].pos[2]==700 and rendered['winxi.chatbox.split'].pos[1]==20 and rendered['winxi.chatbox.split'].size[2]==180,'the second drawn alone, where the game draws it')
assert(text[1].text=='party 29' and #text==12,'only the second\'s rows')
mouse.x,mouse.y=100,600; assert(wheel(120).blocked,'and it still scrolls'); frame(); mouse.x,mouse.y=0,0
said3={}; app.Say=function(_,line) said3[#said3+1]=line end; spec.commands.status(); app.Say=function() end
assert(table.concat(said3,'\n'):find('at 0 lines: nothing drawn',1,true),'/chatbox status says the first is at 0 lines')
nativeLogRect={20,700,660,1018}; splitRect={20,690,660,700}; local begins2=hooks[1].begins; captures=hooks[1].captures; frame()
assert(hooks[1].captures==captures and hooks[1].begins==begins2+1 and #text==22 and text[#text].text=='party 40','the second at 0 lines: not drawn, hidden; the first drawn, still routed')
assert(table.concat((function() said3={}; app.Say=function(_,line) said3[#said3+1]=line end; spec.commands.status(); app.Say=function() end; return said3 end)(),'\n'):find('is at 0 lines; nothing drawn',1,true),'status says the second is at 0 lines')
nativeLogRect={20,1000,660,1018}; inputOpen=true; inputRaw='hi'; inputDisplay='hi'; inputCaret=2; local inputCaptures=hooks[2].captures; firstCaptures=hooks[0].captures; frame()
assert(hooks[0].captures==firstCaptures and hooks[1].captures==captures and hooks[2].captures==inputCaptures+1 and text[#text].text=='hi','both at 0 lines: no box, the input bar still drawn')
inputOpen=false
app.options.matchGameLogSize[1]=false; frame()
assert(hooks[0].captures==firstCaptures+1 and rendered['winxi.chatbox'].size[2]==150,'Match Game Log Size off: ten rows whatever the game\'s size')
app.options.matchGameLogSize[1]=true; nativeLogRect={20,700,660,1018}
-- The game's lines, where uihook says them: the box has as many rows as the game shows now, whatever fits its
-- window (the game grows a row a message and shrinks while none come), no shorter than the game's window and tall
-- enough for its rows at Font Size; at 0 lines nothing; the second window the same
nativeLogRect={20,1002,660,1018}; linesState[0]={shown=1,most=8,fewest=0}; firstCaptures=hooks[0].captures; frame()
assert(hooks[0].captures==firstCaptures+1 and rendered['winxi.chatbox'].pos[2]==1018 and rendered['winxi.chatbox'].size[2]==24 and #text==1 and text[1].text=='party 40','one line in a 16px window: one row, the box tall enough for it, over the game\'s bottom')
linesState[0]={shown=3,most=8,fewest=0}; frame()
assert(rendered['winxi.chatbox'].size[2]==3*12+2*2+12 and #text==3,'three lines: three rows, the box grown for them')
nativeLogRect={20,700,660,1018}; frame()
assert(rendered['winxi.chatbox'].size[2]==318 and #text==3,'the game\'s window taller than three rows need: its height, three rows')
linesState[0]={shown=0,most=8,fewest=0}; firstCaptures=hooks[0].captures; frame()
assert(hooks[0].captures==firstCaptures,'at 0 lines: nothing, whatever the window\'s height')
nativeLogRect=nil; frame(); assert(hooks[0].captures==firstCaptures,'and no hold while the game says 0 lines')
linesState[0]={shown=2,most=8,fewest=0}; nativeLogRect={20,1000,660,1018}; frame()
assert(hooks[0].captures==firstCaptures+1 and #text==2 and rendered['winxi.chatbox'].size[2]==2*12+2+12,'a message: back, two rows in an 18px window')
splitRect={20,520,660,700}; linesState[1]={shown=1,most=6,fewest=0}; frame()
assert(rendered['winxi.chatbox.split'].size[2]==180 and rendered['winxi.chatbox.split'].pos[2]==1018-(2*12+2+12),'the second at one line in a tall window: the game\'s height, over the first')
local splitText=0; for _,entry in ipairs(text) do if entry.text:find('party',1,true) then splitText=splitText+1 end end
assert(#text==3,'one row in it')
linesState[1]={shown=0,most=6,fewest=0}; captures=hooks[1].captures; frame(); assert(hooks[1].captures==captures,'the second at 0 lines: nothing')
linesState={}; nativeLogRect={20,700,660,1018}
-- The game's colours, where uihook reads them: a line's body in the game's colour for its mode (as the user has
-- it configured), its inline codes the colours the game gives them; without them, the approximations
routes=nil; splitRect=nil; spec.commands.clear()
local red,purple,pink={1,0.47,0.47,1},{0.63,0.25,1,1},{1,0.59,0.78,1}
gameColors={serial=1,Mode=function(mode) mode=bit.band(mode,255); return mode==20 and red or mode==4 and pink or {0.5,0.5,0.5,0.5} end,
    Inline=function(bank,slot) if bank==0x1e and slot==0x51 then return purple end; if bank==0x1f and slot==4 then return pink end; return nil end}
package.loaded.encoding.Decode=function(raw,_,colours)
    decodes=decodes+1
    if raw=='bad' then error('bad encoding') end
    if raw=='stamped' then return '[12:00:00] hit', raw, {{first=1,last=10,bank=0x1e,slot=0x51}} end
    return raw
end
message('stamped',{mode=20}); message('plain',{mode=99}); frame()
assert(#text==3 and text[1].text=='[12:00:00]' and text[1].color==purple and text[2].text==' hit' and text[2].color==red,'a damage line by another, mode 20: its stamp in the game\'s purple, its body in the game\'s red for the mode')
assert(text[3].text=='plain' and text[3].color[1]==0.5 and text[3].color[4]==0.5,'a mode the game has no entry for: whatever the game draws those in')
gameColors=nil; frame()
assert(text[2].color==require('palette').Mode(20) and text[2].color[1]==1 and text[2].color[2]==1,'without the game\'s colours, the approximations: mode 20 unlisted, white')
assert(text[1].color[1]==1 and text[1].color[2]==1 and math.abs(text[1].color[3]-0xc9/255)<0.01,'and 1E 51 from the approximate palette')
package.loaded.encoding.Decode=function(raw,...) decodes=decodes+1; return plainDecodeStub(raw,...) end
imgui.GetIO=oldIO
os.clock=realClock
-- Optional info-panel attachment: same native chat capture, never the clock slot.
assert(app.options.infoPanel.layout.enabled[1]==false,'panel opt-in by default')
local fakeTime={get_game_time_raw=function() return 1 end}
for key,value in pairs({hours=3,minutes=32,weekday=3,year=900,month=12,day=30,moon_percent=42}) do
    fakeTime['get_game_'..key]=function() return value end
end
package.loaded['ffxi.time']=fakeTime
local hudBegins=0
package.loaded['winxi.nativehud']={Clock=0,new=function() return {
    Begin=function() hudBegins=hudBegins+1; return false end,
    Grid=function() return nil end,Weather=function() return nil end,
} end}
package.loaded['winxi.infopanel.icons']={Day=function() return 991 end,Weather=function() return nil end,
    Sets=function() return {} end,Forget=function() end}
package.loaded['winxi.theme'].GameBorderColor=function() return {1,1,1,1} end
local panelDraws={}
local menuBounds,menuSlot,menuStops=nil,nil,0
package.loaded['winxi.nativemenus']={new=function() return {
    Set=function(rect,slot) menuBounds,menuSlot=rect,slot; return true end,
    Stop=function() menuBounds,menuSlot=nil,nil; menuStops=menuStops+1 end,
    Status=function() return 'test menu anchor' end,
} end}
package.loaded['winxi.frame']={Draw=function(rect,draw)
    panelDraws[#panelDraws+1]=rect; draw(); currentPanelDrawn=true; sequence[#sequence+1]='panel'
end}
app.options.fontSize[1]=12; app.options.matchGameLogSize[1]=false
chatState.expanded=false; chatState.nativeBrowse=false; ready=true; inputOpen=false
routes=nil; splitRect=nil; nativeLogRect={20,700,660,1018}
spec.commands.panel(app.options,{'/chatbox','panel','on'})
frame()
assert(hooks[0].panel and not hooks[1].panel and #panelDraws==1,'panel joins primary capture')
local panelRect=panelDraws[1]
assert(panelRect.left==20 and panelRect.width==640 and panelRect.height==18 and panelRect.top==1018-18,
    'panel where the log\'s bottom was, input height and chat width')
assert(rendered['winxi.chatbox'].pos[2]==1018-18 and rendered['winxi.chatbox'].size[2]==150,'the log lifted wholly above the panel, its size unchanged')
assert(menuSlot==0 and menuBounds.left==20 and menuBounds.top==1018-18-150 and menuBounds.width==640,
    'menu anchor above the lifted log, committed only with the completed primary capture')
-- Typing: the panel stays at the bottom, the input on it, the log over the input
local savedNative=nativeRect; nativeRect={20,1000,660,1018} -- the game's input where the closed log ends
inputOpen=true; inputRaw='hi'; inputDisplay='hi'; inputCaret=2; panelDraws={}; frame()
local typed=panelDraws[1]
assert(typed.top==1018-18 and typed.height==18,'the panel keeps the bottom while typing')
assert(rendered['winxi.chatbox.input'].pos[2]==1018-18,'the input sits on the panel')
assert(rendered['winxi.chatbox'].pos[2]==1018-18-18,'the log over the input')
assert(menuBounds.top==1018-18-18-150,'menus over the log')
nativeRect={20,1042,660,1060} -- the game's input lower than the log: the log lifted only clear of it
panelDraws={}; frame()
assert(panelDraws[1].top==1060-18 and rendered['winxi.chatbox.input'].pos[2]==1060-18,'the panel at the input\'s bottom, the input on it')
assert(rendered['winxi.chatbox'].pos[2]==1018,'the log already clear of the lifted input stays')
nativeRect=savedNative
inputOpen=false; panelDraws={}; frame()
assert(panelDraws[1].top==1018-18 and rendered['winxi.chatbox'].pos[2]==1018-18,'closed: the panel where it was, the log back on it')
assert(hudBegins==0,'native clock can be unavailable without stopping panel')
local function PanelFrame() panelDraws={}; frame(); return panelDraws[1] end
routes={split=true,first={[1]=true},second={[4]=true}}
splitRect={20,520,660,700}
local rect=PanelFrame()
assert(#panelDraws==1 and hooks[0].panel and not hooks[1].panel,'stacked split: the lower log owns one panel')
assert(rect.top==1018-18 and rendered['winxi.chatbox'].pos[2]==1018-18,'under the lower log, which is lifted')
local split=rendered['winxi.chatbox.split']
assert(split.pos[2]==1018-18-150,'the upper log lifted with it, still flush over the lower')
assert(menuSlot==0 and menuBounds.top==split.pos[2]-split.size[2],'native menus above the whole lifted stack')
splitRect={660,700,1000,1018}; rect=PanelFrame()
assert(hooks[0].panel and not hooks[1].panel and rect.left==20,'horizontal logs keep primary anchor')
assert(rendered['winxi.chatbox.split'].pos[2]==1018-18,'both side-by-side logs lifted over the panel')
assert(app.options.infoPanel.window2.enabled[1]==false,'Window 2 Panel off to start')
-- Window 2 Panel: its own panel under the second log beside the first, its own slots, one shared height
local window2=app.options.infoPanel.window2
window2.enabled[1]=true; window2.height[1]=26
rect=PanelFrame()
assert(#panelDraws==2 and hooks[0].panel and hooks[1].panel,'side by side: a panel on each log\'s capture')
local first,secondRect=panelDraws[1],panelDraws[2]
assert(secondRect.left==660 and secondRect.width==340 and secondRect.top==1018-26 and secondRect.height==26,'Window 2\'s under it, its width')
assert(first.top==1018-26 and first.height==26,'the first takes the taller one\'s height')
assert(rendered['winxi.chatbox'].pos[2]==1018-26 and rendered['winxi.chatbox.split'].pos[2]==1018-26,'both logs lifted by it, one bottom')
assert(menuSlot==0 and menuBounds.left==20,'menus still anchor on the first log')
splitRect={20,520,660,700}; PanelFrame()
assert(#panelDraws==1 and hooks[0].panel,'stacked: one panel only, under the lower log')
window2.height[1]=0; window2.enabled[1]=false; splitRect={660,700,1000,1018}
PanelFrame(); assert(#panelDraws==1,'Window 2 Panel off: one panel')
-- Anchor Top: as before the bottom anchor, flush over the upper log; chat, input and menus as the game has them
assert(app.options.infoPanel.anchor[1]==2,'Bottom to start')
app.options.infoPanel.anchor[1]=1
routes=nil; splitRect=nil
rect=PanelFrame()
assert(hooks[0].panel and rect.left==20 and rect.width==640 and rect.height==18 and rect.top==1018-150-18,'top: flush over the log')
assert(rendered['winxi.chatbox'].pos[2]==1018 and menuBounds==rect and menuSlot==0,'top: the log in place, menus above the panel')
local savedTopNative=nativeRect; nativeRect={20,1000,660,1018}
inputOpen=true; inputRaw='hi'; inputDisplay='hi'; inputCaret=2; rect=PanelFrame()
assert(rendered['winxi.chatbox.input'].pos[2]==1018 and rendered['winxi.chatbox'].pos[2]==1000 and rect.top==1000-150-18,
    'top, typing: the input where the game puts it, the log over it, the panel over the log')
inputOpen=false; nativeRect=savedTopNative
routes={split=true,first={[1]=true},second={[4]=true}}
splitRect={20,520,660,700}; rect=PanelFrame()
local upper=rendered['winxi.chatbox.split']
assert(#panelDraws==1 and hooks[1].panel and not hooks[0].panel and menuSlot==1,'top, stacked: the upper log owns it')
assert(rect.top==upper.pos[2]-upper.size[2]-18 and menuBounds==rect,'flush over the upper log')
splitRect={660,700,1000,1018}; window2.enabled[1]=true; window2.height[1]=26; rect=PanelFrame()
assert(#panelDraws==2 and panelDraws[1].top==1018-150-26 and panelDraws[2].left==660
    and panelDraws[2].top==rendered['winxi.chatbox.split'].pos[2]-rendered['winxi.chatbox.split'].size[2]-26,'top, side by side: one over each log, one height')
window2.enabled[1]=false; window2.height[1]=0
app.options.infoPanel.anchor[1]=2
app.options.matchGameLogSize[1]=true
linesState[0]={shown=0,most=8,fewest=0}; linesState[1]={shown=2,most=6,fewest=0}
splitRect={20,520,660,700}; rect=PanelFrame()
assert(#panelDraws==1 and hooks[1].panel and rect.left==20 and rect.top==700-18,'split alone can own the panel')
assert(rendered['winxi.chatbox.split'].pos[2]==700-18,'and is lifted over it')
linesState[1].shown=0; PanelFrame(); assert(#panelDraws==0 and menuBounds==nil,'zero-line logs release the panel and native menu anchor')
linesState={}; app.options.matchGameLogSize[1]=false; routes=nil; splitRect=nil
chatState.expanded=true; PanelFrame(); assert(#panelDraws==0 and menuBounds==nil,'expanded chat suspends panel/menu anchor')
chatState.expanded=false
-- Expand In Place: the game asked, from the compact log, to open its full log on the first log's bottom-left (before
-- its lift over the panel), so it lays it out there from its first frame; the panel hidden while it is open
local savedExpanded=expandedRect
PanelFrame()
assert(#panelDraws==1 and logPlace and logPlace[1]==20 and logPlace[2]==1018,'asked to open on the log\'s own bottom-left, the panel\'s place too')
chatState.expanded=true; expandedRect={20,600,660,1018}; PanelFrame()
assert(logPlace[2]==1018 and #panelDraws==0 and menuBounds==nil,'opened there: the panel hidden')
assert(rendered['winxi.chatbox.expanded'].pos[1]==20 and rendered['winxi.chatbox.expanded'].pos[2]==1018,'the frame on the moved log')
local said4={}; app.Say=function(_,line) said4[#said4+1]=line end
spec.commands.status(); app.Say=function() end
assert(table.concat(said4,'\n'):find('Opened where the chat log stands',1,true),'/chatbox status says so')
chatState.expanded=false; PanelFrame(); assert(#panelDraws==1,'collapsed: the panel back')
app.options.infoPanel.anchor[1]=1; PanelFrame()
assert(logPlace[2]==1018,'Top: on the log\'s own bottom as well')
chatState.expanded=true; PanelFrame(); assert(#panelDraws==0,'Top: hidden while expanded')
chatState.expanded=false; app.options.infoPanel.anchor[1]=2
app.options.expandInPlace[1]=false; local stops=logStops; PanelFrame()
assert(logPlace==nil and logStops==stops+1,'Expand In Place off: given back, the game\'s place')
chatState.expanded=true; PanelFrame(); assert(#panelDraws==0 and logPlace==nil,'off: still no panel while expanded')
chatState.expanded=false; app.options.expandInPlace[1]=true; PanelFrame(); assert(logPlace,'on again')
app.options.enabled[1]=false; frame(); assert(logPlace==nil,'chatbox off gives the log back')
app.options.enabled[1]=true; expandedRect=savedExpanded
app.options.infoPanel.layout.width[1]=800; app.options.infoPanel.layout.height[1]=32
rect=PanelFrame(); assert(rect.width==800 and rect.height==32,'custom panel sizing')
app.options.infoPanel.layout.attached[1]=false
app.options.infoPanel.layout.x[1]=100; app.options.infoPanel.layout.y[1]=50
rect=PanelFrame(); assert(rect.left==100 and rect.top==50,'custom panel position on host capture')
assert(rendered['winxi.chatbox'].pos[2]==1018 and menuBounds==rect,'a detached panel leaves chat in place; menus above the panel')
events.packet_in({id=0x00b}); PanelFrame(); assert(#panelDraws==0,'zoning releases attachment')
events.packet_in({id=0x00a}); PanelFrame(); assert(#panelDraws==1,'zone-in restores attachment with chat')
app.options.infoPanel.anchorMenus[1]=false
PanelFrame(); assert(#panelDraws==1 and menuBounds==nil,'native menu placement can be disabled independently')
app.options.infoPanel.anchorMenus[1]=true
captureOK=false
PanelFrame(); assert(menuBounds==nil,'failed capture never publishes native menu geometry')
captureOK=true
spec.commands.panel(app.options,{'/chatbox','panel','off'})
PanelFrame(); assert(#panelDraws==0 and menuBounds==nil and menuStops>0,'panel off restores native menu placement')
spec.commands.panel(app.options,{'/chatbox','panel','on'})
-- Hide Game Clock: an empty clock replacement renewed each frame, icons with it; off, chatbox off or
-- zoning gives the game's clock back. Works with the panel off.
local clockBegins,clockStops,clockMask=0,0,nil
local compassBegins,compassStops=0,0
package.loaded['winxi.nativehud']={Clock=0,Compass=1,HideDay=1,HideWeather=2,new=function(index)
    if index==1 then return {Begin=function() compassBegins=compassBegins+1; return true end,
        Stop=function() compassStops=compassStops+1 end,Status=function() return 'test compass' end} end
    return {Begin=function() clockBegins=clockBegins+1; return true end,
        Stop=function() clockStops=clockStops+1 end,HideIcons=function(mask) clockMask=mask end,
        Status=function() return 'test clock' end,Grid=function() return nil end,Weather=function() return nil end}
end}
assert(app.options.infoPanel.hideClock[1]==false,'Hide Game Clock off to start')
PanelFrame(); assert(clockBegins==0,'the game\'s clock left alone while off')
assert(app.options.infoPanel.hideCompass[1]==false and compassBegins==0,'Hide Compass off to start, the compass left alone')
spec.commands.clock(app.options,{'/chatbox','clock'})
assert(app.options.infoPanel.hideClock[1]==true,'/chatbox clock toggles it')
PanelFrame(); assert(clockBegins==1 and clockMask==3,'hidden: its text and both icons')
assert(compassBegins==0,'hiding the clock leaves the compass')
spec.commands.compass(app.options,{'/chatbox','compass','hide'})
PanelFrame(); assert(app.options.infoPanel.hideCompass[1]==true and compassBegins==1 and clockBegins==2,'/chatbox compass hide: both hidden')
spec.commands.compass(app.options,{'/chatbox','compass'}); local cs=compassStops; PanelFrame()
assert(app.options.infoPanel.hideCompass[1]==false and compassStops>cs and compassBegins==1 and clockBegins==3,'toggled back: the compass shown, the clock still hidden')
spec.commands.compass(app.options,{'/chatbox','compass','hide'}); PanelFrame(); assert(compassBegins==2)
spec.commands.panel(app.options,{'/chatbox','panel','off'})
PanelFrame(); assert(clockBegins==5 and compassBegins==3,'with the panel off as well')
spec.commands.panel(app.options,{'/chatbox','panel','on'})
events.packet_in({id=0x00b}); local stops=clockStops; cs=compassStops; PanelFrame()
assert(clockStops>stops and compassStops>cs and clockBegins==5 and compassBegins==3,'zoning gives both back')
events.packet_in({id=0x00a}); PanelFrame(); assert(clockBegins==6 and compassBegins==4,'and hides them again after')
spec.commands.off(app.options); stops=clockStops; cs=compassStops; PanelFrame()
assert(clockStops>stops and compassStops>cs and clockBegins==6 and compassBegins==4,'chatbox off gives both back')
spec.commands.compass(app.options,{'/chatbox','compass','show'})
spec.commands.on(app.options)
spec.commands.clock(app.options,{'/chatbox','clock','show'}); stops=clockStops; PanelFrame()
assert(app.options.infoPanel.hideClock[1]==false and clockStops>stops and clockBegins==6,'/chatbox clock show: the game\'s again')
spec.commands.off(app.options); PanelFrame(); assert(#panelDraws==0,'chatbox off stops panel')
spec.commands.on(app.options)
-- Info Panel owns focused subtabs without changing ordinary chat settings.
local activeTab,editors='General',0
imgui.BeginTabBar=function() return true end; imgui.EndTabBar=function() end
imgui.BeginTabItem=function(label) return label:match('^[^#]+')==activeTab end
imgui.EndTabItem=function() end
imgui.InputText=function() editors=editors+1; return false end
imgui.IsAnyItemActive=function() return false end
imgui.SetNextItemWidth=function() end
imgui.SliderFloat=function() return false end
local oldHeader=package.loaded['winxi.widgets'].Header
package.loaded['winxi.widgets'].Header=function() return true end
app.options.infoPanel.window2.enabled[1]=true
for _,name in ipairs({'General','Layout','Data','Window 2','Text','Icons'}) do
    activeTab=name; editors=0
    spec.tabs[1].draw(app.options)
    assert(editors==((name=='Data' or name=='Window 2') and 3 or 0),'Info Panel data editors isolated to the Data and Window 2 subtabs')
end
app.options.infoPanel.window2.enabled[1]=false
package.loaded['winxi.widgets'].Header=oldHeader
-- The game's own history put before chatbox's as it starts: each of the game's lines a message, oldest first, with
-- its colour codes and whole mode word; the newest that chatbox already has left out; once until the next reset
gameLines={{text='[01:00:00] Old say',mode=1},{text='\x1f\x05(Ann) party',mode=0x8005},{text='',mode=1},
    {text='npc replay',mode=190},{text='Already here',mode=1}}
events.unload(); message('Already here',{mode=1}); local requests=historyRequests
chatState.expanded=false; chatState.selected=false; ready=true; inputOpen=false; nativeLogRect={20,700,660,1018}
app.options.infoPanel.layout.enabled[1]=false
frame(); frame()
local texts={}
for _, t in ipairs(text) do texts[#texts+1]=t.text end
local party=select(2,pcall(require('encoding').Decode,'\x1f\x05(Ann) party',false,true))
assert(historyRequests==requests+1 and table.concat(texts,'|')=='[01:00:00] Old say|'..party..'|Already here',
    'the game\'s lines before chatbox\'s, the empty and the replayed left out, the one it has already not twice: '..table.concat(texts,'|'))
assert(text[2].color==require('palette').Mode(5),'in its mode\'s colour')
frame(); assert(historyRequests==requests+1,'read once')
local said5={}; app.Say=function(_,line) said5[#said5+1]=line end; spec.commands.status(); app.Say=function() end
assert(table.concat(said5,'\n'):find('Game history: 2 of the game\'s lines put before chatbox\'s own',1,true),'/chatbox status says so')
events.unload(); frame(); frame(); assert(historyRequests==requests+2,'read again after a reset')
-- timestamps on: a line without one is the rest of the message before it in the same mode, joined back to it
gameLines={{text='[01:00:00] [uihook:party] Party/target',mode=0},{text='[target] on; unload hideparty first.',mode=0},
    {text='[01:00:01] Beet caught a',mode=0x28e},{text='moorish idol!',mode=0x28e},{text='[01:00:02] Doom says hi',mode=1}}
events.unload(); frame(); frame()
texts={}
for _, t in ipairs(text) do texts[#texts+1]=t.text end
assert(table.concat(texts,'|')=='[01:00:00] [uihook:party] Party/target [target] on; unload hideparty first.|[01:00:01] Beet caught a moorish idol!|[01:00:02] Doom says hi',
    'each message whole again: '..table.concat(texts,'|'))
gameLines={{text='[01:00:00] one',mode=1},{text='two',mode=4}}
events.unload(); frame(); frame()
texts={}
for _, t in ipairs(text) do texts[#texts+1]=t.text end
assert(table.concat(texts,'|')=='[01:00:00] one|two','another mode is another message, timestamp or none')
gameLines={{text='no stamp',mode=1},{text='nor here',mode=1},{text='[01:00:00] once',mode=1}}
events.unload(); frame(); frame()
texts={}
for _, t in ipairs(text) do texts[#texts+1]=t.text end
assert(table.concat(texts,'|')=='no stamp|nor here|[01:00:00] once','timestamps mostly off: each line stays a message')
gameLines={}
-- Timestamps, the option: the stamps SimpleLog or the timestamp addon wrote hidden from the compact log, the
-- messages keeping them; /chatbox timestamps [on|off], or none to toggle; kept across a settings load
assert(app.options.timestamps[1]==true,'shown to begin with')
gameLines={{text='[01:00:00] from the game',mode=1}}
events.unload(); frame(); frame()
message('[01:00:01] Hamelin : live'); frame()
texts={}
for _, t in ipairs(text) do texts[#texts+1]=t.text end
assert(table.concat(texts,'|')=='[01:00:00] from the game|[01:00:01] Hamelin : live','with their stamps: '..table.concat(texts,'|'))
local said6={}; app.Say=function(_,line) said6[#said6+1]=line end
local savesBefore=saves
spec.commands.timestamps(app.options,{'/chatbox','timestamps','off'}); frame()
texts={}
for _, t in ipairs(text) do texts[#texts+1]=t.text end
assert(table.concat(texts,'|')=='from the game|Hamelin : live','/chatbox timestamps off: hidden at once, the game\'s history and live lines alike: '..table.concat(texts,'|'))
assert(app.options.timestamps[1]==false and saves==savesBefore+1 and said6[1]:find('hidden',1,true),'the option saved and said')
message('[01:00:02] another'); frame()
assert(text[#text].text=='another','a line arriving while they are hidden')
spec.commands.timestamps(app.options,{'/chatbox','timestamps'}); frame()
assert(app.options.timestamps[1]==true and text[#text].text=='[01:00:02] another' and text[1].text=='[01:00:00] from the game','no verb toggles; the messages kept their stamps')
spec.commands.timestamps(app.options,{'/chatbox','timestamps','sideways'})
assert(app.options.timestamps[1]==true and said6[#said6]:find('[on|off]',1,true),'an unknown verb says how')
app.options.timestamps[1]=false; spec.onSettings(app.options); frame()
message('[01:00:03] settings loaded'); frame()
assert(text[#text].text=='settings loaded','a settings load applies the saved choice')
app.options.timestamps=nil; spec.onSettings(app.options)
assert(app.options.timestamps[1]==true,'a missing option is repaired to shown')
frame(); message('[01:00:04] repaired'); frame(); assert(text[#text].text=='[01:00:04] repaired','and shows them')
app.Say=function() end
-- Each line read through uihook after every addon (uihook 0.8): chatbox's own copy held for the frame and the line
-- kept as uihook has it, so a formatter or filter loaded after chatbox still reaches it
local said7={}; app.Say=function(_,line) said7[#said7+1]=line end
spec.commands.status(); assert(table.concat(said7,'\n'):find('Lines: chatbox\'s own text_in: load formatting addons before it (Load uihook 0.8',1,true),'without the tap, status says lines are chatbox\'s own and why')
spec.commands.clear(); tapReady=true; frame()
local function tapped(l) tapLines=tapLines or {}; tapLines[#tapLines+1]=l end
message('Ann : hi',{mode=9}); frame()
assert(#text==0,'a line arriving is held for uihook\'s copy, not kept as chatbox\'s own')
tapped({serial=1,mode=9,finalMode=9,original='Ann : hi',text='[12:00:00] Ann : hi',modified=true}); frame()
assert(#text==1 and text[1].text=='[12:00:00] Ann : hi','kept as uihook has it: stamped by an addon loaded after chatbox')
said7={}; spec.commands.status(); assert(table.concat(said7,'\n'):find('Lines: read through uihook after every addon; the load order does not matter',1,true),'status says so')
message('The Crab hits you.',{mode=20}); tapped({serial=2,mode=20,finalMode=20,original='The Crab hits you.',text='The Crab hits you.',blocked=true}); frame()
assert(#text==1,'a line a filter loaded after chatbox blocks is not kept')
message('Bob : yo',{mode=9,message_modified='[12:00:01] Bob : yo'}); tapped({serial=3,mode=9,finalMode=9,original='Bob : yo',text='Bob : yo',modified=false}); frame()
assert(text[#text].text=='[12:00:01] Bob : yo','uihook loaded before the addons: its copy the original, chatbox\'s own formatted one kept instead')
message('party line',{mode=1}); tapped({serial=4,mode=1,finalMode=5,original='party line',text='party line',modified=false}); frame()
assert(text[#text].text=='party line' and text[#text].color==require('palette').Mode(5),'a mode an addon changed after chatbox: the line in that mode')
tapped({serial=5,mode=9,finalMode=9,original='unseen',text='unseen',modified=false}); frame()
assert(text[#text].text=='unseen','a line uihook saw and chatbox\'s handler did not is kept too')
message('Ann : hi',{mode=9}); message('Ann : hi',{mode=9})
tapped({serial=6,mode=9,finalMode=9,original='Ann : hi',text='[12:00:02] Ann : hi',modified=true}); tapped({serial=7,mode=9,finalMode=9,original='Ann : hi',text='[12:00:03] Ann : hi',modified=true}); frame()
assert(text[#text-1].text=='[12:00:02] Ann : hi' and text[#text].text=='[12:00:03] Ann : hi','two alike lines in a frame: each matched to its own, in order')
byteReport={}; app.Say=function(_,line) byteReport[#byteReport+1]=line end; spec.commands.bytes()
assert(byteReport[1]:find('final: as uihook read it',1,true) and #byteReport==6 and byteReport[4]:find('^final: 5B 31 32 3A 30 30 3A 30 33'),'the bytes report shows the final stage, uihook\'s copy')
app.Say=function() end
local count=#text
local tapClock,tapRealClock=100,os.clock; os.clock=function() return tapClock end
message('never tapped',{mode=9}); frame(); assert(#text==count,'a held copy uihook has not matched waits')
tapClock=tapClock+1; frame(); assert(text[#text].text=='never tapped','and is kept as chatbox\'s own after half a second')
os.clock=tapRealClock
tapReady=false; message('tap gone',{mode=9}); frame(); assert(text[#text].text=='tap gone','without the tap, each line is kept as it arrives again')
said7={}; app.Say=function(_,line) said7[#said7+1]=line end; spec.commands.status(); assert(table.concat(said7,'\n'):find('Lines: chatbox\'s own',1,true),'status says lines are chatbox\'s own again')
app.Say=function() end
print('Chatbox UI: compact/expanded chat, routing, failure/lifecycle and chat-owned info-panel capture/settings passed')
