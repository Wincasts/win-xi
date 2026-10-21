// A record of every draw over a few frames, for finding where the game's 3D world ends and its UI
// begins. Pure: the plugin fills a Draw from the device for each call and hands it here; this keeps
// the distinct matrices, targets and textures, groups the draws into runs that share their state, and
// writes the report. Nothing here touches Direct3D, so the check runs it without a device.
#pragma once
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <math.h>
#include <string.h>
#include <string>
#include <vector>

namespace lens {

struct Matrix { float m[16]; };  // row-major, as D3DMATRIX: m[0] _11, m[5] _22, m[10] _33, m[11] _34, m[14] _43, m[15] _44

enum Kind : uint8_t { DP, DIP, DPUP, DIPUP };
static const char* const KindNames[] = { "DP", "DIP", "DPUP", "DIPUP" };

struct Draw {
    uint8_t kind = DP;
    uint32_t prim = 0, count = 0;      // primitive type and count
    uint32_t shader = 0;               // the FVF, or a vertex shader's handle (bit 0 set)
    uintptr_t target = 0;              // the render target surface
    uint32_t targetW = 0, targetH = 0;
    bool targetBack = false;           // the target is the back buffer
    uint32_t vpX = 0, vpY = 0, vpW = 0, vpH = 0;
    float vpMinZ = 0, vpMaxZ = 1;
    uint32_t zEnable = 0, zWrite = 0, blend = 0, fog = 0, lighting = 0;
    Matrix proj = {}, view = {};
    uintptr_t texture = 0;
    uint32_t texW = 0, texH = 0;
    uint32_t caller[2] = {};           // the game's nearest two return addresses up the stack, as offsets in FFXiMain.dll; 0 for none
};

// Screen-space vertices: an FVF (bit 0 clear) whose position is XYZRHW.
inline bool ScreenSpace(uint32_t shader) { return !(shader & 1) && (shader & 0x00E) == 0x004; }

// The fields of view a projection holds, in degrees; false for one that is not a perspective one.
inline bool Perspective(const Matrix& p, double& h, double& v) {
    if (fabs(p.m[11] - 1.0f) > 1e-3f || fabs(p.m[15]) > 1e-3f || p.m[0] <= 0 || p.m[5] <= 0) return false;
    const double deg = 180.0 / 3.14159265358979323846;
    h = 2 * atan(1.0 / p.m[0]) * deg;
    v = 2 * atan(1.0 / p.m[5]) * deg;
    return true;
}

class Capture {
public:
    struct Event {
        enum Type : uint8_t { Draw_, BeginScene, EndScene, Present } type;
        uint32_t draw;  // index into draws for Draw_
        bool back;      // for BeginScene and EndScene: the scene is drawn to the back buffer
    };

    std::vector<Draw> draws;
    std::vector<Event> events;
    std::vector<Matrix> projections, views;
    std::vector<uintptr_t> targets, textures;
    std::vector<uint32_t> drawProj, drawView, drawTarget, drawTexture; // each draw's index into the lists above
    uint32_t frames = 0;

    void Mark(Event::Type type, bool back) {
        events.push_back({ type, 0, back });
        if (type == Event::Present) ++frames;
    }

    void Add(const Draw& d) {
        drawProj.push_back(Intern(projections, d.proj));
        drawView.push_back(Intern(views, d.view));
        drawTarget.push_back(Intern(targets, d.target));
        drawTexture.push_back(Intern(textures, d.texture));
        events.push_back({ Event::Draw_, static_cast<uint32_t>(draws.size()), false });
        draws.push_back(d);
    }

    // Whether two draws belong in the same run: the same target, space, projection, view, depth test,
    // viewport and calling site.
    bool SameRun(uint32_t a, uint32_t b) const {
        const Draw &x = draws[a], &y = draws[b];
        return drawTarget[a] == drawTarget[b] && ScreenSpace(x.shader) == ScreenSpace(y.shader)
            && drawProj[a] == drawProj[b] && drawView[a] == drawView[b] && x.zEnable == y.zEnable
            && x.vpX == y.vpX && x.vpY == y.vpY && x.vpW == y.vpW && x.vpH == y.vpH
            && x.caller[0] == y.caller[0];
    }

    std::string Report(const char* header) const {
        std::string out = header;
        out += Line("%u frames, %u draws, %u projections, %u views, %u targets, %u textures\n\n",
            frames, (unsigned)draws.size(), (unsigned)projections.size(), (unsigned)views.size(), (unsigned)targets.size(), (unsigned)textures.size());
        out += "projections:\n";
        for (size_t i = 0; i < projections.size(); ++i) {
            const Matrix& p = projections[i];
            double h = 0, v = 0;
            if (Perspective(p, h, v)) out += Line("  P%u perspective: %.2f across, %.2f up; _11 %.6f _22 %.6f _33 %.6f _43 %.6f\n", (unsigned)i, h, v, p.m[0], p.m[5], p.m[10], p.m[14]);
            else out += Line("  P%u other: _11 %.6f _22 %.6f _33 %.6f _34 %.6f _41 %.6f _42 %.6f _43 %.6f _44 %.6f\n", (unsigned)i, p.m[0], p.m[5], p.m[10], p.m[11], p.m[12], p.m[13], p.m[14], p.m[15]);
        }
        out += "targets:\n";
        for (size_t i = 0; i < targets.size(); ++i) {
            for (size_t d = 0; d < draws.size(); ++d) if (drawTarget[d] == i) {
                out += Line("  T%u %ux%u%s\n", (unsigned)i, draws[d].targetW, draws[d].targetH, draws[d].targetBack ? " (back buffer)" : "");
                break;
            }
        }
        out += "\nruns (draws in a row sharing target, space, projection, view, depth test, viewport and caller):\n";
        Runs(out);
        out += "\ndraws:\n";
        for (const Event& e : events) {
            if (e.type == Event::BeginScene || e.type == Event::EndScene) { out += Scene(e); continue; }
            if (e.type == Event::Present) { out += "  == Present\n"; continue; }
            out += DrawLine(e.draw);
        }
        return out;
    }

private:
    template <class T> static bool Same(const T& a, const T& b) { return memcmp(&a, &b, sizeof(T)) == 0; }
    template <class T> static uint32_t Intern(std::vector<T>& list, const T& value) {
        for (size_t i = 0; i < list.size(); ++i) if (Same(list[i], value)) return static_cast<uint32_t>(i);
        list.push_back(value);
        return static_cast<uint32_t>(list.size() - 1);
    }
    static std::string Line(const char* format, ...) {
        char buffer[512];
        va_list args;
        va_start(args, format);
        vsnprintf(buffer, sizeof(buffer), format, args);
        va_end(args);
        return buffer;
    }
    static std::string Scene(const Event& e) {
        return Line("  -- %s%s\n", e.type == Event::BeginScene ? "BeginScene" : "EndScene", e.back ? " (back buffer)" : " (another target)");
    }
    std::string Caller(const Draw& d) const {
        if (d.caller[0]) return Line("game+%06X<%06X", d.caller[0], d.caller[1]);
        return "not the game";
    }
    std::string State(uint32_t i) const {
        const Draw& d = draws[i];
        return Line("T%u %s P%u V%u z%u%s blend%u fog%u vp %u,%u %ux%u",
            drawTarget[i], ScreenSpace(d.shader) ? "screen" : "3d", drawProj[i], drawView[i], d.zEnable, d.zWrite ? "w" : "", d.blend, d.fog,
            d.vpX, d.vpY, d.vpW, d.vpH);
    }
    std::string DrawLine(uint32_t i) const {
        const Draw& d = draws[i];
        return Line("  #%u %s prim%u x%u fvf %08X %s tex%u %ux%u %s\n", i, KindNames[d.kind & 3], d.prim, d.count, d.shader,
            State(i).c_str(), drawTexture[i], d.texW, d.texH, Caller(d).c_str());
    }
    void Runs(std::string& out) const {
        uint32_t frame = 0;
        bool open = false;
        uint32_t first = 0, last = 0, prims = 0;
        auto close = [&]() {
            if (!open) return;
            out += Line("  #%u-#%u (%u draws, %u prims) %s %s\n", first, last, last - first + 1, prims, State(first).c_str(), Caller(draws[first]).c_str());
            open = false;
        };
        for (const Event& e : events) {
            if (e.type == Event::Present) { close(); out += Line("  == Present (frame %u ends)\n", frame++); continue; }
            if (e.type == Event::BeginScene || e.type == Event::EndScene) { close(); out += Scene(e); continue; }
            if (open && SameRun(last, e.draw) && e.draw == last + 1) { last = e.draw; prims += draws[e.draw].count; continue; }
            close();
            open = true;
            first = last = e.draw;
            prims = draws[e.draw].count;
        }
        close();
    }
};

} // namespace lens
