// lens shaders: the tokens written out in src/shaders.h are what Wine's d3dx9 assembles from the
// same text, so the hand-written bytecode means what its comments say.
#include <windows.h>
#include <stdio.h>
#include <string.h>
#include "../src/shaders.h"
static int failures = 0;
static void Check(bool ok, const char* text) { printf("%s %s\n", ok ? "ok" : "FAIL", text); if (!ok) ++failures; }

struct Buffer {   // ID3DXBuffer's vtable, all that is used of it
    virtual HRESULT __stdcall QueryInterface(const IID&, void**) = 0;
    virtual ULONG __stdcall AddRef() = 0;
    virtual ULONG __stdcall Release() = 0;
    virtual void* __stdcall GetBufferPointer() = 0;
    virtual DWORD __stdcall GetBufferSize() = 0;
};
typedef HRESULT(WINAPI* Assemble)(const char*, UINT, const void*, void*, DWORD, Buffer**, Buffer**);

static bool Same(Assemble assemble, const char* text, const uint32_t* tokens, size_t size) {
    Buffer *code = nullptr, *errors = nullptr;
    HRESULT hr = assemble(text, static_cast<UINT>(strlen(text)), nullptr, nullptr, 0, &code, &errors);
    if (errors) { printf("%s\n", static_cast<const char*>(errors->GetBufferPointer())); errors->Release(); }
    if (FAILED(hr) || !code) return false;
    bool same = code->GetBufferSize() == size && memcmp(code->GetBufferPointer(), tokens, size) == 0;
    if (!same) {
        const uint32_t* got = static_cast<const uint32_t*>(code->GetBufferPointer());
        for (DWORD i = 0; i < code->GetBufferSize() / 4; ++i) printf("%08X%s", got[i], i % 8 == 7 ? "\n" : " ");
        printf("\n");
    }
    code->Release();
    return same;
}

int main() {
    HMODULE d3dx = LoadLibraryA("d3dx9_43.dll");
    auto assemble = d3dx ? reinterpret_cast<Assemble>(GetProcAddress(d3dx, "D3DXAssembleShader")) : nullptr;
    if (!assemble) { printf("lens shaders: no d3dx9_43 to assemble with; skipped\n"); return 0; }
    const char* average = "ps_1_1\ntex t0\ntex t1\ntex t2\ntex t3\nadd_d2 r0, t0, t1\nadd_d2 r1, t2, t3\nadd_d2 r0, r0, r1\n";
    Check(Same(assemble, average, lens::AverageShader, sizeof(lens::AverageShader)), "the average of four taps");
    char modulate[256];
    snprintf(modulate, sizeof(modulate), "%smul r0, r0, v0\n", average);
    Check(Same(assemble, modulate, lens::AverageModulateShader, sizeof(lens::AverageModulateShader)), "the average modulated by the vertices' colour");
    printf(failures ? "%d FAILED\n" : "lens shaders: all checks passed\n", failures);
    return failures ? 1 : 0;
}
