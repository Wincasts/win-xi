-- Standalone native chat bridge contract; callbacks mocked, no client needed.
local ffi = require('ffi')
local block = {Version=13,Size=71684,Submit=123,SupportedMask=2047,Frame=10,
    NativeFrame={[0]=10,[1]=0,[2]=0},DrawnFrame={[0]=10,[1]=0,[2]=0},
    InputRect={[0]=0,[1]=0.9,[2]=1,[3]=1},InputRectFrame=10,
    PrimaryRect={[0]=0.05,[1]=0.5,[2]=0.5,[3]=0.9},PrimaryRectFrame=10,
    ExpandedRect={[0]=0,[1]=0.1,[2]=1,[3]=0.9},ExpandedRectFrame=10,
    StateFlags=0,StateFrame=10,FullScroll=0,FullCursor=20,FullPageRows=20,FullFilter=0,
    ControlStyleFrame=0,ControlColors={[0]={},[1]={},[2]={},[3]={}},
    ReplaceControls=0,TabFrame=0,TabCount=0,Tabs={},ScrollFrame=0,ScrollPage=0,ScrollCount=0,ScrollTop=0,ScrollRect={[0]=0,[1]=0,[2]=0,[3]=0},
    TextFrame=0,TextCount=0,TextSerial=0,Rows={},Text=ffi.new('char[65536]'),
    SplitRect={[0]=0.05,[1]=0.3,[2]=0.5,[3]=0.5},SplitRectFrame=0,WindowFrame=0,WindowFlags=0,WindowModes={[0]={},[1]={}},
    LinesFrame=0,Lines={[0]={[0]=0,[1]=0,[2]=0},[1]={[0]=0,[1]=0,[2]=0}},
    ColorFrame=0,ColorSerial=0,InlineColors={},CategoryColors={},ModeCategory={}}
for i=0,16 do block.InlineColors[i]=0 end
for i=0,255 do block.CategoryColors[i]=0; block.ModeCategory[i]=0 end
for w=0,1 do for i=0,7 do block.WindowModes[w][i]=0 end end
for i=0,11 do block.Tabs[i]={Rect={[0]=0,[1]=0,[2]=0,[3]=0},Channel=0,Selected=0} end
for i=0,127 do block.Rows[i]={Rect={[0]=0,[1]=0,[2]=0,[3]=0},Offset=0,Length=0,Mode=0,Flags=0} end
local loaded, base, address, now, result = false, 100, 500, 0, 1
local calls, scans = {}, 0
package.loaded.ffi = {cdef=ffi.cdef,sizeof=ffi.sizeof,string=ffi.string,cast=function(kind)
    if kind == 'uihook_chat_t*' then return block end
    assert(kind == 'uihook_chat_submit_t')
    return function(index, capture) calls[#calls+1]={index,capture}; return result end
end}
os.clock=function() return now end
AshitaCore={GetPluginManager=function() return {IsLoaded=function(_,name) assert(name=='uihook'); return loaded end} end}
ashita={memory={get_base=function(name) assert(name=='uihook.dll'); return base end,
    find=function(name,offset,pattern)
        assert(name=='uihook.dll' and offset==0)
        assert(pattern:gsub('..',function(h) return string.char(tonumber(h,16)) end)=='UIHOOK-CHAT'..string.rep('\0',5))
        scans=scans+1; return address
    end}}
local native=dofile('addons/libs/winxi/nativechat.lua')
assert(ffi.sizeof('uihook_chat_t')==71684)
local primary, split, input=native.new(native.Primary),native.new(native.Secondary),native.new(native.Input)
assert(not primary.Begin() and #calls==0)
loaded=true; block.Version=12
assert(not primary.Begin() and primary.Status():find('ABI mismatch'))
block.Version=13; now=2
assert(primary.Begin() and primary.Capture())
assert(calls[#calls][1]==0 and calls[#calls][2]==1)
block.ReplacementRect = {[0]=8,[1]=800,[2]=648,[3]=1000}
block.ReplacementRectFrame = 10
local observer = native.new(native.Primary)
local count = #calls
local l,t,r,b = observer.ClockAnchor()
assert(l==8 and t==800 and r==648 and b==1000 and #calls==count, 'clock observes actual replacement pixels without submitting')
assert(split.ClockAnchor()==nil and input.ClockAnchor()==nil)
block.StateFlags=4; assert(observer.ClockAnchor()==nil, 'expanded log does not attach clock'); block.StateFlags=0
block.PrimaryRectFrame=7; assert(observer.ClockAnchor()==nil, 'stale anchor expires'); block.PrimaryRectFrame=10
-- the replacement's place is the addon's, good for eight frames as uihook has it
block.ReplacementRectFrame=2; assert(observer.ClockAnchor()~=nil, 'a place sent eight frames ago still holds')
block.ReplacementRectFrame=1; assert(observer.ClockAnchor()==nil, 'past eight it expires'); block.ReplacementRectFrame=10
block.DrawnFrame[0]=7; assert(observer.ClockAnchor()==nil); block.DrawnFrame[0]=10
block.NativeFrame[0]=7; assert(observer.ClockAnchor()==nil); block.NativeFrame[0]=10
block.ReplacementRect[2]=8; assert(observer.ClockAnchor()==nil); block.ReplacementRect[2]=648
block.ReplacementRect[0]=0/0; assert(observer.ClockAnchor()==nil); block.ReplacementRect[0]=8
assert(primary.Capture(true) and calls[#calls][1]==0 and calls[#calls][2]==2,
    'expanded capture explicitly requests frame-only native content')
local controls={{0.2,0.4,0.8,0.6},{1,0.9,0.8,1},{0.7,0.8,1,1},{1,1,1,0.7}}
assert(primary.Capture(true,controls) and block.ControlStyleFrame==block.Frame)
assert(block.ControlColors[0][2]==0.8 and block.ControlColors[3][3]==0.7,'RGBA controls copied separately from native state')
controls[2][1]=0/0
assert(primary.Capture(true,controls) and block.ControlStyleFrame==0,'invalid theme falls back to untinted native controls')
controls[2][1]=1
assert(primary.Capture(true,controls) and block.ControlStyleFrame==block.Frame)
assert(primary.Capture() and block.ControlStyleFrame==0,'compact capture cannot retain expanded tints')
block.SupportedMask=31
assert(primary.Capture(true,controls) and block.ControlStyleFrame==0,'optional controls capability is independent of frame capture')
block.SupportedMask=2047
assert(primary.Capture(true,controls)); primary.Stop()
assert(block.ControlStyleFrame==0,'release invalidates shared colour stamp')
-- which of the game's controls the addon draws itself: written with an expanded capture, where uihook can hide them
assert(primary.Begin() and primary.Capture(true,controls,{tabs=true,scrollbar=true}) and block.ReplaceControls==3,'tabs and scrollbar asked for')
assert(primary.Capture(true,controls,{tabs=true}) and block.ReplaceControls==1,'tabs alone')
assert(primary.Capture(true,controls,{scrollbar=true}) and block.ReplaceControls==2,'the scrollbar alone')
assert(primary.Capture(true,controls) and block.ReplaceControls==0,'nothing asked, nothing hidden')
assert(primary.Capture(true,controls,{tabs=true}) and primary.Capture() and block.ReplaceControls==0,'a compact capture hides nothing')
block.SupportedMask=63
assert(primary.Capture(true,controls,{tabs=true,scrollbar=true,text=true}) and block.ReplaceControls==0 and not primary.State().nativeReplace and not primary.State().nativeText,'without the hooks nothing is asked')
block.SupportedMask=2047
assert(primary.Capture(true,controls,{tabs=true,scrollbar=true,text=true}) and block.ReplaceControls==7,'the text as well')
assert(primary.Capture(true,controls,{text=true}) and block.ReplaceControls==4,'the text alone')
assert(primary.Capture(true,controls,{tabs=true,scrollbar=true,text=true,all=true}) and block.ReplaceControls==7 and not primary.State().nativeMirror,'an older uihook: the whole log not asked for')
block.SupportedMask=4095
assert(primary.Capture(true,controls,{tabs=true,scrollbar=true,text=true,all=true}) and block.ReplaceControls==15 and primary.State().nativeMirror,'all of it')
assert(primary.Capture(true,controls,{tabs=true,text=true,all=true}) and block.ReplaceControls==13,'all of it with no scrollbar to draw')
assert(primary.Capture(true,controls,{scrollbar=true,text=true,all=true}) and block.ReplaceControls==6,'not the whole log without the addon\'s tabs')
assert(primary.Capture(true,controls,{tabs=true,scrollbar=true,all=true}) and block.ReplaceControls==3,'nor without its text')
block.SupportedMask=2047
block.SupportedMask=127
assert(primary.Capture(true,controls,{tabs=true,text=true}) and block.ReplaceControls==1 and not primary.State().nativeText,'without the row site the text is not asked for')
block.SupportedMask=2047
assert(primary.Capture(true,controls,{tabs=true}) and block.ReplaceControls==1); primary.Stop()
assert(block.ReplaceControls==0,'release asks for nothing')
assert(primary.State().nativeReplace and primary.State().nativeText,'the hooks are known')
-- where the game drew its tabs and scrollbar: scaled to the display, the tabs left to right, nothing stale
assert(primary.Tabs(1920,1080)==nil and primary.Scrollbar(1920,1080)==nil,'nothing measured yet')
block.TabFrame=10; block.TabCount=3
block.Tabs[0].Rect[0],block.Tabs[0].Rect[1],block.Tabs[0].Rect[2],block.Tabs[0].Rect[3]=0.1,0.05,0.15,0.08; block.Tabs[0].Channel=3; block.Tabs[0].Selected=1
block.Tabs[1].Rect[0],block.Tabs[1].Rect[1],block.Tabs[1].Rect[2],block.Tabs[1].Rect[3]=0.0,0.05,0.1,0.08; block.Tabs[1].Channel=0
block.Tabs[2].Rect[0],block.Tabs[2].Rect[1],block.Tabs[2].Rect[2],block.Tabs[2].Rect[3]=0.15,0.05,0.2,0.08; block.Tabs[2].Channel=4294967295
local tabs=primary.Tabs(1920,1080)
assert(#tabs==3 and tabs[1].channel==3 and tabs[2].channel==0 and tabs[3].channel==nil,'in the game\'s draw order, the channel of each, none for an unknown sprite')
assert(tabs[1].left==192 and tabs[1].top==54 and tabs[1].right==288 and tabs[1].bottom==86.4 and tabs[1].selected and not tabs[2].selected,'display pixels; the chosen one')
assert(split.Tabs(1920,1080)==nil and input.Tabs(1920,1080)==nil,'the primary slot\'s alone')
block.Tabs[1].Rect[2]=0.0; assert(#primary.Tabs(1920,1080)==2,'a tab that is no rectangle is left out')
block.TabCount=0; assert(primary.Tabs(1920,1080)==nil,'no tabs, nothing'); block.TabCount=3
block.Frame=13; assert(primary.Tabs(1920,1080)==nil,'stale tabs expire'); block.Frame=10
block.ScrollFrame=10; block.ScrollPage=20; block.ScrollCount=75; block.ScrollTop=30
block.ScrollRect[0],block.ScrollRect[1],block.ScrollRect[2],block.ScrollRect[3]=0.005,0.1,0.01,0.9
local bar=primary.Scrollbar(1920,1080)
assert(bar.left==9.6 and bar.top==108 and bar.right==19.2 and bar.bottom==972 and bar.page==20 and bar.count==75 and bar.above==30,'the scrollbar\'s place and rows')
block.ScrollTop=80; assert(primary.Scrollbar(1920,1080)==nil,'more above than there are rows is no scrollbar'); block.ScrollTop=30
block.ScrollFrame=0; assert(primary.Scrollbar(1920,1080)==nil,'none drawn, none'); block.ScrollFrame=10
block.SupportedMask=63; assert(primary.Tabs(1920,1080)==nil and primary.Scrollbar(1920,1080)==nil,'without the hooks, nothing'); block.SupportedMask=2047
block.TabFrame=0
-- the game's rows of text: in its order, each with its bytes, mode, flags and place, scaled to the display; the
-- same table while the serial holds; nothing stale, nothing without the row site
assert(primary.Rows(1920,1080)==nil,'no rows yet')
block.TextFrame=10; block.TextCount=3; block.TextSerial=1
ffi.copy(block.Text,'hello\31\2world'); ffi.copy(block.Text+12,'older')
block.Rows[0].Offset,block.Rows[0].Length,block.Rows[0].Mode,block.Rows[0].Flags=0,12,1,1+16
block.Rows[0].Rect[0],block.Rows[0].Rect[1],block.Rows[0].Rect[2],block.Rows[0].Rect[3]=0.02,0.5,0.2,0.515
block.Rows[1].Offset,block.Rows[1].Length,block.Rows[1].Mode,block.Rows[1].Flags=12,5,12,4+8+16+32
block.Rows[1].Rect[0],block.Rows[1].Rect[1],block.Rows[1].Rect[2],block.Rows[1].Rect[3]=0.02,0.485,0.1,0.5
block.Rows[2].Offset,block.Rows[2].Length,block.Rows[2].Mode,block.Rows[2].Flags=17,0,1,2
local rows=primary.Rows(1920,1080)
assert(#rows==3 and rows[1].text=='hello\31\2world' and rows[1].mode==1 and rows[1].cursor and not rows[1].marked and not rows[1].cut,'the newest first, its bytes with the colour code, its mode, the cursor on it')
assert(rows[1].left==38.4 and rows[1].top==540 and rows[1].right==384 and rows[1].bottom==556.2,'its place in display pixels')
assert(rows[2].text=='older' and rows[2].mode==12 and rows[2].marked and rows[2].cut and not rows[2].cursor and rows[2].top==523.8 and rows[2].lit and not rows[1].lit,'the older one, marked, cut and under the game\'s highlight')
assert(rows[3].text=='' and rows[3].left==nil and rows[3].mode==1 and rows[3].pressed and not rows[1].pressed,'an empty row without a place, pressed')
assert(primary.Rows(1920,1080)==rows,'the same table while the rows are what they were')
assert(primary.Rows(1280,720)~=rows and primary.Rows(1280,720)[1].left==25.6,'another display, scaled anew')
block.TextSerial=2; assert(primary.Rows(1920,1080)~=rows,'rows changed: a new table')
assert(split.Rows(1920,1080)==nil and input.Rows(1920,1080)==nil,'the primary slot\'s alone')
block.TextSerial=3; block.Rows[0].Offset=65535; assert(primary.Rows(1920,1080)[1].text=='','text past the room is none'); block.Rows[0].Offset=0
block.TextSerial=4; block.TextCount=0; assert(primary.Rows(1920,1080)==nil,'no rows, nothing'); block.TextCount=3; block.TextSerial=5
block.Frame=13; assert(primary.Rows(1920,1080)==nil,'stale rows expire'); block.Frame=10
block.SupportedMask=127; assert(primary.Rows(1920,1080)==nil,'without the row site, nothing'); block.SupportedMask=2047
block.TextFrame=0
-- the game's routing between its two log windows: the second's place, and which modes each window keeps; the same
-- table while it holds; nothing stale, nothing without the routing hooks
assert(split.Rect(1920,1080)==nil and primary.Routes()==nil,'no second window yet')
block.SplitRectFrame=10
local sl,st,sr,sb=split.Rect(1920,1080)
assert(sl==96 and st==324 and sr==960 and sb==540,'the second log window\'s place in display pixels')
assert(split.Rect(1920,1080,true)==nil,'the split slot has no expanded bounds')
block.WindowFrame=10; block.WindowFlags=1
block.WindowModes[0][0]=2+512; block.WindowModes[1][0]=32+8192; block.WindowModes[1][6]=bit.lshift(1,19) -- the first says 1 and 9, the second party 5 and 13, and 211
local routes=primary.Routes()
assert(routes.split and routes.first[1] and routes.first[9] and not routes.first[5] and routes.second[5] and routes.second[13] and routes.second[211] and not routes.second[1],'each window\'s modes')
assert(native.Shows(routes,1,1) and not native.Shows(routes,1,5) and native.Shows(routes,2,5) and not native.Shows(routes,2,1),'Shows by the window\'s set')
assert(native.Shows(routes,1,0x8005) and not native.Shows(routes,2,0x8005),'a mode word with bit 15: the first window alone')
assert(native.Shows(routes,1,0x105) == false and native.Shows(routes,2,0x105),'other high bits are not the mode')
assert(not native.Shows(routes,3,1),'no third window')
assert(primary.Routes()==routes,'the same table while the routing holds')
block.WindowModes[0][0]=2+512+32; assert(primary.Routes()~=routes and primary.Routes().first[5],'a change: a new table')
block.WindowFlags=0; routes=primary.Routes()
assert(not routes.split and native.Shows(routes,1,5) and native.Shows(routes,1,99) and not native.Shows(routes,2,5),'the second window hidden: the first shows everything, the second nothing')
assert(native.Shows(nil,1,5) and not native.Shows(nil,2,5),'without routes the same')
assert(split.Routes()==nil and input.Routes()==nil,'the primary slot\'s alone')
block.Frame=13; assert(primary.Routes()==nil and split.Rect(1920,1080)==nil,'stale routing and place expire'); block.Frame=10
block.SupportedMask=255; assert(primary.Routes()==nil and split.Rect(1920,1080)==nil,'without the routing hooks, nothing'); block.SupportedMask=2047
block.WindowFrame=0; block.SplitRectFrame=0
-- each window's lines as the game has them now; the same table while they hold; nothing stale, nothing without the hooks
assert(primary.Lines()==nil and split.Lines()==nil,'no lines yet')
block.LinesFrame=10; block.Lines[0][0],block.Lines[0][1],block.Lines[0][2]=3,8,0; block.Lines[1][0],block.Lines[1][1],block.Lines[1][2]=0,6,2
local lines=primary.Lines()
assert(lines.shown==3 and lines.most==8 and lines.fewest==0,'the first at three of eight')
assert(split.Lines().shown==0 and split.Lines().most==6 and split.Lines().fewest==2,'the second at none of six, two its fewest')
assert(primary.Lines()==lines,'the same table while they hold')
block.Lines[0][0]=4; assert(primary.Lines()~=lines and primary.Lines().shown==4,'a change: a new table')
assert(input.Lines()==nil,'the input has no lines')
block.Frame=13; assert(primary.Lines()==nil,'stale lines expire'); block.Frame=10
block.SupportedMask=511; assert(primary.Lines()==nil and not primary.State().nativeLines,'without the lines hooks, nothing'); block.SupportedMask=2047
assert(primary.State().nativeLines,'the hooks known')
block.LinesFrame=0
-- the game's colours: a mode's, by its category; what a 1E or 1F code names; the game's white for the unknown; nil for
-- a return to the row's colour; the same table while the serial holds
assert(primary.Colors()==nil,'no colours yet')
block.ColorFrame=10; block.ColorSerial=1
block.ModeCategory[1]=0x54; block.ModeCategory[4]=0x56; block.ModeCategory[0x14]=0x63
block.CategoryColors[0x54]=0x80808080; block.CategoryColors[0x56]=0x80D84C64; block.CategoryColors[0x63]=0x80FF3C3C; block.CategoryColors[0x51]=0xFF5020FF
block.InlineColors[2]=0x4040C000; block.InlineColors[6]=0x60108080
local colors=primary.Colors()
local function near(c,r,g,b,a) return c and math.abs(c[1]-r)<0.01 and math.abs(c[2]-g)<0.01 and math.abs(c[3]-b)<0.01 and math.abs(c[4]-a)<0.01 end
assert(near(colors.Mode(1),1,1,1,1),'say: the game\'s 80808080 is white at its unity')
assert(near(colors.Mode(4),1,0.59375,0.78125,1),'a tell: pink, the red component past one clamped')
assert(near(colors.Mode(0x14),1,0.46875,0.46875,1) and near(colors.Mode(0x8014),1,0.46875,0.46875,1),'damage by another: red; the low byte is the mode')
assert(near(colors.Mode(7),1,1,1,1),'a mode the game has no entry for: the game\'s 80808080, white')
assert(near(colors.Inline(0x1e,0x51),0.625,0.25,1,1),'1E 51 names a category: Ashita\'s timestamp purple')
assert(near(colors.Inline(0x1e,6),0.125,1,1,0.75),'1E 06 from the palette, three quarters opaque')
assert(colors.Inline(0x1e,1)==nil and colors.Inline(0x1e,0)==nil and colors.Inline(0x1e,9)==nil,'1E 01, 1E 00 and an unset palette slot return to the row\'s colour')
assert(near(colors.Inline(0x1f,4),1,0.59375,0.78125,1) and colors.Inline(0x1f,1)==nil and near(colors.Inline(0x1f,7),1,1,1,1),'1F names a mode; 1F 01 the row\'s colour; an unknown mode white')
assert(colors.Inline(0x20,4)==nil and colors.Mode(nil)==nil,'other banks and no mode: nothing')
assert(primary.Colors()==colors,'the same table while the serial holds')
block.ColorSerial=2; assert(primary.Colors()~=colors,'a change: a new table')
assert(split.Colors()==nil and input.Colors()==nil,'the primary slot\'s alone')
block.Frame=13; assert(primary.Colors()==nil,'stale colours expire'); block.Frame=10
block.SupportedMask=1023; assert(primary.Colors()==nil and not primary.State().nativeColors,'without the colour hooks, nothing'); block.SupportedMask=2047
assert(primary.State().nativeColors,'the hooks known')
block.ColorFrame=0
assert(primary.Begin())
assert(split.Begin() and calls[#calls][1]==1)
assert(input.Begin() and input.Capture() and calls[#calls][1]==2)
input.Stop(); assert(calls[#calls][1]==2 and calls[#calls][2]==-1, 'input stop cannot release logs')
primary.Stop(); assert(calls[#calls][1]==0 and calls[#calls][2]==-1)
local l,t,r,b=input.Rect(1920,1080)
assert(l==0 and t==972 and r==1920 and b==1080, 'input geometry maps normalized native bounds to display pixels')
local pl,pt,pr,pb=primary.Rect(1920,1080)
assert(pl==96 and pt==540 and pr==960 and pb==972, 'primary log anchor uses its own native rectangle')
local el,et,er,eb=primary.Rect(1920,1080,true)
assert(el==0 and et==108 and er==1920 and eb==972, 'expanded geometry independent of compact anchor')
assert(input.Rect(1920,1080,true)==nil, 'input cannot read expanded log bounds')
local state=primary.State(); assert(not state.selected and not state.expanded and state.expandedSupported and state.nativeContent and state.nativeControls and state.nativeReplace and state.nativeText)
block.StateFlags=1; assert(primary.State().selected and primary.State().selectedWindow==1 and not primary.State().expanded, 'native selector focus')
block.StateFlags=2; assert(primary.State().selected and primary.State().selectedWindow==2, 'the second window\'s focus')
block.StateFlags=0; assert(primary.State().selectedWindow==nil and primary.State().nativeWindows, 'no focus; the routing hooks known')
block.StateFlags=4; state=primary.State(); assert(state.expanded and not state.nativeBrowse and state.pageRows==20)
block.StateFlags=12; assert(primary.State().nativeBrowse, 'native history/menu fallback')
block.StateFlags=20; state=primary.State(); assert(state.expanded and state.nested and not state.nativeBrowse, 'a menu open over the live full log')
block.Frame=13; assert(primary.State()==nil and primary.Rect(1920,1080,true)==nil, 'state/full bounds expire')
block.Frame=10; block.StateFlags=0
assert(split.Rect(1920,1080)==nil and input.Rect(0,1080)==nil, 'no split geometry without a fresh place; invalid display rejected')
block.PrimaryRectFrame=0; assert(primary.Rect(1920,1080)==nil and input.Rect(1920,1080)~=nil, 'log/input geometry independent')
block.PrimaryRectFrame=10
block.Frame=13; assert(primary.Rect(1920,1080)==nil, 'stale primary geometry expires')
block.Frame=10
block.Frame=13; assert(input.Rect(1920,1080)==nil, 'stale input geometry expires')
block.Frame=10; block.InputRectFrame=0; assert(input.Rect(1920,1080)==nil)
block.InputRectFrame=10; block.InputRect[2]=0/0; assert(input.Rect(1920,1080)==nil)
block.InputRect[2]=0; assert(input.Rect(1920,1080)==nil)
block.InputRect[2]=1
assert(split.Capture() and calls[#calls][1]==1,'primary stop leaves split alone')
result=0; assert(not split.Capture() and calls[#calls][2]==-1,'failed capture releases empty Begin')
result=1; block.SupportedMask=15
assert(primary.Begin() and not primary.Capture(true) and calls[#calls][2]==-1,
    'missing content capability releases the log rather than hiding native rows')
assert(input.Begin() and not input.Capture(true) and calls[#calls][1]==2 and calls[#calls][2]==-1,
    'frame-only capture is restricted to primary slot')
block.SupportedMask=1
assert(not split.Begin() and not input.Begin() and primary.Begin(),'unsupported split/input do not disable primary')
local n,d=primary.Ages(); assert(n==0 and d==0)
block.Frame=13; n,d=primary.Ages(); assert(n==3 and d==3 and primary.Status():find('not drawing'))
local count=#calls
loaded=false; primary.Stop(); assert(#calls==count and not primary.Capture(),'no stale DLL calls')
loaded=true; base=200; address=0; now=4
assert(not primary.Begin()); local previous=scans
assert(not primary.Begin() and scans==previous,'missing block scan throttled')
base=300; address=600
assert(primary.Begin(),'reload resets scan throttle')
base=400
assert(not primary.Capture(),'new DLL cannot inherit old ownership')
assert(primary.Begin()); block.SupportedMask=0
assert(not primary.Begin() and primary.Status():find('not recognise'))
print('Native chat bridge: ABI, marker, slot isolation, rows of text, window routing, failure release, expiry, unload/reload passed')
