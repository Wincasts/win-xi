// Every line of text the game is given for its chat log, as it stands after every plugin and addon before
// uihook has had its say: Ashita hands each plugin HandleIncomingText in its load order, and the Addons plugin runs
// the Lua addons inside its own turn, so a uihook loaded after it sees each line as the game will keep it. An addon
// whose own text_in handler runs before a formatter's (chatbox loaded before SimpleLog, say) reads the line here
// instead, and the load order no longer matters to it. Recognition of nothing: Ashita gives the text; nothing is
// read from the game or written to it, and no line is changed or blocked.
#pragma once
#include <stdint.h>
#include <string.h>

// The independent text ABI 1, magic UIHOOK-TEXT: a ring of the newest TEXT_TAP_EVENTS lines, each the bytes the game
// was given and the bytes it will keep, at most TEXT_TAP_LINE_BYTES of each (Ashita's own buffer is 4096). Serial
// counts the lines recorded since uihook loaded; the line with serial s is at Events[(s - 1) % TEXT_TAP_EVENTS], so
// a reader that remembers the last serial it read takes the ones after, up to a ring's worth.
#define TEXT_TAP_EVENTS 64
#define TEXT_TAP_LINE_BYTES 4096
#define TEXT_TAP_INJECTED 1  // from an addon, a plugin or Ashita itself, not the game
#define TEXT_TAP_BLOCKED 2   // a plugin or addon has kept it from the game's log
#define TEXT_TAP_INDENT 4    // the game indents it (as left after every change)
#define TEXT_TAP_MODIFIED 8  // the bytes the game will keep differ from the ones it was given
#define TEXT_TAP_CUT 16      // longer than TEXT_TAP_LINE_BYTES: the rest left out
struct TextTapEvent {
    uint32_t Serial, Mode, FinalMode, Flags, OriginalLength, FinalLength;
    char Original[TEXT_TAP_LINE_BYTES]; // as the game was given it (CP932 with its 1E/1F colour codes)
    char Final[TEXT_TAP_LINE_BYTES];    // as the game will keep it, after every change before uihook's turn
};
struct TextTapShared {
    char Magic[16];
    uint32_t Version, Size, Frame, Serial;
    TextTapEvent Events[TEXT_TAP_EVENTS];
};
static_assert(sizeof(TextTapEvent)==24+2*TEXT_TAP_LINE_BYTES,"text ABI 1 event");
static_assert(sizeof(TextTapShared)==16+4*4+TEXT_TAP_EVENTS*sizeof(TextTapEvent),"text ABI 1");

// One line recorded, as Ashita hands it to a plugin: the modified message stands for the final text only where a
// plugin or addon wrote one (Ashita's buffer is empty otherwise), the modified mode where Ashita gives one.
static void ChatTapRecord(TextTapShared& tap,int32_t mode,bool indent,const char* message,const int32_t* modifiedMode,
    const bool* modifiedIndent,const char* modifiedMessage,bool injected,bool blocked) {
    const char* original=message?message:"";
    const char* final_=(modifiedMessage && modifiedMessage[0])?modifiedMessage:original;
    const bool indented=modifiedIndent?*modifiedIndent:indent;
    TextTapEvent& e=tap.Events[tap.Serial%TEXT_TAP_EVENTS];
    e.Serial=0; // not this line's until it is whole: a reader between sees an old serial, not a half-written line
    e.Mode=uint32_t(mode);
    e.FinalMode=uint32_t(modifiedMode?*modifiedMode:mode);
    size_t originalLength=strlen(original),finalLength=strlen(final_);
    uint32_t flags=(injected?TEXT_TAP_INJECTED:0)|(blocked?TEXT_TAP_BLOCKED:0)|(indented?TEXT_TAP_INDENT:0);
    if (final_!=original && (finalLength!=originalLength || memcmp(final_,original,originalLength)!=0)) flags|=TEXT_TAP_MODIFIED;
    if (originalLength>TEXT_TAP_LINE_BYTES) { originalLength=TEXT_TAP_LINE_BYTES; flags|=TEXT_TAP_CUT; }
    if (finalLength>TEXT_TAP_LINE_BYTES) { finalLength=TEXT_TAP_LINE_BYTES; flags|=TEXT_TAP_CUT; }
    memcpy(e.Original,original,originalLength);
    memcpy(e.Final,final_,finalLength);
    e.OriginalLength=uint32_t(originalLength);
    e.FinalLength=uint32_t(finalLength);
    e.Flags=flags;
    tap.Serial++;
    e.Serial=tap.Serial;
}
