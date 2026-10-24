// /uihook native as it draws: the game's own windows drawn moved and scaled (native.h), the game's own menu kept whole.
// One of the party module's parts: Enter about each window Window::Render draws, Draw for each screen-space draw in
// it. nativeui gives it its settings.
#pragma once
#include <vector>
#include <algorithm>
#include "../../drawcontext.h"
#include "native.h"
#include "skinmodule.h"

class NativeModule {
public:
    NativeLook look;
    DrawContext* ctx=nullptr;
    SkinModule* skin=nullptr;       // a moved draw given the skin's colours
    uint8_t* menuManager=nullptr;   // the game's menu manager: the screen's size in the game's units at +80
    std::vector<uint8_t> scaledVertices;  // a draw's vertices, moved
    void Init(DrawContext* context,SkinModule* skinModule,uint8_t* manager) { ctx=context; skin=skinModule; menuManager=manager; }
    // /uihook native: the window being drawn taken, where it is one named, for its draws to be moved and tinted
    NativeLook::Saved Enter(void* window) {
        if (!look.Any()) return look.Enter(nullptr,ctx->Frame());
        void* header=nullptr; char name[16];
        if (!window || !ChatRead(static_cast<uint8_t*>(window)+4,&header,4) || !header
            || !ChatRead(static_cast<uint8_t*>(header)+0x46,name,16)) return look.Enter(nullptr,ctx->Frame());
        // where the game draws it (+3A: left, top, right, bottom), not its layout target (+8C), which for some is over the
        // chat log while they are drawn elsewhere (the Master and Automaton menu, beside the main menu)
        int16_t drawn[4];
        const bool placed=ChatRead(static_cast<uint8_t*>(window)+0x3a,drawn,sizeof(drawn)) && drawn[2]>drawn[0] && drawn[3]>drawn[1];
        if (look.groupOn && placed) {
            const int16_t place[4]={drawn[0],drawn[1],int16_t(drawn[2]-drawn[0]),int16_t(drawn[3]-drawn[1])};
            look.Note(name,place,ctx->Frame());
        }
        // the same in pixels, for one drawn the first time to be placed at once
        float pixels[4]; uint8_t scaled=0; int16_t dims[2]={640,480};
        const bool hint=placed && ChatRead(static_cast<uint8_t*>(window)+0x99,&scaled,1)
            && (!scaled || (menuManager && ChatRead(menuManager+0x80,dims,sizeof(dims)) && dims[0]>0 && dims[1]>0));
        if (hint) {
            const float sx=scaled ? dims[0]/640.0f : 1.0f,sy=scaled ? dims[1]/480.0f : 1.0f;
            pixels[0]=drawn[0]*sx; pixels[1]=drawn[1]*sy; pixels[2]=drawn[2]*sx; pixels[3]=drawn[3]*sy;
        }
        return look.Enter(name,ctx->Frame(),hint ? pixels : nullptr);
    }
    // A screen-space draw of a window with an entry: counted into its bounds; then, where it is moved, drawn so in its
    // place (its vertices copied and moved). vertices: from min, as an indexed draw's are.
    bool Draw(D3DPRIMITIVETYPE t,UINT min,UINT vertices,UINT count,const void* indices,D3DFORMAT format,const void* data,UINT stride) {
        NativeEntry* e=look.current;
        if (!e || !data || !vertices || stride<8) return false;
        const UINT used=min+vertices;
        auto* device=ctx->Device(); DWORD shader=0;
        if (!device || !ctx->DrawFvf(shader) || (shader & D3DFVF_POSITION_MASK)!=D3DFVF_XYZRHW) { look.Unmoved(); return false; }
        look.Gather(static_cast<const uint8_t*>(data)+size_t(min)*stride,vertices,stride);
        // the screen's size, not the viewport's: the game clips some text to its window with a viewport (the title
        // box's), which taken for the screen made its middle the box's and its words pinched there
        D3DVIEWPORT8 viewport={};
        float screen[2]={};
        NativeTransform move; bool whole=false;
        bool placing=used<=8192 && SUCCEEDED(device->GetViewport(&viewport)) && ctx->ScreenSize(device,viewport,screen)
            && look.Transform(screen[0],screen[1],move,&whole);
        if (placing) look.OnBar(static_cast<const uint8_t*>(data)+size_t(min)*stride,vertices,stride,move);
        // wholly outside its frame (the inventory's count, up in the menu name's bar): left where the game put it, but
        // where the whole side is moved
        if (placing && !move.pinch && !whole && !look.Within(static_cast<const uint8_t*>(data)+size_t(min)*stride,vertices,stride)) { e->kept++; placing=false; }
        if (!placing) return false;
        scaledVertices.assign(static_cast<const uint8_t*>(data),static_cast<const uint8_t*>(data)+size_t(used)*stride);
        NativeTransformVertices(scaledVertices.data()+size_t(min)*stride,vertices,stride,move);
        // the skin's colours for its picture, as SkinEnd would have given them had it drawn it: the moved windows
        // had the game's (the bottom-left buttons blue-grey and orange, the frame faded at the sides)
        if (skin) skin->RecolourActive(scaledVertices,used,stride,shader);
        const void* drawn=scaledVertices.data();
        // a viewport clipping the draw to its window moved with it, so what is moved is not clipped away
        const bool clipped=(viewport.X>0 || viewport.Y>0 || float(viewport.Width)<screen[0] || float(viewport.Height)<screen[1]);
        D3DVIEWPORT8 moved=viewport;
        if (clipped) {
            float corners[4]={float(viewport.X),float(viewport.Y),float(viewport.X+viewport.Width),float(viewport.Y+viewport.Height)};
            move.Apply(corners[0],corners[1]); move.Apply(corners[2],corners[3]);
            const float x0=(std::max)(0.0f,corners[0]),y0=(std::max)(0.0f,corners[1]);
            const float x1=(std::min)(screen[0],corners[2]),y1=(std::min)(screen[1],corners[3]);
            if (x1>x0 && y1>y0) {
                moved.X=DWORD(x0+0.5f); moved.Y=DWORD(y0+0.5f); moved.Width=DWORD(x1-x0+0.5f); moved.Height=DWORD(y1-y0+0.5f);
                device->SetViewport(&moved);
            }
        }
        ctx->scaling=true;
        const bool ok=indices ? SUCCEEDED(device->DrawIndexedPrimitiveUP(t,min,vertices,count,indices,format,drawn,stride))
            : SUCCEEDED(device->DrawPrimitiveUP(t,count,drawn,stride));
        ctx->scaling=false;
        if (clipped) device->SetViewport(&viewport);
        if (ok) e->moved++;
        return ok;
    }
    void Command(const char* command) {
        char verb[16]={},name[16]={},a[16]={},b[16]={}; char line[256];
        const int words=sscanf_s(command,"/uihook native %15s %15s %15s %15s",verb,16u,name,16u,a,16u,b,16u);
        auto* chat=ctx->core->GetChatManager();
        if (words>=2 && !_stricmp(verb,"group") && !_stricmp(name,"off")) {
            // quiet: as an addon sends it, said nowhere
            snprintf(line,sizeof(line),"[uihook:native] the windows over the chat log as the game draws them again (%u).",look.GroupOff());
            if (words>=3 && !_stricmp(a,"quiet")) return;
        } else if (words>=3 && !_stricmp(verb,"group")) {
            look.Group(float(atof(name)),float(atof(a)));
            snprintf(line,sizeof(line),"[uihook:native] the windows the game stacks over the chat log drawn %s, %s from where it puts them.",name,a);
            if (words>=4 && !_stricmp(b,"quiet")) return;
        } else if (words>=2 && !_stricmp(verb,"size")) {
            const bool ok=look.MenuScale(float(atof(name)));
            snprintf(line,sizeof(line),ok ? "[uihook:native] every framed window drawn %.2f times its size, from its corner of the screen."
                : "[uihook:native] a size from 0.5 to 3.",look.menuScale);
            if (words>=3 && !_stricmp(a,"quiet")) return;
        } else if (words>=2 && !_stricmp(verb,"inset")) {
            look.Inset(float(atof(name)));
            snprintf(line,sizeof(line),look.inset>0 ? "[uihook:native] the sides brought in %.0f pixels: the bar across the top that much shorter at each end, the windows each side with it."
                : "[uihook:native] the sides where the game puts them.",look.inset);
            if (words>=3 && !_stricmp(a,"quiet")) return;
        } else if (words<1) {
            unsigned n=0; for (auto& e:look.entries) if (e.name[0]) n++;
            snprintf(line,sizeof(line),"[uihook:native] %u windows looked at; the game's mouse hit-tests stay where it puts them.",n);
            chat->Write(0,false,line);
            if (look.menuScale!=1) {
                snprintf(line,sizeof(line),"  every framed window drawn %.2f times its size",look.menuScale);
                chat->Write(0,false,line);
            }
            if (look.inset>0) {
                snprintf(line,sizeof(line),"  the sides brought in %.0f pixels",look.inset);
                chat->Write(0,false,line);
            }
            if (look.groupOn) {
                snprintf(line,sizeof(line),"  group over the chat log: %.0f, %.0f; the log's top %d at its left %d (%s)",look.groupX,look.groupY,
                    look.logTop,look.logLeft,look.logFrame ? "seen" : "not drawn yet");
                chat->Write(0,false,line);
            }
            for (auto& e:look.entries) {
                if (!e.name[0]) continue;
                char seen[48];
                if (!e.seen) snprintf(seen,sizeof(seen),"not drawn since asked");
                else snprintf(seen,sizeof(seen),"drawn %u frames ago",ctx->Frame()-e.seen);
                snprintf(line,sizeof(line),"  %.8s%s: %s; move %.0f,%.0f (%u draws moved, %u outside its frame kept, %u could not be)",
                    e.name+8,e.group ? (e.member ? " (group)" : " (group, not now)") : "",seen,e.dx,e.dy,e.moved,e.kept,e.unmoved);
                chat->Write(0,false,line);
            }
            return;
        } else {
            snprintf(line,sizeof(line),"[uihook:native] /uihook native [group <x> <y> | group off | inset <pixels> | size <factor>]");
        }
        chat->Write(0,false,line);
    }
};
