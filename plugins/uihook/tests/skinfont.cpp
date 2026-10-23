#include <stdio.h>
#include <windows.h>
#include "../src/modules/native/skinfont.h"
static int failures=0;
static void Check(bool ok,const char* text) { printf("%s %s\n",ok?"ok":"FAIL",text); if(!ok) ++failures; }
int main(int argc,char** argv) {
    SkinFonts fonts;
    const unsigned bad=fonts.Parse("# a comment\r\nfont 30CDD9D4 kind=menu fill=FFFFFFFF edge=2 edgecolour=96081008 widen=0.85\r\n"
        "clear 30CDD9D4 0 131 16 155\r\nglyph 30CDD9D4 line 2 14 0 16 131 155 150 17 E /\r\n"
        "glyph 30CDD9D4 line 18 34 16 37 131 155 150 17 E 0\r\n"
        "font 5218C635 kind=title fill=88C0B8D0 edge=0 edgecolour=00000000 widen=0\r\n"
        "glyph 5218C635 fit 198 223 0 256 213 223 0 0 - GEO\r\nglyph 5218C635 fit 1 2 0 256 213 223 0 0 - \xc3\xa4\r\nnonsense line\r\n");
    Check(bad==1,"the lines not understood counted");
    Check(fonts.styles.size()==2 && fonts.styles[0].kind=="menu" && fonts.styles[0].edge==2 && fonts.styles[0].edgeColour==0x96081008 && fonts.styles[1].fill==0x88C0B8D0,"each font's style");
    Check(fonts.clears.size()==1 && fonts.clears[0].x1==16,"its clears");
    Check(fonts.glyphs.size()==4 && !fonts.glyphs[0].fit && fonts.glyphs[0].text==L"/" && fonts.glyphs[0].baseline==150 && fonts.glyphs[0].ref==L'E',"a glyph on a baseline");
    Check(fonts.glyphs[2].fit && fonts.glyphs[2].text==L"GEO" && fonts.glyphs[3].text==L"ä","a word fitted, and one not of ASCII");

    SkinCoverage c; c.width=4; c.height=2; c.v={0,255,255,0, 0,255,255,0};
    SkinCoverage half=SkinResample(c,2,1);
    Check(half.width==2 && half.v[0]==128 && half.v[1]==128,"coverage resampled by area");
    uint32_t px=0; SkinOver(px,0xFFFFFFFF,255); Check(px==0xFFFFFFFF,"a solid colour over clear");
    px=0xFF000000; SkinOver(px,0xFFFFFFFF,128); Check(((px>>16)&255)>=126 && ((px>>16)&255)<=130 && (px>>24)==255,"half over black: grey, solid");

    // a font file drawn, where one is given (the game's prefix's Trebuchet)
    const char* file=argc>1 ? argv[1] : nullptr;
    if (!file) { printf("skipped: no font file given\n"); }
    else {
        SkinFontFace face;
        Check(face.Open(file) && face.family==L"Trebuchet MS" && !face.bold && !face.italic,"a font file opened by its family");
        SkinCoverage e; int base=0,box[4];
        Check(face.Draw(L"E",100,e,base) && SkinInk(e,box) && box[3]-box[1]>50 && box[3]<=base+1,"drawn: ink on its baseline");
        std::vector<uint32_t> argb(256*256,0xFF102030);
        SkinFontDrawer drawer; drawer.face=&face;
        const unsigned drawn=drawer.Draw(fonts,0x30CDD9D4,1,argb,256,256);
        int lit=0,cleared=0;
        for (int y=131;y<155;y++) for (int x=0;x<16;x++) { const uint32_t p=argb[size_t(y)*256+x]; if (p==0) cleared++; if ((p>>24) && ((p>>16)&255)>200) lit++; }
        Check(drawn==2 && cleared>0 && lit>5,"the menu font's glyphs drawn in their cells, the rest cleared");
        int capTop=999,capBottom=-1;
        for (int y=131;y<155;y++) for (int x=18;x<34;x++) { const uint32_t p=argb[size_t(y)*256+x]; if ((p>>24)>128 && ((p>>16)&255)>200) { capTop=(std::min)(capTop,y); capBottom=(std::max)(capBottom,y); } }
        Check(capBottom>=148 && capBottom<=151 && capBottom-capTop>=14 && capBottom-capTop<=19,"the 0 on the baseline, about as tall as the game's");
        std::vector<uint32_t> big(512*512,0);
        Check(drawer.Draw(fonts,0x30CDD9D4,2,big,512,512)==2,"and at twice the size");
    }
    printf("skinfont: %d failures\n",failures);
    return failures ? 1 : 0;
}
