// Adjacent runs may be merged after CPU clipping: no GPU scissor/state changes remain between them.
#pragma once
#include <stdint.h>
#include <vector>
template<class Texture> struct TextureRun { Texture* texture; uint32_t first, count; };
template<class Texture> static void AppendRun(std::vector<TextureRun<Texture>>& runs,Texture* texture,uint32_t first,uint32_t count) {
    if (!count) return; // fully clipped commands need neither a texture reference nor a GPU call
    if (!runs.empty() && runs.back().texture==texture && runs.back().first+runs.back().count==first) {
        runs.back().count+=count;
    } else {
        // Commit storage before AddRef so an allocation exception cannot leak this reference.
        runs.push_back({texture,first,count});
        try { texture->AddRef(); }
        catch (...) { runs.pop_back(); throw; } // never expose a failed retain to cleanup
    }
}
