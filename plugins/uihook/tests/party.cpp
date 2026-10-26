#include <stdio.h>
#include <cmath>
#include "../src/modules/party/detour.h"
#include "../src/modules/party/game.h"
#include "../src/modules/party/target.h"
#include "../src/modules/party/clip.h"
#include "../src/modules/party/partyhook.h"
#include "../src/modules/party/hold.h"
#include "../src/modules/party/runs.h"
static int failures=0;
static void Check(bool ok,const char* text) { printf("%s %s\n",ok?"ok":"FAIL",text); if(!ok) failures++; }
static int __fastcall Replacement(void*,void*) { return 99; }
static uint32_t seenWords[8];
static void* seenThis=nullptr;
static bool spriteBlocked=true, seenBlocking=true;
static void __fastcall OriginalSprite(void* self,void*,uint32_t x,uint32_t y,uint32_t sx,uint32_t sy,uint32_t color,uint32_t a,uint32_t b,uint32_t c) {
    seenThis=self; seenBlocking=spriteBlocked;
    uint32_t args[8]={x,y,sx,sy,color,a,b,c}; memcpy(seenWords,args,sizeof(args));
}
static void __fastcall ForwardSprite(void* self,void*,uint32_t x,uint32_t y,uint32_t sx,uint32_t sy,uint32_t color,uint32_t a,uint32_t b,uint32_t c) {
    ArrowScope scope(spriteBlocked,true);
    SpriteDraw original=&OriginalSprite;
    original(self,nullptr,x,y,sx,sy,color,a,b,c);
}
int main() {
    // Real Window::Render bytes from the unpacked client; six stolen bytes are complete instructions.
    uint8_t bytes[]={0x83,0xec,0x24,0x53,0x55,0x56,0x57,0x8b,0xe9,0xe8,0xf0,0xff,0xff,0xff,
        0x66,0x8b,0x45,0x56,0x33,0xff,0x66,0x3b,0xc7,0x7e,0x05,0x48,0x66,0x89,0x45,0x56};
    uint8_t* image=static_cast<uint8_t*>(VirtualAlloc(nullptr,4096,MEM_COMMIT|MEM_RESERVE,PAGE_EXECUTE_READWRITE));
    memset(image,0xcc,4096); memcpy(image+100,bytes,sizeof(bytes));
    Check(FindPattern(image,4096,WINDOW_PATTERN)==image+100,"native window renderer signature matches captured bytes");
    Detour detour={WINDOW_PATTERN,WINDOW_STOLEN,-1,reinterpret_cast<void*>(&Replacement),nullptr,nullptr,{},{}};
    memcpy(image+200,bytes,sizeof(bytes));
    Check(!Take(detour,image,4096),"duplicate renderer matches are rejected without patching");
    memset(image+200,0xcc,sizeof(bytes));
    Check(Take(detour,image,4096),"unique renderer can be detoured");
    Check(reinterpret_cast<int(__fastcall*)(void*,void*)>(image+100)(nullptr,nullptr)==99,"detoured renderer calls replacement with matching ABI");
    Check(memcmp(detour.trampoline,bytes,6)==0,"trampoline preserves all stolen instructions");
    Give(detour); Check(memcmp(image+100,bytes,sizeof(bytes))==0,"unload restores renderer bytes");
    // Executable trampoline exercises stack preservation and calling convention with a safe body.
    uint8_t safe[]={0x83,0xec,0x24,0x53,0x55,0x56,0xb8,42,0,0,0,0x5e,0x5d,0x5b,0x83,0xc4,0x24,0xc3};
    memcpy(image+100,safe,sizeof(safe));
    Detour roundtrip={"83 EC 24 53 55 56 B8 2A",6,-1,reinterpret_cast<void*>(&Replacement),nullptr,nullptr,{},{}};
    Check(Take(roundtrip,image,4096),"safe renderer-shaped fixture taken");
    Check(reinterpret_cast<int(__fastcall*)(void*,void*)>(roundtrip.trampoline)(nullptr,nullptr)==42,"trampoline runs original with stack intact");
    Give(roundtrip);
    // Something else writes over the jump after it is taken: given back only while ours, so left as the other
    // left it, the trampoline kept, and uihook kept loaded (stranded) as the client may go through it into this DLL
    memcpy(image+100,safe,sizeof(safe));
    Detour overwritten={"83 EC 24 53 55 56 B8 2A",6,-1,reinterpret_cast<void*>(&Replacement),nullptr,nullptr,{},{}};
    Check(Take(overwritten,image,4096) && image[100]==0xE9,"taken: the jump in");
    uint8_t* const kept=overwritten.trampoline;
    image[100]=0xE9; image[101]^=0x55; // another's jump in its place
    const uint8_t foreign[2]={image[100],image[101]};
    Check(!CodeStranded(),"not stranded before");
    Give(overwritten);
    Check(image[100]==foreign[0] && image[101]==foreign[1],"another's jump left as it is, not our original put over it");
    Check(CodeStranded() && overwritten.trampoline==nullptr && kept[0]==safe[0],"stranded, the trampoline kept for whatever goes through it");
    CodeStranded()=false;
    // put back as it was found by something else: nothing lost, nothing stranded
    memcpy(image+100,safe,sizeof(safe));
    Check(Take(overwritten,image,4096),"taken again");
    memcpy(image+100,safe,6);
    Give(overwritten);
    Check(!CodeStranded() && memcmp(image+100,safe,sizeof(safe))==0,"put back by another as found: given back, not stranded");

    const char* names[]={"menu    partywin","menu    raid1   ","menu    raid2   "};
    for(unsigned j=0;j<3;j++) {
        memcpy(image+500+j*44,names[j],16);
        uint32_t address=static_cast<uint32_t>(reinterpret_cast<uintptr_t>(image+1000+j*4));
        memcpy(image+500+j*44+32,&address,4);
    }
    void** globals[3]={}; uintptr_t main=reinterpret_cast<uintptr_t>(image+1000);
    Check(PartyGlobals(image,4096,main,globals) && globals[1]==reinterpret_cast<void**>(image+1004)
        && globals[2]==reinterpret_cast<void**>(image+1008),"partywin and both alliance HUD globals discovered and cross-checked");
    Check(!PartyGlobals(image,4096,main+4,globals),"registry disagrees with code signature: reject");
    image[500+44+8]='X'; Check(!PartyGlobals(image,4096,main,globals),"wrong menu name: reject"); image[500+44+8]='r';
    memcpy(image+1500,image+500,132);
    Check(!PartyGlobals(image,4096,main,globals),"ambiguous menu registry: reject");
    // Independent target registry slot, cross-checked against hideparty's target global.
    memcpy(image+2500,"menu    targetwi",16); memset(image+2516,0,16);
    uint32_t target=static_cast<uint32_t>(reinterpret_cast<uintptr_t>(image+1100));
    memcpy(image+2532,&target,4);
    Check(TargetGlobal(image,4096,target)==reinterpret_cast<void**>(image+1100),"targetwi registry agrees with code signature");
    Check(!TargetGlobal(image,4096,target+4),"mismatched target global is rejected");
    // Real arrow-call byte fixtures from Target::Draw. The shared callee is independently checked.
    const uint8_t mainArrow[]={0x33,0xc9,0x8a,0x8e,0xba,0,0,0,0x68,0x80,0x80,0x80,0xe0,0x0f,0xbf,0xc0,
        0x8b,0x4c,0x8e,0x78,0x68,0,0,0x80,0x3f,0x68,0,0,0x80,0x3f,0x52,0x50,0xe8,0,0,0,0};
    const uint8_t subArrow[]={0x33,0xc9,0x8a,0x8e,0xba,0,0,0,0x57,0x68,0,0,0x80,0x3f,0x68,0,0,0x80,0x3f,
        0x8b,0x4c,0x8e,0x78,0x52,0x50,0xe8,0,0,0,0};
    const uint8_t sprite[]={0x83,0xec,0x0c,0x53,0x55,0x56,0x8b,0xf1,0x57,0x8b,0x6e,0x14,0x8d,0x4e,0x04,
        0x89,0x6c,0x24,0x18,0x89,0x4c,0x24,0x14,0xe8};
    memcpy(image+2200,mainArrow,sizeof(mainArrow)); memcpy(image+2300,subArrow,sizeof(subArrow));
    memcpy(image+2400,sprite,sizeof(sprite));
    uint8_t* mainCall=image+2200+MAIN_ARROW_CALL; uint8_t* subCall=image+2300+SUB_ARROW_CALL;
    int32_t rel=Distance(mainCall+5,image+2400); memcpy(mainCall+1,&rel,4);
    rel=Distance(subCall+5,image+2400); memcpy(subCall+1,&rel,4);
    ArrowCalls arrows;
    uint8_t mainSaved[5],subSaved[5]; memcpy(mainSaved,mainCall,5); memcpy(subSaved,subCall,5);
    Check(TakeArrows(arrows,image,4096,reinterpret_cast<void*>(&Replacement)),"both native overhead-arrow calls recognised and redirected");
    Check(VerifyCall(mainCall,reinterpret_cast<uint8_t*>(&Replacement)) && VerifyCall(subCall,reinterpret_cast<uint8_t*>(&Replacement)),"redirection remains a CALL, preserving native return addresses");
    Check(arrows.sprite==image+2400 && memcmp(image+2400,sprite,sizeof(sprite))==0,"general sprite renderer is not patched");
    GiveArrows(arrows);
    Check(memcmp(mainCall,mainSaved,5)==0 && memcmp(subCall,subSaved,5)==0,"both arrow calls restored on unload");
    // one of the two arrow calls written over by something else after: the other given back, that one left
    Check(TakeArrows(arrows,image,4096,reinterpret_cast<void*>(&Replacement)),"arrows taken again");
    uint8_t other[5]={0xE8,1,2,3,4}; memcpy(subCall,other,5);
    GiveArrows(arrows);
    Check(memcmp(mainCall,mainSaved,5)==0 && memcmp(subCall,other,5)==0 && CodeStranded(),"the main arrow call given back; another's in the sub's left, stranded");
    CodeStranded()=false; memcpy(subCall,subSaved,5);
    subCall[1]^=1;
    Check(!TakeArrows(arrows,image,4096,reinterpret_cast<void*>(&Replacement)) && memcmp(mainCall,mainSaved,5)==0,
        "different arrow callee rejected before changing either call");
    bool blocked=true;
    { ArrowScope scope(blocked,true); Check(!blocked,"target arrow bypasses GPU suppression"); }
    Check(blocked,"target HUD suppression restored after arrow");
    { ArrowScope scope(blocked,false); Check(blocked,"party suppression is not bypassed outside target scope"); }
    // Execute an x86 CALL forwarding all eight native stack words, then returning with ret 0x20.
    // Each push [esp+32] takes the next original argument backwards as the stack grows.
    uint8_t* caller=image+3000;
    for (unsigned i=0;i<8;i++) { const uint8_t push[]={0xff,0x74,0x24,0x20}; memcpy(caller+i*4,push,4); }
    caller[32]=0xe8;
    rel=Distance(caller+37,reinterpret_cast<void*>(&ForwardSprite)); memcpy(caller+33,&rel,4);
    caller[37]=0xc2; caller[38]=0x20; caller[39]=0;
    FlushInstructionCache(GetCurrentProcess(),caller,40);
    SpriteDraw invoke=reinterpret_cast<SpriteDraw>(caller);
    invoke(image+3100,nullptr,0xfffffff0,123,0x3f800000,0x40000000,0xe04040d0,0,1,0xabcdef01);
    const uint32_t expected[8]={0xfffffff0,123,0x3f800000,0x40000000,0xe04040d0,0,1,0xabcdef01};
    Check(seenThis==image+3100 && memcmp(seenWords,expected,sizeof(expected))==0,
        "x86 arrow wrapper preserves this and all eight stack words including float/colour bits");
    Check(!seenBlocking && spriteBlocked,"GPU bypass is active only during forwarded original sprite draw");
    VirtualFree(image,0,MEM_RELEASE);

    PartyVertex t[3]={{-10,5,0,1,0xff000000,0,0},{10,5,0,1,0xffffffff,1,0},{0,15,0,1,0xff000000,0.5f,1}},out[12];
    unsigned n=ClipTriangle(t,{0,0,8,10},out);
    Check(n>=3 && n<=7,"partially clipped triangle remains a bounded polygon");
    bool inside=true,interpolated=false;
    for(unsigned i=0;i<n;i++) {
        inside &= out[i].x>=0 && out[i].x<=8 && out[i].y>=0 && out[i].y<=10;
        if(out[i].x==0 && out[i].y==5) interpolated=std::fabs(out[i].u-0.5f)<0.001f && (out[i].color&255)==128;
    }
    Check(inside,"all emitted vertices obey command clipping"); Check(interpolated,"clipping interpolates texture UVs and colour");
    Check(ClipTriangle(t,{100,100,200,200},out)==0,"fully clipped triangle emits nothing");
    Check(sizeof(PartyShared)==168,"shared ABI size matches Lua (no 64-bit texture IDs in Lua)");
    Check(TextureAddress(0x12345678ull)==0x12345678u,"a texture id below 2 GB is its address");
    Check(TextureAddress(0x8ABC0000ull)==0x8ABC0000u,"a texture id above 2 GB, zero-extended, is its address");
    Check(TextureAddress(0xFFFFFFFF8ABC0000ull)==0x8ABC0000u,"a texture id above 2 GB, sign-extended, is its address");
    Check(TextureAddress(0xFFFFFFFF12345678ull)==0,"ones over a pointer below 2 GB are no sign extension: refused");
    Check(TextureAddress(0x100000000ull)==0 && TextureAddress(1)==0 && TextureAddress(0)==0 && TextureAddress(0xFFFFull)==0,
        "a 33-bit value, the font mark, a null and a low address are refused");
    int16_t rect[4]={400,300,620,460}; NativeRect native={};
    Check(MakeNativeRect(rect,true,1280,960,1920,1080,17,native),"native menu-scaled HUD rectangle captured");
    Check(std::fabs(native.Right-1240.0f/1920)<0.0001f && std::fabs(native.Bottom-920.0f/1080)<0.0001f && native.Frame==17,
        "native rect follows independent menu/viewport axis scaling");
    Check(MakeNativeRect(rect,false,0,0,1920,1080,18,native) && std::fabs(native.Left-400.0f/1920)<0.0001f,
        "unscaled native windows retain pixel coordinates");
    Check(!MakeNativeRect(rect,true,0,960,1920,1080,18,native) && !MakeNativeRect(rect,false,0,0,0,1080,18,native),
        "invalid menu/viewport dimensions rejected without publishing geometry");
    // lens: the arrow's tip moved to where the warp shows it, and left alone without a live warp
    {
        lens::Shared warp={"LENS-WARP",1,sizeof(lens::Shared),10,9,lens::Panini,0.25f,1/0.556459f,1/1.260417f};
        int32_t x=3268,y=720;   // near the right edge of a 3440x1440 menu layer, half way down
        Check(WarpArrow(x,y,3440,1440,&warp) && x>3268 && y==720,"lens warping: the arrow's tip moved out toward the edge, as the warp shows it");
        double s=0,t=0; lens::ScreenOf(3268.0/3440,0.5,warp.TanH,warp.TanV,lens::Panini,warp.Strength,s,t);
        Check(x==static_cast<int32_t>(std::lround(s*3440)),"to the warp's own ScreenOf, in menu pixels");
        int32_t mx=1720,my=500;
        Check(WarpArrow(mx,my,3440,1440,&warp) && mx==1720,"the middle column stays");
        int32_t ox=3268,oy=720;
        warp.Frame=20;
        Check(!WarpArrow(ox,oy,3440,1440,&warp) && ox==3268 && oy==720,"a stale warp leaves the arrow alone");
        Check(!WarpArrow(ox,oy,3440,1440,nullptr) && ox==3268,"no lens leaves the arrow alone");
        warp.Frame=10; warp.Strength=0;
        Check(!WarpArrow(ox,oy,3440,1440,&warp) && ox==3268,"strength 0 leaves the arrow alone");
        warp.Strength=0.25f;
        Check(!WarpArrow(ox,oy,0,0,&warp),"no menu size, nothing moved");
    }
    {
        // imgui making its font texture again: the last capture is kept, a few frames, for that alone
        Check(HoldCapture(REFUSED_TEXTURE_NOT_READY,true,0),"texture not ready: the last capture kept");
        Check(HoldCapture(REFUSED_TEXTURE_NOT_READY,true,PARTY_HOLD_FRAMES-1) && !HoldCapture(REFUSED_TEXTURE_NOT_READY,true,PARTY_HOLD_FRAMES),
            "kept PARTY_HOLD_FRAMES frames in a row, then refused");
        Check(!HoldCapture(REFUSED_TEXTURE_NOT_READY,false,0),"none fresh to keep: refused");
        Check(!HoldCapture(REFUSED_VERTEX,true,0) && !HoldCapture(REFUSED_TEXTURE_ID,true,0) && !HoldCapture(REFUSED_NONE,true,0),
            "any other refusal is not covered");
        // the capture holds its texture: imgui letting the old atlas go leaves it there to draw from
        struct Texture { int refs=1; void AddRef() { ++refs; } void Release() { --refs; } } old;
        std::vector<TextureRun<Texture>> runs;
        AppendRun(runs,&old,0,6); AppendRun(runs,&old,6,6);
        old.Release(); // the renderer's own reference, given up as imgui makes the texture again
        Check(old.refs==1 && runs.size()==1 && runs[0].count==12,"the old atlas lives while a capture is drawn from it");
        for (auto& r:runs) r.texture->Release();
        Check(old.refs==0,"and goes with the capture");
    }
    {
        // The party list at the screen's bottom right (normalized, a 1000x500 viewport): 800,400 to 1000,500;
        // what is within an eighth of the height (62.5 pixels) of it is its own
        NativeRect list={0.8f,0.8f,1.0f,1.0f,1};
        struct V { float x,y,z,rhw; uint32_t color; float u,v; };
        auto Quad=[](V* q,float l,float t,float r,float b) { V v[4]={{l,t,0,1,0,0,0},{r,t,0,1,0,0,0},{l,b,0,1,0,0,0},{r,b,0,1,0,0,0}}; memcpy(q,v,sizeof(v)); };
        auto Away=[&](float l,float t,float r,float b) { V q[4]; Quad(q,l,t,r,b); return DrawOutside(q,4,sizeof(V),list,1000,500,PARTY_PASS_REACH); };
        Check(Away(400,200,600,230),"the fish's bar mid-screen is away from the party list");
        Check(Away(820,50,980,80),"far above the list, in its columns, is away");
        Check(!Away(820,410,980,430),"a row of the list is its own");
        Check(!Away(780,450,804,460),"a frame piece reaching into the list is its own");
        Check(!Away(790,450,795,460),"a shadow against it is its own");
        Check(!Away(820,330,980,380),"the pet bar just above the list is its own");
        Check(!Away(700,470,790,490),"the pet bar just beside it is its own");
        V bad[2]={{NAN,0,0,1,0,0,0},{0,0,0,1,0,0,0}};
        V gauge[4]; Quad(gauge,400,200,600,230);
        Check(!DrawOutside(bad,2,sizeof(V),list,1000,500,PARTY_PASS_REACH) && !DrawOutside(nullptr,4,sizeof(V),list,1000,500,PARTY_PASS_REACH)
            && !DrawOutside(gauge,0,sizeof(V),list,1000,500,PARTY_PASS_REACH) && !DrawOutside(gauge,4,4,list,1000,500,PARTY_PASS_REACH)
            && !DrawOutside(gauge,4,sizeof(V),list,0,500,PARTY_PASS_REACH),
            "no position, no vertices, too short a vertex or no viewport: not away");
    }
    printf("%d failures\n",failures); return failures?1:0;
}
