#include <stdio.h>
#include <d3d8.h>
#include "../src/modules/mirror/textures.h"
static int failures=0;
static void Check(bool ok,const char* text) { printf("%s %s\n",ok?"ok":"FAIL",text); if(!ok) ++failures; }
static LabelPixels Pixels(uint32_t fill) { LabelPixels p; p.width=2; p.height=2; p.argb.assign(4,fill); return p; }
int main() {
    TextureCensus census;
    Check(census.Known(0x1000,1)==SIZE_MAX,"a texture not seen is to be read");
    LabelPixels a=Pixels(0xff102030);
    const size_t first=census.Add(0x1000,1,2,2,D3DFMT_A8R8G8B8,1,&a,"");
    Check(census.Known(0x1000,2)==first,"seen again: its entry");
    LabelPixels b=Pixels(0xff102030);
    Check(census.Add(0x2000,2,2,2,D3DFMT_A8R8G8B8,1,&b,"")==first && census.entries.size()==1,"the same pixels elsewhere: the same entry");
    LabelPixels c=Pixels(0xff405060);
    const size_t second=census.Add(0x3000,2,2,2,D3DFMT_A8R8G8B8,1,&c,"");
    Check(second!=first && census.entries.size()==2,"other pixels: an entry of their own");
    Check(census.Known(0x1000,2+TEXTURE_STALE+1)==SIZE_MAX,"a pointer unseen a while is read again");
    const size_t none=census.Add(0,3,0,0,0,0,nullptr,"");
    Check(census.Add(0,4,0,0,0,0,nullptr,"")==none && !census.entries[none].width,"no texture: one entry");
    const size_t locked=census.Add(0x4000,3,256,256,D3DFMT_A8R8G8B8,0,nullptr,"not lockable");
    Check(census.Add(0x5000,3,256,256,D3DFMT_A8R8G8B8,0,nullptr,"not lockable")==locked,"unread textures of one kind: one entry");
    Check(census.memory==2*16,"only pixels kept counted");

    census.Window("menu    inventor");
    Check(!strcmp(census.window,"inventor"),"a window named by its own part");
    census.Window("menu    iuse    ");
    Check(!strcmp(census.window,"iuse"),"its trailing spaces dropped");
    const float uv1[4]={0.1f,0.2f,0.3f,0.4f},uv2[4]={0.0f,0.3f,0.5f,0.35f}; const uint32_t white=0xffffffff;
    census.Count(first,TEXTURE_FRAME,uv1,&white,false);
    census.Window("menu    equip   ");
    census.Count(first,TEXTURE_TEXT,uv2,&white,false);
    census.Window(nullptr);
    census.Count(first,TEXTURE_OUTSIDE,nullptr,nullptr,true);
    const TextureEntry& e=census.entries[first];
    Check(e.draws[TEXTURE_FRAME]==1 && e.draws[TEXTURE_TEXT]==1 && e.draws[TEXTURE_OUTSIDE]==1 && e.buffered==1 && e.Total()==3,"draws counted by part");
    Check(e.windows.size()==3 && e.windows[0]=="iuse" && e.windows[1]=="equip" && e.windows[2]=="(no window)","the windows drawing it, once each");
    Check(e.uvKnown && e.uv[0]==0.0f && e.uv[1]==0.2f && e.uv[2]==0.5f && e.uv[3]==0.4f,"the texture places used, together");
    Check(e.colourCount==1,"a colour once");

    struct V { float x,y,z,w; uint32_t colour; float u,v; } v[2]={{0,0,0,1,0xff808080,0.25f,0.5f},{10,10,0,1,0,0.75f,0.125f}};
    float uv[4]; uint32_t colour=0; bool hasColour=false;
    Check(TextureVertices(v,2,sizeof(V),D3DFVF_XYZRHW|D3DFVF_DIFFUSE|D3DFVF_TEX1,uv,&colour,hasColour)
        && hasColour && colour==0xff808080 && uv[0]==0.25f && uv[1]==0.125f && uv[2]==0.75f && uv[3]==0.5f,"texture places and colour by the FVF");
    Check(!TextureVertices(v,2,sizeof(V),D3DFVF_XYZRHW|D3DFVF_DIFFUSE,uv,&colour,hasColour) && hasColour,"no texture places, the colour still");
    Check(!TextureVertices(v,2,sizeof(V),D3DFVF_XYZ|D3DFVF_TEX1,uv,&colour,hasColour),"not screen space");
    printf("textures: %d failures\n",failures);
    return failures ? 1 : 0;
}
