// Chatdiag/FancyChat discovery; recognition only. Rendering shares Window::Render's dispatcher.
#pragma once
#include <windows.h>
#include <stdint.h>
#include <string.h>
#include <cmath>
#include <algorithm>

#define CHAT_INPUT_PATTERN "8B 48 0C 85 C9 74 ?? 8B 51 08 85 D2 74 ?? 3B 05"
#define CHAT_STATE_PATTERN "83 EC ?? B9 ?? ?? ?? ?? E8 ?? ?? ?? ?? 0F BF 4C 24 ?? 84 C0"
// Phoenix full-log constructor: cross-check the vtable before reading its cursor/page fields.
#define CHAT_FULL_PATTERN "56 8B F1 8D 4E 04 E8 ?? ?? ?? ?? 33 C0 B1 01 66 C7 46 0E FF FF 89 46 08 88 4E 0C 66 89 46 14 66 89 46 16 66 89 46 18 66 89 46 1A 88 46 25 C7 06 ?? ?? ?? ?? 88 4E 24 8B C6 5E C3"
// Full-log content Draw: native tabs, glyph rows and row decorations. Cross-check with vtable +10.
#define CHAT_FULL_DRAW_PATTERN "83 EC 0C 53 55 56 8B F1 57 33 ED 8B 46 54 89 6C 24 14 50 E8"
#define CHAT_FULL_INIT_PATTERN "8B 56 58 89 56 1C 89 5E 28"
// The compact log owner's Update, where its whole lines (+31, the ceiling of its height +34 over its row height +54)
// and page rows (+30) are made, and its grow (a row added to the height per message, up to its most lines +4E):
// the fields the two log windows' current, most and fewest (+50) lines are read from. Both windows share the class.
#define CHAT_LINES_UPDATE_PATTERN "8B 46 34 0F BF 4E 54 99 F7 F9 88 46 31 FE C0 3B D3 88 46 30"
#define CHAT_LINES_GROW_PATTERN "8A 44 24 04 83 EC 08 84 C0 53 55 56 57 8B F1 74 42 8B 46 34 0F BF 4E 54"
#define CHAT_FULL_FIELDS_PATTERN "8B 55 54 8B 0D ?? ?? ?? ?? 52 E8 ?? ?? ?? ?? 25 FF 00 00 00 89 47 10 8B 4D 58 89 4F 0C 8B 55 20 8B 4D 58 2B C2 2B C1 89 47 14"
// StateFlags bits: 16, a menu (a row's actions, input) open over the live full log, which keeps its skin
enum { CHAT_SELECTED_PRIMARY=1, CHAT_SELECTED_SPLIT=2, CHAT_EXPANDED=4, CHAT_NATIVE_BROWSE=8, CHAT_NESTED_MENU=16 };
// SupportedMask bits: 1 primary, 2 split, 4 input, 8 full-log state, 16 content pass-through, 32 control art,
// 64 the tab strip and scrollbar measured as the game draws them, and hidden when the addon draws its own,
// 128 the full log's rows of text decoded and measured as the game draws them, and hidden the same way
// 256 the game's two log windows' routing read: which chat modes each shows, and the second window's bounds
enum { CHAT_FULL_SUPPORTED=8, CHAT_FULL_SKIN_SUPPORTED=16, CHAT_CONTROLS_SUPPORTED=32, CHAT_REPLACE_SUPPORTED=64, CHAT_TEXT_SUPPORTED=128, CHAT_WINDOWS_SUPPORTED=256, CHAT_LINES_SUPPORTED=512, CHAT_COLORS_SUPPORTED=1024 };
// 1024 the game's chat colours read: each mode's category and each category's colour, and the inline palette
// 512 the two log windows' lines read: each window's current whole lines (the game grows a row a message and shrinks
// to its fewest), its most and its fewest
// WindowFlags bits: 1, the second log window is shown, so the game routes each message by its filters;
// clear, the first window shows everything (and WindowModes says so)
enum { CHAT_SECOND_WINDOW=1 };
// ReplaceControls bits, written by Lua: which native controls to leave undrawn, the addon drawing its own in their places
enum { CHAT_REPLACE_TABS=1, CHAT_REPLACE_SCROLL=2, CHAT_REPLACE_TEXT=4 };
// A row of the full log's text as last drawn: its bounds, normalized to the viewport (where placed), its text's
// place and length in the shared Text, its message's chat mode, and flags: 1 the game's cursor is on it, 2 pressed,
// 4 marked by the game, 8 cut (longer than the room left), 16 placed (its Rect is where it was drawn)
enum { CHAT_ROW_CURSOR=1, CHAT_ROW_PRESSED=2, CHAT_ROW_MARKED=4, CHAT_ROW_CUT=8, CHAT_ROW_PLACED=16 };
struct ChatTextRow { float Rect[4]; uint32_t Offset, Length, Mode, Flags; };
#define CHAT_TEXT_ROWS 128   // rows of text published at most: a 4K screen's full log holds fewer
#define CHAT_TEXT_BYTES 65536 // the room for their text, in all
// A tab of the game's strip as last drawn: its bounds, normalized to the viewport, the channel whose tab it is
// (0 to 10, or 0xffffffff when its sprite is not one of the owner's) and whether it was drawn chosen
struct ChatTab { float Rect[4]; uint32_t Channel, Selected; };
#define CHAT_PATTERN "A1 ?? ?? ?? ?? C6 40 59 01 8B 0D ?? ?? ?? ?? C6 41 59 01 C2 08 00"
struct ChatShared {
    char Magic[16];
    uint32_t Version, Size, SupportedMask, Frame, Submit;
    uint32_t DrawnFrame[3], NativeFrame[3];
    float InputRect[4]; // viewport-normalized native window rectangle; read-only
    uint32_t InputRectFrame;
    float PrimaryRect[4]; // native primary log bounds, independent of replacement height
    uint32_t PrimaryRectFrame;
    float ReplacementRect[4]; // actual captured primary window, in ImGui pixels
    uint32_t ReplacementRectFrame;
    float ExpandedRect[4]; // normalized native fulllog bounds; same primary replacement slot
    uint32_t ExpandedRectFrame;
    uint32_t StateFlags, StateFrame;
    uint32_t FullScroll, FullCursor, FullPageRows, FullFilter; // diagnostics, read-only
    uint32_t ControlStyleFrame; // Lua-owned, copied only with a successful expanded capture
    float ControlColors[4][4]; // highlight, tab label/art, cursor, scrollbar; RGBA [0,1]
    uint32_t ReplaceControls; // Lua-owned CHAT_REPLACE_* bits, copied only with a successful expanded capture
    uint32_t TabFrame, TabCount; // the game's tab strip as last drawn in a skinned full log
    ChatTab Tabs[12];
    uint32_t ScrollFrame, ScrollPage, ScrollCount, ScrollTop; // its scrollbar: page rows, rows in all, rows above the view
    float ScrollRect[4]; // normalized to the viewport, as the game drew (or would have drawn) it
    uint32_t TextFrame, TextCount, TextSerial; // the full log's rows of text as last drawn in a skinned full log, newest first; the serial changes when they do
    ChatTextRow Rows[CHAT_TEXT_ROWS];
    char Text[CHAT_TEXT_BYTES]; // each row's bytes at its Offset, as the game was given them (CP932 with 1E/1F colour codes)
    float SplitRect[4]; // the game's second log window's bounds, normalized to the viewport; read-only
    uint32_t SplitRectFrame;
    uint32_t WindowFrame, WindowFlags; // the game's routing, read each frame: CHAT_SECOND_WINDOW when the second window is shown
    uint32_t WindowModes[2][8]; // per window, a bit for each chat mode (its low byte) the window's filters keep; a mode word
                                // with bit 15 set goes to the first window alone, whatever these say
    uint32_t LinesFrame;        // the two log windows' lines, read each frame from the game's owners
    uint32_t Lines[2][3];       // per window: its lines now (0, nothing shown), its most and its fewest
    uint32_t ColorFrame, ColorSerial; // the game's chat colours, read each frame; the serial moves when they change
    uint32_t InlineColors[17];  // the colours 1E 00 to 1E 10 name (0, none: 1E 01 returns to the row's colour)
    uint32_t CategoryColors[256]; // by category: the colour the game draws its modes in, and 1E and 1F codes name;
                                  // 0 where the game has no entry (it draws those 80808080). Components are of
                                  // 80 as one: 80808080 is white, FF twice white, 40 half
    uint8_t ModeCategory[256];  // by chat mode (its low byte): its category, or 0 where the game has no entry
};
static_assert(sizeof(ChatShared)==71684, "chat ABI 13");
// ABI 8: primary capture=1 replaces compact contents; capture=2 skins the expanded frame ONLY.
// Never replay a capture across the compact/full boundary: the native content must remain visible.
static inline bool ChatReplayAllowed(const ChatShared& chat, bool expandedCapture) {
    return !(chat.StateFlags & CHAT_NATIVE_BROWSE)
        && bool(chat.StateFlags & CHAT_EXPANDED)==expandedCapture
        && (!expandedCapture || (chat.SupportedMask & CHAT_FULL_SKIN_SUPPORTED));
}
// Re-enable native GPU submissions at content Draw, leaving them enabled for Window::Render's
// subsequent cursor and scrollbar. The outer window scope restores the previous blocking state.
static inline void ChatNativeContent(bool expandedSkin, bool& blocking) {
    if (expandedSkin) blocking=false;
}

// Move the clock group by the same offset as the replacement log's top-left, preserving
// the game's spacing between the stock clock and stock log. Expired/hidden logs never move it.
static inline bool ChatClockOffset(const ChatShared& chat,float width,float height,float& x,float& y) {
    x=y=0;
    if ((chat.StateFlags & CHAT_EXPANDED) || !(chat.SupportedMask & 1) || !std::isfinite(width) || !std::isfinite(height) || width<=0 || height<=0) return false;
    const uint32_t stamps[]={chat.PrimaryRectFrame,chat.ReplacementRectFrame,chat.NativeFrame[0],chat.DrawnFrame[0]};
    for (auto stamp:stamps) if (!stamp || chat.Frame-stamp>2) return false;
    for (unsigned i=0;i<4;i++) if (!std::isfinite(chat.PrimaryRect[i]) || !std::isfinite(chat.ReplacementRect[i])) return false;
    if (chat.PrimaryRect[2]<=chat.PrimaryRect[0] || chat.PrimaryRect[3]<=chat.PrimaryRect[1]
        || chat.ReplacementRect[2]<=chat.ReplacementRect[0] || chat.ReplacementRect[3]<=chat.ReplacementRect[1]) return false;
    x=chat.ReplacementRect[0]-chat.PrimaryRect[0]*width;
    y=chat.ReplacementRect[1]-chat.PrimaryRect[1]*height;
    return std::isfinite(x) && std::isfinite(y);
}
static inline bool ChatTranslateVertices(void* data,unsigned count,unsigned stride,float x,float y) {
    if (!data || !count || count>4096 || stride<8 || !std::isfinite(x) || !std::isfinite(y)) return false;
    auto* bytes=static_cast<uint8_t*>(data);
    for (unsigned i=0;i<count;i++) {
        float pos[2]; memcpy(pos,bytes+size_t(i)*stride,8);
        pos[0]+=x; pos[1]+=y;
        if (!std::isfinite(pos[0]) || !std::isfinite(pos[1])) return false;
        memcpy(bytes+size_t(i)*stride,pos,8);
    }
    return true;
}

static bool ChatReadable(const MEMORY_BASIC_INFORMATION& page) {
    const DWORD access=page.Protect & 0xff;
    return page.State==MEM_COMMIT && !(page.Protect & PAGE_GUARD)
        && (access==PAGE_READONLY || access==PAGE_READWRITE || access==PAGE_WRITECOPY
            || access==PAGE_EXECUTE_READ || access==PAGE_EXECUTE_READWRITE || access==PAGE_EXECUTE_WRITECOPY);
}
static bool ChatRead(const void* at,void* out,size_t size) {
    MEMORY_BASIC_INFORMATION page={};
    const uintptr_t address=reinterpret_cast<uintptr_t>(at);
    if (!address || !size || address+size<address || !VirtualQuery(at,&page,sizeof(page)) || !ChatReadable(page)
        || address+size>reinterpret_cast<uintptr_t>(page.BaseAddress)+page.RegionSize) return false;
    memcpy(out,at,size);
    return true;
}
// As much of size bytes from at as can be read, region by region, one VirtualQuery a region (a table read entry by
// entry with ChatRead asks once an entry, every frame): how many bytes were copied, from the start.
static inline size_t ChatReadSpan(const void* at,void* out,size_t size) {
    const uintptr_t address=reinterpret_cast<uintptr_t>(at);
    if (!address || address+size<address) return 0;
    size_t done=0;
    while (done<size) {
        MEMORY_BASIC_INFORMATION page={};
        const uintptr_t from=address+done;
        if (!VirtualQuery(reinterpret_cast<const void*>(from),&page,sizeof(page)) || !ChatReadable(page)) break;
        const uintptr_t end=reinterpret_cast<uintptr_t>(page.BaseAddress)+page.RegionSize;
        if (end<=from) break;
        const size_t count=(std::min)(size-done,size_t(end-from));
        memcpy(static_cast<uint8_t*>(out)+done,reinterpret_cast<const void*>(from),count);
        done+=count;
    }
    return done;
}
class ChatModule {
    void** slots[2]={};
    void** activeMenu=nullptr;
    void** fullOwner=nullptr;
    uint8_t* sizeByte=nullptr;
    uintptr_t fullVtable=0;
    uint8_t* fullDraw=nullptr;
    bool linesKnown=false; // the owners' line fields pinned by their Update and grow
    bool Full(void*& owner,void*& child) const {
        uintptr_t vtable=0;
        return fullOwner && ChatRead(fullOwner,&owner,4) && owner && ChatRead(owner,&vtable,4) && vtable==fullVtable
            && ChatRead(static_cast<uint8_t*>(owner)+8,&child,4) && child;
    }
    static bool Named(void* window,const char* expected) {
        uint8_t* header=nullptr; char name[16];
        return window && ChatRead(static_cast<uint8_t*>(window)+4,&header,4) && header
            && ChatRead(header+0x46,name,16) && !memcmp(name,expected,16);
    }
public:
    bool Discover(uint8_t* begin,size_t size) {
        Clear();
        auto* at=UniquePattern(begin,size,CHAT_PATTERN);
        if (!at || size<4) return false;
        uintptr_t addresses[2]={};
        memcpy(&addresses[0],at+1,4); memcpy(&addresses[1],at+11,4);
        const uintptr_t low=reinterpret_cast<uintptr_t>(begin);
        for (auto address:addresses)
            if (address<low || address-low>size-4 || address%4) return false;
        if (addresses[0]==addresses[1]) return false;
        for (unsigned i=0;i<2;i++) slots[i]=reinterpret_cast<void**>(addresses[i]);
        auto* input=UniquePattern(begin,size,CHAT_INPUT_PATTERN);
        if (input && size_t(input-begin)+20<=size) {
            uintptr_t address=0; memcpy(&address,input+16,4);
            if (address>=low && address-low<=size-4 && address%4==0)
                activeMenu=reinterpret_cast<void**>(address);
        }
        auto* state=UniquePattern(begin,size,CHAT_STATE_PATTERN);
        uintptr_t manager=0;
        if (state) memcpy(&manager,state+4,4);
        if (manager>=low && size>=0xf2 && manager-low<=size-0xf2) sizeByte=reinterpret_cast<uint8_t*>(manager)+0xf1;
        auto* constructor=UniquePattern(begin,size,CHAT_FULL_PATTERN);
        if (constructor) memcpy(&fullVtable,constructor+48,4);
        uintptr_t fullUpdate=0;
        auto* fields=UniquePattern(begin,size,CHAT_FULL_FIELDS_PATTERN);
        auto* init=UniquePattern(begin,size,CHAT_FULL_INIT_PATTERN);
        if (fullVtable>=low && size>=44 && fullVtable-low<=size-44 && fullVtable%4==0)
            memcpy(&fullUpdate,reinterpret_cast<const void*>(fullVtable+0x28),4);
        // These fields belong to this exact class's Update and Open methods, not just a similar menu.
        if (!constructor || !fields || !init || init<constructor || size_t(init-constructor)>0x200
            || fullUpdate<low || fullUpdate-low>=size || reinterpret_cast<uintptr_t>(fields)<fullUpdate
            || reinterpret_cast<uintptr_t>(fields)-fullUpdate>0x600) fullVtable=0;
        // Three adjacent native registry entries, cross-checked against the primary/split signature.
        bool ambiguous=false;
        for (size_t i=0;i+132<=size;i++) {
            auto* row=begin+i;
            if (memcmp(row,"menu    logwindo",16) || memcmp(row+44,"menu    logwin2 ",16) || memcmp(row+88,"menu    fulllog ",16)) continue;
            uintptr_t pointers[3]={};
            for (unsigned j=0;j<3;j++) memcpy(&pointers[j],row+44*j+32,4);
            if (pointers[0]!=addresses[0] || pointers[1]!=addresses[1] || pointers[2]<low || pointers[2]-low>size-4
                || pointers[2]%4 || pointers[2]==pointers[0] || pointers[2]==pointers[1]) continue;
            if (fullOwner) ambiguous=true;
            fullOwner=reinterpret_cast<void**>(pointers[2]);
        }
        if (ambiguous) fullOwner=nullptr;
        linesKnown=UniquePattern(begin,size,CHAT_LINES_UPDATE_PATTERN) && UniquePattern(begin,size,CHAT_LINES_GROW_PATTERN);
        auto* draw=UniquePattern(begin,size,CHAT_FULL_DRAW_PATTERN);
        uintptr_t entry=0;
        if (draw && fullVtable && ChatRead(reinterpret_cast<void*>(fullVtable+0x10),&entry,4)
            && entry==reinterpret_cast<uintptr_t>(draw)) fullDraw=draw;
        return true;
    }
    uint8_t* ExpandedDraw() const { return ExpandedSupported() ? fullDraw : nullptr; }
    void** SplitOwner() const { return slots[1]; } // the second log window's owner global (logwin2)
    bool InputSupported() const { return activeMenu!=nullptr; }
    bool ExpandedSupported() const { return activeMenu && fullOwner && sizeByte && fullVtable; }
    bool LinesSupported() const { return linesKnown && slots[0] && slots[1]; }
    void Clear() { slots[0]=slots[1]=nullptr; activeMenu=nullptr; fullOwner=nullptr; sizeByte=nullptr; fullVtable=0; fullDraw=nullptr; linesKnown=false; }
    // Each log window's lines now, most and fewest, read from its owner and checked for sense (a row height of 4 to
    // 128, most 0 to 64, fewest no more than most, the lines no more than most and one, the height within them);
    // nothing published where any of it cannot be read or makes no sense.
    void SampleLines(ChatShared& shared,uint32_t frame) const {
        shared.LinesFrame=0;
        if (!LinesSupported()) return;
        uint32_t lines[2][3];
        for (unsigned i=0;i<2;i++) {
            uint8_t* owner=nullptr; int8_t now=0; int16_t most=0,fewest=0,row=0; int32_t height=0;
            if (!ChatRead(slots[i],&owner,4) || !owner || !ChatRead(owner+0x31,&now,1) || !ChatRead(owner+0x4e,&most,2)
                || !ChatRead(owner+0x50,&fewest,2) || !ChatRead(owner+0x54,&row,2) || !ChatRead(owner+0x34,&height,4)) return;
            if (row<4 || row>128 || most<0 || most>64 || fewest<0 || fewest>most || now<0 || now>most+1
                || height<0 || height>(most+2)*row) return;
            lines[i][0]=uint32_t(now); lines[i][1]=uint32_t(most); lines[i][2]=uint32_t(fewest);
        }
        memcpy(shared.Lines,lines,sizeof(lines));
        shared.LinesFrame=frame;
    }
    void Sample(ChatShared& shared,uint32_t frame) const {
        shared.StateFlags=shared.StateFrame=0;
        shared.FullScroll=shared.FullCursor=shared.FullPageRows=shared.FullFilter=0;
        void* active=nullptr;
        if (!activeMenu || !ChatRead(activeMenu,&active,4)) return;
        shared.StateFrame=frame;
        const int index=Identify(active);
        uint8_t cursor[2]={};
        if ((index==0 || index==1) && ChatRead(static_cast<uint8_t*>(active)+0x62,cursor,2) && cursor[0] && cursor[1])
            shared.StateFlags=1u<<index;
        uint8_t expanded=0;
        if (!sizeByte || !ChatRead(sizeByte,&expanded,1) || expanded<=2) return;
        shared.StateFlags=CHAT_EXPANDED | CHAT_NATIVE_BROWSE; // unknown/full-history interactions stay native
        if (!ExpandedSupported()) return;
        void* owner=nullptr; void* child=nullptr;
        const bool full=Full(owner,child) && Named(child,"menu    fulllog ");
        // Opening or closing: the full log is not yet (or no longer) what the game's focus is on, which
        // is still a log window or nothing. No history is being browsed, so the addon keeps drawing.
        if (!full) {
            if (!active || index==0 || index==1) shared.StateFlags=CHAT_EXPANDED;
            return;
        }
        int32_t cursorScroll[2]={},filterPage[2]={};
        if (!ChatRead(static_cast<uint8_t*>(owner)+0x1c,cursorScroll,8)
            || !ChatRead(static_cast<uint8_t*>(owner)+0x54,filterPage,8)
            || cursorScroll[0]<1 || cursorScroll[1]<0 || cursorScroll[1]>1048576
            || filterPage[0]<0 || filterPage[0]>15 || filterPage[1]<1 || filterPage[1]>4096 || cursorScroll[0]>filterPage[1]) return;
        shared.FullCursor=cursorScroll[0]; shared.FullScroll=cursorScroll[1];
        shared.FullFilter=filterPage[0]; shared.FullPageRows=filterPage[1];
        // Every page stays native-controlled. The optional replacement skins the frame (and, asked, stands
        // its own controls and text where the game's are); the client's rows, cursor and actions are its own.
        // A menu open over the live full log (a row's actions, the input line) is noted: the log, still
        // drawn under it, keeps its skin, and the menu is the game's. Focus still on a log window is the
        // log opening, not a menu.
        shared.StateFlags=CHAT_EXPANDED | (active && active!=child && index!=0 && index!=1 ? CHAT_NESTED_MENU : 0);
    }
    int Identify(void* window) const {
        if (!window) return -1;
        // Input remains the game's editor: only replace this menu's GPU submissions.
        void* active=nullptr; uint8_t* inputHeader=nullptr; char inputName[16];
        if (window && activeMenu && ChatRead(activeMenu,&active,4) && active==window
            && ChatRead(static_cast<uint8_t*>(window)+4,&inputHeader,4) && inputHeader
            && ChatRead(inputHeader+0x46,inputName,16)
            && !memcmp(inputName,"menu    inline",14)
            && (inputName[14]==0 || inputName[14]==' ') && (inputName[15]==0 || inputName[15]==' ')) return 2;
        void* owner=nullptr; void* full=nullptr;
        if (ExpandedSupported() && Full(owner,full) && window==full && Named(window,"menu    fulllog ")) return 3;
        // Re-follow each slot every draw: chatdiag saw null/recreated children during zoning,
        // expand/collapse and split changes. Never cache live window/menu addresses.
        for (unsigned i=0;i<2;i++) {
            uint8_t* owner=nullptr; void* child=nullptr; uint8_t* header=nullptr; char name[16];
            if (!slots[i] || !ChatRead(slots[i],&owner,4) || !owner
                || !ChatRead(owner+8,&child,4) || child!=window
                || !ChatRead(static_cast<uint8_t*>(window)+4,&header,4) || !header
                || !ChatRead(header+0x46,name,sizeof(name))) continue;
            if (!memcmp(name,"menu    logwindo",16) || (i==1 && !memcmp(name,"menu    logwin2 ",16))) return static_cast<int>(i);
        }
        return -1;
    }
};
