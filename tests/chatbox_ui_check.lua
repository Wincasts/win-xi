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
local nativeRect, lastWindowStyle
local rendered = {}
local nativeLogRect = {20,700,660,1018}
local expandedRect={0,100,1920,1020}
local chatState={selected=false,expanded=false,expandedSupported=true,nativeBrowse=false,nested=false,nativeContent=true,nativeControls=true,nativeReplace=true,nativeText=true}
local tabsGeometry, scrollGeometry, rowsGeometry -- where the game drew its tabs, scrollbar and rows of text, as uihook measured them
local splitRect, routes -- the game's second log window, and its routing between the two, as uihook reads them
package.loaded['winxi.nativechat'] = { Primary=0,Secondary=1,Input=2,new=function(index)
    local hook = {begins=0,stops=0,captures=0}
    function hook.Begin() hook.begins=hook.begins+1; return ready end
    function hook.Stop() hook.stops=hook.stops+1 end
    function hook.Capture(expanded,controls,replace)
        hook.expanded,hook.controls=expanded,controls
        hook.replace=replace and {tabs=replace.tabs,scrollbar=replace.scrollbar,text=replace.text} or nil
        assert(sequence[#sequence] == 'border', 'complete decoration captured')
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
local fontDepth, pushedFonts = 0, {}
package.loaded['winxi.fonts'] = {Push=function() return false end,Pop=function() end,
    Get=function(file) if file and file~='' then return 'font:'..file end end, Files=function() return {'arial.ttf'} end}
local headers = {}
package.loaded['winxi.widgets'] = {Header=function(name) return headers[name] end, Label=function() end}
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
    GetIO=function() return { DisplaySize=screen } end,
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
    PushFont=function(font) fontDepth=fontDepth+1; pushedFonts[#pushedFonts+1]=font end,
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
inputOpen=false; stops=hooks[2].stops; frame(); assert(hooks[2].stops>stops,'closed input releases slot')
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
assert(measuredPos[2]==1020 and measuredSize[2]==920,'native expansion takes the full log\'s height, not stale compact geometry')
assert(measuredPos[1]==0 and measuredSize[1]==1920,'expanded frame matches native bounds exactly, not compact width')
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
-- square boxes stacked as the game stacks them (each over the ones drawn before it) with the chosen one on
-- top, each the window's background then the highlight (solid for the chosen one), the tab style over it,
-- an edge, and its name centred in what is left uncovered; a thumb in the game's bar; and the game asked
-- to leave both undrawn, only while there is a fresh place to draw them in
look.BackgroundColor, look.BorderColor = {0.1,0.1,0.2,0.8}, {0.5,0.5,0.5,1}
tabsGeometry={{left=10,top=100,right=64,bottom=116,channel=0,selected=false},
    {left=60,top=100,right=114,bottom=116,channel=3,selected=true},{left=110,top=100,right=160,bottom=116,channel=nil,selected=false}}
scrollGeometry={left=2,top=120,right=6,bottom=1020,page=20,count=100,above=80}
frame()
assert(hooks[0].replace.tabs and hooks[0].replace.scrollbar,'the game asked to leave its tabs and scrollbar undrawn')
assert(#labels==3 and labels[1].text=='Window' and labels[2].text=='Tab 3' and labels[3].text=='Say','drawn in the game\'s order with the chosen tab last; a part of the strip named by channel, an unknown one by its place')
assert(labels[3].x==60+(54-3*7)/2 and labels[3].y>100 and labels[3].y<108 and labels[3].color==look.TextColor,'the chosen tab on top, its name centred in the whole of it, in the title colour')
assert(labels[1].x==10+(50-6*7)/2 and labels[2].x==114+(46-5*7)/2,'the others\' names centred in what the tab over them leaves uncovered')
assert(#filled==8 and filled[1].color==look.BackgroundColor and filled[1].a[1]==10 and filled[1].b[1]==64 and filled[2].color[4]==filled[4].color[4] and filled[6].color[4]>filled[2].color[4],
    'each tab the background then the highlight where the game drew it, the chosen one solid and the rest faint')
assert(#outlines==3 and outlines[3].a[1]==60 and outlines[3].b[1]==114 and outlines[3].color==look.BorderColor,'an edge round each in the border colour, the chosen one\'s last')
assert(#overs==3 and overs[3][1]==60 and overs[3][3]==114 and overs[3][5]==0 and #lines==0,
    'the tab style over each, square-cornered, and no line under the row')
assert(filled[7].a[1]==2 and filled[7].a[2]==120 and filled[7].b[1]==6 and filled[7].b[2]==1020 and filled[8].a[2]==840 and filled[8].b[2]==1020 and filled[8].b[1]==6,
    'the track where the game\'s bar is and, at the newest, the thumb at its foot, as wide as the bar')
assert(#text==0 and #images==0,'still no addon rows or cursor over the native content')
scrollGeometry.above=0; frame()
assert(filled[8].a[2]==120 and filled[8].b[2]==300,'scrolled to the oldest, the thumb at the top')
tabsGeometry[2].channel=10; frame()
assert(labels[3].text=='Assist' or labels[3].text=='Assist (E)','a long name cut to what fits the tab')
tabsGeometry[2].channel=2; frame(); assert(#labels[3].text>0 and ('Linkshell 1'):sub(1,#labels[3].text)==labels[3].text,'the first linkshell\'s tab says Linkshell 1, cut to fit')
local channels=require('channels')
local places={}
for filter, tab in pairs(channels.Filters) do places[tab.place]=tab.name end
assert(table.concat(places,',')=='Window,Say,Tell,Party,Linkshell 1,Linkshell 2,Assist (J),Assist (E),Unity,Shout','the tabs in the game\'s order, named as the game names them')
tabsGeometry[2].channel=3
tabsGeometry[1].selected, tabsGeometry[2].selected = true, false; frame()
assert(labels[3].text=='Window' and labels[3].x==10+(54-6*7)/2 and labels[1].text=='Say' and labels[1].x==64+(46-3*7)/2,
    'another tab chosen: it is drawn last, whole, and the one that lay over it now gives way to it')
tabsGeometry[1].selected, tabsGeometry[2].selected = false, true
-- the whole strip: named by where each stands, left to right, whatever channel its sprite was matched to
local whole={}
for i=1,10 do whole[i]={left=i*50-40+(i>1 and -4 or 0),top=100,right=i*50+10,bottom=116,channel=(i*3)%11,selected=i==4} end
whole[3],whole[7]=whole[7],whole[3] -- drawn in another order than they stand
local before=tabsGeometry; tabsGeometry=whole; frame()
local byLeft={}
for _, l in ipairs(labels) do byLeft[#byLeft+1]=l end
table.sort(byLeft,function(a,b) return a.x<b.x end)
local seen={}
for i, l in ipairs(byLeft) do seen[i]=l.text end
local wanted={'Window','Say','Tell','Party','Linkshell 1','Linkshell 2','Assist (J)','Assist (E)','Unity','Shout'}
for i=1,10 do
    assert(#seen[i]>=3 and wanted[i]:sub(1,#seen[i])==seen[i], 'all ten from the left, each cut to fit: '..i..' is '..seen[i]..', not '..wanted[i])
end
assert(labels[10].text=='Party','the chosen fourth tab drawn last, named for its place')
tabsGeometry=before
-- the game's rows of text replaced: each drawn where the game drew it, in the chat's font no taller than the
-- row and centred in it, in its mode's colour; the cursor after the cursor row's text; decoded once each; and
-- the game asked to leave its text undrawn only while there are fresh rows to draw
rowsGeometry={{left=40,top=820,right=300,bottom=836,text='newest line',mode=1,cursor=false},
    {left=40,top=804,right=200,bottom=820,text='older',mode=12,cursor=true},{left=40,top=788,right=100,bottom=804,text='',mode=1,cursor=false},
    {text='nowhere',mode=1,cursor=false}}
pushedFonts={}; app.options.fontFile='arial.ttf'; decodes=0; frame()
assert(hooks[0].replace.text,'the game asked to leave its text undrawn')
assert(#text==2 and text[1].text=='newest line' and text[1].pos[1]==40 and text[1].pos[2]==822 and text[1].color==require('palette').Mode(1),
    'the newest row where the game drew it, 12px text centred in the 16px row, in its mode\'s colour')
assert(text[2].text=='older' and text[2].pos[2]==806 and text[2].color==require('palette').Mode(12),'the older row in a tell\'s colour')
assert(#images==1 and images[1].a[1]==40+5*7+4 and images[1].a[2]==805,'the cursor after the cursor row\'s text')
assert(pushedFonts[1]=='font:arial.ttf' and decodes==2,'the chat\'s font; the two rows with text decoded, the empty and the unplaced not')
frame(); assert(decodes==2,'the rows decoded once, not every frame')
rowsGeometry[1].text='older'; frame(); assert(decodes==2,'a row already decoded is known by its bytes')
rowsGeometry[1].text='newest line'
local said2={}; app.Say=function(_,line) said2[#said2+1]=line end
spec.commands.status()
assert(table.concat(said2,'\n'):find('WinXI tabs, scrollbar and text where the game\'s are',1,true) and table.concat(said2,'\n'):find('2 drawn',1,true),'/chatbox status says the text is the addon\'s and how many rows were drawn')
app.Say=function() end
app.options.fontSize[1]=24; frame()
assert(text[1].pos[2]==820 and labels[1].y>100,'Font Size past the row\'s height: the row\'s height, the text at the row\'s top')
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
assert(not hooks[0].replace.tabs and hooks[0].replace.scrollbar and #labels==0 and #filled==2,'Replace Tabs off: the game\'s tabs stay, the scrollbar still the addon\'s')
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
imgui.Checkbox=function() return false end
imgui.ColorEdit4=function() return false end
imgui.IsItemDeactivatedAfterEdit=function() return false end
imgui.SameLine=function() end
imgui.TextDisabled=function() end
imgui.SliderInt=function() return false end
imgui.SmallButton=function() return false end
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
assert(spec.tabs == nil and app.options.colors == nil and app.options.combat == nil, 'no channel colour controls or Combat Log tab')
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
local function pearl(name)
    local extra, alphabet = {}, 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
    for i=0,27 do extra[i]=0 end
    for i=1,#name+1 do
        local code=i>#name and 63 or assert(alphabet:find(name:sub(i,i),1,true))
        local offset,shift=9+math.floor((i-1)*6/8),((i-1)*6)%8
        local value=code*2^shift
        extra[offset]=extra[offset]+value%256
        extra[offset+1]=extra[offset+1]+math.floor(value/256)
    end
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
assert(rendered['winxi.chatbox'].style.title=='Linkshell 2: NewShell','equipped pearl changes refresh the name')
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
byteReport={}; spec.commands.clear(); spec.commands.bytes()
assert(#byteReport==1 and byteReport[1]:find('No decode sample',1,true),'clear removes captured diagnostic data')
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
routes=nil; splitRect=nil
imgui.GetIO=oldIO
os.clock=realClock
print('Chatbox UI: compact rows, two log windows routed as the game routes them, native expanded frame/content separation, no custom selection/input, mouse pass-through, menu handoff, failure and lifecycle passed')
