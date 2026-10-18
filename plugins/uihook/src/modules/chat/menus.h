// Native action-menu placement, independent of chat ABI. Move the native layout target BEFORE
// Window::Render calls Window::Update: its frame, rows, cursor geometry and hit tests then share
// the same coordinates. Never translate GPU vertices or intercept mouse coordinates.
#pragma once
#include <cmath>
#define MENU_UPDATE_PATTERN "83 EC 08 56 8B F1 8D 4E 14 E8 ?? ?? ?? ?? 85 C0 89 44 24 04 0F 84"
#define MENU_TARGET_PROOF "66 8B 86 8C 00 00 00 66 89 47 1A 66 8B 8E 8E 00 00 00 66 89 4F 1C 66 8B 96 90 00 00 00 66 89 57 22 66 8B 86 92 00 00 00 66 89 47 24"
struct MenuShared {
    char Magic[16]; uint32_t Version,Size,Frame,Supported;
    volatile uint32_t RequestFrame,HostSlot; volatile float Panel[4]; // Lua-published pixel bounds
    uint32_t MenuFrame,Applied,Restored; char LastName[16];
    // The expanded chat log (fulllog) placed by its bottom-left, in display pixels, while LogRequestFrame is fresh;
    // the same move as the menus', its own Update laying out its rows, tabs, scrollbar and hit-tests there
    volatile uint32_t LogRequestFrame; volatile float LogPlace[2];
    uint32_t LogFrame,LogApplied,LogRestored;
};
static_assert(sizeof(MenuShared)==108,"menu ABI");
static bool MenuFresh(const MenuShared& menu,const ChatShared& chat,uint32_t frame) {
    const uint32_t request=menu.RequestFrame,host=menu.HostSlot;
    return menu.Supported && request && frame-request<=2 && host<2
        && chat.DrawnFrame[host] && frame-chat.DrawnFrame[host]<=2
        && !(chat.StateFlags & CHAT_EXPANDED);
}
static bool MenuWritable(void* ptr,size_t bytes) {
    MEMORY_BASIC_INFORMATION page={};
    if (!ptr || !VirtualQuery(ptr,&page,sizeof(page)) || page.State!=MEM_COMMIT
        || page.Protect & (PAGE_GUARD|PAGE_NOACCESS)) return false;
    const DWORD access=page.Protect & 0xff;
    const uintptr_t start=reinterpret_cast<uintptr_t>(ptr),end=reinterpret_cast<uintptr_t>(page.BaseAddress)+page.RegionSize;
    return (access==PAGE_READWRITE || access==PAGE_EXECUTE_READWRITE || access==PAGE_WRITECOPY
        || access==PAGE_EXECUTE_WRITECOPY) && end>=start && bytes<=end-start;
}
static bool MenuPosition(const int16_t* target,bool scaled,const int* dimensions,unsigned width,unsigned height,
    const float* panel,int16_t* out) {
    if (!width || !height || target[2]<=0 || target[3]<=0) return false;
    for (unsigned i=0;i<4;i++) if (!std::isfinite(panel[i])) return false;
    if (panel[2]<=panel[0] || panel[3]<=panel[1] || panel[0]<0 || panel[1]<0
        || panel[2]>width || panel[3]>height) return false;
    if (scaled && (dimensions[0]<=0 || dimensions[1]<=0 || dimensions[0]>16384 || dimensions[1]>16384)) return false;
    const float sx=scaled ? dimensions[0]/640.0f : 1.0f,sy=scaled ? dimensions[1]/480.0f : 1.0f;
    const float x=(std::min)(panel[0]/sx,float(width)/sx-target[2]);
    const float y=(panel[1]-2.0f)/sy-target[3];
    // A tall native list that cannot fit above the panel is left native, not clipped/offscreen.
    if (x<0 || y<0 || x>32767 || y>32767) return false;
    out[0]=static_cast<int16_t>(std::floor(x+0.5f)); out[1]=static_cast<int16_t>(std::floor(y+0.5f));
    return true;
}
// The full log's target for its bottom-left at place (display pixels), its size the game's. Kept on the screen:
// moved left or down as far as it must; a log taller than the screen is left where the game puts it.
static bool LogPosition(const int16_t* target,bool scaled,const int* dimensions,unsigned width,unsigned height,
    const float* place,int16_t* out) {
    if (!width || !height || target[2]<=0 || target[3]<=0) return false;
    for (unsigned i=0;i<2;i++) if (!std::isfinite(place[i])) return false;
    if (place[0]<0 || place[1]<=0 || place[0]>width || place[1]>height) return false;
    if (scaled && (dimensions[0]<=0 || dimensions[1]<=0 || dimensions[0]>16384 || dimensions[1]>16384)) return false;
    const float sx=scaled ? dimensions[0]/640.0f : 1.0f,sy=scaled ? dimensions[1]/480.0f : 1.0f;
    const float right=float(width)/sx,bottom=float(height)/sy;
    if (target[3]>bottom) return false;
    const float x=(std::max)(0.0f,(std::min)(place[0]/sx,right-target[2]));
    const float y=(std::max)(0.0f,place[1]/sy-target[3]);
    if (x>32767 || y>32767) return false;
    out[0]=static_cast<int16_t>(std::floor(x+0.5f)); out[1]=static_cast<int16_t>(std::floor(y+0.5f));
    return true;
}
static bool LogFresh(const MenuShared& menu,uint32_t frame) {
    const uint32_t request=menu.LogRequestFrame;
    return menu.Supported && request && frame-request<=2;
}
class MenuModule {
    struct Entry {
        const char* name; void** global=nullptr; void* window=nullptr; void* header=nullptr; void* owner=nullptr;
        int16_t original[2]={},applied[2]={}; bool moved=false;
    };
    // Only this registry family: command, magic, abilities, inventory/item-use and their
    // controls, and an event's choices (query: an NPC's Yes/No). Not expanded chat, trade/shop
    // layouts or arbitrary windows near chat.
    // Each global owns a Window at +8; live ownership is checked again before any write.
    static constexpr unsigned Count=10;
    Entry entries[Count]={{"menu    playermo"},{"menu    magselec"},{"menu    abiselec"},{"menu    iuse    "},
        {"menu    mgcmenu "},{"menu    abimenu "},{"menu    itemctrl"},{"menu    lootope "},{"menu    inventor"},
        {"menu    query   "}};
    Entry log={"menu    fulllog "}; // its owner global given by the chat module, which recognises it
    void (__fastcall* update)(void*,void*)=nullptr;
    uint32_t sampledFrame=0;
    void* children[Count]={};
    static void* Child(const Entry& entry,void** ownerOut=nullptr) {
        void* owner=nullptr; void* child=nullptr;
        if (!entry.global || !ChatRead(entry.global,&owner,4) || !owner
            || !ChatRead(static_cast<uint8_t*>(owner)+8,&child,4)) return nullptr;
        if (ownerOut) *ownerOut=owner;
        return child;
    }
    static bool Fields(void* window,uint8_t* data,void*& header) {
        char name[8];
        return window && ChatRead(window,data,0x9a) && (memcpy(&header,data+4,4),header)
            && ChatRead(static_cast<uint8_t*>(header)+0x46,name,8) && !memcmp(name,"menu    ",8)
            && MenuWritable(static_cast<uint8_t*>(window)+0x8c,12);
    }
    void Restore(Entry& entry,MenuShared& state) { Restore(entry,state.Restored); }
    void Restore(Entry& entry,uint32_t& restored) {
        if (!entry.moved) return;
        uint8_t data[0x9a]; void* header=nullptr; void* owner=nullptr;
        if (Child(entry,&owner)==entry.window && owner==entry.owner
            && Fields(entry.window,data,header) && header==entry.header) {
            int16_t target[2]; memcpy(target,data+0x8c,4);
            bool changed=false;
            for (unsigned i=0;i<2;i++) if (target[i]==entry.applied[i]) {
                target[i]=entry.original[i]; changed=true;
            }
            if (changed) {
                auto* at=static_cast<uint8_t*>(entry.window);
                memcpy(at+0x8c,target,4); const int32_t dirty=-1; memcpy(at+0x94,&dirty,4);
                // Rebuild native geometry too, including when the window is no longer rendered.
                update(entry.window,nullptr); restored++;
            }
        }
        entry.moved=false; entry.window=entry.header=entry.owner=nullptr;
    }
public:
    bool Discover(uint8_t* begin,size_t size,uint8_t* renderer) {
        update=nullptr; sampledFrame=0;
        for (auto& entry:entries) { entry.global=nullptr; entry.moved=false; }
        log=Entry{"menu    fulllog "};
        auto* found=UniquePattern(begin,size,MENU_UPDATE_PATTERN);
        // Pin the caller and all four short target fields, not just a similar function prefix.
        if (!found || size_t(found-begin)+0x230>size || !renderer || renderer[9]!=0xe8) return false;
        int32_t relative=0; memcpy(&relative,renderer+10,4);
        if (renderer+14+relative!=found || !UniquePattern(found,0x230,MENU_TARGET_PROOF)) return false;
        unsigned count=0;
        for (auto& entry:entries) {
            bool ambiguous=false;
            for (size_t i=0;i+44<=size;i++) {
                if (memcmp(begin+i,entry.name,16)) continue;
                const uint8_t zeros[16]={}; if (memcmp(begin+i+16,zeros,16)) continue;
                uintptr_t address=0; memcpy(&address,begin+i+32,4);
                const uintptr_t low=reinterpret_cast<uintptr_t>(begin);
                if (address<low || address-low>size-4 || address%4 || !MenuWritable(reinterpret_cast<void*>(address),4)) continue;
                auto** global=reinterpret_cast<void**>(address);
                if (entry.global && entry.global!=global) { ambiguous=true; break; }
                entry.global=global;
            }
            if (ambiguous) entry.global=nullptr;
            if (entry.global) ++count;
        }
        if (!entries[0].global || !count) return false;
        update=reinterpret_cast<decltype(update)>(found);
        return true;
    }
    void Stop(MenuShared& state) { for (auto& entry:entries) Restore(entry,state); }
    // The full log's owner global (the fulllog registry row's, from the chat module); null disables placing it
    void Log(void** global) { if (!log.moved) log.global=global; }
    void StopLog(MenuShared& state) { Restore(log,state.LogRestored); }
    // Before the full log's own Update: its target moved to the requested bottom-left, or given back
    void BeforeLog(void* window,MenuShared& state,bool active,const int* dimensions,unsigned width,unsigned height) {
        if (!update || !log.global) return;
        if (!active) { StopLog(state); return; }
        void* owner=nullptr;
        if (Child(log,&owner)!=window) return;
        if (log.moved && window!=log.window) { log.moved=false; log.window=log.header=log.owner=nullptr; }
        uint8_t data[0x9a]; void* header=nullptr;
        if (!Fields(window,data,header)) return;
        if (log.moved && (header!=log.header || owner!=log.owner)) log.moved=false;
        int16_t target[4],desired[2]; memcpy(target,data+0x8c,8);
        float place[2]={state.LogPlace[0],state.LogPlace[1]};
        if (!LogPosition(target,data[0x99]!=0,dimensions,width,height,place,desired)) { StopLog(state); return; }
        if (!log.moved) { memcpy(log.original,target,4); log.window=window; log.header=header; log.owner=owner; }
        else for (unsigned i=0;i<2;i++) if (target[i]!=log.applied[i]) log.original[i]=target[i];
        if (target[0]!=desired[0] || target[1]!=desired[1]) {
            auto* at=static_cast<uint8_t*>(window);
            memcpy(at+0x8c,desired,4); const int32_t dirty=-1; memcpy(at+0x94,&dirty,4);
            log.moved=true; state.LogApplied++;
        }
        memcpy(log.applied,desired,4);
        state.LogFrame=state.Frame;
    }
    void Before(void* window,MenuShared& state,bool active,const int* dimensions,unsigned width,unsigned height) {
        if (!update) return;
        if (!active) { Stop(state); return; }
        if (sampledFrame!=state.Frame) {
            for (unsigned i=0;i<Count;i++) children[i]=Child(entries[i]);
            sampledFrame=state.Frame;
        }
        for (unsigned index=0;index<Count;index++) {
            auto& entry=entries[index];
            void* current=children[index];
            if (entry.moved && current!=entry.window) { entry.moved=false; entry.window=entry.header=entry.owner=nullptr; }
            void* owner=nullptr;
            if (current!=window || Child(entry,&owner)!=window) continue;
            uint8_t data[0x9a]; void* header=nullptr;
            if (!Fields(window,data,header)) return;
            if (entry.moved && (header!=entry.header || owner!=entry.owner)) entry.moved=false;
            int16_t target[4],desired[2]; memcpy(target,data+0x8c,8);
            float panel[4]; for (unsigned i=0;i<4;i++) panel[i]=state.Panel[i];
            if (!MenuPosition(target,data[0x99]!=0,dimensions,width,height,panel,desired)) { Restore(entry,state); return; }
            if (!entry.moved) { memcpy(entry.original,target,4); entry.window=window; entry.header=header; entry.owner=owner; }
            else for (unsigned i=0;i<2;i++) if (target[i]!=entry.applied[i]) entry.original[i]=target[i];
            if (target[0]!=desired[0] || target[1]!=desired[1]) {
                auto* at=static_cast<uint8_t*>(window);
                memcpy(at+0x8c,desired,4); const int32_t dirty=-1; memcpy(at+0x94,&dirty,4);
                // Window::Update consumes dirty once and updates ALL its shapes and row origins.
                // No double update/timer tick and no selection, owner or mouse-position writes.
                entry.moved=true; state.Applied++;
            }
            memcpy(entry.applied,desired,4);
            state.MenuFrame=state.Frame; memcpy(state.LastName,entry.name,16);
            return;
        }
    }
};
