// /uihook mirror labels: every element the mirror published in the last frame (the labels of the menus whose
// words are pictures, their buttons and icons) cut from its texture as the game drew it and written out as a
// .bmp, with a line naming its window, its texture's size and format, its place in it and a hash of its
// pixels, so the words of those menus can be read once and kept in a table keyed by what is lasting of them.
#pragma once
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <string>
#include <vector>

struct LabelPixels { uint32_t width=0,height=0; std::vector<uint32_t> argb; };

static uint32_t LabelArgb(uint32_t a,uint32_t r,uint32_t g,uint32_t b) { return a<<24 | r<<16 | g<<8 | b; }
static uint32_t Label565(uint16_t c) { return LabelArgb(255,((c>>11)&31)*255/31,((c>>5)&63)*255/63,(c&31)*255/31); }

// One 4x4 block of DXT1 (alpha from its colours), DXT2/3 (explicit alpha) or DXT4/5 (interpolated alpha)
static void LabelBlock(const uint8_t* block,uint32_t format,uint32_t out[16]) {
    uint32_t alpha[16]; for (auto& a:alpha) a=255;
    const bool dxt1=format==MAKEFOURCC('D','X','T','1');
    if (format==MAKEFOURCC('D','X','T','2') || format==MAKEFOURCC('D','X','T','3')) {
        for (int i=0;i<16;i++) alpha[i]=((block[i/2]>>((i&1)*4))&15)*17;
        block+=8;
    } else if (format==MAKEFOURCC('D','X','T','4') || format==MAKEFOURCC('D','X','T','5')) {
        uint32_t a[8]={block[0],block[1]};
        if (a[0]>a[1]) for (int i=2;i<8;i++) a[i]=((8-i)*a[0]+(i-1)*a[1])/7;
        else { for (int i=2;i<6;i++) a[i]=((6-i)*a[0]+(i-1)*a[1])/5; a[6]=0; a[7]=255; }
        uint64_t bits=0; for (int i=0;i<6;i++) bits|=uint64_t(block[2+i])<<(8*i);
        for (int i=0;i<16;i++) alpha[i]=a[(bits>>(3*i))&7];
        block+=8;
    }
    const uint16_t c0=uint16_t(block[0] | block[1]<<8),c1=uint16_t(block[2] | block[3]<<8);
    const uint32_t e0=Label565(c0),e1=Label565(c1);
    auto mix=[](uint32_t x,uint32_t y,uint32_t wx,uint32_t wy,uint32_t d) {
        uint32_t c=0xff000000;
        for (int s=0;s<24;s+=8) c|=((((x>>s)&255)*wx+((y>>s)&255)*wy)/d)<<s;
        return c;
    };
    uint32_t colour[4]={e0,e1};
    if (c0>c1 || !dxt1) { colour[2]=mix(e0,e1,2,1,3); colour[3]=mix(e0,e1,1,2,3); }
    else { colour[2]=mix(e0,e1,1,1,2); colour[3]=0; }
    const uint32_t bits=uint32_t(block[4] | block[5]<<8 | block[6]<<16 | uint32_t(block[7])<<24);
    for (int i=0;i<16;i++) {
        const uint32_t c=colour[(bits>>(2*i))&3];
        out[i]=dxt1 ? c : (c&0xffffff) | alpha[i]<<24;
    }
}

// The texels x0..x1, y0..y1 of a locked level in its format, as ARGB. False for a format not read here.
static bool LabelDecode(const uint8_t* bits,int pitch,uint32_t format,uint32_t x0,uint32_t y0,uint32_t x1,uint32_t y1,LabelPixels& out) {
    out.width=x1-x0; out.height=y1-y0; out.argb.assign(size_t(out.width)*out.height,0);
    const bool dxt=format==MAKEFOURCC('D','X','T','1') || format==MAKEFOURCC('D','X','T','2') || format==MAKEFOURCC('D','X','T','3')
        || format==MAKEFOURCC('D','X','T','4') || format==MAKEFOURCC('D','X','T','5');
    if (dxt) {
        const uint32_t size=format==MAKEFOURCC('D','X','T','1') ? 8 : 16;
        for (uint32_t by=y0/4;by*4<y1;by++) for (uint32_t bx=x0/4;bx*4<x1;bx++) {
            uint32_t block[16]; LabelBlock(bits+size_t(by)*pitch+size_t(bx)*size,format,block);
            for (uint32_t i=0;i<16;i++) {
                const uint32_t x=bx*4+i%4,y=by*4+i/4;
                if (x>=x0 && x<x1 && y>=y0 && y<y1) out.argb[size_t(y-y0)*out.width+(x-x0)]=block[i];
            }
        }
        return true;
    }
    for (uint32_t y=y0;y<y1;y++) for (uint32_t x=x0;x<x1;x++) {
        const uint8_t* row=bits+size_t(y)*pitch; uint32_t c;
        switch (format) {
        case D3DFMT_A8R8G8B8: memcpy(&c,row+x*4,4); break;
        case D3DFMT_X8R8G8B8: memcpy(&c,row+x*4,4); c|=0xff000000; break;
        case D3DFMT_R5G6B5: { uint16_t v; memcpy(&v,row+x*2,2); c=Label565(v); break; }
        case D3DFMT_X1R5G5B5: case D3DFMT_A1R5G5B5: {
            uint16_t v; memcpy(&v,row+x*2,2);
            c=LabelArgb(format==D3DFMT_X1R5G5B5 || (v>>15) ? 255 : 0,((v>>10)&31)*255/31,((v>>5)&31)*255/31,(v&31)*255/31); break;
        }
        case D3DFMT_A4R4G4B4: { uint16_t v; memcpy(&v,row+x*2,2); c=LabelArgb((v>>12)*17,((v>>8)&15)*17,((v>>4)&15)*17,(v&15)*17); break; }
        case D3DFMT_A8: c=LabelArgb(row[x],255,255,255); break;
        default: return false;
        }
        out.argb[size_t(y-y0)*out.width+(x-x0)]=c;
    }
    return true;
}

static uint32_t LabelHash(const LabelPixels& p) {
    uint32_t h=2166136261u;
    for (uint32_t c:p.argb) for (int s=0;s<32;s+=8) { h^=(c>>s)&255; h*=16777619u; }
    return h;
}

// A texture's level 0, the part uv names of it (left, top, right, bottom, either way round), cut out
static bool LabelCut(IDirect3DBaseTexture8* base,const float uv[4],LabelPixels& out,D3DSURFACE_DESC& desc,uint32_t texels[4],const char*& why) {
    if (!base || base->GetType()!=D3DRTYPE_TEXTURE) { why="not a 2D texture"; return false; }
    auto* texture=static_cast<IDirect3DTexture8*>(base);
    if (FAILED(texture->GetLevelDesc(0,&desc))) { why="no level 0"; return false; }
    auto texel=[](float t,uint32_t size) { const float v=t*float(size)+0.5f; return v<=0 ? 0u : v>=float(size) ? size : uint32_t(v); };
    uint32_t x0=texel(uv[0],desc.Width),x1=texel(uv[2],desc.Width),y0=texel(uv[1],desc.Height),y1=texel(uv[3],desc.Height);
    if (x0>x1) std::swap(x0,x1);
    if (y0>y1) std::swap(y0,y1);
    texels[0]=x0; texels[1]=y0; texels[2]=x1; texels[3]=y1;
    if (x0==x1 || y0==y1) { why="empty"; return false; }
    D3DLOCKED_RECT locked;
    if (FAILED(texture->LockRect(0,&locked,nullptr,D3DLOCK_READONLY))) { why="not lockable"; return false; }
    const bool read=LabelDecode(static_cast<const uint8_t*>(locked.pBits),locked.Pitch,desc.Format,x0,y0,x1,y1,out);
    texture->UnlockRect(0);
    if (!read) why="a format not read";
    return read;
}

// A 32-bit top-down .bmp, alpha kept
static bool LabelWrite(const char* path,const LabelPixels& p) {
    FILE* f=fopen(path,"wb"); if (!f) return false;
    const uint32_t bytes=p.width*p.height*4;
    uint8_t header[54]={'B','M'};
    auto put=[&](int at,uint32_t v) { memcpy(header+at,&v,4); };
    put(2,54+bytes); put(10,54); put(14,40); put(18,p.width); put(22,uint32_t(-int32_t(p.height)));
    header[26]=1; header[28]=32; put(34,bytes);
    const bool ok=fwrite(header,1,54,f)==54 && fwrite(p.argb.data(),1,bytes,f)==bytes;
    fclose(f); return ok;
}
