-- DAT parsing and party selection drawing; no installed client or GPU required.
local ffi = require('ffi')
local cursor, mapdat = require('winxi.cursor'), require('winxi.mapdat')
local length = 4192+432
local source = ffi.new('uint8_t[?]',length)
local function u16(at,v) source[at],source[at+1]=v%256,math.floor(v/256)%256 end
local function u32(at,v) u16(at,v%65536);u16(at+2,math.floor(v/65536)) end
u32(4,4192/16*128+0x20)
ffi.copy(source+17,'anc     anc     ',16)
u32(33,40);u32(37,64);u32(41,64);u16(47,8);u32(73,0x44585433)
for at=85,85+4096-1,16 do
    source[at]=0x48
    source[at+8]=0x12 -- compressed colour data must remain untouched
end
local shape=4192
u32(shape+4,432/16*128+0x31)
ffi.copy(source+shape+16,'anc     anc_s   ',16)
source[shape+32]=1
ffi.copy(source+shape+33,'anc     anc     ',16)
source[shape+49]=6
local pos=shape+51
for i=0,5 do
    source[pos]=1
    local piece=pos+1
    u16(piece+16,32);u16(piece+18,20)
    u16(piece+20,math.floor(i/3)*32);u16(piece+22,1+i%3*21)
    ffi.copy(source+piece+45,'anc     anc     ',16)
    pos=piece+61
end
local image,imageLength,frames=cursor.Parse(source,length)
assert(image,imageLength)
assert(imageLength==4224 and #frames==6)
assert(frames[1][1]==0 and frames[1][2]==1/64 and frames[6][3]==1 and frames[6][4]==63/64)
assert(frames[1][5]==32 and frames[1][6]==20, 'DAT dimensions preserved')
assert(image[117]==0x8f and image[125]==0x12 and source[85]==0x48, 'double alpha only, do not alter source or colours')
assert(mapdat.Header(image,imageLength), 'shared texture loader accepts repacked image')
assert(not cursor.Parse(source,8), 'short file rejected')
assert(not cursor.Parse(source,length-16), 'truncated chunk rejected')
u16(shape+52+20,64)
assert(not cursor.Parse(source,length), 'invalid UV rejected')
u16(shape+52+20,0)
source[shape+51]=2
assert(not cursor.Parse(source,length), 'unsupported multipart sprite fails safely')
source[shape+51]=1

-- Successful load caches the texture and does no file I/O per drawn row/frame.
local d3d8=require('d3d8')
local oldRead,oldTexture,oldDevice,oldGC=mapdat.Read,mapdat.Texture,d3d8.get_device,d3d8.gc_safe_release
pcall(ffi.cdef,'typedef struct IDirect3DTexture8 IDirect3DTexture8;')
local reads=0
local function failure(expected)
    local handle,reason=cursor.Get(true)
    assert(not handle and reason==expected, 'exact failure reason: '..tostring(reason))
    local again,cached=cursor.Get()
    assert(not again and cached==reason, 'failure retained during retry delay')
end
d3d8.get_device=function() return nil end
failure('device: Direct3D device unavailable')
d3d8.get_device=function() return {} end
mapdat.Read=function() return nil,'could not open ROM/119/51.DAT' end
failure('DAT read: could not open ROM/119/51.DAT')
mapdat.Read=function() return source,8 end
failure('DAT parse: short menu DAT')
mapdat.Read=function() return source,length end
mapdat.Texture=function() return nil,'the texture could not be locked' end
failure('texture upload: the texture could not be locked')
mapdat.Read=function(path) assert(path=='ROM/119/51.DAT');reads=reads+1;return source,length end
mapdat.Texture=function(_,b,n) assert(mapdat.Header(b,n));return 991 end
d3d8.get_device=function() return {} end
d3d8.gc_safe_release=function(t) return t end
assert(cursor.Get(true)==991, 'forced retry bypasses delay')
assert(cursor.Get()==991 and reads==0, 'cursor texture retained; the DAT parsed by the failed upload is not read again')
mapdat.Read,mapdat.Texture,d3d8.get_device,d3d8.gc_safe_release=oldRead,oldTexture,oldDevice,oldGC

local draw,partyFrames,options=require('draw'),require('frames'),require('options')
local oldImage,oldText,oldGet=draw.Image,draw.Text,cursor.Get
local images,words,positions={},{},{}
draw.Image=function(handle,x1,y1,x2,y2,packed,u1,v1,u2,v2)
    if handle==991 then images[#images+1]={x1,y1,x2,y2,u1,v1,u2,v2} end
end
draw.Text=function(x,y,color,text) words[#words+1]=text;positions[text]={x,y} end
local members={}
local selectionFlags={'isTarget','isSubTarget','isPartyTarget'}
for i,flag in ipairs(selectionFlags) do
    members[i]={name='Selected'..i,serverId=200+i,isInZone=true,hpp=80,hp=1000,mpp=60,mp=500,tp=1000,statusIds={}}
    members[i][flag]=true
end
local style=options.Style(H.options())
partyFrames.Draw(members,'party',nil,style)
assert(#images==3, 'image cursor for target, subtarget and native party cursor')
for _,text in ipairs(words) do assert(not text:find('>',1,true), 'no text arrows when image available') end
for _,image in ipairs(images) do
    assert(math.abs((image[3]-image[1])/(image[4]-image[2])-32/20)<0.0001, 'cursor aspect ratio preserved')
    assert(image[5]>=0 and image[6]>=0 and image[7]<=1 and image[8]<=1)
end
local selectedPositions=positions
for i,image in ipairs(images) do
    assert(image[3]<selectedPositions[members[i].name][1], 'cursor overlays to the left of the name')
end
for i,flag in ipairs(selectionFlags) do members[i][flag]=false end
images,words,positions={},{},{}
partyFrames.Draw(members,'party',nil,style)
assert(#images==0)
for i,flag in ipairs(selectionFlags) do
    local before,after=selectedPositions[members[i].name],positions[members[i].name]
    assert(before[1]==after[1] and before[2]==after[2], 'targeting does not shift or truncate the name')
    members[i][flag]=true
end
cursor.Get=function() return nil end
images,words,positions={},{},{}
partyFrames.Draw(members,'alliance',nil,style)
local main,sub=false,false
for _,text in ipairs(words) do
    main=main or text=='>> '
    sub=sub or text=='> '
end
assert(#images==0 and main and sub, 'failed cursor load restores text markers')
for _,member in ipairs(members) do
    assert(positions[member.name][1]==selectedPositions[member.name][1], 'fallback does not indent the name either')
end
draw.Image,draw.Text,cursor.Get=oldImage,oldText,oldGet
local wasShowing=H.options().showConfig[1]
assert(H.command('/pt cursor'))
assert(H.options().showConfig[1]==wasShowing, 'cursor diagnostic does not open settings')
assert(H.printed[#H.printed]:find('Native cursor loaded:',1,true))
cursor.Get=function(force) assert(force);return nil,'DAT parse: cursor is not a DXT3 atlas' end
assert(H.command('/pt cursor'))
assert(H.printed[#H.printed]:find('Native cursor unavailable: DAT parse: cursor is not a DXT3 atlas',1,true))
cursor.Get=oldGet
H.print('Native DAT cursor: six sprite frames, UVs, alpha, malformed files, caching, selection drawing and fallback passed')
