// What the modules that change the game's own drawing share for each draw: the device, the frame, the draw's vertex
// format (asked of the device once a draw for all that want it), the screen's size (read once a frame), and whether a
// draw of uihook's own is under way, which Ashita gives back to the draw callbacks and is not to be heard again.
#pragma once
#include "Ashita.h"
#include <stdint.h>

struct DrawContext {
    IAshitaCore* core=nullptr;
    const uint32_t* frame=nullptr;  // the party block's frame, counted at each Present
    bool scaling=false;             // a draw of uihook's own (moved, scaled or skinned) under way
    IDirect3DDevice8* Device() const { return core ? core->GetDirect3DDevice() : nullptr; }
    uint32_t Frame() const { return frame ? *frame : 0; }
    // Each draw callback first: the draw under way's format is asked again
    void NewDraw() { drawFvfKnown=false; }
    // The draw under way's vertex format (its FVF), asked of the device once a draw for all that want it (the census,
    // the watch, the native look, the skin each asked for every draw); false where it cannot be told
    bool DrawFvf(DWORD& fvf) {
        if (!drawFvfKnown) {
            drawFvfKnown=true;
            auto* device=Device();
            drawFvfOk=device && SUCCEEDED(device->GetVertexShader(&drawFvf));
        }
        fvf=drawFvf;
        return drawFvfOk;
    }
    // Whether the draw under way is of screen-space vertices (pretransformed, as the game's interface is)
    bool ScreenDraw(DWORD& fvf) { return DrawFvf(fvf) && (fvf & D3DFVF_POSITION_MASK)==D3DFVF_XYZRHW; }
    // The screen's size: the render target's the draw is made to (the scene may be drawn to a larger one first), the
    // viewport's where it cannot be read. Read once a frame, at the first window's draw that wants it (the windows draw
    // to the screen's own target, after the scene): asked for each draw moved it was three calls of the device's a draw.
    bool ScreenSize(IDirect3DDevice8* device,const D3DVIEWPORT8& viewport,float* out) {
        if (screenFrame!=Frame() || !screenSize[0]) {
            screenFrame=Frame(); screenSize[0]=screenSize[1]=0;
            IDirect3DSurface8* target=nullptr; D3DSURFACE_DESC desc{};
            if (SUCCEEDED(device->GetRenderTarget(&target)) && target) {
                if (SUCCEEDED(target->GetDesc(&desc))) { screenSize[0]=float(desc.Width); screenSize[1]=float(desc.Height); }
                target->Release();
            }
        }
        out[0]=screenSize[0]; out[1]=screenSize[1];
        if (!out[0] || !out[1]) { out[0]=float(viewport.X+viewport.Width); out[1]=float(viewport.Y+viewport.Height); }
        return out[0]>0 && out[1]>0;
    }
private:
    DWORD drawFvf=0; bool drawFvfKnown=false, drawFvfOk=false;
    float screenSize[2]={}; uint32_t screenFrame=0;
};
