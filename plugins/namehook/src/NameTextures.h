#pragma once
// The textures one owner's drawing is drawn from (the names', a claim slot's, a layer's, the bubbles', the
// popups'): each an addon gave by its address, held (AddRef) while it is drawn from and let go (Release) once
// another or none is given; and imgui's font texture, given as HOOK_TEXTURE_FONT, only borrowed. The host looks
// that one up afresh every frame before it draws, so it never needs holding, and a hold on it could keep a
// device reset from going through: Ashita's imgui may make it in the default pool, which a reset needs released.
// Templated on the texture type, so the tests count references with a stand-in.
#include <stddef.h>
#include <stdint.h>

#ifndef HOOK_TEXTURE_FONT
#define HOOK_TEXTURE_FONT 1
#endif

template<class Texture, size_t N>
struct NameTextures {
    Texture* Slots[N] = {};  // what each slot draws from now: what RenderCustom indexes by a quad's Texture
    bool Borrowed[N] = {};   // the slot holds imgui's font texture, not held

    // givens are the first part of the slots (count of them), extras the rest; either may be null, for none.
    // font is imgui's font texture this frame, for a slot given HOOK_TEXTURE_FONT, or null.
    void Retain(const uint32_t* givens, size_t count, const uint32_t* extras, Texture* font) {
        for (size_t i = 0; i < N; i++) {
            const uint32_t* from = i < count ? givens : extras;
            const uint32_t given = from != nullptr ? from[i < count ? i : i - count] : 0;
            const bool borrow = given == HOOK_TEXTURE_FONT;
            Texture* texture = borrow ? font : reinterpret_cast<Texture*>(static_cast<uintptr_t>(given));
            if (texture == Slots[i] && (borrow || texture == nullptr) == Borrowed[i]) {
                continue;
            }
            if (texture != nullptr && !borrow) texture->AddRef();
            if (Slots[i] != nullptr && !Borrowed[i]) Slots[i]->Release();
            Slots[i] = texture;
            Borrowed[i] = borrow || texture == nullptr;
        }
    }

    // Every held texture let go, every slot empty
    void Clear() {
        Retain(nullptr, 0, nullptr, nullptr);
    }

    Texture* operator[](size_t i) const { return Slots[i]; }
};
