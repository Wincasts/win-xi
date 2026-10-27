#include <stdio.h>
#include <d3d8.h>
#include "../src/modules/native/skin.h"
#include "../src/modules/native/skinfile.h"
static int failures=0;
static void Check(bool ok,const char* text) { printf("%s %s\n",ok?"ok":"FAIL",text); if(!ok) ++failures; }
int main() {
    uint32_t hash=0;
    Check(SkinLook::FileHash("tex-72D3D795.png",hash) && hash==0x72D3D795u,"a picture named for its texture");
    Check(SkinLook::FileHash("TEX-c4ddaeb2.BMP",hash) && hash==0xC4DDAEB2u,"either case");
    Check(!SkinLook::FileHash("tex-72D3D795.jpg",hash) && !SkinLook::FileHash("tex-72D3.png",hash) && !SkinLook::FileHash("frame.png",hash),"anything else left");

    SkinLook skin; int ours=1;
    Check(!skin.On() && skin.Lookup(0x1000,1,[](uint32_t&) { return true; })==-1,"no skin: nothing swapped");
    SkinTexture a; a.hash=0xAAAA; a.texture=&ours; skin.textures.push_back(a);
    SkinTexture b; b.hash=0xBBBB; b.texture=&ours+1; skin.textures.push_back(b);
    unsigned reads=0;
    auto as=[&](uint32_t h) { return [&reads,h](uint32_t& out) { reads++; out=h; return true; }; };
    Check(skin.Lookup(0x1000,1,as(0xBBBB))==1 && reads==1,"a game texture known by its pixels");
    Check(skin.Lookup(0x1000,2,as(0xAAAA))==1 && reads==1,"seen again: not read again");
    Check(skin.Lookup(0x2000,2,as(0x1234))==-1 && reads==2,"one the skin has no picture for");
    Check(skin.Lookup(0x2000,3,as(0x1234))==-1 && reads==2,"and it not read again either");
    Check(skin.Lookup(0x1000,3+TEXTURE_STALE+1,as(0xAAAA))==0 && reads==3,"unseen a while: read again, as the game may have made another there");
    Check(skin.Lookup(reinterpret_cast<uintptr_t>(&ours),4,as(0xAAAA))==-1 && reads==3,"the skin's own pictures never swapped");
    Check(skin.Lookup(0,4,as(0xAAAA))==-1,"no texture: nothing");
    Check(skin.textures[0].matched==1 && skin.textures[1].matched==1,"game textures found counted");
    auto failing=[](uint32_t&) { return false; };
    Check(skin.Lookup(0x3000,5,failing)==-1,"one that cannot be read: left");
    Check(skin.Clear().size()==2 && !skin.On() && skin.pointers.empty(),"cleared, its textures handed back");
    Check(SkinLeftOutside(true,0,true),"a font drawn in no window (the names over heads): left as the game's");
    Check(!SkinLeftOutside(true,1,true) && !SkinLeftOutside(true,2,true),"a font in a window, or one within another: skinned");
    Check(!SkinLeftOutside(true,0,false),"another texture drawn in no window: skinned");
    Check(!SkinLeftOutside(false,0,true),"the windows not heard: every font skinned, as before");

    SkinLook full; full.textures.push_back(a);
    for (uint32_t i=0;i<SKIN_POINTERS;i++) full.Lookup(0x10000+i*16,i,as(0x1));
    full.Lookup(0x9999990,SKIN_POINTERS,as(0xAAAA));
    Check(full.pointers.size()==SKIN_POINTERS && full.pointers.back().index==0 && full.pointers.front().texture==0x10010,"full: the one longest unseen made room");

    // skin.txt: a game colour (or any) drawn in another, alpha kept
    std::vector<SkinTexture> pictures(2); pictures[0].hash=0x9E2854A3; pictures[1].hash=0x11111111;
    Check(SkinColours(pictures,"# buttons\r\n9E2854A3 616180 363650\r\n9e2854a3 * 4566D0  # the rest\nFFFFFFFF * 000000\nnonsense\n")==2
        && pictures[0].colours.size()==2 && pictures[0].colours[0].from==0x616180 && pictures[0].colours[1].from==SKIN_ANY && pictures[0].colours[1].to==0x4566D0,
        "skin.txt read, a line of no picture and one not understood counted");
    struct C { float x,y,z,w; uint32_t colour; float u,v; } cv[3]={{0,0,0,1,0xA9616180,0,0},{0,0,0,1,0x61613C20,0,0},{0,0,0,1,0x06616180,0,0}};
    std::vector<uint8_t> out;
    Check(SkinRecolour(pictures[0],cv,3,sizeof(C),D3DFVF_XYZRHW|D3DFVF_DIFFUSE|D3DFVF_TEX1,out),"recoloured");
    const C* rc=reinterpret_cast<const C*>(out.data());
    Check(rc[0].colour==0xA9363650 && rc[1].colour==0x614566D0 && rc[2].colour==0x06363650 && cv[0].colour==0xA9616180,"the first line that fits, alpha the game's, the game's own left");
    Check(SkinColours(pictures,"11111111 * 66808080\n")==0 && pictures[1].colours[0].alpha,"a colour of eight digits sets the alpha too");
    Check(SkinRecolour(pictures[1],cv,3,sizeof(C),D3DFVF_XYZRHW|D3DFVF_DIFFUSE|D3DFVF_TEX1,out)
        && reinterpret_cast<const C*>(out.data())[0].colour==0x66808080 && reinterpret_cast<const C*>(out.data())[2].colour==0x66808080,"its alpha, not the game's");
    pictures[1].colours.clear();
    Check(!SkinRecolour(pictures[1],cv,3,sizeof(C),D3DFVF_XYZRHW|D3DFVF_DIFFUSE|D3DFVF_TEX1,out),"a picture with no colours: as they are");
    Check(!SkinRecolour(pictures[0],cv,3,sizeof(C),D3DFVF_XYZRHW|D3DFVF_TEX1,out),"vertices without colour: as they are");

    // a 2x2 32-bit bmp, bottom-up, written and read back
    const char* path="skin-test.bmp";
    FILE* f=fopen(path,"wb");
    uint8_t header[54]={'B','M'}; auto put=[&](int at,uint32_t v) { memcpy(header+at,&v,4); };
    put(2,54+16); put(10,54); put(14,40); put(18,2); put(22,2); header[26]=1; header[28]=32; put(34,16);
    const uint32_t pixels[4]={0x80FF0000,0x8000FF00,0x800000FF,0x80FFFFFF}; // bottom row first
    fwrite(header,1,54,f); fwrite(pixels,4,4,f); fclose(f);
    uint32_t w=0,h=0; std::vector<uint32_t> argb;
    Check(SkinReadPicture(path,w,h,argb) && w==2 && h==2 && argb[0]==0x800000FF && argb[3]==0x8000FF00 && argb[2]==0x80FF0000,"a bmp read the right way up, its alpha kept");
    put(22,uint32_t(-2)); const uint32_t opaque[4]={0x00102030,0,0,0};
    f=fopen(path,"wb"); fwrite(header,1,54,f); fwrite(opaque,4,4,f); fclose(f);
    Check(SkinReadPicture(path,w,h,argb) && argb[0]==0xFF102030,"top-down, and no alpha made opaque");
    remove(path);
    // a 2x1 png (half-clear red, blue), by Windows' imaging component
    static const uint8_t png[]={0x89,0x50,0x4e,0x47,0x0d,0x0a,0x1a,0x0a,0x00,0x00,0x00,0x0d,0x49,0x48,0x44,0x52,0x00,0x00,0x00,0x02,0x00,0x00,0x00,0x01,0x08,0x06,0x00,0x00,0x00,0xf4,0x22,0x7f,0x8a,0x00,0x00,0x00,0x11,0x49,0x44,0x41,0x54,0x78,0x9c,0x63,0xf8,0xcf,0xc0,0xd0,0xc0,0xc0,0xf0,0xff,0x3f,0x00,0x0d,0x7e,0x03,0x7e,0xea,0x1e,0x17,0x21,0x00,0x00,0x00,0x00,0x49,0x45,0x4e,0x44,0xae,0x42,0x60,0x82};
    f=fopen("skin-test.png","wb"); fwrite(png,1,sizeof(png),f); fclose(f);
    Check(SkinReadPicture("skin-test.png",w,h,argb) && w==2 && h==1 && argb[0]==0x80FF0000 && argb[1]==0xFF0000FF,"a png read, its alpha kept");
    remove("skin-test.png");
    // a picture halved: alpha averaged, colours weighted by it
    std::vector<uint32_t> four={0xFFFF0000,0x00000000,0xFFFF0000,0x00000000};
    uint32_t hw=2,hh=2; SkinHalve(four,hw,hh);
    Check(hw==1 && hh==1 && four.size()==1 && four[0]==0x7FFF0000,"halved: half as solid, its colour not darkened by the clear");
    std::vector<uint32_t> odd(3*1,0xFF00FF00); uint32_t ow=3,oh=1; SkinHalve(odd,ow,oh);
    Check(ow==1 && oh==1 && odd[0]==0xFF00FF00,"an odd size halved down to a texel");
    // sizes of a picture: named, kept smallest first, chosen by how large a texel is drawn
    float factor=0;
    Check(SkinLook::FileHash("tex-30CDD9D4@0.5.png",hash,&factor) && hash==0x30CDD9D4u && factor==0.5f,"a size named by its factor");
    Check(SkinLook::FileHash("tex-30CDD9D4.png",hash,&factor) && factor==1,"no factor: the game's size");
    Check(!SkinLook::FileHash("tex-30CDD9D4@.png",hash,&factor) && !SkinLook::FileHash("tex-30CDD9D4@99.png",hash,&factor),"a factor that is none, or too large");
    SkinTexture font; int t1=0,t2=0,t05=0;
    SkinSize z; z.factor=1; z.width=256; z.height=256; z.texture=&t1; SkinLook::AddSize(font,z);
    z.factor=2; z.width=512; z.height=512; z.texture=&t2; SkinLook::AddSize(font,z);
    z.factor=0.5f; z.width=128; z.height=128; z.texture=&t05; SkinLook::AddSize(font,z);
    Check(font.sizes.size()==3 && font.sizes[0].factor==0.5f && font.texture==&t05,"smallest first, the first its texture");
    bool exact=false;
    bool levels=false;
    const SkinSize* chosen=SkinLook::Choose(font,1.0f,exact,&levels);
    Check(chosen && chosen->factor==0.5f && exact && !levels,"a texel of the first a pixel: the first, unfiltered");
    chosen=SkinLook::Choose(font,2.0f,exact,&levels);
    Check(chosen && chosen->factor==1 && exact,"drawn twice as large: the size twice as fine, unfiltered");
    // the menu font: a texel of its first (0.5) about 0.95 pixels, none a pixel: the smallest twice as fine, no levels
    chosen=SkinLook::Choose(font,0.95f,exact,&levels);
    Check(chosen && chosen->factor==1 && !exact && !levels,"none a pixel: the one about twice as fine, filtered, no levels");
    chosen=SkinLook::Choose(font,0.2f,exact,&levels);
    Check(chosen && chosen->factor==0.5f && !exact && levels,"shrunk far: filtered with its levels");
    chosen=SkinLook::Choose(font,8.0f,exact,&levels);
    Check(chosen && chosen->factor==2 && !exact && !levels,"larger than any: the largest");
    printf("skin: %d failures\n",failures);
    return failures ? 1 : 0;
}
