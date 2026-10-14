-- Run: luajit tests/harness.lua menurect addons/menurect/menurect.lua tests/menurect_check.lua
local ffi=require('ffi')
local probe=require('probe')
local blocks, reads={},0
local function block(address)
    local b=ffi.new('uint8_t[256]'); blocks[address]=b; return b
end
local function put(b,offset,kind,values)
    local types={ i16='int16_t*', i32='int32_t*', f32='float*' }
    local ptr=ffi.cast(types[kind],b+offset)
    for i,v in ipairs(values) do ptr[i-1]=v end
end
local slot,holder,node,header,child=0x10000,0x20000,0x30000,0x40000,0x50000
put(block(slot),0,'i32',{holder}); put(block(holder),0,'i32',{node})
local n=block(node); put(n,4,'i32',{header}); put(n,8,'i32',{child})
local h=block(header); ffi.copy(h+0x46,'menu    item    \0',16)
local c=block(child); put(c,0x60,'i16',{10,20,210,120})
local memory={ read=function(address,length)
    reads=reads+1
    for base,b in pairs(blocks) do
        if address>=base and address+length<=base+256 then
            return ffi.string(b+address-base,length)
        end
    end
    return nil,'unreadable'
end }
assert(not probe.resolve(memory,0))
local menu=assert(probe.resolve(memory,slot)); assert(menu.node==node and menu.header==header)
local candidates,sources=probe.scan(memory,menu,1920,1080)
assert(#sources==3 and reads<60, 'bounded one-hop reads')
local chosen
for _,v in ipairs(candidates) do
    if v.source.root=='node' and v.source.via==8 and v.offset==0x60
        and v.kind=='i16' and v.layout=='ltrb' then chosen=v end
end
assert(chosen and chosen.rect[3]==210)
assert(probe.live(memory,menu,chosen,1920,1080)[2]==20)
put(c,0x60,'i16',{30,40,230,140})
assert(probe.live(memory,menu,chosen,1920,1080)[1]==30, 'live motion')
put(n,8,'i32',{0x60000})
assert(not probe.live(memory,menu,chosen,1920,1080), 'reject stale child')
put(n,8,'i32',{child})
local rects=block(0x70000)
put(rects,0,'i32',{10,20,200,100})
local bytes=ffi.string(rects,256)
assert(probe.rectangle(bytes,0,'i32','xywh',1920,1080)[3]==210)
assert(not probe.rectangle(bytes,250,'i32','ltrb',1920,1080))
put(rects,0,'f32',{10,20,210,120})
assert(probe.rectangle(ffi.string(rects,256),0,'f32','ltrb',1920,1080)[4]==120)
put(rects,0,'f32',{0/0,20,210,120})
assert(not probe.rectangle(ffi.string(rects,256),0,'f32','ltrb',1920,1080))
put(rects,0,'i16',{10,20,5,5})
assert(not probe.rectangle(ffi.string(rects,256),0,'i16','ltrb',1920,1080))
H.print('menu chain, bounded scan, integer/float layouts, live motion, stale child and invalid rectangles: passed')
-- The addon must do no reads unless explicitly enabled. Simulate guarded memory on Linux.
package.loaded['winxi.safe_memory']=memory
AshitaCore.GetPointerManager=function() return {Get=function() return slot end} end
local before=reads; H.frames(2); assert(reads==before)
assert(H.command('/menurect')); H.frames(4); assert(reads>before and H.calls.Begin>0)
local after=reads; assert(H.command('/menurect off')); H.frames(4); assert(reads==after)
assert(not H.command('/menurectx'))
H.print('opt-in reads, probe UI and off switch: passed')
