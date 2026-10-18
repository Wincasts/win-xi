package.path='addons/libs/?.lua;'..package.path
local ffi=require('ffi')
local model=require('winxi.nativehistory')
assert(ffi.sizeof('uihook_history_t')==16+36+24*100+65536)
local data=ffi.new('uihook_history_t[1]')
local b=data[0]; b.Version=1; b.Size=ffi.sizeof('uihook_history_t'); b.Frame=42; b.Supported=1
local loaded,base,finds=true,1000,0
AshitaCore={GetPluginManager=function() return {IsLoaded=function(_,name) assert(name=='uihook'); return loaded end} end}
ashita={memory={get_base=function() return base end,find=function(_,_,pattern)
    assert(pattern=='5549484F4F4B2D484953544F52590000'); finds=finds+1; return ffi.cast('uintptr_t',data)
end}}
local function Put(i,text,mode,serial,flags,extra,offset)
    ffi.copy(b.Text+offset,text,#text)
    local l=b.Lines[i]; l.Offset,l.Length,l.Mode,l.Serial,l.Flags,l.Extra=offset,#text,mode,serial,flags,extra
end
local hook=model.new()
assert(hook.Lines()==nil,'nothing before a request')
assert(hook.Request() and b.RequestFrame==42,'a read asked for, stamped with the frame')
assert(hook.Lines()==nil,'nothing until uihook serves it')
Put(0,'Ann : hi',1,7,0x41,0x1234,0); Put(1,'there',1,8,0,0,8); Put(2,'\31\5(Bo) yo',0x8005,9,0x10,0,13)
b.Count,b.Used=3,22; b.Serial=b.Serial+1
local lines=hook.Lines()
assert(#lines==3 and lines[1].text=='Ann : hi' and lines[2].text=='there' and lines[3].text=='\31\5(Bo) yo','the lines, oldest first, as the game was given them')
assert(lines[1].mode==1 and lines[3].mode==0x8005 and lines[1].serial==7 and lines[1].flags==0x41 and lines[1].extra==0x1234,'each line\'s header fields')
assert(hook.Lines()==nil,'served once')
b.Lines[1].Offset=70000; assert(hook.Request()); b.Serial=b.Serial+1
assert(hook.Lines()[2].text=='','a line past the text left empty')
b.Supported=0; local other=model.new(); assert(not other.Request() and other.Status():find('recognise'))
b.Supported=1; b.Version=2; assert(not model.new().Request(),'ABI mismatch refused')
b.Version=1; loaded=false; assert(not model.new().Request(),'no uihook, nothing')
print('Native history: ABI, request and serve once, lines and header fields, bounds, unsupported and missing uihook passed')
