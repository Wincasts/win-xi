// The keys an addon keeps from the game's chat editor (window/keys.h): a held key's press kept whole, its character
// and release with it, everything else the game's.
#include <stdio.h>
#include <string.h>
#include <initializer_list>
#include "../src/modules/window/keys.h"
static int failures=0;
static void Check(bool ok,const char* text) { printf("%s %s\n",ok?"ok":"FAIL",text); if(!ok) ++failures; }
static MSG Message(UINT kind,WPARAM wParam,uint32_t scan,bool extended=false,bool repeat=false,bool up=false) {
    MSG m={}; m.message=kind; m.wParam=wParam;
    m.lParam=LPARAM(1u | (scan<<16) | (extended ? 1u<<24 : 0) | (repeat || up ? 1u<<30 : 0) | (up ? 1u<<31 : 0));
    return m;
}
static void Hold(KeysShared& s,std::initializer_list<uint32_t> keys) {
    memset(s.Hold,0,sizeof(s.Hold));
    for (uint32_t vk : keys) s.Hold[vk>>5]|=1u<<(vk&31);
    s.HoldFrame=s.Frame;
}
int main() {
    static KeysShared block={ "UIHOOK-KEYS", 1, sizeof(KeysShared), 100, 1, {}, 0, 0 };
    GameKeys keys; keys.shared=&block;
    const UINT D=WM_KEYDOWN,U=WM_KEYUP,C=WM_CHAR;
    Check(keys.Pass(Message(D,VK_RETURN,0x1c)) && keys.Pass(Message(C,'\r',0x1c)) && keys.Pass(Message(U,VK_RETURN,0x1c,false,false,true)),
        "nothing held: Enter, its character and release the game's");
    Hold(block,{VK_RETURN,VK_TAB});
    Check(!keys.Pass(Message(D,VK_RETURN,0x1c)),"Enter held: its press kept");
    Hold(block,{VK_TAB}); // the picker closes on the press: Enter no longer held
    Check(!keys.Pass(Message(C,'\r',0x1c)),"its character kept though Enter is held no longer: the line is not sent");
    Check(!keys.Pass(Message(D,VK_RETURN,0x1c,false,true)) && !keys.Pass(Message(C,'\r',0x1c,false,true)),"its repeats and theirs kept until it is let go");
    Check(!keys.Pass(Message(U,VK_RETURN,0x1c,false,false,true)),"its release kept");
    Check(keys.Pass(Message(D,VK_RETURN,0x1c)) && keys.Pass(Message(C,'\r',0x1c)),"the next press, not held, the game's: the line is sent");
    keys.Pass(Message(U,VK_RETURN,0x1c,false,false,true));
    Check(!keys.Pass(Message(D,VK_TAB,0x0f)) && !keys.Pass(Message(C,'\t',0x0f)),"Tab held: press and character kept, the game's menu not opened");
    Check(keys.Pass(Message(D,'A',0x1e)) && keys.Pass(Message(C,'a',0x1e)),"a letter typed meanwhile the game's");
    Check(!keys.Pass(Message(U,VK_TAB,0x0f,false,false,true)),"Tab's release kept");
    // Up's scan code is numpad 8's with the extended bit: Up taken keeps nothing of numpad 8's '8'
    Hold(block,{VK_UP});
    Check(!keys.Pass(Message(D,VK_UP,0x48,true)) && !keys.Pass(Message(U,VK_UP,0x48,true,false,true)),"Up held: kept");
    Check(keys.Pass(Message(D,VK_NUMPAD8,0x48)) && keys.Pass(Message(C,'8',0x48)),"numpad 8's press and character the game's");
    // a release lost (the window losing focus): the next fresh press is judged afresh
    Hold(block,{VK_ESCAPE});
    Check(!keys.Pass(Message(D,VK_ESCAPE,0x01)),"Escape held: kept");
    memset(block.Hold,0,sizeof(block.Hold));
    Check(keys.Pass(Message(D,VK_ESCAPE,0x01)) && keys.Pass(Message(C,0x1b,0x01)),"its release never seen, its next fresh press the game's, character and all");
    // the addon gone quiet: past KEYS_HOLD_FRAMES its keys are the game's again
    Hold(block,{VK_RETURN});
    block.Frame+=KEYS_HOLD_FRAMES;
    Check(!keys.Pass(Message(D,VK_RETURN,0x1c)),"still held KEYS_HOLD_FRAMES after the commit");
    keys.Pass(Message(C,'\r',0x1c)); keys.Pass(Message(U,VK_RETURN,0x1c,false,false,true));
    block.Frame+=1;
    Check(keys.Pass(Message(D,VK_RETURN,0x1c)) && keys.Pass(Message(C,'\r',0x1c)),"one frame more: the game's");
    keys.Pass(Message(U,VK_RETURN,0x1c,false,false,true));
    Hold(block,{VK_RETURN}); block.Supported=0;
    Check(keys.Pass(Message(D,VK_RETURN,0x1c)),"the handler not taken (Supported clear): nothing kept");
    block.Supported=1; block.HoldFrame=0;
    Check(keys.Pass(Message(D,VK_RETURN,0x1c)),"never committed: nothing kept");
    Check(keys.Pass(Message(WM_MOUSEMOVE,0,0)),"other messages untouched");
    Check(block.Kept==14,"each kept message counted");
    printf("%d failures\n",failures);
    return failures ? 1 : 0;
}
