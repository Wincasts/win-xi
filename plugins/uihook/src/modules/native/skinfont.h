// A skin's fonts drawn by uihook from a font chosen in game: the skin's fonts.txt (made by tools/uihook_skin.py) says
// where each glyph of the game's two font textures goes (the menu font, 30CDD9D4, and the title font, 5218C635), and
// each is drawn there again, at each size of the skin's picture, in the font file chosen (/uihook skin font), by
// Windows' own font drawing. The skin's own pictures stand where no font is chosen, or one cannot be drawn.
//
// fonts.txt, a line each, in the game's texels (a size's are times its factor):
//   font <hash> kind=<menu|title> fill=<AARRGGBB> edge=<texels> edgecolour=<AARRGGBB> [shadow=<AARRGGBB> shadowx=<texels>
//       shadowy=<texels>] widen=<share>       the style of the clears and glyphs after it (one texture may hold several
//                                             fonts: 30CDD9D4 the menus' small one and a large one)
//   clear <hash> <x0> <y0> <x1> <y1>          cleared before the glyphs are drawn
//   glyph <hash> line <a> <b> <cx0> <cx1> <top> <bottom> <baseline> <height> <ref> <text>
//       on baseline, at the size whose ref is height tall, centred on a..b and no wider than it less the edges
//       (widened to widen of that), drawn only within cx0..cx1, top..bottom
//   glyph <hash> fit <a> <b> <cx0> <cx1> <top> <bottom> 0 0 - <text>
//       its ink fitted to a..b, top..bottom: as tall, no wider
#pragma once
#include <windows.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <string>
#include <vector>
#include <cmath>
#include <algorithm>

struct SkinFontStyle { uint32_t hash=0; std::string kind; uint32_t fill=0xffffffff, edgeColour=0, shadow=0; float edge=0, widen=0, shadowX=0, shadowY=0; };
struct SkinClear { uint32_t hash=0; size_t style=0; float x0=0, y0=0, x1=0, y1=0; };
struct SkinGlyph { uint32_t hash=0; size_t style=0; bool fit=false; float a=0, b=0, cx0=0, cx1=0, top=0, bottom=0, baseline=0, height=0; wchar_t ref=L'E'; std::wstring text; };

static std::wstring SkinWide(const char* text,int length=-1) {
    const int n=MultiByteToWideChar(CP_UTF8,0,text,length,nullptr,0);
    std::wstring out(n>0 ? size_t(n) : 0,L'\0');
    if (n>0) MultiByteToWideChar(CP_UTF8,0,text,length,&out[0],n);
    while (!out.empty() && out.back()==L'\0') out.pop_back();
    return out;
}

struct SkinFonts {
    std::vector<SkinFontStyle> styles;
    std::vector<SkinClear> clears;
    std::vector<SkinGlyph> glyphs;
    bool Has(uint32_t hash) const { for (auto& s:styles) if (s.hash==hash) return true; return false; }
    void Clear() { styles.clear(); clears.clear(); glyphs.clear(); }
    // fonts.txt read: the lines not understood
    unsigned Parse(const char* text) {
        Clear();
        unsigned bad=0;
        while (text && *text) {
            const char* end=strchr(text,'\n'); const size_t length=end ? size_t(end-text) : strlen(text);
            std::string line(text,length); text=end ? end+1 : nullptr;
            while (!line.empty() && (line.back()=='\r' || line.back()==' ')) line.pop_back();
            if (line.empty() || line[0]=='#') continue;
            std::vector<std::string> words; size_t at=0;
            // the words before a glyph's text, its text the rest of the line
            const size_t before=!line.compare(0,6,"glyph ") ? 13 : 64;
            while (at<line.size() && words.size()<before) {
                while (at<line.size() && line[at]==' ') at++;
                if (at>=line.size()) break;
                if (words.size()+1==before) { words.push_back(line.substr(at)); break; }
                const size_t next=line.find(' ',at);
                words.push_back(line.substr(at,next==std::string::npos ? std::string::npos : next-at));
                at=next==std::string::npos ? line.size() : next;
            }
            if (words.size()<2) { bad++; continue; }
            const uint32_t hash=static_cast<uint32_t>(strtoul(words[1].c_str(),nullptr,16));
            if (words[0]=="font") {
                SkinFontStyle s; s.hash=hash;
                for (size_t i=2;i<words.size();i++) {
                    const size_t eq=words[i].find('=');
                    if (eq==std::string::npos) continue;
                    const std::string key=words[i].substr(0,eq),value=words[i].substr(eq+1);
                    if (key=="kind") s.kind=value;
                    else if (key=="fill") s.fill=static_cast<uint32_t>(strtoul(value.c_str(),nullptr,16));
                    else if (key=="edgecolour") s.edgeColour=static_cast<uint32_t>(strtoul(value.c_str(),nullptr,16));
                    else if (key=="edge") s.edge=float(atof(value.c_str()));
                    else if (key=="widen") s.widen=float(atof(value.c_str()));
                    else if (key=="shadow") s.shadow=static_cast<uint32_t>(strtoul(value.c_str(),nullptr,16));
                    else if (key=="shadowx") s.shadowX=float(atof(value.c_str()));
                    else if (key=="shadowy") s.shadowY=float(atof(value.c_str()));
                }
                if (s.kind.empty()) { bad++; continue; }
                styles.push_back(s);
            } else if (styles.empty()) { bad++; continue;   // a clear or a glyph before any style
            } else if (words[0]=="clear" && words.size()==6) {
                SkinClear c; c.hash=hash; c.style=styles.size()-1;
                c.x0=float(atof(words[2].c_str())); c.y0=float(atof(words[3].c_str())); c.x1=float(atof(words[4].c_str())); c.y1=float(atof(words[5].c_str()));
                clears.push_back(c);
            } else if (words[0]=="glyph" && words.size()==13 && (words[2]=="line" || words[2]=="fit")) {
                SkinGlyph g; g.hash=hash; g.style=styles.size()-1; g.fit=words[2]=="fit";
                float* v[8]={&g.a,&g.b,&g.cx0,&g.cx1,&g.top,&g.bottom,&g.baseline,&g.height};
                for (int i=0;i<8;i++) *v[i]=float(atof(words[3+i].c_str()));
                const std::wstring ref=SkinWide(words[11].c_str());
                g.ref=ref.empty() || ref==L"-" ? L'E' : ref[0];
                g.text=SkinWide(words[12].c_str());
                if (g.text.empty()) { bad++; continue; }
                glyphs.push_back(g);
            } else bad++;
        }
        return bad;
    }
};

// A font file's family and style names, from its name table (the Windows names, English where there are several)
static bool SkinFontNames(const std::vector<uint8_t>& f,std::wstring& family,std::wstring& style) {
    auto u16=[&](size_t at) { return at+2<=f.size() ? uint32_t(f[at])<<8 | f[at+1] : 0u; };
    auto u32=[&](size_t at) { return at+4<=f.size() ? u16(at)<<16 | u16(at+2) : 0u; };
    if (f.size()<12) return false;
    const uint32_t tables=u16(4);
    size_t name=0;
    for (uint32_t i=0;i<tables;i++) {
        const size_t r=12+size_t(i)*16;
        if (r+16>f.size()) return false;
        if (!memcmp(&f[r],"name",4)) { name=u32(r+8); break; }
    }
    if (!name) return false;
    const uint32_t count=u16(name+2),strings=u16(name+4);
    int bestFamily=-1,bestStyle=-1;
    for (uint32_t i=0;i<count;i++) {
        const size_t r=name+6+size_t(i)*12;
        const uint32_t platform=u16(r),language=u16(r+4),id=u16(r+6),length=u16(r+8),offset=u16(r+10);
        if (platform!=3 || (id!=1 && id!=2)) continue;
        const int rank=language==0x409 ? 2 : 1;
        int& best=id==1 ? bestFamily : bestStyle;
        if (rank<=best) continue;
        const size_t at=name+strings+offset;
        if (at+length>f.size()) continue;
        std::wstring text;
        for (uint32_t k=0;k+1<length;k+=2) text.push_back(wchar_t(u16(at+k)));
        (id==1 ? family : style)=text; best=rank;
    }
    return !family.empty();
}

// A coverage picture: 0..255 a texel
struct SkinCoverage { int width=0, height=0; std::vector<uint8_t> v; uint8_t At(int x,int y) const { return v[size_t(y)*width+x]; } };

// Resampled to w x h, each texel the area of the picture under it
static SkinCoverage SkinResample(const SkinCoverage& in,int w,int h) {
    SkinCoverage out; out.width=w; out.height=h; out.v.assign(size_t(w)*h,0);
    if (!in.width || !in.height || w<=0 || h<=0) return out;
    std::vector<float> rows(size_t(in.height)*w,0);
    const float sx=float(in.width)/w,sy=float(in.height)/h;
    for (int y=0;y<in.height;y++) for (int x=0;x<w;x++) {
        float x0=x*sx,x1=x0+sx,sum=0;
        if (sx<1) { const float c=(x+0.5f)*sx-0.5f; const int i=int(std::floor(c)); const float t=c-i;
            const int a=(std::max)(0,(std::min)(in.width-1,i)),b=(std::max)(0,(std::min)(in.width-1,i+1));
            rows[size_t(y)*w+x]=in.At(a,y)*(1-t)+in.At(b,y)*t; continue; }
        for (int i=int(x0);i<int(std::ceil(x1)) && i<in.width;i++) sum+=in.At(i,y)*((std::min)(x1,float(i+1))-(std::max)(x0,float(i)));
        rows[size_t(y)*w+x]=sum/sx;
    }
    for (int x=0;x<w;x++) for (int y=0;y<h;y++) {
        float v=0;
        if (sy<1) { const float c=(y+0.5f)*sy-0.5f; const int i=int(std::floor(c)); const float t=c-i;
            const int a=(std::max)(0,(std::min)(in.height-1,i)),b=(std::max)(0,(std::min)(in.height-1,i+1));
            v=rows[size_t(a)*w+x]*(1-t)+rows[size_t(b)*w+x]*t; }
        else { const float y0=y*sy,y1=y0+sy; float sum=0;
            for (int i=int(y0);i<int(std::ceil(y1)) && i<in.height;i++) sum+=rows[size_t(i)*w+x]*((std::min)(y1,float(i+1))-(std::max)(y0,float(i)));
            v=sum/sy; }
        out.v[size_t(y)*w+x]=uint8_t((std::max)(0.0f,(std::min)(255.0f,v+0.5f)));
    }
    return out;
}

// A font file opened for drawing: added to this process alone, drawn by its family and style
#define SKIN_SUPERSAMPLE 4   // a glyph drawn this many times larger and averaged down: smooth whatever the font says
class SkinFontFace {
public:
    std::wstring path, family;
    bool bold=false, italic=false, added=false;
    int weight=0;   // FW_* to draw at, or 0 for the file's own (bold or not)
    bool Open(const char* file) {
        Close();
        FILE* f=fopen(file,"rb"); if (!f) return false;
        std::vector<uint8_t> bytes; uint8_t chunk[65536]; size_t n;
        while ((n=fread(chunk,1,sizeof(chunk),f))>0 && bytes.size()<(64u<<20)) bytes.insert(bytes.end(),chunk,chunk+n);
        fclose(f);
        std::wstring style;
        if (!SkinFontNames(bytes,family,style)) return false;
        bold=style.find(L"Bold")!=std::wstring::npos;
        italic=style.find(L"Italic")!=std::wstring::npos || style.find(L"Oblique")!=std::wstring::npos;
        path=SkinWide(file);
        added=AddFontResourceExW(path.c_str(),FR_PRIVATE,nullptr)>0;
        return added;
    }
    void Close() { if (added) RemoveFontResourceExW(path.c_str(),FR_PRIVATE,nullptr); added=false; family.clear(); }
    ~SkinFontFace() { Close(); }
    // text drawn px high (the em), its coverage and its baseline's row in it; false where nothing was drawn. Drawn
    // SKIN_SUPERSAMPLE times as large and each square of texels averaged: small, a font's own hints (its gasp table)
    // turn Windows' smoothing off, and its letters came out two-toned and jagged a pixel wide
    bool Draw(const std::wstring& text,int px,SkinCoverage& out,int& baseline) const {
        if (!added || px<2 || px>2000) return false;
        SkinCoverage big; int bigBase=0;
        if (!DrawAt(text,px*SKIN_SUPERSAMPLE,big,bigBase)) return false;
        const int n=SKIN_SUPERSAMPLE;
        out.width=big.width/n; out.height=big.height/n; out.v.assign(size_t(out.width)*out.height,0);
        for (int y=0;y<out.height;y++) for (int x=0;x<out.width;x++) {
            uint32_t sum=0;
            for (int dy=0;dy<n;dy++) for (int dx=0;dx<n;dx++) sum+=big.At(x*n+dx,y*n+dy);
            out.v[size_t(y)*out.width+x]=uint8_t(sum/(n*n));
        }
        baseline=bigBase/n;
        return true;
    }
    bool DrawAt(const std::wstring& text,int px,SkinCoverage& out,int& baseline) const {
        if (px<2 || px>8000) return false;
        const int w=px*int(text.size()+2),h=px*3;
        HDC dc=CreateCompatibleDC(nullptr);
        if (!dc) return false;
        BITMAPINFO info={}; info.bmiHeader.biSize=sizeof(info.bmiHeader); info.bmiHeader.biWidth=w; info.bmiHeader.biHeight=-h;
        info.bmiHeader.biPlanes=1; info.bmiHeader.biBitCount=32; info.bmiHeader.biCompression=BI_RGB;
        void* bits=nullptr;
        HBITMAP bitmap=CreateDIBSection(dc,&info,DIB_RGB_COLORS,&bits,nullptr,0);
        HFONT font=CreateFontW(-px,0,0,0,weight ? weight : bold ? FW_BOLD : FW_NORMAL,italic,0,0,DEFAULT_CHARSET,OUT_TT_ONLY_PRECIS,CLIP_DEFAULT_PRECIS,
            ANTIALIASED_QUALITY,DEFAULT_PITCH,family.c_str());
        bool ok=false;
        if (bitmap && font && bits) {
            HGDIOBJ oldBitmap=SelectObject(dc,bitmap),oldFont=SelectObject(dc,font);
            memset(bits,0,size_t(w)*h*4);
            SetBkMode(dc,TRANSPARENT); SetTextColor(dc,RGB(255,255,255)); SetTextAlign(dc,TA_BASELINE | TA_LEFT);
            baseline=px*2;
            ok=TextOutW(dc,px,baseline,text.c_str(),int(text.size()))!=0;
            GdiFlush();
            out.width=w; out.height=h; out.v.resize(size_t(w)*h);
            const auto* p=static_cast<const uint8_t*>(bits);
            for (size_t i=0;i<out.v.size();i++) out.v[i]=(std::max)((std::max)(p[i*4],p[i*4+1]),p[i*4+2]);
            SelectObject(dc,oldFont); SelectObject(dc,oldBitmap);
        }
        if (font) DeleteObject(font);
        if (bitmap) DeleteObject(bitmap);
        DeleteDC(dc);
        return ok;
    }
};

// A coverage picture's ink: x0, y0, x1, y1; false where there is none
static bool SkinInk(const SkinCoverage& c,int* box) {
    box[0]=c.width; box[1]=c.height; box[2]=-1; box[3]=-1;
    for (int y=0;y<c.height;y++) for (int x=0;x<c.width;x++) if (c.At(x,y)>8) {
        box[0]=(std::min)(box[0],x); box[1]=(std::min)(box[1],y); box[2]=(std::max)(box[2],x+1); box[3]=(std::max)(box[3],y+1);
    }
    return box[2]>box[0];
}
static SkinCoverage SkinCrop(const SkinCoverage& c,const int* box) {
    SkinCoverage out; out.width=box[2]-box[0]; out.height=box[3]-box[1]; out.v.resize(size_t(out.width)*out.height);
    for (int y=0;y<out.height;y++) memcpy(&out.v[size_t(y)*out.width],&c.v[size_t(y+box[1])*c.width+box[0]],size_t(out.width));
    return out;
}
// One straight-alpha colour laid over a texel by coverage
static void SkinOver(uint32_t& dst,uint32_t colour,uint32_t coverage) {
    const uint32_t sa=((colour>>24)*coverage+127)/255;
    if (!sa) return;
    const uint32_t da=dst>>24,oa=sa+da*(255-sa)/255;
    if (!oa) { dst=0; return; }
    uint32_t out=oa<<24;
    for (int s=0;s<24;s+=8) {
        const uint32_t sc=(colour>>s)&255,dc=(dst>>s)&255;
        out|=((sc*sa+dc*da*(255-sa)/255)/oa)<<s;
    }
    dst=out;
}

// The kinds of a skin's fonts a font may be chosen for
static int SkinFontKind(const std::string& kind) { return kind=="menu" ? 0 : kind=="title" ? 1 : -1; }

// A skin's font texture of one size (factor times the game's) drawn again: for each font in it with a face chosen
// for its kind, its clears made and each glyph drawn in the face
class SkinFontDrawer {
public:
    const SkinFontFace* faces[2]={};
    // a font chosen drawn in winxi's look in place of the game's: its fill, an outline of outline pixels in
    // outlineColour about it (as winxi.text draws words over the game), no shadow. The outline's texels are a
    // pixel's: the game's own edge's (1 for the small font, drawn a texel to a pixel; 2 for the large, drawn at half)
    int outline[2]={1,1};
    uint32_t outlineColour[2]={0xE6000000,0xE6000000};
    // the em, in pixels, whose ref is height pixels tall in a face; kept for each the same asked
    struct Size { const SkinFontFace* face; wchar_t ref; int height; int px; };
    std::vector<Size> sizes;
    int SizeFor(const SkinFontFace* face,wchar_t ref,int height) {
        for (auto& s:sizes) if (s.face==face && s.ref==ref && s.height==height) return s.px;
        int px=0;
        SkinCoverage c; int base=0,box[4];
        const std::wstring one(1,ref);
        if (face->Draw(one,100,c,base) && SkinInk(c,box) && box[3]>box[1]) {
            px=(std::max)(2,int(std::ceil(100.0f*height/float(box[3]-box[1]))));
            // as near as can be: the measured height no less than asked, at the least em
            for (int tries=0;tries<6;tries++) {
                if (!face->Draw(one,px,c,base) || !SkinInk(c,box)) break;
                const int got=box[3]-box[1];
                if (got<height) px++; else if (px>2 && face->Draw(one,px-1,c,base) && SkinInk(c,box) && box[3]-box[1]>=height) px--; else break;
            }
        }
        sizes.push_back({face,ref,height,px});
        return px;
    }
    const SkinFontFace* FaceOf(const SkinFonts& fonts,size_t style) const {
        if (style>=fonts.styles.size()) return nullptr;
        const int k=SkinFontKind(fonts.styles[style].kind);
        return k>=0 && faces[k] && faces[k]->added ? faces[k] : nullptr;
    }
    unsigned Draw(const SkinFonts& fonts,uint32_t hash,float factor,std::vector<uint32_t>& argb,int width,int height) {
        auto at=[&](float v) { return int(std::floor(v*factor+0.5f)); };
        for (auto& c:fonts.clears) if (c.hash==hash && FaceOf(fonts,c.style))
            for (int y=(std::max)(0,at(c.y0));y<(std::min)(height,at(c.y1));y++)
                for (int x=(std::max)(0,at(c.x0));x<(std::min)(width,at(c.x1));x++) argb[size_t(y)*width+x]=0;
        unsigned drawn=0;
        for (auto& g:fonts.glyphs) {
            const SkinFontFace* face=g.hash==hash ? FaceOf(fonts,g.style) : nullptr;
            if (!face) continue;
            SkinFontStyle style=fonts.styles[g.style];
            const int k=SkinFontKind(style.kind);
            // winxi's look: the outline a pixel (as many texels as the game's own edge is), no shadow
            const int edge=outline[k]>0 ? int(std::lround((std::max)(1.0f,style.edge)*outline[k])) : 0;
            style.edgeColour=outlineColour[k]; style.shadow=0;
            const int sx=0,sy=0;
            SkinCoverage c; int base=0,box[4];
            int px=g.fit ? (std::max)(4,int((g.bottom-g.top)*(std::max)(1.0f,factor)*2)) : SizeFor(face,g.ref,(std::max)(1,at(g.height)));
            if (px<2 || !face->Draw(g.text,px,c,base) || !SkinInk(c,box)) continue;
            SkinCoverage ink=SkinCrop(c,box);
            int gx,gy;
            if (g.fit) {
                const int bx0=at(g.a),by0=at(g.top),bx1=at(g.b),by1=at(g.bottom);
                const int h=(std::max)(1,by1-by0);
                const int w=(std::max)(1,(std::min)(bx1-bx0,int(std::lround(float(ink.width)*h/ink.height))));
                ink=SkinResample(ink,w,h);
                gx=(bx0+bx1)/2-w/2; gy=by0;
            } else {
                const int above=base-box[1];
                const int room=at(g.b)-at(g.a)-2*edge;
                const int want=(std::min)(room,(std::max)(ink.width,int(room*style.widen)));
                if (want>0 && want!=ink.width) ink=SkinResample(ink,want,ink.height);
                gx=at((g.a+g.b)/2)-ink.width/2; gy=at(g.baseline)-above;
                if (gy<0) gy=0;
            }
            // the edge (the ink spread by edge each way), the shadow (the ink moved), then the fill, within the glyph's bounds
            const int cx0=(std::max)(0,at(g.cx0)),cx1=(std::min)(width,at(g.cx1)),cy0=(std::max)(0,at(g.top)),cy1=(std::min)(height,at(g.bottom));
            const int reach=edge+(std::max)(sx,sy);
            for (int pass=0;pass<3;pass++) {
                if ((pass==0 && !edge) || (pass==1 && !style.shadow)) continue;
                const uint32_t colour=pass==0 ? style.edgeColour : pass==1 ? style.shadow : style.fill;
                for (int y=-reach;y<ink.height+reach;y++) for (int x=-reach;x<ink.width+reach;x++) {
                    const int tx=gx+x,ty=gy+y;
                    if (tx<cx0 || tx>=cx1 || ty<cy0 || ty>=cy1) continue;
                    uint32_t v=0;
                    if (pass==0) {
                        // outside the letter alone: under a fill less than solid (the small font's, as the game's)
                        // it showed through, and the letters came out grey
                        for (int dy=-edge;dy<=edge;dy++) for (int dx=-edge;dx<=edge;dx++) {
                            const int ex=x+dx,ey=y+dy;
                            if (ex>=0 && ey>=0 && ex<ink.width && ey<ink.height) v=(std::max)(v,uint32_t(ink.At(ex,ey)));
                        }
                        const uint32_t own=x>=0 && y>=0 && x<ink.width && y<ink.height ? ink.At(x,y) : 0;
                        v=v*(255-own)/255;
                    } else {
                        const int ex=pass==1 ? x-sx : x,ey=pass==1 ? y-sy : y;
                        if (ex>=0 && ey>=0 && ex<ink.width && ey<ink.height) v=ink.At(ex,ey);
                    }
                    if (v) SkinOver(argb[size_t(ty)*width+tx],colour,v);
                }
            }
            drawn++;
        }
        return drawn;
    }
};
