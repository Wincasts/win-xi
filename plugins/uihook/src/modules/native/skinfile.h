// A skin's picture read from its file as ARGB (BGRA in memory, as D3DFMT_A8R8G8B8 keeps it): a .bmp of 24 or 32
// bits by hand, its fourth byte kept as alpha (Windows' imaging component reads a 32-bit .bmp as opaque), anything
// else (.png) by Windows' imaging component.
#pragma once
#include <windows.h>
#include <wincodec.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <vector>

#define SKIN_LARGEST 8192

// A .bmp of 24 or 32 bits, uncompressed (or 32-bit bitfields), either way up; one whose alpha is all 0 made opaque
static bool SkinReadBmp(const char* path,uint32_t& width,uint32_t& height,std::vector<uint32_t>& argb) {
    FILE* f=fopen(path,"rb"); if (!f) return false;
    std::vector<uint8_t> file;
    uint8_t chunk[65536]; size_t n;
    while ((n=fread(chunk,1,sizeof(chunk),f))>0) file.insert(file.end(),chunk,chunk+n);
    fclose(f);
    auto u32=[&](size_t at) { uint32_t v=0; if (at+4<=file.size()) memcpy(&v,file.data()+at,4); return v; };
    auto u16=[&](size_t at) { uint16_t v=0; if (at+2<=file.size()) memcpy(&v,file.data()+at,2); return v; };
    if (file.size()<54 || file[0]!='B' || file[1]!='M' || u32(14)<40) return false;
    const uint32_t offset=u32(10),compression=u32(30),bits=u16(28);
    const int32_t w=int32_t(u32(18)),h=int32_t(u32(22));
    if (w<=0 || h==0 || w>SKIN_LARGEST || h>SKIN_LARGEST || h<-SKIN_LARGEST || (bits!=24 && bits!=32) || (compression!=0 && !(compression==3 && bits==32))) return false;
    width=uint32_t(w); height=uint32_t(h<0 ? -h : h);
    const size_t pitch=(size_t(width)*(bits/8)+3)&~size_t(3);
    if (offset+pitch*height>file.size()) return false;
    argb.assign(size_t(width)*height,0);
    bool alpha=false;
    for (uint32_t y=0;y<height;y++) {
        const uint8_t* row=file.data()+offset+pitch*(h<0 ? y : height-1-y);
        for (uint32_t x=0;x<width;x++) {
            const uint8_t* p=row+size_t(x)*(bits/8);
            const uint32_t a=bits==32 ? p[3] : 255;
            if (a) alpha=true;
            argb[size_t(y)*width+x]=a<<24 | uint32_t(p[2])<<16 | uint32_t(p[1])<<8 | p[0];
        }
    }
    if (!alpha) for (auto& c:argb) c|=0xff000000;
    return true;
}

static bool SkinReadPicture(const char* path,uint32_t& width,uint32_t& height,std::vector<uint32_t>& argb) {
    const size_t length=strlen(path);
    if (length>4 && !_stricmp(path+length-4,".bmp")) return SkinReadBmp(path,width,height,argb);
    wchar_t wide[MAX_PATH*2];
    if (!MultiByteToWideChar(CP_ACP,0,path,-1,wide,MAX_PATH*2)) return false;
    // the game's thread may have COM already, of another kind: then it is used as it is
    const HRESULT init=CoInitializeEx(nullptr,COINIT_MULTITHREADED);
    IWICImagingFactory* factory=nullptr; IWICBitmapDecoder* decoder=nullptr; IWICBitmapFrameDecode* frame=nullptr; IWICFormatConverter* converter=nullptr;
    bool ok=false;
    if (SUCCEEDED(CoCreateInstance(CLSID_WICImagingFactory1,nullptr,CLSCTX_INPROC_SERVER,IID_PPV_ARGS(&factory)))
        && SUCCEEDED(factory->CreateDecoderFromFilename(wide,nullptr,GENERIC_READ,WICDecodeMetadataCacheOnDemand,&decoder))
        && SUCCEEDED(decoder->GetFrame(0,&frame))
        && SUCCEEDED(factory->CreateFormatConverter(&converter))
        && SUCCEEDED(converter->Initialize(frame,GUID_WICPixelFormat32bppBGRA,WICBitmapDitherTypeNone,nullptr,0,WICBitmapPaletteTypeCustom))
        && SUCCEEDED(converter->GetSize(&width,&height)) && width && height && width<=SKIN_LARGEST && height<=SKIN_LARGEST) {
        argb.assign(size_t(width)*height,0);
        ok=SUCCEEDED(converter->CopyPixels(nullptr,width*4,UINT(argb.size()*4),reinterpret_cast<BYTE*>(argb.data())));
    }
    if (converter) converter->Release();
    if (frame) frame->Release();
    if (decoder) decoder->Release();
    if (factory) factory->Release();
    if (init==S_OK || init==S_FALSE) CoUninitialize();
    return ok;
}
