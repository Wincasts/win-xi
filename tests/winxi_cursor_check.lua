-- Run: luajit tests/winxi_cursor_check.lua
-- winxi.cursor's sprite groups, their corners and the grey copy, against a made-up menu DAT and, where
-- the game is installed here, its own 51.DAT.
package.path = 'addons/libs/?.lua;' .. package.path
local ffi = require('ffi')
package.preload['d3d8'] = function() return { get_device = function() return nil end } end
local cursor, mapdat = require('winxi.cursor'), require('winxi.mapdat')

local function check(label, ...)
    print(label, ...)
    for i = 1, select('#', ...) do assert(select(i, ...), label) end
end

-- One texture and two groups over the same cells: anc_s drawn as it is, anc_l turned to point down.
local length = 4192+432*2
local source = ffi.new('uint8_t[?]',length)
local function u16(at,v) v=v%65536 source[at],source[at+1]=v%256,math.floor(v/256) end
local function u32(at,v) u16(at,v%65536);u16(at+2,math.floor(v/65536)) end
u32(4,4192/16*128+0x20)
ffi.copy(source+17,'anc     anc     ',16)
u32(33,40);u32(37,64);u32(41,64);u16(47,8);u32(73,0x44585433)
for at=85,85+4096-1,16 do
    source[at]=0x48
    u16(at+8,0xF800)  -- pure red end
    u16(at+10,0x0400) -- dim green end
end
local function Group(at, name, corners)
    u32(at+4,432/16*128+0x31)
    ffi.copy(source+at+16,('anc     %-8s'):format(name),16)
    source[at+32]=1
    ffi.copy(source+at+33,'anc     anc     ',16)
    source[at+49]=6
    local pos=at+51
    for i=0,5 do
        source[pos]=1
        local piece=pos+1
        for c=1,8 do u16(piece+(c-1)*2,corners[c]) end
        u16(piece+16,32);u16(piece+18,20)
        u16(piece+20,math.floor(i/3)*32);u16(piece+22,1+i%3*21)
        ffi.copy(source+piece+45,'anc     anc     ',16)
        pos=piece+61
    end
end
Group(4192,'anc_s',{-32,-2,0,-2,-32,18,0,18})
Group(4192+432,'anc_l',{10,-32,10,0,-10,-32,-10,0})

local image,imageLength,frames=cursor.Parse(source,length)
check('anc_s by default, corners as stored', image ~= nil, frames[1].corners[1]==-32 and frames[1].corners[8]==18)
local _,_,down=cursor.Parse(source,length,'anc_l')
local c=down[4].corners
check('anc_l: negative corners read signed', c[1]==10 and c[2]==-32 and c[5]==-10 and c[8]==0)
check('anc_l: same cells as anc_s', down[4][1]==frames[4][1] and down[4][2]==frames[4][2] and down[4][5]==32 and down[4][6]==20)
check('pixel rect of a cell', down[2].rect[1]==0 and down[2].rect[2]==22 and down[2].rect[3]==32 and down[2].rect[4]==42)
local missing,why=cursor.Parse(source,length,'anc2s')
check('a group not in the file says which', missing==nil and why:find('anc2s',1,true)~=nil)

local grey=assert(cursor.Neutral(image,imageLength))
local header=mapdat.Header(grey,imageLength)
local function ends(b,at) return b[at+8]+b[at+9]*256, b[at+10]+b[at+11]*256 end
local function isGrey(v) local r,g,b=math.floor(v/2048),math.floor(v/32)%64,v%32 return r==b and math.abs(g-2*r)<=1 end
local a,b=ends(grey,header.at)
check('grey copy: both ends grey, brightest white', isGrey(a) and isGrey(b) and math.max(a,b)==0xFFFF)
check('grey copy: alpha and the original untouched', grey[header.at]==image[header.at] and ends(image,header.at)==0xF800)

-- The game's own, where it is installed here.
local GAME = os.getenv('FFXI_DIR') or (os.getenv('HOME') .. '/Games/PhoenixXI/SquareEnix/FINAL FANTASY XI')
local file = io.open(GAME .. '/ROM/119/51.DAT','rb')
if file then
    local bytes = file:read('*a'); file:close()
    local buffer = ffi.new('uint8_t[?]',#bytes); ffi.copy(buffer,bytes,#bytes)
    local _,_,l=cursor.Parse(buffer,#bytes,'anc_l')
    local _,_,s=cursor.Parse(buffer,#bytes,'anc_s')
    check('51.DAT: six frames each', l and #l==6 and s and #s==6)
    local lc=l[1].corners
    check('51.DAT: anc_l is 20 wide, 32 tall, tip at the pivot', math.abs(lc[1]-lc[5])==20 and math.abs(lc[2]-lc[4])==32 and math.max(lc[2],lc[4])==0)
    local img,len=cursor.Parse(buffer,#bytes,'anc_l')
    check('51.DAT: grey copy made', cursor.Neutral(img,len)~=nil)
else
    print('51.DAT not installed here: skipped')
end
print('winxi.cursor: groups, signed corners, pixel rects and grey copy passed')
