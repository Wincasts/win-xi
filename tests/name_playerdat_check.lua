-- CPU DAT parser plus mocked upload/read path; optional argument checks a real menu DAT.
package.path = 'addons/name/?.lua;addons/libs/?.lua;' .. package.path
local ffi = require('ffi')
local mapdat = require('winxi.mapdat')
local dat = require('playerdat')
local function put16(b, at, value) value = value % 65536; b[at], b[at+1] = value % 256, math.floor(value/256) end
local function put32(b, at, value) put16(b,at,value%65536); put16(b,at+2,math.floor(value/65536)) end
local function align(n) return math.ceil(n/16)*16 end
local function fixture(width)
    local picSize = align(85 + width*width)
    local shapeSize = align(51 + 36*62 + 61)
    local size = picSize + shapeSize
    local b = ffi.new('uint8_t[?]',size)
    put32(b,4,picSize/16*128+0x20)
    ffi.copy(b+17,'menu    ustatshd',16)
    put32(b,33,40); put32(b,37,width); put32(b,41,width)
    put16(b,45,1); put16(b,47,32); put32(b,73,0x44585433)
    for at = 85,85+width*width-1,16 do
        for i = 0,7 do b[at+i] = 0x84 end
        for i = 8,15 do b[at+i] = 0xAB end
    end
    put32(b,picSize+4,shapeSize/16*128+0x31)
    ffi.copy(b+picSize+16,'font    fontshp ',16)
    b[picSize+32],b[picSize+48],b[picSize+49] = 1,0x8E,36
    local cursor, pieces = picSize+51, {}
    local function piece(at, overlay, byte)
        local xy = overlay and {-1,-1,7,-1,-1,7,7,7} or {0,0,16,0,0,16,16,16}
        for i,v in ipairs(xy) do put16(b,at+(i-1)*2,v) end
        local side = width/8
        put16(b,at+16,side); put16(b,at+18,side)
        put16(b,at+20,byte==0x92 and width/2 or 0); put16(b,at+22,byte==0x92 and width/2 or 0)
        ffi.copy(b+at+45,'menu    ustatshd',16)
    end
    for byte = 0x8E,0xB1 do
        local count = byte==0xAC and 2 or 1
        b[cursor] = count
        pieces[byte] = cursor+1
        cursor=cursor+1
        for i=1,count do piece(cursor,i==2,byte); cursor=cursor+61 end
    end
    return b,size,picSize,pieces
end
local bytes,length,shape,pieces = fixture(256)
local parsed = assert(dat.Parse(bytes,length))
local header = assert(mapdat.Header(parsed.image,parsed.length))
assert(header.width==256 and parsed.image[header.at]==0xF8 and bytes[85]==0x84,
    'double/saturate both alpha nibbles without modifying input')
assert(parsed.image[header.at+8]==0xAB, 'colour blocks must remain unchanged')
local pearl = parsed.places[0x92]
assert(pearl[1]==.5 and pearl[2]==.5 and pearl[3]==.625 and pearl[4]==.625,
    'use DAT mapping, not fixed bundled rectangles')
local overlay=parsed.overlays[0xAC][1]
assert(overlay[1]==-1/16 and overlay[2]==-1/16 and overlay[3]==7/16 and overlay[4]==7/16)
assert(not parsed.overlays[0xAD] and parsed.places[0xAD] and not parsed.places[0x20])
local large,largeSize = fixture(512)
local hd=assert(dat.Parse(large,largeSize))
assert(mapdat.Header(hd.image,hd.length).width==512 and hd.places[0x92][1]==.5)
local function rejected(change)
    local b,n,s,p = fixture(256)
    change(b,n,s,p)
    local value,why=dat.Parse(b,n)
    assert(value==nil and type(why)=='string')
end
assert(not dat.Parse(nil,0))
assert(not dat.Parse(bytes,15))
assert(not dat.Parse(bytes,length-1))
rejected(function(b) put32(b,4,0) end)
rejected(function(b) put32(b,73,0x44585431) end)
rejected(function(b) put32(b,37,8193) end)
rejected(function(b) put32(b,37,8192) end) -- payload too short
rejected(function(b,n,s) b[s+32]=255 end) -- table outside chunk
rejected(function(b,n,s) b[s+49]=0 end)
rejected(function(b,n,s) b[s+48],b[s+49]=250,36 end)
rejected(function(b,n,s,p) b[p[0x92]-1]=255 end)
rejected(function(b,n,s,p) put16(b,p[0x92]+16,257) end)
rejected(function(b,n,s,p) b[p[0xAD]+24]=1 end)
rejected(function(b,n,s,p) ffi.copy(b+p[0x92]+45,'other   texture ',16) end)
rejected(function(b,n,s,p) for i=0,3 do put16(b,p[0x92]+i*4,0) end end)
-- Confirm the parser against a real installed DAT without requiring Windows/D3D.
if arg[1] then
    local file=assert(io.open(arg[1],'rb')); local raw=file:read('*a'); file:close()
    local actual=assert(dat.Parse(raw,#raw))
    local stock=require('assets.player-icons')
    local total=0
    for byte in pairs(stock) do assert(actual.places[byte]); total=total+1 end
    assert(total==36 and actual.overlays[0xAC])
    print('Real menu DAT: 36 icons, mastery and composite overlay parsed\ttrue')
end
-- Load must use the resource-mapped menu path through the Pivot-aware reader,
-- then upload the parsed image and own/release the resulting texture.
ffi.cdef('typedef struct { int unused; } IDirect3DTexture8;')
local device,reads,uploads,releases = {},0,0,0
local mapped,expected = 'C:\\Game\\ROM2\\10\\20.DAT','ROM2\\10\\20.DAT'
AshitaCore={ GetResourceManager=function() return { GetFilePath=function(_,id) assert(id==39542);return mapped end } end }
package.loaded.d3d8={get_device=function() return device end,gc_safe_release=function(t) return t end}
package.loaded['gdi.atlas']={release=function(t) assert(tonumber(ffi.cast('uint32_t',t))==0x1234);releases=releases+1 end}
mapdat.Read=function(path) assert(path==expected);reads=reads+1;return bytes,length end
mapdat.Texture=function(d,image,n)
    assert(d==device and mapdat.Header(image,n).width==256)
    uploads=uploads+1
    return ffi.cast('IDirect3DTexture8*',0x1234)
end
local loaded=assert(dat.Load())
assert(loaded.address==0x1234 and loaded.places[0x92][1]==.5 and reads==1 and uploads==1)
dat.Release(loaded);dat.Release(loaded);assert(releases==1 and loaded.texture==nil)
mapped,expected=nil,'ROM/119/51.DAT'
assert(dat.Load() and reads==2)
mapdat.Read=function() return nil,'missing overlay' end
local absent,why=dat.Load();assert(not absent and why:find('missing overlay'))
mapdat.Read=function() return bytes,15 end
absent,why=dat.Load();assert(not absent and why:find('DAT parse'))
mapdat.Read=function() return bytes,length end
mapdat.Texture=function() return nil,'device lost' end
absent,why=dat.Load();assert(not absent and why:find('device lost'))
device=nil
absent,why=dat.Load();assert(not absent and why:find('device unavailable'))
print('Player DAT: bounded chunks/shapes, native/HD UVs, alpha, composites, mapped path, upload ownership and failures\ttrue')
