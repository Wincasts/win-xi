// Portable CPU microbenchmark, not an in-game FPS or Direct3D performance measurement.
#include <cstdio>
#include <cstring>
#include <chrono>
#include <vector>
#include <cstdlib>
#include "../src/clip.h"
#include "../src/runs.h"
struct Triangle { PartyVertex v[3]; };
struct Texture { int refs=0; bool fail=false; void AddRef() { if (fail) throw 1; ++refs; } void Release() { --refs; } };
static void Check(bool ok,const char* text) { if (!ok) { std::fprintf(stderr,"FAIL %s\n",text); std::exit(1); } }
using Clipper=unsigned(*)(const PartyVertex*,PartyClip,PartyVertex*);
static volatile unsigned checksum=0;
static double Measure(Clipper clipper,const std::vector<Triangle>& triangles) {
    auto start=std::chrono::steady_clock::now();
    unsigned sum=0;
    for (unsigned pass=0;pass<100;pass++) for (const auto& t:triangles) {
        PartyVertex out[12]; unsigned n=clipper(t.v,{0,0,1000,1000},out);
        sum+=n; if (n) sum+=unsigned(out[0].x+1000);
    }
    checksum=sum;
    return std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-start).count();
}
int main() {
    unsigned random=12345;
    auto value=[&]() { random=random*1664525u+1013904223u; return float(random%20001)/10-500; };
    for (unsigned i=0;i<10000;i++) {
        PartyVertex t[3],a[12],b[12];
        for (auto& v:t) v={value(),value(),0,1,random,0.25f,0.75f};
        unsigned na=ClipTriangleFull(t,{0,0,1000,1000},a), nb=ClipTriangle(t,{0,0,1000,1000},b);
        Check(na==nb && !std::memcmp(a,b,na*sizeof(PartyVertex)),"fast clip must exactly match full clipping");
    }
    Texture a,b; std::vector<TextureRun<Texture>> runs;
    AppendRun(runs,&a,0,3); AppendRun(runs,&a,3,9); AppendRun(runs,&a,12,0);
    Check(runs.size()==1 && runs[0].count==12 && a.refs==1,"adjacent texture runs merge; empty commands retain nothing");
    AppendRun(runs,&b,12,3); AppendRun(runs,&a,15,3); AppendRun(runs,&a,99,3);
    Check(runs.size()==4 && a.refs==3 && b.refs==1,"different textures and gaps preserve draw order/boundaries");
    Texture bad; bad.fail=true; bool failed=false;
    try { AppendRun(runs,&bad,102,3); } catch (...) { failed=true; }
    Check(failed && runs.size()==4 && bad.refs==0,"failed retain leaves no unowned texture in cleanup");
    for (auto& run:runs) run.texture->Release();
    runs.clear();
    Check(a.refs==0 && b.refs==0,"retained texture references balance");
    for (unsigned i=0;i<1000;i++) AppendRun(runs,&a,i*3,3);
    Check(runs.size()==1 && a.refs==1 && runs[0].count==3000,"1000 adjacent commands become one retained run");
    for (auto& run:runs) run.texture->Release();
    std::vector<Triangle> triangles(10000);
    for (unsigned i=0;i<triangles.size();i++) {
        float x=10+float(i%980),y=10+float((i*7)%980);
        if (i%20==18) x=1200; // outside
        if (i%20==19) x=-1;   // partially clipped
        triangles[i]={{{x,y,0,1,0xff00ff00,0,0},{x+2,y,0,1,0xff00ff00,1,0},{x,y+2,0,1,0xff00ff00,0,1}}};
    }
    double full=Measure(ClipTriangleFull,triangles); unsigned expected=checksum;
    double fast=Measure(ClipTriangle,triangles);
    Check(checksum==expected,"mixed-workload clipping benchmark output unchanged");
    std::printf("10,000 randomized clipping comparisons and texture-run ownership/order checks passed\n");
    std::printf("CPU only: 1,000,000 triangles (90%% inside/5%% outside/5%% partial): full %.2f ms; fast %.2f ms (%.2fx)\n",full,fast,full/fast);
    std::printf("Synthetic contiguous same-texture workload: 1,000 commands -> 1 run/texture reference\n");
}
